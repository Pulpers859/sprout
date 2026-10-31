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
                }

                SectionPickerView(selection: $store.activeSection)

                HolidaySummaryCardView {
                    router.present(.editBudget)
                }

                primaryActions

                peopleSection

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
                router.present(.addGift(recipientID: nil))
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
        let unassignedCount = store.holidayUnassignedPurchaseCount

        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("People", detail: "\(recipients.count)")
                .padding(.bottom, 8)

            if recipients.isEmpty && unassignedCount == 0 {
                ContentUnavailableView(
                    "No one on the list yet",
                    systemImage: "person.2",
                    description: Text("Add the people you're buying for, then log each gift as you buy it.")
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 28)
            } else {
                ForEach(Array(recipients.enumerated()), id: \.element.id) { index, recipient in
                    NavigationLink {
                        GiftRecipientDetailView(recipientID: recipient.id)
                    } label: {
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

                    if index < recipients.count - 1 || unassignedCount > 0 {
                        Divider()
                            .padding(.leading, 54)
                    }
                }

                // Gifts that belong to nobody in particular, plus any whose
                // person was removed. Either way the money is already in the
                // season total, so it has to be reachable from somewhere.
                if unassignedCount > 0 {
                    NavigationLink {
                        GiftRecipientDetailView(recipientID: nil)
                    } label: {
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
