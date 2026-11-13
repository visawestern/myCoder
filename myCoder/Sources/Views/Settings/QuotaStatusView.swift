import SwiftUI

/// Live quota accounting for one provider (directive 2026-11-13): which API
/// key is currently active and how much of the minute's allowance remains.
/// Reads `QuotaGate` state; refreshes when the view appears / provider changes.
struct QuotaStatusView: View {
    let providerID: String
    @State private var activeKey: String?
    @State private var statuses: [QuotaScopeStatus] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let activeKey, !activeKey.isEmpty {
                Label(L.t("Active key: "), systemImage: "key.fill")
                    .interfaceFont(size: 10)
                    .foregroundColor(Color.mimo.textMuted)
                Text(shortKey(activeKey))
                    .interfaceFont(size: 10, design: .monospaced)
                    .foregroundColor(Color.mimo.success)
            }
            ForEach(statuses.prefix(6), id: \.scopeKey) { status in
                Text(render(status))
                    .interfaceFont(size: 10)
                    .foregroundColor(Color.mimo.textMuted)
            }
        }
        .onAppear(perform: refresh)
        .onChange(of: providerID) { _ in refresh() }
    }

    private func refresh() {
        Task {
            let gate = QuotaGate.shared
            let snapshot = await gate.snapshot()
            let key = await gate.activeKey(for: providerID)
            await MainActor.run {
                statuses = snapshot.filter {
                    $0.kind == .provider ? $0.scopeKey == providerID
                        : ($0.kind == .model ? $0.scopeKey.contains(providerID) : true)
                }
                activeKey = key
            }
        }
    }

    private func render(_ status: QuotaScopeStatus) -> String {
        "\(status.kind.rawValue) \(shortKey(status.scopeKey)): reset in \(status.resetSeconds)s"
    }

    private func shortKey(_ key: String) -> String {
        key.count > 12 ? "…\(key.suffix(12))" : key
    }
}
