import SwiftUI

struct BudgetEditorSheet: View {
    @Environment(\.dismiss) private var dismiss

    let navigationTitle: String
    let scopeTitle: String
    let scopeSymbol: String
    let accent: Color
    let explanation: String
    let amountAccessibilityLabel: String
    /// Only the monthly budgets have carryover; the holiday budget has none, and
    /// the footnote that explains the arithmetic is hidden rather than shown with
    /// a figure that does not apply.
    let carryover: MoneyAmount
    let onSave: (MoneyAmount) -> Void

    @FocusState private var isAmountFocused: Bool
    @ScaledMetric(relativeTo: .largeTitle) private var amountFontSize: CGFloat = 54
    @ScaledMetric(relativeTo: .title2) private var currencySymbolFontSize: CGFloat = 28
    @State private var amountText: String

    init(
        navigationTitle: String,
        scopeTitle: String,
        scopeSymbol: String,
        accent: Color,
        explanation: String,
        amountAccessibilityLabel: String,
        startingAmount: MoneyAmount,
        carryover: MoneyAmount = .zero,
        onSave: @escaping (MoneyAmount) -> Void
    ) {
        self.navigationTitle = navigationTitle
        self.scopeTitle = scopeTitle
        self.scopeSymbol = scopeSymbol
        self.accent = accent
        self.explanation = explanation
        self.amountAccessibilityLabel = amountAccessibilityLabel
        self.carryover = carryover
        self.onSave = onSave
        _amountText = State(initialValue: SproutMoneyText.editableWhole(startingAmount))
    }

    /// A monthly budget tab.
    init(tab: BudgetTab, startingAmount: MoneyAmount, carryover: MoneyAmount = .zero, onSave: @escaping (MoneyAmount) -> Void) {
        self.init(
            navigationTitle: "Monthly budget",
            scopeTitle: tab.title,
            scopeSymbol: tab == .grocery ? "cart.fill" : "person.fill",
            accent: tab.accentDarkColor,
            explanation: "Your budget for every month. Any leftover carried over is added on top of it.",
            amountAccessibilityLabel: "Monthly budget amount",
            startingAmount: startingAmount,
            carryover: carryover,
            onSave: onSave
        )
    }

    /// The holiday budget, which is its own pot: no months, no carryover, and
    /// deliberately not part of either monthly budget.
    static func holiday(
        seasonLabel: String,
        startingAmount: MoneyAmount,
        onSave: @escaping (MoneyAmount) -> Void
    ) -> BudgetEditorSheet {
        BudgetEditorSheet(
            navigationTitle: "Holiday budget",
            scopeTitle: seasonLabel,
            scopeSymbol: "gift.fill",
            accent: .sproutBerryDark,
            explanation: "What you plan to spend on gifts this season. It is kept entirely separate from your Personal and Grocery budgets. Set it to 0 to clear it.",
            amountAccessibilityLabel: "Holiday budget amount",
            startingAmount: startingAmount,
            carryover: .zero,
            onSave: onSave
        )
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Label(scopeTitle, systemImage: scopeSymbol)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(accent)
                    .multilineTextAlignment(.center)

                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(SproutFormatters.currencySymbol)
                        .font(.system(size: currencySymbolFontSize, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.sproutTextSecondary)

                    TextField("0", text: $amountText)
                        .accessibilityLabel(amountAccessibilityLabel)
                        .keyboardType(.decimalPad)
                        .font(.system(size: amountFontSize, weight: .bold, design: .rounded))
                        .multilineTextAlignment(.center)
                        .focused($isAmountFocused)
                        .minimumScaleFactor(0.65)
                }

                VStack(spacing: 6) {
                    Text(explanation)
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
                        // Spell the arithmetic out, so it is obvious the figure in
                        // the field is not the same as this month's spending power.
                        Label(
                            "Plus \(SproutFormatters.currency(carryover)) carried over — \(SproutFormatters.currency(availableThisMonth)) available this month",
                            systemImage: "arrow.turn.down.right"
                        )
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.sageDark)
                        .multilineTextAlignment(.center)
                    }
                }
            }
            .padding(24)
            .frame(maxHeight: .infinity, alignment: .top)
            .background(Color.sproutBackground.ignoresSafeArea())
            .navigationTitle(navigationTitle)
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

    /// What the user can actually spend: the budget in the field plus carryover.
    private var availableThisMonth: MoneyAmount {
        (parsedAmount ?? .zero) + carryover
    }

    /// Zero is the one amount the shared parser deliberately refuses, so it is
    /// recognised here instead — using the same normalization `evaluate` applies,
    /// rather than a second, weaker copy that choked on "$0" or a stray space.
    private var isExplicitZero: Bool {
        SproutMoneyText.isZeroAmount(amountText)
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
