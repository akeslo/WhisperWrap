# WhisperWrap

WhisperWrap is a powerful macOS application that wraps the `faster-whisper` library to provide local, privacy-focused speech-to-text capabilities. It offers system-wide dictation, file transcription, and text-to-speech features.

## Features

- **System-Wide Dictation**: Press a global hotkey (default: `Option+Space`) to start dictating anywhere. The transcribed text is automatically copied to your clipboard and can be auto-pasted.
- **File Transcription**: Drag and drop audio or video files to transcribe them using the Whisper model.
- **Text-to-Speech (TTS)**: Convert text to speech using system voices.
- **Local Processing**: All speech processing is done locally on your device using `faster-whisper`, ensuring data privacy.
- **Private Python Environment**: Automatically manages a dedicated Python environment for dependencies, keeping your system clean.
- **Menu Bar Access**: Quick access to dictation and settings from the menu bar.

## Installation

1.  Download the latest release from the [Releases Page](https://github.com/akeslo/WhisperWrap/releases).
2.  Unzip `WhisperWrap.zip` if needed.
3.  Move `WhisperWrap.app` to your Applications folder.
4.  Open the app. On first launch, click "Set Up Speech Engine" to install the necessary local AI models and dependencies.

## Usage

### Dictation
1.  Ensure the app is running.
2.  Place your cursor where you want to type.
3.  Press `Option + Space` to start recording.
4.  Speak your text.
5.  Press `Option + Space` again to stop.
6.  The text will be transcribed and pasted automatically (if "Auto Paste" is enabled in settings).

### Settings
- **Model Selection**: Choose between different Whisper model sizes (Tiny, Base, Small, Medium, Large) to balance speed vs. accuracy.
- **Auto Copy/Paste**: Configure clipboard behavior.
- **Hotkeys**: Customize the global dictation hotkey.

## Building from Source

Requirements:
- macOS 13.0+
- Swift 5.9+
- Python 3.10+ (for runtime environment creation)

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
