import Testing
import Foundation
@testable import Sprout

/// Holiday spending tracker.
///
/// The first group is the one that matters most: the whole promise of this
/// feature is that gift money is not part of the monthly budget, and those
/// tests fail loudly if any of it leaks across.
@MainActor
struct HolidayStoreTests {

    private func makeStore(
        calendar: Calendar = .current,
        now: (() -> Date)? = nil
    ) -> BudgetStore {
        BudgetStore(
            fileManager: .default,
            calendar: calendar,
            saveURL: Self.makeTempSaveURL(),
            now: now ?? { Date() }
        )
    }

    private static func makeTempSaveURL() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SproutHolidayTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("budget-data.json")
    }

    private static var gregorian: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York") ?? .current
        return calendar
    }

    private static func makeDate(_ year: Int, _ month: Int, _ day: Int) -> Date {
        gregorian.date(from: DateComponents(year: year, month: month, day: day, hour: 12)) ?? Date()
    }

    /// `on` defaults to the store's own clock, not the wall clock. Hard-coding
    /// `Date()` here meant every gift in a clock-controlled test was dated
    /// today regardless of the season it belonged to, so no test exercised gift
    /// dates under a controlled clock at all.
    @discardableResult
    private func addGift(
        _ store: BudgetStore,
        _ name: String,
        _ dollars: Double,
        for recipientID: UUID? = nil,
        on date: Date? = nil,
        isReturn: Bool = false
    ) -> Bool {
        var draft = store.makeHolidayPurchaseDraft(for: recipientID, isReturn: isReturn)
        draft.name = name
        draft.amountText = SproutMoneyText.editable(MoneyAmount(dollars: dollars))
        if let date { draft.date = date }
        return store.addHolidayPurchase(draft: draft)
    }

    @discardableResult
    private func addReturn(
        _ store: BudgetStore,
        _ name: String,
        _ dollars: Double,
        for recipientID: UUID? = nil
    ) -> Bool {
        addGift(store, name, dollars, for: recipientID, isReturn: true)
    }

    private func addPerson(
        _ store: BudgetStore,
        _ name: String,
        planned: Double? = nil
    ) -> GiftRecipient {
        var draft = GiftRecipientDraft()
        draft.name = name
        if let planned {
            draft.plannedAmountText = SproutMoneyText.editable(MoneyAmount(dollars: planned))
        }
        return store.addHolidayRecipient(draft: draft)!
    }

    // MARK: - Separation from the monthly budget

    @Test func holidayGiftsNeverTouchTheMonthlyBudgets() {
        let store = makeStore()
        let personalBefore = store.remaining(for: .personal)
        let groceryBefore = store.remaining(for: .grocery)

        let mom = addPerson(store, "Mom")
        addGift(store, "Sweater", 80, for: mom.id)
        addGift(store, "Wrapping paper", 12)

        #expect(store.holidaySpent == MoneyAmount(dollars: 92))
        #expect(store.remaining(for: .personal) == personalBefore)
        #expect(store.remaining(for: .grocery) == groceryBefore)
        #expect(store.netSpent(for: .personal) == .zero)
        #expect(store.netSpent(for: .grocery) == .zero)
        // Not in the monthly ledger at all, which is what makes the exclusion
        // structural rather than a filter every caller has to remember.
        #expect(store.snapshot.transactions.isEmpty)
        #expect(store.transactions(for: .personal).isEmpty)
        #expect(store.transactions(for: .grocery).isEmpty)
    }

    @Test func monthlySpendingNeverTouchesTheHolidayBudget() {
        let store = makeStore()
        store.setHolidayBudget(MoneyAmount(dollars: 600))

        var draft = store.makeDraft(for: .personal, mode: .expense)
        draft.name = "Coffee"
        draft.amountText = "4.75"
        #expect(store.addTransaction(mode: .expense, draft: draft, tab: .personal))

        #expect(store.holidaySpent == .zero)
        #expect(store.holidayRemaining == MoneyAmount(dollars: 600))
        #expect(store.holidayPurchaseCount == 0)
    }

    @Test func closingOutAMonthLeavesHolidaySpendingAlone() {
        let clock = TestClock(Self.makeDate(2026, 11, 20))
        let store = makeStore(calendar: Self.gregorian, now: { clock.date })
        store.setHolidayBudget(MoneyAmount(dollars: 500))
        let dad = addPerson(store, "Dad", planned: 150)
        addGift(store, "Headphones", 120, for: dad.id, on: Self.makeDate(2026, 11, 18))

        // Every rollover path, including the one that walks a multi-month gap.
        store.resetMonth(carryOverRemainders: true)
        clock.date = Self.makeDate(2027, 2, 3)
        store.refreshForCurrentDate()
        store.resetMonth(carryOverRemainders: false)
        store.keepCurrentTransactions()

        #expect(store.holidayBudget == MoneyAmount(dollars: 500))
        #expect(store.holidaySpent == MoneyAmount(dollars: 120))
        #expect(store.holidayPurchaseCount == 1)
        #expect(store.holidayRecipients.count == 1)
        #expect(store.holidaySpent(for: dad.id) == MoneyAmount(dollars: 120))
    }

    /// The strong form: a month carrying real transactions *and* a season
    /// carrying gifts, closed out, with both sides checked against what they
    /// would have been on their own.
    @Test func aMonthWithBothKindsOfSpendingClosesOutWithNeitherAffectingTheOther() {
        let clock = TestClock(Self.makeDate(2026, 11, 20))

        func makeMonthlySpending(_ store: BudgetStore) {
            for (name, amount) in [("Coffee", 4.75), ("Lunch", 18.40)] {
                var draft = store.makeDraft(for: .personal, mode: .expense)
                draft.name = name
                draft.amountText = SproutMoneyText.editable(MoneyAmount(dollars: amount))
                draft.date = Self.makeDate(2026, 11, 18)
                #expect(store.addTransaction(mode: .expense, draft: draft, tab: .personal))
            }
        }

        // Control: the same month, same transactions, no holiday data at all.
        let control = makeStore(calendar: Self.gregorian, now: { clock.date })
        makeMonthlySpending(control)
        control.resetMonth(carryOverRemainders: true)

        let withHoliday = makeStore(calendar: Self.gregorian, now: { clock.date })
        makeMonthlySpending(withHoliday)
        withHoliday.setHolidayBudget(MoneyAmount(dollars: 500))
        let dad = addPerson(withHoliday, "Dad", planned: 150)
        addGift(withHoliday, "Headphones", 120, for: dad.id, on: Self.makeDate(2026, 11, 18))
        addReturn(withHoliday, "Headphones returned", 20, for: dad.id)
        withHoliday.resetMonth(carryOverRemainders: true)

        // Monthly side: identical to the control, down to the cent.
        #expect(withHoliday.carryover(for: .personal) == control.carryover(for: .personal))
        #expect(withHoliday.carryover(for: .grocery) == control.carryover(for: .grocery))
        #expect(withHoliday.archivedMonths.count == control.archivedMonths.count)
        for (lhs, rhs) in zip(withHoliday.archivedMonths, control.archivedMonths) {
            #expect(lhs.monthKey == rhs.monthKey)
            #expect(lhs.transactions.count == rhs.transactions.count)
            #expect(lhs.netSpent(for: .personal) == rhs.netSpent(for: .personal))
            #expect(lhs.remaining(for: .personal) == rhs.remaining(for: .personal))
            // No gift was copied into the archived month's ledger.
            #expect(lhs.transactions.allSatisfy { $0.name != "Headphones" })
        }

        // Holiday side: untouched by the close-out, returns netted.
        #expect(withHoliday.holidayBudget == MoneyAmount(dollars: 500))
        #expect(withHoliday.holidaySpent == MoneyAmount(dollars: 100))
        #expect(withHoliday.holidayPurchaseCount == 2)
        #expect(withHoliday.holidayGiftCount == 1)
        #expect(withHoliday.holidayReturnCount == 1)
        #expect(withHoliday.holidaySpent(for: dad.id) == MoneyAmount(dollars: 100))
    }

    @Test func aHolidayBudgetIsNotAddedToEitherMonthlyBudget() {
        let store = makeStore()
        store.setHolidayBudget(MoneyAmount(dollars: 1_000))

        #expect(store.budget(for: .personal) == MoneyAmount(dollars: 200))
        #expect(store.budget(for: .grocery) == MoneyAmount(dollars: 400))
        #expect(store.remaining(for: .personal) == MoneyAmount(dollars: 200))
    }

    // MARK: - Budget math

    @Test func aFreshSeasonHasNoBudgetRatherThanAZeroOne() {
        let store = makeStore()
        #expect(store.holidayBudget == .zero)
        #expect(store.holidayHasBudget == false)
        // No budget and no spending is an untouched bar, not a full one.
        #expect(store.holidayProgress() == 0)
    }

    @Test func spendingWithNoBudgetReadsAsFullyConsumed() {
        let store = makeStore()
        addGift(store, "Candle", 15)
        // Matches `progress(for:)`: an empty mint bar under an over-budget
        // headline is the state this avoids.
        #expect(store.holidayProgress() == 1)
    }

    @Test func remainingAndProgressTrackTheBudget() {
        let store = makeStore()
        store.setHolidayBudget(MoneyAmount(dollars: 400))
        addGift(store, "Boots", 150)
        addGift(store, "Book", 25.50)

        #expect(store.holidaySpent == MoneyAmount(dollars: 175.50))
        #expect(store.holidayRemaining == MoneyAmount(dollars: 224.50))
        #expect(abs(store.holidayProgress() - 0.43875) < 0.0001)
    }

    @Test func overspendingIsVisibleAndTheBarStaysClamped() {
        let store = makeStore()
        store.setHolidayBudget(MoneyAmount(dollars: 100))
        addGift(store, "Watch", 260)

        #expect(store.holidayRemaining == MoneyAmount(dollars: -160))
        #expect(store.holidayProgress() == 1)
    }

    @Test func centsStayExactAcrossManyGifts() {
        let store = makeStore()
        store.setHolidayBudget(MoneyAmount(dollars: 100))
        for _ in 0..<10 {
            addGift(store, "Ornament", 0.07)
        }
        // Repeated Double-dollar addition is exactly what integer cents exists
        // to prevent.
        #expect(store.holidaySpent.cents == 70)
        #expect(store.holidayRemaining.cents == 9_930)
    }

    @Test func setHolidayBudgetRejectsNegativeAmounts() {
        let store = makeStore()
        store.setHolidayBudget(MoneyAmount(dollars: 300))
        store.setHolidayBudget(MoneyAmount(cents: -1))
        #expect(store.holidayBudget == MoneyAmount(dollars: 300))
    }

    @Test func zeroClearsTheBudgetBackToUnset() {
        let store = makeStore()
        store.setHolidayBudget(MoneyAmount(dollars: 300))
        store.setHolidayBudget(.zero)
        #expect(store.holidayHasBudget == false)
    }

    // MARK: - People

    @Test func perPersonTotalsAddUpToTheSeasonTotal() {
        let store = makeStore()
        let mom = addPerson(store, "Mom")
        let dad = addPerson(store, "Dad")

        addGift(store, "Scarf", 40, for: mom.id)
        addGift(store, "Mug", 18, for: mom.id)
        addGift(store, "Socks", 12, for: dad.id)
        addGift(store, "Gift bags", 9)

        #expect(store.holidaySpent(for: mom.id) == MoneyAmount(dollars: 58))
        #expect(store.holidaySpent(for: dad.id) == MoneyAmount(dollars: 12))
        #expect(store.holidaySpent(for: nil) == MoneyAmount(dollars: 9))

        let sumOfParts = store.holidayRecipients.reduce(MoneyAmount.zero) {
            $0 + store.holidaySpent(for: $1.id)
        } + store.holidaySpent(for: nil)
        #expect(sumOfParts == store.holidaySpent)
    }

    @Test func noPersonCanBeLostToACacheThatOutlivesAnEdit() {
        let store = makeStore()
        let mom = addPerson(store, "Mom")
        addGift(store, "Scarf", 40, for: mom.id)
        #expect(store.holidaySpent(for: mom.id) == MoneyAmount(dollars: 40))

        addGift(store, "Mug", 18, for: mom.id)
        // Read again immediately: a cache not dropped on mutation answers 40.
        #expect(store.holidaySpent(for: mom.id) == MoneyAmount(dollars: 58))

        // Newest first, so this removes the mug.
        store.removeHolidayPurchase(store.holidayPurchases(for: mom.id)[0])
        #expect(store.holidaySpent(for: mom.id) == MoneyAmount(dollars: 40))
        #expect(store.holidaySpent == MoneyAmount(dollars: 40))
    }

    @Test func aPlannedTargetOfNothingIsNotTheSameAsNoTarget() throws {
        let store = makeStore()
        store.setHolidayBudget(MoneyAmount(dollars: 500))

        let untargeted = addPerson(store, "Mom")
        #expect(untargeted.plannedAmount == nil)
        #expect(store.holidayPlannedTotal == .zero)
        #expect(store.holidayProgress(forRecipient: untargeted) == nil)

        var zeroDraft = GiftRecipientDraft()
        zeroDraft.name = "Neighbour"
        zeroDraft.plannedAmountText = "0"
        let zeroTarget = try #require(store.addHolidayRecipient(draft: zeroDraft))
        #expect(zeroTarget.plannedAmount == .zero)
        // A target of zero makes the bar meaningful; having none does not, so it
        // must not render as a full bar.
        #expect(store.holidayProgress(forRecipient: zeroTarget) == 0)
        // The discriminator: `plannedTotal` is zero for both shapes, so only
        // this can tell "has a target of nothing" from "has no target".
        #expect(store.holidayHasPerPersonTargets)
        #expect(untargeted.plannedAmount == nil)
        #expect(zeroTarget.plannedAmount == .zero)
    }

    @Test func unreservedBudgetCountsOnlyRealTargets() {
        let store = makeStore()
        store.setHolidayBudget(MoneyAmount(dollars: 600))
        let mom = addPerson(store, "Mom", planned: 200)
        _ = addPerson(store, "Dad", planned: 150)
        _ = addPerson(store, "Sam")

        #expect(store.holidayPlannedTotal == MoneyAmount(dollars: 350))
        #expect(store.holidayUnreserved == MoneyAmount(dollars: 250))

        // Spending into a target does not free up money: the target shrinks by
        // what was spent, so the unreserved figure holds.
        addGift(store, "Scarf", 100, for: mom.id)
        #expect(store.holidayUnreserved == MoneyAmount(dollars: 250))

        // Spending that nobody planned for does eat into it.
        addGift(store, "Wrapping paper", 60)
        #expect(store.holidayUnreserved == MoneyAmount(dollars: 190))
    }

    @Test func overshootingATargetReservesNothingFurther() {
        let store = makeStore()
        store.setHolidayBudget(MoneyAmount(dollars: 500))
        let mom = addPerson(store, "Mom", planned: 100)
        addGift(store, "Watch", 260, for: mom.id)

        // Mom's target is spent past, so none of it is still held back.
        #expect(store.holidaySeason.remainingTargets == .zero)
        #expect(store.holidayUnreserved == MoneyAmount(dollars: 240))
    }

    /// The card showed "Left to plan $200" forty points below "OVER BUDGET
    /// $120", because the old figure was `budget - targets` and never looked at
    /// spending. Two numbers a reader takes as "money I can still commit" is
    /// the same bug the monthly summary card had to be fixed for.
    @Test func thePlanningFigureCanNeverOutClaimWhatIsAvailable() {
        let store = makeStore()
        store.setHolidayBudget(MoneyAmount(dollars: 500))
        let mom = addPerson(store, "Mom", planned: 150)
        _ = addPerson(store, "Dad", planned: 100)
        _ = addPerson(store, "Sam", planned: 50)

        // Walk from untouched, through partly spent, to well over budget.
        for amount in [0.0, 80.0, 200.0, 240.0, 100.0] where amount > 0 {
            addGift(store, "Gift", amount, for: mom.id)
            #expect(store.holidayUnreserved <= store.holidayRemaining)
        }

        #expect(store.holidaySpent == MoneyAmount(dollars: 620))
        #expect(store.holidayRemaining == MoneyAmount(dollars: -120))
        #expect(store.holidayUnreserved <= store.holidayRemaining)
    }

    /// `plannedTotal > .zero` reported "no targets" for a list where every
    /// target was deliberately set to zero.
    @Test func aListOfZeroTargetsStillCountsAsHavingTargets() {
        let store = makeStore()
        store.setHolidayBudget(MoneyAmount(dollars: 500))
        #expect(store.holidayHasPerPersonTargets == false)

        _ = addPerson(store, "Mom")
        #expect(store.holidayHasPerPersonTargets == false)

        var draft = GiftRecipientDraft()
        draft.name = "Neighbour"
        draft.plannedAmountText = "0"
        _ = store.addHolidayRecipient(draft: draft)
        #expect(store.holidayPlannedTotal == .zero)
        #expect(store.holidayHasPerPersonTargets)
    }

    @Test func removingAPersonRemovesExactlyTheMoneyTheWarningNamed() {
        let store = makeStore()
        store.setHolidayBudget(MoneyAmount(dollars: 500))
        let mom = addPerson(store, "Mom")
        let dad = addPerson(store, "Dad")
        addGift(store, "Scarf", 40, for: mom.id)
        addGift(store, "Mug", 18, for: mom.id)
        addGift(store, "Socks", 12, for: dad.id)

        // The confirmation quotes this figure, so it has to be what leaves.
        let quoted = store.holidaySpent(for: mom.id)
        let totalBefore = store.holidaySpent
        store.removeHolidayRecipient(mom)

        #expect(store.holidaySpent == totalBefore - quoted)
        #expect(store.holidayRecipients.count == 1)
        #expect(store.holidayPurchaseCount == 1)
        // And nothing was left behind as an orphan.
        #expect(store.holidayUnassignedPurchaseCount == 0)
    }

    @Test func renamingAPersonKeepsTheirGifts() {
        let store = makeStore()
        let mom = addPerson(store, "Mom")
        addGift(store, "Scarf", 40, for: mom.id)

        var draft = GiftRecipientDraft(recipient: mom)
        draft.name = "Mum"
        draft.plannedAmountText = "250"
        #expect(store.updateHolidayRecipient(mom, with: draft))

        #expect(store.holidayRecipients.first?.name == "Mum")
        #expect(store.holidayRecipients.first?.plannedAmount == MoneyAmount(dollars: 250))
        #expect(store.holidaySpent(for: mom.id) == MoneyAmount(dollars: 40))
    }

    @Test func clearingAPersonsTargetPutsThemBackToNoTarget() {
        let store = makeStore()
        let mom = addPerson(store, "Mom", planned: 200)
        var draft = GiftRecipientDraft(recipient: mom)
        draft.plannedAmountText = "   "
        #expect(store.updateHolidayRecipient(mom, with: draft))
        #expect(store.holidayRecipients.first?.plannedAmount == nil)
    }

    @Test func aBlankOrUnparseablePersonIsRefusedRatherThanStored() {
        let store = makeStore()
        var blank = GiftRecipientDraft()
        blank.name = "   "
        #expect(store.addHolidayRecipient(draft: blank) == nil)

        var badTarget = GiftRecipientDraft()
        badTarget.name = "Mom"
        badTarget.plannedAmountText = "not a number"
        #expect(store.addHolidayRecipient(draft: badTarget) == nil)
        #expect(store.holidayRecipients.isEmpty)
    }

    @Test func thePersonLimitIsEnforcedAndReported() {
        let store = makeStore()
        for index in 0..<HolidaySeason.recipientLimit {
            var draft = GiftRecipientDraft()
            draft.name = "Person \(index)"
            #expect(store.addHolidayRecipient(draft: draft) != nil)
        }
        #expect(store.canAddHolidayRecipient == false)

        var overflow = GiftRecipientDraft()
        overflow.name = "One too many"
        #expect(store.addHolidayRecipient(draft: overflow) == nil)
        #expect(store.holidayRecipients.count == HolidaySeason.recipientLimit)
    }

    // MARK: - Gifts

    @Test func aGiftNeedsANameAndAPositiveAmount() {
        let store = makeStore()

        var noName = store.makeHolidayPurchaseDraft()
        noName.amountText = "20"
        #expect(store.addHolidayPurchase(draft: noName) == false)

        var noAmount = store.makeHolidayPurchaseDraft()
        noAmount.name = "Mystery"
        #expect(store.addHolidayPurchase(draft: noAmount) == false)

        var zero = store.makeHolidayPurchaseDraft()
        zero.name = "Free sample"
        zero.amountText = "0"
        #expect(store.addHolidayPurchase(draft: zero) == false)

        #expect(store.holidayPurchaseCount == 0)
    }

    @Test func aGiftAmountSharesTheOneMoneyParser() {
        let store = makeStore()
        var tooLarge = store.makeHolidayPurchaseDraft()
        tooLarge.name = "Yacht"
        tooLarge.amountText = "1000000"
        #expect(store.addHolidayPurchase(draft: tooLarge) == false)
        #expect(SproutMoneyText.evaluate("1000000") == .exceedsMaximum)

        var atMaximum = store.makeHolidayPurchaseDraft()
        atMaximum.name = "Almost a yacht"
        atMaximum.amountText = SproutMoneyText.editable(SproutMoneyText.maximum)
        #expect(store.addHolidayPurchase(draft: atMaximum))
        #expect(store.holidaySpent == SproutMoneyText.maximum)
    }

    @Test func anEditedGiftRoundTripsThroughTheSameTextRepresentation() {
        let store = makeStore()
        let mom = addPerson(store, "Mom")
        addGift(store, "Scarf", 40.25, for: mom.id)
        let gift = store.holidayPurchases(for: mom.id)[0]

        let draft = store.makeHolidayEditDraft(for: gift)
        #expect(SproutMoneyText.parse(draft.amountText) == MoneyAmount(dollars: 40.25))
        #expect(draft.recipientID == mom.id)
        #expect(store.updateHolidayPurchase(gift, with: draft))
        #expect(store.holidaySpent == MoneyAmount(dollars: 40.25))
    }

    @Test func reassigningAGiftMovesTheMoneyAndNothingElse() {
        let store = makeStore()
        let mom = addPerson(store, "Mom")
        let dad = addPerson(store, "Dad")
        addGift(store, "Scarf", 40, for: mom.id)

        let gift = store.holidayPurchases(for: mom.id)[0]
        var draft = store.makeHolidayEditDraft(for: gift)
        draft.recipientID = dad.id
        #expect(store.updateHolidayPurchase(gift, with: draft))

        #expect(store.holidaySpent(for: mom.id) == .zero)
        #expect(store.holidaySpent(for: dad.id) == MoneyAmount(dollars: 40))
        #expect(store.holidaySpent == MoneyAmount(dollars: 40))
    }

    @Test func aGiftFiledAgainstSomeoneWhoIsNotThereBecomesUnassignedNotInvisible() {
        let store = makeStore()
        var draft = store.makeHolidayPurchaseDraft(for: UUID())
        draft.name = "Scarf"
        draft.amountText = "40"
        #expect(store.addHolidayPurchase(draft: draft))

        // Still counted, and reachable from the unassigned bucket — money that
        // is in the total but in no list is the failure this prevents.
        #expect(store.holidaySpent == MoneyAmount(dollars: 40))
        #expect(store.holidayUnassignedPurchaseCount == 1)
        #expect(store.holidayPurchases(for: nil).count == 1)
    }

    @Test func giftsAreListedNewestFirst() {
        let store = makeStore()
        addGift(store, "Oldest", 10, on: Self.makeDate(2026, 11, 1))
        addGift(store, "Newest", 20, on: Self.makeDate(2026, 12, 5))
        addGift(store, "Middle", 15, on: Self.makeDate(2026, 11, 20))

        #expect(store.holidayPurchasesNewestFirst.map(\.name) == ["Newest", "Middle", "Oldest"])
    }

    @Test func textIsTrimmedOnTheWayIn() {
        let store = makeStore()
        var draft = store.makeHolidayPurchaseDraft()
        draft.name = "  Scarf  "
        draft.note = "  from the market  "
        draft.amountText = "40"
        #expect(store.addHolidayPurchase(draft: draft))

        let gift = store.holidayPurchasesNewestFirst[0]
        #expect(gift.name == "Scarf")
        #expect(gift.note == "from the market")
    }

    // MARK: - Seasons

    @Test func startingANewSeasonArchivesTheOldOneAndClearsTheGifts() {
        let clock = TestClock(Self.makeDate(2026, 12, 28))
        let store = makeStore(calendar: Self.gregorian, now: { clock.date })
        store.setHolidayBudget(MoneyAmount(dollars: 600))
        let mom = addPerson(store, "Mom", planned: 200)
        addGift(store, "Scarf", 40, for: mom.id)

        clock.date = Self.makeDate(2027, 11, 2)
        store.startNewHolidaySeason(carryRecipients: true)

        #expect(store.holidaySeasonHistory.count == 1)
        let archived = store.holidaySeasonHistory[0]
        #expect(archived.label == "Holiday 2026")
        #expect(archived.spent == MoneyAmount(dollars: 40))
        #expect(archived.closedAt != nil)

        // The new season keeps the people and the budget, not the spending.
        #expect(store.holidaySeasonLabel == "Holiday 2027")
        #expect(store.holidayBudget == MoneyAmount(dollars: 600))
        #expect(store.holidaySpent == .zero)
        #expect(store.holidayRecipients.map(\.name) == ["Mom"])
        #expect(store.holidayRecipients.first?.plannedAmount == MoneyAmount(dollars: 200))
    }

    @Test func aNewSeasonCanStartWithoutCarryingThePeople() {
        let store = makeStore()
        _ = addPerson(store, "Mom")
        addGift(store, "Scarf", 40)
        store.startNewHolidaySeason(carryRecipients: false)

        #expect(store.holidayRecipients.isEmpty)
        #expect(store.holidayPurchaseCount == 0)
        #expect(store.holidaySeasonHistory[0].recipients.count == 1)
    }

    @Test func anUntouchedSeasonIsNotArchived() {
        let store = makeStore()
        #expect(store.canStartNewHolidaySeason == false)
        store.startNewHolidaySeason(carryRecipients: false)
        // Nothing to look back at, and archiving it would push a real season
        // out of the capped history.
        #expect(store.holidaySeasonHistory.isEmpty)
    }

    /// Disambiguation happens when a season is filed, not when one is opened.
    ///
    /// Deduping the new season's name meant the sheet promised "Holiday 2026"
    /// and the store handed back "Holiday 2026 (2)" — and silently rewrote a
    /// name the user had typed by hand. The season you are about to work in now
    /// keeps exactly the name that was asked for; the history still never holds
    /// two identical labels.
    @Test func seasonsClosedInTheSameYearStayDistinguishableInHistory() {
        let clock = TestClock(Self.makeDate(2026, 12, 1))
        let store = makeStore(calendar: Self.gregorian, now: { clock.date })
        #expect(store.holidaySeasonLabel == "Holiday 2026")

        addGift(store, "Scarf", 40)
        store.startNewHolidaySeason(carryRecipients: false)
        #expect(store.holidaySeasonHistory.map(\.label) == ["Holiday 2026"])
        #expect(store.holidaySeasonLabel == store.defaultNewHolidaySeasonLabel)
        #expect(store.holidaySeasonLabel == "Holiday 2026")

        addGift(store, "Mug", 15)
        store.startNewHolidaySeason(carryRecipients: false)
        #expect(store.holidaySeasonLabel == "Holiday 2026")
        #expect(store.holidaySeasonHistory.map(\.label) == ["Holiday 2026 (2)", "Holiday 2026"])
        #expect(Set(store.holidaySeasonHistory.map(\.label)).count == store.holidaySeasonHistory.count)
    }

    @Test func renamingTheSeasonOntoAnArchivedNameStillLeavesHistoryUnique() {
        let clock = TestClock(Self.makeDate(2026, 12, 1))
        let store = makeStore(calendar: Self.gregorian, now: { clock.date })
        addGift(store, "Scarf", 40)
        store.startNewHolidaySeason(label: "Gifts", carryRecipients: false)

        addGift(store, "Mug", 15)
        #expect(store.renameHolidaySeason("Holiday 2026"))
        // Accepted as typed while it is the live season.
        #expect(store.holidaySeasonLabel == "Holiday 2026")

        store.startNewHolidaySeason(carryRecipients: false)
        #expect(Set(store.holidaySeasonHistory.map(\.label)).count == store.holidaySeasonHistory.count)
    }

    @Test func aCustomSeasonNameIsKeptAndABlankOneFallsBack() {
        let clock = TestClock(Self.makeDate(2026, 12, 1))
        let store = makeStore(calendar: Self.gregorian, now: { clock.date })
        addGift(store, "Scarf", 40)
        store.startNewHolidaySeason(label: "  Christmas with the Kanes  ", carryRecipients: false)
        #expect(store.holidaySeasonLabel == "Christmas with the Kanes")

        #expect(store.renameHolidaySeason("   ") == false)
        #expect(store.holidaySeasonLabel == "Christmas with the Kanes")
        #expect(store.renameHolidaySeason("  Gifts 2026 "))
        #expect(store.holidaySeasonLabel == "Gifts 2026")
    }

    @Test func seasonHistoryIsCappedAndKeepsTheMostRecent() {
        // Starts a year before the first close so the opening season's default
        // label never collides with the first new one.
        let clock = TestClock(Self.makeDate(2019, 12, 1))
        let store = makeStore(calendar: Self.gregorian, now: { clock.date })
        let lastYear = 2020 + BudgetStore.holidaySeasonHistoryLimit + 1

        for year in 2020...lastYear {
            clock.date = Self.makeDate(year, 12, 1)
            addGift(store, "Gift \(year)", 10)
            store.startNewHolidaySeason(carryRecipients: false)
        }

        let labels = store.holidaySeasonHistory.map(\.label)
        #expect(labels.count == BudgetStore.holidaySeasonHistoryLimit)
        #expect(labels.first == "Holiday \(lastYear - 1)")
        #expect(labels.contains("Holiday 2019") == false)
        #expect(store.holidaySeasonLabel == "Holiday \(lastYear)")
    }

    @Test func anArchivedSeasonCanBeDeleted() {
        let store = makeStore()
        store.setHolidayBudget(MoneyAmount(dollars: 300))
        _ = addPerson(store, "Mom")
        addGift(store, "Scarf", 40)
        store.startNewHolidaySeason(carryRecipients: true)
        addGift(store, "Mug", 15)
        let archived = store.holidaySeasonHistory[0]
        let activeLabel = store.holidaySeasonLabel

        store.removeArchivedHolidaySeason(archived)
        #expect(store.holidaySeasonHistory.isEmpty)
        // The active season is untouched — asserted on things that were not
        // already zero before the delete.
        #expect(store.holidaySeasonLabel == activeLabel)
        #expect(store.holidayBudget == MoneyAmount(dollars: 300))
        #expect(store.holidaySpent == MoneyAmount(dollars: 15))
        #expect(store.holidayRecipients.map(\.name) == ["Mom"])
    }

    // MARK: - Persistence

    @Test func holidayDataSurvivesAReload() throws {
        let saveURL = Self.makeTempSaveURL()
        let first = BudgetStore(calendar: .current, saveURL: saveURL)
        first.setHolidayBudget(MoneyAmount(dollars: 750))
        _ = first.renameHolidaySeason("Gifts 2026")
        let mom = addPerson(first, "Mom", planned: 300)
        addGift(first, "Scarf", 40.25, for: mom.id)
        addGift(first, "Gift bags", 7, for: nil)

        let second = BudgetStore(calendar: .current, saveURL: saveURL)
        #expect(second.holidaySeasonLabel == "Gifts 2026")
        #expect(second.holidayBudget == MoneyAmount(dollars: 750))
        #expect(second.holidaySpent == MoneyAmount(dollars: 47.25))
        #expect(second.holidayRecipients.map(\.name) == ["Mom"])
        #expect(second.holidayRecipients.first?.plannedAmount == MoneyAmount(dollars: 300))
        #expect(second.holidaySpent(for: mom.id) == MoneyAmount(dollars: 40.25))
        #expect(second.holidayUnassignedPurchaseCount == 1)
        #expect(second.persistenceAlert == nil)
    }

    @Test func aBackupCarriesHolidayDataBothWays() throws {
        let source = makeStore()
        source.setHolidayBudget(MoneyAmount(dollars: 400))
        let mom = addPerson(source, "Mom", planned: 150)
        addGift(source, "Scarf", 40, for: mom.id)
        addGift(source, "Mug", 15)
        source.startNewHolidaySeason(carryRecipients: true)
        addGift(source, "Next year's first gift", 20)

        let data = try source.exportBackupData()
        let destination = makeStore()
        try destination.importBackupData(data)

        #expect(destination.holidayBudget == MoneyAmount(dollars: 400))
        #expect(destination.holidaySpent == MoneyAmount(dollars: 20))
        #expect(destination.holidaySeasonHistory.count == 1)
        #expect(destination.holidaySeasonHistory[0].spent == MoneyAmount(dollars: 55))
        #expect(destination.holidayRecipients.map(\.name) == ["Mom"])
    }

    /// The confirmation prompt has to describe what the import replaces. It
    /// quietly said nothing about holiday data while replacing all of it.
    @Test func theImportSummaryDescribesHolidayPeopleAndSeasonsToo() throws {
        let source = makeStore()
        let mom = addPerson(source, "Mom")
        addGift(source, "Scarf", 40, for: mom.id)
        addGift(source, "Mug", 15)
        source.startNewHolidaySeason(carryRecipients: true)
        addGift(source, "Next year", 20)
        let data = try source.exportBackupData()

        let destination = makeStore()
        let summary = try #require(destination.backupSummary(for: data))
        #expect(summary.contains("1 holiday gift"))
        #expect(summary.contains("1 person"))
        #expect(summary.contains("1 past season"))
    }

    /// "0 holiday gifts" could not tell a pre-Holiday backup apart from a
    /// season that is set up but not yet shopped — on the one screen where the
    /// user decides whether to overwrite everything they have.
    @Test func theImportSummarySaysWhenAFileHasNoHolidayDataAtAll() throws {
        let store = makeStore()
        let payload: [String: Any] = [
            "schemaVersion": 2,
            "currentMonth": SproutDate.currentMonthKey(),
            "transactions": [],
            "personalBudget": 20_000,
            "groceryBudget": 40_000
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        #expect(BudgetStore.containsHolidayData(data) == false)
        let summary = try #require(store.backupSummary(for: data))
        #expect(summary.contains("no holiday data"))
        #expect(summary.contains("0 holiday gift") == false)
    }

    /// The Replace prompt listed budgets, transactions, recurring items,
    /// categories and months — and then also took the season, every person and
    /// every gift without naming them.
    @Test func theReplaceWarningNamesWhatTheImportWouldDestroy() {
        let store = makeStore()
        #expect(store.holidayReplacementWarning == nil)

        let mom = addPerson(store, "Mom")
        addGift(store, "Scarf", 40, for: mom.id)
        store.startNewHolidaySeason(carryRecipients: true)
        addGift(store, "Mug", 15)

        let warning = store.holidayReplacementWarning ?? ""
        #expect(warning.contains("1 gift"))
        #expect(warning.contains("1 person"))
        #expect(warning.contains("1 past season"))
    }

    @Test func aPreHolidayBackupImportsAsAnEmptySeasonNotAsDamage() throws {
        let store = makeStore()
        // A v2 file written before this feature existed: no holiday keys at all.
        let payload: [String: Any] = [
            "schemaVersion": 2,
            "personalBudget": 20_000,
            "groceryBudget": 40_000,
            "personalCarryover": 0,
            "groceryCarryover": 0,
            "transactions": [],
            "recurringRules": [],
            "monthHistory": [],
            "currentMonth": SproutDate.currentMonthKey(),
            "personalCategories": [],
            "updatedAt": ISO8601DateFormatter().string(from: Date())
        ]
        try store.importBackupData(try JSONSerialization.data(withJSONObject: payload))

        #expect(store.holidayPurchaseCount == 0)
        #expect(store.holidayHasBudget == false)
        // A real label for the current year, not "Holiday 1" from a missing
        // start date, and not merely "some non-empty string".
        #expect(store.holidaySeasonLabel == store.defaultNewHolidaySeasonLabel)
        // Absent keys are an empty season, not a file that lost data.
        #expect(store.persistenceAlert == nil)
    }

    @Test func oneUnreadableGiftCostsThatGiftAndIsReported() throws {
        let store = makeStore()
        let payload: [String: Any] = [
            "schemaVersion": 2,
            "currentMonth": SproutDate.currentMonthKey(),
            "transactions": [],
            "holidaySeason": [
                "id": UUID().uuidString,
                "label": "Holiday 2026",
                "budget": 50_000,
                "startedAt": ISO8601DateFormatter().string(from: Date()),
                "recipients": [],
                "purchases": [
                    [
                        "id": UUID().uuidString,
                        "name": "Good gift",
                        "amount": 4_000,
                        "note": "",
                        "date": ISO8601DateFormatter().string(from: Date())
                    ],
                    // No amount: not a purchase, so this row alone is dropped.
                    [
                        "id": UUID().uuidString,
                        "name": "Broken gift",
                        "date": ISO8601DateFormatter().string(from: Date())
                    ]
                ]
            ]
        ]
        try store.importBackupData(try JSONSerialization.data(withJSONObject: payload))

        #expect(store.holidayPurchaseCount == 1)
        #expect(store.holidaySpent == MoneyAmount(dollars: 40))
        let alert = try #require(store.persistenceAlert)
        #expect(alert.message.contains("1 holiday gift"))
    }

    @Test func anUnreadablePersonListStillKeepsTheMoneyVisible() throws {
        let store = makeStore()
        let momID = UUID().uuidString
        let payload: [String: Any] = [
            "schemaVersion": 2,
            "currentMonth": SproutDate.currentMonthKey(),
            "transactions": [],
            "holidaySeason": [
                "id": UUID().uuidString,
                "label": "Holiday 2026",
                "budget": 50_000,
                "startedAt": ISO8601DateFormatter().string(from: Date()),
                // Structurally wrong: an object where an array belongs.
                "recipients": ["nope": true],
                "purchases": [
                    [
                        "id": UUID().uuidString,
                        "recipientID": momID,
                        "name": "Scarf",
                        "amount": 4_000,
                        "note": "",
                        "date": ISO8601DateFormatter().string(from: Date())
                    ]
                ]
            ]
        ]
        try store.importBackupData(try JSONSerialization.data(withJSONObject: payload))

        #expect(store.holidayRecipients.isEmpty)
        // Losing the people must not lose the money with them.
        #expect(store.holidaySpent == MoneyAmount(dollars: 40))
        #expect(store.holidayUnassignedPurchaseCount == 1)
        let alert = try #require(store.persistenceAlert)
        #expect(alert.message.contains("people on your holiday list"))
    }

    /// Falling back to an empty season without saying so is how a whole holiday
    /// list disappears behind a "Backup Imported" success message.
    @Test func aStructurallyBrokenSeasonIsReportedRatherThanSilentlyEmptied() throws {
        let store = makeStore()
        let payload: [String: Any] = [
            "schemaVersion": 2,
            "currentMonth": SproutDate.currentMonthKey(),
            "transactions": [],
            // Present, not null, and not an object.
            "holidaySeason": "wiped"
        ]
        try store.importBackupData(try JSONSerialization.data(withJSONObject: payload))

        #expect(store.holidayPurchaseCount == 0)
        let alert = try #require(store.persistenceAlert)
        #expect(alert.message.contains("current holiday season"))
    }

    @Test func anAbsentSeasonKeyIsNotTreatedAsDamage() throws {
        let store = makeStore()
        let payload: [String: Any] = [
            "schemaVersion": 2,
            "currentMonth": SproutDate.currentMonthKey(),
            "transactions": [],
            "holidaySeason": NSNull()
        ]
        try store.importBackupData(try JSONSerialization.data(withJSONObject: payload))

        #expect(store.holidayPurchaseCount == 0)
        #expect(store.persistenceAlert == nil)
    }

    @Test func duplicateIdsAndBlankNamesAreNormalizedRatherThanDropped() throws {
        let store = makeStore()
        let sharedID = UUID().uuidString
        let payload: [String: Any] = [
            "schemaVersion": 2,
            "currentMonth": SproutDate.currentMonthKey(),
            "transactions": [],
            "holidaySeason": [
                "id": UUID().uuidString,
                "label": "   ",
                "budget": -500,
                "startedAt": ISO8601DateFormatter().string(from: Date()),
                "recipients": [
                    ["id": sharedID, "name": "   ", "emoji": ""],
                    ["id": sharedID, "name": "Duplicate", "emoji": "🎄"]
                ],
                "purchases": [
                    [
                        "id": UUID().uuidString,
                        "recipientID": sharedID,
                        "name": "  ",
                        "amount": 1_000,
                        "date": ISO8601DateFormatter().string(from: Date())
                    ]
                ]
            ]
        ]
        try store.importBackupData(try JSONSerialization.data(withJSONObject: payload))

        // Both people survive. They share an id but are different rows, so
        // dropping the second would delete someone; it is re-identified
        // instead. The old behaviour dropped it with nothing recorded, and the
        // test that covered this path asserted the drop.
        #expect(store.holidayRecipients.count == 2)
        #expect(store.holidayRecipients.map(\.name).sorted() == ["Duplicate", "Someone"])
        #expect(Set(store.holidayRecipients.map(\.id)).count == 2)
        #expect(store.holidaySeasonLabel == store.defaultNewHolidaySeasonLabel)
        #expect(store.holidayHasBudget == false)

        let renamed = try #require(store.holidayRecipients.first { $0.name == "Someone" })
        #expect(renamed.emoji == GiftRecipient.defaultEmoji)
        // The gift keeps the id it referenced, which stayed with the first row.
        #expect(store.holidayPurchaseCount == 1)
        #expect(store.holidayPurchasesNewestFirst[0].name == "Gift")
        #expect(store.holidaySpent == MoneyAmount(dollars: 10))
        #expect(store.holidaySpent(for: renamed.id) == MoneyAmount(dollars: 10))
    }

    /// The other half of the same rule: an identical row repeated is a merge
    /// artifact, and collapsing it loses nothing.
    @Test func anIdenticalRepeatedRowIsCollapsedRatherThanCountedTwice() throws {
        let store = makeStore()
        let sharedID = UUID().uuidString
        let personID = UUID().uuidString
        let date = ISO8601DateFormatter().string(from: Date())
        let gift: [String: Any] = [
            "id": sharedID, "recipientID": personID, "name": "Scarf",
            "amount": 4_000, "note": "", "date": date
        ]
        let payload: [String: Any] = [
            "schemaVersion": 2,
            "currentMonth": SproutDate.currentMonthKey(),
            "transactions": [],
            "holidaySeason": [
                "id": UUID().uuidString, "label": "Holiday 2026", "budget": 50_000,
                "startedAt": date,
                "recipients": [["id": personID, "name": "Mom", "emoji": "🎁"]],
                "purchases": [gift, gift]
            ]
        ]
        try store.importBackupData(try JSONSerialization.data(withJSONObject: payload))

        #expect(store.holidayPurchaseCount == 1)
        #expect(store.holidaySpent == MoneyAmount(dollars: 40))
    }

    @Test func editingAPersonDoesNotDeleteThemMidEdit() {
        let store = makeStore()
        let mom = addPerson(store, "Mom")
        addGift(store, "Scarf", 40, for: mom.id)

        // Normalization runs on every save, so a half-typed name must be
        // refused by the store rather than normalized into the stored row.
        var blanked = GiftRecipientDraft(recipient: mom)
        blanked.name = ""
        #expect(store.updateHolidayRecipient(mom, with: blanked) == false)
        #expect(store.holidayRecipients.map(\.name) == ["Mom"])
        #expect(store.holidaySpent(for: mom.id) == MoneyAmount(dollars: 40))
    }

    // MARK: - Returns

    @Test func aReturnComesBackOffTheSeasonTotal() {
        let store = makeStore()
        store.setHolidayBudget(MoneyAmount(dollars: 400))
        let mom = addPerson(store, "Mom", planned: 150)
        addGift(store, "Sweater", 90, for: mom.id)
        addReturn(store, "Sweater returned", 90, for: mom.id)

        #expect(store.holidaySpent == .zero)
        #expect(store.holidayRemaining == MoneyAmount(dollars: 400))
        #expect(store.holidaySpent(for: mom.id) == .zero)
        // Both rows are kept: deleting the gift would lose the record of what
        // was bought, and editing it down would lose that money moved twice.
        #expect(store.holidayPurchaseCount == 2)
        #expect(store.holidayGiftCount == 1)
        #expect(store.holidayReturnCount == 1)
    }

    @Test func aPartialCreditLeavesTheOriginalGiftIntact() {
        let store = makeStore()
        let mom = addPerson(store, "Mom")
        addGift(store, "Coat", 90, for: mom.id)
        addReturn(store, "Price match credit", 15, for: mom.id)

        #expect(store.holidaySpent == MoneyAmount(dollars: 75))
        let gifts = store.holidayPurchases(for: mom.id)
        #expect(gifts.count == 2)
        // The $90 the receipt shows is still findable.
        #expect(gifts.contains { $0.name == "Coat" && $0.amount == MoneyAmount(dollars: 90) })
    }

    @Test func aReturnDoesNotCountAsAGiftInCopyOrTallies() {
        let store = makeStore()
        let mom = addPerson(store, "Mom")
        addGift(store, "Sweater", 90, for: mom.id)
        addGift(store, "Book", 20, for: mom.id)
        addReturn(store, "Sweater returned", 90, for: mom.id)

        let tally = store.holidayTally(for: mom.id)
        #expect(tally.gifts == 2)
        #expect(tally.returns == 1)
        #expect(tally.rows == 3)
        #expect(tally.spent == MoneyAmount(dollars: 20))
    }

    /// A bucket holding only a return would hide from the dashboard while its
    /// money stayed in the season total — counted but invisible.
    @Test func aBucketHoldingOnlyAReturnIsStillVisible() {
        let store = makeStore()
        addReturn(store, "Gift card refund", 25)

        #expect(store.holidaySpent == MoneyAmount(dollars: -25))
        #expect(store.holidayUnassignedPurchaseCount == 1)
        #expect(store.holidayTally(for: nil).isEmpty == false)
        #expect(store.holidayPurchases(for: nil).count == 1)
    }

    @Test func returningMoreThanWasSpentCannotReserveMoreThanTheTarget() {
        let store = makeStore()
        store.setHolidayBudget(MoneyAmount(dollars: 500))
        let mom = addPerson(store, "Mom", planned: 100)
        addReturn(store, "Over-refund", 300, for: mom.id)

        #expect(store.holidaySpent(for: mom.id) == MoneyAmount(dollars: -300))
        // Clamped at the target: a refund must not reserve more than Mom was
        // ever allotted.
        #expect(store.holidaySeason.remainingTargets == MoneyAmount(dollars: 100))
        #expect(store.holidayUnreserved <= store.holidayRemaining)
    }

    @Test func aReturnSurvivesABackupRoundTrip() throws {
        let source = makeStore()
        let mom = addPerson(source, "Mom")
        addGift(source, "Sweater", 90, for: mom.id)
        addReturn(source, "Sweater returned", 40, for: mom.id)

        let destination = makeStore()
        try destination.importBackupData(try source.exportBackupData())

        #expect(destination.holidaySpent == MoneyAmount(dollars: 50))
        #expect(destination.holidayReturnCount == 1)
        #expect(destination.holidayGiftCount == 1)
    }

    @Test func anEditCanTurnAGiftIntoAReturnAndBack() {
        let store = makeStore()
        let mom = addPerson(store, "Mom")
        addGift(store, "Sweater", 90, for: mom.id)
        let gift = store.holidayPurchases(for: mom.id)[0]

        var draft = store.makeHolidayEditDraft(for: gift)
        #expect(draft.isReturn == false)
        draft.isReturn = true
        #expect(store.updateHolidayPurchase(gift, with: draft))
        #expect(store.holidaySpent == MoneyAmount(dollars: -90))

        var back = store.makeHolidayEditDraft(for: store.holidayPurchases(for: mom.id)[0])
        #expect(back.isReturn)
        back.isReturn = false
        #expect(store.updateHolidayPurchase(store.holidayPurchases(for: mom.id)[0], with: back))
        #expect(store.holidaySpent == MoneyAmount(dollars: 90))
    }

    // MARK: - Recovery

    /// History is sorted by `closedAt` and then trimmed to the cap, so a stored
    /// season closed on a device whose clock ran ahead sorted the season being
    /// filed right now to the bottom — where the cap dropped it on the spot,
    /// under a "New season started" toast.
    @Test func aSeasonClosedUnderABackwardsClockIsNotEvictedOnTheSpot() throws {
        let clock = TestClock(Self.makeDate(2030, 12, 1))
        let store = makeStore(calendar: Self.gregorian, now: { clock.date })

        // Fill history to the cap with seasons closed in the future.
        for index in 0..<BudgetStore.holidaySeasonHistoryLimit {
            clock.date = Self.makeDate(2030 + index, 12, 1)
            addGift(store, "Future gift \(index)", 10)
            store.startNewHolidaySeason(carryRecipients: false)
        }
        #expect(store.holidaySeasonHistory.count == BudgetStore.holidaySeasonHistoryLimit)

        // Now the clock goes back, as it does on a restored device before it
        // syncs, and the user closes a season holding real money.
        clock.date = Self.makeDate(2026, 12, 20)
        _ = store.renameHolidaySeason("The one that matters")
        addGift(store, "Expensive gift", 800)
        store.startNewHolidaySeason(carryRecipients: false)

        let archived = try #require(store.holidaySeasonHistory.first)
        #expect(archived.label == "The one that matters")
        #expect(archived.spent == MoneyAmount(dollars: 800))
        #expect(store.holidaySeasonHistory.count == BudgetStore.holidaySeasonHistoryLimit)
    }

    /// Holiday money has only ever been written as integer cents. A file whose
    /// `schemaVersion` cannot be read as an Int was treated as v1 dollars,
    /// which multiplied every gift by 100 and then wrote the inflated figures
    /// back as cents on the next save.
    @Test func holidayMoneyIsNeverReadAsV1Dollars() throws {
        func payload(version: Any?) -> [String: Any] {
            var dictionary: [String: Any] = [
                "currentMonth": SproutDate.currentMonthKey(),
                "transactions": [],
                "holidaySeason": [
                    "id": UUID().uuidString, "label": "Holiday 2026", "budget": 50_000,
                    "startedAt": ISO8601DateFormatter().string(from: Date()),
                    "recipients": [],
                    "purchases": [[
                        "id": UUID().uuidString, "name": "Scarf", "amount": 4_000,
                        "note": "", "date": ISO8601DateFormatter().string(from: Date())
                    ]]
                ]
            ]
            if let version { dictionary["schemaVersion"] = version }
            return dictionary
        }

        // Version absent entirely, and version quoted as a string.
        let versions: [Any?] = [nil, "2"]
        for version in versions {
            let store = makeStore()
            let data = try JSONSerialization.data(withJSONObject: payload(version: version))
            try store.importBackupData(data)
            #expect(store.holidaySpent == MoneyAmount(dollars: 40))
            #expect(store.holidayBudget == MoneyAmount(dollars: 500))
        }
    }

    /// `.zero` is overloaded to mean "no budget set yet", so a budget that is
    /// present but unreadable silently invited the user to set one they had
    /// already chosen.
    @Test func anUnreadableHolidayBudgetIsReportedRatherThanReadAsUnset() throws {
        let store = makeStore()
        let payload: [String: Any] = [
            "schemaVersion": 2,
            "currentMonth": SproutDate.currentMonthKey(),
            "transactions": [],
            "holidaySeason": [
                "id": UUID().uuidString, "label": "Holiday 2026",
                "budget": "six hundred",
                "startedAt": ISO8601DateFormatter().string(from: Date()),
                "recipients": [], "purchases": []
            ]
        ]
        try store.importBackupData(try JSONSerialization.data(withJSONObject: payload))

        #expect(store.holidayHasBudget == false)
        let alert = try #require(store.persistenceAlert)
        #expect(alert.message.contains("holiday budget"))
    }

    /// Undo is the only recovery path for a holiday import gone wrong, and
    /// nothing covered it.
    @Test func undoImportRestoresHolidayData() throws {
        let saveURL = Self.makeTempSaveURL()
        let store = BudgetStore(calendar: .current, saveURL: saveURL)
        store.setHolidayBudget(MoneyAmount(dollars: 750))
        let mom = addPerson(store, "Mom", planned: 300)
        addGift(store, "Scarf", 40, for: mom.id)
        addReturn(store, "Scarf returned", 10, for: mom.id)

        let other = makeStore()
        addGift(other, "Someone else's gift", 5)
        try store.importBackupData(try other.exportBackupData())
        #expect(store.holidaySpent == MoneyAmount(dollars: 5))
        #expect(store.canUndoImport)

        try store.undoImport()
        #expect(store.holidayBudget == MoneyAmount(dollars: 750))
        #expect(store.holidaySpent == MoneyAmount(dollars: 30))
        #expect(store.holidayRecipients.map(\.name) == ["Mom"])
        #expect(store.holidayReturnCount == 1)
    }

    /// The prompt quotes `holidayTally(for:)`, so what the user is told they
    /// are losing has to be exactly what leaves the total — returns included.
    @Test func removingAPersonWithReturnsRemovesTheNetFigureQuoted() {
        let store = makeStore()
        store.setHolidayBudget(MoneyAmount(dollars: 500))
        let mom = addPerson(store, "Mom")
        let dad = addPerson(store, "Dad")
        addGift(store, "Sweater", 90, for: mom.id)
        addReturn(store, "Sweater returned", 40, for: mom.id)
        addGift(store, "Socks", 12, for: dad.id)

        let tally = store.holidayTally(for: mom.id)
        #expect(tally.gifts == 1)
        #expect(tally.returns == 1)
        #expect(tally.spent == MoneyAmount(dollars: 50))

        let totalBefore = store.holidaySpent
        store.removeHolidayRecipient(mom)
        #expect(store.holidaySpent == totalBefore - tally.spent)
        #expect(store.holidaySpent == MoneyAmount(dollars: 12))
        #expect(store.holidayUnassignedPurchaseCount == 0)
    }

    // MARK: - Timestamp compatibility

    /// `JSONDecoder.DateDecodingStrategy.iso8601` is `ISO8601DateFormatter`
    /// with `.withInternetDateTime` only — it refuses fractional seconds, and
    /// the refusal is silent here: a gift's date falls back to `.distantPast`,
    /// a person's `createdAt` likewise, and an archived `closedAt` to `nil`.
    /// JavaScript's `toISOString()` always emits three decimals, so a backup
    /// authored in the web app arrives in exactly that shape.
    @Test func holidayTimestampsDecodeWithOrWithoutFractionalSeconds() throws {
        for stamp in ["2026-11-02T12:00:00Z", "2026-11-02T12:00:00.000Z", "2026-11-02T12:00:00.456Z"] {
            let store = makeStore()
            let personID = UUID().uuidString
            let payload: [String: Any] = [
                "schemaVersion": 2,
                "currentMonth": SproutDate.currentMonthKey(),
                "transactions": [],
                "holidaySeason": [
                    "id": UUID().uuidString, "label": "Holiday 2026", "budget": 50_000,
                    "startedAt": stamp, "closedAt": NSNull(),
                    "recipients": [[
                        "id": personID, "name": "Mom", "emoji": "🎁", "createdAt": stamp
                    ]],
                    "purchases": [[
                        "id": UUID().uuidString, "recipientID": personID, "name": "Scarf",
                        "amount": 4_000, "note": "", "date": stamp
                    ]]
                ]
            ]
            try store.importBackupData(try JSONSerialization.data(withJSONObject: payload))

            let gift = try #require(store.holidayPurchasesNewestFirst.first, stamp)
            // Survived rather than collapsing to year 1 AD.
            #expect(gift.date > Self.makeDate(2026, 11, 1), "\(stamp)")
            #expect(gift.date < Self.makeDate(2026, 11, 3), "\(stamp)")
            let person = try #require(store.holidayRecipients.first, stamp)
            #expect(person.createdAt > Self.makeDate(2026, 11, 1), "\(stamp)")
            #expect(store.holidaySpent == MoneyAmount(dollars: 40), "\(stamp)")
            #expect(store.persistenceAlert == nil, "\(stamp)")
        }
    }

    /// The widened strategy applies to the whole file, so the monthly ledger
    /// gains the same tolerance.
    @Test func aMonthlyTransactionWithFractionalSecondsDecodes() throws {
        let store = makeStore()
        let payload: [String: Any] = [
            "schemaVersion": 2,
            "currentMonth": "2026-11",
            "transactions": [[
                "id": UUID().uuidString, "name": "Coffee", "amount": 475,
                "emoji": "☕️", "date": "2026-11-02T12:00:00.000Z",
                "tab": "personal", "isRefund": false
            ]],
            "personalBudget": 20_000, "groceryBudget": 40_000
        ]
        try store.importBackupData(try JSONSerialization.data(withJSONObject: payload))

        #expect(store.netSpent(for: .personal) == MoneyAmount(dollars: 4.75))
        let entry = try #require(store.transactions(for: .personal).first)
        #expect(entry.date > Self.makeDate(2026, 11, 1))
        #expect(store.persistenceAlert == nil)
    }

    /// Widening must not mean accepting anything: a date that is not a
    /// timestamp still fails its row, which the lossy decode then reports.
    @Test func anUnreadableDateStillCostsItsRowAndIsReported() throws {
        let store = makeStore()
        let payload: [String: Any] = [
            "schemaVersion": 2,
            "currentMonth": "2026-11",
            "transactions": [[
                "id": UUID().uuidString, "name": "Coffee", "amount": 475,
                "emoji": "☕️", "date": "not a date", "tab": "personal", "isRefund": false
            ]],
            "personalBudget": 20_000
        ]
        try store.importBackupData(try JSONSerialization.data(withJSONObject: payload))

        #expect(store.transactions(for: .personal).isEmpty)
        let alert = try #require(store.persistenceAlert)
        #expect(alert.message.contains("transaction"))
    }

    /// What Sprout writes is unchanged: whole seconds, which is what the web
    /// app's importer and every older build expect.
    @Test func exportedTimestampsCarryNoFractionalSeconds() throws {
        let store = makeStore()
        let mom = addPerson(store, "Mom")
        addGift(store, "Scarf", 40, for: mom.id)
        let text = try #require(String(data: try store.exportBackupData(), encoding: .utf8))

        #expect(text.contains("holidaySeason"))
        // No "…:SS.mmmZ" anywhere in the payload.
        #expect(text.range(of: #":\d{2}\.\d+Z"#, options: .regularExpression) == nil)
    }

    /// A person whose stamp was absent sorted ahead of everyone forever,
    /// because `.distantPast` is year 1 AD. The web app treats such a person as
    /// having joined when the season did; both surfaces now agree.
    @Test func aPersonWithNoCreatedStampJoinsWhenTheSeasonDid() throws {
        let store = makeStore()
        let payload: [String: Any] = [
            "schemaVersion": 2,
            "currentMonth": SproutDate.currentMonthKey(),
            "transactions": [],
            "holidaySeason": [
                "id": UUID().uuidString, "label": "Holiday 2026", "budget": 50_000,
                "startedAt": "2026-11-01T12:00:00Z",
                "recipients": [["id": UUID().uuidString, "name": "Mom", "emoji": "🎁"]],
                "purchases": []
            ]
        ]
        try store.importBackupData(try JSONSerialization.data(withJSONObject: payload))

        let person = try #require(store.holidayRecipients.first)
        #expect(person.createdAt > Self.makeDate(2026, 10, 31))
        #expect(person.createdAt < Self.makeDate(2026, 11, 2))
    }

    // MARK: - Routing

    @Test func aHolidayQuickAddLinkDoesNotLandInThePersonalBudget() throws {
        let holiday = try #require(QuickEntryRoute(url: URL(string: "sprout://quick-add?tab=holiday")!))
        #expect(holiday.section == .holiday)

        let personal = try #require(QuickEntryRoute(url: URL(string: "sprout://quick-add?tab=personal&mode=payment")!))
        #expect(personal.section == .personal)
        #expect(personal.mode == .payment)

        let unknown = try #require(QuickEntryRoute(url: URL(string: "sprout://quick-add?tab=nonsense")!))
        #expect(unknown.section == .personal)
    }

    @Test func aPendingRequestWrittenByAnOlderBuildStillRoutes() throws {
        let suiteName = "sprout.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let legacy: [String: Any] = [
            "id": UUID().uuidString,
            "tab": "grocery",
            "mode": "payment",
            "createdAt": ISO8601DateFormatter().string(from: Date())
        ]
        defaults.set(try JSONSerialization.data(withJSONObject: legacy), forKey: QuickEntryRequestStore.key)

        let request = try #require(QuickEntryRequestStore.consume(defaults: defaults))
        #expect(request.section == .grocery)
        #expect(request.mode == .payment)
    }

    @Test func aHolidayRequestRoundTripsThroughStorage() throws {
        let suiteName = "sprout.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let request = QuickEntryRequest(section: .holiday)
        QuickEntryRequestStore.save(request, defaults: defaults)
        let consumed = try #require(QuickEntryRequestStore.consume(defaults: defaults))
        #expect(consumed.section == .holiday)
    }

    @Test func theActiveTabBridgeNeverReportsHolidayAsABudgetTab() {
        let store = makeStore()
        store.activeSection = .holiday
        #expect(store.activeSection.budgetTab == nil)
        // Code that only understands two budget tabs gets a safe answer rather
        // than a third case it has no meaning for.
        #expect(store.activeTab == .personal)

        store.activeTab = .grocery
        #expect(store.activeSection == .grocery)
    }
}
