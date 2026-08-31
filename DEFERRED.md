# WhisperWrap — Deferred Findings — 2026-08-23

**Addendum (2026-08-31):** several items named below as deferred/not-reached have since been
fixed by later autonomous commits — R2, R4 (timeout half), R8/U19 (overwrite half), R9/A-SEC-6,
A-SEC-3, A-SEC-4, A-SLOP-4 (ClaudePrompt half), A-SLOP-11, and U7. See `REMEDIATION_PLAN.md`
for the per-item commit hashes; this file's prose below is left as written and is no longer
fully current.

Everything here is a valid finding from `AUDIT.md`/`QA_REPORT.md`, re-verified against
current code, that was **not** fixed in this remediation pass. Grouped by reason. Full
per-item table with IDs/locations/severity is in `REMEDIATION_PLAN.md`; this file adds the
"why" and "what next" that plan's table rows summarize tersely.

## Out of scope: needs a design decision from Kes

These are recorded as BLOCKED-NEEDS-DECISION in `REMEDIATION_PLAN.md` §D, not implemented as
a guess:

1. **Auto-paste (A-GAP-1 / U3 / A-DEAD-3).** README and in-app copy promise it; no code exists;
   `git log` shows no prior attempt. Two legitimate resolutions with different scope (build a
   real CGEvent-based paste feature with an Accessibility-permission flow, vs. delete the
   claim and the dead alert case) — **recommended next step:** ask Kes which direction, then
   either a focused feature-dev session (if build) or a two-file doc fix (if delete).
2. **First-run permission flow (U1, U2).** Fixing the immediate bug (request mic access on
   `.notDetermined` instead of treating it as denied) is easy; but *where* that request should
   live given the app launches hidden is a product decision about onboarding UX. **Recommended
   next step:** decide whether first-run gets a one-time onboarding window or a launch-time
   request, then implement both U1 and U2 together (they share the same code path).
3. **Claude prompt-picker countdown (U9).** Auto-advance-with-countdown vs. opt-in picker is a
   product choice, not a defect. **Recommended next step:** Kes's call on desired flow.
4. **ElevenLabs Keychain migration (A-SEC-1 / R10).** The Keychain move itself is
   straightforward; migrating an *existing* plaintext value safely (silent migrate-and-delete
   vs. one-time user-facing prompt) is the open question, and it's the single most-flagged
   security finding in both reports. **Recommended next step:** decide the migration UX, then
   implement — this should be one of the very next things done given its severity.
5. **Terminology ("Whisper" vs "WhisperKit" vs "CoreML") in U21.** A copywriting decision.
   **Recommended next step:** pick one term for user-facing copy; the rest of U21 (drop-zone
   format list, magic tab-index numbers) can be cleaned up independently of this.

## Out of scope: real work not attempted this session (time-boxed out)

Severity-ordered. None of these are ambiguous — they just weren't reached given the session's
time budget against a ~55-item backlog. Each is a good next PR-sized unit of work.

- **R4/R5/R6 + A-SLOP-3 (Claude stream hardening, Med).** No exit-status check or timeout on
  the `claude` CLI stream; a hung process wedges the HUD; prompt injection via undelimited
  transcript text; `looksLikeError` false-positives on legitimate text containing "error:".
  These four all live in the same two files (`ShellService.swift`, `ClaudeService.swift`) and
  should be fixed together — recommend a dedicated session scoped to just this area, since it
  touches both the dictation and file-transcription call sites and needs careful async
  timeout plumbing.
- **R2 (Med).** Stale-task `defer` race on cancel-then-immediately-re-record. Needs task-
  identity comparison in the `defer` block; timing-dependent, should be paired with a test
  that can force the race deterministically (e.g. injectable clock/task hooks) rather than a
  flaky timing-based test.
- **R8 / A-SEC-6 / R9 (Med/Low, data-loss + hygiene).** Silent output-file overwrite on repeat
  transcription; `dictation_trimmed.wav` written outside the scratch-dir convention and
  excluded from the reaper. Both straightforward, good quick-win candidates for the next pass.
- **A-SEC-4 (Med).** Move-to-Applications relaunch uses a `bash -c` shell string — the only
  shell-exec in the app. Fix is mechanical (two `Process` argv calls + verify-before-delete)
  but wasn't reached.
- **A-SLOP-1/2/4/5/8/10/11/12 (mostly S/M).** HUD geometry duplication, `enableClaude()`
  duplication, silent `try?` on persistence, VAD force-unwraps, TTS double-invocation guard,
  settings-key centralization, filename collision, blinking-dot timing. All individually small;
  recommend batching into one cleanup session per the audit's own §4 framing.
- **A-SLOP-7 (L, structural).** `DictationViewModel` is a ~900-line god object. Per the task
  brief's explicit instruction, a structural finding uncovered mid-fix should be reported, not
  expanded into unilaterally. This one was already flagged by the audit itself, not newly
  discovered, so it's recorded here rather than as a "Discovered" item — no minimal safe fix
  exists for a structural sizing complaint, so nothing was attempted.
- **A-SEC-2 (Med/High if distributed).** Ad-hoc codesigning, no entitlements/hardened runtime.
  Needs a real Apple Developer signing identity that only Kes can supply — not implementable
  by an agent regardless of time budget.
- **A-SEC-5, A-SEC-8, A-SEC-9/U11, A-SEC-10, R11, R12** — all valid, all deferred for time.
- **U5, U6, U7, U8, U10, U12, U13, U14, U18, U19, U20** — UI/UX findings not reached. U7
  (hardcoded "⌥Space" hint) is flagged as the easiest next pickup: one line, no design
  decision needed, use the persisted hotkey's own display string instead of the literal.

## GUI-unverifiable in this environment

The GUI cannot be launched in this sandbox (confirmed by both source reports and this
session). These require live interaction or real system-state manipulation to verify even
after a code fix is written, so implementing them here would produce an unverified change:

- **U15, U16, U17 (accessibility).** VoiceOver traversal, keyboard reachability, contrast —
  all need a live accessibility inspector pass.
- **R13.** Mic permission revoked mid-recording via real TCC state — needs a live System
  Settings toggle during an active recording.
- **A-SLOP-13.** CoreAudio device disappearing mid-recording — needs a live USB mic unplug
  test; audit's own verdict was already "unverified."
- **A-SLOP-9.** `checkWindowsVisible` title-string heuristic brittleness across OS updates —
  inherently only observable "if it ever misbehaves" on a real OS update, per the audit.

**Recommended next step for all of the above:** a future session with an interactive macOS
session (not this sandboxed environment) should build the app via `./generate_app.sh`, launch
it, and work through U15-U17 and R13 as a dedicated live-QA pass.

## Explicitly not a defect (re-verified INVALID)

- **CFBundleVersion hardcoded "1" (part of R15).** `generate_app.sh` has always hardcoded
  `CFBundleVersion` to the literal `"1"` — there is no code regression here to fix; the only
  stale artifact is CLAUDE.local.md's claim (outside this repo, in the parent Scrypting
  container's protected-section rules) that it's `git rev-list --count HEAD`. That claim
  cannot be corrected by this pass because it lives inside CLAUDE.local.md's protected
  `<!-- /protected -->` section which this task was instructed not to touch. **Recommended
  next step:** flag to Kes directly (outside this repo) that the claim should be corrected or
  the versioning scheme actually implemented, whichever he prefers.

## Info-only, no action needed

- **A-GAP-6** (no TODO/FIXME markers — informational, not a gap).
- **A-SLOP-14** (three concurrent timers while recording — audit's own verdict: "acceptable,
  noted for profiling").
- **A-DEP-2, A-DEP-3** (WhisperKit range is fine per audit; swift-argument-parser is
  correctly noted as transitive, not a direct dep — no action implied).
- **R16, U22** (blue-team/red-team positives and UI/UX positives — nothing to fix).
