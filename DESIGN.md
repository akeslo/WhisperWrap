---
title: WhisperWrap design system
created: 2026-10-08T23:59:00-05:00
tags: [design-system, impeccable]
name: WhisperWrap
description: Push-to-Talk Readback. Graphite shell, tally lights for state, words land before attention moves.
colors:
  graphite-ground: "#16191A"
  graphite-raised: "#2A302E"
  hairline: "rgba(255, 255, 255, 0.08)"
  bone: "#E9ECE8"
  bone-dim: "rgba(233, 236, 232, 0.62)"
  tally-tx: "#E5483B"
  tally-amber: "#F2A33A"
  tally-landed: "#58C48A"
typography:
  page-title:
    fontFamily: "SF Pro, -apple-system, system-ui"
    fontSize: "22px"
    fontWeight: 600
  status:
    fontFamily: "SF Pro, -apple-system, system-ui"
    fontSize: "15px"
    fontWeight: 500
  title:
    fontFamily: "SF Pro, -apple-system, system-ui"
    fontSize: "13px"
    fontWeight: 600
  body:
    fontFamily: "SF Pro, -apple-system, system-ui"
    fontSize: "13px"
    fontWeight: 400
  label:
    fontFamily: "SF Pro, -apple-system, system-ui"
    fontSize: "11px"
    fontWeight: 400
  keycap:
    fontFamily: "SF Pro Rounded, ui-rounded, system-ui"
    fontSize: "12px"
    fontWeight: 500
  numerals:
    fontFamily: "SF Mono, ui-monospace, monospace"
    fontSize: "12px"
    fontWeight: 500
    fontFeature: "\"tnum\""
rounded:
  meter: "1px"
  keycap: "5px"
  field: "6px"
  plate: "8px"
  panel: "10px"
  capsule: "999px"
spacing:
  xs: "4px"
  sm: "8px"
  md: "12px"
  panel: "14px"
  page: "24px"
  section: "28px"
components:
  panel:
    backgroundColor: "{colors.graphite-raised}"
    textColor: "{colors.bone}"
    rounded: "{rounded.panel}"
    padding: "14px"
  keycap:
    backgroundColor: "{colors.graphite-ground}"
    textColor: "{colors.bone}"
    typography: "{typography.keycap}"
    rounded: "{rounded.keycap}"
    padding: "4px 8px"
  field:
    backgroundColor: "{colors.graphite-ground}"
    textColor: "{colors.bone}"
    rounded: "{rounded.field}"
    padding: "6px"
  list-row-selected:
    backgroundColor: "{colors.graphite-ground}"
    textColor: "{colors.bone}"
    rounded: "{rounded.field}"
    padding: "7px 10px"
  tally-light:
    size: "8px"
    rounded: "{rounded.capsule}"
  hud-capsule:
    backgroundColor: "{colors.graphite-ground}"
    textColor: "{colors.bone}"
    rounded: "{rounded.capsule}"
    width: "340px"
    height: "44px"
    padding: "0 14px"
  hud-refine-pill:
    backgroundColor: "{colors.graphite-ground}"
    textColor: "{colors.bone}"
    rounded: "{rounded.capsule}"
    width: "176px"
    height: "32px"
  button-key:
    backgroundColor: "{colors.tally-tx}"
    textColor: "{colors.bone}"
---

# Design System: WhisperWrap

## Overview

**Creative North Star: "Push-to-Talk Readback"**

WhisperWrap behaves like a radio operator's console reduced to its signals: a dark graphite shell, bone-colored type, and three tally lights that say what the microphone is doing. Key up and the light goes red; release and it goes amber while the words decode; it turns green once they have landed in the focused app. Refine is the readback: the same message, corrected and pasted back over the raw text.

The system is quiet and dense in the way native macOS utilities are dense. Every control is a stock SwiftUI/AppKit control (buttons, toggles, pickers, menus, the `NavigationSplitView` sidebar) tinted bone instead of system blue, sitting on opaque graphite plates. Color appears only when it carries state or a measurement. The world is held to palette, tally, and numerals so it never becomes a radio costume: no faux hardware, no textures, no dials.

**Key Characteristics:**
- Opaque graphite ground with one raised plate tone and a white hairline; dark scheme forced everywhere.
- Three tally colors (red, amber, green) as the only chroma, each bound to a dictation state.
- Amber monospaced numerals for every measurement (elapsed time, percent, sizes, rates, counts).
- One floating HUD shape that shrinks from a recording capsule into a Refine pill.
- Native controls and SF Symbols throughout; the accent tint is bone, not blue.

## Colors

A graphite-and-bone neutral shell lit only by three broadcast tally colors.

### Primary
- **TX Red** (tally-tx): the keyed state. The HUD tally and level meter while listening, the menu bar and Dictate page tally while recording, the tint of the one control that keys the mic (the menu bar's Start/Stop Dictation button), and failure states (HUD `failed`, the TTS character count past its limit).

### Secondary
- **Decode Amber** (tally-amber): work in flight. Pulsing tally while transcribing, refining, downloading a model, or checking the `claude` CLI; progress bar tint; the Refine pill's wand glyph (the pill offers the refining beat). Also the color of measurement numerals.

### Tertiary
- **Landed Green** (tally-landed): done and in place. The steady tally after a paste or replacement, a downloaded model, a healthy permission.

### Neutral
- **Graphite Ground** (graphite-ground): window, menu bar panel, and HUD background; also the inset tone for fields, keycaps, log wells, and the selected prompt row.
- **Graphite Raised** (graphite-raised): Panel plates, the menu bar transcript preview, permission rows, the drop zone, unlit level-meter segments.
- **Hairline** (hairline): 1px stroke on every plate, keycap, field, and the HUD; dividers; the separator inside the Refine pill.
- **Bone** (bone): primary text and the app-wide control tint.
- **Bone Dim** (bone-dim): secondary text, ledes, hints, empty-state copy, glyph buttons (close, mic menu, chevron).

### Named Rules
**The Tally Rule.** Red, amber, and green carry state only: red is keyed (or failed), amber is working, green is landed. If an element is not reporting dictation, decode, refine, download, or health state, it gets no tally color.

**The Bone Tint Rule.** The app's accent is bone (`.tint(Theme.text)`), so native controls stay neutral; system blue never appears.

## Typography

**Display Font:** SF Pro (system)
**Body Font:** SF Pro (system)
**Label/Mono Font:** SF Mono for measurements; SF Pro Rounded for key combinations

**Character:** One family at small, functional sizes, weight doing the hierarchy work. Monospaced amber numerals read as instrument readouts; rounded glyphs make shortcut keys look like keys.

### Hierarchy
- **Page title** (600, 22px): one per main-window sidebar destination, above an optional bone-dim lede.
- **Status** (500, 15px): the live tally label on the Dictate page and the drop-zone prompt.
- **Title** (600, 13px): Panel titles, HUD state word, menu bar status line.
- **Body** (400, 13px): settings labels, transcript text, preview text (12px in the 300px menu bar panel).
- **Label** (400, 11px): HUD subtitle (device or prompt name), captions, permission hints, section labels inside a Panel ("Raw", "Refined" at caption semibold, bone-dim, sentence case).
- **Keycap** (500, 12px rounded; 10px inside the Refine pill): hotkey displays only.
- **Numerals** (500, 11-13px monospaced, tabular): every measurement, always amber.

### Named Rules
**The Readout Rule.** Numbers that measure something (duration, latency, percent, size, rate, count, version) are set in `Theme.numerals` and colored amber. Prose never uses the monospaced face; log text and prompt editors use monospaced in bone or bone-dim, not amber.

## Layout

The main window is a `NavigationSplitView`: a native sidebar (160-220px, ideal 180) listing Dictate, Files, Voice, Prompts, System with SF Symbols, and a detail pane on graphite ground. Each destination is a `Page`: scrolling column, 24px padding, content capped at 720px and left-aligned (not centered), 28px between sections, title and lede stacked 6px apart. Sections are Panels stacked vertically; inside a Panel, rows sit 12px apart and each `SettingRow` puts label and optional hint left, native control right, with at least 12px between.

The menu bar panel is a fixed 300px column with 12px gutters: status row (tally, state word, hotkey keycap), transcript preview plate, two full-width large buttons, a hairline divider, then borderless Open/Quit.

The HUD is a borderless floating panel centered horizontally, 10px below the top of the visible frame (under the menu bar). It never takes focus.

## Elevation & Depth

Depth is tonal: ground, raised plate, ground-colored insets, all outlined by the same white hairline. Main window and menu bar surfaces carry no shadows. Two soft shadows exist and both are about light, not stacking.

### Shadow Vocabulary
- **HUD float** (`shadow: rgba(0,0,0,0.35) radius 10 y 4`): only on the HUD capsule/pill, which floats over other apps. The window server shadow is disabled so this one is the only one.
- **Tally glow** (`shadow: <tally color> at 60%, radius 3, y 1`): the LED's own light bleed on every `TallyLight`.

### Named Rules
**The Flat Window Rule.** Inside the app's own windows, separation comes from ground/raised tone and the hairline. Shadows belong to the floating HUD and to lit LEDs only.

## Shapes

Continuous-corner rounded rectangles scaled by container size: 5px keycaps, 6px fields and inset wells, 8px small plates in the menu bar, 10px Panels and the drop zone. The HUD is a true capsule. Level-meter segments are 1px-rounded bars. Every plate pairs its fill with a 1px hairline stroke; the drop zone uses a 6px-dash hairline that brightens to bone at 50% when a file hovers.

## Components

### Buttons
- **Native first.** Buttons are stock SwiftUI (`.bordered` default, `.borderless` for footer links, `.plain` for HUD glyph and pill buttons), tinted bone by the app tint.
- **Key button:** the menu bar's Start/Stop Dictation, large control size, full width, tinted TX red because it keys the mic. Only this control gets a tally tint.
- **Glyph buttons:** SF Symbols at 9-11px semibold/bold in bone-dim, 20x20 hit area.

### Cards / Containers (Panel)
- **Corner Style:** 10px continuous.
- **Background:** graphite-raised with hairline stroke, 14px padding.
- **Title:** 13px semibold bone, 8px above the plate (outside it).

### Inputs / Fields
- **Style:** native controls on plates; text editors and log wells are graphite-ground insets, 6px radius, hairline stroke, background scroll content hidden.
- **Hotkey recorder:** a KeyCap that becomes a button; while recording, its stroke brightens to bone at 60% and the label reads "Press new keys…".

### Navigation
- **Sidebar:** native `List` with `Label(title, systemImage:)` rows, system selection and material.
- **Prompt list:** plain rows, 7px x 10px padding; the selected row sits on a graphite-ground 6px plate.

### Tally Light
8px circle in a tally color with its own glow. Steady for listening and landed; breathes between 100% and 35% opacity on a 0.7s ease-in-out loop for in-progress states. Always paired with a text state word; hidden from accessibility.

### KeyCap
Read-only shortcut display: rounded 12px medium bone glyphs on a graphite-ground 5px plate with hairline, 4px x 8px padding.

### HUD Capsule and Refine Pill (signature)
One floating shape, one state at a time. The capsule (340 x 44) holds tally light, state word with bone-dim subtitle, and while listening a red level meter, amber elapsed time (m:ss), and a mic device menu, plus a close glyph. After the paste it shrinks to the Refine pill (176 x 32): amber wand, "Refine", a dim ⌥⌘R keycap glyph, a hairline separator, and a chevron menu of prompts. The window frame animates between sizes over 0.28s while content crossfades with a slight scale (0.96 capsule, 0.9 pill) under a 0.28s snappy spring; on hide the panel fades over 0.25s.

## Do's and Don'ts

### Do:
- **Do** route every state color through `Theme.tx`, `Theme.amber`, `Theme.landed`, and pair it with a `TallyLight` and a state word.
- **Do** set measurements in `Theme.numerals` amber.
- **Do** build new main-window sections from `Page`, `Panel`, and `SettingRow`, with native controls on the right.
- **Do** outline every plate, field, and keycap with the 1px hairline.
- **Do** keep the HUD at one fixed height per state, top-center, focus-free.

### Don't:
- **Don't** use tally colors for decoration, icons that are not reporting state, or emphasis.
- **Don't** introduce system blue or a second accent; the tint is bone.
- **Don't** make the HUD translucent or vibrant; it is opaque graphite with its own soft shadow.
- **Don't** add shadows inside the main window or menu bar panel.
- **Don't** add hardware costume (knobs, grilles, textures, faux LEDs beyond `TallyLight`).
