import SwiftUI

/// Push-to-Talk Readback palette. Tally colors carry state only, never decoration:
/// red = keyed/recording, amber = decoding or refining, green = landed.
enum Theme {
    static let ground = Color(red: 0x16 / 255, green: 0x19 / 255, blue: 0x1A / 255)
    static let raised = Color(red: 0x2A / 255, green: 0x30 / 255, blue: 0x2E / 255)
    static let hairline = Color.white.opacity(0.08)
    static let text = Color(red: 0xE9 / 255, green: 0xEC / 255, blue: 0xE8 / 255)
    static let textDim = Color(red: 0xE9 / 255, green: 0xEC / 255, blue: 0xE8 / 255).opacity(0.62)

    static let tx = Color(red: 0xE5 / 255, green: 0x48 / 255, blue: 0x3B / 255)
    static let amber = Color(red: 0xF2 / 255, green: 0xA3 / 255, blue: 0x3A / 255)
    static let landed = Color(red: 0x58 / 255, green: 0xC4 / 255, blue: 0x8A / 255)

    /// Tabular numerals for measurements (durations, latency, sizes). Never for prose.
    static func numerals(_ size: CGFloat, weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

/// Small status LED. `pulsing` breathes for in-progress states.
struct TallyLight: View {
    let color: Color
    var pulsing = false
    @State private var dim = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .shadow(color: color.opacity(0.6), radius: 3, y: 1)
            .opacity(pulsing && dim ? 0.35 : 1)
            .onAppear {
                guard pulsing else { return }
                withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) { dim = true }
            }
            .accessibilityHidden(true)
    }
}

/// Grouped section used across the main window: title, then content on a raised plate.
struct Panel<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.text)
            VStack(alignment: .leading, spacing: 12) { content }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.raised, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.hairline))
        }
    }
}

/// One labeled setting line inside a Panel: label (and optional hint) left, native control right.
struct SettingRow<Control: View>: View {
    let label: String
    var detail: String? = nil
    @ViewBuilder var control: Control

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).foregroundStyle(Theme.text)
                if let detail {
                    Text(detail).font(.caption).foregroundStyle(Theme.textDim)
                }
            }
            Spacer(minLength: 12)
            control
        }
    }
}

/// Scrolling page body for a main-window sidebar destination.
struct Page<Content: View>: View {
    let title: String
    var lede: String? = nil
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(Theme.text)
                    if let lede {
                        Text(lede).foregroundStyle(Theme.textDim)
                    }
                }
                content
            }
            .padding(24)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.ground)
    }
}

/// Read-only key combo, drawn as a quiet keycap.
struct KeyCap: View {
    let keys: String
    var body: some View {
        Text(keys)
            .font(.system(size: 12, weight: .medium, design: .rounded))
            .foregroundStyle(Theme.text)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Theme.ground, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(Theme.hairline))
    }
}
