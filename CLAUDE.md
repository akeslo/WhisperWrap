# CLAUDE.md — WhisperWrap

macOS 14+ menu bar app: local speech-to-text via WhisperKit (CoreML), global-hotkey dictation with auto-copy to clipboard (README's "Auto Paste" does not exist in code — no paste synthesis, no such setting), drag-drop file transcription, TTS (system voices + optional ElevenLabs), and optional Claude post-processing that shells out to the `claude` CLI (no Claude API key stored — auth is via the `claude` CLI's own login). The ElevenLabs API key *is* stored, in plaintext `UserDefaults`/`@AppStorage` — see AUDIT.md's top finding.

## Stack

- Swift 6.2 toolchain (`swift-tools-version: 6.2`), SwiftUI + AppKit, SPM executable target (no Xcode project).
- Deps: WhisperKit `from: 1.0.0`, FluidAudio `.upToNextMinor(from: 0.14.7)` (VAD, tightened 2026-08-23 — was an open `from:` range on a pre-1.0 package). No other third-party deps.
- Entry point: `Sources/WhisperWrap/WhisperWrap.swift` (`WhisperWrapApp` + `AppDelegate`). App runs as an accessory (menu bar only) unless a window is shown.

## Commands

```bash
swift build              # debug build
swift test               # run test suite (6 test files) — MUST run outside the Claude
                         # command sandbox: SwiftPM invokes sandbox-exec itself and fails
                         # with "sandbox_apply: Operation not permitted" when nested.
./generate_app.sh        # Release build + package WhisperWrap.app at repo root
                         # (CFBundleVersion hardcoded "1", ad-hoc signing; the
                         # git rev-list versioning claim in CLAUDE.local.md is stale)
./uninstall_clean.sh     # kills app, removes /Applications copy + local .app + prefs/caches
```

No lint config. No CI. Tests are XCTest under `Tests/WhisperWrapTests/` (8 files as of 2026-08-23).

`simulate_login.sh` was deleted 2026-08-23 — it tested a `-backgroundLaunch` flag and
`/tmp/ww_internal.log` that never existed in Sources (`LoggerService` is in-memory only).

## Architecture

- `DictationViewModel` — the core pipeline: hotkey toggle → AVAudioEngine capture → WhisperKit transcription → clipboard/auto-paste, plus HUD state. Largest file (~900 lines).
- `ContentViewModel` — file transcription (drag-drop), temp-file management, export.
- `WhisperTranscriptionEngine` — WhisperKit wrapper (model load/transcribe).
- `ClaudeService` + `ShellService` — Claude post-processing via `claude --print --model <m>` with the prompt+transcript on stdin (arguments are passed as a Process argv array, not a shell string). `ClaudePrompt`/`ClaudePromptManager` hold built-in and custom prompts.
- `TTSViewModel` — system `AVSpeechSynthesizer` + ElevenLabs HTTP engine.
- `MenuBarManager`/`MenuBarView` — status item + menu; `HUDWindowController`/`HUDView`/`HUDState` — floating recording HUD panel; `LastResultWindowController` — last-transcript popup.
- `HotKeyManager` (Carbon global hotkey), `PermissionsManager` (mic/accessibility health check), `PrefetchManager` (model downloads), `SilentRecordingMonitor`/`FluidVADProcessor` (silence detection), `LoggerService` (in-memory ring of 5000 entries, viewable in the app's log view — it writes no file).

## Conventions & Gotchas

- Settings live in `UserDefaults.standard`, except the ElevenLabs API key which lives in `@AppStorage("elevenLabsAPIKey")` (`TTSViewModel.swift`) — same plaintext-on-disk exposure as `UserDefaults`, just accessed via the SwiftUI wrapper. See AUDIT.md before changing key handling.
- Temp files go in `ContentViewModel.scratchDirectory` (`<temp>/WhisperWrap/`), never `FileManager.default.temporaryDirectory` itself. `cleanupOldTempFiles()` deletes by extension (`.txt`/`.srt`/`.json`) with no ownership check, so pointing it at the shared per-user temp dir reaps other processes' files — real defect, fixed 2026-08-03.
- `ContentViewModel.init()` reads the saved Claude-prompt ID from real `UserDefaults` — state leaks across tests and across `swift test` invocations. Clear `fileClaudePromptID` in `setUp()` (see `ContentViewModelTests`) for any test touching it.
- `UNUserNotificationCenter` requires a real .app bundle; notification setup is skipped under `swift run` (no bundle ID).
- `AUDIT.md` / `QA_REPORT.md` at repo root hold the 2026-08-23 static audit and feature QA findings.
  `REMEDIATION_PLAN.md` / `VALIDATION_REPORT.md` / `DEFERRED.md` (also 2026-08-23) track the
  remediation pass against those two reports — check `DEFERRED.md` before assuming a listed
  finding is still open, and `REMEDIATION_PLAN.md` for the full backlog status.
- `WhisperTranscriptionEngine.transcribeFormatted`'s txt/srt/json formatting is extracted into
  a static, WhisperKit-independent `WhisperTranscriptionEngine.format(segments:as:)` taking
  `ExportedSegment` — testable without a loaded model. JSON export now uses `JSONEncoder`
  (was hand-rolled string interpolation that only escaped `"`, producing invalid JSON and
  JSONL under a `.json` extension — R7, fixed 2026-08-23).
- `ContentViewModel.noSpeechDetectedSentinel` ("No Speech Detected") is a display-only value
  for a silent take — `DictationViewModel`'s autoCopy path explicitly excludes it so it can
  never overwrite the user's actual clipboard contents (U4, fixed 2026-08-23).
- `HotKeyManager.registerHotKey` validates `keyCode`/`modifiers` with `UInt32(exactly:)` before
  calling into Carbon; a corrupted persisted hotkey (e.g. via `defaults write ... -int -1`)
  used to trap and crash-loop the app on every launch (R3, fixed 2026-08-23).
