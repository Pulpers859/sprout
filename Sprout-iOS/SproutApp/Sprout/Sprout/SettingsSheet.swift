import SwiftUI
import UniformTypeIdentifiers

struct SettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: BudgetStore

    @State private var isShowingCategorySettings = false
    @State private var isShowingRecentMonths = false
    @State private var isExportingBackup = false
    @State private var isImportingBackup = false
    @State private var exportDocument: SproutBackupDocument?
    @State private var statusMessage: SettingsStatusMessage?

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    settingsSectionTitle(
                        title: "Organize",
                        subtitle: "Keep your categories tidy and easy to recognize."
                    )

                    Button {
                        isShowingCategorySettings = true
                    } label: {
                        SettingsRow(
                            symbol: "square.grid.2x2",
                            title: "Manage Categories",
                            subtitle: "Edit names and choose icons for personal spending."
                        )
                    }
                    .buttonStyle(.plain)

                    settingsSectionTitle(
                        title: "History",
                        subtitle: "Reference the last two closed months without mixing them into your current budget."
                    )

                    Button {
                        isShowingRecentMonths = true
                    } label: {
                        SettingsRow(
                            symbol: "clock.arrow.circlepath",
                            title: "Recent Months",
                            subtitle: store.archivedMonths.isEmpty
                                ? "Closed months will appear here after you reset into a new month."
                                : "Review your last \(store.archivedMonths.count) closed month\(store.archivedMonths.count == 1 ? "" : "s")."
                        )
                    }
                    .buttonStyle(.plain)

                    settingsSectionTitle(
                        title: "Backup",
                        subtitle: "Export a copy of your budget data or restore from a previous backup."
                    )

                    VStack(spacing: 12) {
                        Button {
                            exportBackup()
                        } label: {
                            SettingsRow(
                                symbol: "square.and.arrow.up",
                                title: "Export Backup",
                                subtitle: "Save a JSON backup to Files or another destination."
                            )
                        }
                        .buttonStyle(.plain)

                        Button {
                            isImportingBackup = true
                        } label: {
                            SettingsRow(
                                symbol: "square.and.arrow.down",
                                title: "Import Backup",
                                subtitle: "Restore your budget data from a previous Sprout backup."
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(20)
            }
            .background(Color.sproutBackground.ignoresSafeArea())
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundStyle(Color.sageDark)
                }
            }
        }
        .sheet(isPresented: $isShowingCategorySettings) {
            CategorySettingsSheet()
                .environmentObject(store)
        }
        .sheet(isPresented: $isShowingRecentMonths) {
            RecentMonthsSheet()
                .environmentObject(store)
        }
        .fileExporter(
            isPresented: $isExportingBackup,
            document: exportDocument,
            contentType: .json,
            defaultFilename: backupFileName
        ) { result in
            switch result {
            case .success:
                statusMessage = SettingsStatusMessage(
                    title: "Backup Exported",
                    message: "Your Sprout backup was exported successfully."
                )
            case .failure(let error):
                guard !isUserCancelled(error) else { return }
                statusMessage = SettingsStatusMessage(
                    title: "Export Failed",
                    message: error.localizedDescription
                )
            }
            exportDocument = nil
        }
        .fileImporter(
            isPresented: $isImportingBackup,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                importBackup(from: url)
            case .failure(let error):
                guard !isUserCancelled(error) else { return }
                statusMessage = SettingsStatusMessage(
                    title: "Import Failed",
                    message: error.localizedDescription
                )
            }
        }
        .alert(item: $statusMessage) { status in
            Alert(
                title: Text(status.title),
                message: Text(status.message),
                dismissButton: .default(Text("OK"))
            )
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var backupFileName: String {
        "Sprout-Backup-\(dateStamp(from: Date()))"
    }

    private func exportBackup() {
        do {
            exportDocument = SproutBackupDocument(data: try store.exportBackupData())
            isExportingBackup = true
        } catch {
            statusMessage = SettingsStatusMessage(
                title: "Export Failed",
                message: error.localizedDescription
            )
        }
    }

    private func importBackup(from url: URL) {
        let didStartSecurityScope = url.startAccessingSecurityScopedResource()
        defer {
            if didStartSecurityScope {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let data = try Data(contentsOf: url)
            try store.importBackupData(data)
            statusMessage = SettingsStatusMessage(
                title: "Backup Imported",
                message: "Your Sprout data has been restored from the selected backup."
            )
        } catch {
            statusMessage = SettingsStatusMessage(
                title: "Import Failed",
                message: error.localizedDescription
            )
        }
    }

    private func settingsSectionTitle(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(.title3, design: .serif, weight: .semibold))
                .foregroundStyle(Color.sproutText)

            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(Color.sproutTextSecondary)
        }
    }

    private func dateStamp(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = .current
        formatter.locale = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private func isUserCancelled(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == NSCocoaErrorDomain && nsError.code == NSUserCancelledError
    }
}

private struct SettingsRow: View {
    let symbol: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.sageMist)
                    .frame(width: 48, height: 48)

                Image(systemName: symbol)
                    .font(.headline)
                    .foregroundStyle(Color.sageDark)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(Color.sproutText)

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(Color.sproutTextSecondary)
                    .multilineTextAlignment(.leading)
            }

            Spacer(minLength: 8)

            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.sproutTextMuted)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.sproutCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.sproutBorder, lineWidth: 1)
        )
        .shadow(color: Color.sproutShadow, radius: 14, x: 0, y: 8)
    }
}

private struct SettingsStatusMessage: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

private struct RecentMonthsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: BudgetStore

    @State private var selectedMonth: ArchivedBudgetMonth?

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                if store.archivedMonths.isEmpty {
                    ContentUnavailableView(
                        "No archived months yet",
                        systemImage: "clock.arrow.circlepath",
                        description: Text("When you choose Reset Fresh or Carry Over at month rollover, Sprout will keep the closed month here for reference.")
                    )
                    .padding(.top, 60)
                    .padding(.horizontal, 20)
                } else {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("These snapshots are read-only and capped at the last two closed months.")
                            .font(.subheadline)
                            .foregroundStyle(Color.sproutTextSecondary)

                        ForEach(store.archivedMonths) { month in
                            Button {
                                selectedMonth = month
                            } label: {
                                ArchivedMonthRow(month: month)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(20)
                }
            }
            .background(Color.sproutBackground.ignoresSafeArea())
            .navigationTitle("Recent Months")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundStyle(Color.sageDark)
                }
            }
        }
        .sheet(item: $selectedMonth) { month in
            ArchivedMonthDetailView(month: month)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

private struct ArchivedMonthRow: View {
    let month: ArchivedBudgetMonth

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(SproutDate.monthYearTitle(forMonthKey: month.monthKey))
                        .font(.system(.title3, design: .serif, weight: .semibold))
                        .foregroundStyle(Color.sproutText)

                    Text("\(month.transactions.count) transaction\(month.transactions.count == 1 ? "" : "s") saved")
                        .font(.footnote)
                        .foregroundStyle(Color.sproutTextMuted)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.sproutTextMuted)
            }

            HStack(spacing: 10) {
                ArchivedMonthBudgetPill(
                    title: "Personal",
                    remaining: month.remaining(for: .personal)
                )

                ArchivedMonthBudgetPill(
                    title: "Grocery",
                    remaining: month.remaining(for: .grocery)
                )
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.sproutCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.sproutBorder, lineWidth: 1)
        )
        .shadow(color: Color.sproutShadow, radius: 12, x: 0, y: 8)
    }
}

private struct ArchivedMonthBudgetPill: View {
    let title: String
    let remaining: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.sproutTextMuted)
                .textCase(.uppercase)

            Text(remaining < 0 ? "Over \(SproutFormatters.currency(abs(remaining)))" : "\(SproutFormatters.currency(remaining)) left")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(remaining < 0 ? Color.sproutRed : Color.sageDark)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.sproutCardSoft)
        )
    }
}

private struct ArchivedMonthDetailView: View {
    @Environment(\.dismiss) private var dismiss

    let month: ArchivedBudgetMonth

    @State private var selectedTab: BudgetTab = .personal

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(SproutDate.monthYearTitle(forMonthKey: month.monthKey))
                            .font(.system(.title2, design: .serif, weight: .semibold))
                            .foregroundStyle(Color.sproutText)

                        Text("Read-only snapshot of the month you closed out.")
                            .font(.subheadline)
                            .foregroundStyle(Color.sproutTextSecondary)
                    }

                    Picker("Budget", selection: $selectedTab) {
                        ForEach(BudgetTab.allCases) { tab in
                            Text(tab.shortTitle)
                                .tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)

                    ArchivedMonthStatsGrid(month: month, tab: selectedTab)

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Transactions")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.sproutTextMuted)
                            .textCase(.uppercase)

                        if month.transactions(for: selectedTab).isEmpty {
                            Text("No \(selectedTab.shortTitle.lowercased()) transactions were saved for this month.")
                                .font(.body)
                                .foregroundStyle(Color.sproutTextMuted)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.vertical, 32)
                        } else {
                            ForEach(month.transactions(for: selectedTab), id: \.id) { entry in
                                ArchivedTransactionRow(entry: entry)
                            }
                        }
                    }
                }
                .padding(20)
            }
            .background(Color.sproutBackground.ignoresSafeArea())
            .navigationTitle("Month Detail")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundStyle(Color.sageDark)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
}

private struct ArchivedMonthStatsGrid: View {
    let month: ArchivedBudgetMonth
    let tab: BudgetTab

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                ArchivedMetricCard(title: "Budget", value: SproutFormatters.currency(month.budget(for: tab)), tone: .sproutText)
                ArchivedMetricCard(title: "Spent", value: SproutFormatters.currency(max(month.netSpent(for: tab), 0)), tone: .sproutText)
            }

            HStack(spacing: 10) {
                ArchivedMetricCard(
                    title: "Remaining",
                    value: SproutFormatters.currency(month.remaining(for: tab)),
                    tone: month.remaining(for: tab) < 0 ? .sproutRed : .sageDark
                )
                ArchivedMetricCard(
                    title: "Carryover",
                    value: SproutFormatters.currency(tab == .personal ? month.personalCarryover : month.groceryCarryover),
                    tone: .sproutTextSecondary
                )
            }
        }
    }
}

private struct ArchivedMetricCard: View {
    let title: String
    let value: String
    let tone: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.sproutTextMuted)
                .textCase(.uppercase)

            Text(value)
                .font(.system(.headline, design: .rounded, weight: .semibold))
                .foregroundStyle(tone)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.sproutCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.sproutBorder, lineWidth: 1)
        )
    }
}

private struct ArchivedTransactionRow: View {
    let entry: TransactionEntry

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(entry.isRefund ? "💸" : entry.emoji)
                .font(.title3)
                .frame(width: 42, height: 42)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.sproutCardSoft)
                )

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(entry.name)
                        .font(.body.weight(.medium))
                        .foregroundStyle(Color.sproutText)

                    Spacer()

                    Text("\(entry.isRefund ? "+" : "−")\(SproutFormatters.currency(entry.amount))")
                        .font(.system(.subheadline, design: .monospaced, weight: .semibold))
                        .foregroundStyle(entry.isRefund ? Color.sageDark : Color.sproutText)
                }

                HStack(spacing: 6) {
                    Text(SproutDate.shortDate(entry.date))

                    if entry.isRefund {
                        Text("payment")
                            .foregroundStyle(Color.sageDark)
                    }

                    if !entry.note.isEmpty {
                        Text(entry.note)
                    }
                }
                .font(.footnote)
                .foregroundStyle(Color.sproutTextMuted)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.sproutCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.sproutBorder, lineWidth: 1)
        )
    }
}
