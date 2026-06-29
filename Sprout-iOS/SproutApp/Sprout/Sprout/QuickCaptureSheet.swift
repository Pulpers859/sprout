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
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    contextLabel
                    amountField
                    categoryPicker
                    entryFields
                    metadataRow

                    if let validationMessage {
                        Label(validationMessage, systemImage: "exclamationmark.circle.fill")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(Color.sproutRed)
                    }
                }
                .padding(20)
            }
            .background(Color.sproutBackground.ignoresSafeArea())
            .safeAreaInset(edge: .bottom) {
                saveButton
            }
            .navigationTitle(mode == .payment ? "Quick payment" : "Quick expense")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .onAppear {
                focusedField = .amount
            }
        }
    }

    private var contextLabel: some View {
        Label(tab.shortTitle, systemImage: tab == .grocery ? "cart.fill" : "person.fill")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(tab.accentDarkColor)
    }

    private var amountField: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("$")
                .font(.system(size: 26, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.sproutTextSecondary)

            TextField("0.00", text: $draft.amountText)
                .keyboardType(.decimalPad)
                .font(.system(size: 50, weight: .bold, design: .rounded))
                .foregroundStyle(Color.sproutText)
                .focused($focusedField, equals: .amount)
                .minimumScaleFactor(0.65)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var categoryPicker: some View {
        if mode == .expense && tab == .personal {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(store.categories(for: tab)) { category in
                        let isSelected = draft.selectedCategoryID == category.id
                        Button {
                            draft.selectedCategoryID = category.id
                            draft.selectedEmoji = category.emoji
                        } label: {
                            Text(category.emoji)
                                .font(.title3)
                                .frame(width: 42, height: 42)
                                .background(
                                    isSelected ? tab.accentDarkColor : Color.sproutCard,
                                    in: Circle()
                                )
                                .overlay(Circle().stroke(Color.sproutBorder, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(category.label)
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                    }
                }
            }
        }
    }

    private var entryFields: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "text.cursor")
                    .foregroundStyle(Color.sproutTextMuted)
                    .frame(width: 24)

                TextField(mode.prompt, text: $draft.name)
                    .textInputAutocapitalization(.words)
                    .focused($focusedField, equals: .name)
                    .font(.headline)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 15)

            Divider()
                .padding(.leading, 52)

            HStack(spacing: 12) {
                Image(systemName: "note.text")
                    .foregroundStyle(Color.sproutTextMuted)
                    .frame(width: 24)

                TextField("Note (optional)", text: $draft.note)
                    .focused($focusedField, equals: .note)
                    .font(.subheadline)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 15)
        }
        .background(Color.sproutCard, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.sproutBorder, lineWidth: 1))
    }

    private var metadataRow: some View {
        HStack {
            Text(mode == .payment ? "Payment" : "Expense")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.sproutTextMuted)

            Spacer()

            DatePicker("", selection: $draft.date, displayedComponents: .date)
                .labelsHidden()
                .datePickerStyle(.compact)
                .tint(tab.accentDarkColor)
        }
    }

    private var saveButton: some View {
        Button {
            submit()
        } label: {
            Label(
                mode == .payment ? "Save payment" : "Save expense",
                systemImage: mode.symbol
            )
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
        }
        .buttonStyle(.glassProminent)
        .tint(tab.accentDarkColor)
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .background(.bar)
    }

    private func submit() {
        let trimmedName = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            validationMessage = "Add a short description first."
            focusedField = .name
            return
        }

        guard let amount = draft.parsedAmount, amount > 0 else {
            let raw = draft.amountText.replacingOccurrences(of: ",", with: "")
            if let v = Double(raw), v > TransactionDraft.maximumAmount {
                validationMessage = "Amount cannot exceed \(SproutFormatters.currency(TransactionDraft.maximumAmount))."
            } else {
                validationMessage = "Enter an amount greater than zero."
            }
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
