import SwiftUI

struct QuickCaptureSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: BudgetStore

    let tab: BudgetTab
    let mode: TransactionMode
    let onSubmit: (TransactionDraft) -> Void

    @FocusState private var focusedField: Field?
    @State private var draft: TransactionDraft
    @State private var validationMessage: String?

    init(tab: BudgetTab, mode: TransactionMode, initialDraft: TransactionDraft, onSubmit: @escaping (TransactionDraft) -> Void) {
        self.tab = tab
        self.mode = mode
        self.onSubmit = onSubmit
        _draft = State(initialValue: initialDraft)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                header

                if mode == .expense && tab == .personal {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Category")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.sproutTextMuted)
                            .textCase(.uppercase)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(store.categories(for: tab)) { category in
                                    Button {
                                        draft.selectedEmoji = category.emoji
                                    } label: {
                                        Text("\(category.emoji) \(category.label)")
                                            .font(.subheadline.weight(.medium))
                                            .foregroundStyle(draft.selectedEmoji == category.emoji ? Color.white : Color.sproutText)
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 8)
                                            .background(
                                                Capsule()
                                                    .fill(draft.selectedEmoji == category.emoji ? Color.sageDark : Color.sproutCard)
                                            )
                                            .overlay(
                                                Capsule()
                                                    .stroke(draft.selectedEmoji == category.emoji ? Color.sageDark : Color.sproutBorder, lineWidth: 1)
                                            )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("$")
                            .font(.system(size: 24, weight: .medium, design: .rounded))
                            .foregroundStyle(Color.sproutTextSecondary)

                        TextField("0.00", text: $draft.amountText)
                            .keyboardType(.decimalPad)
                            .font(.system(size: 40, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color.sproutText)
                            .focused($focusedField, equals: .amount)
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(Color.sproutCard)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(Color.sproutBorder, lineWidth: 1)
                    )

                    TextField(mode.prompt, text: $draft.name)
                        .textInputAutocapitalization(.words)
                        .focused($focusedField, equals: .name)
                        .font(.headline)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(Color.sproutCard)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(Color.sproutBorder, lineWidth: 1)
                        )

                    TextField("Note (optional)", text: $draft.note)
                        .focused($focusedField, equals: .note)
                        .font(.subheadline)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(Color.sproutCard)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(Color.sproutBorder, lineWidth: 1)
                        )
                }

                HStack(spacing: 12) {
                    Label(tab.shortTitle, systemImage: tab == .grocery ? "cart.fill" : "person.fill")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color.sproutTextSecondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(Capsule().fill(Color.sproutCard))
                        .overlay(Capsule().stroke(Color.sproutBorder, lineWidth: 1))

                    Spacer()

                    DatePicker("", selection: $draft.date, displayedComponents: .date)
                        .labelsHidden()
                        .datePickerStyle(.compact)
                }

                if let validationMessage {
                    Text(validationMessage)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(Color.sproutRed)
                }

                HStack(spacing: 10) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .font(.headline)
                    .foregroundStyle(Color.sproutTextSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color.sproutCard)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Color.sproutBorder, lineWidth: 1)
                    )
                    .buttonStyle(.plain)

                    Button {
                        submit()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: mode.symbol)
                            Text(mode == .payment ? "Save Payment" : "Save Expense")
                        }
                        .font(.headline)
                        .foregroundStyle(Color.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(mode == .payment ? Color.sageDark : Color.sage)
                        )
                    }
                    .buttonStyle(.plain)
                }

                Spacer(minLength: 0)
            }
            .padding(20)
            .background(Color.sproutBackground.ignoresSafeArea())
            .navigationBarBackButtonHidden()
            .presentationDetents([.fraction(0.56), .medium])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(28)
            .onAppear {
                focusedField = .amount
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(tab.icon)
                    .font(.title2)
                Text(mode == .payment ? "Quick Payment" : "Quick Add")
                    .font(.system(.title3, design: .serif, weight: .semibold))
                    .foregroundStyle(Color.sproutText)
                Spacer()
            }

            Text("Opened from your shortcut so you can log it fast and move on.")
                .font(.subheadline)
                .foregroundStyle(Color.sproutTextSecondary)
        }
    }

    private func submit() {
        let trimmedName = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            validationMessage = "Add a short description first."
            focusedField = .name
            return
        }

        guard let amount = draft.parsedAmount, amount > 0 else {
            validationMessage = "Enter an amount greater than zero."
            focusedField = .amount
            return
        }

        validationMessage = nil
        draft.name = trimmedName
        draft.amountText = String(format: "%.2f", amount)
        onSubmit(draft)
    }

    private enum Field {
        case amount
        case name
        case note
    }
}
