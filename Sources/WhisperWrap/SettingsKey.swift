/// UserDefaults keys DictationViewModel persists its settings under. The values are
/// stored on disk, so never change one: that would reset the setting for every user.
enum SettingsKey {
    static let autoCopy = "autoCopy"
    static let autoRefine = "autoRefine"
    static let showHUD = "showHUD"
    static let saveRecordings = "saveRecordings"
    static let recordingsSaveDirectory = "recordingsSaveDirectory"
    static let dictationClaudePromptID = "dictationClaudePromptID"
    static let dictationClaudeModel = "dictationClaudeModel"
    static let selectedAudioDeviceID = "selectedAudioDeviceID"
}
