import SwiftUI

/// The Holiday tab: one budget, the people you're buying for, and every gift.
struct HolidayDashboardView: View {
    @EnvironmentObject private var store: BudgetStore
    @EnvironmentObject private var router: HolidayRouter

    let onOpenSettings: () -> Void

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
                router.present(.addGift(recipient: .unspecified))
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
                        GiftRecipientRowView(
                            emoji: recipient.emoji,
                            name: recipient.name,
                            spent: store.holidaySpent(for: recipient.id),
                            plannedAmount: recipient.plannedAmount,
                            giftCount: store.holidayPurchases(for: recipient.id).count,
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
        let unassignedCount = store.holidayUnassignedPurchaseCount

        if unassignedCount > 0 {
            VStack(alignment: .leading, spacing: 0) {
                sectionHeader("Not assigned to a person", detail: "\(unassignedCount)")
                    .padding(.bottom, 8)

                NavigationLink(value: HolidayRecipientRoute(recipientID: nil)) {
                    GiftRecipientRowView(
                        emoji: "🎁",
                        name: "Not for one person",
                        spent: store.holidaySpent(for: nil),
                        plannedAmount: nil,
                        giftCount: unassignedCount,
                        progress: nil
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var giftsSection: some View {
        let gifts = store.holidayPurchasesNewestFirst

        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("All gifts", detail: "\(gifts.count)")
                .padding(.bottom, 8)

            if gifts.isEmpty {
                ContentUnavailableView(
                    "No gifts logged yet",
                    systemImage: "gift",
                    description: Text("Every gift you add here counts against your holiday budget and nothing else.")
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 28)
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
