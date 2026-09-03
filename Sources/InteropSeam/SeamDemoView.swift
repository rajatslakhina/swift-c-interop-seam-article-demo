#if canImport(SwiftUI)
import SwiftUI

/// The demo screen: the fixture planned both ways, side by side, with the
/// diagnostics a build system would never raise.
public struct SeamDemoView: View {
    @State private var layout: SeamLayout = .shimTarget
    private let planner = SeamPlanner()
    private let model = LegacyLedgerFixture.model

    public init() {}

    private var plan: SeamPlan { planner.plan(model, layout: layout) }
    private var comparison: (legacy: SeamPlan, designed: SeamPlan) { planner.compare(model) }

    public var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Layout", selection: $layout) {
                        ForEach(SeamLayout.allCases, id: \.self) { l in
                            Text(l == .shimTarget ? "Shim target" : "SE-0541 seam").tag(l)
                        }
                    }
                    .pickerStyle(.segmented)
                    Text(layout.title)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Downstream-visible C declarations") {
                    exposureRow(title: "Shim target + umbrella", plan: comparison.legacy)
                    exposureRow(title: "SE-0541 designed seam", plan: comparison.designed)
                }

                Section("Placement under the selected layout") {
                    ForEach(model.headers, id: \.self) { header in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(header).font(.headline)
                            ForEach(model.declarations.filter { $0.header == header }, id: \.name) { decl in
                                HStack {
                                    Text(decl.name).font(.system(.body, design: .monospaced))
                                    Spacer()
                                    placementChip(for: decl.name)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                Section("Diagnostics (\(plan.diagnostics.count))") {
                    if plan.diagnostics.isEmpty {
                        Text("None").foregroundStyle(.secondary)
                    }
                    ForEach(Array(plan.diagnostics.enumerated()), id: \.offset) { _, diag in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(diag.severity.rawValue.uppercased())
                                    .font(.caption2.bold())
                                    .foregroundStyle(severityColor(diag.severity))
                                Text(diag.code.rawValue)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                            Text(diag.message).font(.footnote)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            .navigationTitle("Interop Seam")
        }
    }

    private func exposureRow(title: String, plan: SeamPlan) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text("\(plan.downstreamVisibleCount) / \(plan.totalCount)")
                    .font(.system(.body, design: .monospaced).bold())
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.2))
                    Capsule()
                        .fill(plan.exposureRatio > 0.5 ? Color.red : Color.green)
                        .frame(width: max(4, geo.size.width * plan.exposureRatio))
                }
            }
            .frame(height: 8)
        }
        .padding(.vertical, 2)
    }

    private func placementChip(for name: String) -> some View {
        let placement: Placement? = layout == .shimTarget ? nil : plan.placement(of: name)
        let label: String
        let color: Color
        if layout == .shimTarget {
            label = "public (umbrella)"
            color = .red
        } else if let placement {
            label = placement.title
            color = placement == .publicHeaders ? .red : (placement == .bridgingHeader ? .green : .gray)
        } else {
            label = "?"
            color = .gray
        }
        return Text(label)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }

    private func severityColor(_ s: SeamDiagnostic.Severity) -> Color {
        switch s {
        case .error: return .red
        case .warning: return .orange
        case .note: return .secondary
        }
    }
}

#Preview {
    SeamDemoView()
}
#endif
