import SwiftUI
import CoreLocation

/// Sheet for logging a single knock against the active KnockSession.
/// Pre-filled with the rep's current CLLocation. Voice-input on notes is a
/// stub (mic toggles a visual state) — wiring SFSpeechRecognizer is out of
/// scope for this phase.
struct LogKnockSheet: View {
    @Environment(\.dismiss) private var dismiss

    let coord: CLLocationCoordinate2D
    let sessionId: UUID
    /// Called after a successful save so the parent can update its map.
    var onSaved: (Knock) -> Void = { _ in }

    @State private var outcome: KnockSessionOutcome = .not_home
    @State private var notes: String = ""
    @State private var followUpDate: Date = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
    @State private var followUpPreset: FollowUpPreset = .tomorrow
    @State private var showCustomPicker: Bool = false
    @State private var address: String? = nil
    @State private var isResolvingAddress: Bool = false
    @State private var isVoiceListening: Bool = false

    private let geocoder: GeocodingService = GeocodingServiceFactory.shared

    enum FollowUpPreset: String, CaseIterable, Identifiable {
        case tomorrow, threeDays, oneWeek, custom
        var id: String { rawValue }
        var label: String {
            switch self {
            case .tomorrow: return "Tomorrow"
            case .threeDays: return "3 Days"
            case .oneWeek: return "1 Week"
            case .custom: return "Custom"
            }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    addressCard
                    outcomeGrid
                    notesField
                    if outcome == .follow_up {
                        followUpRow
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                    Color.clear.frame(height: 100)
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
            }
            .background(Theme.canvas)
            .navigationBarTitleDisplayMode(.inline)
            .navigationTitle("Log Knock")
            .safeAreaInset(edge: .bottom) { bottomBar }
            .sheet(isPresented: $showCustomPicker) {
                NavigationStack {
                    VStack(spacing: 16) {
                        DatePicker(
                            "Follow-up date",
                            selection: $followUpDate,
                            in: Date()...,
                            displayedComponents: [.date]
                        )
                        .datePickerStyle(.graphical)
                        .padding(.horizontal, 16)
                        Spacer()
                    }
                    .padding(.top, 16)
                    .navigationTitle("Pick a date")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") { showCustomPicker = false }
                                .font(.system(size: Theme.TypeRamp.bodyTight, weight: .heavy))
                        }
                    }
                }
                .presentationDetents([.medium, .large])
            }
            .task { await resolveAddress() }
            .animation(.spring(response: 0.3, dampingFraction: 0.85), value: outcome)
        }
    }

    // MARK: - Sections

    private var addressCard: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12).fill(Theme.skySoft)
                Image(systemName: "mappin.and.ellipse")
                    .font(.system(size: Theme.TypeRamp.subhead, weight: .heavy))
                    .foregroundStyle(Theme.sky)
            }
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 2) {
                Text("CURRENT LOCATION")
                    .font(.system(size: Theme.TypeRamp.captionSm, weight: .heavy))
                    .tracking(1.2)
                    .foregroundStyle(Theme.inkFaint)
                if let address {
                    Text(address)
                        .font(.system(size: Theme.TypeRamp.body, weight: .heavy))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(2)
                } else {
                    Text(isResolvingAddress
                         ? "Resolving address…"
                         : String(format: "%.5f, %.5f", coord.latitude, coord.longitude))
                        .font(.system(size: Theme.TypeRamp.body, weight: .heavy))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(2)
                }
            }
            Spacer()
        }
        .padding(14)
        .cardStyle(padding: 0, radius: 16)
    }

    private var outcomeGrid: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("OUTCOME")
                .font(.system(size: Theme.TypeRamp.captionSm, weight: .heavy))
                .tracking(1.2)
                .foregroundStyle(Theme.inkFaint)
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 10),
                GridItem(.flexible(), spacing: 10)
            ], spacing: 10) {
                ForEach(KnockSessionOutcome.allCases) { o in
                    outcomeChip(o)
                }
            }
        }
    }

    private func outcomeChip(_ o: KnockSessionOutcome) -> some View {
        Button {
            let g = UISelectionFeedbackGenerator(); g.selectionChanged()
            withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                outcome = o
            }
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    Circle().fill(color(for: o))
                    Image(systemName: o.icon)
                        .font(.system(size: Theme.TypeRamp.captionSm, weight: .heavy))
                        .foregroundStyle(.white)
                }
                .frame(width: 28, height: 28)
                Text(o.label.uppercased())
                    .font(.system(size: Theme.TypeRamp.metaSm, weight: .heavy))
                    .foregroundStyle(outcome == o ? .white : Theme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 64)
            .background(
                outcome == o ? AnyShapeStyle(color(for: o)) : AnyShapeStyle(Theme.card),
                in: .rect(cornerRadius: 14)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(outcome == o ? .clear : Theme.hairline, lineWidth: 0.6)
            )
        }
        .buttonStyle(.plain)
    }

    private var notesField: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("NOTES")
                    .font(.system(size: Theme.TypeRamp.captionSm, weight: .heavy))
                    .tracking(1.2)
                    .foregroundStyle(Theme.inkFaint)
                Spacer()
                Button {
                    let g = UIImpactFeedbackGenerator(style: .light); g.impactOccurred()
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                        isVoiceListening.toggle()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: isVoiceListening ? "mic.fill" : "mic")
                            .font(.system(size: Theme.TypeRamp.metaSm, weight: .heavy))
                        Text(isVoiceListening ? "Listening…" : "Voice")
                            .font(.system(size: Theme.TypeRamp.metaSm, weight: .heavy))
                    }
                    .foregroundStyle(isVoiceListening ? .white : Theme.ember)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(
                        isVoiceListening ? AnyShapeStyle(Theme.ember) : AnyShapeStyle(Theme.emberSoft),
                        in: .capsule
                    )
                }
                .buttonStyle(.plain)
            }
            TextEditor(text: $notes)
                .font(.system(size: Theme.TypeRamp.body))
                .scrollContentBackground(.hidden)
                .frame(minHeight: 96)
                .padding(12)
                .background(Theme.card, in: .rect(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.hairline, lineWidth: 0.6))
        }
    }

    private var followUpRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("FOLLOW-UP DATE")
                .font(.system(size: Theme.TypeRamp.captionSm, weight: .heavy))
                .tracking(1.2)
                .foregroundStyle(Theme.inkFaint)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(FollowUpPreset.allCases) { p in
                        followUpChip(p)
                    }
                }
            }
            Text("Scheduled: \(followUpDate.formatted(date: .abbreviated, time: .omitted))")
                .font(.system(size: Theme.TypeRamp.metaSm))
                .foregroundStyle(Theme.inkSoft)
        }
    }

    private func followUpChip(_ p: FollowUpPreset) -> some View {
        Button {
            let g = UISelectionFeedbackGenerator(); g.selectionChanged()
            followUpPreset = p
            switch p {
            case .tomorrow:
                followUpDate = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
            case .threeDays:
                followUpDate = Calendar.current.date(byAdding: .day, value: 3, to: Date()) ?? Date()
            case .oneWeek:
                followUpDate = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
            case .custom:
                showCustomPicker = true
            }
        } label: {
            Text(p.label.uppercased())
                .font(.system(size: Theme.TypeRamp.metaSm, weight: .heavy))
                .tracking(0.8)
                .foregroundStyle(followUpPreset == p ? .white : Theme.ink)
                .padding(.horizontal, 18)
                .frame(minHeight: 64)
                .background(
                    followUpPreset == p ? AnyShapeStyle(Theme.ink) : AnyShapeStyle(Theme.card),
                    in: .capsule
                )
                .overlay(
                    Capsule()
                        .stroke(followUpPreset == p ? .clear : Theme.hairline, lineWidth: 0.6)
                )
        }
        .buttonStyle(.plain)
    }

    private var bottomBar: some View {
        VStack(spacing: 8) {
            Button {
                let g = UIImpactFeedbackGenerator(style: .medium); g.impactOccurred()
                save()
            } label: {
                Text("Save Knock")
                    .font(.system(size: Theme.TypeRamp.cta, weight: .heavy))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 64)
                    .background(Theme.ink, in: .capsule)
            }
            .buttonStyle(.plain)

            Button {
                dismiss()
            } label: {
                Text("Cancel")
                    .font(.system(size: Theme.TypeRamp.bodyTight, weight: .heavy))
                    .foregroundStyle(Theme.inkSoft)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .frame(minHeight: 88)
        .background(.ultraThinMaterial)
    }

    // MARK: - Helpers

    private func color(for o: KnockSessionOutcome) -> Color {
        switch o {
        case .interested: return Theme.mint
        case .inspection_scheduled: return Theme.ink
        case .not_home: return Theme.inkFaint
        case .not_interested: return Theme.ember
        case .follow_up: return Theme.amber
        }
    }

    private func resolveAddress() async {
        isResolvingAddress = true
        defer { isResolvingAddress = false }
        // Best-effort reverse-geocode. GeocodingService only exposes forward
        // geocoding, so fall back to CLGeocoder directly.
        let cl = CLGeocoder()
        let loc = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
        if let placemark = try? await cl.reverseGeocodeLocation(loc).first {
            let parts = [placemark.subThoroughfare, placemark.thoroughfare, placemark.locality]
                .compactMap { $0 }
            let resolved = parts.joined(separator: " ")
            if !resolved.isEmpty {
                address = resolved
            }
        }
    }

    private func save() {
        let knock = Knock(
            lat: coord.latitude,
            lng: coord.longitude,
            address: address,
            outcome: outcome,
            notes: notes.isEmpty ? nil : notes,
            follow_up_date: outcome == .follow_up ? followUpDate : nil
        )
        KnockSessionStore.shared.append(knock: knock, to: sessionId)

        // Auto-create a Lead/Inspection draft on positive outcomes.
        var stamped = knock
        if outcome == .interested || outcome == .inspection_scheduled {
            let leadId = createLeadDraft(for: knock)
            stamped.created_lead_id = leadId
            KnockSessionStore.shared.setCreatedLead(leadId, knockId: knock.id, sessionId: sessionId)
            ActivityStore.shared.log(
                .knockConvertedToLead,
                summary: "Knock converted to lead",
                detail: leadId,
                reportId: leadId
            )
        }

        ActivityStore.shared.log(
            .knockLogged,
            summary: "Knock logged · \(outcome.label)",
            detail: address,
            reportId: "doorKnocking.knockSaved"
        )

        let g = UINotificationFeedbackGenerator(); g.notificationOccurred(.success)
        onSaved(stamped)
        dismiss()
    }

    private func createLeadDraft(for knock: Knock) -> String {
        var draft = InspectionStore.shared.makeDraft()
        draft.job.propertyAddress = knock.address ?? String(format: "%.5f, %.5f", knock.lat, knock.lng)
        draft.job.clientName = knock.address ?? "Door-knock lead"
        InspectionStore.shared.add(draft)
        return draft.job.reportId
    }
}

#Preview {
    LogKnockSheet(
        coord: .init(latitude: 33.0631, longitude: -96.7517),
        sessionId: UUID()
    )
}
