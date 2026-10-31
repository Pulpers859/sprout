import SwiftUI

/// The Holiday tab: one budget, the people you're buying for, and every gift.
struct HolidayDashboardView: View {
    @EnvironmentObject private var store: BudgetStore
    @EnvironmentObject private var router: HolidayRouter

    let onOpenSettings: () -> Void

    @State private var searchText = ""

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 26) {
                SproutDashboardHeader(onOpenSettings: onOpenSettings) {
                    Button("Rename this season", systemImage: "pencil") {
                        router.present(.renameSeason)
                    }
                    Button("Start a new season", systemImage: "sparkles") {
                        router.present(.startNewSeason)
                    }
                    .disabled(!store.canStartNewHolidaySeason)
                    // Starting a season is the one action that creates archived
                    // data, and the only route to it was Settings -> History,
                    // which nothing on this screen mentioned.
                    Button("Record a return", systemImage: "arrow.uturn.backward") {
                        router.present(.addGift(recipient: .unspecified, isReturn: true))
                    }
                    Button("Past seasons", systemImage: "clock.arrow.circlepath") {
                        router.present(.seasonHistory)
                    }
                }

                SectionPickerView(selection: $store.activeSection)

                HolidaySummaryCardView {
                    router.present(.editBudget)
                }

                primaryActions

                peopleSection

                unassignedSection

                giftsSection
            }
            .padding(.horizontal, 18)
            .padding(.top, 8)
            .padding(.bottom, 40)
            // Matches the budget dashboard: an unconstrained single column
            // stretches these cards across an iPad's full width.
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .background(Color.sproutBackground.ignoresSafeArea())
    }

    private var primaryActions: some View {
        HStack(spacing: 12) {
            Button {
                router.present(.addGift(recipient: .unspecified, isReturn: false))
            } label: {
                Label("Add gift", systemImage: "plus")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.glassProminent)
            .tint(Color.sproutBerryDark)

            Button {
                router.present(.addPerson)
            } label: {
                Label("Add person", systemImage: "person.badge.plus")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.glass)
            .tint(Color.sproutBerry)
            .disabled(!store.canAddHolidayRecipient)
        }
    }

    @ViewBuilder
    private var peopleSection: some View {
        let recipients = store.holidayRecipients

        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("People", detail: "\(recipients.count)")
                .padding(.bottom, 8)

            // Gated on the people list alone. It used to also require zero
            // unassigned gifts, so logging one gift with nobody added flipped
            // the header to "People 0" above a single row and took away the
            // only instruction for adding people at the moment it was needed.
            if recipients.isEmpty {
                ContentUnavailableView(
                    "No one on the list yet",
                    systemImage: "person.2",
                    description: Text("Add the people you're buying for, then log each gift as you buy it.")
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 28)
            } else {
                ForEach(Array(recipients.enumerated()), id: \.element.id) { index, recipient in
                    NavigationLink(value: HolidayRecipientRoute(recipientID: recipient.id)) {
                        // Counts come from the cached tally. They used to come
                        // from `holidayPurchases(for:)`, a full filter-and-sort
                        // per person per render pass, which defeated the cache
                        // sitting right beside it.
                        let tally = store.holidayTally(for: recipient.id)

                        GiftRecipientRowView(
                            emoji: recipient.emoji,
                            name: recipient.name,
                            spent: tally.spent,
                            plannedAmount: recipient.plannedAmount,
                            giftCount: tally.gifts,
                            returnCount: tally.returns,
                            progress: store.holidayProgress(forRecipient: recipient)
                        )
                    }
                    .buttonStyle(.plain)
                    // The row navigates, so an inline menu button inside it
                    // would fight the tap. A context menu is the standard
                    // secondary affordance; the primary path is still the
                    // detail view's own menu.
                    .contextMenu {
                        Button("Edit person", systemImage: "pencil") {
                            router.present(.editPerson(recipient))
                        }
                        Button("Remove person", systemImage: "trash", role: .destructive) {
                            router.confirm(.removePerson(recipient))
                        }
                    }

                    if index < recipients.count - 1 {
                        Divider()
                            .padding(.leading, 54)
                    }
                }
            }
        }
    }

    /// Gifts that belong to nobody in particular, plus any whose person was
    /// removed. Either way the money is already in the season total, so it has
    /// to be reachable — and it is not a person, so it does not belong under a
    /// "People" count.
    @ViewBuilder
    private var unassignedSection: some View {
        let tally = store.holidayTally(for: nil)

        if !tally.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                sectionHeader("Not assigned to a person", detail: "\(tally.rows)")
                    .padding(.bottom, 8)

                NavigationLink(value: HolidayRecipientRoute(recipientID: nil)) {
                    GiftRecipientRowView(
                        emoji: "🎁",
                        name: "Not for one person",
                        spent: tally.spent,
                        plannedAmount: nil,
                        giftCount: tally.gifts,
                        returnCount: tally.returns,
                        progress: nil
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var giftsSection: some View {
        let all = store.holidayPurchasesNewestFirst
        // Same rule as the transactions list: the field only appears at five or
        // more rows, and the filter is inert whenever its control is off screen
        // — otherwise deleting down to four leaves "No gifts match" with no box
        // and no way to clear it.
        let isSearchable = all.count >= 5
        let query = isSearchable ? searchText : ""
        let gifts = query.isEmpty ? all : all.filter { matches($0, query: query) }

        VStack(alignment: .leading, spacing: 0) {
            sectionHeader(
                "All gifts",
                detail: query.isEmpty ? "\(all.count)" : "\(gifts.count) of \(all.count)"
            )
            .padding(.bottom, 8)

            if isSearchable {
                searchField
            }

            if all.isEmpty {
                ContentUnavailableView(
                    "No gifts logged yet",
                    systemImage: "gift",
                    description: Text("Every gift you add here counts against your holiday budget and nothing else.")
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 28)
            } else if gifts.isEmpty {
                Text("No gifts match \u{201C}\(query)\u{201D}")
                    .font(.subheadline)
                    .foregroundStyle(Color.sproutTextMuted)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            } else {
                ForEach(Array(gifts.enumerated()), id: \.element.id) { index, purchase in
                    let recipient = store.holidayRecipient(with: purchase.recipientID)

                    GiftPurchaseRowView(
                        purchase: purchase,
                        recipientName: recipient?.name ?? "Not for one person",
                        emoji: recipient?.emoji ?? "🎁",
                        onEdit: { router.present(.editGift(purchase)) },
                        onRemove: { router.confirm(.removeGift(purchase)) }
                    )

                    if index < gifts.count - 1 {
                        Divider()
                            .padding(.leading, 54)
                    }
                }
            }
        }
    }

    /// Searches the person's name too, which is the thing a holiday list is
    /// most likely to be scanned by.
    private func matches(_ purchase: GiftPurchase, query: String) -> Bool {
        if purchase.name.localizedCaseInsensitiveContains(query) { return true }
        if purchase.note.localizedCaseInsensitiveContains(query) { return true }
        let name = store.holidayRecipient(with: purchase.recipientID)?.name ?? "Not for one person"
        return name.localizedCaseInsensitiveContains(query)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Color.sproutTextMuted)
            TextField("Search gifts or people", text: $searchText)
                .font(.subheadline)
                .foregroundStyle(Color.sproutText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Color.sproutTextMuted)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.sproutCard, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.sproutBorder, lineWidth: 1))
        .padding(.bottom, 10)
    }

    private func sectionHeader(_ title: String, detail: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundStyle(Color.sproutText)

            Text(detail)
                .font(.footnote)
                .foregroundStyle(Color.sproutTextMuted)
        }
    }
}
