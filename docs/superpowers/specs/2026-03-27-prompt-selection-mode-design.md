# Prompt Selection Mode — Design Spec

## Overview

Add an optional prompt-selection step to the dictation flow. When enabled, a 5-second interactive prompt picker appears in the HUD after transcription completes and before Claude processing begins. The user can tap a prompt pill, enter custom text, or let the timer auto-select the default.

## Feature Flag

- **UserDefaults key:** `dictationPromptSelectionMode`
- **Type:** `Bool`, default `false`
- **UI:** Toggle in `DictationSettingsView`, visible only when Claude processing is enabled
- **Behavior when disabled:** Current flow preserved — uses `selectedClaudePromptID` directly

## HUD State Addition

New case `HUDStatus.selectingPrompt` inserted between `.transcribing` and `.processingWithClaude`.

### Layout (selectingPrompt state)

```
┌──────────────────────────────────────────────────┐
│ 🧠  Select prompt                            ✕   │
│                                                  │
│ [Polish] [Summarize] [Action Items] [Custom...]  │
│                                                  │
│ ████████████░░░░░░░░  (progress bar, shrinking)  │
└──────────────────────────────────────────────────┘
```

- **Icon:** Purple brain (matches `.processingWithClaude`)
- **Pills:** Horizontal `ScrollView` of prompt name buttons. One pill per entry from `ClaudePromptManager.allPrompts`. Default prompt (matching `selectedClaudePromptID`) is pre-highlighted with a distinct border/fill.
- **"Custom..." pill:** Last pill. Tapping reveals an inline `TextField` replacing the pill row. Pressing Enter submits the custom text as the prompt.
- **Progress bar:** Thin (~4px), below the pills. Starts full width, shrinks to zero over 5 seconds. Purple fill matching the brain icon color.
- **Window size:** Width 450–500px (same as current), height ~130px (up from 80px base).

### Interactions

| Action | Result |
|--------|--------|
| Tap a prompt pill | Immediately selects that prompt, cancels timer, transitions to `.processingWithClaude` |
| Tap "Custom..." | Shows inline text field, pauses timer |
| Press Enter in custom field | Uses entered text as prompt, transitions to `.processingWithClaude` |
| Press Escape in custom field | Returns to pill view, resumes timer |
| Timer expires (5s) | Auto-selects the default prompt (`selectedClaudePromptID`), transitions to `.processingWithClaude` |
| Tap close (X) | Cancels Claude processing entirely, hides HUD |

## Data Flow

### HUDState Changes

New published properties on `HUDState`:

```swift
@Published var availablePrompts: [ClaudePrompt] = []
@Published var defaultPromptID: UUID? = nil
@Published var countdownProgress: Double = 1.0   // 1.0 → 0.0 over 5s
@Published var isEnteringCustomPrompt: Bool = false
@Published var customPromptText: String = ""
```

### HUDWindowController Changes

New method:

```swift
func showPromptSelection(
    prompts: [ClaudePrompt],
    defaultID: UUID
) async -> PromptSelectionResult
```

**`PromptSelectionResult`** enum:
```swift
enum PromptSelectionResult {
    case selected(ClaudePrompt)    // User tapped a pill or timer expired
    case custom(String)            // User entered custom text
    case cancelled                 // User closed HUD
}
```

Implementation uses `AsyncStream` or `CheckedContinuation` to bridge the UI callback to async/await. A `Timer` drives `countdownProgress` from 1.0 to 0.0 over 5 seconds. On expiry, the continuation resumes with the default prompt.

### DictationViewModel Changes

In `transcribe()`, after getting transcribed text, before Claude processing:

```swift
// Existing: check claudeEnabled
if claudeEnabled, let claudeService, let claudePromptManager, ... {

    // NEW: prompt selection mode
    let prompt: ClaudePrompt
    if promptSelectionMode {
        HUDWindowController.shared.setStatus(.selectingPrompt)
        let result = await HUDWindowController.shared.showPromptSelection(
            prompts: claudePromptManager.allPrompts,
            defaultID: selectedClaudePromptID ?? ClaudePrompt.builtinPolish.id
        )
        switch result {
        case .selected(let p):
            prompt = p
        case .custom(let text):
            prompt = ClaudePrompt(id: UUID(), name: "Custom", prompt: text, isBuiltin: false)
        case .cancelled:
            // Skip Claude processing, proceed to copy/paste
            break
        }
    } else {
        // Existing behavior: use selectedClaudePromptID
        prompt = claudePromptManager.allPrompts.first(where: { $0.id == promptID })!
    }

    HUDWindowController.shared.setStatus(.processingWithClaude)
    let stream = claudeService.process(text: text, prompt: prompt.prompt, model: selectedClaudeModel)
    // ... existing streaming logic
}
```

### DictationSettingsView Changes

New toggle below the existing Claude settings, only visible when `claudeEnabled`:

```swift
Toggle("Prompt selection on each use", isOn: $viewModel.promptSelectionMode)
    .help("Show a 5-second prompt picker after each transcription")
```

### DictationViewModel Property

```swift
@Published var promptSelectionMode: Bool = false {
    didSet { UserDefaults.standard.set(promptSelectionMode, forKey: "dictationPromptSelectionMode") }
}
// Initialize from UserDefaults in init()
```

## HUDView Changes

New `@ViewBuilder` block for `.selectingPrompt` status:

- Purple brain icon + "Select prompt" text (top row)
- `ScrollView(.horizontal)` containing pill buttons
- Each pill: rounded rect with prompt name, tap gesture
- Default pill has highlighted style (purple fill vs outline)
- "Custom..." pill at end
- When `isEnteringCustomPrompt`: replace pill row with `TextField` + Enter hint
- Progress bar: `Rectangle` with `.frame(width: maxWidth * countdownProgress)`, animated with `.linear` over 5s

## Files Modified

1. **`HUDState.swift`** — Add `.selectingPrompt` case, new published properties
2. **`HUDView.swift`** — Add selectingPrompt view with pills + progress bar
3. **`HUDWindowController.swift`** — Add `showPromptSelection()`, `PromptSelectionResult`, timer logic, continuation management
4. **`DictationViewModel.swift`** — Add `promptSelectionMode` property, modify `transcribe()` to insert selection step
5. **`DictationSettingsView.swift`** — Add toggle for prompt selection mode

## Edge Cases

- **No prompts available:** Should not happen (builtins always exist), but if it did, skip selection and use default behavior.
- **Claude disconnects during selection:** Selection still completes, error caught during processing phase (existing error handling).
- **User closes HUD during countdown:** Return `.cancelled`, skip Claude processing, still copy/paste raw transcription.
- **Custom text is empty:** Treat as cancellation, don't send empty prompt to Claude.
- **Task cancellation:** Timer and continuation must handle cancellation cleanly — no leaked resources or dangling continuations.
