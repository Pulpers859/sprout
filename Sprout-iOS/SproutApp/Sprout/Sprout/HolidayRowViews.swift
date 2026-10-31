import SwiftUI

/// One gift in a list. Mirrors `TransactionRowView` so the two tabs read the
/// same way, including the 44pt menu target.
struct GiftPurchaseRowView: View {
    let purchase: GiftPurchase
    /// The person's display name, or `nil` in a list that is already scoped to
    /// one person and would only repeat it on every row.
    let recipientName: String?
    let emoji: String
    let onEdit: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(emoji)
                .font(.title3)
                .frame(width: 40, height: 40)
                .background(Color.sproutCardSoft, in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(purchase.name)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.sproutText)
                    .lineLimit(1)

                HStack(spacing: 5) {
                    if let recipientName {
                        Text(recipientName)
                            .foregroundStyle(Color.sproutBerryText)
                            .lineLimit(1)
                        Text("·")
                    }
                    Text(SproutDate.shortDate(purchase.date))
                    if !purchase.note.isEmpty {
                        Text("·")
                        Text(purchase.note)
                            .lineLimit(1)
                    }
                }
                .font(.footnote)
                .foregroundStyle(Color.sproutTextMuted)
            }

            Spacer(minLength: 10)

            Text(SproutFormatters.currency(purchase.amount))
                .font(.system(.subheadline, design: .rounded, weight: .bold))
                .foregroundStyle(Color.sproutText)

            Menu {
                Button("Edit gift", systemImage: "pencil") {
                    onEdit()
                }
                Button("Remove gift", systemImage: "trash", role: .destructive) {
                    onRemove()
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.sproutTextMuted)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Shows options to edit or remove")
    }

    private var accessibilityLabel: String {
        let amount = SproutFormatters.currency(purchase.amount)
        guard let recipientName else { return "\(purchase.name), \(amount)" }
        return "\(purchase.name) for \(recipientName), \(amount)"
    }
}

/// One person in the holiday list, with their spend and — when they have a
/// target — how much of it is used.
struct GiftRecipientRowView: View {
    let emoji: String
    let name: String
    let spent: MoneyAmount
    let plannedAmount: MoneyAmount?
    let giftCount: Int
    /// `nil` when the person has no target, which is not the same as a target
    /// of zero and must not render as a full bar.
    let progress: Double?

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(emoji)
                .font(.title3)
                .frame(width: 40, height: 40)
                .background(Color.sproutCardSoft, in: Circle())

            VStack(alignment: .leading, spacing: 5) {
                Text(name)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.sproutText)
                    .lineLimit(1)

                // Never hard-clipped to one line: at accessibility sizes
                // "$50.00 over $100.00 planned" truncated mid-number, and a
                // truncated money figure is a wrong money figure.
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(isOverTarget ? Color.sproutRed : Color.sproutTextMuted)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .fixedSize(horizontal: false, vertical: true)

                if let progress {
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.sproutTrack)
                            Capsule()
                                .fill(isOverTarget ? Color.sproutRed : Color.sproutBerry)
                                .frame(width: geometry.size.width * progress)
                        }
                    }
                    .frame(height: 4)
                }
            }

            Spacer(minLength: 10)

            Text(SproutFormatters.currency(spent))
                .font(.system(.subheadline, design: .rounded, weight: .bold))
                .foregroundStyle(Color.sproutText)

            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.sproutTextMuted)
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(name), \(SproutFormatters.currency(spent)) spent, \(subtitle)")
    }

    private var isOverTarget: Bool {
        guard let plannedAmount else { return false }
        return spent > plannedAmount
    }

    private var subtitle: String {
        guard let plannedAmount else {
            return giftCount == 0 ? "No gifts yet" : "\(giftCount) gift\(giftCount == 1 ? "" : "s")"
        }
        if spent > plannedAmount {
            return "\(SproutFormatters.currency(spent - plannedAmount)) over \(SproutFormatters.currency(plannedAmount)) planned"
        }
        return "\(SproutFormatters.currency(plannedAmount - spent)) left of \(SproutFormatters.currency(plannedAmount))"
    }
}
