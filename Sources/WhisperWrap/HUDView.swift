import SwiftUI

struct HUDView: View {
    @ObservedObject var state: HUDState
    var onClose: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: state.status == .listening ? "mic.fill" : "waveform.circle.fill")
                .font(.title2)
                .foregroundColor(state.status == .listening ? .red : .orange)
                .symbolEffect(.pulse, isActive: state.status == .listening) // Pulse only when listening
            
            VStack(alignment: .leading, spacing: 2) {
                Text("WhisperWrap")
                    .font(.headline)
                    .fixedSize()
                Text(state.status == .listening ? "Listening..." : "Transcribing...")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize()
            }
            
            Spacer()
            
            // Visualizer - organic "dancing" bars
            HStack(spacing: 4) {
                ForEach(0..<20) { index in
                    // Combine varying frequencies for a pseudo-random "dancing" look
                    // Phase speed varies by index to prevent uniform waving
                    let t = state.phase
                    let i = Double(index)
                    // More varied interference pattern
                    let h1 = sin(t + i * 0.6)
                    let h2 = cos(t * 0.8 - i * 1.2)
                    let h3 = sin(t * 0.2 + i * 2.5) // High frequency jitter
                    
                    // Combine them and ensure positive value
                    let baseSignal = abs(h1 + h2 + 0.5 * h3)
                    
                    // Amplitude multiplier
                    let wave = CGFloat(baseSignal) * 12.0

                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(Color.blue)
                        // Dynamic resizing:
                        // - minimal base height: 4
                        // - wave motion: wave
                        // - audio scaling: multiply the wave by audio level to make it jump
                        // - direct audio boost: add raw audio level
                        .frame(width: 4, height: 4 + wave * (0.5 + CGFloat(state.audioLevel) * 5.0) + (CGFloat(state.audioLevel) * 30))
                        // Remove animation modifier to let high-speed timer drive smooth updates without interpolation lag
                }
            }
            .frame(height: 40)
            // Use local animation for smooth transitions if phase jumps, but here phase is continuous
            .animation(.linear(duration: 0.05), value: state.phase)
            
            // Close button
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("Stop Recording")
        }
        .padding()
        .background(.regularMaterial)
        .cornerRadius(20)
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        )
        .padding(10)
    }
}
