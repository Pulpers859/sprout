import SwiftUI

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var store: BudgetStore
    @EnvironmentObject private var quickEntryCoordinator: QuickEntryCoordinator
    @EnvironmentObject private var holidayRouter: HolidayRouter

    @State private var transactionSheet: TransactionSheetRequest?
    @State private var budgetEditorTab: BudgetTab?
    @State private var isShowingSettings = false
    @State private var pendingDeleteTransaction: TransactionEntry?
    @State private var editingTransaction: TransactionEntry?
    @State private var shouldRestoreMonthResetPrompt = false
    @State private var successToastMessage: String?
    @State private var successToastToken = UUID()
    /// Driven by a path so switching tabs can clear it. Without that, a
    /// quick-add Shortcut that moves the app to Grocery left the user on a
    /// pushed Holiday screen with Grocery selected underneath, and Back dropped
    /// them into the Grocery dashboard from a Holiday one.
    @State private var holidayPath = NavigationPath()

    var body: some View {
        NavigationStack(path: $holidayPath) {
            Group {
                if let tab = store.activeSection.budgetTab {
                    BudgetDashboardView(
                        tab: tab,
                        onEditBudget: { budgetEditorTab = tab },
                        onOpenSettings: { isShowingSettings = true },
                        onStartNewMonth: { store.needsMonthResetPrompt = true },
                        onRequestDeleteTransaction: { pendingDeleteTransaction = $0 },
                        onEditTransaction: { editingTransaction = $0 },
                        onOpenTransaction: { mode, seed in
                            transactionSheet = TransactionSheetRequest(
                                tab: tab,
                                mode: mode,
                                draft: store.makeDraft(for: tab, mode: mode, seed: seed),
                                style: .standard
                            )
                        }
                    )
                } else {
                    HolidayDashboardView(onOpenSettings: { isShowingSettings = true })
                }
            }
            .navigationDestination(for: HolidayRecipientRoute.self) { route in
                GiftRecipientDetailView(recipientID: route.recipientID)
            }
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
                startingAmount: store.baseBudget(for: tab),
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
        // Presented here rather than inside the holiday views so there is one
        // sheet authority in the app and `isPresentingAnySheet` can see it.
        .sheet(item: Binding(
            get: { holidayRouter.sheet },
            set: { holidayRouter.sheet = $0 }
        )) { sheet in
            holidaySheet(sheet)
                .environmentObject(store)
                .environmentObject(holidayRouter)
        }
        .sheet(item: $editingTransaction) { entry in
            TransactionEntrySheet(
                tab: entry.tab,
                mode: entry.isRefund ? .payment : .expense,
                // Editing does not create recurring rules, so offering the toggle
                // here only ever silently discarded the user's choice.
                isEditing: true,
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
        .alert(monthResetTitle, isPresented: Binding(
            // Also held back while a holiday confirmation is up: two alerts
            // requested at once leaves one of them never shown. `needsMonthResetPrompt`
            // stays true, so this re-presents by itself once the other clears.
            get: {
                store.needsMonthResetPrompt
                    && store.persistenceAlert == nil
                    && holidayRouter.confirmation == nil
            },
            set: { store.needsMonthResetPrompt = $0 }
        )) {
            // An explicit no-op cancel, so the action iOS invokes on an implicit
            // dismissal (VoiceOver escape, hardware Esc) does nothing at all.
            // Relying on SwiftUI to synthesize one was luck, not design, and
            // "Keep" must not take the role: it advances the stored month and
            // posts recurring catch-up, so it is not a no-op.
            Button("Cancel", role: .cancel) {}

            // Safest real option first. Reordering this to put "Carry Over" on top
            // was a mistake: it also clears the ledger, so anyone tapping the first
            // button out of habit lost their transactions, and it carries no
            // destructive role to warn them.
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
            Text(monthResetMessage)
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
            holidayConfirmationTitle,
            isPresented: Binding(
                get: { holidayRouter.confirmation != nil },
                set: { if !$0 { holidayRouter.confirmation = nil } }
            ),
            presenting: holidayRouter.confirmation
        ) { confirmation in
            Button("Cancel", role: .cancel) {}
            Button("Remove", role: .destructive) {
                HapticFeedback.warning()
                switch confirmation {
                case .removeGift(let purchase):
                    store.removeHolidayPurchase(purchase)
                case .removePerson(let recipient):
                    store.removeHolidayRecipient(recipient)
                }
                holidayRouter.confirmation = nil
            }
        } message: { confirmation in
            Text(holidayConfirmationMessage(confirmation))
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
            // Routed through the coordinator even for holiday, so a link that
            // arrives while another sheet is up is held rather than dropped.
            quickEntryCoordinator.present(.init(section: route.section, mode: route.mode))
        }
        .onAppear {
            store.refreshForCurrentDate()
            quickEntryCoordinator.consumePendingRequestIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
            quickEntryCoordinator.consumePendingRequestIfNeeded()
        }
        .onChange(of: store.activeSection) { _, _ in
            // A pushed holiday screen must not survive a tab change, and the
            // store-level calendar selection must not survive it either — it
            // outlived the dashboard's own state, so re-expanding the calendar
            // showed a stale selected day.
            holidayPath = NavigationPath()
            store.selectedCalendarDate = nil
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

    private var monthResetTitle: String {
        switch store.monthResetContext {
        case .monthEnded:
            "New month, fresh start?"
        case .earlyClose:
            "Close out \(store.currentMonthLabel) early?"
        }
    }

    /// The prompt is raised two different ways and used to describe only one of
    /// them. Tapping the "month ending soon" banner on the 28th produced
    /// "September 2026 is over" while the card behind it read "3 days left".
    ///
    /// Every option also runs the recurring catch-up, so claiming Keep changes
    /// nothing was inaccurate whenever a rule had come due.
    private var monthResetMessage: String {
        let lead: String
        switch store.monthResetContext {
        case .monthEnded:
            lead = "\(store.currentMonthLabel) is over."
        case .earlyClose:
            let days = store.daysLeftInDisplayedMonth
            lead = "\(store.currentMonthLabel) isn't over yet — \(days) day\(days == 1 ? "" : "s") left. "
                + "Closing out now starts a fresh period, and you'll still be in \(store.currentMonthLabel)."
        }

        // Worded to stay true whether this is a real rollover or an early close.
        let choices = " Reset Fresh clears this period's transactions and starts at your full budget. "
            + "Carry Over clears them too but keeps any positive leftover on top of it. "
            + "Keep leaves this period's transactions in place."

        let base = lead + choices
        guard store.hasRecurringRules else { return base }
        return base + " Either way, any recurring items that came due are added."
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
            || holidayRouter.sheet != nil
            // A quick-add link arriving while "Remove person?" was on screen
            // used to pass this guard, present a sheet over the live alert, and
            // consume the request — so one of the two was silently dropped.
            || holidayRouter.confirmation != nil
    }

    private func presentQuickEntryIfPossible() {
        guard let request = quickEntryCoordinator.activeRequest else { return }
        guard !isPresentingAnySheet else { return }

        if store.needsMonthResetPrompt {
            shouldRestoreMonthResetPrompt = true
            store.needsMonthResetPrompt = false
        }

        store.activeSection = request.section

        if request.section == .holiday {
            holidayRouter.present(.addGift(recipient: .unspecified, isReturn: false))
        } else {
            transactionSheet = TransactionSheetRequest(
                tab: request.tab,
                mode: request.mode,
                draft: store.makeDraft(for: request.tab, mode: request.mode),
                style: .quickCapture
            )
        }
        quickEntryCoordinator.dismiss()
    }

    @ViewBuilder
    private func holidaySheet(_ sheet: HolidayRouter.Sheet) -> some View {
        switch sheet {
        case .addGift(let recipient, let isReturn):
            GiftEntrySheet(
                initialDraft: store.makeHolidayPurchaseDraft(
                    for: recipient.recipientID,
                    isReturn: isReturn
                ),
                recipientIsChosen: recipient.isChosen
            ) { draft in
                guard store.addHolidayPurchase(draft: draft) else { return false }
                HapticFeedback.success()
                holidayRouter.dismiss()
                showSuccessToast(draft.isReturn ? "Return saved" : "Gift saved")
                return true
            }

        case .editGift(let purchase):
            GiftEntrySheet(
                isEditing: true,
                initialDraft: store.makeHolidayEditDraft(for: purchase),
                recipientIsChosen: true
            ) { draft in
                guard store.updateHolidayPurchase(purchase, with: draft) else { return false }
                HapticFeedback.success()
                holidayRouter.dismiss()
                showSuccessToast(draft.isReturn ? "Return updated" : "Gift updated")
                return true
            }

        case .addPerson:
            GiftRecipientSheet(initialDraft: GiftRecipientDraft()) { draft in
                guard store.addHolidayRecipient(draft: draft) != nil else { return false }
                HapticFeedback.success()
                holidayRouter.dismiss()
                showSuccessToast("Person added")
                return true
            }

        case .editPerson(let recipient):
            GiftRecipientSheet(
                isEditing: true,
                initialDraft: GiftRecipientDraft(recipient: recipient)
            ) { draft in
                guard store.updateHolidayRecipient(recipient, with: draft) else { return false }
                HapticFeedback.success()
                holidayRouter.dismiss()
                showSuccessToast("Person updated")
                return true
            }

        case .editBudget:
            BudgetEditorSheet.holiday(
                seasonLabel: store.holidaySeasonLabel,
                startingAmount: store.holidayBudget
            ) { amount in
                HapticFeedback.light()
                store.setHolidayBudget(amount)
                holidayRouter.dismiss()
            }

        case .renameSeason:
            holidaySeasonSheet(mode: .rename)

        case .startNewSeason:
            holidaySeasonSheet(mode: .startNew)

        case .seasonHistory:
            HolidaySeasonsSheet()
        }
    }

    private func holidaySeasonSheet(mode: HolidaySeasonSheet.Mode) -> HolidaySeasonSheet {
        HolidaySeasonSheet(
            mode: mode,
            currentLabel: store.holidaySeasonLabel,
            giftCount: store.holidayPurchaseCount,
            personCount: store.holidayRecipients.count,
            budget: store.holidayBudget,
            archivedCount: store.holidaySeasonHistory.count,
            defaultNewLabel: store.defaultNewHolidaySeasonLabel
        ) { label, carryRecipients in
            switch mode {
            case .rename:
                guard store.renameHolidaySeason(label) else { return false }
                HapticFeedback.light()
                holidayRouter.dismiss()
                showSuccessToast("Season renamed")
            case .startNew:
                HapticFeedback.success()
                store.startNewHolidaySeason(
                    label: label.isEmpty ? nil : label,
                    carryRecipients: carryRecipients
                )
                holidayRouter.dismiss()
                showSuccessToast("New season started")
            }
            return true
        }
    }

    private var holidayConfirmationTitle: String {
        switch holidayRouter.confirmation {
        case .removeGift(let purchase):
            purchase.isReturn ? "Remove return?" : "Remove gift?"
        case .removePerson:
            "Remove person?"
        case nil:
            ""
        }
    }

    /// Names the exact cost of each removal. For a person that includes the
    /// gifts that go with them — leaving those behind would keep money in the
    /// season total with nobody attached to explain it.
    private func holidayConfirmationMessage(_ confirmation: HolidayRouter.Confirmation) -> String {
        switch confirmation {
        case .removeGift(let purchase):
            let kind = purchase.isReturn ? "return" : "gift"
            return "This \(kind), \(purchase.name) (\(SproutFormatters.currency(purchase.amount))), "
                + "will be removed from your holiday spending."
        case .removePerson(let recipient):
            let tally = store.holidayTally(for: recipient.id)
            guard tally.rows > 0 else {
                return "\(recipient.name) will be removed from your holiday list."
            }
            var items = ["\(tally.gifts) gift\(tally.gifts == 1 ? "" : "s")"]
            if tally.returns > 0 {
                items.append("\(tally.returns) return\(tally.returns == 1 ? "" : "s")")
            }
            // The figure comes from the same tally the dashboard shows, so what
            // the user is told they are losing is exactly what leaves the total.
            return "\(recipient.name), \(items.joined(separator: " and ")) "
                + "totalling \(SproutFormatters.currency(tally.spent)) "
                + "will be removed from your holiday spending."
        }
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
        .environmentObject(HolidayRouter())
}
