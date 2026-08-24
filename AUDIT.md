# WhisperWrap Static Audit — 2026-08-23

Documentation/reporting pass only; no functional code changes made. `swift build` compiles clean; `swift test` = 41/41 green (run outside the Claude sandbox). Companion feature-QA and UI/UX findings are in `QA_REPORT.md`. All findings are static/code-traced — the GUI app was not launched in this environment; items marked "inferred" were not reproduced live.

## 1. Feature maturity

| Feature | Verdict | Evidence |
|---|---|---|
| Dictation hotkey pipeline | Production-ready (most mature code) | `DictationViewModel.swift` — persisted hotkey (166-180), mic-fallback that preserves the saved device (341-360), silent-mic notification (874-890), defensive HUD edge-case handling (603-646) |
| CoreML transcription (WhisperKit) | Production-ready | `WhisperTranscriptionEngine.swift:30-41` — concurrent-load dedup, download progress, error propagation |
| VAD / silence trim | Production-ready, silent-failure-by-design | `FluidVADProcessor.swift:40-42` swallows all errors, returns nil (caller degrades to untrimmed audio) |
| Claude post-processing | Production-ready with fragile error heuristic | Full streaming/cancel plumbing, well hardened against SIGPIPE/UTF-8 split/backpressure (`ShellService.swift:10-49,60-74`); weakness is `looksLikeError` string-sniffing (`ClaudeService.swift:104-108`) |
| TTS (system + ElevenLabs) | Functional, roughest module | `TTSViewModel.swift` — redundant actor hops (83-124), single-entry cache (68-69), `stop()` can't cancel in-flight downloads (467-477) |
| File transcription (drag-drop) | Production-ready; best-tested path | `ContentViewModel.processAudio` (83-191) — security-scoped access, staged scratch dir, correct cancel semantics, Claude privacy confirm |
| Menu bar UI / settings | Production-ready, minor debt | `WhisperWrap.swift:106-114, 238-282` window-suppression relies on 0.1/0.5s `asyncAfter` timing hacks |
| Model prefetch | Production-ready | `PrefetchManager.swift`; assumes WhisperKit's App Support layout (17-21), version-coupled |
| Permissions handling | Above-average | `PermissionsManager.swift:86-128` — live mic-tap and AX-attribute probes, not just TCC status |
| Install/uninstall scripts | Prototype | Ad-hoc signing, no entitlements; `simulate_login.sh` stale; `uninstall_clean.sh` TCC surgery SIP-blocked (see §7, QA_REPORT #R12-R13) |

## 2. Feature gaps / partial abstractions

| Finding | Location | Sev | Effort | Recommendation |
|---|---|---|---|---|
| Auto-paste feature in README + dead `.accessibility` alert case, but no paste code or setting exists anywhere | README.md:7,29; MenuBarView.swift:138-147 | High | M | Implement CGEvent Cmd-V behind the AX check, or delete the alert case and fix README |
| `transcribeToText(onProgress:)`/`transcribeFormatted(onProgress:)` callbacks never invoked — file-transcription progress ring jumps 0.1→0.9 | WhisperTranscriptionEngine.swift:79,94; ContentViewModel.swift:116-120 | Med | M | Wire WhisperKit segment callbacks or drop the params |
| JSON export is hand-rolled JSONL escaping only `"` — invalid JSON on `\`/newline/control chars | WhisperTranscriptionEngine.swift:113-118 | Med | S | Use `JSONEncoder`; decide JSONL vs array and name the extension honestly |
| `saveRecordings` directory stored as bare path, no security-scoped bookmark (breaks if ever sandboxed) | DictationViewModel.swift:135-137 | Low | S | Store a bookmark |
| ElevenLabs 10,000-char limit duplicated as literal in 4 places | TTSView.swift:187,196; TTSViewModel.swift:309,445 | Low | S | One constant |
| No TODO/FIXME markers anywhere — gaps are structural, unannotated | repo-wide (grep-confirmed) | Info | — | — |

## 3. Dead code (grep-confirmed)

| Finding | Location | Sev | Effort | Recommendation |
|---|---|---|---|---|
| `AudioConstants.swift` entirely unreferenced; 16000 hard-coded independently at call sites | Sources/WhisperWrap/AudioConstants.swift; DictationViewModel.swift:543; FluidVADProcessor.swift:8 | Low | S | Delete or actually use |
| `AppDelegate.showMainWindow()` never called | WhisperWrap.swift:117-123 | Low | S | Delete |
| `activeAlert = .accessibility` never set — alert UI is unreachable | MenuBarView.swift:138-147 | Med | S | See §2 auto-paste item |
| `simulate_login.sh` tests a `-backgroundLaunch` flag and `/tmp/ww_internal.log` that exist nowhere in Sources (`LoggerService` is in-memory only; grep-verified) | simulate_login.sh:21-41; LoggerService.swift:18-27 | Low | S | Delete or implement the flag + file log |
| Duplicate clamp logic: `clampToScreen`/`reClampWindowToScreen` vs `resizeWindowOnPrimaryScreen` | HUDWindowController.swift:387-407 | Low | S | Keep one |
| Empty `.onAppear { }` | TranscriptionView.swift:295 | Low | S | Delete |

## 4. Sloppy code

| Finding | Location | Sev | Effort | Recommendation |
|---|---|---|---|---|
| HUD geometry duplicated across 4 resize blocks with magic sizes (450×80 / 500×280 / 550×130 / 315) | HUDWindowController.swift:174-189,191-225,284-295,431-444 | Med | M | Extract a `HUDLayout` enum of named frames |
| `enableClaude()` copy-pasted verbatim incl. error strings | TranscriptionView.swift:298-317; DictationSettingsView.swift:286-307 | Med | S | Share one implementation |
| "Claude stream → `looksLikeError` → flip `isConnected=false`" block duplicated between dictation and file paths — the two can drift on error behavior | DictationViewModel.swift:784-801; ContentViewModel.swift:145-164 | Low | S | Extract a `ClaudeService.runToCompletion(...) -> Result` helper |
| Silent `try?` on persistence: prompt save; ElevenLabs request body (nil body sends empty POST) | ClaudePrompt.swift:106; TTSViewModel.swift:353 | Med | S | Handle/log failures |
| Force-unwraps in VAD path (`AVAudioFormat`/`PCMBuffer`/`floatChannelData!`) — crash instead of degrade on odd inputs | FluidVADProcessor.swift:52,55,63,125,128 | Med | S | Guard-let with nil fallback (processor already degrades on nil) |
| `AVAudioConverter` dest capacity = source frameCount; sub-16kHz input would silently truncate (low confidence) | FluidVADProcessor.swift:61-69 | Low | M | Size by rate ratio; loop until `.endOfStream` |
| `DictationViewModel` is a ~900-line god object (recording, HUD orchestration, hotkey config, device enumeration, Claude orchestration, notifications); `processAudio` 108 lines, `transcribe` 146 lines | DictationViewModel.swift (whole file); ContentViewModel.swift:83-191 | Low | L | Continue the existing extracted-static-helper pattern; split device enumeration and hotkey display logic out |
| `TTSViewModel.speak()` guards on `isSpeaking` but not `isDownloadingAudio` — rapid double-invocation can fire two ElevenLabs requests (wasted credits, last writer wins); `stop()` also can't cancel an in-flight fetch, whose completion can overwrite newer state | TTSViewModel.swift:212-227,299-317,355-430,467-477 | Low | S | Guard on `isDownloadingAudio`; track and cancel the fetch Task in `stop()` |
| `checkWindowsVisible` detects "only status-bar windows left" by title-string heuristics (`$0.title != ""`, `"Item-"` prefix) — brittle across OS updates | WhisperWrap.swift:263-281 | Low | M | Filter on window class/level instead if it ever misbehaves |
| Three settings-persistence patterns coexist (`didSet`+UserDefaults, `@AppStorage`, manual init read); key strings are raw literals repeated at read/write sites | e.g. "dictationClaudeModel" in DictationViewModel.swift:71 and ContentViewModel.swift:144 | Low | M | Centralize keys in an enum |
| Saved-recording name collides if two takes stop in same second (copy fails, logged only) | DictationViewModel.swift:656 | Low | S | Uniquify filename |
| Blinking-dot animation keyed on `Date()` per body render — doesn't blink reliably | DictationRecordingView.swift:23-24 | Low | S | TimelineView or repeating animation |
| CoreAudio device-disappearing-between-enumeration-and-use during `setDefaultInputDevice` not traced end-to-end (status codes are checked/logged; the mid-recording switch case at :362-373 is handled) | DictationViewModel.swift:217-401 | Low | M | Unverified — flag for live QA with a USB mic unplug |
| Three concurrent timers while recording (10 Hz meter, 20 Hz HUD, visualizer recompute) | DictationViewModel.swift:834; HUDState.swift:40 | Info | — | Acceptable; noted for profiling |

## 5. Test coverage gaps

Well-covered: file pipeline end-to-end with mocks incl. Claude fallback/cancel (`ContentViewModelTests`, 535 ln); dictation post-processing incl. the Claude branch with a mock service (`DictationViewModelTests`, 334 ln); ShellService SIGPIPE cases; extracted pure helpers (`ClaudeServiceTests`, `ClaudePromptTests`, hotkey display tests).

| Gap | Location | Sev | Effort | Recommendation |
|---|---|---|---|---|
| `SilentRecordingMonitor` — pure state machine, zero tests (highest ROI) | SilentRecordingMonitor.swift | Med | S | Add unit tests |
| `UTF8StreamDecoder` split-multibyte carry logic untested | ShellService.swift:14-49 | Med | S | Add unit tests feeding multi-chunk partial sequences |
| `WhisperTranscriptionEngine` — load dedup race, SRT/JSON formatting untested | WhisperTranscriptionEngine.swift:30-41,113-118 | Med | M | Test formatting pure parts at minimum |
| HUD prompt-selection continuation handling (double-await cancel, countdown fallback) — subtle async, zero coverage | HUDWindowController.swift:297-372 | Med | L | Extract `HUDState` transitions to make testable |
| `TTSViewModel`, `PrefetchManager`, `PermissionsManager`, `HotKeyManager`, `AppDelegate` — no corresponding test files at all (ElevenLabs HTTP path, permission probes, relocation logic verified only by manual QA) | Tests/WhisperWrapTests/ | Med | M | Test the pure parts (text extraction TTSViewModel.swift:496-519, cache keys, error decode) |
| MenuBar/AppDelegate window policy (`asyncAfter` timing logic) untested | WhisperWrap.swift:106-114,263-282 | Low | L | Accept or restructure |
| Tests construct real `DictationViewModel` → mutate the developer's actual UserDefaults (e.g. `autoCopy`) | DictationViewModelTests.swift | Med | S | Inject a test `UserDefaults` suite |

## 6. Dependencies

| Finding | Location | Sev | Effort | Recommendation |
|---|---|---|---|---|
| FluidAudio pinned `from: "0.14.7"` — pre-1.0, so an API-breaking 0.15 resolves on `swift package update` (e.g. `VadManager.chunkSize` at FluidVADProcessor.swift:76). Package.resolved currently locks 0.14.7 | Package.swift:9 | Med | S | `.upToNextMinor` or exact pin |
| WhisperKit `from: "1.0.0"` — open range would pick up a breaking 2.x on a fresh resolve, but Package.resolved locks 1.0.0 and is committed | Package.swift:8 | Low | — | Fine; consider `.upToNextMajor` explicitness |
| `swift-argument-parser 1.8.1` is transitive (WhisperKit), not a direct dep — don't document it as one | Package.resolved | Info | — | — |

## 7. Security & performance

| Finding | Location | Sev | Effort | Recommendation |
|---|---|---|---|---|
| ElevenLabs API key plaintext in UserDefaults via `@AppStorage` (`defaults read` away; in unencrypted backups). Single most actionable finding | TTSViewModel.swift:44 | High | M | Keychain (`kSecClassGenericPassword`); migrate existing plaintext once |
| Ad-hoc `codesign --deep --sign -`, no entitlements/hardened runtime/notarization; signature changes every build → TCC permissions reset each rebuild (likely why uninstall grew TCC surgery) | generate_app.sh:109 | Med (High if distributed) | M | Real signing identity + entitlements |
| Dictation path sends every utterance to Claude with no disclosure beyond the toggle; file-drop path shows an explicit privacy alert — asymmetric consent | ClaudeService.swift:84-88 vs TranscriptionView.swift:196-198 | Med | S | Add caption to dictation Claude toggle |
| Move-to-Applications relaunch builds `bash -c "sleep 1 && rm -rf '<src>' && open '<dst>'"` — the only shell-string exec in the app; quote-escaped app-own paths (low exploitability), but the `rm -rf` runs unconditionally after `sleep 1` with no re-check that the copy landed | WhisperWrap.swift:208-216 | Med | S | Two `Process` argv steps (`/bin/rm`, `/usr/bin/open`), no shell layer; verify copy before delete |
| `uninstall_clean.sh` direct sqlite DELETE on TCC.db — always SIP-blocked; shouldn't ship in the bundle | uninstall_clean.sh:81-107 | Low | S | `tccutil` only |
| `dictation_trimmed.wav` written to the shared temp dir (violates repo's own scratch-dir convention); crash mid-transcription leaks it forever — reaper only sweeps `.txt/.srt/.json` (`.wav` excluded, incl. `dictation.wav` in the scratch dir) | FluidVADProcessor.swift:36-37; ContentViewModel.swift:206-226 | Low | S | Route through scratch dir; add `.wav` to reaper or document its exclusion |
| `LSMinimumSystemVersion 13.0` contradicts macOS 14 floor → dyld crash instead of friendly dialog on macOS 13 | generate_app.sh:97 vs Package.swift | Low | S | Set 14.0 |
| VAD loads entire recording into `[Float]` twice (~230 MB for a 1-hour take) — fine for dictation, hazard if reused for file transcription | FluidVADProcessor.swift:45-73 | Low | M | Document or stream |
| `NSAlert.runModal` inside drop handler and move-prompt blocks the UI | TranscriptionView.swift:196-203; WhisperWrap.swift:156 | Med | S | Sheet/confirmationDialog |
| ElevenLabs MP3 decoded via `AVAudioPlayer(data:)` on MainActor; whole file + `lastAudioData` cache retained (unbounded single entry) | TTSViewModel.swift:68,416 | Low | S | Play from file URL; cap cache |
| Positives: no shell interpolation in the Claude path (argv arrays via `/usr/bin/env`, transcript over stdin); pipes drained concurrently (no >64KB deadlock); no secrets observed in `LoggerService` output; app-owned scratch dir with age-scoped reaping; clipboard snapshot/restore on HUD copy; ElevenLabs byte-loop perf bug already fixed (comment TTSViewModel.swift:386-395) | ShellService.swift:97-98,162-163; ContentViewModel.swift:193-225; HUDWindowController.swift:450-478 | — | — | — |

**Top 5 actions:** (1) Keychain for the ElevenLabs key; (2) real codesigning + entitlements (fixes recurring TCC resets); (3) tighten the FluidAudio pin; (4) tests for `SilentRecordingMonitor` + `UTF8StreamDecoder`; (5) delete dead `AudioConstants.swift`, `showMainWindow()`, stale `simulate_login.sh`, and dedupe `enableClaude()`.
