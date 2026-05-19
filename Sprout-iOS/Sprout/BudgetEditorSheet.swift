import SwiftUI

struct BudgetEditorSheet: View {
    @Environment(\.dismiss) private var dismiss

    let tab: BudgetTab
    let onSave: (Double) -> Void

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
            Form {
                Section(tab.title) {
                    TextField("Budget", text: $amountText)
                        .keyboardType(.decimalPad)
                }
            }
            .navigationTitle("Edit Budget")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard let amount = Double(amountText), amount > 0 else { return }
                        onSave(amount)
                        dismiss()
                    }
                }
            }
        }
    }
}
