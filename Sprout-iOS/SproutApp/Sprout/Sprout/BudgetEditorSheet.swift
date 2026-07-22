import SwiftUI

struct BudgetEditorSheet: View {
    @Environment(\.dismiss) private var dismiss

    let tab: BudgetTab
    let carryover: MoneyAmount
    let onSave: (MoneyAmount) -> Void

    @FocusState private var isAmountFocused: Bool
    @State private var amountText: String

    init(tab: BudgetTab, startingAmount: MoneyAmount, carryover: MoneyAmount = .zero, onSave: @escaping (MoneyAmount) -> Void) {
        self.tab = tab
        self.carryover = carryover
        self.onSave = onSave
        let dollars = startingAmount.dollars
        let text = dollars.truncatingRemainder(dividingBy: 1) == 0
            ? String(Int(dollars))
            : String(format: "%.2f", dollars)
        _amountText = State(initialValue: text)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Label(tab.title, systemImage: tab == .grocery ? "cart.fill" : "person.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(tab.accentDarkColor)

                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(Locale.current.currencySymbol ?? "$")
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.sproutTextSecondary)

                    TextField("0", text: $amountText)
                        .keyboardType(.decimalPad)
                        .font(.system(size: 54, weight: .bold, design: .rounded))
                        .multilineTextAlignment(.center)
                        .focused($isAmountFocused)
                        .minimumScaleFactor(0.65)
                }

                VStack(spacing: 6) {
                    Text("Set the total amount available for this month.")
                        .font(.footnote)
                        .foregroundStyle(Color.sproutTextMuted)
                        .multilineTextAlignment(.center)

                    if carryover > .zero {
                        Label(
                            "\(SproutFormatters.currency(carryover)) is carried over from last month",
                            systemImage: "arrow.turn.down.right"
                        )
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.sageDark)
                    }
                }
            }
            .padding(24)
            .frame(maxHeight: .infinity, alignment: .top)
            .background(Color.sproutBackground.ignoresSafeArea())
            .navigationTitle("Monthly budget")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                    }
                    .disabled(parsedAmount == nil)
                }
            }
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
            .onAppear {
                isAmountFocused = true
            }
        }
    }

    private var parsedAmount: MoneyAmount? {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = .current
        let dollars: Double
        if let value = formatter.number(from: amountText)?.doubleValue {
            dollars = value
        } else {
            let sanitized = amountText.replacingOccurrences(of: ",", with: "")
            guard let value = Double(sanitized) else { return nil }
            dollars = value
        }
        guard dollars > 0, dollars <= TransactionDraft.maximumAmount.dollars else { return nil }
        return MoneyAmount(dollars: dollars)
    }

    private func save() {
        guard let amount = parsedAmount else { return }
        onSave(amount)
        dismiss()
    }
}
