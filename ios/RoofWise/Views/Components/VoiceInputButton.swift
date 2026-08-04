import SwiftUI
import UIKit

/// Reusable mic control wrapping `SpeechDictationService` (SFSpeechRecognizer).
///
/// - First tap requests Speech + Mic authorization, then live-transcribes into
///   the bound `text`.
/// - Tap again to stop.
/// - Shows a recording indicator while active.
/// - Denied permission → alert with a Settings deep-link.
///
/// Tap target is 56–64pt. Theme tokens only.
struct VoiceInputButton: View {
    @Binding var text: String
    var style: Style = .icon
    var append: Bool = false
    var accessibilityLabelText: String = "Dictate"

    enum Style {
        /// Circular / rounded square icon (56pt).
        case icon
        /// Capsule with "Voice" / "Listening…" label (min 56pt height).
        case capsule
        /// Compact circle suitable for inline field leading (56pt).
        case compact
    }

    @State private var speech = SpeechDictationService()
    @State private var showDeniedAlert = false
    @State private var deniedMessage = ""

    var body: some View {
        Button {
            // Start/stop/denied haptics live in SpeechDictationService.toggle().
            speech.toggle()
        } label: {
            labelContent
        }
        .buttonStyle(.plain)
        .accessibilityLabel(speech.isListening ? "Stop dictation" : accessibilityLabelText)
        .accessibilityAddTraits(speech.isListening ? .isSelected : [])
        .onChange(of: speech.transcript) { _, value in
            guard !value.isEmpty else { return }
            if append, !text.isEmpty {
                // Append with a separating space when the field already has content.
                let needsSpace = !text.hasSuffix(" ") && !text.hasSuffix("\n")
                text = text + (needsSpace ? " " : "") + value
            } else {
                text = value
            }
        }
        .onChange(of: speech.state) { _, newState in
            if case .unavailable(let msg) = newState {
                deniedMessage = msg
                showDeniedAlert = true
            }
        }
        .onDisappear { speech.stop() }
        .alert("Microphone & Speech", isPresented: $showDeniedAlert) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(deniedMessage.isEmpty
                 ? "Allow Microphone and Speech Recognition in Settings to dictate."
                 : deniedMessage)
        }
    }

    @ViewBuilder
    private var labelContent: some View {
        switch style {
        case .icon:
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(speech.isListening ? Theme.ember : Theme.ink)
                Image(systemName: speech.isListening ? "mic.fill" : "mic")
                    .font(.system(size: Theme.TypeRamp.subhead, weight: .heavy))
                    .foregroundStyle(.white)
                if speech.isListening {
                    Circle()
                        .fill(Theme.crimson)
                        .frame(width: 8, height: 8)
                        .offset(x: 14, y: -14)
                }
            }
            .frame(width: 56, height: 56)
            .contentShape(.rect)

        case .capsule:
            HStack(spacing: 8) {
                ZStack {
                    Image(systemName: speech.isListening ? "mic.fill" : "mic")
                        .font(.system(size: Theme.TypeRamp.metaSm, weight: .heavy))
                    if speech.isListening {
                        Circle()
                            .fill(.white)
                            .frame(width: 6, height: 6)
                            .offset(x: 8, y: -8)
                    }
                }
                Text(speech.isListening ? "Listening…" : "Voice")
                    .font(.system(size: Theme.TypeRamp.metaSm, weight: .heavy))
            }
            .foregroundStyle(speech.isListening ? .white : Theme.ember)
            .padding(.horizontal, 14)
            .frame(minHeight: 56)
            .background(
                speech.isListening ? AnyShapeStyle(Theme.ember) : AnyShapeStyle(Theme.emberSoft),
                in: .capsule
            )
            .contentShape(.capsule)

        case .compact:
            ZStack {
                Circle()
                    .fill(speech.isListening ? Theme.emberSoft : Theme.canvas)
                Image(systemName: speech.isListening ? "mic.fill" : "mic")
                    .font(.system(size: Theme.TypeRamp.body, weight: .heavy))
                    .foregroundStyle(speech.isListening ? Theme.ember : Theme.inkSoft)
                if speech.isListening {
                    Circle()
                        .fill(Theme.crimson)
                        .frame(width: 7, height: 7)
                        .offset(x: 14, y: -14)
                }
            }
            .frame(width: 56, height: 56)
            .contentShape(.circle)
        }
    }
}
