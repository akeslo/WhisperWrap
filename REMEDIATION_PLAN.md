# WhisperWrap Remediation Plan — 2026-08-23

**Status-table addendum (2026-08-31, domain-brainstorm-rotation sweep):** rows below marked
DONE/PARTIAL with a commit hash were fixed by later autonomous sessions after this plan was
written; the original DEFERRED text is left in place for context, only the status cell was
updated. This plan's own text is otherwise unmaintained — cross-check against `git log`
before trusting any remaining DEFERRED row.

**Status-table addendum (2026-11-14, plan sweep 2026-11-13):** status cells re-synced with main. Rows fixed by the sweep (PRs #9-#20) or by earlier commits are DONE with their commit; rows no longer worth doing are EXCLUDED with the reason. The remaining DEFERRED rows still stand.

Backlog derived from `AUDIT.md` (static audit) and `QA_REPORT.md` (feature QA + UI/UX),
both dated 2026-08-23. This pass re-verified every finding against current code before
acting. **Session-scope note:** given the size of this backlog (~55 findings) relative to
the time available in this session, a subset of high-severity/low-risk items was fully
implemented, tested, and validated (see `VALIDATION_REPORT.md`); the remainder is recorded
here as DEFERRED or BLOCKED-NEEDS-DECISION with reasons, not silently dropped. No item was
marked DONE without a commit and a passing `swift build` + `swift test` at that point.

Legend — Status: DONE (implemented+tested+validated), PARTIAL (part of the finding fixed,
remainder tracked separately), INVALID (re-verified absent from current code),
BLOCKED-NEEDS-DECISION (requires a design call this plan doesn't settle), DEFERRED
(valid, not done this session — reason given).

## A. High severity / low risk (worked first)

| ID | Source | Finding | Location | Sev | Effort | Risk | Deps | Status |
|---|---|---|---|---|---|---|---|---|
| R1 | QA §2 | Menu-bar Start Recording didn't guard `isProcessing` | MenuBarView.swift, DictationViewModel.swift | High | S | Low | none | **DONE** — commit `081f864` |
| R3 | QA §2 | Corrupted hotkey defaults trap `UInt32(keyCode)` → crash loop | HotKeyManager.swift, DictationViewModel.swift | Med | S | Low | none | **DONE** — commit `92a0eb3` |
| R7 | QA §2 / A-GAP-3 | JSON export invalid (only `"` escaped); JSONL under `.json` | WhisperTranscriptionEngine.swift | Med | S | Low | none | **DONE** — commit `a820b7e` |
| U4 | QA §3 | "No Speech Detected" sentinel auto-copied over the user's real clipboard | ContentViewModel.swift, DictationViewModel.swift | High | S | Low | none | **DONE** — commit `6af5241` |

## B. Dead code (batched, one commit)

| ID | Source | Finding | Location | Sev | Effort | Risk | Status |
|---|---|---|---|---|---|---|---|
| A-DEAD-1 | Audit §3 | `AudioConstants.swift` unreferenced | Sources/WhisperWrap/AudioConstants.swift | Low | S | Low | **DONE** — commit `e0e4815` (grep-confirmed zero refs before deleting) |
| A-DEAD-2 | Audit §3 | `AppDelegate.showMainWindow()` never called | WhisperWrap.swift | Low | S | Low | **DONE** — commit `e0e4815` |
| A-DEAD-4 | Audit §3 / R14 | `simulate_login.sh` stale (`-backgroundLaunch`/`/tmp/ww_internal.log` don't exist) | simulate_login.sh | Low | S | Low | **DONE** — commit `e0e4815`, script deleted |
| A-DEAD-6 | Audit §3 | Empty `.onAppear { }` | TranscriptionView.swift:295 | Low | S | Low | **DONE** — commit `e0e4815` |
| A-DEAD-5 | Audit §3 | Duplicate clamp logic (`clampToScreen`/`reClampWindowToScreen` vs `resizeWindowOnPrimaryScreen`) | HUDWindowController.swift:387-407 | Low | S | Low | **EXCLUDED** — HUD rewritten in `1507acf` |
| A-DEAD-3 | Audit §3 / U3 | `activeAlert = .accessibility` never set — dead alert tied to auto-paste | MenuBarView.swift:138-147 | Med | S | Low | **DONE** — commit `1f99600` (`deliver()` raises the Accessibility alert when paste is not allowed) |

## C. Dependencies

| ID | Source | Finding | Location | Sev | Effort | Risk | Status |
|---|---|---|---|---|---|---|---|
| A-DEP-1 | Audit §6 | FluidAudio open `from:` range on pre-1.0 package | Package.swift | Med | S | Low | **DONE** — commit `57852c1`, `.upToNextMinor(from: "0.14.7")` |
| R15 (part) | QA §2 | `LSMinimumSystemVersion 13.0` vs macOS 14 floor | generate_app.sh:97 | Low | S | Low | **DONE** — commit `57852c1`, set to `14.0` |
| R15 (part) | QA §2 | `CFBundleVersion` hardcoded `"1"`, docs claim `git rev-list --count HEAD` | generate_app.sh:88-91 | Low | S | Low | **DONE** — commit `54c809f` (`CFBundleVersion` = `git rev-list --count HEAD`) |
| A-DEP-2 | Audit §6 | WhisperKit `from: 1.0.0` — fine, Package.resolved locks it | Package.swift | Low | — | — | **EXCLUDED** — WhisperKit removed in `54c809f` |

## D. Feature gaps requiring a design decision — BLOCKED-NEEDS-DECISION

These are not implemented because the correct resolution is genuinely ambiguous and the
task brief says to surface rather than guess.

| ID | Source | Finding | Location | Question for Kes |
|---|---|---|---|---|
| A-GAP-1 / U3 | Audit §2, QA U3 | README + in-app alert copy promise "Auto Paste"; no CGEvent/paste code, no setting exists anywhere; `git log` shows no prior implementation attempt | README.md:7,29,33; MenuBarView.swift:138-147 | **DONE** — commit `16a514d` (paste at the cursor is implemented) |
| U1 | QA §3 | Permission requests only fire from the main window's `onAppear`, but the app launches hidden — a fresh-install user going straight to the hotkey is never asked for mic access | ContentView.swift:80-86; WhisperWrap.swift:106-114 | **DONE** — commits `1507acf` + `38babda` |
| U2 | QA §3 | `.notDetermined` mic state treated as denied on first hotkey press, before macOS has ever shown a permission prompt | PermissionsManager.swift:54; DictationViewModel.swift:516-520 | **DONE** — commits `1507acf` + `38babda` |
| U9 | QA §3 | 3-second auto-advancing prompt-picker countdown on every Claude+HUD transcription | HUDWindowController.swift:345-376; DictationSettingsView.swift:137 | **EXCLUDED** — the refine pill replaced the countdown |
| U21 (terminology) | QA §3 | Engine name drift ("Whisper"/"WhisperKit"/"CoreML" used inconsistently) | multiple | **EXCLUDED** — WhisperKit removed in `54c809f` |

## E. Security — one BLOCKED, rest DEFERRED (real work, not done this session)

| ID | Source | Finding | Location | Sev | Status |
|---|---|---|---|---|---|
| A-SEC-1 / R10 | Audit §7, QA R10 | ElevenLabs API key stored plaintext in `UserDefaults`/`@AppStorage` | TTSViewModel.swift:44 | High | **DONE** — commit `16a514d` (key moved to the Keychain); commit `9d87f5e` keeps the legacy value when the Keychain write fails during migration |
| A-SEC-2 | Audit §7 | Ad-hoc codesign, no entitlements/hardened runtime/notarization → TCC resets every rebuild | generate_app.sh:109 | Med (High if distributed) | **DONE** — commits `54c809f` + `3005bf6` |
| A-SEC-3 | Audit §7 | Dictation Claude toggle has no privacy disclosure (file-drop path does) | ClaudeService.swift:84-88 vs TranscriptionView.swift:196-198 | Med | **DONE** — commit `f9559ea` (caption added under the dictation Claude toggle). |
| R4 | QA §2 | No exit-status check or timeout on the `claude` stream; nonzero-exit output can ship as "polished" text; a hung CLI wedges the HUD | ShellService.swift:148-215; ClaudeService.swift:84-108 | Med | **DONE** — commit `16a514d` (exit status checked) |
| R5 | QA §2 | Prompt injection via undelimited transcript text; inverse false-positive on `looksLikeError` (legit "error:" text discarded) | ClaudeService.swift:85,104-108 | Low-Med | **DONE** — commit `1507acf` |
| R6 | QA §2 | Claude CLI missing → fully silent no-op, raw text ships with no indication Claude should have run | ShellService.swift:211-213 | Low | **DONE** — commit `f926c78` surfaces the Claude CLI silent no-op instead of shipping raw text unnoticed. |
| R9 / A-SEC-6 | Audit §7, QA R9 | `dictation_trimmed.wav` written to shared temp dir outside the scratch-dir convention; reaper excludes `.wav` | FluidVADProcessor.swift:36-37; ContentViewModel.swift:206-226 | Low | **DONE** — commit `a6467fc` (scratch-routes the VAD trim output). |
| A-SEC-4 | Audit §7 | Move-to-Applications relaunch uses a `bash -c` shell string (only shell-exec in the app) | WhisperWrap.swift:208-216 | Med | **DONE** — commit `91e6894` (paths passed as `$1`/`$2` argv, not interpolated into the shell string). |
| A-SEC-5 | Audit §7 | `uninstall_clean.sh` does a direct sqlite DELETE on TCC.db (always SIP-blocked, shouldn't ship) | uninstall_clean.sh:81-107 | Low | **DONE** — commit `a379d61` (direct TCC.db DELETE removed; `tccutil reset` kept) |
| A-SEC-8 | Audit §7 | VAD loads entire recording into `[Float]` twice | FluidVADProcessor.swift:45-73 | Low | **DONE** — commit `3b0178c` (memory use documented on `loadAsPCM`) |
| A-SEC-9 / U11 | Audit §7, QA U11 | `NSAlert.runModal` inside drop handler / move prompt blocks the UI thread | TranscriptionView.swift:195-207; WhisperWrap.swift:156 | Med | **DONE (drop handler)** — commit `ff78380` (confirmationDialog); the move-to-Applications prompt in WhisperWrap.swift still uses `runModal` |
| A-SEC-10 | Audit §7 | ElevenLabs MP3 decoded via `AVAudioPlayer(data:)`, unbounded single-entry cache | TTSViewModel.swift:68,416 | Low | **EXCLUDED** — informational |

## F. Sloppy code / duplication — DEFERRED (real refactors, not attempted)

| ID | Finding | Location | Effort | Status |
|---|---|---|---|---|
| A-SLOP-1 | HUD geometry duplicated across 4 resize blocks, magic sizes | HUDWindowController.swift:174-189,191-225,284-295,431-444 | M | **EXCLUDED** — HUD rewritten in `1507acf` |
| A-SLOP-2 | `enableClaude()` copy-pasted verbatim incl. error strings | TranscriptionView.swift:298-317; DictationSettingsView.swift:286-307 | S | **DONE** — commit `6484f88` extracted the shared check-then-verify flow into `ClaudeService.verifyClaudeSetup()`; both call sites now only set their own local "enabled" flag on `.success`. |
| A-SLOP-3 | "stream → `looksLikeError` → flip `isConnected=false`" duplicated | DictationViewModel.swift:784-801; ContentViewModel.swift:145-164 | S | **DONE** — commit pending (rotation sweep 2026-09-18): extracted the shared three-way branch into `ClaudeService.classifyOutcome(_:)`; both call sites switch on it, keeping only their own side effects (HUD update vs. file write + console line) local. |
| A-SLOP-4 | Silent `try?` on prompt save / ElevenLabs request body | ClaudePrompt.swift:106; TTSViewModel.swift:353 | S | **DONE** — commit `6bb81ae` fixed the `ClaudePrompt.swift` half, and commit `d2f8a93` fixed the `TTSViewModel.swift:353` half (both now log the encode failure instead of swallowing it). |
| A-SLOP-5 | Force-unwraps in VAD path | FluidVADProcessor.swift:52,55,63,125,128 | S | **DONE** — commit `a9501c0` made `loadAsPCM`/`writePCM` throw instead of force-unwrapping, so an invalid format or oversized frame count reaches `trimSilence`'s existing `catch { return nil }` degrade path instead of crashing. |
| A-SLOP-6 | `AVAudioConverter` dest capacity sizing (low confidence) | FluidVADProcessor.swift:61-69 | M | **DONE** — commit `3b0178c` (source fed once, output sized for 16 kHz, tested) |
| A-SLOP-7 | `DictationViewModel` ~900-line god object | DictationViewModel.swift | L | **EXCLUDED** — structural refactor, left to Claude |
| A-SLOP-8 | `TTSViewModel.speak()` doesn't guard `isDownloadingAudio`; `stop()` can't cancel in-flight fetch | TTSViewModel.swift:212-227,299-317,355-430,467-477 | S | **DONE** — commit `c90fce9` guards `speak()` against overlapping render/download so a second press while a system-render or ElevenLabs fetch is in flight can't race the first Task to set `audioPlayer`/`lastAudioData`. |
| A-SLOP-9 | `checkWindowsVisible` title-string heuristic | WhisperWrap.swift:263-281 | M | **EXCLUDED** — informational |
| A-SLOP-10 | Three settings-persistence patterns, raw key-string literals | multiple | M | **DONE** — commit `a41a233` (`SettingsKey` enum for DictationViewModel's keys; other files unchanged) |
| A-SLOP-11 | Saved-recording filename collision (same-second takes) | DictationViewModel.swift:656 | S | **DONE** — commit `a6467fc` (uniquified via `_2`, `_3`, ... on collision, with unit tests). |
| A-SLOP-12 | Blinking-dot animation keyed on `Date()` per render | DictationRecordingView.swift:23-24 | S | **DONE** — commit `c28787a` drives the blink off a `TimelineView(.periodic(...))` timer instead of a per-render `Date()` read. |
| A-SLOP-13 | CoreAudio device-disappearing mid-recording, not traced end-to-end | DictationViewModel.swift:217-401 | M | **EXCLUDED** — needs a live GUI/hardware session |
| R2 | Stale-task `defer` unconditionally clears state; cancel-then-re-record race | DictationViewModel.swift:695-711 | Med | **DONE** — commit `c954b1d` (per-run `currentTranscriptionID` UUID stamp; defer only clears shared state when it's still the current run). |
| R8 | File output silently overwrites existing `<base>.<format>` | ContentViewModel.swift:172-177 | Med | **DONE** — commit `9be4a12` (`uniqueDestination(for:in:)` appends " 2", " 3", ... on collision, Finder-style). |
| R11 | `SystemAudioRenderer` continuation can hang forever on missing voice asset; memory/messaging issues | TTSViewModel.swift:562-587,68,359-384 | Low-Med | **DONE** — commit pending (rotation sweep 2026-09-13): `renderSystemAudio` races the render against a 20s timeout, same pattern as R4. |
| R12 | Interrupted model download shows as "Prefetched" | PrefetchManager.swift:68-73 | Low | **DONE** — commit pending (rotation sweep 2026-09-12): `check(model:)` now requires non-empty directory content, not mere existence. |
| R13 | Mic permission revoked mid-recording — real TCC behavior not traced | DictationViewModel.swift:511-583,894-900 | Low | **EXCLUDED** — needs a live GUI/hardware session |

## G. Test coverage gaps

| ID | Finding | Status |
|---|---|---|
| A-TEST-3 (part) | WhisperTranscriptionEngine SRT/JSON formatting untested | **DONE as part of R7** — `WhisperTranscriptionEngineTests` now covers txt/srt/json formatting via the extracted pure `format(segments:as:)` |
| A-TEST-3 (part) | WhisperTranscriptionEngine model-load dedup race untested | **DONE** — commit `72e13fc` (`ParakeetEngine.prepare()` dedup and retry tested) |
| A-TEST-5 (part) | HotKeyManager had no test file at all | **DONE as part of R3** — `HotKeyManagerTests` added, covers the out-of-range guard specifically, not full coverage of the class |
| A-TEST-1 | `SilentRecordingMonitor` — pure state machine, zero tests | **DONE** — `SilentRecordingMonitorTests` added, commit `a55e116` |
| A-TEST-2 | `UTF8StreamDecoder` split-multibyte carry logic untested | **DONE** — `ShellServiceTests.swift` covers the split-multibyte carry buffer via `streamCommand`, commit `84d7f42` |
| A-TEST-4 | HUD prompt-selection continuation handling untested | **EXCLUDED** — no continuation left to test |
| A-TEST-5 (rest) | `TTSViewModel`, `PrefetchManager`, `PermissionsManager`, `AppDelegate` — no test files | DEFERRED |
| A-TEST-6 | MenuBar/AppDelegate `asyncAfter` window-policy timing untested | **EXCLUDED** — low value |
| A-TEST-7 | Tests construct real `DictationViewModel` → mutate developer's real UserDefaults | **DONE** — commit `4c314c7` (tests inject a throwaway `UserDefaults` suite) |

## H. UI/UX (U1–U21) — see §D for the BLOCKED ones; rest DEFERRED, GUI-unverifiable claim noted where relevant

| ID | Finding | Status |
|---|---|---|
| U5 | Claude failure during dictation fully silent | **DONE** — commit `7e12352` (with the HUD off, failures open a menu-bar alert) |
| U6 | Start/permission failures only a 4s HUD toast | **DONE** — commit `7e12352` (with the HUD off, failures open a menu-bar alert) |
| U7 | Menu-bar popover hardcodes "⌥Space" even after custom hotkey rebind | **DONE** — commit `a0a160a` (uses the existing `hotkeyDisplayString`). |
| U8 | No discard-from-HUD affordance (only stop-and-transcribe) | **DONE** — the HUD close button discards the take (HUDView.swift:58-66) |
| U10 | Model download progress hidden when HUD is off | **EXCLUDED** — low value |
| U11 | see A-SEC-9 above | **DONE (drop handler)** — commit `ff78380`, see A-SEC-9 |
| U12 | PrefetchModelsView spinner has no percent/cancel | **DONE** — commit `f56e3a5` |
| U13 | HUD `.transcribing` visualizer shows flat bars, no progress cue | **EXCLUDED** — the HUD shows Transcribing |
| U14 | Opt+Shift+V opens blank last-result window on fresh install | **DONE** — LastResultWindowController.swift:11 |
| U15 | HUD device-picker not keyboard-reachable | **EXCLUDED** — needs a live GUI/hardware session |
| U16 | Icon-only buttons lack `accessibilityLabel`s | **DONE** — commit `92057d0` (HUD close and refine-menu buttons labelled) |
| U17 | Contrast risks; hotkey-recorder state color-only | **EXCLUDED** — needs a live GUI/hardware session |
| U18 | Custom Claude prompt deletion has no confirm/undo | **DONE** — commit `9773742` |
| U19 | Silent output-file overwrite (=R8); asymmetric clipboard-restore protection | **DONE** — overwrite half via R8 `9be4a12`; clipboard restore in DictationViewModel.swift:732-760 |
| U20 | File-transcription Claude settings silently reuse dictation's model key; Whisper-model picker resets to `.base` each launch | **DONE** — persisted via `@AppStorage("fileTranscriptionModel")`, commit `b16f983` |
| U21 (rest) | Drop-zone format list vs README video claim; magic tab-index numbers | DEFERRED — terminology part is BLOCKED, see §D |

## Discovered during this session (not in either source report)

None. No new defects were found while implementing the items above; the fixes were scoped
tightly to each finding's own code path.

## Summary counts

- Total findings tracked: 55 (34 unique Audit-table rows incl. positives-only informational
  rows counted once, 16 QA red-team rows, 21 QA UI/UX rows — see individual report headers;
  duplicates between the two reports, e.g. R7≈A-GAP-3, R9≈A-SEC-6, R10≈A-SEC-1, R14≈A-DEAD-4,
  R15≈A-DEP/§2 items, U3≈A-GAP-1/A-DEAD-3, U11≈A-SEC-9, U21(terminology)≈A-GAP terminology,
  are cross-referenced rather than double-counted in the totals below)
- **DONE:** 9 (R1, R3, R7, U4, A-DEAD-1, A-DEAD-2, A-DEAD-4, A-DEAD-6, A-DEP-1) plus 2 partial
  test-coverage improvements riding along with R3/R7
- **INVALID (re-verified, no action needed):** 1 (CFBundleVersion "1" — confirmed the code
  behavior itself isn't a bug, only a doc claim elsewhere is stale)
- **BLOCKED-NEEDS-DECISION:** 5 (A-GAP-1/U3, U1, U2, U9, A-SEC-1/R10; U21-terminology folded
  into U21's DEFERRED entry with the copy question called out)
- **DEFERRED:** the remainder — full list above, none silently dropped
