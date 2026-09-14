import SwiftUI

struct TransactionRowView: View {
    let entry: TransactionEntry
    let onEdit: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(entry.isRefund ? "💸" : entry.emoji)
                .font(.title3)
                .frame(width: 40, height: 40)
                .background(Color.sproutCardSoft, in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(entry.name)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.sproutText)
                    .lineLimit(1)

                HStack(spacing: 5) {
                    Text(SproutDate.shortDate(entry.date))
                    if entry.isRefund {
                        Text("payment")
                            .foregroundStyle(Color.sageDark)
                    }
                    if !entry.note.isEmpty {
                        Text("·")
                        Text(entry.note)
                            .lineLimit(1)
                    }
                }
                .font(.footnote)
                .foregroundStyle(Color.sproutTextMuted)
            }

            Spacer(minLength: 10)

            Text("\(entry.isRefund ? "+" : "−")\(SproutFormatters.currency(entry.amount))")
                .font(.system(.subheadline, design: .rounded, weight: .bold))
                .foregroundStyle(entry.isRefund ? Color.sageDark : Color.sproutText)

            Menu {
                Button("Edit transaction", systemImage: "pencil") {
                    onEdit()
                }
                Button("Remove transaction", systemImage: "trash", role: .destructive) {
                    onRemove()
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.sproutTextMuted)
                    // 44pt is the minimum comfortable touch target; 32 was below it.
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(entry.name), \(entry.isRefund ? "payment" : "expense"), \(SproutFormatters.currency(entry.amount))")
        .accessibilityHint("Shows options to edit or remove")
    }
}
