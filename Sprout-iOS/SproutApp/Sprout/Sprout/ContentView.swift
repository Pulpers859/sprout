import SwiftUI

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var store: BudgetStore
    @EnvironmentObject private var quickEntryCoordinator: QuickEntryCoordinator

    @State private var transactionSheet: TransactionSheetRequest?
    @State private var budgetEditorTab: BudgetTab?
    @State private var isShowingSettings = false
    @State private var pendingDeleteTransaction: TransactionEntry?
    @State private var editingTransaction: TransactionEntry?
    @State private var shouldRestoreMonthResetPrompt = false
    @State private var successToastMessage: String?

    var body: some View {
        NavigationStack {
            BudgetDashboardView(
                tab: store.activeTab,
                onEditBudget: { budgetEditorTab = store.activeTab },
                onOpenSettings: { isShowingSettings = true },
                onStartNewMonth: { store.needsMonthResetPrompt = true },
                onRequestDeleteTransaction: { pendingDeleteTransaction = $0 },
                onEditTransaction: { editingTransaction = $0 },
                onOpenTransaction: { mode, seed in
                    transactionSheet = TransactionSheetRequest(
                        tab: store.activeTab,
                        mode: mode,
                        draft: store.makeDraft(for: store.activeTab, mode: mode, seed: seed),
                        style: .standard
                    )
                }
            )
            .toolbar(.hidden, for: .navigationBar)
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
                            HapticFeedback.success()
                            transactionSheet = nil
                            showSuccessToast(request.mode == .payment ? "Payment saved" : "Expense saved")
                        }
                    }
                case .quickCapture:
                    QuickCaptureSheet(
                        tab: request.tab,
                        mode: request.mode,
                        initialDraft: request.draft
                    ) { draft in
                        if store.addTransaction(mode: request.mode, draft: draft, tab: request.tab) {
                            HapticFeedback.success()
                            transactionSheet = nil
                            showSuccessToast(request.mode == .payment ? "Payment saved" : "Expense saved")
                        }
                    }
                }
            }
            .environmentObject(store)
        }
        .sheet(item: $budgetEditorTab) { tab in
            BudgetEditorSheet(
                tab: tab,
                startingAmount: store.budget(for: tab),
                carryover: store.carryover(for: tab)
            ) { amount in
                HapticFeedback.light()
                store.setBudget(amount, for: tab)
                budgetEditorTab = nil
            }
        }
        .sheet(isPresented: $isShowingSettings) {
            SettingsSheet()
                .environmentObject(store)
        }
        .sheet(item: $editingTransaction) { entry in
            TransactionEntrySheet(
                tab: entry.tab,
                mode: entry.isRefund ? .payment : .expense,
                initialDraft: TransactionDraft(
                    name: entry.name,
                    amountText: String(format: "%.2f", entry.amount),
                    note: entry.note,
                    selectedEmoji: entry.emoji,
                    date: entry.date
                )
            ) { draft in
                let mode: TransactionMode = entry.isRefund ? .payment : .expense
                if store.updateTransaction(entry, with: draft, mode: mode) {
                    HapticFeedback.success()
                    editingTransaction = nil
                    showSuccessToast("Transaction updated")
                }
            }
            .environmentObject(store)
        }
        // Deferred while a persistence alert is up: SwiftUI can only present one
        // alert per view, and the dropped one never re-presents on its own.
        .alert("New month, fresh start?", isPresented: Binding(
            get: { store.needsMonthResetPrompt && store.persistenceAlert == nil },
            set: { store.needsMonthResetPrompt = $0 }
        )) {
            Button("Keep") {
                store.keepCurrentTransactions()
            }
            Button("Reset Fresh", role: .destructive) {
                HapticFeedback.warning()
                store.resetMonth(carryOverRemainders: false)
            }
            Button("Carry Over") {
                HapticFeedback.light()
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
                HapticFeedback.warning()
                store.deleteTransaction(entry)
                pendingDeleteTransaction = nil
            }
        } message: { entry in
            Text("\(entry.name) on \(SproutDate.shortDate(entry.date)) will be removed.")
        }
        .alert(
            store.persistenceAlert?.title ?? "",
            isPresented: Binding(
                get: { store.persistenceAlert != nil },
                set: { if !$0 { store.persistenceAlert = nil } }
            ),
            presenting: store.persistenceAlert
        ) { _ in
            Button("OK", role: .cancel) { store.persistenceAlert = nil }
        } message: { alert in
            Text(alert.message)
        }
        .onOpenURL { url in
            guard let route = QuickEntryRoute(url: url) else { return }
            quickEntryCoordinator.present(.init(tab: route.tab, mode: route.mode))
        }
        .onAppear {
            store.refreshForCurrentDate()
            quickEntryCoordinator.consumePendingRequestIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
            quickEntryCoordinator.consumePendingRequestIfNeeded()
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            store.refreshForCurrentDate()
            quickEntryCoordinator.consumePendingRequestIfNeeded()
        }
        .onChange(of: quickEntryCoordinator.activeRequest) { _, request in
            guard request != nil else {
                restoreDeferredMonthResetPromptIfNeeded()
                return
            }
            presentQuickEntryIfPossible()
        }
        .onChange(of: transactionSheet == nil) { _, isSheetCleared in
            guard isSheetCleared else { return }
            presentQuickEntryIfPossible()
            restoreDeferredMonthResetPromptIfNeeded()
        }
        .overlay(alignment: .top) {
            if let message = successToastMessage {
                SuccessToastView(message: message)
                    .padding(.top, 60)
                    .transition(.asymmetric(
                        insertion: .move(edge: .top).combined(with: .opacity),
                        removal: .opacity
                    ))
            }
        }
        .animation(.snappy(duration: 0.35), value: successToastMessage != nil)
    }

    private func presentQuickEntryIfPossible() {
        guard let request = quickEntryCoordinator.activeRequest else { return }
        guard transactionSheet == nil else { return }

        if store.needsMonthResetPrompt {
            shouldRestoreMonthResetPrompt = true
            store.needsMonthResetPrompt = false
        }

        store.activeTab = request.tab
        transactionSheet = TransactionSheetRequest(
            tab: request.tab,
            mode: request.mode,
            draft: store.makeDraft(for: request.tab, mode: request.mode),
            style: .quickCapture
        )
        quickEntryCoordinator.dismiss()
    }

    private func showSuccessToast(_ message: String) {
        successToastMessage = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            successToastMessage = nil
        }
    }

    private func restoreDeferredMonthResetPromptIfNeeded() {
        guard shouldRestoreMonthResetPrompt else { return }
        guard transactionSheet == nil else { return }
        guard quickEntryCoordinator.activeRequest == nil else { return }

        shouldRestoreMonthResetPrompt = false
        store.needsMonthResetPrompt = true
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
