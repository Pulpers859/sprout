import SwiftUI
import UniformTypeIdentifiers

struct SettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: BudgetStore

    @State private var isShowingCategorySettings = false
    @State private var isShowingRecurringTransactions = false
    @State private var isShowingRecentMonths = false
    @State private var isExportingBackup = false
    @State private var isImportingBackup = false
    @State private var exportDocument: SproutBackupDocument?
    @State private var statusMessage: SettingsStatusMessage?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button {
                        isShowingCategorySettings = true
                    } label: {
                        SettingsRow(
                            symbol: "square.grid.2x2",
                            title: "Manage Categories",
                            subtitle: "Names and icons for personal spending",
                            tint: .sageDark
                        )
                    }
                    .buttonStyle(.plain)

                    Button {
                        isShowingRecurringTransactions = true
                    } label: {
                        SettingsRow(
                            symbol: "repeat",
                            title: "Recurring Transactions",
                            subtitle: recurringCount == 0
                                ? "No automatic expenses or payments"
                                : "\(recurringCount) automatic item\(recurringCount == 1 ? "" : "s")",
                            tint: .sproutBlue
                        )
                    }
                    .buttonStyle(.plain)
                } header: {
                    Text("Organize")
                }

                Section {
                    Button {
                        isShowingRecentMonths = true
                    } label: {
                        SettingsRow(
                            symbol: "clock.arrow.circlepath",
                            title: "Recent Months",
                            subtitle: store.archivedMonths.isEmpty
                                ? "Closed months appear after a reset"
                                : "\(store.archivedMonths.count) closed month\(store.archivedMonths.count == 1 ? "" : "s") available",
                            tint: .sproutBlue
                        )
                    }
                    .buttonStyle(.plain)
                } header: {
                    Text("History")
                }

                Section {
                    Button {
                        exportBackup()
                    } label: {
                        SettingsRow(
                            symbol: "square.and.arrow.up",
                            title: "Export Backup",
                            subtitle: "Save a portable copy of your data",
                            tint: .sproutAmber
                        )
                    }
                    .buttonStyle(.plain)

                    Button {
                        isImportingBackup = true
                    } label: {
                        SettingsRow(
                            symbol: "square.and.arrow.down",
                            title: "Import Backup",
                            subtitle: "Restore a previous Sprout backup",
                            tint: .sproutAmber
                        )
                    }
                    .buttonStyle(.plain)
                } header: {
                    Text("Backup")
                } footer: {
                    Text("Backups include budgets, transactions, recurring entries, categories, and recent month history.")
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
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
        .sheet(isPresented: $isShowingRecurringTransactions) {
            RecurringTransactionsSheet()
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
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private var backupFileName: String {
        "Sprout-Backup-\(dateStamp(from: Date()))"
    }

    private var recurringCount: Int {
        BudgetTab.allCases.reduce(0) { $0 + store.recurringRules(for: $1).count }
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

private struct RecurringTransactionsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: BudgetStore

    @State private var pendingDeleteRule: RecurringTransactionRule?

    private var recurringCount: Int {
        BudgetTab.allCases.reduce(0) { $0 + store.recurringRules(for: $1).count }
    }

    var body: some View {
        NavigationStack {
            Group {
                if recurringCount == 0 {
                    ContentUnavailableView(
                        "No recurring transactions",
                        systemImage: "repeat",
                        description: Text("Mark an expense or payment as recurring when you add it, and it will appear here.")
                    )
                } else {
                    List {
                        ForEach(BudgetTab.allCases) { tab in
                            let rules = store.recurringRules(for: tab)

                            if !rules.isEmpty {
                                Section(tab.shortTitle) {
                                    ForEach(rules) { rule in
                                        recurringRuleRow(rule, tab: tab)
                                    }
                                }
                            }
                        }
                    }
                    .scrollContentBackground(.hidden)
                }
            }
            .background(Color.sproutBackground.ignoresSafeArea())
            .navigationTitle("Recurring")
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
        .alert("Remove recurring item?", isPresented: Binding(
            get: { pendingDeleteRule != nil },
            set: { if !$0 { pendingDeleteRule = nil } }
        ), presenting: pendingDeleteRule) { rule in
            Button("Keep", role: .cancel) {}
            Button("Remove", role: .destructive) {
                store.removeRecurringRule(rule)
                pendingDeleteRule = nil
            }
        } message: { rule in
            Text("\(rule.name) will stop posting automatically.")
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func recurringRuleRow(_ rule: RecurringTransactionRule, tab: BudgetTab) -> some View {
        HStack(spacing: 12) {
            Text(rule.isRefund ? "💸" : rule.emoji)
                .font(.title3)
                .frame(width: 40, height: 40)
                .background(tab.accentLightColor, in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(rule.name)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.sproutText)
                    .lineLimit(1)

                Text("\(rule.frequency.shortTitle) · Next \(SproutDate.shortDate(rule.nextOccurrenceDate))")
                    .font(.footnote)
                    .foregroundStyle(Color.sproutTextMuted)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Text("\(rule.isRefund ? "+" : "−")\(SproutFormatters.currency(rule.amount))")
                .font(.system(.subheadline, design: .rounded, weight: .bold))
                .foregroundStyle(rule.isRefund ? Color.sageDark : Color.sproutText)

            Menu {
                Button("Remove recurring item", systemImage: "trash", role: .destructive) {
                    pendingDeleteRule = rule
                }
            } label: {
                Image(systemName: "ellipsis")
                    .foregroundStyle(Color.sproutTextMuted)
                    .frame(width: 32, height: 32)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct SettingsRow: View {
    let symbol: String
    let title: String
    let subtitle: String
    let tint: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.white)
                .frame(width: 32, height: 32)
                .background(tint, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.sproutText)

                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(Color.sproutTextMuted)
                    .multilineTextAlignment(.leading)
            }

            Spacer(minLength: 8)

            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.sproutTextMuted)
        }
        .contentShape(Rectangle())
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
                        Text("These snapshots are read-only and capped at the last twelve closed months.")
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
        .background(Color.sproutCard, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.sproutBorder, lineWidth: 1))
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
        .background(Color.sproutCardSoft, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
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
        .background(Color.sproutCard, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.sproutBorder, lineWidth: 1))
    }
}

private struct ArchivedTransactionRow: View {
    let entry: TransactionEntry

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(entry.isRefund ? "💸" : entry.emoji)
                .font(.title3)
                .frame(width: 40, height: 40)
                .background(Color.sproutCardSoft, in: Circle())

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
        .padding(.vertical, 10)
    }
}
