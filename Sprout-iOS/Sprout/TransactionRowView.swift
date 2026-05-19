import SwiftUI

struct TransactionRowView: View {
    let entry: TransactionEntry
    let onRemove: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(entry.isRefund ? "💸" : entry.emoji)
                .font(.title3)
                .frame(width: 42, height: 42)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.sproutCardSoft)
                )

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(entry.name)
                        .font(.body.weight(.medium))
                        .foregroundStyle(Color.sproutText)

                    Spacer()

                    Text("\(entry.isRefund ? "+" : "−")\(SproutFormatters.currency(entry.amount))")
                        .font(.system(.subheadline, design: .monospaced, weight: .semibold))
                        .foregroundStyle(entry.isRefund ? Color.sageDark : Color.sproutText)
                }

                HStack(spacing: 6) {
                    Text(SproutDate.shortDate(entry.date))
                    if entry.isRefund {
                        Text("payment")
                            .foregroundStyle(Color.sageDark)
                    }
                    if !entry.note.isEmpty {
                        Text(entry.note)
                    }
                }
                .font(.footnote)
                .foregroundStyle(Color.sproutTextMuted)
            }

            Button(action: onRemove) {
                Image(systemName: "trash")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.sproutTextMuted)
                    .padding(8)
                    .background(Circle().fill(Color.sproutCardSoft))
            }
                .buttonStyle(.plain)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.sproutCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.sproutBorder, lineWidth: 1)
        )
    }
}
