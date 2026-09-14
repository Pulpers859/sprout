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
        _amountText = State(initialValue: SproutMoneyText.editableWhole(startingAmount))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Label(tab.title, systemImage: tab == .grocery ? "cart.fill" : "person.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(tab.accentDarkColor)

                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(SproutFormatters.currencySymbol)
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.sproutTextSecondary)

                    TextField("0", text: $amountText)
                        .accessibilityLabel("Monthly budget amount")
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

                    // Save is disabled for an unparseable amount; saying why beats
                    // an inert button with no explanation.
                    if let validationMessage {
                        Label(validationMessage, systemImage: "exclamationmark.circle.fill")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Color.sproutRed)
                            .multilineTextAlignment(.center)
                    }

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

    /// A budget of zero is a legitimate choice (pause a category for a month), so
    /// it is accepted here even though the shared parser rejects zero amounts for
    /// transactions.
    private var parsedAmount: MoneyAmount? {
        if amountText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return nil }
        if case .valid(let amount) = SproutMoneyText.evaluate(amountText) { return amount }
        if isExplicitZero { return .zero }
        return nil
    }

    private var isExplicitZero: Bool {
        let separator = Locale.current.decimalSeparator ?? "."
        let digits = amountText
            .replacingOccurrences(of: separator, with: "")
            .replacingOccurrences(of: Locale.current.groupingSeparator ?? ",", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return !digits.isEmpty && digits.allSatisfy { $0 == "0" }
    }

    private var validationMessage: String? {
        let trimmed = amountText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard parsedAmount == nil else { return nil }
        if case .exceedsMaximum = SproutMoneyText.evaluate(amountText) {
            return "Budget cannot exceed \(SproutFormatters.currency(SproutMoneyText.maximum))."
        }
        return "Enter a whole or decimal amount, like \(SproutMoneyText.editableWhole(MoneyAmount(dollars: 400)))."
    }

    private func save() {
        guard let amount = parsedAmount else { return }
        onSave(amount)
        dismiss()
    }
}
