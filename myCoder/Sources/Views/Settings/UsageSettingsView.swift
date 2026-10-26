import SwiftUI

struct UsageSettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedRange: UsageRange = .last30
    @State private var stats: StorageStats?
    @State private var points: [UsageDataPoint] = []
    
    enum UsageRange: String, CaseIterable {
        case last7 = "Last 7 days"
        case last30 = "Last 30 days"
        var days: Int { self == .last7 ? 7 : 30 }
        var localizedTitle: String {
            self == .last7 ? L.t(AppLocalizationKey.locLast7Days) : L.t(AppLocalizationKey.locLast30Days)
        }
    }

    private var filteredPoints: [UsageDataPoint] {
        UsageStatisticsAggregator.filter(points, range: .lastDays(selectedRange.days))
    }
    private var byModel: [UsageAggregate] {
        UsageStatisticsAggregator.aggregateByModel(filteredPoints)
    }
    private var totals: (tokens: Int, cost: Double?) {
        UsageStatisticsAggregator.totals(filteredPoints)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack {
                Text(L.t(AppLocalizationKey.locUsage))
                    .interfaceFont(size: 24, weight: .bold)
                    .foregroundColor(Color.mimo.textPrimary)
                Text(L.t(AppLocalizationKey.locAppUsage))
                    .interfaceFont(size: 14)
                    .foregroundColor(Color.mimo.textMuted)
            }
            
            HStack(spacing: 8) {
                Text(L.t(AppLocalizationKey.locTimeRange))
                    .interfaceFont(size: 12)
                    .foregroundColor(Color.mimo.textMuted)
                
                ForEach(UsageRange.allCases, id: \.self) { range in
                    SettingsSegmentButton(
                        title: range.localizedTitle,
                        isSelected: selectedRange == range
                    ) {
                        selectedRange = range
                    }
                }
            }
            
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 16) {
                UsageStatCard(title: L.t(AppLocalizationKey.locTotalTokens), value: formatTokens(totals.tokens), icon: "flame")
                UsageStatCard(title: L.t(AppLocalizationKey.locTotalCost), value: UsageStatisticsAggregator.costLabel(totals.cost), icon: "dollarsign.circle")
                UsageStatCard(title: L.t(AppLocalizationKey.locMessages), value: formattedMessages, icon: "message")
                UsageStatCard(title: L.t(AppLocalizationKey.locActiveDays), value: "\(UsageStatisticsAggregator.activeDays(filteredPoints))", icon: "calendar")
                UsageStatCard(title: L.t(AppLocalizationKey.locDatabaseSize), value: stats?.databaseSizeFormatted ?? "—", icon: "internaldrive")
                UsageStatCard(title: L.t(AppLocalizationKey.locFavoriteModel),
                              value: UsageStatisticsAggregator.favoriteModel(filteredPoints) ?? L.t(AppLocalizationKey.locNone),
                              subtitle: L.t(AppLocalizationKey.locUsage1), icon: "brain")
            }

            // Per-model breakdown (plan Раздел 10 Блок 2 п.16)
            if !byModel.isEmpty {
                Text(L.t(AppLocalizationKey.locModel))
                    .interfaceFont(size: 16, weight: .semibold)
                    .foregroundColor(Color.mimo.textPrimary)
                VStack(spacing: 6) {
                    ForEach(byModel, id: \.key) { agg in
                        HStack {
                            Text(agg.key)
                                .interfaceFont(size: 12, weight: .medium)
                                .foregroundColor(Color.mimo.textPrimary)
                            Spacer()
                            Text(L.t(AppLocalizationKey.locMessagesCount, agg.messageCount))
                                .interfaceFont(size: 11).foregroundColor(Color.mimo.textMuted)
                            Text("\(formatTokens(agg.promptTokens))↑ \(formatTokens(agg.completionTokens))↓")
                                .interfaceFont(size: 11, design: .monospaced).foregroundColor(Color.mimo.textSecondary)
                            Text(UsageStatisticsAggregator.costLabel(agg.costUSD))
                                .interfaceFont(size: 11).foregroundColor(Color.mimo.textSecondary)
                        }
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(Color.mimo.surface)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.mimo.border, lineWidth: 1))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
            } else {
                Text(L.t(AppLocalizationKey.locUsageDataForTheSelectedPeriod))
                    .interfaceFont(size: 12)
                    .foregroundColor(Color.mimo.textMuted)
            }
        }
        .onAppear {
            stats = appState.loadStorageStats()
            points = appState.loadUsageDataPoints()
        }
    }

    private func formatTokens(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 1_000 { return String(format: "%.1fk", Double(n) / 1_000) }
        return "\(n)"
    }

    private var formattedMessages: String {
        "\(UsageScreenSummaryLogic.messageCount(for: filteredPoints))"
    }
}

struct UsageStatCard: View {
    let title: String
    let value: String
    var subtitle: String? = nil
    let icon: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .interfaceFont(size: 12)
                    .foregroundColor(Color.mimo.textMuted)
                Text(title)
                    .interfaceFont(size: 12)
                    .foregroundColor(Color.mimo.textMuted)
            }
            
            Text(value)
                .interfaceFont(size: 24, weight: .bold)
                .foregroundColor(Color.mimo.textPrimary)
            
            if let subtitle = subtitle {
                Text(subtitle)
                    .interfaceFont(size: 12)
                    .foregroundColor(Color.mimo.textMuted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.mimo.surface)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
