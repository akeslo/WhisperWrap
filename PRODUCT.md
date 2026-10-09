---
title: WhisperWrap product record
created: 2026-10-08T22:50:00-05:00
tags: [product, impeccable]
---

# Product

<!-- impeccable:product-schema 1 -->

## Platform

macos

## Users

One user: the owner, dictating into whatever app has focus on a Mac all day (chat, email, editors, Claude Code). The job is getting spoken thought onto the screen as text with zero waiting, then optionally cleaning it up.

## Product Purpose

Local, private speech-to-text from a global hotkey. Success is: press, talk, press, and the words are already pasted before attention has moved on. AI refinement is a second, optional beat, never a gate in front of the paste.

## Positioning

On-device transcription (Parakeet TDT v3 / WhisperKit CoreML) with instant paste, plus a one-keystroke Claude refine that replaces the raw paste in place, authenticated through the user's own `claude` CLI login (no API key stored).

## Operating Context

- Lives in the menu bar; the HUD floats over whatever app is in front. It must never steal focus or cover what the user is typing into.
- Dictation flow (confirmed 2026-10-08): transcribe as fast as possible, paste immediately, then the HUD shrinks into a small non-obstructive "Refine" pill for 6s. Click or ⌥⌘R runs the default prompt (Polish) and replaces the pasted text (Cmd-Z the raw paste, paste refined). A chevron on the pill picks another prompt. ⌥⌘R keeps working on the last dictation after the pill fades.
- Secondary surfaces: main window (file transcription by drag-drop, dictation settings, TTS, diagnostics) and the menu bar panel.

## Capabilities and Constraints

- AI prompts must always return a finished, updated version of the input. They may never ask questions, request more input, or comment on missing context.
- Claude runs via `claude --print` subprocess; startup latency (~3s) is the floor, so refine must be asynchronous and optional.
- macOS 14+, SwiftUI + AppKit, SPM, no Xcode project.

## Product Principles

1. Paste first, polish later. Nothing sits between the stop key and the paste.
2. Never in the way: no focus steal, no modal, nothing over the caret.
3. One keystroke for the common path; choice is one click deeper.
4. AI output is always a usable result, never a conversation.
