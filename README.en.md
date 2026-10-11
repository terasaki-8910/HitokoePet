<div align="right">

[日本語](./README.md)

</div>

# HitokoePet

One desktop pet stands in for every Claude Code session and tells you, with a speech bubble and a voice, when a session is waiting on you or has reached a stopping point.
Compatible with the Codex pet atlas format.

<p align="center">
  <img src="docs/images/hero.png" width="380" alt="A speech bubble reading 'Waiting for you…' above the pet">
</p>
<p align="center"><sub>The bubble is a real render from the app (<code>native automate screenshot</code>). The pet is the waiting row of the same atlas, placed exactly where the app places it.</sub></p>

Running Claude Code in several projects at once makes it easy to miss which session is blocked on a permission prompt.
Instead of one notification per session, HitokoePet folds everything into a single pet: if any session is waiting, the pet looks like it is waiting,
and tapping the bubble brings that session's terminal to the front.

`app/` is a subtree import of [petdex](https://github.com/crafter-station/petdex)'s `packages/petdex-desktop-native` (MIT, Zig + Native SDK),
with the missing pieces added on top. The blue components in the diagrams and the change table in `app/PROVENANCE.md` show exactly what was added.

## Features and verification status

| Feature | What it does | Status |
| --- | --- | --- |
| Multi-session aggregation | Reads `~/.claude/sessions/*.json` every 100 ms and folds them into one state by priority `waiting > busy > idle`. WSL sessions are scanned too | Verified on Windows + WSL (4 sessions detected at once: 1 native + 3 WSL). 8 concurrent sessions not measured |
| Tap the bubble to jump to the terminal | The hook captures its own terminal id (HWND / tty) the moment it starts and attaches it to the bubble; tapping focuses that terminal | Verified with standalone console windows and WSL host windows on Windows. macOS (iTerm2) is code only |
| Grab and throw | Grab the character itself; the held pose stays while the button is down, then throw physics on release | Verified on Windows. macOS is upstream code. Window moving on Linux (X11) not implemented |
| Transparency | Per-pixel alpha via `UpdateLayeredWindow` (a patch to the SDK fork) | Verified on Windows |
| State-linked voice | Speaks only at the moments that need you: waiting, right after a prompt, failure. 60 s per-category cooldown, volume and on/off in Settings | Verified on Windows (WAVs pre-generated with a local TTS on the Windows machine) |
| Tray | Lives in the notification area instead of the taskbar | Verified on Windows |
| `voice/` completion hook | Speaks on the `Stop` hook and picks the available player per OS (macOS / Ubuntu / NixOS / Windows) | `voice/test.sh`: 14 pass, 1 skipped (no shellcheck). WAVs not bundled, not registered in `settings.json` yet |
| 3-OS builds | GitHub Actions builds portable macOS (.app) / Windows / Linux packages | Latest manual run (`43aa72a`) succeeded |
| Lip sync | Mouth shape chosen from a precomputed loudness envelope | **Not implemented.** Pure functions and tests only; not composited into rendering |
| Idle CPU | Physics timer only runs while dragging; WSL scan throttled to every 2 s | **No reduction confirmed** (see Measurements) |

## Screenshots

<table>
  <tr>
    <td valign="top" width="50%">
      <img src="docs/images/bubbles.png" alt="Three bubbles: working, waiting, done"><br>
      <sub>Bubbles: working (tool description), waiting, and the final message on completion. The first line is the session's first prompt.</sub>
    </td>
    <td valign="top" width="50%">
      <img src="docs/images/settings.png" alt="Settings window"><br>
      <sub>Lower half of Settings. Held-motion sensitivity, voice on/off, cooldown and volume were added by HitokoePet.</sub>
    </td>
  </tr>
</table>

<img src="pixelart/iroha.gif" width="200" align="right" alt="Pixel-art animation of the pet">

The character is an 11-frame GIF animated in Aseprite, assigned to the rows of a Codex-compatible atlas (8 columns x 9 rows, 192x208 px cells).
The atlas format is untouched, so any pet made for Codex loads as is.

<br clear="right">

## Architecture

<img src="docs/images/architecture.svg" alt="Architecture diagram (labels in Japanese)">

State arrives on two paths.

- **Hooks** (upstream): Claude Code hooks launch `petdex-hook`, which POSTs state and bubble text to the HTTP server inside the pet.
  It carries tool names and descriptions, but every session writes to the same pet, so the last writer wins.
- **Session registry aggregation** (added): read every `~/.claude/sessions/<pid>.json` that Claude Code itself writes and fold them by priority.
  None of the three prior implementations (clawdex / claude-code-pet / petdex) read this file or handled multiple sessions (`docs/prior-art.md`).
  It is an internal file, not a public API, so unreadable files are skipped and the result falls back to idle; the hook path keeps working.

When `petdex-hook` starts as a hook it is a child of the terminal running that session, so it reads the terminal id directly
(`GetConsoleWindow()` on Windows, `ttyname` on macOS / Linux). No pid-to-terminal lookup is needed, and the same call works from WSL.

## State flow

<img src="docs/images/flow.svg" alt="State decision flow (labels in Japanese)">

## Voice

<img src="docs/images/voice.svg" alt="Voice pipeline (labels in Japanese)">

- **State-linked voice** (in the pet): edit `app/assets/voice/<slug>/script.json` and run `python scripts/generate-voice.py --pet <slug>`.
  The TTS (Irodori-TTS with a character LoRA) lives only on the Windows machine with a GPU; the pet just plays the pre-generated WAVs.
  This TTS reads lines flat unless they contain emoji, so the script embeds emoji right after interjections and sound words (`voice/samples/daihon.md`).
- **`voice/` completion hook**: a standalone shell script that can ship to machines without the pet (headless boxes, for example).
  A script written for Codex never fires here, because Claude Code's Stop payload has no `.type`; this one checks `hook_event_name` only.

## Stack and CI

<img src="docs/images/stack.svg" alt="Tech stack and CI (labels in Japanese)">

Native SDK is pre-1.0, and the npm releases (0.4.0 to 0.6.1) reject `.floating` / `.transparent` in `app.zon`.
Like upstream, this repo pins `Railly/native@feat/floating-window-0.5.3` (`65d4885`) and keeps its Windows changes as 11 patches in `patches/native-sdk-fork/`.
CI clones the pinned commit, applies the patches, builds the CLI and then the app every time, so the fork never has to live in the repo.

## How it was built

<img src="docs/images/process.svg" alt="Development process (labels in Japanese)">

Built with Claude Code, through a gated pipeline (`pipeline.yaml`, `scripts/run.sh`): humans decide only at the judgment points (spec, acceptance criteria, acceptance), and tests plus lint stop everything else.
`ACCEPTANCE.md` states every criterion as a machine-checkable pass/fail. `main.zig` had zero tests, so state selection, aggregation, mouth shape and terminal focus were pulled out into pure functions and tested.

## Measurements: idle CPU

| Condition | CPU (share of one core) | RSS |
| --- | --- | --- |
| Upstream v0.3.1, macOS, 91 s (2026-07-28) | 22.7% | 111 MB |
| This repo, Windows, 45 s x 2 (2026-10-11) | 17.4% / 16.3% | 55 MB |
| Upstream at import time, same Windows machine and SDK fork, 45 s x 2 (2026-10-11) | 8.1% / 16.4% | 41-47 MB |

On the same machine, no reduction is confirmed. Upstream varied a lot between runs, and the runs happened in Claude Code's own session rather than an interactive desktop,
so the conclusion is "cannot claim a reduction", not the size of the gap. Windows / Linux go through the SDK's software present path (`gpu_present_path=pixels`),
where the incremental-present optimization does not apply (`docs/prior-art.md` 5.1). Root cause and target values (`ACCEPTANCE.md` E1-E3) are still open.

## Build and run

Requires Zig 0.16.

```sh
# 1. Prepare the pinned Native SDK fork and apply the patches (same steps as CI)
git clone --branch feat/floating-window-0.5.3 https://github.com/Railly/native.git tools/native-sdk-fork
git -C tools/native-sdk-fork checkout 65d4885cb5f76a5d1f33cace56b93a898f7b2cb3
for p in patches/native-sdk-fork/*.patch; do patch -p0 < "$p"; done
(cd tools/native-sdk-fork && zig build cli)
export PATH="$PWD/tools/native-sdk-fork/zig-out/bin:$PATH"

# 2. Build and test
native build app
native test app
```

- Put pets in `~/.petdex/pets/<id>/` (or `~/.codex/pets/<id>/`) as `pet.json` + `spritesheet.webp`.
- Register the Claude Code hooks from Settings > Agents > Claude Code.
- Prebuilt portable packages are on [Releases](https://github.com/terasaki-8910/HitokoePet/releases). They are unsigned:
  on macOS right-click > Open the first time; on Windows expect a SmartScreen prompt.

## Limits and out of scope

- Terminal focus is verified only for standalone console windows and WSL host windows on Windows. Windows Terminal has no API to select a specific tab from outside, and Wayland is out of scope.
- `~/.claude/sessions/` is not a public API. If its schema changes, aggregation falls back to idle and only the hook path remains.
- Not built: microphone input, STT, reading Claude's replies aloud, one pet per session.
- No code signing or notarization. No upstream PR in v1.

## Documents

| File | Contents |
| --- | --- |
| `SPEC.md` | What is and isn't built, constraints (updated with findings after implementation) |
| `ACCEPTANCE.md` | Pass/fail criteria and the commands that judge them |
| `docs/prior-art.md` | Comparison of three prior implementations, with measurements |
| `app/PROVENANCE.md` | How upstream is imported, and the record of this project's changes and investigations |
| `task.md` | Open issues |

The documents are written in Japanese.

## License

MIT (`LICENSE`). `app/` is a subtree of petdex-desktop-native and keeps the upstream license (MIT, Copyright (c) 2026 Crafter Station) in `app/LICENSE`.

Diagram icons come from [Simple Icons](https://simpleicons.org/) (CC0) and [Lucide](https://lucide.dev/) (ISC). Logos are trademarks of their respective owners.
The pet is fan art of Iroha Natsume from Blue Archive; rights to the character belong to the original rights holders.
