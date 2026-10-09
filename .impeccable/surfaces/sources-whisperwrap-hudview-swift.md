---
version: 1
slug: "sources-whisperwrap-hudview-swift"
primary_target: "Sources/WhisperWrap/HUDView.swift"
related_targets: ["Sources/WhisperWrap/ContentView.swift","Sources/WhisperWrap/MenuBarView.swift"]
---

Scope: whole app (HUD, menu bar panel, main window). Mode: Operate. Seed: fc342377 (assigned).

## Direction contract

THESIS: Push-to-Talk Readback. Key up, talk, release, words land instantly. Refine is the readback: same message corrected in place. Refuses the category default of a translucent blue-accent bubble and a modal prompt picker blocking the paste.

OWN-WORLD: Graphite shell (#16191a ground, #2a302e raised), bone text #e9ece8. Strict tally vocabulary: TX red #e5483b while keyed, amber #f2a33a decoding/refining, green #58c48a landed. Amber tabular numerals only for measurements (duration, latency, model). SF Pro + SF Mono numerals, SF Symbols, native controls.

STORY: Hotkey -> red tally capsule with live level -> amber decode -> green landed + auto paste -> capsule shrinks to a corner Readback pill (6s) -> click or Opt-Cmd-R -> amber pulse -> refined text replaces raw paste.

FIRST VIEWPORT: HUD capsule top-center under menu bar, one fixed height, one state at a time. Main window: sidebar Dictate / Files / Voice / Prompts / System.

SIGNATURE: the capsule-to-Readback-pill morph (matchedGeometry), tally LED carrying state.

RISK: radio costume. Hold world to palette, tally, numerals.
