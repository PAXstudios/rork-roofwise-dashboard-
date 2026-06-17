import SwiftUI

struct DamageExplainerView: View {
    @Bindable var progress: TrainingProgressStore
    @Environment(CustomerStore.self) private var customers
    @Environment(\.dismiss) private var dismiss

    @State private var selectedCustomerID: UUID? = nil
    @State private var explanation: DamageExplanation? = nil
    @State private var isGenerating = false
    @State private var useMockFindings = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    intro
                    customerPicker
                    findingsPreview
                    runButton
                    if let exp = explanation {
                        explanationBlock(exp)
                    } else if isGenerating {
                        shimmer
                    }
                    Spacer(minLength: 24)
                }
                .padding(.horizontal, 18)
                .padding(.top, 4)
                .padding(.bottom, 32)
            }
            .background(Theme.canvas)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Damage Explainer")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(Theme.ink)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Theme.ember)
                        .fontWeight(.semibold)
                }
            }
            .onAppear {
                if selectedCustomerID == nil {
                    selectedCustomerID = customers.activeCustomerID ?? customers.customers.first?.id
                }
            }
        }
    }

    // MARK: - Computed

    private var selectedCustomer: Customer? {
        guard let id = selectedCustomerID else { return nil }
        return customers.customers.first { $0.id == id }
    }

    private var effectiveFindings: [InspectionFinding] {
        let real = selectedCustomer?.damageFindings.filter { $0.detected } ?? []
        if !real.isEmpty && !useMockFindings { return real }
        return InspectionMock.findings.filter { $0.detected }
    }

    // MARK: - Sections

    private var intro: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle().fill(LinearGradient(colors: [Theme.ember, Theme.emberDeep],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                Image(systemName: "house.lodge.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 4) {
                Text("Translate findings for the homeowner")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.ink)
                Text("Pick a customer's inspection. RoofWise Vision turns the technical findings into a friendly script you can read at the door.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.inkSoft)
            }
        }
    }

    private var customerPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Customer")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Theme.inkSoft)
                .textCase(.uppercase)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(customers.customers) { c in
                        Button {
                            withAnimation(.spring(duration: 0.25)) {
                                selectedCustomerID = c.id
                                explanation = nil
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(c.ownerName)
                                    .font(.system(size: 13, weight: .bold))
                                    .lineLimit(1)
                                Text(c.address)
                                    .font(.system(size: 11))
                                    .lineLimit(1)
                                    .opacity(0.85)
                            }
                            .foregroundStyle(selectedCustomerID == c.id ? .white : Theme.ink)
                            .padding(.horizontal, 12).padding(.vertical, 10)
                            .frame(maxWidth: 200, alignment: .leading)
                            .background(selectedCustomerID == c.id ? Theme.ink : Theme.card,
                                        in: .rect(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12)
                                .stroke(Theme.hairline, lineWidth: selectedCustomerID == c.id ? 0 : 0.6))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .contentMargins(.horizontal, 0)
        }
    }

    private var findingsPreview: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Inspection findings")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.inkSoft)
                    .textCase(.uppercase)
                Spacer()
                if let c = selectedCustomer, c.damageFindings.filter({ $0.detected }).isEmpty {
                    Text("Using sample data")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.amber)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Theme.amberSoft, in: .capsule)
                }
            }
            VStack(spacing: 6) {
                ForEach(effectiveFindings.prefix(5)) { f in
                    HStack(spacing: 10) {
                        Image(systemName: f.icon)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(f.tint)
                            .frame(width: 22, height: 22)
                            .background(f.tint.opacity(0.12), in: .rect(cornerRadius: 6))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(f.display)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Theme.ink)
                            Text(f.value)
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.inkSoft)
                                .lineLimit(1)
                        }
                        Spacer()
                        Text(f.severity.rawValue)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(f.severity.color)
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(f.severity.bg, in: .capsule)
                    }
                }
                if effectiveFindings.count > 5 {
                    Text("+ \(effectiveFindings.count - 5) more")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.inkSoft)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .cardStyle(padding: 14)
        }
    }

    private var runButton: some View {
        Button {
            Task { await generate() }
        } label: {
            HStack(spacing: 8) {
                if isGenerating {
                    ProgressView().tint(.white).controlSize(.small)
                } else {
                    Image(systemName: "wand.and.stars").font(.system(size: 14, weight: .bold))
                }
                Text(isGenerating ? "Translating…" : "Generate homeowner explanation")
                    .font(.system(size: 16, weight: .bold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                LinearGradient(colors: [Theme.ember, Theme.emberDeep],
                               startPoint: .topLeading, endPoint: .bottomTrailing),
                in: .rect(cornerRadius: 16)
            )
            .shadow(color: Theme.ember.opacity(0.35), radius: 12, x: 0, y: 6)
        }
        .buttonStyle(.plain)
        .disabled(isGenerating || effectiveFindings.isEmpty)
        .opacity(effectiveFindings.isEmpty ? 0.6 : 1)
    }

    private var shimmer: some View {
        VStack(spacing: 10) {
            ForEach(0..<3, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 14)
                    .fill(Theme.canvas)
                    .frame(height: 60)
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.hairline, lineWidth: 0.6))
            }
        }
    }

    private func explanationBlock(_ exp: DamageExplanation) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            // Headline card — what to lead with
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "quote.opening")
                        .foregroundStyle(.white.opacity(0.7))
                    Text("LEAD WITH THIS")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white.opacity(0.85))
                        .tracking(0.6)
                }
                Text(exp.headline)
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background(
                LinearGradient(colors: [Theme.ink, Color(red: 0.10, green: 0.18, blue: 0.36)],
                               startPoint: .topLeading, endPoint: .bottomTrailing),
                in: .rect(cornerRadius: 20)
            )

            // Plain summary script
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "text.bubble.fill").foregroundStyle(Theme.sky)
                    Text("Read this out loud").font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Theme.ink)
                    Spacer()
                    Button {
                        UIPasteboard.general.string = exp.plainSummary
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "doc.on.doc"); Text("Copy")
                        }
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.ember)
                    }
                }
                Text(exp.plainSummary)
                    .font(.system(size: 14.5))
                    .foregroundStyle(Theme.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .cardStyle()

            // Bullets — finding-by-finding plain English
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "list.bullet.rectangle.fill").foregroundStyle(Theme.mint)
                    Text("If they ask 'what does that mean?'")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Theme.ink)
                }
                ForEach(exp.bullets, id: \.self) { item in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "circle.fill").font(.system(size: 5))
                            .foregroundStyle(Theme.mint).padding(.top, 6)
                        Text(item).font(.system(size: 13.5)).foregroundStyle(Theme.ink)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Theme.mintSoft, in: .rect(cornerRadius: 16))

            // Soft close question
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.bubble.fill").foregroundStyle(Theme.ember)
                    Text("Soft close")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Theme.ember)
                        .textCase(.uppercase)
                }
                Text(exp.homeownerQuestion)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.ink)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Theme.emberSoft, in: .rect(cornerRadius: 16))
        }
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }

    // MARK: - Logic

    private func generate() async {
        isGenerating = true
        explanation = nil
        let result = await TrainingCoachService.explainDamage(
            findings: effectiveFindings,
            homeownerName: selectedCustomer?.ownerName
        )
        await MainActor.run {
            withAnimation(.spring(duration: 0.4)) { explanation = result }
            progress.explainerGenerationsCount += 1
            isGenerating = false
        }
    }
}
