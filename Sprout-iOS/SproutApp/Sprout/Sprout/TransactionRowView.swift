import SwiftUI

struct TransactionRowView: View {
    let entry: TransactionEntry
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
                Button(role: .destructive) {
                    onRemove()
                } label: {
                    Label("Remove transaction", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.sproutTextMuted)
                    .frame(width: 32, height: 32)
            }
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}
