//! Stage 1（criteria）で書いた受け入れテスト。**フィーチャコードは含まない。**
//! ACCEPTANCE.md の機械判定項目 A / B / D / H の純粋関数部分を赤（RED）で符号化する。
//!
//! ここは現在コンパイルできない（下記の純粋関数がまだ main.zig に無いため）。それが
//! 意図した RED である。build 段階が SPEC 5.4 に従い、状態選択・集約・口形決定・端末
//! フォーカスの判断を純粋関数として main.zig に切り出した時点で、コンパイルが通り緑になる。
//!
//! build 段階が満たすべき契約（main.zig に pub で公開する宣言）:
//!
//!   pub const Velocity = struct { x: f64, y: f64 };
//!   pub const Pid = i32;
//!   pub const Status = enum { busy, idle, waiting, unknown };
//!   pub const Session = struct { status: Status = .unknown, pid: Pid = 0, ... };
//!       // name / cwd / waiting_for 等は build が固定長バッファで持ってよい。
//!       // aggregate / focusTarget のテストは status / pid だけを設定して構築するので、
//!       // 残りのフィールドは既定値を持つこと（`Session{ .status = .busy }` が通る）。
//!
//!   pub fn dragState(vel: ?Velocity, primary_down: bool) ?State   // A1-A3
//!   pub fn enterThrow(vel: Velocity) bool                         // A4（現状の投擲判定の抽出）
//!   pub fn throwEnded(elapsed_ms: u32, speed: f64) bool           // A5
//!   pub const post_throw_state: State                             // A5（= .waving）
//!
//!   pub fn aggregate(sessions: []const Session) State             // B1-B6
//!   pub fn parseSession(json: []const u8) ?Session               // B6/B7（必須キー欠落で null）
//!
//!   pub fn mouthFrame(rms: f32) u8                                // D4-D8
//!   pub const mouth_shape_count: u8                               // = 3（design_brief 2項: 閉/半/開）
//!   pub fn mouthFrameMotion(rms: f32, reduce_motion: bool) u8     // D11
//!   pub fn rmsAt(env: []const f32, i: usize) f32                  // D10（範囲外は 0）
//!
//!   pub fn focusTarget(sessions: []const Session) ?Pid           // H1/H2
//!   pub fn parseTty(ps_out: []const u8) ?[]const u8              // H6/H8（tty 無しは null）
//!
//! 各テスト名の先頭に対応する ACCEPTANCE 番号を付す。criterion -> test の対応表は
//! docs/criteria-notes.md にある。

const std = @import("std");
const main = @import("main.zig");

const State = main.State;
const Session = main.Session;
const Velocity = main.Velocity;
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;

// ============================================================ A. つまみ保持
// SPEC 3.1 / ACCEPTANCE A。押下中は速度に依存せず単一のつまみ状態を保持する。

test "A1 dragState: 押下中・速度(0,0) は .idle ではない" {
    const s = main.dragState(Velocity{ .x = 0, .y = 0 }, true);
    try expect(s != null);
    try expect(s.? != .idle);
}

test "A2 dragState: 押下中は速度に依らず常に同一の状態" {
    const held = main.dragState(Velocity{ .x = 0, .y = 0 }, true).?;
    const vels = [_]?Velocity{
        Velocity{ .x = 0, .y = 0 },
        Velocity{ .x = 5, .y = 0 },
        Velocity{ .x = -5, .y = 0 },
        Velocity{ .x = 500, .y = 0 },
        Velocity{ .x = -500, .y = 0 },
        null,
    };
    for (vels) |v| {
        const got = main.dragState(v, true);
        try expect(got != null);
        try expectEqual(held, got.?);
    }
}

test "A3 dragState: 押下中は .running-left を返さない（片方向のみ）" {
    const vels = [_]?Velocity{
        Velocity{ .x = -500, .y = 0 },
        Velocity{ .x = -5, .y = 0 },
        Velocity{ .x = 0, .y = 0 },
        null,
    };
    for (vels) |v| {
        try expect(main.dragState(v, true).? != .@"running-left");
    }
}

test "A4 enterThrow: リリース時の投擲突入判定が現状の閾値(約1)を保つ" {
    // 現状の main.zig:1457 は `|vx|<1 かつ |vy|<1` のとき投擲に入らない。
    // 注意: ACCEPTANCE A4 の括弧書き「速度 < physics_min_vel で throwing に入らない」は
    //       現行コード（閾値 1、physics_min_vel=65 ではない）と一致しない。
    //       ここでは "現状と同じ挙動を保つ" という A4 本文に忠実に符号化する。
    //       この食い違いは docs/human-gates.md に人間の確認事項として記録した。
    try expect(!main.enterThrow(Velocity{ .x = 0.5, .y = 0.5 }));
    try expect(main.enterThrow(Velocity{ .x = 5, .y = 0 }));
    try expect(main.enterThrow(Velocity{ .x = 0, .y = 5 }));
}

test "A5 throwEnded: 減速完了/最大時間で終了し、その後 .waving へ" {
    // physics_min_vel(65) 未満に落ちた、または最大時間を超えたら投擲終了。
    // 定数値そのものには依存せず、明確に上下する値で境界をまたぐ。
    try expect(main.throwEnded(0, 1.0)); //   遅い -> 終了
    try expect(!main.throwEnded(0, 1000.0)); // 速い -> 継続
    try expect(main.throwEnded(100_000, 1000.0)); // 最大時間超過 -> 終了
    try expectEqual(State.waving, main.post_throw_state);
}

// ======================================================== B. セッション集約
// SPEC 3.2 / ACCEPTANCE B。優先度 waiting > busy > idle。ペットは常に1匹。

test "B1 aggregate: 0件で .idle" {
    const empty = [_]Session{};
    try expectEqual(State.idle, main.aggregate(&empty));
}

test "B2 aggregate: waiting が1件でもあれば busy 何件でも waiting" {
    const s = [_]Session{
        .{ .status = .busy },
        .{ .status = .busy },
        .{ .status = .waiting },
        .{ .status = .busy },
    };
    try expectEqual(State.waiting, main.aggregate(&s));
}

test "B3 aggregate: waiting 無し・busy 1件以上で .running（作業中）" {
    const s = [_]Session{
        .{ .status = .idle },
        .{ .status = .busy },
        .{ .status = .idle },
    };
    try expectEqual(State.running, main.aggregate(&s));
}

test "B4 aggregate: 全件 idle で .idle" {
    const s = [_]Session{
        .{ .status = .idle },
        .{ .status = .idle },
    };
    try expectEqual(State.idle, main.aggregate(&s));
}

test "B5 aggregate: 順序非依存（シャッフルしても結果不変）" {
    const forward = [_]Session{
        .{ .status = .idle },
        .{ .status = .busy },
        .{ .status = .waiting },
        .{ .status = .unknown },
        .{ .status = .busy },
    };
    const reverse = [_]Session{
        .{ .status = .busy },
        .{ .status = .unknown },
        .{ .status = .waiting },
        .{ .status = .busy },
        .{ .status = .idle },
    };
    try expectEqual(main.aggregate(&forward), main.aggregate(&reverse));
    try expectEqual(State.waiting, main.aggregate(&forward));
}

test "B6 aggregate: 未知 status を含んでもクラッシュせず無視する" {
    const only_unknown = [_]Session{.{ .status = .unknown }};
    try expectEqual(State.idle, main.aggregate(&only_unknown));

    const unknown_and_busy = [_]Session{
        .{ .status = .unknown },
        .{ .status = .busy },
    };
    try expectEqual(State.running, main.aggregate(&unknown_and_busy));

    const unknown_and_waiting = [_]Session{
        .{ .status = .unknown },
        .{ .status = .waiting },
    };
    try expectEqual(State.waiting, main.aggregate(&unknown_and_waiting));
}

test "B6b parseSession: 未知の status 文字列は .unknown に写す" {
    const json =
        \\{"pid":1,"status":"frobnicating","cwd":"/tmp/x","name":"x-1"}
    ;
    const s = main.parseSession(json);
    try expect(s != null);
    try expectEqual(main.Status.unknown, s.?.status);
}

test "B7 parseSession: 必須キー(status/cwd/name)欠落は例外を投げず null（劣化）" {
    const missing_status =
        \\{"pid":1,"cwd":"/tmp/x","name":"x-1"}
    ;
    const missing_cwd =
        \\{"pid":1,"status":"busy","name":"x-1"}
    ;
    const missing_name =
        \\{"pid":1,"status":"busy","cwd":"/tmp/x"}
    ;
    const complete =
        \\{"pid":1,"status":"busy","cwd":"/tmp/x","name":"x-1"}
    ;
    try expect(main.parseSession(missing_status) == null);
    try expect(main.parseSession(missing_cwd) == null);
    try expect(main.parseSession(missing_name) == null);
    try expect(main.parseSession(complete) != null);
}

// ============================================================= D. 口パク
// SPEC 3.4 / ACCEPTANCE D。振幅は事前計算エンベロープから読む純粋関数。

test "D4 mouthFrame: rms 単調増加で返り値は単調非減少" {
    const seq = [_]f32{ 0.0, 0.05, 0.1, 0.2, 0.35, 0.5, 0.7, 0.85, 1.0, 2.0 };
    var prev: u8 = 0;
    for (seq) |r| {
        const f = main.mouthFrame(r);
        try expect(f >= prev);
        prev = f;
    }
}

test "D5 mouthFrame: rms==0 は閉口フレーム(0)" {
    try expectEqual(@as(u8, 0), main.mouthFrame(0.0));
}

test "D6 mouthFrame: NaN/inf/負値でも 0..口形数-1 に収まる" {
    const hi = main.mouth_shape_count - 1;
    const bad = [_]f32{
        std.math.nan(f32),
        std.math.inf(f32),
        -std.math.inf(f32),
        -1.0,
        -0.0001,
    };
    for (bad) |r| {
        const f = main.mouthFrame(r);
        try expect(f <= hi);
    }
    // NaN と負値は「無音」として閉口(0)に倒す。
    try expectEqual(@as(u8, 0), main.mouthFrame(std.math.nan(f32)));
    try expectEqual(@as(u8, 0), main.mouthFrame(-1.0));
}

test "D7 mouthFrame: 発話終了（rms が 0 に戻る）で閉口へ" {
    const tail = [_]f32{ 0.8, 0.4, 0.1, 0.0, 0.0 };
    try expectEqual(@as(u8, 0), main.mouthFrame(tail[tail.len - 1]));
}

test "D8 mouthFrame: 同じ入力列は完全に同一の口形列（決定論）" {
    const seq = [_]f32{ 0.0, 0.3, 0.9, 0.3, 0.0, 0.6 };
    var a: [seq.len]u8 = undefined;
    var b: [seq.len]u8 = undefined;
    for (seq, 0..) |r, i| a[i] = main.mouthFrame(r);
    for (seq, 0..) |r, i| b[i] = main.mouthFrame(r);
    try std.testing.expectEqualSlices(u8, &a, &b);
}

test "D10 rmsAt: エンベロープ長と再生長が不整合でも範囲外アクセスしない" {
    const env = [_]f32{ 0.2, 0.5 };
    try expectEqual(@as(f32, 0.2), main.rmsAt(&env, 0));
    try expectEqual(@as(f32, 0.5), main.rmsAt(&env, 1));
    // 範囲外は 0（= 閉口）。空エンベロープでも安全。
    try expectEqual(@as(f32, 0.0), main.rmsAt(&env, 2));
    try expectEqual(@as(f32, 0.0), main.rmsAt(&env, 99));
    const empty = [_]f32{};
    try expectEqual(@as(f32, 0.0), main.rmsAt(&empty, 0));
    // 範囲外読み取り -> mouthFrame も閉口。
    try expectEqual(@as(u8, 0), main.mouthFrame(main.rmsAt(&env, 99)));
}

test "D11 mouthFrameMotion: reduce_motion 有効時は口パクを抑制" {
    // reduce_motion が真なら、どんな振幅でも閉口で固定（アニメーションを抑制）。
    try expectEqual(@as(u8, 0), main.mouthFrameMotion(1.0, true));
    try expectEqual(@as(u8, 0), main.mouthFrameMotion(0.5, true));
    // 偽なら通常の mouthFrame と一致。
    try expectEqual(main.mouthFrame(1.0), main.mouthFrameMotion(1.0, false));
    try expectEqual(main.mouthFrame(0.3), main.mouthFrameMotion(0.3, false));
}

// ================================================ H. 吹き出しタップの対象
// SPEC 3.6 / ACCEPTANCE H。集約(B)と同一の優先度規則で対象 pid を選ぶ。

test "H1 focusTarget: 返す pid は aggregate の勝者セッションと一致（waiting 勝者）" {
    const s = [_]Session{
        .{ .status = .idle, .pid = 1 },
        .{ .status = .busy, .pid = 2 },
        .{ .status = .waiting, .pid = 3 },
        .{ .status = .busy, .pid = 4 },
    };
    try expectEqual(State.waiting, main.aggregate(&s));
    try expectEqual(@as(?main.Pid, 3), main.focusTarget(&s));
}

test "H1b focusTarget: busy 勝者のとき busy の pid を指す" {
    const s = [_]Session{
        .{ .status = .idle, .pid = 10 },
        .{ .status = .busy, .pid = 20 },
        .{ .status = .idle, .pid = 30 },
    };
    try expectEqual(State.running, main.aggregate(&s));
    try expectEqual(@as(?main.Pid, 20), main.focusTarget(&s));
}

test "H2 focusTarget: 0件で null（タップしても何も起きない）" {
    const empty = [_]Session{};
    try expect(main.focusTarget(&empty) == null);
}

test "H6/H8 parseTty: tty を持たない pid（デーモン/終了済み）は null" {
    // `ps -o tty= -p PID` は tty 無しで "?"、pid 消失で空を返す。どちらも null。
    try expect(main.parseTty("?\n") == null);
    try expect(main.parseTty("??\n") == null);
    try expect(main.parseTty("") == null);
    try expect(main.parseTty("   \n") == null);
    // 正常な tty はその名前を返す。
    const got = main.parseTty("ttys012\n");
    try expect(got != null);
    try std.testing.expectEqualStrings("ttys012", got.?);
}
