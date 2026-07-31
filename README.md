# WhisperWrap

WhisperWrap is a powerful macOS application that provides local, privacy-focused speech-to-text capabilities using native CoreML transcription. It offers system-wide dictation, file transcription, optional Claude AI post-processing, and text-to-speech features.

## Features

- **System-Wide Dictation**: Press a global hotkey (default: `Option+Space`) to start dictating anywhere. The transcribed text is automatically copied to your clipboard and can be auto-pasted.
- **File Transcription**: Drag and drop audio or video files to transcribe them using the native CoreML Whisper model.
- **Text-to-Speech (TTS)**: Convert text to speech using system voices, or optionally the ElevenLabs cloud engine (requires an ElevenLabs API key; text is sent to their servers).
- **Local Transcription**: Speech-to-text runs entirely on your device using native CoreML transcription — no audio leaves the machine. The optional Claude and ElevenLabs features are the only parts that reach the network, and both are off unless you enable them.
- **Optional Claude AI Post-Processing**: Polish transcriptions with grammar correction, summarization, or custom prompts. This runs through the [Claude Code CLI](https://claude.com/claude-code) (`claude` on your `PATH`, or a custom path set in settings) using your existing Claude login — no API key is stored in WhisperWrap.
- **Menu Bar Access**: Quick access to dictation and settings from the menu bar.

## Installation

1.  Download the latest release from the [Releases Page](https://github.com/akeslo/WhisperWrap/releases).
2.  Unzip `WhisperWrap.zip` if needed.
3.  Move `WhisperWrap.app` to your Applications folder.
4.  Open the app. On first launch, the native CoreML Whisper model will be downloaded automatically (size varies by model).

## Usage

### Dictation
1.  Ensure the app is running.
2.  Place your cursor where you want to type.
3.  Press `Option + Space` to start recording.
4.  Speak your text.
5.  Press `Option + Space` again to stop.
6.  The text will be transcribed and pasted automatically (if "Auto Paste" is enabled in settings).

### Settings
- **Model Selection**: Choose between different Whisper model sizes (Tiny, Base, Small, Medium, Large, Turbo) to balance speed vs. accuracy.
- **Auto Copy/Paste**: Configure clipboard behavior.
- **Hotkeys**: Customize the global dictation hotkey.

## Building from Source

Requirements:
- macOS 14.0+
- Swift 6.2+ toolchain (Xcode 26 or newer) — `Package.swift` declares `swift-tools-version: 6.2`

```bash
# Clone the repository
git clone https://github.com/akeslo/WhisperWrap.git
cd WhisperWrap

# Build the app bundle
./generate_app.sh
```

The compiled `WhisperWrap.app` will be in the project root.

## License

[MIT License](LICENSE)
