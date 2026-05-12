import SwiftUI
import CoreLocation

struct JobDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var store = InspectionStore.shared
    @State private var showAddSlope = false
    @State private var editingOrientation: String? = nil
    @State private var slopePendingDelete: Slope? = nil
    @State private var showSignatures = false
    @State private var pdfShareURL: URL? = nil
    @State private var isGenerating = false
    @State private var showWeather = false
    @State private var stormMatchFocus: StormPinEvent? = nil
    @State private var showStormOnMap = false
    @State private var roofMeasurements: RoofMeasurements? = nil
    @State private var showSolarSheet = false
    @State private var showRoofOnMap = false
    @State private var estimatesStore = EstimatesStore.shared
    @State private var showOriginEstimate = false
    @State private var showActivity = false
    @State private var proposalStore = ProposalStore.shared
    @State private var showProposalEditor = false
    @State private var showProposalSend = false
    @State private var showHomeownerProposal = false
    @State private var pendingProposal: Proposal? = nil

    let reportId: String

    private var inspection: Inspection? {
        store.inspection(with: reportId)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Theme.canvas.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let insp = inspection {
                        header(insp)
                        if !insp.event.weatherSources.isEmpty {
                            stormMatchCard(insp)
                        }
                        roofMeasurementsCard(insp)
                        replacementCostCard(insp)
                        if insp.slopes.isEmpty {
                            emptySlopesCard
                        } else {
                            decisionBanner(insp)
                            slopesSummaryCard(insp)
                            slopesList(insp)
                        }
                        addSlopeButton(label: insp.slopes.isEmpty ? "Add slope" : "Add another slope")
                        if !insp.slopes.isEmpty {
                            signReportCard(insp)
                            proposalSection(insp)
                        }
                        Color.clear.frame(height: 140)
                    } else {
                        Text("Job not found.")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Theme.inkSoft)
                            .padding(.top, 80)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
            }

            generateReportBar
        }
        .navigationTitle("Job")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { dismiss() }
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.ember)
            }
        }
        .navigationDestination(isPresented: $showAddSlope) {
            SlopeCaptureView(reportId: reportId)
        }
        .navigationDestination(item: $editingOrientation) { orient in
            SlopeCaptureView(reportId: reportId, existingOrientation: orient)
        }
        .navigationDestination(isPresented: $showSignatures) {
            SignaturesView(reportId: reportId)
        }
        .navigationDestination(isPresented: $showStormOnMap) {
            MapHubView(currentReportId: reportId, focusedStorm: stormMatchFocus)
        }
        .navigationDestination(isPresented: $showRoofOnMap) {
            MapHubView(
                currentReportId: reportId,
                focusedAddress: inspection?.job.propertyAddress,
                focusedRoof: roofMeasurements
            )
        }
        .task(id: reportId) {
            await store.autoPopulateEvent(for: reportId)
        }
        .task(id: reportId) {
            await loadRoofMeasurements()
        }
        .sheet(isPresented: $showSolarSheet) {
            if let m = roofMeasurements, let insp = inspection {
                SolarMeasurementsSheet(measurements: m, address: insp.job.propertyAddress)
            }
        }
        .sheet(isPresented: $showActivity) {
            ActivityFeedSheet(reportId: reportId)
        }
        .sheet(isPresented: $showProposalEditor) {
            if let p = pendingProposal, let insp = inspection {
                ProposalEditorView(proposal: p, inspection: insp)
            }
        }
        .sheet(isPresented: $showProposalSend) {
            if let p = existingProposal {
                ProposalSendSheet(proposal: p) { sent in
                    proposalStore.update(sent)
                    if let insp = inspection {
                        ActivityStore.shared.log(.proposalSent,
                                                 summary: "Proposal resent",
                                                 detail: sent.sentChannel?.rawValue,
                                                 on: insp)
                    }
                }
            }
        }
        .sheet(isPresented: $showHomeownerProposal) {
            if let p = existingProposal {
                NavigationStack { HomeownerProposalView(proposalId: p.id) }
            }
        }
        .sheet(isPresented: $showOriginEstimate) {
            if let saved = originSavedEstimate {
                CostEstimatorWizard(prefilledSaved: saved)
            }
        }
        .sheet(item: Binding(
            get: { pdfShareURL.map(IdentifiableURL.init) },
            set: { pdfShareURL = $0?.url }
        )) { wrapper in
            PDFPreviewSheet(url: wrapper.url)
        }
        .alert("Remove this slope?",
               isPresented: Binding(get: { slopePendingDelete != nil },
                                    set: { if !$0 { slopePendingDelete = nil } })) {
            Button("Remove", role: .destructive) {
                if let s = slopePendingDelete {
                    store.removeSlope(orientation: s.orientation, on: reportId)
                    UINotificationFeedbackGenerator().notificationOccurred(.warning)
                }
                slopePendingDelete = nil
            }
            Button("Cancel", role: .cancel) { slopePendingDelete = nil }
        } message: {
            Text("All damage scoring for this face will be deleted from the report.")
        }
    }

    private func header(_ insp: Inspection) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(insp.job.clientName.isEmpty ? "Untitled job" : insp.job.clientName)
                .font(.system(size: 24, weight: .heavy))
                .foregroundStyle(Theme.ink)

            Text(insp.job.propertyAddress.isEmpty ? "No address on file" : insp.job.propertyAddress)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.inkSoft)

            HStack(spacing: 8) {
                infoChip(text: insp.job.reportId,
                         icon: "doc.text.fill",
                         tint: Theme.ink)
                if insp.originEstimateId != nil {
                    fromEstimateChip
                }
                if !insp.job.claimNumber.isEmpty {
                    infoChip(text: "Claim \(insp.job.claimNumber)",
                             icon: "shield.fill",
                             tint: Theme.ember)
                }
                if !insp.job.carrierName.isEmpty {
                    infoChip(text: insp.job.carrierName,
                             icon: "building.2.fill",
                             tint: Theme.sky)
                }
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    showWeather = true
                    ActivityStore.shared.log(
                        .weatherSynced,
                        summary: "Weather pulled for site",
                        detail: insp.job.propertyAddress.isEmpty ? nil : insp.job.propertyAddress,
                        on: insp
                    )
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "cloud.sun.fill")
                            .font(.system(size: Theme.TypeRamp.caption, weight: .bold))
                        Text("Site Weather")
                            .font(.system(size: Theme.TypeRamp.metaSm, weight: .heavy))
                            .lineLimit(1)
                    }
                    .foregroundStyle(Theme.mint)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Theme.mintSoft, in: .capsule)
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            activityButton
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle(padding: 20, radius: 20)
        .sheet(isPresented: $showWeather) {
            WeatherDetailSheet(
                coord: WeatherServiceFactory.mockCoord(forAddress: insp.job.propertyAddress),
                locationLabel: insp.job.propertyAddress.isEmpty ? "Site" : insp.job.propertyAddress
            )
        }
    }

    private var originSavedEstimate: SavedEstimate? {
        guard let id = inspection?.originEstimateId else { return nil }
        return estimatesStore.estimates.first { $0.id == id }
    }

    private var fromEstimateChip: some View {
        let exists = originSavedEstimate != nil
        return Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            if exists { showOriginEstimate = true }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "dollarsign.circle.fill")
                    .font(.system(size: Theme.TypeRamp.caption, weight: .bold))
                Text(exists ? "From estimate" : "From estimate (deleted)")
                    .font(.system(size: Theme.TypeRamp.metaSm, weight: .heavy))
                    .lineLimit(1)
            }
            .foregroundStyle(exists ? Theme.mint : Theme.inkSoft)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background((exists ? Theme.mintSoft : Theme.canvas), in: .capsule)
            .overlay(Capsule().stroke(
                exists ? Color.clear : Theme.hairline, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(!exists)
    }

    private func infoChip(text: String, icon: String, tint: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .bold))
            Text(text)
                .font(.system(size: 13, weight: .heavy))
                .lineLimit(1)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(tint.opacity(0.10), in: .capsule)
    }

    private var emptySlopesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            FieldLabelInline(text: "Slopes inspected")
            Text("0 slopes captured")
                .font(.system(size: 22, weight: .heavy))
                .foregroundStyle(Theme.ink)
            Text("Add a slope to start scoring damage by face. Each slope feeds the Haag report directly.")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle(padding: 20, radius: 18)
    }

    private func slopesSummaryCard(_ insp: Inspection) -> some View {
        let slopes = insp.slopes
        let totalSquares = slopes.reduce(0.0) { $0 + $1.areaSquares }
        let functional = slopes.filter { $0.functionalDamagePresent }.count
        let totalRepair = slopes.reduce(0.0) { $0 + $1.repairCostSlope }
        return VStack(alignment: .leading, spacing: 14) {
            FieldLabelInline(text: "Slopes inspected")
            HStack(spacing: 10) {
                summaryStat(value: "\(slopes.count)", label: "Slopes", tint: Theme.ink)
                summaryStat(value: String(format: "%.1f", totalSquares), label: "Squares", tint: Theme.amber)
                summaryStat(value: "\(functional)", label: "Functional",
                            tint: functional > 0 ? Theme.crimson : Theme.mint)
            }
            if totalRepair > 0 {
                HStack(spacing: 8) {
                    Image(systemName: "hammer.fill")
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(Theme.ember)
                    Text("Repair estimate: \(currency(totalRepair))")
                        .font(.system(size: 15, weight: .heavy))
                        .foregroundStyle(Theme.ink)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle(padding: 20, radius: 18)
    }

    private func summaryStat(value: String, label: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.system(size: 24, weight: .heavy))
                .foregroundStyle(tint)
                .monospacedDigit()
            Text(label.uppercased())
                .font(.system(size: 10, weight: .heavy))
                .tracking(0.8)
                .foregroundStyle(Theme.inkSoft)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Theme.canvas, in: .rect(cornerRadius: 14))
    }

    private func slopesList(_ insp: Inspection) -> some View {
        VStack(spacing: 12) {
            ForEach(insp.slopes) { slope in
                slopeRow(slope)
            }
        }
    }

    private func slopeRow(_ slope: Slope) -> some View {
        let photoCount = store.photos(for: reportId, orientation: slope.orientation).count
        return HStack(spacing: 12) {
            Button {
                editingOrientation = slope.orientation
            } label: {
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 14)
                            .fill(slope.functionalDamagePresent ? Theme.crimson.opacity(0.15) : Theme.emberSoft)
                        Text(slope.orientation)
                            .font(.system(size: 18, weight: .heavy))
                            .foregroundStyle(slope.functionalDamagePresent ? Theme.crimson : Theme.ember)
                    }
                    .frame(width: 64, height: 64)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(slope.orientation) slope")
                            .font(.system(size: 17, weight: .heavy))
                            .foregroundStyle(Theme.ink)
                        Text("Pitch \(slope.pitchRiseOver12)/12 · \(String(format: "%.1f", slope.areaSquares)) sq · \(slope.damagedUnitsPerSquare)/sq")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.inkSoft)
                            .lineLimit(1)
                        HStack(spacing: 6) {
                            verdictPill(slope: slope)
                            if slope.verifyWithInspector {
                                verifyInspectorBadge
                            }
                            if photoCount > 0 {
                                HStack(spacing: 4) {
                                    Image(systemName: "photo.fill")
                                        .font(.system(size: 10, weight: .heavy))
                                    Text("\(photoCount)")
                                        .font(.system(size: 12, weight: .heavy))
                                }
                                .foregroundStyle(Theme.inkSoft)
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(Theme.canvas, in: .capsule)
                            }
                        }
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Theme.inkFaint)
                }
                .frame(maxWidth: .infinity, minHeight: 92, alignment: .leading)
                .cardStyle(padding: 14, radius: 18)
            }
            .buttonStyle(.plain)

            Button {
                slopePendingDelete = slope
            } label: {
                Image(systemName: "trash.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Theme.crimson)
                    .frame(width: 64, height: 64)
                    .background(Theme.card, in: .rect(cornerRadius: 18))
                    .overlay(RoundedRectangle(cornerRadius: 18)
                        .stroke(Theme.crimson.opacity(0.3), lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
    }

    private var verifyInspectorBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 10, weight: .heavy))
            Text("Verify with inspector")
                .font(.system(size: Theme.TypeRamp.metaSm, weight: .heavy))
                .lineLimit(1)
        }
        .foregroundStyle(Theme.amber)
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(Theme.amberSoft, in: .capsule)
        .overlay(Capsule().stroke(Theme.amber.opacity(0.35), lineWidth: 0.6))
    }

    private func verdictPill(slope: Slope) -> some View {
        let title: String
        let bg: Color
        let fg: Color
        if slope.slopeReplacementRecommended {
            title = "Full Replacement"
            bg = Theme.crimson.opacity(0.14); fg = Theme.crimson
        } else if slope.slopeRepairsRecommended {
            // Per spec: "yellow repairs" = amber chip.
            title = "Repairs"
            bg = Theme.amberSoft; fg = Theme.amber
        } else if slope.cosmeticOnly {
            // Cosmetic damage shows as orange (partial) per the 4-color scheme.
            title = "Cosmetic"
            bg = Theme.emberSoft; fg = Theme.ember
        } else {
            title = "No damage"
            bg = Theme.mintSoft; fg = Theme.mint
        }
        return Text(title)
            .font(.system(size: 12, weight: .heavy))
            .foregroundStyle(fg)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(bg, in: .capsule)
    }

    private func currency(_ value: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: value)) ?? "$\(Int(value))"
    }

    private func addSlopeButton(label: String) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            showAddSlope = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 22, weight: .bold))
                Text(label)
                    .font(.system(size: 18, weight: .bold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 64)
            .background(Theme.inkGradient, in: .rect(cornerRadius: 18))
            .shadow(color: Theme.ink.opacity(0.28), radius: 14, x: 0, y: 6)
        }
        .buttonStyle(.plain)
    }

    private var generateReportBar: some View {
        let enabled = canGeneratePDF
        return VStack(spacing: 6) {
            Rectangle().fill(Theme.hairline).frame(height: 0.5)
            Button {
                generatePDF()
            } label: {
                HStack(spacing: 8) {
                    if isGenerating {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(.white)
                    } else {
                        Image(systemName: "doc.richtext.fill")
                            .font(.system(size: 18, weight: .bold))
                    }
                    Text(isGenerating ? "Generating…" : "Generate Haag Report (PDF)")
                        .font(.system(size: Theme.TypeRamp.cta, weight: .bold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 64)
                .background(enabled ? AnyShapeStyle(Theme.inkGradient) : AnyShapeStyle(Theme.inkFaint),
                            in: .rect(cornerRadius: 18))
                .shadow(color: enabled ? Theme.ink.opacity(0.28) : .clear,
                        radius: 14, x: 0, y: 6)
                .padding(.horizontal, 20)
                .padding(.top, 12)
            }
            .buttonStyle(.plain)
            .disabled(!enabled || isGenerating)

            Text(generateCaption)
                .font(.system(size: Theme.TypeRamp.metaSm, weight: .semibold))
                .foregroundStyle(Theme.inkSoft)
                .padding(.bottom, 18)
        }
        .background(Theme.canvas)
    }

    // MARK: PDF gating

    private var canGeneratePDF: Bool {
        guard let insp = inspection,
              !insp.slopes.isEmpty else { return false }
        let job = insp.job
        return !job.clientName.trimmingCharacters(in: .whitespaces).isEmpty
            && !job.propertyAddress.trimmingCharacters(in: .whitespaces).isEmpty
            && !job.inspectorName.trimmingCharacters(in: .whitespaces).isEmpty
            && !job.companyName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var generateCaption: String {
        guard let insp = inspection else { return "Add a slope to enable." }
        if insp.slopes.isEmpty { return "Add at least one slope to enable." }
        if !canGeneratePDF { return "Fill in client, property, and inspector to enable." }
        return "Saves to Files · share via Mail, AirDrop, Print."
    }

    private func generatePDF() {
        guard let insp = inspection else { return }
        isGenerating = true
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        Task { @MainActor in
            // PDF generation is fast but synchronous; hop off the main
            // run-loop tick so the spinner has a chance to render.
            try? await Task.sleep(for: .milliseconds(50))
            let url = HaagReportGenerator.write(inspection: insp)
            isGenerating = false
            if let url {
                pdfShareURL = url
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                ActivityStore.shared.log(
                    .reportGenerated,
                    summary: "Haag report generated",
                    detail: url.lastPathComponent,
                    on: insp
                )
            } else {
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            }
        }
    }

    // MARK: Sign Report card

    private func signReportCard(_ insp: Inspection) -> some View {
        let inspectorSigned = insp.inspectorSignaturePng != nil
        let homeownerSigned = insp.homeownerSignaturePng != nil
        return Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            showSignatures = true
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14).fill(Theme.emberSoft)
                    Image(systemName: "signature")
                        .font(.system(size: 20, weight: .heavy))
                        .foregroundStyle(Theme.ember)
                }
                .frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Sign Report")
                        .font(.system(size: Theme.TypeRamp.body, weight: .heavy))
                        .foregroundStyle(Theme.ink)
                    Text(signatureSubtitle(inspectorSigned: inspectorSigned,
                                           homeownerSigned: homeownerSigned))
                        .font(.system(size: Theme.TypeRamp.metaSm, weight: .semibold))
                        .foregroundStyle(Theme.inkSoft)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        signaturePill(label: "Inspector", signed: inspectorSigned)
                        signaturePill(label: "Homeowner", signed: homeownerSigned)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.inkFaint)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardStyle(padding: 16, radius: 18)
        }
        .buttonStyle(.plain)
    }

    private func signatureSubtitle(inspectorSigned: Bool, homeownerSigned: Bool) -> String {
        switch (inspectorSigned, homeownerSigned) {
        case (true, true):   return "Both signatures captured."
        case (true, false):  return "Homeowner signature still needed."
        case (false, true):  return "Inspector signature still needed."
        case (false, false): return "Capture inspector & homeowner signatures."
        }
    }

    private func signaturePill(label: String, signed: Bool) -> some View {
        HStack(spacing: 4) {
            Image(systemName: signed ? "checkmark.seal.fill" : "circle.dashed")
                .font(.system(size: 10, weight: .heavy))
            Text(label)
                .font(.system(size: Theme.TypeRamp.caption, weight: .heavy))
        }
        .foregroundStyle(signed ? Theme.mint : Theme.inkSoft)
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background((signed ? Theme.mintSoft : Theme.canvas), in: .capsule)
    }

    // MARK: Proposal card (Phase 7)

    private var existingProposal: Proposal? {
        proposalStore.find(byJobId: reportId)
    }

    @ViewBuilder
    private func proposalSection(_ insp: Inspection) -> some View {
        if let p = existingProposal {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12).fill(Theme.skySoft)
                        Image(systemName: "doc.text.fill")
                            .font(.system(size: Theme.TypeRamp.subhead, weight: .heavy))
                            .foregroundStyle(Theme.sky)
                    }
                    .frame(width: 44, height: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("PROPOSAL")
                            .font(.system(size: Theme.TypeRamp.captionSm, weight: .heavy))
                            .tracking(1.2)
                            .foregroundStyle(Theme.inkSoft)
                        Text(currency(p.total))
                            .font(.system(size: Theme.TypeRamp.body, weight: .heavy))
                            .foregroundStyle(Theme.ink)
                            .monospacedDigit()
                    }
                    Spacer()
                    proposalStatusPill(p)
                }
                HStack(spacing: 8) {
                    proposalActionButton("Open", icon: "eye.fill") {
                        showHomeownerProposal = true
                    }
                    proposalActionButton("Edit", icon: "pencil") {
                        pendingProposal = p
                        showProposalEditor = true
                    }
                    proposalActionButton("Resend", icon: "paperplane.fill") {
                        showProposalSend = true
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardStyle(padding: 16, radius: 18)
        } else {
            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                let generated = ProposalGenerator.generate(forInspection: insp)
                _ = proposalStore.create(generated)
                ActivityStore.shared.log(.proposalDrafted,
                                         summary: "Proposal drafted",
                                         on: insp)
                pendingProposal = generated
                showProposalEditor = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "doc.badge.plus")
                        .font(.system(size: 22, weight: .bold))
                    Text("Generate Proposal")
                        .font(.system(size: Theme.TypeRamp.cta, weight: .bold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 64)
                .background(Theme.inkGradient, in: .rect(cornerRadius: 18))
                .shadow(color: Theme.ink.opacity(0.28), radius: 14, x: 0, y: 6)
            }
            .buttonStyle(.plain)
        }
    }

    private func proposalActionButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: Theme.TypeRamp.subhead, weight: .heavy))
                Text(title)
                    .font(.system(size: Theme.TypeRamp.subhead, weight: .heavy))
            }
            .foregroundStyle(Theme.ink)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(Theme.canvas, in: .rect(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.hairline, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func proposalStatusPill(_ p: Proposal) -> some View {
        let (bg, fg): (Color, Color) = {
            switch p.status {
            case .draft:    return (Theme.canvas, Theme.inkSoft)
            case .sent:     return (Theme.amberSoft, Theme.amber)
            case .viewed:   return (Theme.skySoft, Theme.sky)
            case .signed:   return (Theme.mintSoft, Theme.mint)
            case .declined: return (Theme.emberSoft, Theme.crimson)
            case .expired:  return (Theme.canvas, Theme.inkFaint)
            }
        }()
        return Text(p.status.displayName)
            .font(.system(size: Theme.TypeRamp.captionSm, weight: .heavy))
            .tracking(1.0)
            .foregroundStyle(fg)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(bg, in: .capsule)
    }

    // MARK: Storm match card

    private func stormMatchCard(_ insp: Inspection) -> some View {
        let event = insp.event
        let dateText = event.eventDate?.formatted(date: .abbreviated, time: .omitted) ?? "—"
        let magText: String = {
            if let h = event.hailMaxSizeIn { return String(format: "%.2f\" hail", h) }
            if let w = event.windMaxGustMph { return "\(Int(w)) mph wind" }
            return "Storm event"
        }()
        let isHail = event.hailMaxSizeIn != nil
        let tint: Color = isHail ? Theme.sky : Theme.ember
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12).fill(tint.opacity(0.15))
                    Image(systemName: isHail ? "cloud.hail.fill" : "wind")
                        .font(.system(size: Theme.TypeRamp.subhead, weight: .heavy))
                        .foregroundStyle(tint)
                }
                .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text("STORM MATCH")
                        .font(.system(size: Theme.TypeRamp.captionSm, weight: .heavy))
                        .tracking(1.2)
                        .foregroundStyle(Theme.inkSoft)
                    Text("\(dateText) · \(magText)")
                        .font(.system(size: Theme.TypeRamp.body, weight: .heavy))
                        .foregroundStyle(Theme.ink)
                }
                Spacer()
                ForEach(event.weatherSources, id: \.self) { src in
                    Text(src)
                        .font(.system(size: Theme.TypeRamp.captionSm, weight: .heavy))
                        .tracking(0.8)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Theme.ink, in: .capsule)
                }
            }
            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                stormMatchFocus = stormPin(from: event)
                showStormOnMap = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "map.fill")
                        .font(.system(size: Theme.TypeRamp.body, weight: .heavy))
                    Text("View on Map")
                        .font(.system(size: Theme.TypeRamp.cta, weight: .heavy))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 64)
                .background(Theme.inkGradient, in: .rect(cornerRadius: 16))
                .shadow(color: Theme.ink.opacity(0.18), radius: 12, y: 4)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle(padding: 16, radius: 18)
    }

    private func stormPin(from event: InspectionEvent) -> StormPinEvent {
        // Reuse the same stable-coord helper MapHubView uses for jobs so the
        // pin lands where the job marker already does.
        let address = inspection?.job.propertyAddress ?? ""
        let coord = GeocodingServiceFactory.eagerCoord(forAddress: address)
        return StormPinEvent(
            date: event.eventDate ?? .now,
            hailSizeIn: event.hailMaxSizeIn,
            windGustMph: event.windMaxGustMph.map { Int($0.rounded()) },
            latitude: coord.latitude,
            longitude: coord.longitude,
            source: event.weatherSources.first ?? "NOAA"
        )
    }

    // MARK: Roof measurements (Google Solar)

    private func loadRoofMeasurements() async {
        guard let address = inspection?.job.propertyAddress,
              !address.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        let coord = WeatherServiceFactory.mockCoord(forAddress: address)
        let m = try? await SolarServiceFactory.shared.measurements(at: coord)
        await MainActor.run {
            let wasNil = self.roofMeasurements == nil
            self.roofMeasurements = m
            if wasNil, let m, let insp = self.inspection {
                ActivityStore.shared.log(
                    .roofDetected,
                    summary: String(format: "Roof measured: %.1f sq", m.totalAreaSquares),
                    detail: "\(m.segments.count) faces \u{00B7} \(m.source)",
                    on: insp
                )
            }
        }
    }

    private var activityButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            showActivity = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: Theme.TypeRamp.body, weight: .heavy))
                Text("Activity")
                    .font(.system(size: Theme.TypeRamp.body, weight: .heavy))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: Theme.TypeRamp.caption, weight: .heavy))
                    .foregroundStyle(Theme.inkFaint)
            }
            .foregroundStyle(Theme.ink)
            .frame(maxWidth: .infinity, minHeight: 56)
            .padding(.horizontal, 14)
            .background(Theme.canvas, in: .rect(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14)
                .stroke(Theme.hairline, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .padding(.top, 4)
    }

    @ViewBuilder
    private func roofMeasurementsCard(_ insp: Inspection) -> some View {
        if let m = roofMeasurements, insp.roof.detectedAreaSquares != nil {
            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                showRoofOnMap = true
            } label: {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 10) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 12).fill(Theme.amberSoft)
                            Image(systemName: "square.3.layers.3d.top.filled")
                                .font(.system(size: Theme.TypeRamp.subhead, weight: .heavy))
                                .foregroundStyle(Theme.amber)
                        }
                        .frame(width: 44, height: 44)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("ROOF MEASUREMENTS")
                                .font(.system(size: Theme.TypeRamp.captionSm, weight: .heavy))
                                .tracking(1.2)
                                .foregroundStyle(Theme.inkSoft)
                            Text("\(squaresLabel(m.totalAreaSquares)) \u{00B7} \(m.segments.count) faces")
                                .font(.system(size: Theme.TypeRamp.body, weight: .heavy))
                                .foregroundStyle(Theme.ink)
                        }
                        Spacer()
                        sourcePill(text: m.source.uppercased(),
                                   live: SolarServiceFactory.shared.isLive)
                    }
                    HStack(spacing: 8) {
                        ForEach(m.segments.prefix(4)) { seg in
                            faceChip(seg)
                        }
                        if m.segments.count > 4 {
                            Text("+\(m.segments.count - 4)")
                                .font(.system(size: Theme.TypeRamp.captionSm, weight: .heavy))
                                .foregroundStyle(Theme.inkSoft)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: Theme.TypeRamp.caption, weight: .heavy))
                            .foregroundStyle(Theme.inkFaint)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardStyle(padding: 16, radius: 18)
            }
            .buttonStyle(.plain)
        }
    }

    private func faceChip(_ seg: RoofSegmentMeasurement) -> some View {
        VStack(spacing: 2) {
            Text(seg.orientation)
                .font(.system(size: Theme.TypeRamp.captionSm, weight: .heavy))
                .foregroundStyle(Theme.ember)
            Text(String(format: "%.1f sq", seg.areaSquares))
                .font(.system(size: Theme.TypeRamp.captionSm, weight: .semibold))
                .foregroundStyle(Theme.inkSoft)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Theme.emberSoft, in: .capsule)
    }

    private func sourcePill(text: String, live: Bool) -> some View {
        Text(text)
            .font(.system(size: Theme.TypeRamp.captionSm, weight: .heavy))
            .tracking(0.8)
            .foregroundStyle(.white)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(live ? Theme.mint : Theme.inkFaint, in: .capsule)
    }

    private func squaresLabel(_ sq: Double) -> String {
        String(format: "%.1f sq", sq)
    }

    // MARK: Replacement cost (auto)

    @ViewBuilder
    private func replacementCostCard(_ insp: Inspection) -> some View {
        if let m = roofMeasurements,
           insp.roof.detectedAreaSquares != nil {
            let est = CostEstimator.estimate(
                measurement: m,
                material: insp.roof.primaryMaterial,
                address: insp.job.propertyAddress
            )
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12).fill(Theme.mintSoft)
                        Image(systemName: "dollarsign.circle.fill")
                            .font(.system(size: Theme.TypeRamp.subhead, weight: .heavy))
                            .foregroundStyle(Theme.mint)
                    }
                    .frame(width: 44, height: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("REPLACEMENT COST")
                            .font(.system(size: Theme.TypeRamp.captionSm, weight: .heavy))
                            .tracking(1.2)
                            .foregroundStyle(Theme.inkSoft)
                        Text(est.rangeLabel)
                            .font(.system(size: Theme.TypeRamp.titleSm, weight: .heavy))
                            .foregroundStyle(Theme.ink)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    Spacer()
                    Text("AUTO ESTIMATE")
                        .font(.system(size: Theme.TypeRamp.captionSm, weight: .heavy))
                        .tracking(0.8)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Theme.mint, in: .capsule)
                }
                Text(String(format: "%@ / sq \u{00B7} %.1f sq \u{00B7} %@",
                            currency(est.pricePerSquare),
                            est.input.totalSquares,
                            insp.roof.primaryMaterial.displayName))
                    .font(.system(size: Theme.TypeRamp.metaSm, weight: .semibold))
                    .foregroundStyle(Theme.inkSoft)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardStyle(padding: 16, radius: 18)
        }
    }

    // MARK: Decision banner

    private func decisionBanner(_ insp: Inspection) -> some View {
        let v = decisionVerdict(insp)
        return HStack(spacing: 12) {
            Image(systemName: v.icon)
                .font(.system(size: 22, weight: .heavy))
                .foregroundStyle(v.fg)
                .frame(width: 44, height: 44)
                .background(v.fg.opacity(0.15), in: .circle)
            VStack(alignment: .leading, spacing: 2) {
                Text(v.title.uppercased())
                    .font(.system(size: 11, weight: .heavy))
                    .tracking(0.7)
                    .foregroundStyle(v.fg)
                Text(v.detail)
                    .font(.system(size: 17, weight: .heavy))
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(v.bg, in: .rect(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18)
            .stroke(v.fg.opacity(0.25), lineWidth: 1))
    }

    private struct DecisionStyle {
        let title: String
        let detail: String
        let icon: String
        let fg: Color
        let bg: Color
    }

    private func decisionVerdict(_ insp: Inspection) -> DecisionStyle {
        let s = insp.summary
        let list = s.replacementSlopesList.isEmpty ? "" : " — \(s.replacementSlopesList)"
        if s.roofFullReplacementRecommended {
            return DecisionStyle(
                title: "Full Replacement Recommended",
                detail: "Full Replacement Recommended\(list)",
                icon: "exclamationmark.octagon.fill",
                fg: Theme.crimson, bg: Theme.crimson.opacity(0.10)
            )
        }
        if s.roofPartialReplacementRecommended {
            return DecisionStyle(
                title: "Partial Replacement",
                detail: "Partial Replacement\(list)",
                icon: "exclamationmark.triangle.fill",
                fg: Theme.ember, bg: Theme.emberSoft
            )
        }
        if s.roofRepairsRecommended {
            return DecisionStyle(
                title: "Repairs Recommended",
                detail: "Repairs Recommended",
                icon: "wrench.and.screwdriver.fill",
                fg: Theme.amber, bg: Theme.amberSoft
            )
        }
        return DecisionStyle(
            title: "No Damage",
            detail: "No storm-related damage found",
            icon: "checkmark.seal.fill",
            fg: Theme.mint, bg: Theme.mintSoft
        )
    }
}

// Allow String to drive .fullScreenCover(item:) for editing-by-orientation.
extension String: @retroactive Identifiable {
    public var id: String { self }
}

/// Identifiable wrapper for URL so .sheet(item:) can present a share sheet.
private struct IdentifiableURL: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

// MARK: - PDF Preview Sheet

import PDFKit

private struct PDFPreviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    let url: URL
    @State private var showShare = false

    var body: some View {
        NavigationStack {
            PDFKitView(url: url)
                .background(Theme.canvas.ignoresSafeArea())
                .navigationTitle("Report Preview")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Done") { dismiss() }
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Theme.ember)
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        HStack(spacing: 18) {
                            Button {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                printPDF()
                            } label: {
                                Image(systemName: "printer")
                                    .font(.system(size: 17, weight: .semibold))
                            }
                            .foregroundStyle(Theme.ink)

                            Button {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                showShare = true
                            } label: {
                                Image(systemName: "square.and.arrow.up")
                                    .font(.system(size: 17, weight: .semibold))
                            }
                            .foregroundStyle(Theme.ember)
                        }
                    }
                }
                .sheet(isPresented: $showShare) {
                    ShareSheet(items: [url])
                }
        }
    }

    private func printPDF() {
        guard UIPrintInteractionController.canPrint(url) else { return }
        let info = UIPrintInfo(dictionary: nil)
        info.outputType = .general
        info.jobName = url.lastPathComponent
        let pic = UIPrintInteractionController.shared
        pic.printInfo = info
        pic.printingItem = url
        pic.present(animated: true, completionHandler: nil)
    }
}

private struct PDFKitView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> PDFView {
        let v = PDFView()
        v.autoScales = true
        v.displayMode = .singlePageContinuous
        v.displayDirection = .vertical
        v.backgroundColor = UIColor(Theme.canvas)
        v.document = PDFDocument(url: url)
        return v
    }

    func updateUIView(_ uiView: PDFView, context: Context) {
        if uiView.document?.documentURL != url {
            uiView.document = PDFDocument(url: url)
        }
    }
}

private struct FieldLabelInline: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 12, weight: .heavy))
            .foregroundStyle(Theme.inkSoft)
            .tracking(0.6)
    }
}

// MARK: - Solar measurements sheet

struct SolarMeasurementsSheet: View {
    @Environment(\.dismiss) private var dismiss
    let measurements: RoofMeasurements
    let address: String

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    headerCard
                    segmentsCard
                    sourceCard
                    Color.clear.frame(height: 24)
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
            }
            .background(Theme.canvas.ignoresSafeArea())
            .navigationTitle("Roof Measurements")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.system(size: Theme.TypeRamp.body, weight: .heavy))
                        .foregroundStyle(Theme.ember)
                }
            }
        }
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(address.isEmpty ? "Site" : address)
                .font(.system(size: Theme.TypeRamp.subhead, weight: .heavy))
                .foregroundStyle(Theme.inkSoft)
                .lineLimit(2)
            Text(String(format: "%.1f roof squares", measurements.totalAreaSquares))
                .font(.system(size: Theme.TypeRamp.display, weight: .heavy))
                .foregroundStyle(Theme.ink)
            Text(String(format: "%.0f sq ft total roof footprint", measurements.totalAreaSqFt))
                .font(.system(size: Theme.TypeRamp.metaSm, weight: .semibold))
                .foregroundStyle(Theme.inkSoft)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle(padding: 20, radius: 20)
    }

    private var segmentsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("FACES")
                .font(.system(size: Theme.TypeRamp.captionSm, weight: .heavy))
                .tracking(0.8)
                .foregroundStyle(Theme.inkSoft)
            ForEach(measurements.segments) { seg in
                segmentRow(seg)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle(padding: 16, radius: 18)
    }

    private func segmentRow(_ seg: RoofSegmentMeasurement) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(Theme.emberSoft)
                Text(seg.orientation)
                    .font(.system(size: Theme.TypeRamp.subhead, weight: .heavy))
                    .foregroundStyle(Theme.ember)
            }
            .frame(width: 48, height: 48)
            VStack(alignment: .leading, spacing: 2) {
                Text(String(format: "%.1f sq \u{00B7} %.0f sq ft", seg.areaSquares, seg.areaSqFt))
                    .font(.system(size: Theme.TypeRamp.body, weight: .heavy))
                    .foregroundStyle(Theme.ink)
                Text("Pitch \(seg.pitchRiseOver12)/12 \u{00B7} \(Int(seg.pitchDegrees.rounded()))\u{00B0} \u{00B7} az \(Int(seg.azimuthDegrees.rounded()))\u{00B0}")
                    .font(.system(size: Theme.TypeRamp.metaSm, weight: .semibold))
                    .foregroundStyle(Theme.inkSoft)
            }
            Spacer()
        }
        .padding(.vertical, 6)
    }

    private var sourceCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SOURCE")
                .font(.system(size: Theme.TypeRamp.captionSm, weight: .heavy))
                .tracking(0.8)
                .foregroundStyle(Theme.inkSoft)
            HStack(spacing: 8) {
                Image(systemName: SolarServiceFactory.shared.isLive
                      ? "checkmark.seal.fill" : "sparkles")
                    .foregroundStyle(SolarServiceFactory.shared.isLive ? Theme.mint : Theme.inkFaint)
                Text(measurements.source)
                    .font(.system(size: Theme.TypeRamp.body, weight: .heavy))
                    .foregroundStyle(Theme.ink)
            }
            if let date = measurements.imageryDate {
                Text("Imagery \(date.formatted(date: .abbreviated, time: .omitted))")
                    .font(.system(size: Theme.TypeRamp.metaSm, weight: .semibold))
                    .foregroundStyle(Theme.inkSoft)
            }
            if let kwh = measurements.sunshineKwhPerSqMPerYear {
                Text(String(format: "~%.0f kWh/m\u{00B2}/yr sunshine at site", kwh))
                    .font(.system(size: Theme.TypeRamp.metaSm, weight: .semibold))
                    .foregroundStyle(Theme.inkSoft)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle(padding: 16, radius: 18)
    }
}

private struct ReportComingSoonSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle().fill(Theme.emberSoft)
                Image(systemName: "doc.richtext.fill")
                    .font(.system(size: Theme.TypeRamp.display, weight: .bold))
                    .foregroundStyle(Theme.ember)
            }
            .frame(width: 84, height: 84)
            .padding(.top, 12)

            Text("Coming next")
                .font(.system(size: 12, weight: .heavy))
                .foregroundStyle(Theme.ember)
                .tracking(0.8)

            Text("Haag PDF report")
                .font(.system(size: 22, weight: .heavy))
                .foregroundStyle(Theme.ink)

            Text("Roll your slopes into a Haag-formatted PDF and ship it to the carrier — coming in the next build.")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.inkSoft)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()

            Button {
                dismiss()
            } label: {
                Text("Got it")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 64)
                    .background(Theme.ink, in: .rect(cornerRadius: 18))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
        .padding(.top, 8)
    }
}
