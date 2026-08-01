#!/usr/bin/env python3
"""
app/assets/voice/<pet>/script.json の台詞から、状態連動ボイス（SPEC 3.7）の
WAVファイルを (re)生成する。

台詞を書き換えたら、このスクリプトを実行するだけで
app/assets/voice/<pet>/<category>/<番号>.wav に反映される。
キャラごとに台本を分けたい場合は app/assets/voice/<pet>/script.json を
新規に作ればよい（app/src/main.zig の voiced_pet_slug / voice_line_counts
もそのキャラを鳴らす対象に含める必要がある — 詳細はそちらのコメント参照）。

前提: このリポジトリ外にある個人環境固有のTTSプロジェクト
（C:\\Users\\e8910\\Documents\\TTS\\Irodori-TTS）を使う。Windows機・このユーザー環境専用。
script.json に "lora_adapter" キーがあれば infer.py --lora-adapter に渡す
（キャラ専用LoRAで声の再現度・感情表現を上げたい場合。省略時は base checkpoint
 + ref-wav の声クローンのみ）。

使い方:
    python scripts/generate-voice.py                        # iroha の全カテゴリ
    python scripts/generate-voice.py waiting jumping         # iroha の指定カテゴリのみ
    python scripts/generate-voice.py --pet iroha waiting     # pet 明示 + カテゴリ指定
    python scripts/generate-voice.py --pet <slug>            # 別キャラの全カテゴリ
"""
import argparse
import json
import subprocess
import sys
from pathlib import Path

sys.stdout.reconfigure(encoding="utf-8", errors="replace")
sys.stderr.reconfigure(encoding="utf-8", errors="replace")

REPO_ROOT = Path(__file__).resolve().parent.parent
VOICE_ROOT = REPO_ROOT / "app" / "assets" / "voice"
TTS_PROJECT = Path(r"C:\Users\e8910\Documents\TTS\Irodori-TTS")
TTS_PYTHON = TTS_PROJECT / ".venv" / "Scripts" / "python.exe"
TTS_INFER = TTS_PROJECT / "infer.py"


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--pet", default="iroha", help="app/assets/voice/<pet>/ の <pet> (デフォルト: iroha)")
    parser.add_argument("categories", nargs="*", help="再生成するカテゴリ名（省略時は全部）")
    args = parser.parse_args(argv)

    if not TTS_PYTHON.exists():
        print(f"TTS venv not found at {TTS_PYTHON} — this script only runs on "
              "the dev machine with Irodori-TTS set up.", file=sys.stderr)
        return 1

    voice_dir = VOICE_ROOT / args.pet
    script_json = voice_dir / "script.json"
    if not script_json.exists():
        print(f"no script.json for pet {args.pet!r} at {script_json}", file=sys.stderr)
        return 1

    data = json.loads(script_json.read_text(encoding="utf-8"))
    categories = data["categories"]
    voice_ref = data["voice_ref"]
    checkpoint = data["checkpoint"]
    lora_adapter = data.get("lora_adapter")

    wanted = set(args.categories) if args.categories else set(categories.keys())
    unknown = wanted - set(categories.keys())
    if unknown:
        print(f"unknown categories: {sorted(unknown)}", file=sys.stderr)
        return 1

    for category, entry in categories.items():
        if category not in wanted:
            continue
        lines = entry["lines"]
        out_dir = voice_dir / category
        out_dir.mkdir(parents=True, exist_ok=True)
        for i, text in enumerate(lines, start=1):
            out_wav = out_dir / f"{i}.wav"
            print(f"[{args.pet}/{category}/{i}] {text!r} -> {out_wav}")
            cmd = [
                str(TTS_PYTHON), str(TTS_INFER),
                "--checkpoint", checkpoint,
                "--ref-wav", voice_ref,
                "--text", text,
                "--output-wav", str(out_wav),
                "--model-device", "cuda",
                "--codec-device", "cuda",
            ]
            if lora_adapter:
                cmd += ["--lora-adapter", lora_adapter]
            result = subprocess.run(
                cmd,
                cwd=str(TTS_PROJECT),
                capture_output=True,
                text=True,
                encoding="utf-8",
                errors="replace",
            )
            if result.returncode != 0:
                print(f"  FAILED (exit {result.returncode}):", file=sys.stderr)
                print(result.stderr[-2000:], file=sys.stderr)
                return 1
        # Any leftover numbered files beyond the current line count are
        # stale (a category that shrank) — remove them so playback
        # never picks up an orphaned old line.
        i = len(lines) + 1
        while (stale := out_dir / f"{i}.wav").exists():
            stale.unlink()
            print(f"  removed stale {stale}")
            i += 1

    print("done")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
