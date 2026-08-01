//! Portable file/socket/clock primitives for the off-main-thread code.
//!
//! The hook server thread, the hook runner process, and agent-hook
//! detection all need small blocking IO, and none of them can borrow
//! `init.io`: that Io belongs to the main thread and the runtime
//! thread must not touch it. The previous answer was raw `std.c`,
//! which pinned the whole app to POSIX and broke the Windows target
//! (`std.c.open`'s variadic `mode_t` is not expressible in the
//! x86_64_win calling convention).
//!
//! The answer here is the shape the SDK itself uses for exactly this
//! situation (`src/embed/host.zig`, `src/platform/macos/root.zig`):
//! a caller-owned `std.Io.Threaded`. Each thread builds its own Io, so
//! the main-thread invariant holds by construction rather than by
//! comment, and every operation below is `std.Io.Dir`/`std.Io.net`,
//! which already carry the Windows implementations.
//!
//! `std.posix` is deliberately not used: in Zig 0.16 it kept only
//! `read`/`openat` plus mmap and signal bits, and even `posix.read` is
//! `@compileError("unsupported OS")` on Windows, so it is a POSIX
//! escape hatch, not a portability layer.

const std = @import("std");
const builtin = @import("builtin");

/// One Io per calling thread. Cheap to build (no worker threads spin
/// up until an async call asks for them) and never shared, so the
/// blocking helpers below are safe from any thread.
pub const Scope = struct {
    threaded: std.Io.Threaded,

    pub fn init() Scope {
        // Allocator.failing is what the SDK passes when a scope only
        // does blocking calls: it is consulted solely by the async
        // vtable entries, which nothing here reaches.
        return .{ .threaded = std.Io.Threaded.init(std.heap.page_allocator, .{}) };
    }

    pub fn io(self: *Scope) std.Io {
        return self.threaded.io();
    }

    pub fn deinit(self: *Scope) void {
        self.threaded.deinit();
    }
};

/// Read a whole file into a caller buffer. Null on any failure or an
/// empty file, matching the std.c helpers this replaces (callers treat
/// "no bytes" and "no file" identically).
pub fn readFile(path: []const u8, buf: []u8) ?[]const u8 {
    var scope = Scope.init();
    defer scope.deinit();
    return readFileIo(scope.io(), path, buf);
}

pub fn readFileIo(io: std.Io, path: []const u8, buf: []u8) ?[]const u8 {
    var file = std.Io.Dir.cwd().openFile(io, path, .{}) catch return null;
    defer file.close(io);
    var read_buf: [4096]u8 = undefined;
    var reader = file.reader(io, &read_buf);
    var total: usize = 0;
    while (total < buf.len) {
        const n = reader.interface.readSliceShort(buf[total..]) catch break;
        if (n == 0) break;
        total += n;
    }
    if (total == 0) return null;
    return buf[0..total];
}

/// Last `buf.len` bytes of a file. Used for transcript tails, where
/// the head is uninteresting and the file can be many megabytes.
pub fn readFileTail(path: []const u8, buf: []u8) ?[]const u8 {
    var scope = Scope.init();
    defer scope.deinit();
    const io = scope.io();
    var file = std.Io.Dir.cwd().openFile(io, path, .{}) catch return null;
    defer file.close(io);
    var read_buf: [4096]u8 = undefined;
    var reader = file.reader(io, &read_buf);
    const size = reader.getSize() catch return null;
    if (size == 0) return null;
    const want: u64 = @min(size, buf.len);
    reader.seekTo(size - want) catch return null;
    var total: usize = 0;
    while (total < want) {
        const n = reader.interface.readSliceShort(buf[total..@intCast(want)]) catch break;
        if (n == 0) break;
        total += n;
    }
    if (total == 0) return null;
    return buf[0..total];
}

/// Allocate-and-read, capped at `max`. Returns a slice sized to the
/// bytes actually read so the caller's free matches the allocation.
pub fn readFileAlloc(allocator: std.mem.Allocator, path: []const u8, max: usize) ?[]u8 {
    const buf = allocator.alloc(u8, max) catch return null;
    var scope = Scope.init();
    defer scope.deinit();
    const got = readFileIo(scope.io(), path, buf) orelse {
        allocator.free(buf);
        return null;
    };
    return allocator.realloc(buf, got.len) catch buf[0..got.len];
}

pub fn writeFile(path: []const u8, bytes: []const u8) bool {
    var scope = Scope.init();
    defer scope.deinit();
    return writeFileIo(scope.io(), path, bytes, null);
}

/// `mode` is the POSIX permission bits and is honored only there; on
/// Windows the ACL inherited from the parent directory governs, which
/// is why the token file's 0600 cannot be reproduced (see hook_server).
pub fn writeFileMode(path: []const u8, bytes: []const u8, mode: u16) bool {
    var scope = Scope.init();
    defer scope.deinit();
    return writeFileIo(scope.io(), path, bytes, mode);
}

fn writeFileIo(io: std.Io, path: []const u8, bytes: []const u8, mode: ?u16) bool {
    var file = std.Io.Dir.cwd().createFile(io, path, .{
        .truncate = true,
        .permissions = permissionsFromMode(mode),
    }) catch return false;
    defer file.close(io);
    var write_buf: [4096]u8 = undefined;
    var writer = file.writer(io, &write_buf);
    writer.interface.writeAll(bytes) catch return false;
    writer.interface.flush() catch return false;
    return true;
}

/// On Windows `Permissions` is a readonly-attribute enum with no mode
/// bits, so a requested POSIX mode degrades to the inherited ACL.
fn permissionsFromMode(mode: ?u16) std.Io.File.Permissions {
    const m = mode orelse return .default_file;
    if (builtin.os.tag == .windows) return .default_file;
    return @enumFromInt(m);
}

pub fn makeDir(path: []const u8) void {
    var scope = Scope.init();
    defer scope.deinit();
    // Already-exists is the common case at every call site, so the
    // error is swallowed exactly like the old `_ = std.c.mkdir(...)`.
    std.Io.Dir.cwd().createDirPath(scope.io(), path) catch {};
}

pub fn deleteFile(path: []const u8) void {
    var scope = Scope.init();
    defer scope.deinit();
    std.Io.Dir.cwd().deleteFile(scope.io(), path) catch {};
}

pub fn fileExists(path: []const u8) bool {
    var scope = Scope.init();
    defer scope.deinit();
    const io = scope.io();
    var file = std.Io.Dir.cwd().openFile(io, path, .{}) catch return false;
    file.close(io);
    return true;
}

pub fn dirExists(path: []const u8) bool {
    var scope = Scope.init();
    defer scope.deinit();
    const io = scope.io();
    var dir = std.Io.Dir.cwd().openDir(io, path, .{}) catch return false;
    dir.close(io);
    return true;
}

/// Iterate `dir`, calling `visit` with each entry basename. The
/// callback shape avoids handing an iterator (and its Io lifetime)
/// back to the caller.
pub fn forEachEntry(
    path: []const u8,
    context: anytype,
    comptime visit: fn (@TypeOf(context), []const u8) void,
) void {
    var scope = Scope.init();
    defer scope.deinit();
    const io = scope.io();
    var dir = std.Io.Dir.cwd().openDir(io, path, .{ .iterate = true }) catch return;
    defer dir.close(io);
    var it = dir.iterate();
    while (it.next(io) catch return) |entry| visit(context, entry.name);
}

pub fn readStdin(buf: []u8) []const u8 {
    var scope = Scope.init();
    defer scope.deinit();
    const io = scope.io();
    var read_buf: [4096]u8 = undefined;
    var reader = std.Io.File.stdin().reader(io, &read_buf);
    var total: usize = 0;
    while (total < buf.len) {
        const n = reader.interface.readSliceShort(buf[total..]) catch break;
        if (n == 0) break;
        total += n;
    }
    return buf[0..total];
}

// ------------------------------------------------------------------ clock

pub fn nowMs() i64 {
    var scope = Scope.init();
    defer scope.deinit();
    const ns = std.Io.Timestamp.now(scope.io(), .real).nanoseconds;
    return @intCast(@divTrunc(ns, std.time.ns_per_ms));
}

pub fn nowSeconds() i64 {
    return @divTrunc(nowMs(), 1000);
}

// ----------------------------------------------------------------- random

/// Session token entropy. `std.crypto.random` is gone in 0.16 and
/// reading /dev/urandom by hand was the POSIX-only stand-in; this is
/// the OS CSPRNG through Io, which already picks getrandom on Linux,
/// getentropy on Darwin, and RtlGenRandom on Windows.
pub fn fillRandom(out: []u8) !void {
    var scope = Scope.init();
    defer scope.deinit();
    try std.Io.randomSecure(scope.io(), out);
}

// ---------------------------------------------------------------- process

/// Absolute path of the running binary. Replaces realpath(argv0),
/// which lied whenever argv0 was a bare name found on PATH.
pub fn executablePath(buf: []u8) ?[]const u8 {
    var scope = Scope.init();
    defer scope.deinit();
    const len = std.process.executablePath(scope.io(), buf) catch return null;
    return buf[0..len];
}

/// Point `link` at `target`, replacing any existing link.
///
/// Windows caveat: creating a symlink needs either Developer Mode or
/// SeCreateSymbolicLinkPrivilege, so this can fail on a default
/// install. The caller treats failure as "hooks not wired" rather than
/// crashing, and the hook command already exits 0 when the link is
/// missing, so the app degrades to no bubbles instead of breaking.
pub fn replaceSymlink(target: []const u8, link: []const u8) bool {
    var scope = Scope.init();
    defer scope.deinit();
    const io = scope.io();
    const cwd = std.Io.Dir.cwd();
    cwd.deleteFile(io, link) catch {};
    cwd.symLink(io, target, link, .{}) catch {
        // `CreateSymbolicLink` needs SeCreateSymbolicLinkPrivilege on
        // Windows — off by default unless Developer Mode is enabled or
        // the process runs elevated — so this silently leaves an empty
        // placeholder file behind instead of a working link (reproduced
        // on real hardware: agent hooks that shell out to this path see
        // a zero-byte, non-executable file and quietly do nothing).
        // A real file copy needs no special privilege, and this runs on
        // every boot (see the caller), so a stale copy self-heals on
        // the app's next launch after a rebuild.
        if (builtin.os.tag != .windows) return false;
        std.Io.Dir.copyFileAbsolute(target, link, io, .{}) catch return false;
        return true;
    };
    return true;
}

/// Own pid, for the /whoami endpoint. std has no portable accessor in
/// 0.16, so this is the one genuine per-platform branch in this file.
/// Linux gets its own raw-syscall arm (`std.os.linux.getpid`, no libc)
/// rather than falling into the `std.c.getpid()` arm below: this app's
/// analysis build target does not link libc on Linux (macOS does, by
/// platform convention), and `extern "c"` there is a hard build error
/// — "dependency on libc must be explicitly specified" — not a runtime
/// one, caught by CI (2026-08-01, this app's first-ever Linux build).
pub fn processId() u32 {
    return switch (builtin.os.tag) {
        .windows => std.os.windows.GetCurrentProcessId(),
        .linux => @intCast(std.os.linux.getpid()),
        else => @intCast(std.c.getpid()),
    };
}

const windows = std.os.windows;

/// shell32's URL/file-association launcher — what `cmd /c start` and
/// `explorer.exe <target>` both delegate to internally. Calling it
/// directly removes both of those as points of failure: no cmd
/// argument grammar (broke as a bare cmd.exe window + a COM+ registry
/// error, reproduced on real hardware), and no dependency on
/// explorer.exe accepting a bare URL as argv (also reproduced — the
/// cursor busy-spins for the launch, then nothing opens).
extern "shell32" fn ShellExecuteW(
    hwnd: ?windows.HWND,
    lpOperation: ?[*:0]const u16,
    lpFile: [*:0]const u16,
    lpParameters: ?[*:0]const u16,
    lpDirectory: ?[*:0]const u16,
    nShowCmd: c_int,
) callconv(.winapi) windows.HINSTANCE;

const sw_shownormal: c_int = 1;

fn openExternalWindows(target: []const u8) void {
    var wide_buf: [1025]u16 = undefined;
    const capped = target[0..@min(target.len, 1024)];
    const wide_len = std.unicode.utf8ToUtf16Le(&wide_buf, capped) catch return;
    wide_buf[wide_len] = 0;
    _ = ShellExecuteW(null, null, wide_buf[0..wide_len :0], null, null, sw_shownormal);
}

/// Open a URL or a folder in the desktop's default handler. One
/// spawn, no shell, so a path with quotes cannot become an argument
/// injection the way the old `system()` string could. Windows instead
/// calls `ShellExecuteW` directly — see `openExternalWindows`.
pub fn openExternal(target: []const u8) void {
    if (builtin.os.tag == .windows) return openExternalWindows(target);
    var scope = Scope.init();
    defer scope.deinit();
    const io = scope.io();
    const argv: []const []const u8 = switch (builtin.os.tag) {
        .macos => &.{ "/usr/bin/open", target },
        else => &.{ "xdg-open", target },
    };
    var child = std.process.spawn(io, .{
        .argv = argv,
        .stdin = .ignore,
        .stdout = .ignore,
        .stderr = .ignore,
    }) catch return;
    _ = child.wait(io) catch {};
}

extern "kernel32" fn GetConsoleWindow() callconv(.winapi) ?windows.HWND;
extern "user32" fn SetForegroundWindow(hWnd: windows.HWND) callconv(.winapi) c_int;

/// The console window hosting the CURRENT process, as an opaque handle
/// value — called from `hook_runner.run()`, which inherits its
/// console from whatever shell Claude Code's hook spawned it in (a
/// normal child process shares its parent's console unless explicitly
/// detached). 0 means "no console" (not run from a Windows console
/// host, or a non-Windows platform) — the bubble-tap-focus feature is
/// a silent no-op in that case, never an error.
pub fn currentConsoleWindowHandle() u64 {
    if (builtin.os.tag != .windows) return 0;
    const hwnd = GetConsoleWindow() orelse return 0;
    return @intFromPtr(hwnd);
}

/// Bring a window (captured earlier via `currentConsoleWindowHandle`)
/// to the foreground. `handle_value` is an opaque `HWND` bit pattern,
/// not a PID — the window may since have closed (stale handle), which
/// `SetForegroundWindow` simply fails on quietly, matching every other
/// helper in this file's "never error outward" contract.
pub fn focusForeignWindow(handle_value: u64) void {
    if (builtin.os.tag != .windows or handle_value == 0) return;
    const hwnd: windows.HWND = @ptrFromInt(handle_value);
    _ = SetForegroundWindow(hwnd);
}

extern "c" fn ttyname_r(fd: c_int, buf: [*]u8, buflen: usize) c_int;

/// The controlling terminal device path (e.g. `/dev/ttys012` on
/// macOS, `/dev/pts/3` on Linux) for this process's stdin — the
/// macOS/Linux analogue of `currentConsoleWindowHandle`. `hook_runner`
/// is a normal child of whatever shell invoked it, so it inherits the
/// SAME controlling tty as the interactive session running Claude
/// Code; capturing it now, while still running inside that shell, is
/// what SPEC.md 3.6 verified end to end on macOS (`ps -o tty= -p
/// <pid>` reading the same value another way — `ttyname_r` on our own
/// fd 0 is the direct route and needs no PID lookup at all). Empty
/// when stdin isn't a real tty or the platform has none of this
/// (Windows: use `currentConsoleWindowHandle` instead).
/// Linux takes the `/proc/self/fd/0` symlink route instead of
/// `ttyname_r`: same libc-linking problem as `processId` above, and
/// `/proc/self/fd/<n>` resolving to the tty device path is the kernel's
/// own documented behavior for a tty fd, not a workaround.
pub fn currentTty(buf: []u8) []const u8 {
    if (builtin.os.tag == .windows) return "";
    if (builtin.os.tag == .linux) {
        const rc = std.os.linux.readlink("/proc/self/fd/0", buf.ptr, buf.len);
        if (std.os.linux.errno(rc) != .SUCCESS) return "";
        return buf[0..rc];
    }
    if (ttyname_r(0, buf.ptr, buf.len) != 0) return "";
    const len = std.mem.indexOfScalar(u8, buf, 0) orelse buf.len;
    return buf[0..len];
}
