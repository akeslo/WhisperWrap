import SwiftUI

struct DictationRecordingView: View {
    @ObservedObject var viewModel: DictationViewModel
    
    var body: some View {
        VStack(spacing: 20) {
            // MARK: - Status & Waveform
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                    )
                
                VStack(spacing: 16) {
                    if viewModel.isRecording {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(Color.red)
                                .frame(width: 10, height: 10)
                                .opacity(Double(Int(Date().timeIntervalSince1970 * 2) % 2 == 0 ? 1 : 0.5)) // Blink
                                .animation(.default, value: Date())
                            
                            Text("Recording...")
                                .font(.headline)
                                .foregroundColor(.red)
                        }
                        
                        // Simulated Waveform Visualizer
                        HStack(spacing: 4) {
                            ForEach(0..<20) { index in
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color.accentColor)
                                    .frame(width: 4, height: 10 + (CGFloat(viewModel.audioLevel) * CGFloat.random(in: 10...40)))
                                    .animation(.easeInOut(duration: 0.1), value: viewModel.audioLevel)
                            }
                        }
                        .frame(height: 60)
                        
                    } else if viewModel.isProcessing {
                        ProgressView("Processing with Whisper...")
                    } else {
                        Text(viewModel.transcribedText.isEmpty ? "Tap Record to Start" : "Ready")
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
            }
            .frame(height: 100)
            
            // MARK: - Controls
            HStack(spacing: 20) {
                if viewModel.isRecording {
                    Button(action: { viewModel.cancelRecording() }) {
                        Text("Cancel")
                            .frame(minWidth: 80)
                    }
                    .buttonStyle(.bordered)

                    Button(action: { viewModel.stopRecording() }) {
                        Text("Stop Recording")
                            .frame(minWidth: 120)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                } else {
                    Button(action: { viewModel.startRecording() }) {
                        Label("Start Recording", systemImage: "mic.fill")
                            .font(.title3)
                            .padding()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.isProcessing)
                }
            }
            .padding(.bottom, 16)
        }
        .padding()
    }
}
