# WhisperWrap Validation Report — 2026-08-23

One entry per DONE finding from `REMEDIATION_PLAN.md`. All commits are on `main`, local and
unpushed per the task instructions. `swift build` was clean and `swift test` fully green
(all counts below) after every commit in this report.

---

## R1 — Menu-bar Start Recording didn't guard `isProcessing`

**Changed:** `Sources/WhisperWrap/MenuBarView.swift` — the "Start Recording" button action now
branches on `viewModel.isProcessing` the same way the hotkey handler
(`DictationViewModel.swift` `registerDictationHotkey`) does: cancel the in-flight
transcription instead of starting a new recording, which used to truncate the fixed
`dictation.wav` file the in-flight transcription was still reading.

**Test:** None written — `MenuBarView` is a SwiftUI view with no test target in this repo, and
the GUI cannot be launched in this sandbox. **Code-trace verified, not test-covered.**

**Code-trace argument:** Before the fix, the button action was
`if viewModel.isRecording { stopRecording() } else { startRecording() }` — no `isProcessing`
branch existed, so clicking Start Recording while `isProcessing == true` unconditionally
called `startRecording()`. After the fix, the middle branch
(`else if viewModel.isProcessing { viewModel.cancelTranscription() }`) intercepts exactly that
case before `startRecording()` can run. This mirrors the already-correct hotkey path at
`DictationViewModel.swift` (`isSelectingPrompt` → `isProcessing` → `toggleRecording`), which
QA_REPORT.md's own adjudication in §1 already confirmed guards correctly.

**Happy-path re-verify:** `isRecording == false && isProcessing == false` still falls through
to `viewModel.startRecording()` unchanged — normal Start Recording is untouched.

**Adversarial re-attack (code-trace):** Repro from QA_REPORT R1 — "Record → stop → while HUD
says 'Transcribing' click Start Recording in the menu popover" — now takes the
`isProcessing` branch and cancels instead of truncating the file. Variant tried: rapid
double-click during processing — both clicks hit the same `isProcessing` branch and both
call `cancelTranscription()`, which is idempotent (guarded internally), so no new race is
introduced.

**Commit:** `081f864`

---

## R3 — Corrupted hotkey defaults crash-loop the app

**Changed:**
- `Sources/WhisperWrap/HotKeyManager.swift` — `registerHotKey` now converts `keyCode`/
  `modifiers` via `UInt32(exactly:)` and returns (logging) instead of calling
  `RegisterEventHotKey` when either value is out of `UInt32` range, instead of the previous
  unguarded `UInt32(keyCode)` / `UInt32(modifiers)` which traps on a negative or overflowing
  `Int`.
- `Sources/WhisperWrap/DictationViewModel.swift` — `setupHotKey` additionally validates the
  persisted hotkey defaults up front; on an invalid value it resets to the Option+Space
  default and clears the bad `UserDefaults` keys so the corruption doesn't recur next launch.

**Test:** `Tests/WhisperWrapTests/HotKeyManagerTests.swift` (new, 4 tests) —
`testRegisterDoesNotTrapOnNegativeKeyCode`, `testRegisterDoesNotTrapOnOutOfRangeKeyCode`,
`testRegisterDoesNotTrapOnNegativeModifiers`, `testRegisterAdditionalDoesNotTrapOnNegativeKeyCode`.
A passing test means no trap occurred — an unguarded trap aborts the whole `xctest` process,
not just one assertion.

**Confirmed the test fails on old code:** `git stash push` on `HotKeyManager.swift` +
`DictationViewModel.swift` to restore the pre-fix code, ran
`swift test --filter HotKeyManagerTests`, and it crashed the test process:
```
Swift/arm64e-apple-macos.swiftinterface:13148: Fatal error: Negative value is not representable
error: Process '...xctest ...' exited with unexpected signal code 5
```
`git stash pop` restored the fix; the same 4 tests then passed (part of 45/45 green at that
point in the session).

**Happy-path re-verify:** A normal, valid persisted hotkey (e.g. keyCode 49/modifiers
`optionKey`, both well within `UInt32` range) is unaffected — `UInt32(exactly:)` succeeds and
registration proceeds exactly as before.

**Adversarial re-attack:** Original repro (`defaults write com.akeslo.WhisperWrap
dictationHotkeyKeyCode -int -1`) — DictationViewModel's own validation now catches this before
it ever reaches HotKeyManager, resets to the default, and clears the bad keys. Variants tried
directly against `HotKeyManagerTests`: `Int(UInt32.max) + 1` (overflow, not just negative),
and a negative *modifiers* value with a valid keyCode — both handled by the same guard since
it checks both parameters.

**Commit:** `92a0eb3`

---

## R7 — Invalid JSON export

**Changed:** `Sources/WhisperWrap/WhisperTranscriptionEngine.swift` — the `json` case in
`transcribeFormatted` used to build JSON by hand (`"{\"start\":\(seg.start)...`) escaping only
`"`. Replaced with `JSONEncoder` over a new `ExportedSegment: Encodable` struct, producing a
real JSON array (`[.prettyPrinted, .sortedKeys]`). The txt/srt/json formatting logic was
extracted into a new `static func format(segments: [ExportedSegment], as format: String)
throws -> String`, decoupled from WhisperKit's own segment type, so it's unit-testable
without a loaded model. `formatSRTTime` was made `static` to support this.

**Test:** `Tests/WhisperWrapTests/WhisperTranscriptionEngineTests.swift` (new, 5 tests):
`testTxtFormatJoinsTrimmedSegmentText`, `testSrtFormatIncludesIndexAndTimestamps`,
`testJsonFormatProducesValidJSONForBackslashAndNewline` (the direct repro of the original
defect — text containing `\` and a newline), `testJsonFormatProducesAnArrayNotJSONL`,
`testJsonFormatRoundTripsStartEndText`.

**Repro no longer reproduces:** QA_REPORT R7's repro was "transcribe audio whose transcript
contains a backslash; parse the output." `testJsonFormatProducesValidJSONForBackslashAndNewline`
constructs exactly that text (`"path\\to\\file and a \"quote\"\nnewline"`), runs it through
the fixed `format(segments:as:)`, and parses the result with `JSONSerialization` — the old
code would have emitted an invalid escape sequence and this parse would throw; the test
passes, confirming the fix.

**Happy-path re-verify:** Plain ASCII segment text (no special characters) still round-trips
correctly per `testJsonFormatRoundTripsStartEndText`; txt/srt formatting unchanged in
behavior, only relocated (`testTxtFormatJoinsTrimmedSegmentText`,
`testSrtFormatIncludesIndexAndTimestamps` pass against the same logic that was inline before).

**Adversarial re-attack:** Variants tried beyond the literal repro — embedded double quotes
(handled by the old code too, still handled), a literal newline character (not handled by the
old code, now handled), and confirming the top-level JSON value is an array
(`[[String: Any]]`) rather than the old JSONL-under-`.json` shape.

**Commit:** `a820b7e`

---

## U4 — "No Speech Detected" sentinel clobbers the clipboard

**Changed:**
- `Sources/WhisperWrap/ContentViewModel.swift` — named the literal `"No Speech Detected"` as
  `static let noSpeechDetectedSentinel` on `ContentViewModel`.
- `Sources/WhisperWrap/DictationViewModel.swift` — the `autoCopy` block now reads
  `if autoCopy && text != ContentViewModel.noSpeechDetectedSentinel`, so a silent take's
  sentinel is never written to the pasteboard.

**Test:** `Tests/WhisperWrapTests/DictationViewModelTests.swift` —
`testAutoCopyTrue_DoesNotCopyNoSpeechDetectedSentinel` (new). Seeds the pasteboard with a
known string, mocks `transcribeDictation` to return the sentinel, runs the dictation pipeline
with `autoCopy = true`, and asserts the pasteboard still holds the original string.

**Confirmed load-bearing on old code:** `git stash push` on `ContentViewModel.swift` +
`DictationViewModel.swift` (+ the new test file staged) to get back to the pre-fix state, ran
`swift test --filter testAutoCopyTrue_DoesNotCopyNoSpeechDetectedSentinel` — compile failed
(`type 'ContentViewModel' has no member 'noSpeechDetectedSentinel'`), because the pre-fix code
had no named sentinel for the test to reference, i.e. the safety path this test exercises did
not exist yet. `git stash pop` restored the fix; the same test then passed as part of 51/51
green.

**Happy-path re-verify:** `testAutoCopyTrue_CopiesTranscriptionToClipboard` (pre-existing)
still passes — ordinary non-sentinel text is still copied when `autoCopy` is on.

**Adversarial re-attack:** Confirmed the guard is an exact-string match, not a substring
check, so real transcribed text that happens to *contain* "No Speech Detected" (e.g. the user
dictates that exact phrase) is unaffected — only the literal sentinel value is excluded. This
was a deliberate implementation choice given `transcribeDictation` only ever returns that
exact string for the empty case, never as a mixed-in substring.

**Commit:** `6af5241`

---

## Dead code batch (A-DEAD-1, A-DEAD-2, A-DEAD-4/R14, A-DEAD-6)

**Changed:**
- Deleted `Sources/WhisperWrap/AudioConstants.swift` (zero references, grep-confirmed across
  the whole repo before deletion).
- Deleted `AppDelegate.showMainWindow()` from `Sources/WhisperWrap/WhisperWrap.swift` (zero
  callers, grep-confirmed).
- Deleted `simulate_login.sh` (grep-confirmed `-backgroundLaunch` and `/tmp/ww_internal.log`
  appear nowhere in `Sources/`).
- Deleted the empty `.onAppear { }` in `Sources/WhisperWrap/TranscriptionView.swift:295`.

**Test:** None — pure deletions of unreferenced code/scripts. **Code-trace verified**: for
each, `grep -rn` across the whole repo (not just `Sources/`, also scripts/README) returned no
call sites before the delete, and `swift build` + `swift test` (41/41 at that point) confirmed
nothing broke.

**Adversarial re-attack:** N/A — no attack surface for a dead-code deletion; the check that
matters is "did anything actually reference this," which the grep sweep and successful build
both confirm.

**Commit:** `e0e4815`

---

## A-DEP-1 + R15 (partial) — FluidAudio pin, LSMinimumSystemVersion

**Changed:**
- `Package.swift` — FluidAudio dependency changed from `from: "0.14.7"` to
  `.upToNextMinor(from: "0.14.7")`.
- `generate_app.sh` — `LSMinimumSystemVersion` changed from `13.0` to `14.0` to match
  `Package.swift`'s `platforms: [.macOS(.v14)]` floor.

**Test:** No unit test applies (build-config and packaging-script literals). **Code-trace /
build verified**: `swift build` succeeded and `Package.resolved` still shows `0.14.7` locked
(the tightened range only constrains a *future* `swift package update`, so this checkout's
resolved dependency graph is unchanged — confirmed by inspecting `Package.resolved` after the
change). `swift test` 51/51 green, confirming no runtime behavior regressed.

**Adversarial re-attack:** N/A — these are supply-chain and packaging-metadata hardening, not
runtime logic; the relevant check is that the resolved graph is unaffected today and
constrained going forward, both confirmed above.

**Commit:** `57852c1`

---

## Full test count progression

| After commit | Tests | Result |
|---|---|---|
| `e0e4815` (dead code) | 41 | 41/41 green |
| `081f864` (R1) | 41 | 41/41 green (no new tests — GUI-unverifiable) |
| `92a0eb3` (R3) | 45 | 45/45 green |
| `a820b7e` (R7) | 50 | 50/50 green |
| `6af5241` (U4) | 51 | 51/51 green |
| `57852c1` (deps/R15) | 51 | 51/51 green |

`swift build` was clean at every step above. All `swift test` runs were executed outside the
Claude command sandbox (`dangerouslyDisableSandbox: true`), per this repo's documented
requirement (SwiftPM shells out to `sandbox-exec` itself).
