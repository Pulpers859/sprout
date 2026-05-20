import SwiftUI

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var store: BudgetStore
    @EnvironmentObject private var quickEntryCoordinator: QuickEntryCoordinator

    @State private var transactionSheet: TransactionSheetRequest?
    @State private var budgetEditorTab: BudgetTab?
    @State private var isShowingSettings = false
    @State private var pendingDeleteTransaction: TransactionEntry?

    var body: some View {
        NavigationStack {
            BudgetDashboardView(
                tab: store.activeTab,
                onEditBudget: { budgetEditorTab = store.activeTab },
                onRequestDeleteTransaction: { pendingDeleteTransaction = $0 },
                onOpenTransaction: { mode, seed in
                    transactionSheet = TransactionSheetRequest(
                        tab: store.activeTab,
                        mode: mode,
                        draft: store.makeDraft(for: store.activeTab, mode: mode, seed: seed),
                        style: .standard
                    )
                }
            )
            .navigationTitle("Sprout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button("Reset") {
                        store.needsMonthResetPrompt = true
                    }

                    Button {
                        isShowingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                BottomTabBarView(selection: $store.activeTab)
            }
        }
        .sheet(item: $transactionSheet) { request in
            Group {
                switch request.style {
                case .standard:
                    TransactionEntrySheet(
                        tab: request.tab,
                        mode: request.mode,
                        initialDraft: request.draft
                    ) { draft in
                        if store.addTransaction(mode: request.mode, draft: draft, tab: request.tab) {
                            transactionSheet = nil
                        }
                    }
                case .quickCapture:
                    QuickCaptureSheet(
                        tab: request.tab,
                        mode: request.mode,
                        initialDraft: request.draft
                    ) { draft in
                        if store.addTransaction(mode: request.mode, draft: draft, tab: request.tab) {
                            transactionSheet = nil
                        }
                    }
                }
            }
            .environmentObject(store)
        }
        .sheet(item: $budgetEditorTab) { tab in
            BudgetEditorSheet(tab: tab, startingAmount: store.budget(for: tab)) { amount in
                store.setBudget(amount, for: tab)
                budgetEditorTab = nil
            }
        }
        .sheet(isPresented: $isShowingSettings) {
            SettingsSheet()
                .environmentObject(store)
        }
        .alert("New month, fresh start?", isPresented: $store.needsMonthResetPrompt) {
            Button("Keep") {
                store.keepCurrentTransactions()
            }
            Button("Reset Fresh", role: .destructive) {
                store.resetMonth(carryOverRemainders: false)
            }
            Button("Carry Over") {
                store.resetMonth(carryOverRemainders: true)
            }
        } message: {
            Text("This will clear all transactions for the current period. Carry Over keeps any positive leftover balance in each budget for the new month.")
        }
        .alert("Remove transaction?", isPresented: Binding(
            get: { pendingDeleteTransaction != nil },
            set: { if !$0 { pendingDeleteTransaction = nil } }
        ), presenting: pendingDeleteTransaction) { entry in
            Button("Cancel", role: .cancel) {}
            Button("Remove", role: .destructive) {
                store.deleteTransaction(entry)
                pendingDeleteTransaction = nil
            }
        } message: { entry in
            Text("\(entry.name) on \(SproutDate.shortDate(entry.date)) will be removed.")
        }
        .onOpenURL { url in
            guard let route = QuickEntryRoute(url: url) else { return }
            quickEntryCoordinator.present(.init(tab: route.tab, mode: route.mode))
        }
        .onAppear {
            store.processRecurringTransactionsIfNeeded()
            quickEntryCoordinator.consumePendingRequestIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
            quickEntryCoordinator.consumePendingRequestIfNeeded()
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            store.processRecurringTransactionsIfNeeded()
            quickEntryCoordinator.consumePendingRequestIfNeeded()
        }
        .onChange(of: quickEntryCoordinator.activeRequest) { _, request in
            guard let request else { return }
            store.activeTab = request.tab
            transactionSheet = TransactionSheetRequest(
                tab: request.tab,
                mode: request.mode,
                draft: store.makeDraft(for: request.tab, mode: request.mode),
                style: .quickCapture
            )
            quickEntryCoordinator.dismiss()
        }
    }
}

private struct TransactionSheetRequest: Identifiable {
    let id = UUID()
    let tab: BudgetTab
    let mode: TransactionMode
    let draft: TransactionDraft
    let style: TransactionPresentationStyle
}

#Preview {
    ContentView()
        .environmentObject(BudgetStore())
        .environmentObject(QuickEntryCoordinator())
}
