import SwiftUI

struct JobDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var store = InspectionStore.shared
    @State private var showAddSlope = false

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
                        emptySlopesCard
                        addSlopeButton
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
        .sheet(isPresented: $showAddSlope) {
            AddSlopePlaceholderSheet()
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
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
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: .rect(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Theme.hairline, lineWidth: 1))
        .shadow(color: Theme.ink.opacity(0.05), radius: 14, x: 0, y: 6)
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
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: .rect(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.hairline, lineWidth: 1))
    }

    private var addSlopeButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            showAddSlope = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 22, weight: .bold))
                Text("Add slope")
                    .font(.system(size: 18, weight: .bold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 64)
            .background(
                LinearGradient(colors: [Theme.ink, Color(red: 0.12, green: 0.20, blue: 0.42)],
                               startPoint: .topLeading, endPoint: .bottomTrailing),
                in: .rect(cornerRadius: 18)
            )
            .shadow(color: Theme.ink.opacity(0.28), radius: 14, x: 0, y: 6)
        }
        .buttonStyle(.plain)
    }

    private var generateReportBar: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Theme.hairline).frame(height: 0.5)
            Button {
                // Disabled until first slope is added.
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "doc.richtext.fill")
                        .font(.system(size: 18, weight: .bold))
                    Text("Generate Haag Report (PDF)")
                        .font(.system(size: 18, weight: .bold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 64)
                .background(Theme.inkFaint, in: .rect(cornerRadius: 18))
            }
            .buttonStyle(.plain)
            .disabled(true)
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 20)
        }
        .background(Theme.canvas)
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

private struct AddSlopePlaceholderSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle().fill(Theme.emberSoft)
                Image(systemName: "house.lodge.fill")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(Theme.ember)
            }
            .frame(width: 84, height: 84)
            .padding(.top, 12)

            Text("Coming next")
                .font(.system(size: 12, weight: .heavy))
                .foregroundStyle(Theme.ember)
                .tracking(0.8)

            Text("Slope inspection capture")
                .font(.system(size: 22, weight: .heavy))
                .foregroundStyle(Theme.ink)

            Text("Walk a slope, mark damaged units per square, and let RoofWise score it against Haag thresholds — coming in the next build.")
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
