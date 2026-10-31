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

    @discardableResult
    private func addGift(
        _ store: BudgetStore,
        _ name: String,
        _ dollars: Double,
        for recipientID: UUID? = nil,
        on date: Date = Date()
    ) -> Bool {
        var draft = store.makeHolidayPurchaseDraft(for: recipientID)
        draft.name = name
        draft.amountText = SproutMoneyText.editable(MoneyAmount(dollars: dollars))
        draft.date = date
        return store.addHolidayPurchase(draft: draft)
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
        // And no archived month absorbed the gift.
        for month in store.archivedMonths {
            #expect(month.transactions.isEmpty)
        }
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
        #expect(store.holidayPlannedTotal == .zero)
    }

    @Test func unallocatedBudgetCountsOnlyRealTargets() {
        let store = makeStore()
        store.setHolidayBudget(MoneyAmount(dollars: 600))
        _ = addPerson(store, "Mom", planned: 200)
        _ = addPerson(store, "Dad", planned: 150)
        _ = addPerson(store, "Sam")

        #expect(store.holidayPlannedTotal == MoneyAmount(dollars: 350))
        #expect(store.holidayUnallocated == MoneyAmount(dollars: 250))
    }

    @Test func overPlanningIsReportedAsNegativeUnallocated() {
        let store = makeStore()
        store.setHolidayBudget(MoneyAmount(dollars: 100))
        _ = addPerson(store, "Mom", planned: 200)
        #expect(store.holidayUnallocated == MoneyAmount(dollars: -100))
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

    @Test func twoSeasonsInOneYearGetDistinguishableNames() {
        let clock = TestClock(Self.makeDate(2026, 12, 1))
        let store = makeStore(calendar: Self.gregorian, now: { clock.date })
        #expect(store.holidaySeasonLabel == "Holiday 2026")

        addGift(store, "Scarf", 40)
        store.startNewHolidaySeason(carryRecipients: false)
        #expect(store.holidaySeasonHistory.map(\.label) == ["Holiday 2026"])
        // Two "Holiday 2026" rows would make the history list unreadable.
        #expect(store.holidaySeasonLabel == "Holiday 2026 (2)")

        addGift(store, "Mug", 15)
        store.startNewHolidaySeason(carryRecipients: false)
        #expect(store.holidaySeasonLabel == "Holiday 2026 (3)")
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
        addGift(store, "Scarf", 40)
        store.startNewHolidaySeason(carryRecipients: false)
        let archived = store.holidaySeasonHistory[0]

        store.removeArchivedHolidaySeason(archived)
        #expect(store.holidaySeasonHistory.isEmpty)
        // And the active season is untouched.
        #expect(store.holidayPurchaseCount == 0)
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
    @Test func theImportSummaryMentionsHolidayGifts() throws {
        let source = makeStore()
        addGift(source, "Scarf", 40)
        addGift(source, "Mug", 15)
        let data = try source.exportBackupData()

        let destination = makeStore()
        let summary = try #require(destination.backupSummary(for: data))
        #expect(summary.contains("2 holiday gifts"))
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
        #expect(store.holidaySeasonLabel.isEmpty == false)
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

        // One person, renamed rather than deleted; the duplicate id is dropped.
        #expect(store.holidayRecipients.count == 1)
        #expect(store.holidayRecipients[0].name == "Someone")
        #expect(store.holidayRecipients[0].emoji == GiftRecipient.defaultEmoji)
        #expect(store.holidaySeasonLabel.isEmpty == false)
        #expect(store.holidayHasBudget == false)
        #expect(store.holidayPurchaseCount == 1)
        #expect(store.holidayPurchasesNewestFirst[0].name == "Gift")
        #expect(store.holidaySpent == MoneyAmount(dollars: 10))
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
