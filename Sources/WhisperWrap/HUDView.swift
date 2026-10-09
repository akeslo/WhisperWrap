import SwiftUI

/// One state at a time, one shape that morphs: recording capsule -> Refine pill.
struct HUDView: View {
    @ObservedObject var state: HUDState
    var onClose: () -> Void
    var onDevice: (String) -> Void
    var onRefine: (UUID?) -> Void
    var onDismissPill: () -> Void

    var body: some View {
        Group {
            if state.isPill { pill } else { capsule }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.ground, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.hairline))
        .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
        .padding(1)
        .environment(\.colorScheme, .dark)
    }

    // MARK: - Capsule

    private var capsule: some View {
        HStack(spacing: 10) {
            TallyLight(color: tallyColor, pulsing: state.status != .listening && state.status != .landed)
                .id(tallyColor.description) // restart pulse when the state changes

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textDim)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer(minLength: 6)

            if state.status == .listening {
                LevelMeter(level: state.audioLevel)
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    Text(elapsed(at: ctx.date))
                        .font(Theme.numerals(11))
                        .foregroundStyle(Theme.amber)
                        .monospacedDigit()
                }
                deviceMenu
            }

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.textDim)
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(state.status == .listening ? "Cancel recording" : "Hide")
        }
        .padding(.horizontal, 14)
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
    }

    private var deviceMenu: some View {
        Menu {
            ForEach(state.availableDevices, id: \.id) { device in
                Button {
                    onDevice(device.id)
                } label: {
                    if device.id == state.selectedDeviceID {
                        Label(device.name, systemImage: "checkmark")
                    } else {
                        Text(device.name)
                    }
                }
            }
        } label: {
            Image(systemName: "mic")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.textDim)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Switch microphone")
    }

    // MARK: - Refine pill

    private var pill: some View {
        HStack(spacing: 0) {
            Button { onRefine(nil) } label: {
                HStack(spacing: 6) {
                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.amber)
                    Text("Refine")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.text)
                    Text("⌥⌘R")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(Theme.textDim)
                }
                .padding(.leading, 12)
                .padding(.trailing, 6)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Refine with \(defaultPromptName) and replace the pasted text")

            Rectangle().fill(Theme.hairline).frame(width: 1, height: 16)

            Menu {
                ForEach(state.prompts) { prompt in
                    Button(prompt.name) { onRefine(prompt.id) }
                }
                Divider()
                Button("Dismiss", action: onDismissPill)
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Theme.textDim)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .padding(.horizontal, 8)
            .help("Refine with another prompt")
        }
        .transition(.opacity.combined(with: .scale(scale: 0.9)))
    }

    // MARK: - Copy

    private var tallyColor: Color {
        switch state.status {
        case .listening: Theme.tx
        case .transcribing, .processingWithClaude, .refineOffer: Theme.amber
        case .landed: Theme.landed
        case .failed: Theme.tx
        }
    }

    private var title: String {
        switch state.status {
        case .listening: "Listening"
        case .transcribing: "Transcribing"
        case .refineOffer: "Pasted"
        case .processingWithClaude: "Refining"
        case .landed: "Refined and replaced"
        case .failed(let message): message
        }
    }

    private var subtitle: String? {
        if !state.note.isEmpty { return state.note }
        switch state.status {
        case .listening: return selectedDeviceName
        case .processingWithClaude: return defaultPromptName
        default: return nil
        }
    }

    private var selectedDeviceName: String? {
        state.availableDevices.first { $0.id == state.selectedDeviceID }?.name
    }

    private var defaultPromptName: String {
        state.prompts.first { $0.id == state.defaultPromptID }?.name ?? "Polish"
    }

    private func elapsed(at date: Date) -> String {
        let s = max(0, Int(date.timeIntervalSince(state.recordingStartedAt)))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

/// Five-segment input meter, red segments lit by level.
private struct LevelMeter: View {
    let level: Float

    var body: some View {
        // averagePower normalized from -160...0; speech lives in roughly the top 40%.
        let lit = Int(((Double(level) - 0.6) / 0.4 * 5).rounded().clamped(to: 0...5))
        HStack(spacing: 2) {
            ForEach(0..<5, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1)
                    .fill(i < lit ? Theme.tx : Theme.raised)
                    .frame(width: 3, height: CGFloat(6 + i * 2))
            }
        }
        .frame(height: 14, alignment: .bottom)
        .animation(.easeOut(duration: 0.1), value: lit)
        .accessibilityHidden(true)
    }
}

private extension Double {
    func clamped(to r: ClosedRange<Double>) -> Double { min(max(self, r.lowerBound), r.upperBound) }
}
