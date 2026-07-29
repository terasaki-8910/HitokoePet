<div align="right">

[![日本語](https://img.shields.io/badge/lang-%E6%97%A5%E6%9C%AC%E8%AA%9E-bc002d?style=flat-square)](./README.md)

</div>

# HitokoePet

A desktop pet that reacts to Claude Code session state. One pet represents every session, announces task completion with its voice, and lip-syncs (compatible with the Codex pet atlas spec).

This project consists of **two deliverables with different supported environments**. Do not conflate them.

| Deliverable | What it is | Supported environments |
| --- | --- | --- |
| `app/` | The pet itself (drag / multi-session aggregation / lip-sync / idle-CPU reduction / bubble tap) | Decided by the spike. Currently verified on real Windows hardware for build, always-on-top, and transparency (with a known noise artifact in the transparent region). macOS / Linux unverified |
| `voice/` | Voice-notification hook (speaks on completion via the Stop hook) | macOS / Ubuntu / NixOS / Windows |

`app/` is a subtree import of upstream [petdex](https://github.com/crafter-station/petdex)'s `packages/petdex-desktop-native` (MIT, see `app/PROVENANCE.md`), plus this project's own features.

## Requirements

- **Native SDK (`@native-sdk/cli`)** — required to build and test the pet.
  The **published npm versions (0.4.0–0.6.1) do not work**: they reject `app/app.zon`'s
  `.floating` / `.transparent` as an unexpected field and `native build` fails.
  You need a CLI built yourself from `Railly/native@feat/floating-window-0.5.3`
  (commit `65d4885`); the pin is recorded in `app/PROVENANCE.md`. The SDK is pre-1.0
  and expected to introduce breaking changes.
- **An audio-playback command** — `voice/` auto-detects and uses one of `afplay` /
  `pw-play` / `paplay` / `ffplay` / `powershell.exe` / `aplay`. On a machine with none
  of them (headless), it stays silent and does nothing.
- **Codex pet atlas assets** — place the spritesheet and `pet.json` below under
  `~/.codex/pets/<id>/`.
- **(optional) `shellcheck`** — used to lint the `voice/` shell scripts.

### Spritesheet spec (inherited from upstream, read unmodified)

- 8 columns × 9 rows, 192×208px cells, 1536×1872px overall, transparent PNG/WebP
- Rows = states, columns = frames. Leftover cells are fully transparent
- Row order: `idle`(6) / `running-right`(8) / `running-left`(8) / `waving`(4) /
  `jumping`(5) / `failed`(8) / `waiting`(6) / `running`(6) / `review`(6)
- Layout: `pet.json` + `spritesheet.webp` under `~/.codex/pets/<id>/`

## Setup

1. **Build the pet** (using the pinned CLI):

   ```sh
   native build app
   ```

   This yields the persistent desktop pet. Run `native doctor` to diagnose the
   environment first if the build does not go through.

2. **Register the voice hook with Claude Code** — add the `voice/` script to
   `~/.claude/settings.json` under `hooks.Stop[].hooks[]`. It fires **only on the `Stop`
   hook** (`SubagentStop` is out of scope).

   > Do not reuse a Codex-oriented script. Claude Code's Stop payload has no `.type`
   > field, so `jq -r '.type'` returns `null`. The failure mode is that it looks
   > installed and working while never playing a sound (see SPEC 3.3.1).

3. **(optional) Enable lip-sync** — place a mouth layer `mouth.png` next to the pet.
   A pet without one works normally with no lip-sync (never an error). The amplitude is
   read from an RMS envelope pre-computed next to the WAV (`done.wav` + `done.rms`).

4. **(optional) Configure the home-server TTS (L3)** — only on a cache miss, query the
   home server's TTS over Tailscale. If the home server is down, fall back to the L1
   generic WAV.

## Usage / behavior

- **One pet represents everything.** It reads `~/.claude/sessions/<pid>.json` and folds
  all sessions into a single display state by priority `waiting` > `busy` > `idle`. More
  sessions never add more pets. If schema validation fails, this feature is disabled and
  the pet keeps working via the existing hook path (graceful degradation).
- **Drag.** While the mouse button stays down, a single drag state is held regardless of
  velocity (motion never stops even when you move slowly or grab and hold still). On
  release, throw physics kicks in and the pet returns to `waving` after decelerating.
  Window follow works on macOS (already implemented) plus Windows (`SetWindowPos`) and
  Linux X11 (`XMoveWindow`); on Linux Wayland it does nothing.
- **Completion voice.** The `Stop` hook plays an utterance. Tiered design:

  | Tier | Content | Runs on |
  | --- | --- | --- |
  | L1 | Fixed WAV per event kind | Each machine |
  | L2 | Cache keyed by the phrase hash (`~/.cache/hitokoe/<sha1>.wav`) | Each machine |
  | L3 | On cache miss only, the home server's TTS over Tailscale | Home server |

  To keep notifications from overlapping when several projects run at once, playback is
  serialized with an atomic `mkdir` lock. If the lock wait exceeds a limit, it gives up
  and exits 0 (so hook invocations do not pile up).
- **Lip-sync.** It reads the `done.rms` envelope and deterministically picks a mouth
  shape (closed / half / open). It never observes the playing audio and touches no audio
  device or recording API; the same WAV always produces the same mouth motion.
- **Bubble tap.** Tapping the speech bubble moves focus to the terminal tab where the
  aggregation winner (the session whose state is currently shown) is running, so
  "there's a permission prompt → tap the bubble → jump to that terminal" is a straight
  line. Verified on macOS + iTerm2. On an unsupported terminal it does nothing.

## Constraints

- **The Native SDK is pre-1.0.** A pinned, self-built CLI is required (see Requirements).
- **`app/`'s supported environments are the spike's output**, not an unconditional
  guarantee. The transparent window is verified on real Windows hardware but has a known
  noise artifact in the transparent region; macOS / Linux are unverified.
- **A system tray** exists on macOS / Windows but not Linux. `close_policy = "hide"`
  requires the `tray` capability on Windows and is rejected at build time on Linux.
- **Terminal focus (bubble tap) is guaranteed only on macOS + iTerm2.** Ghostty /
  WezTerm / Alacritty / kitty are uninvestigated.
- **Dependence on an internal path.** `~/.claude/sessions/` is a non-public internal
  path, so if its schema changes the aggregation feature is disabled and the pet keeps
  running.

## Out of scope (explicitly not built)

- Microphone input / STT / prompt injection into Claude Code
- Reading out Claude's response bodies
- One pet per session (N pets) / a session-list panel
- Installing a local TTS runtime on each machine (generation is pushed to the L3 home server)
- Guaranteed support for terminal emulators other than iTerm2
- Terminal focus on Windows / Linux
- Viseme-based lip-sync
- New features for Codex / Gemini CLI / opencode (upstream support is not broken, but not extended)
- A PR to upstream (not in v1)
- Code signing / notarization / release distribution
- Unconditional operation on Windows / Linux (Wayland drag and the Windows transparency noise remain unresolved)

## Developed via the gated pipeline

This project is built stage by stage through a gated pipeline. This README is itself an
artifact generated from SPEC.md, never hand-authored.

```sh
sh scripts/run.sh from <stage>      # advance from a given stage
INTERACTIVE=1 sh scripts/run.sh from <stage>   # run in the TUI instead of headless
```

- Stage (gate) definitions live in `pipeline.yaml`.
- Pass/fail criteria live in `ACCEPTANCE.md`.
- Tests: `native test app`
- Lint: `native check app --strict && scripts/gate-lint.sh`
  (`native check` alone is not enough: this app has zero `.native` markup, so
  no-emoji / design-tokens-only / a11y are enforced by `scripts/gate-lint.sh`)
