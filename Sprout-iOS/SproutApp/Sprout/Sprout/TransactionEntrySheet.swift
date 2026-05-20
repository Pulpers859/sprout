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
                VStack(alignment: .leading, spacing: 18) {
                    header

                    if mode == .expense && tab == .personal {
                        VStack(alignment: .leading, spacing: 10) {
                            sectionLabel("Category")

                            FlowLayout(spacing: 8) {
                                ForEach(store.categories(for: tab)) { category in
                                    Button {
                                        draft.selectedEmoji = category.emoji
                                    } label: {
                                        Text("\(category.emoji) \(category.label)")
                                            .font(.subheadline.weight(.medium))
                                            .foregroundStyle(draft.selectedEmoji == category.emoji ? Color.white : Color.sproutText)
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 9)
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

                    composerFields

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
                            .tint(.sageDark)
                    }

                    recurringSection

                    if let validationMessage {
                        Text(validationMessage)
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(Color.sproutRed)
                    }
                }
                .padding(20)
                .padding(.bottom, 12)
            }
            .background(Color.sproutBackground.ignoresSafeArea())
            .safeAreaInset(edge: .bottom) {
                actionBar
            }
            .scrollDismissesKeyboard(.interactively)
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(28)
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

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(tab.icon)
                    .font(.title2)
                Text(mode.title)
                    .font(.system(.title3, design: .serif, weight: .semibold))
                    .foregroundStyle(Color.sproutText)
                Spacer()
            }

            Text("Fast entry, clear fields, no wasted space.")
                .font(.subheadline)
                .foregroundStyle(Color.sproutTextSecondary)
        }
    }

    private var composerFields: some View {
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
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color.sproutCard)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.sproutBorder, lineWidth: 1)
            )

            composerField(mode.prompt, text: $draft.name, field: .name)
            composerField("Note (optional)", text: $draft.note, field: .note)
        }
    }

    private var recurringSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    sectionLabel("Recurring")
                    Text("Set it once and Sprout will add future entries automatically.")
                        .font(.footnote)
                        .foregroundStyle(Color.sproutTextMuted)
                }

                Spacer()

                Toggle("", isOn: $draft.isRecurring)
                    .labelsHidden()
                    .tint(.sageDark)
            }

            if draft.isRecurring {
                VStack(alignment: .leading, spacing: 12) {
                    Picker("Frequency", selection: $draft.recurringFrequency) {
                        ForEach(RecurrenceFrequency.allCases) { frequency in
                            Text(frequency.shortTitle)
                                .tag(frequency)
                        }
                    }
                    .pickerStyle(.segmented)

                    HStack {
                        Label("Next due", systemImage: "repeat")
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
                        .tint(.sageDark)
                    }

                    Text("\(draft.recurringFrequency.title) starting \(SproutDate.shortDate(draft.recurringNextDate)).")
                        .font(.footnote)
                        .foregroundStyle(Color.sproutTextMuted)
                }
                .padding(16)
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
    }

    private var actionBar: some View {
        HStack(spacing: 10) {
            pillButton("Cancel", foreground: .sproutTextSecondary, background: .sproutCard, border: .sproutBorder) {
                dismiss()
            }

            pillButton(mode == .payment ? "Save Payment" : "Save Expense", foreground: .white, background: .sageDark, border: .sageDark) {
                submit()
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 12)
        .background(.ultraThinMaterial)
    }

    private func composerField(_ title: String, text: Binding<String>, field: Field) -> some View {
        TextField(title, text: text)
            .textInputAutocapitalization(.words)
            .font(field == .name ? .headline : .subheadline)
            .foregroundStyle(Color.sproutText)
            .focused($focusedField, equals: field)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.sproutCard)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.sproutBorder, lineWidth: 1)
            )
    }

    private func pillButton(_ title: String, foreground: Color, background: Color, border: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .foregroundStyle(foreground)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(background)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(border, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
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
            validationMessage = "Enter an amount greater than zero."
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
