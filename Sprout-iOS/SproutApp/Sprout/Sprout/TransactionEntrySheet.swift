import SwiftUI

struct TransactionEntrySheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: BudgetStore

    let tab: BudgetTab
    let mode: TransactionMode
    let onSubmit: (TransactionDraft) -> Void

    @FocusState private var focusedField: Field?
    @State private var draft: TransactionDraft
    @State private var validationMessage: String?
    @State private var hasCustomizedRecurringDate = false

    init(tab: BudgetTab, mode: TransactionMode, initialDraft: TransactionDraft, onSubmit: @escaping (TransactionDraft) -> Void) {
        self.tab = tab
        self.mode = mode
        self.onSubmit = onSubmit
        _draft = State(initialValue: initialDraft)
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    amountField
                    categoryPicker
                    composerFields
                    metadataRow
                    recurringSection

                    if let validationMessage {
                        Label(validationMessage, systemImage: "exclamationmark.circle.fill")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(Color.sproutRed)
                    }
                }
                .padding(20)
                .padding(.bottom, 8)
            }
            .background(Color.sproutBackground.ignoresSafeArea())
            .safeAreaInset(edge: .bottom) {
                saveButton
            }
            .navigationTitle(mode.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .onAppear {
                focusedField = .amount
            }
            .onChange(of: draft.isRecurring) { _, isRecurring in
                if isRecurring {
                    updateRecurringDate(force: true)
                } else {
                    hasCustomizedRecurringDate = false
                }
            }
            .onChange(of: draft.date) { _, _ in
                updateRecurringDate(force: false)
            }
            .onChange(of: draft.recurringFrequency) { _, _ in
                updateRecurringDate(force: false)
            }
        }
    }

    private var amountField: some View {
        VStack(spacing: 6) {
            Text(mode == .payment ? "PAYMENT AMOUNT" : "EXPENSE AMOUNT")
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.sproutTextMuted)

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("$")
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.sproutTextSecondary)

                TextField("0.00", text: $draft.amountText)
                    .keyboardType(.decimalPad)
                    .font(.system(size: 52, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.sproutText)
                    .focused($focusedField, equals: .amount)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.65)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var categoryPicker: some View {
        if mode == .expense && tab == .personal {
            VStack(alignment: .leading, spacing: 10) {
                sectionLabel("Category")

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(store.categories(for: tab)) { category in
                            let isSelected = draft.selectedCategoryID == category.id
                            Button {
                                draft.selectedCategoryID = category.id
                                draft.selectedEmoji = category.emoji
                            } label: {
                                HStack(spacing: 6) {
                                    Text(category.emoji)
                                    Text(category.label)
                                }
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(isSelected ? Color.white : Color.sproutText)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 9)
                                .background(
                                    isSelected ? tab.accentDarkColor : Color.sproutCard,
                                    in: Capsule()
                                )
                                .overlay(Capsule().stroke(Color.sproutBorder, lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private var composerFields: some View {
        VStack(spacing: 0) {
            composerField(mode.prompt, text: $draft.name, field: .name, symbol: "text.cursor")

            Divider()
                .padding(.leading, 52)

            composerField("Note (optional)", text: $draft.note, field: .note, symbol: "note.text")
        }
        .background(Color.sproutCard, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.sproutBorder, lineWidth: 1))
    }

    private var metadataRow: some View {
        HStack(spacing: 10) {
            Label(tab.shortTitle, systemImage: tab == .grocery ? "cart.fill" : "person.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tab.accentDarkColor)

            Spacer()

            DatePicker("", selection: $draft.date, displayedComponents: .date)
                .labelsHidden()
                .datePickerStyle(.compact)
                .tint(tab.accentDarkColor)
        }
    }

    private var recurringSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Recurring")
                        .font(.headline)
                        .foregroundStyle(Color.sproutText)

                    Text("Add future entries automatically")
                        .font(.footnote)
                        .foregroundStyle(Color.sproutTextMuted)
                }

                Spacer()

                Toggle("", isOn: $draft.isRecurring)
                    .labelsHidden()
                    .tint(tab.accentDarkColor)
            }

            if draft.isRecurring {
                VStack(alignment: .leading, spacing: 14) {
                    Picker("Frequency", selection: $draft.recurringFrequency) {
                        ForEach(RecurrenceFrequency.allCases) { frequency in
                            Text(frequency.shortTitle)
                                .tag(frequency)
                        }
                    }
                    .pickerStyle(.segmented)

                    HStack {
                        Label("Next due", systemImage: "calendar")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Color.sproutTextSecondary)

                        Spacer()

                        DatePicker(
                            "",
                            selection: Binding(
                                get: { draft.recurringNextDate },
                                set: { newValue in
                                    hasCustomizedRecurringDate = true
                                    draft.recurringNextDate = newValue
                                }
                            ),
                            in: draft.minimumRecurringDate...,
                            displayedComponents: .date
                        )
                        .labelsHidden()
                        .datePickerStyle(.compact)
                        .tint(tab.accentDarkColor)
                    }
                }
                .padding(16)
                .background(tab.accentLightColor, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.snappy(duration: 0.25), value: draft.isRecurring)
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

    private func composerField(
        _ title: String,
        text: Binding<String>,
        field: Field,
        symbol: String
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .foregroundStyle(Color.sproutTextMuted)
                .frame(width: 24)

            TextField(title, text: text)
                .textInputAutocapitalization(.words)
                .font(field == .name ? .headline : .subheadline)
                .foregroundStyle(Color.sproutText)
                .focused($focusedField, equals: field)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 15)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.bold))
            .foregroundStyle(Color.sproutTextMuted)
            .textCase(.uppercase)
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

    private func updateRecurringDate(force: Bool) {
        guard draft.isRecurring else { return }
        guard force || !hasCustomizedRecurringDate else { return }

        draft.recurringNextDate = TransactionDraft.defaultRecurringNextDate(
            from: draft.date,
            frequency: draft.recurringFrequency
        )
    }

    private enum Field {
        case amount
        case name
        case note
    }
}
