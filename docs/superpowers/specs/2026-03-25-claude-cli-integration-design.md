# Claude CLI Integration for WhisperWrap

## Overview

Add optional Claude CLI processing to WhisperWrap's transcription pipeline. After Whisper produces raw text, users can pipe it through Claude for cleanup, summarization, or custom processing. Uses the `claude` CLI (OAuth login, no API key needed) via shell execution, matching the app's existing pattern for external tools.

Available in both dictation and file transcription flows.

## ClaudeService

New file: `Sources/WhisperWrap/ClaudeService.swift`

Wraps all Claude CLI interaction:

- **`checkAvailability() -> String?`** — runs `which claude`, returns path or nil.
- **`authenticate()`** — launches `claude` to trigger OAuth login flow (opens browser). Monitors process for success.
- **`process(text: String, prompt: String) -> AsyncStream<String>`** — runs `echo "<text>" | claude --print "<prompt>"`, streams stdout line-by-line via AsyncStream.
- **`isConnected: Bool`** — stored in UserDefaults. Set true after first successful auth. Rechecked if a call fails.

Follows the same pattern as `PythonEnvManager` — a service managing an external tool dependency.

## Prompt Management

### Built-in Presets (3)

1. **Clean Up** — "Fix grammar, punctuation, and remove filler words. Keep the original meaning intact. Return only the cleaned text."
2. **Summarize** — "Condense this into key points. Be concise."
3. **Action Items** — "Extract action items and to-dos as a bulleted list."

### Custom Prompts

- Text field for writing a custom prompt.
- "Save" button stores it with a user-given name.
- Saved prompts appear in the dropdown alongside presets, with a delete option.
- Storage: UserDefaults as an array of `{name: String, prompt: String, isBuiltin: Bool}`.

### Selection

- One dropdown in Dictation Settings, one in Transcription View.
- Selected prompt stored per-context (dictation and file transcription can have different active prompts).

## Settings UI

### Dictation Settings (`DictationSettingsView.swift`)

New section: "Claude Processing"

- **Toggle:** "Process with Claude" (off by default).
- **First-time enable gate:** toggle on → check CLI availability → if not found, show install instructions → if found, run auth flow → on success, enable the section and set `isConnected = true`.
- **Dropdown:** prompt selector (presets + saved customs).
- **Text field:** custom prompt input with Save button.
- **Status indicator:** connection state.

### Transcription View (`TranscriptionView.swift`)

Same controls (toggle, dropdown, custom prompt) below existing transcription options. Independent toggle and prompt selection from dictation.

### State Management

Claude-related settings can live on existing ViewModels or a shared `ClaudeSettings` ObservableObject, depending on coupling.

## Processing Flow

### Dictation

1. User presses hotkey → records → Whisper transcribes → raw text.
2. If "Process with Claude" is enabled:
   - HUD switches to "Processing with Claude..." state.
   - `ClaudeService.process(text:prompt:)` starts streaming.
   - HUD updates in real-time with streaming text.
   - On completion, final text → clipboard + auto-paste.
3. If disabled: current behavior unchanged.

### File Transcription

1. Whisper transcribes file → raw text.
2. If "Process with Claude" is enabled:
   - Progress label updates to "Processing with Claude..."
   - Streaming output shown in transcription result area.
   - Final output replaces raw transcription in the output file.
3. If disabled: current behavior unchanged.

## HUD Changes

`HUDWindowController.swift`:

- New state: `.processingWithClaude`
- Text area becomes scrollable, updates as lines stream in.
- Same floating window style.

## Error Handling

- **CLI not found / auth expired / network error:** fall back to raw transcription, show brief error in HUD. Never block the user.
- **Streaming timeout (30s):** cancel, use raw transcription, notify user.

## Files to Create/Modify

### New Files
- `Sources/WhisperWrap/ClaudeService.swift` — CLI wrapper service

### Modified Files
- `DictationSettingsView.swift` — add Claude Processing section
- `DictationViewModel.swift` — add claude toggle/prompt settings, call ClaudeService after transcription
- `TranscriptionView.swift` — add Claude Processing controls
- `ContentViewModel.swift` — integrate ClaudeService into file transcription flow
- `HUDWindowController.swift` — add `.processingWithClaude` state with streaming text display
