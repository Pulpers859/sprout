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
    @State private var successToastToken = UUID()

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
                        saveNewTransaction(request: request, draft: draft)
                    }
                case .quickCapture:
                    QuickCaptureSheet(
                        tab: request.tab,
                        mode: request.mode,
                        initialDraft: request.draft
                    ) { draft in
                        saveNewTransaction(request: request, draft: draft)
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
                // Editing does not create recurring rules, so offering the toggle
                // here only ever silently discarded the user's choice.
                allowsRecurring: false,
                initialDraft: store.makeEditDraft(for: entry)
            ) { draft in
                let mode: TransactionMode = entry.isRefund ? .payment : .expense
                guard store.updateTransaction(entry, with: draft, mode: mode) else { return false }
                HapticFeedback.success()
                editingTransaction = nil
                showSuccessToast("Transaction updated")
                return true
            }
            .environmentObject(store)
        }
        // Deferred while a persistence alert is up: SwiftUI can only present one
        // alert per view, and the dropped one never re-presents on its own.
        .alert("New month, fresh start?", isPresented: Binding(
            get: { store.needsMonthResetPrompt && store.persistenceAlert == nil },
            set: { store.needsMonthResetPrompt = $0 }
        )) {
            // Most-likely intent first; the irreversible clear is not the middle
            // button any more.
            Button("Carry Over") {
                HapticFeedback.light()
                store.resetMonth(carryOverRemainders: true)
            }
            Button("Reset Fresh", role: .destructive) {
                HapticFeedback.warning()
                store.resetMonth(carryOverRemainders: false)
            }
            Button("Keep", role: .cancel) {
                store.keepCurrentTransactions()
            }
        } message: {
            Text("\(store.currentMonthLabel) is over. Reset Fresh clears this period's transactions and starts at your full budget. Carry Over clears them too but adds any positive leftover to next month. Keep leaves everything exactly as it is.")
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
        .onChange(of: isPresentingAnySheet) { _, isPresenting in
            guard !isPresenting else { return }
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

    private func saveNewTransaction(request: TransactionSheetRequest, draft: TransactionDraft) -> Bool {
        guard store.addTransaction(mode: request.mode, draft: draft, tab: request.tab) else { return false }
        HapticFeedback.success()
        transactionSheet = nil
        showSuccessToast(request.mode == .payment ? "Payment saved" : "Expense saved")
        return true
    }

    /// SwiftUI presents one sheet per view, so a quick-entry request arriving while
    /// Settings, the budget editor, or an edit sheet is up used to be consumed and
    /// then silently dropped — the sheet simply never appeared. The request is now
    /// held until every sheet is down.
    private var isPresentingAnySheet: Bool {
        transactionSheet != nil
            || budgetEditorTab != nil
            || editingTransaction != nil
            || isShowingSettings
    }

    private func presentQuickEntryIfPossible() {
        guard let request = quickEntryCoordinator.activeRequest else { return }
        guard !isPresentingAnySheet else { return }

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
        let token = UUID()
        successToastToken = token
        // Token-guarded so a second toast is not cut short by the first's timer.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            guard successToastToken == token else { return }
            successToastMessage = nil
        }
    }

    private func restoreDeferredMonthResetPromptIfNeeded() {
        guard shouldRestoreMonthResetPrompt else { return }
        guard !isPresentingAnySheet else { return }
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
