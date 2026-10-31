import SwiftUI

/// Everything bought for one person, or the gifts that belong to nobody.
///
/// Takes an id rather than the value so a rename, a changed target, or a
/// deleted gift is reflected while the view is on screen instead of showing a
/// copy captured when it was pushed.
struct GiftRecipientDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: BudgetStore
    @EnvironmentObject private var router: HolidayRouter

    /// `nil` is the "not for one person" bucket.
    let recipientID: UUID?

    var body: some View {
        let recipient = store.holidayRecipient(with: recipientID)
        let gifts = store.holidayPurchases(for: recipientID)
        let spent = store.holidaySpent(for: recipientID)

        ScrollView {
            LazyVStack(alignment: .leading, spacing: 22) {
                summary(recipient: recipient, spent: spent, giftCount: gifts.count)

                Button {
                    // Pre-chosen, so this sheet does not ask again: the user
                    // reached it from a list that is already scoped to one
                    // person, or from the unassigned bucket.
                    router.present(.addGift(
                        recipient: recipientID.map { GiftRecipientSelection.person($0) } ?? .nobody
                    ))
                } label: {
                    Label(
                        recipient.map { "Add gift for \($0.name)" } ?? "Add gift",
                        systemImage: "plus"
                    )
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                }
                .buttonStyle(.glassProminent)
                .tint(Color.sproutBerryDark)

                giftList(gifts)
            }
            .padding(.horizontal, 18)
            .padding(.top, 8)
            .padding(.bottom, 40)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .background(Color.sproutBackground.ignoresSafeArea())
        .navigationTitle(recipient?.name ?? "Not for one person")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let recipient {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Edit person", systemImage: "pencil") {
                            router.present(.editPerson(recipient))
                        }
                        Button("Remove person", systemImage: "trash", role: .destructive) {
                            router.confirm(.removePerson(recipient))
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("Person options")
                }
            }
        }
        // The person can be removed from this very screen, which would
        // otherwise leave an empty detail view pushed on top of the list.
        .onChange(of: store.holidayRecipient(with: recipientID) == nil) { _, isGone in
            if isGone, recipientID != nil { dismiss() }
        }
    }

    private func summary(recipient: GiftRecipient?, spent: MoneyAmount, giftCount: Int) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Text(recipient?.emoji ?? "🎁")
                    .font(.title)
                    .frame(width: 52, height: 52)
                    .background(Color.white.opacity(0.18), in: Circle())

                VStack(alignment: .leading, spacing: 3) {
                    Text("SPENT")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.white.opacity(0.80))

                    Text(SproutFormatters.currency(spent))
                        .font(.system(.largeTitle, design: .rounded, weight: .bold))
                        .foregroundStyle(Color.white)
                        .contentTransition(.numericText())
                        .minimumScaleFactor(0.7)
                }

                Spacer()
            }

            if let recipient, let planned = recipient.plannedAmount {
                let remaining = planned - spent
                // Progress comes from the store, not a second local copy of the
                // same formula — two implementations of one figure are a drift
                // hazard by construction.
                let fraction = store.holidayProgress(forRecipient: recipient) ?? 0
                VStack(alignment: .leading, spacing: 6) {
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.white.opacity(0.16))
                            Capsule()
                                .fill(remaining < .zero ? Color.sproutRedBright : Color.sproutMint)
                                .frame(width: geometry.size.width * fraction)
                        }
                    }
                    .frame(height: 6)
                    .accessibilityElement()
                    .accessibilityLabel("\(recipient.name) progress")
                    .accessibilityValue("\(Int(fraction * 100)) percent of the planned amount spent")

                    Text(remaining < .zero
                         ? "\(SproutFormatters.currency(remaining.magnitude)) over the \(SproutFormatters.currency(planned)) planned"
                         : "\(SproutFormatters.currency(remaining)) left of the \(SproutFormatters.currency(planned)) planned")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.white.opacity(0.85))
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Text(giftCount == 0
                     ? "No gifts yet."
                     : "\(giftCount) gift\(giftCount == 1 ? "" : "s") · no per-person target set")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.white.opacity(0.85))
            }
        }
        .padding(20)
        .background(AppSection.holiday.heroGradient, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: Color.sproutBerryDark.opacity(0.2), radius: 16, x: 0, y: 8)
    }

    @ViewBuilder
    private func giftList(_ gifts: [GiftPurchase]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Gifts")
                    .font(.headline)
                    .foregroundStyle(Color.sproutText)
                Text("\(gifts.count)")
                    .font(.footnote)
                    .foregroundStyle(Color.sproutTextMuted)
            }
            .padding(.bottom, 8)

            if gifts.isEmpty {
                Text("Nothing logged here yet.")
                    .font(.subheadline)
                    .foregroundStyle(Color.sproutTextMuted)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            } else {
                ForEach(Array(gifts.enumerated()), id: \.element.id) { index, purchase in
                    GiftPurchaseRowView(
                        purchase: purchase,
                        // The heading already names who this list is for.
                        recipientName: nil,
                        emoji: store.holidayRecipient(with: purchase.recipientID)?.emoji ?? "🎁",
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
}
