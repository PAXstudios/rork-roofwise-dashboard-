import SwiftUI

struct CustomerProfileView: View {
    @Environment(CustomerStore.self) private var store
    @Environment(TrainingProgressStore.self) private var trainingProgress
    @Environment(\.dismiss) private var dismiss

    let customerID: UUID

    @State private var showStagePicker = false
    @State private var showAddNote = false
    @State private var newNoteText = ""
    @State private var previewPhoto: CapturedPhoto?
    @State private var slopeBeingViewed: SlopeType?
    @State private var isEditing = false
    @State private var draft: Customer?
    @State private var showHomeownerShare = false
    @State private var showCoach = false
    @State private var coachTipLesson: Lesson? = nil

    private var customer: Customer {
        store.customers.first { $0.id == customerID }
            ?? Customer(ownerName: "Unknown", address: "")
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                header
                if customer.isUnassignedDraft {
                    assignPropertyPrompt
                }
                shareHomeownerButton
                practiceCoachButton
                coachTipCard
                stagePipeline
                PropertyStormHistoryCard(customer: customer)
                contactCard
                insuranceCard
                photosSection
                damageSection
                notesSection
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 40)
            .padding(.top, 8)
        }
        .background(Theme.canvas)
        .navigationTitle(customer.ownerName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    if isEditing { saveEdits() } else { startEditing() }
                } label: {
                    Text(isEditing ? "Done" : "Edit")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Theme.ember)
                }
            }
        }
        .sheet(isPresented: $showStagePicker) {
            StagePickerSheet(current: customer.stage) { newStage in
                store.updateStage(customer.id, to: newStage)
                showStagePicker = false
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showAddNote) {
            AddNoteSheet(text: $newNoteText) {
                store.addNote(newNoteText, to: customer.id)
                newNoteText = ""
                showAddNote = false
            } onCancel: {
                newNoteText = ""
                showAddNote = false
            }
            .presentationDetents([.medium])
        }
        .sheet(isPresented: $showHomeownerShare) {
            HomeownerShareSheet(customer: customer)
                .presentationDetents([.large])
                .presentationDragIndicator(.hidden)
        }
        .sheet(isPresented: $showCoach) {
            @Bindable var bindable = trainingProgress
            RolePlayCoachView(progress: bindable,
                              customerContext: customerCoachContext)
        }
        .sheet(item: $coachTipLesson) { lesson in
            @Bindable var bindable = trainingProgress
            LessonDetailView(lesson: lesson, progress: bindable)
        }
        .sheet(item: $slopeBeingViewed) { slope in
            SlopePhotosSheet(
                slope: slope,
                photos: customer.photos.filter { $0.slope == slope },
                onSelect: { picked in
                    slopeBeingViewed = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        previewPhoto = picked
                    }
                },
                onClose: { slopeBeingViewed = nil }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .fullScreenCover(item: $previewPhoto) { photo in
            PhotoDamageOverlayView(
                photo: photo,
                onClose: { previewPhoto = nil },
                onDelete: {
                    var c = customer
                    c.photos.removeAll { $0.id == photo.id }
                    store.update(c)
                    previewPhoto = nil
                },
                onRetry: {
                    let result = await GeminiAnalysisService.analyzeFull(
                        image: photo.image,
                        slope: photo.slope,
                        mode: photo.captureMode,
                        squaresCovered: photo.squaresCovered
                    )
                    var c = customer
                    if let idx = c.photos.firstIndex(where: { $0.id == photo.id }) {
                        c.photos[idx].findings = result.findings
                        c.photos[idx].damageMarkers = result.markers
                        c.photos[idx].analyzed = !result.failed
                        store.update(c)
                        previewPhoto = c.photos[idx]
                    }
                    let g = UINotificationFeedbackGenerator()
                    g.notificationOccurred(result.failed ? .error : .success)
                }
            )
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle().fill(customer.stage.color.opacity(0.16))
                Text(customer.initials)
                    .font(.system(size: 26, weight: .heavy))
                    .foregroundStyle(customer.stage.color)
            }
            .frame(width: 78, height: 78)

            VStack(spacing: 4) {
                Text(customer.ownerName)
                    .font(.system(size: 20, weight: .heavy))
                    .foregroundStyle(Theme.ink)
                Text(customer.address)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.inkSoft)
                    .multilineTextAlignment(.center)
            }

            HStack(spacing: 8) {
                if customer.stormTagged {
                    Label("Storm Lead", systemImage: "bolt.fill")
                        .labelStyle(.titleAndIcon)
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(Theme.ember)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Theme.emberSoft, in: .capsule)
                }
                if !customer.estimatedValue.isEmpty {
                    Text(customer.estimatedValue)
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(Theme.ink)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Theme.canvas, in: .capsule)
                        .overlay(Capsule().stroke(Theme.hairline, lineWidth: 0.6))
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .padding(.horizontal, 14)
        .background(Theme.card, in: .rect(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(Theme.hairline, lineWidth: 0.6))
    }

    // MARK: Assign Property

    private var assignPropertyPrompt: some View {
        Button { startEditing() } label: {
            HStack(spacing: 12) {
                Image(systemName: "house.and.flag.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(Theme.amber, in: .rect(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 3) {
                    Text("Assign Property")
                        .font(.system(size: 14, weight: .heavy))
                        .foregroundStyle(Theme.ink)
                    Text("Add the customer name and address for these saved photos.")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.inkSoft)
                        .multilineTextAlignment(.leading)
                }

                Spacer()
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.amber)
            }
            .padding(14)
            .background(Theme.amber.opacity(0.12), in: .rect(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.amber.opacity(0.35), lineWidth: 0.8))
        }
        .buttonStyle(.plain)
    }

    // MARK: Share with Homeowner

    private var shareHomeownerButton: some View {
        Button { showHomeownerShare = true } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.white.opacity(0.22))
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                }
                .frame(width: 38, height: 38)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Share with Homeowner")
                        .font(.system(size: 14, weight: .heavy))
                        .foregroundStyle(.white)
                    Text("One-page recap · text, email, or AirDrop")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.85))
                }
                Spacer()
                Image(systemName: "arrow.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
            }
            .padding(14)
            .background(
                LinearGradient(colors: [Theme.ember, Theme.emberDeep],
                               startPoint: .topLeading, endPoint: .bottomTrailing),
                in: .rect(cornerRadius: 18)
            )
            .shadow(color: Theme.ember.opacity(0.35), radius: 14, y: 8)
        }
        .buttonStyle(.plain)
    }

    // MARK: Practice Coach Button

    private var practiceCoachButton: some View {
        let sessions = trainingProgress.customerCoachSessions[customerID] ?? 0
        let lastScore = trainingProgress.customerCoachLastScore[customerID]
        return Button { showCoach = true } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.white.opacity(0.22))
                    Image(systemName: "mic.and.signal.meter.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                }
                .frame(width: 38, height: 38)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Practice this approach")
                        .font(.system(size: 14, weight: .heavy))
                        .foregroundStyle(.white)
                    Text(practiceSubtitle(sessions: sessions, lastScore: lastScore))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(1)
                }
                Spacer()
                if let score = lastScore {
                    Text("\(score)")
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(.white.opacity(0.22), in: .capsule)
                } else {
                    Image(systemName: "sparkles")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .padding(14)
            .background(
                LinearGradient(colors: [Theme.sky, Color(red: 0.12, green: 0.36, blue: 0.78)],
                               startPoint: .topLeading, endPoint: .bottomTrailing),
                in: .rect(cornerRadius: 18)
            )
            .shadow(color: Theme.sky.opacity(0.35), radius: 14, y: 8)
        }
        .buttonStyle(.plain)
    }

    private func practiceSubtitle(sessions: Int, lastScore: Int?) -> String {
        if sessions == 0 {
            return "Role-play this exact pitch with AI coach"
        }
        if let score = lastScore {
            return "\(sessions) rep\(sessions == 1 ? "" : "s") · last score \(score)"
        }
        return "\(sessions) practice rep\(sessions == 1 ? "" : "s") logged"
    }

    // MARK: Coach Tip Card

    private var coachTipCard: some View {
        let lessonID = customer.stage.coachLessonID
        let lesson = TrainingCurriculum.lessons.first { $0.id == lessonID }
        return Button {
            coachTipLesson = lesson
        } label: {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(customer.stage.color.opacity(0.16))
                    Image(systemName: "lightbulb.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(customer.stage.color)
                }
                .frame(width: 38, height: 38)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text("COACH TIP")
                            .font(.system(size: 9, weight: .heavy))
                            .tracking(0.6)
                            .foregroundStyle(customer.stage.color)
                        Text("· \(customer.stage.shortLabel)")
                            .font(.system(size: 9, weight: .heavy))
                            .tracking(0.4)
                            .foregroundStyle(Theme.inkFaint)
                    }
                    Text(customer.stage.coachTip)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    if let lesson {
                        HStack(spacing: 4) {
                            Text("Open lesson: \(lesson.title)")
                                .font(.system(size: 11, weight: .heavy))
                                .foregroundStyle(customer.stage.color)
                                .lineLimit(1)
                            Image(systemName: "arrow.right")
                                .font(.system(size: 9, weight: .heavy))
                                .foregroundStyle(customer.stage.color)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: .rect(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18)
                .stroke(customer.stage.color.opacity(0.30), lineWidth: 0.8))
        }
        .buttonStyle(.plain)
        .disabled(lesson == nil)
    }

    // MARK: Customer coach context builder

    private var customerCoachContext: CustomerCoachContext {
        // Pull plain-text snippets from the most recent notes — these are
        // the rep's own captured objections and follow-ups.
        let recentNotes = customer.notes.prefix(3).map(\.text)
        return CustomerCoachContext(
            customerID: customer.id,
            ownerName: customer.ownerName,
            address: customer.address,
            stage: customer.stage,
            insuranceCompany: customer.insuranceCompany,
            recentObjections: recentNotes,
            lastInteraction: customer.notes.first.map { Self.dateFmt.string(from: $0.date) }
        )
    }

    // MARK: Pipeline

    private var stagePipeline: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Job Pipeline")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(Theme.ink)
                Spacer()
                Button { showStagePicker = true } label: {
                    HStack(spacing: 4) {
                        Text("Change")
                            .font(.system(size: 11, weight: .semibold))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .bold))
                    }
                    .foregroundStyle(Theme.ember)
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 10) {
                Image(systemName: customer.stage.icon)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(customer.stage.color, in: .rect(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 2) {
                    Text(customer.stage.rawValue.uppercased())
                        .font(.system(size: 10, weight: .heavy))
                        .tracking(0.6)
                        .foregroundStyle(customer.stage.color)
                    Text("Step \(customer.stage.stepIndex + 1) of \(JobPipelineStage.allCases.count)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.inkSoft)
                }
                Spacer()
            }

            // Progress dots
            HStack(spacing: 4) {
                ForEach(JobPipelineStage.allCases) { s in
                    Capsule()
                        .fill(s.stepIndex <= customer.stage.stepIndex ? customer.stage.color : Theme.hairline)
                        .frame(height: 5)
                }
            }
        }
        .padding(16)
        .background(Theme.card, in: .rect(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.hairline, lineWidth: 0.6))
    }

    // MARK: Contact

    private var contactCard: some View {
        sectionCard(title: "Contact", icon: "person.crop.circle.fill", tint: Theme.sky) {
            if isEditing, draft != nil {
                editableRow(label: "Owner",
                            text: Binding(get: { draft?.ownerName ?? "" },
                                          set: { draft?.ownerName = $0 }))
                editableRow(label: "Address",
                            text: Binding(get: { draft?.address ?? "" },
                                          set: { draft?.address = $0 }))
                editableRow(label: "Phone",
                            text: Binding(get: { draft?.phone ?? "" },
                                          set: { draft?.phone = $0 }), keyboard: .phonePad)
                editableRow(label: "Email",
                            text: Binding(get: { draft?.email ?? "" },
                                          set: { draft?.email = $0 }), keyboard: .emailAddress)
            } else {
                infoRow(label: "Phone", value: customer.phone, action: customer.phone.isEmpty ? nil : "phone.fill")
                infoRow(label: "Email", value: customer.email, action: customer.email.isEmpty ? nil : "envelope.fill")
                infoRow(label: "Address", value: customer.address, action: "map.fill")
            }
        }
    }

    // MARK: Insurance

    private var insuranceCard: some View {
        sectionCard(title: "Insurance & Claim", icon: "shield.lefthalf.filled", tint: Theme.amber) {
            if isEditing, draft != nil {
                editableRow(label: "Carrier",
                            text: Binding(get: { draft?.insuranceCompany ?? "" },
                                          set: { draft?.insuranceCompany = $0 }))
                editableRow(label: "Policy #",
                            text: Binding(get: { draft?.policyNumber ?? "" },
                                          set: { draft?.policyNumber = $0 }))
                editableRow(label: "Adjuster",
                            text: Binding(get: { draft?.adjusterName ?? "" },
                                          set: { draft?.adjusterName = $0 }))
                editableRow(label: "Adj. Phone",
                            text: Binding(get: { draft?.adjusterPhone ?? "" },
                                          set: { draft?.adjusterPhone = $0 }), keyboard: .phonePad)
                HStack {
                    Text("Date of Loss")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.inkSoft)
                    Spacer()
                    DatePicker("",
                               selection: Binding(get: { draft?.dateOfLoss ?? .now },
                                                  set: { draft?.dateOfLoss = $0 }),
                               displayedComponents: .date)
                        .labelsHidden()
                }
            } else {
                infoRow(label: "Carrier", value: customer.insuranceCompany)
                infoRow(label: "Policy #", value: customer.policyNumber)
                infoRow(label: "Date of Loss",
                        value: customer.dateOfLoss.map { Self.dateFmt.string(from: $0) } ?? "")
                infoRow(label: "Adjuster", value: customer.adjusterName)
                infoRow(label: "Adj. Phone", value: customer.adjusterPhone,
                        action: customer.adjusterPhone.isEmpty ? nil : "phone.fill")
                if let grade = customer.claimGrade {
                    HStack(spacing: 8) {
                        Image(systemName: grade.icon)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(grade.color)
                        Text(grade.rawValue)
                            .font(.system(size: 12, weight: .heavy))
                            .foregroundStyle(grade.color)
                        Spacer()
                    }
                    .padding(10)
                    .background(grade.color.opacity(0.1), in: .rect(cornerRadius: 12))
                }
            }
        }
    }

    // MARK: Photos (slope-grouped damage cards)

    private var slopeGroups: [(slope: SlopeType, photos: [CapturedPhoto])] {
        let dict = Dictionary(grouping: customer.photos, by: \.slope)
        return SlopeType.allCases.compactMap { s in
            guard let items = dict[s], !items.isEmpty else { return nil }
            let sorted = items.sorted { $0.timestamp > $1.timestamp }
            return (s, sorted)
        }
    }

    private var totalDamageMarkers: Int {
        customer.photos.reduce(0) { $0 + $1.damageMarkers.count }
    }

    private var photosSection: some View {
        sectionCard(title: "Damaged Photos by Slope", icon: "photo.stack.fill", tint: Theme.ember,
                    trailing: AnyView(
                        HStack(spacing: 4) {
                            Image(systemName: "scope")
                                .font(.system(size: 9, weight: .heavy))
                                .foregroundStyle(Theme.crimson)
                            Text("\(totalDamageMarkers)")
                                .font(.system(size: 11, weight: .heavy))
                                .foregroundStyle(Theme.ink)
                                .monospacedDigit()
                        }
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(Theme.crimson.opacity(0.10), in: .capsule)
                    )) {
            if customer.photos.isEmpty {
                emptyState(icon: "camera.viewfinder",
                           title: "No photos yet",
                           subtitle: "Photos taken during Quick Inspection auto-attach here.")
            } else {
                VStack(spacing: 10) {
                    ForEach(slopeGroups, id: \.slope) { group in
                        Button {
                            let g = UIImpactFeedbackGenerator(style: .light); g.impactOccurred()
                            slopeBeingViewed = group.slope
                        } label: {
                            slopeDamageCard(slope: group.slope, photos: group.photos)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func slopeDamageCard(slope: SlopeType, photos: [CapturedPhoto]) -> some View {
        let markers = photos.reduce(0) { $0 + $1.damageMarkers.count }
        let worst: FindingSeverity = photos
            .map(\.worstSeverity)
            .max(by: { $0.rank < $1.rank }) ?? .none
        let preview = Array(photos.prefix(3))
        let extra = max(0, photos.count - preview.count)
        let damageTypes: [DamageMarkerType] = {
            let all = photos.flatMap { $0.damageMarkers.map(\.type) }
            var seen = Set<DamageMarkerType>()
            return all.filter { seen.insert($0).inserted }
        }()

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 11).fill(Theme.emberSoft)
                    Image(systemName: slope.icon)
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(Theme.ember)
                }
                .frame(width: 38, height: 38)
                VStack(alignment: .leading, spacing: 2) {
                    Text(slope.shortName)
                        .font(.system(size: 14, weight: .heavy))
                        .foregroundStyle(Theme.ink)
                    HStack(spacing: 6) {
                        Text("\(photos.count) photo\(photos.count == 1 ? "" : "s")")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Theme.inkSoft)
                        if markers > 0 {
                            Text("·")
                                .font(.system(size: 11, weight: .heavy))
                                .foregroundStyle(Theme.inkFaint)
                            HStack(spacing: 3) {
                                Image(systemName: "scope")
                                    .font(.system(size: 9, weight: .heavy))
                                Text("\(markers) marker\(markers == 1 ? "" : "s")")
                                    .font(.system(size: 11, weight: .heavy))
                            }
                            .foregroundStyle(Theme.crimson)
                        }
                    }
                }
                Spacer(minLength: 0)
                if worst != .none {
                    Text(worst.rawValue.uppercased())
                        .font(.system(size: 9, weight: .heavy))
                        .tracking(0.8)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(worst.color, in: .capsule)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(Theme.inkFaint)
            }

            // Photo strip with marker dots overlaid
            HStack(spacing: 8) {
                ForEach(preview) { photo in
                    slopePhotoPreview(photo)
                }
                if extra > 0 {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12).fill(Theme.canvas)
                        VStack(spacing: 2) {
                            Text("+\(extra)")
                                .font(.system(size: 15, weight: .heavy))
                                .foregroundStyle(Theme.ink)
                            Text("more")
                                .font(.system(size: 9, weight: .heavy))
                                .tracking(0.6)
                                .foregroundStyle(Theme.inkFaint)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 78)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.hairline, lineWidth: 0.6))
                }
            }

            if !damageTypes.isEmpty {
                HStack(spacing: 6) {
                    ForEach(damageTypes.prefix(4), id: \.self) { t in
                        HStack(spacing: 4) {
                            Image(systemName: t.icon)
                                .font(.system(size: 9, weight: .heavy))
                            Text(t.display)
                                .font(.system(size: 10, weight: .heavy))
                                .lineLimit(1)
                        }
                        .foregroundStyle(t.color)
                        .padding(.horizontal, 7).padding(.vertical, 4)
                        .background(t.color.opacity(0.12), in: .capsule)
                        .overlay(Capsule().stroke(t.color.opacity(0.3), lineWidth: 0.5))
                    }
                    Spacer(minLength: 0)
                }
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundStyle(Theme.mint)
                    Text("No AI damage detected on this slope")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.inkSoft)
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.canvas, in: .rect(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.hairline, lineWidth: 0.6))
    }

    private func slopePhotoPreview(_ photo: CapturedPhoto) -> some View {
        Color(.secondarySystemBackground)
            .frame(maxWidth: .infinity)
            .frame(height: 78)
            .overlay {
                Image(uiImage: photo.image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .allowsHitTesting(false)
            }
            .clipShape(.rect(cornerRadius: 12))
            .overlay {
                GeometryReader { geo in
                    ForEach(photo.damageMarkers) { marker in
                        Circle()
                            .fill(marker.type.color.opacity(0.95))
                            .overlay(Circle().stroke(.white, lineWidth: 1))
                            .frame(width: 7, height: 7)
                            .position(x: marker.x * geo.size.width,
                                      y: marker.y * geo.size.height)
                    }
                }
                .allowsHitTesting(false)
            }
            .overlay(alignment: .topLeading) {
                if photo.damageMarkers.count > 0 {
                    Text("\(photo.damageMarkers.count)")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(Theme.crimson, in: .capsule)
                        .padding(5)
                }
            }
            .overlay(alignment: .bottomLeading) {
                if photo.analyzed {
                    HStack(spacing: 3) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 8, weight: .heavy))
                        Text("AI")
                            .font(.system(size: 8, weight: .heavy))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(Theme.ember, in: .capsule)
                    .padding(5)
                }
            }
    }

    private func photoThumb(_ photo: CapturedPhoto) -> some View {
        Color.black
            .frame(width: 110, height: 140)
            .overlay {
                Image(uiImage: photo.image)
                    .resizable().aspectRatio(contentMode: .fill)
                    .allowsHitTesting(false)
            }
            .clipShape(.rect(cornerRadius: 14))
            .overlay(alignment: .topLeading) {
                Text(photo.slope.shortLabel)
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(.black.opacity(0.55), in: .capsule)
                    .padding(6)
            }
            .overlay(alignment: .bottomTrailing) {
                if photo.analyzed {
                    Image(systemName: "sparkles")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(5)
                        .background(Theme.ember, in: .circle)
                        .padding(6)
                }
            }
    }

    // MARK: Damage analysis

    private var damageSection: some View {
        sectionCard(title: "Damage Analysis", icon: "scope", tint: Theme.crimson) {
            if customer.damageFindings.isEmpty && customer.claimPacketSummary.isEmpty {
                emptyState(icon: "waveform.path.ecg",
                           title: "No analysis yet",
                           subtitle: "Run a Quick Inspection to populate findings.")
            } else {
                if !customer.claimPacketSummary.isEmpty {
                    Text(customer.claimPacketSummary)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.inkSoft)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.canvas, in: .rect(cornerRadius: 12))
                }
                ForEach(customer.damageFindings.filter(\.detected).prefix(6)) { f in
                    HStack(spacing: 10) {
                        Image(systemName: f.icon)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(f.tint)
                            .frame(width: 28, height: 28)
                            .background(f.tint.opacity(0.14), in: .rect(cornerRadius: 8))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(f.display)
                                .font(.system(size: 13, weight: .heavy))
                                .foregroundStyle(Theme.ink)
                            Text(f.value)
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.inkSoft)
                                .lineLimit(1)
                        }
                        Spacer()
                        Text(f.severity.rawValue.uppercased())
                            .font(.system(size: 9, weight: .heavy))
                            .tracking(0.4)
                            .foregroundStyle(f.severity.color)
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(f.severity.bg, in: .capsule)
                    }
                }
            }
        }
    }

    // MARK: Notes

    private var notesSection: some View {
        sectionCard(title: "Notes", icon: "note.text", tint: Theme.inkSoft,
                    trailing: AnyView(
                        Button { showAddNote = true } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "plus")
                                    .font(.system(size: 10, weight: .bold))
                                Text("Add")
                                    .font(.system(size: 11, weight: .heavy))
                            }
                            .foregroundStyle(Theme.ember)
                        }
                        .buttonStyle(.plain)
                    )) {
            if customer.notes.isEmpty {
                emptyState(icon: "square.and.pencil",
                           title: "No notes yet",
                           subtitle: "Capture details, conversations, or follow-ups.")
            } else {
                VStack(spacing: 10) {
                    ForEach(customer.notes) { note in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(note.text)
                                .font(.system(size: 13))
                                .foregroundStyle(Theme.ink)
                            Text(Self.dateFmt.string(from: note.date))
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(Theme.inkFaint)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(Theme.canvas, in: .rect(cornerRadius: 12))
                    }
                }
            }
        }
    }

    // MARK: Helpers

    private func sectionCard<C: View>(title: String, icon: String, tint: Color,
                                      trailing: AnyView? = nil,
                                      @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(tint)
                    .frame(width: 22, height: 22)
                    .background(tint.opacity(0.14), in: .rect(cornerRadius: 7))
                Text(title)
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(Theme.ink)
                Spacer()
                if let trailing { trailing }
            }
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: .rect(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.hairline, lineWidth: 0.6))
    }

    private func infoRow(label: String, value: String, action: String? = nil) -> some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.inkSoft)
                .frame(width: 92, alignment: .leading)
            Text(value.isEmpty ? "—" : value)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(value.isEmpty ? Theme.inkFaint : Theme.ink)
                .lineLimit(2)
            Spacer(minLength: 0)
            if let action {
                Image(systemName: action)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Theme.ember)
                    .frame(width: 28, height: 28)
                    .background(Theme.emberSoft, in: .circle)
            }
        }
    }

    private func editableRow(label: String, text: Binding<String>,
                             keyboard: UIKeyboardType = .default) -> some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.inkSoft)
                .frame(width: 92, alignment: .leading)
            TextField(label, text: text)
                .keyboardType(keyboard)
                .autocorrectionDisabled(keyboard == .emailAddress || keyboard == .phonePad)
                .textInputAutocapitalization(keyboard == .emailAddress ? .never : .words)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 10).padding(.vertical, 8)
                .background(Theme.canvas, in: .rect(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.hairline, lineWidth: 0.6))
        }
    }

    private func emptyState(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Theme.inkFaint)
            Text(title)
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(Theme.ink)
            Text(subtitle)
                .font(.system(size: 11))
                .foregroundStyle(Theme.inkFaint)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
    }

    private func startEditing() {
        draft = customer
        withAnimation(.spring(duration: 0.25)) { isEditing = true }
    }

    private func saveEdits() {
        if let d = draft { store.update(d) }
        draft = nil
        withAnimation(.spring(duration: 0.25)) { isEditing = false }
    }

    static let dateFmt: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .none; return f
    }()
}

// MARK: - Stage Picker

private struct StagePickerSheet: View {
    let current: JobPipelineStage
    let onPick: (JobPipelineStage) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Update Pipeline Stage")
                    .font(.system(size: 20, weight: .heavy))
                    .foregroundStyle(Theme.ink)
                Text("Move this customer through the job pipeline.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.inkSoft)

                VStack(spacing: 8) {
                    ForEach(JobPipelineStage.allCases) { s in
                        Button { onPick(s) } label: {
                            HStack(spacing: 12) {
                                Image(systemName: s.icon)
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(.white)
                                    .frame(width: 36, height: 36)
                                    .background(s.color, in: .rect(cornerRadius: 11))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(s.rawValue)
                                        .font(.system(size: 14, weight: .heavy))
                                        .foregroundStyle(Theme.ink)
                                    Text("Step \(s.stepIndex + 1)")
                                        .font(.system(size: 11))
                                        .foregroundStyle(Theme.inkFaint)
                                }
                                Spacer()
                                if s == current {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 18, weight: .bold))
                                        .foregroundStyle(Theme.ember)
                                }
                            }
                            .padding(12)
                            .background(s == current ? s.color.opacity(0.08) : Theme.canvas,
                                        in: .rect(cornerRadius: 14))
                            .overlay(RoundedRectangle(cornerRadius: 14)
                                .stroke(s == current ? s.color.opacity(0.4) : Theme.hairline,
                                        lineWidth: 0.8))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(20)
        }
        .background(Theme.canvas)
    }
}

// MARK: - Add Note Sheet

private struct AddNoteSheet: View {
    @Binding var text: String
    let onSave: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Add Note")
                    .font(.system(size: 20, weight: .heavy))
                    .foregroundStyle(Theme.ink)
                Spacer()
                Button("Cancel", action: onCancel)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.inkSoft)
            }
            TextEditor(text: $text)
                .font(.system(size: 14))
                .scrollContentBackground(.hidden)
                .padding(12)
                .frame(minHeight: 140)
                .background(Theme.canvas, in: .rect(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.hairline, lineWidth: 0.6))

            Button(action: onSave) {
                Text("Save Note")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Theme.ember, in: .rect(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .opacity(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.5 : 1)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - SlopeType helper

private extension SlopeType {
    var shortLabel: String {
        rawValue.split(separator: " ").first.map(String.init) ?? rawValue
    }
}
