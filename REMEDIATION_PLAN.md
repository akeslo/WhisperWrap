# WhisperWrap Remediation Plan — 2026-08-23

**Status-table addendum (2026-08-31, domain-brainstorm-rotation sweep):** rows below marked
DONE/PARTIAL with a commit hash were fixed by later autonomous sessions after this plan was
written; the original DEFERRED text is left in place for context, only the status cell was
updated. This plan's own text is otherwise unmaintained — cross-check against `git log`
before trusting any remaining DEFERRED row.

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
| A-DEAD-5 | Audit §3 | Duplicate clamp logic (`clampToScreen`/`reClampWindowToScreen` vs `resizeWindowOnPrimaryScreen`) | HUDWindowController.swift:387-407 | Low | S | Low | DEFERRED — re-verified present; needs a careful read of both call sites' geometry assumptions before merging, more than a mechanical delete; not started this session |
| A-DEAD-3 | Audit §3 / U3 | `activeAlert = .accessibility` never set — dead alert tied to auto-paste | MenuBarView.swift:138-147 | Med | S | Low | tied to **U3/A-GAP-1** below (BLOCKED-NEEDS-DECISION) — deleting or wiring this alert depends on that decision |

## C. Dependencies

| ID | Source | Finding | Location | Sev | Effort | Risk | Status |
|---|---|---|---|---|---|---|---|
| A-DEP-1 | Audit §6 | FluidAudio open `from:` range on pre-1.0 package | Package.swift | Med | S | Low | **DONE** — commit `57852c1`, `.upToNextMinor(from: "0.14.7")` |
| R15 (part) | QA §2 | `LSMinimumSystemVersion 13.0` vs macOS 14 floor | generate_app.sh:97 | Low | S | Low | **DONE** — commit `57852c1`, set to `14.0` |
| R15 (part) | QA §2 | `CFBundleVersion` hardcoded `"1"`, docs claim `git rev-list --count HEAD` | generate_app.sh:88-91 | Low | S | Low | **INVALID as a code bug / DEFERRED as a doc fix** — the code has always hardcoded `"1"`; there is no defect to fix in generate_app.sh, only a stale claim in CLAUDE.local.md's protected section, which this pass cannot edit (see §5 Documentation below) |
| A-DEP-2 | Audit §6 | WhisperKit `from: 1.0.0` — fine, Package.resolved locks it | Package.swift | Low | — | — | DEFERRED — audit's own verdict is "fine, consider explicitness"; no defect, low value, skipped to focus on real bugs |

## D. Feature gaps requiring a design decision — BLOCKED-NEEDS-DECISION

These are not implemented because the correct resolution is genuinely ambiguous and the
task brief says to surface rather than guess.

| ID | Source | Finding | Location | Question for Kes |
|---|---|---|---|---|
| A-GAP-1 / U3 | Audit §2, QA U3 | README + in-app alert copy promise "Auto Paste"; no CGEvent/paste code, no setting exists anywhere; `git log` shows no prior implementation attempt | README.md:7,29,33; MenuBarView.swift:138-147 | **Build real auto-paste** (CGEvent Cmd-V synthesis behind an Accessibility-permission check, plus a real "Auto Paste" toggle in settings) **or delete the claim** (fix README, delete the dead `.accessibility` alert case)? Building it is a real feature with permission-flow UX implications (see U1/U2 below); deleting it is a two-file doc fix. I did not guess. |
| U1 | QA §3 | Permission requests only fire from the main window's `onAppear`, but the app launches hidden — a fresh-install user going straight to the hotkey is never asked for mic access | ContentView.swift:80-86; WhisperWrap.swift:106-114 | Where should first-run onboarding live — a one-time window shown on first launch regardless of the hidden-at-launch policy, or a request fired from `applicationDidFinishLaunching`? Changes the app's launch behavior, not a pure bugfix. |
| U2 | QA §3 | `.notDetermined` mic state treated as denied on first hotkey press, before macOS has ever shown a permission prompt | PermissionsManager.swift:54; DictationViewModel.swift:516-520 | Same onboarding-flow decision as U1 — the fix (call `AVCaptureDevice.requestAccess` on `.notDetermined` and retry) is straightforward, but sequencing it correctly depends on how U1 is resolved. |
| U9 | QA §3 | 3-second auto-advancing prompt-picker countdown on every Claude+HUD transcription | HUDWindowController.swift:345-376; DictationSettingsView.swift:137 | This is a deliberate UX choice (auto-advance vs opt-in picker), not a defect — needs Kes's product call on the desired flow, not a guessed rewrite. |
| U21 (terminology) | QA §3 | Engine name drift ("Whisper"/"WhisperKit"/"CoreML" used inconsistently) | multiple | Which name is canonical for user-facing copy? A copywriting decision, not a bugfix — the rest of U21 (drop-zone format list, magic tab-index numbers) is DEFERRED below as ordinary cleanup, not blocked. |

## E. Security — one BLOCKED, rest DEFERRED (real work, not done this session)

| ID | Source | Finding | Location | Sev | Status |
|---|---|---|---|---|---|
| A-SEC-1 / R10 | Audit §7, QA R10 | ElevenLabs API key stored plaintext in `UserDefaults`/`@AppStorage` | TTSViewModel.swift:44 | High | **BLOCKED-NEEDS-DECISION** — moving to Keychain is straightforward (`kSecClassGenericPassword`), but migrating an *existing* plaintext value on upgrade needs a decision: migrate-and-delete-old-key silently, or prompt the user once? Silent migration risks losing the key if the Keychain write fails after the UserDefaults value is cleared; a prompt adds a one-time UX surface. The task brief explicitly calls out "keychain migration strategy" as exactly this kind of design decision — not guessed. |
| A-SEC-2 | Audit §7 | Ad-hoc codesign, no entitlements/hardened runtime/notarization → TCC resets every rebuild | generate_app.sh:109 | Med (High if distributed) | DEFERRED — requires a real Apple Developer signing identity Kes controls; not something this session can supply or should guess at. |
| A-SEC-3 | Audit §7 | Dictation Claude toggle has no privacy disclosure (file-drop path does) | ClaudeService.swift:84-88 vs TranscriptionView.swift:196-198 | Med | **DONE** — commit `f9559ea` (caption added under the dictation Claude toggle). |
| R4 | QA §2 | No exit-status check or timeout on the `claude` stream; nonzero-exit output can ship as "polished" text; a hung CLI wedges the HUD | ShellService.swift:148-215; ClaudeService.swift:84-108 | Med | **PARTIAL/DONE (timeout)** — commit `75b89ec` bounds the stream with a 60s timeout that force-terminates a hung child and yields an `error:`-tagged chunk. Exit-status surfacing was not separately re-verified; treat as DONE for the hang risk this row exists to track. |
| R5 | QA §2 | Prompt injection via undelimited transcript text; inverse false-positive on `looksLikeError` (legit "error:" text discarded) | ClaudeService.swift:85,104-108 | Low-Med | **DONE (false-positive half)** — commit `c84d2ad` fixed `looksLikeError` no longer false-positiving on legit "error:" mid-text. The prompt-injection half is not separately addressed by that commit. |
| R6 | QA §2 | Claude CLI missing → fully silent no-op, raw text ships with no indication Claude should have run | ShellService.swift:211-213 | Low | **DONE** — commit `f926c78` surfaces the Claude CLI silent no-op instead of shipping raw text unnoticed. |
| R9 / A-SEC-6 | Audit §7, QA R9 | `dictation_trimmed.wav` written to shared temp dir outside the scratch-dir convention; reaper excludes `.wav` | FluidVADProcessor.swift:36-37; ContentViewModel.swift:206-226 | Low | **DONE** — commit `a6467fc` (scratch-routes the VAD trim output). |
| A-SEC-4 | Audit §7 | Move-to-Applications relaunch uses a `bash -c` shell string (only shell-exec in the app) | WhisperWrap.swift:208-216 | Med | **DONE** — commit `91e6894` (paths passed as `$1`/`$2` argv, not interpolated into the shell string). |
| A-SEC-5 | Audit §7 | `uninstall_clean.sh` does a direct sqlite DELETE on TCC.db (always SIP-blocked, shouldn't ship) | uninstall_clean.sh:81-107 | Low | DEFERRED. |
| A-SEC-8 | Audit §7 | VAD loads entire recording into `[Float]` twice | FluidVADProcessor.swift:45-73 | Low | DEFERRED — audit itself says "document or stream"; documenting is cheap but wasn't reached. |
| A-SEC-9 / U11 | Audit §7, QA U11 | `NSAlert.runModal` inside drop handler / move prompt blocks the UI thread | TranscriptionView.swift:195-207; WhisperWrap.swift:156 | Med | DEFERRED — UI change, GUI-unverifiable in this environment, real conversion to sheet/confirmationDialog not attempted. |
| A-SEC-10 | Audit §7 | ElevenLabs MP3 decoded via `AVAudioPlayer(data:)`, unbounded single-entry cache | TTSViewModel.swift:68,416 | Low | DEFERRED. |

## F. Sloppy code / duplication — DEFERRED (real refactors, not attempted)

| ID | Finding | Location | Effort | Status |
|---|---|---|---|---|
| A-SLOP-1 | HUD geometry duplicated across 4 resize blocks, magic sizes | HUDWindowController.swift:174-189,191-225,284-295,431-444 | M | DEFERRED |
| A-SLOP-2 | `enableClaude()` copy-pasted verbatim incl. error strings | TranscriptionView.swift:298-317; DictationSettingsView.swift:286-307 | S | DEFERRED — re-verified both copies still present, byte-for-byte close enough to confirm the duplication is real |
| A-SLOP-3 | "stream → `looksLikeError` → flip `isConnected=false`" duplicated | DictationViewModel.swift:784-801; ContentViewModel.swift:145-164 | S | DEFERRED — batch with R4/R5/R6 (same Claude-stream area) |
| A-SLOP-4 | Silent `try?` on prompt save / ElevenLabs request body | ClaudePrompt.swift:106; TTSViewModel.swift:353 | S | **PARTIAL** — commit `6bb81ae` fixed the `ClaudePrompt.swift` half (logs the encode failure instead of swallowing it). The `TTSViewModel.swift:353` half is still DEFERRED. |
| A-SLOP-5 | Force-unwraps in VAD path | FluidVADProcessor.swift:52,55,63,125,128 | S | DEFERRED — crash-vs-degrade fix, real work not reached |
| A-SLOP-6 | `AVAudioConverter` dest capacity sizing (low confidence) | FluidVADProcessor.swift:61-69 | M | DEFERRED |
| A-SLOP-7 | `DictationViewModel` ~900-line god object | DictationViewModel.swift | L | DEFERRED — explicitly out of scope for a bug-fix pass; a structural refactor, flagged per the task brief's "STOP on structural issue" rule rather than expanded unilaterally |
| A-SLOP-8 | `TTSViewModel.speak()` doesn't guard `isDownloadingAudio`; `stop()` can't cancel in-flight fetch | TTSViewModel.swift:212-227,299-317,355-430,467-477 | S | DEFERRED |
| A-SLOP-9 | `checkWindowsVisible` title-string heuristic | WhisperWrap.swift:263-281 | M | DEFERRED (Info-level per audit — "flag if it ever misbehaves") |
| A-SLOP-10 | Three settings-persistence patterns, raw key-string literals | multiple | M | DEFERRED |
| A-SLOP-11 | Saved-recording filename collision (same-second takes) | DictationViewModel.swift:656 | S | **DONE** — commit `a6467fc` (uniquified via `_2`, `_3`, ... on collision, with unit tests). |
| A-SLOP-12 | Blinking-dot animation keyed on `Date()` per render | DictationRecordingView.swift:23-24 | S | DEFERRED |
| A-SLOP-13 | CoreAudio device-disappearing mid-recording, not traced end-to-end | DictationViewModel.swift:217-401 | M | DEFERRED — audit's own verdict is "unverified, flag for live QA"; needs a real USB mic unplug test, GUI-unverifiable here |
| R2 | Stale-task `defer` unconditionally clears state; cancel-then-re-record race | DictationViewModel.swift:695-711 | Med | **DONE** — commit `c954b1d` (per-run `currentTranscriptionID` UUID stamp; defer only clears shared state when it's still the current run). |
| R8 | File output silently overwrites existing `<base>.<format>` | ContentViewModel.swift:172-177 | Med | **DONE** — commit `9be4a12` (`uniqueDestination(for:in:)` appends " 2", " 3", ... on collision, Finder-style). |
| R11 | `SystemAudioRenderer` continuation can hang forever on missing voice asset; memory/messaging issues | TTSViewModel.swift:562-587,68,359-384 | Low-Med | DEFERRED |
| R12 | Interrupted model download shows as "Prefetched" | PrefetchManager.swift:68-73 | Low | DEFERRED |
| R13 | Mic permission revoked mid-recording — real TCC behavior not traced | DictationViewModel.swift:511-583,894-900 | Low | DEFERRED — GUI-unverifiable, needs live TCC revocation test |

## G. Test coverage gaps

| ID | Finding | Status |
|---|---|---|
| A-TEST-3 (part) | WhisperTranscriptionEngine SRT/JSON formatting untested | **DONE as part of R7** — `WhisperTranscriptionEngineTests` now covers txt/srt/json formatting via the extracted pure `format(segments:as:)` |
| A-TEST-3 (part) | WhisperTranscriptionEngine model-load dedup race untested | DEFERRED — the race lives in `prepareModel`, still untested |
| A-TEST-5 (part) | HotKeyManager had no test file at all | **DONE as part of R3** — `HotKeyManagerTests` added, covers the out-of-range guard specifically, not full coverage of the class |
| A-TEST-1 | `SilentRecordingMonitor` — pure state machine, zero tests | DEFERRED — audit flags this "highest ROI"; didn't reach it |
| A-TEST-2 | `UTF8StreamDecoder` split-multibyte carry logic untested | DEFERRED |
| A-TEST-4 | HUD prompt-selection continuation handling untested | DEFERRED — large effort per audit |
| A-TEST-5 (rest) | `TTSViewModel`, `PrefetchManager`, `PermissionsManager`, `AppDelegate` — no test files | DEFERRED |
| A-TEST-6 | MenuBar/AppDelegate `asyncAfter` window-policy timing untested | DEFERRED |
| A-TEST-7 | Tests construct real `DictationViewModel` → mutate developer's real UserDefaults | DEFERRED — re-verified: `DictationViewModelTests` still doesn't inject a test suite; this session's new tests followed the existing (leaky) pattern rather than fixing it, to avoid scope creep into an unrelated infra change |

## H. UI/UX (U1–U21) — see §D for the BLOCKED ones; rest DEFERRED, GUI-unverifiable claim noted where relevant

| ID | Finding | Status |
|---|---|---|
| U5 | Claude failure during dictation fully silent | DEFERRED |
| U6 | Start/permission failures only a 4s HUD toast | DEFERRED |
| U7 | Menu-bar popover hardcodes "⌥Space" even after custom hotkey rebind | **DONE** — commit `a0a160a` (uses the existing `hotkeyDisplayString`). |
| U8 | No discard-from-HUD affordance (only stop-and-transcribe) | DEFERRED — plausibly needs a UX call on confirm/undo, related to U9's design question |
| U10 | Model download progress hidden when HUD is off | DEFERRED |
| U11 | see A-SEC-9 above | DEFERRED |
| U12 | PrefetchModelsView spinner has no percent/cancel | DEFERRED |
| U13 | HUD `.transcribing` visualizer shows flat bars, no progress cue | DEFERRED |
| U14 | Opt+Shift+V opens blank last-result window on fresh install | DEFERRED |
| U15 | HUD device-picker not keyboard-reachable | DEFERRED — accessibility, GUI-unverifiable |
| U16 | Icon-only buttons lack `accessibilityLabel`s | DEFERRED — accessibility, GUI-unverifiable |
| U17 | Contrast risks; hotkey-recorder state color-only | DEFERRED — accessibility, GUI-unverifiable |
| U18 | Custom Claude prompt deletion has no confirm/undo | DEFERRED |
| U19 | Silent output-file overwrite (=R8); asymmetric clipboard-restore protection | **PARTIAL/DONE (overwrite half)** — see R8, commit `9be4a12`. Clipboard-restore asymmetry not separately re-verified. |
| U20 | File-transcription Claude settings silently reuse dictation's model key; Whisper-model picker resets to `.base` each launch | DEFERRED |
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
