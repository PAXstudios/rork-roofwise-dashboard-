import SwiftUI

/// Compact bottom sheet shown when the inspector taps anywhere on the live
/// camera preview. Lets them pick a damage type + severity + optional note,
/// then confirms placement of a `ManualDamageMarker`.
struct MarkDamageSheet: View {
    /// Tap position in normalized (0-1) preview coordinates.
    let tapNormalized: CGPoint
    var onCancel: () -> Void
    var onConfirm: (_ type: DamageMarkerType, _ severity: String, _ note: String?) -> Void

    @State private var selectedType: DamageMarkerType = .hailStrike
    @State private var selectedSeverity: String = "medium"
    @State private var note: String = ""
    @FocusState private var noteFocused: Bool

    private let severities: [(key: String, label: String)] = [
        ("low", "Low"), ("medium", "Medium"), ("high", "High")
    ]

    var body: some View {
        VStack(spacing: 16) {
            // Drag indicator handled by .presentationDragIndicator
            header

            typePicker

            severityPicker

            noteField

            HStack(spacing: 10) {
                Button {
                    let g = UIImpactFeedbackGenerator(style: .light); g.impactOccurred()
                    onCancel()
                } label: {
                    Text("Cancel")
                        .font(.system(size: 14, weight: .heavy))
                        .foregroundStyle(.white.opacity(0.85))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(.white.opacity(0.10), in: .capsule)
                        .overlay(Capsule().stroke(.white.opacity(0.18), lineWidth: 0.6))
                }
                .buttonStyle(.plain)

                Button {
                    let g = UINotificationFeedbackGenerator(); g.notificationOccurred(.success)
                    let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
                    onConfirm(selectedType, selectedSeverity, trimmed.isEmpty ? nil : trimmed)
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "scope")
                            .font(.system(size: 13, weight: .heavy))
                        Text("Mark Damage")
                            .font(.system(size: 14, weight: .heavy))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(
                        LinearGradient(colors: [selectedType.color, selectedType.color.opacity(0.78)],
                                       startPoint: .leading, endPoint: .trailing),
                        in: .capsule
                    )
                    .shadow(color: selectedType.color.opacity(0.45), radius: 12, y: 6)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 8)
        .padding(.bottom, 22)
        .background(Color(red: 0.08, green: 0.09, blue: 0.13))
        .environment(\.colorScheme, .dark)
        .onTapGesture { noteFocused = false }
    }

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(selectedType.color.opacity(0.22))
                    .frame(width: 38, height: 38)
                Circle()
                    .fill(selectedType.color)
                    .frame(width: 14, height: 14)
                    .overlay(Circle().stroke(.white, lineWidth: 2))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Mark Damage")
                    .font(.system(size: 17, weight: .heavy))
                    .foregroundStyle(.white)
                Text(String(format: "Tap @ %.0f%% × %.0f%%",
                            tapNormalized.x * 100, tapNormalized.y * 100))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.6))
                    .monospacedDigit()
            }
            Spacer()
            Image(systemName: "pencil.circle.fill")
                .font(.system(size: 22, weight: .heavy))
                .foregroundStyle(.white.opacity(0.85))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var typePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("DAMAGE TYPE")
                .font(.system(size: 10, weight: .heavy))
                .tracking(1.2)
                .foregroundStyle(.white.opacity(0.55))
            HStack(spacing: 8) {
                ForEach(ManualDamageMarker.allowedTypes, id: \.self) { type in
                    let isOn = selectedType == type
                    Button {
                        let g = UISelectionFeedbackGenerator(); g.selectionChanged()
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                            selectedType = type
                        }
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: type.icon)
                                .font(.system(size: 14, weight: .heavy))
                                .foregroundStyle(isOn ? .white : type.color)
                            Text(shortLabel(for: type))
                                .font(.system(size: 10, weight: .heavy))
                                .foregroundStyle(isOn ? .white : .white.opacity(0.78))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background {
                            if isOn {
                                Capsule().fill(type.color)
                                    .shadow(color: type.color.opacity(0.5), radius: 8, y: 2)
                            } else {
                                Capsule().fill(.white.opacity(0.08))
                            }
                        }
                        .overlay(
                            Capsule().stroke(isOn ? .clear : type.color.opacity(0.5), lineWidth: 0.8)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var severityPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SEVERITY")
                .font(.system(size: 10, weight: .heavy))
                .tracking(1.2)
                .foregroundStyle(.white.opacity(0.55))
            HStack(spacing: 8) {
                ForEach(severities, id: \.key) { entry in
                    let isOn = selectedSeverity == entry.key
                    Button {
                        let g = UISelectionFeedbackGenerator(); g.selectionChanged()
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                            selectedSeverity = entry.key
                        }
                    } label: {
                        Text(entry.label)
                            .font(.system(size: 12, weight: .heavy))
                            .foregroundStyle(isOn ? .black : .white.opacity(0.8))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background {
                                if isOn {
                                    Capsule().fill(
                                        LinearGradient(colors: [Theme.amber, Theme.ember],
                                                       startPoint: .leading, endPoint: .trailing)
                                    )
                                } else {
                                    Capsule().fill(.white.opacity(0.08))
                                }
                            }
                            .overlay(Capsule().stroke(isOn ? .clear : .white.opacity(0.18), lineWidth: 0.6))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var noteField: some View {
        HStack(spacing: 10) {
            Image(systemName: "text.bubble.fill")
                .font(.system(size: 12, weight: .heavy))
                .foregroundStyle(.white.opacity(0.55))
            TextField("", text: $note,
                      prompt: Text("Add note (optional)").foregroundStyle(.white.opacity(0.4)))
                .focused($noteFocused)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .submitLabel(.done)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .background(.white.opacity(0.08), in: .rect(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12)
            .stroke(noteFocused ? Theme.ember.opacity(0.7) : .white.opacity(0.14), lineWidth: 0.8))
    }

    private func shortLabel(for type: DamageMarkerType) -> String {
        switch type {
        case .hailHits: return "Hail"
        case .windCreasing: return "Wind"
        case .cracking: return "Crack"
        case .missingShingles: return "Missing"
        default: return type.display
        }
    }
}
