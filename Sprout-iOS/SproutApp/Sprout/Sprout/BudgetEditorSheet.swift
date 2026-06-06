import SwiftUI

struct BudgetEditorSheet: View {
    @Environment(\.dismiss) private var dismiss

    let tab: BudgetTab
    let onSave: (Double) -> Void

    @FocusState private var isAmountFocused: Bool
    @State private var amountText: String

    init(tab: BudgetTab, startingAmount: Double, onSave: @escaping (Double) -> Void) {
        self.tab = tab
        self.onSave = onSave
        let text = startingAmount.truncatingRemainder(dividingBy: 1) == 0
            ? String(Int(startingAmount))
            : String(format: "%.2f", startingAmount)
        _amountText = State(initialValue: text)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Label(tab.title, systemImage: tab == .grocery ? "cart.fill" : "person.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(tab.accentDarkColor)

                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("$")
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.sproutTextSecondary)

                    TextField("0", text: $amountText)
                        .keyboardType(.decimalPad)
                        .font(.system(size: 54, weight: .bold, design: .rounded))
                        .multilineTextAlignment(.center)
                        .focused($isAmountFocused)
                        .minimumScaleFactor(0.65)
                }

                Text("This is the total amount available for the current month, including any carryover.")
                    .font(.footnote)
                    .foregroundStyle(Color.sproutTextMuted)
                    .multilineTextAlignment(.center)
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

    private var parsedAmount: Double? {
        guard let amount = Double(amountText), amount > 0 else { return nil }
        return amount
    }

    private func save() {
        guard let amount = parsedAmount else { return }
        onSave(amount)
        dismiss()
    }
}
