import SwiftUI

/// Logs or edits one gift.
///
/// Shares `SproutMoneyText` with every other amount field in the app, the
/// double-submit guard from `TransactionEntrySheet`, and the same
/// re-serialize-before-submit step so the string the store re-parses is exactly
/// the one validated here.
struct GiftEntrySheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: BudgetStore

    let isEditing: Bool
    let onSubmit: (GiftPurchaseDraft) -> Bool

    @FocusState private var focusedField: Field?
    @ScaledMetric(relativeTo: .largeTitle) private var amountFontSize: CGFloat = 52
    @ScaledMetric(relativeTo: .title2) private var currencySymbolFontSize: CGFloat = 28
    @State private var draft: GiftPurchaseDraft
    @State private var validationMessage: String?
    @State private var isSubmitting = false
    /// False until the user says who the gift is for. See
    /// `GiftRecipientSelection`: without this, the primary Add gift button
    /// opened pre-selected on "Not for one person" and a gift saved straight
    /// away was filed against nobody, silently.
    @State private var hasPickedRecipient: Bool

    init(
        isEditing: Bool = false,
        initialDraft: GiftPurchaseDraft,
        recipientIsChosen: Bool,
        onSubmit: @escaping (GiftPurchaseDraft) -> Bool
    ) {
        self.isEditing = isEditing
        self.onSubmit = onSubmit
        _draft = State(initialValue: initialDraft)
        _hasPickedRecipient = State(initialValue: recipientIsChosen)
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    modePicker
                    amountField
                    recipientPicker
                    composerFields
                    dateRow

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
            .navigationTitle(navigationTitle)
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
        }
    }

    /// Gifts and returns are one sheet with a mode, mirroring the monthly
    /// tab's expense/payment pair. A returned gift keeps its own row instead of
    /// being deleted or edited down: deleting loses the record of what was
    /// bought, and editing the amount loses the fact that money moved twice.
    private var navigationTitle: String {
        if isEditing { return draft.isReturn ? "Edit Return" : "Edit Gift" }
        return draft.isReturn ? "Record Return" : "Add Gift"
    }

    private var modePicker: some View {
        Picker("Entry type", selection: $draft.isReturn) {
            Text("Gift").tag(false)
            Text("Return").tag(true)
        }
        .pickerStyle(.segmented)
    }

    private var amountField: some View {
        VStack(spacing: 6) {
            Text(draft.isReturn ? "AMOUNT RETURNED" : "GIFT AMOUNT")
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.sproutTextMuted)

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(SproutFormatters.currencySymbol)
                    .font(.system(size: currencySymbolFontSize, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.sproutTextSecondary)

                TextField(SproutMoneyText.editable(.zero), text: $draft.amountText)
                    .keyboardType(.decimalPad)
                    .font(.system(size: amountFontSize, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.sproutText)
                    .focused($focusedField, equals: .amount)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.65)
            }
            .frame(maxWidth: .infinity)

            // Said plainly at the point of entry, because the whole reason this
            // tab exists is that this money is not part of the monthly budget.
            Text(draft.isReturn
                 ? "Comes back off your holiday budget only."
                 : "Counted against your holiday budget only.")
                .font(.caption)
                .foregroundStyle(Color.sproutTextMuted)
        }
        .padding(.vertical, 12)
    }

    private var recipientPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Who it's for")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    // First, not last. It used to sit after every person in a
                    // scrolling row, so with four people or one long name it
                    // was off screen — while being the selected option.
                    //
                    // Still a first-class choice, not only what a removed
                    // person leaves behind: wrapping paper and party gifts are
                    // real holiday spending that belongs to nobody in
                    // particular.
                    chip(
                        title: "Not for one person",
                        emoji: "🎁",
                        isSelected: hasPickedRecipient && draft.recipientID == nil
                    ) {
                        draft.recipientID = nil
                        hasPickedRecipient = true
                    }

                    ForEach(store.holidayRecipients) { recipient in
                        chip(
                            title: recipient.name,
                            emoji: recipient.emoji,
                            isSelected: hasPickedRecipient && draft.recipientID == recipient.id
                        ) {
                            draft.recipientID = recipient.id
                            hasPickedRecipient = true
                        }
                    }
                }
            }
            .contentMargins(.horizontal, 1, for: .scrollContent)

            if store.holidayRecipients.isEmpty {
                Text("Add people on the Holiday tab to track who each gift is for.")
                    .font(.caption)
                    .foregroundStyle(Color.sproutTextMuted)
            } else if !hasPickedRecipient {
                Text("Pick a person, or \u{201C}Not for one person\u{201D}.")
                    .font(.caption)
                    .foregroundStyle(Color.sproutTextMuted)
            }
        }
    }

    private func chip(title: String, emoji: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(emoji)
                Text(title)
                    .lineLimit(1)
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(isSelected ? Color.white : Color.sproutText)
            .padding(.horizontal, 14)
            // 44pt is the minimum comfortable touch target; the padding alone
            // left these at about 38.
            .frame(minHeight: 44)
            .background(isSelected ? Color.sproutBerryDark : Color.sproutCard, in: Capsule())
            .overlay(Capsule().stroke(Color.sproutBorder, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var composerFields: some View {
        VStack(spacing: 0) {
            composerField(
                draft.isReturn ? "What did you return?" : "What did you buy?",
                text: $draft.name,
                field: .name,
                symbol: "text.cursor"
            )

            Divider()
                .padding(.leading, 52)

            composerField("Note (optional)", text: $draft.note, field: .note, symbol: "note.text")
        }
        .background(Color.sproutCard, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.sproutBorder, lineWidth: 1))
    }

    private var dateRow: some View {
        HStack(spacing: 10) {
            Label(draft.isReturn ? "Returned on" : "Bought on", systemImage: "calendar")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.sproutBerryText)

            Spacer()

            DatePicker("", selection: $draft.date, displayedComponents: .date)
                .labelsHidden()
                .datePickerStyle(.compact)
                .tint(Color.sproutBerryDark)
        }
    }

    private var saveButton: some View {
        Button {
            submit()
        } label: {
            Label(
                isEditing
                    ? "Save changes"
                    : (draft.isReturn ? "Save return" : "Save gift"),
                systemImage: isEditing
                    ? "checkmark.circle.fill"
                    : (draft.isReturn ? "arrow.uturn.backward" : "gift.fill")
            )
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
        }
        .buttonStyle(.glassProminent)
        .tint(Color.sproutBerryDark)
        .disabled(isSubmitting)
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
        // The caller dismisses after a successful save, which leaves a window
        // where a second tap lands on a still-live button and files the gift twice.
        guard !isSubmitting else { return }

        let trimmedName = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            validationMessage = "Add a short description first."
            focusedField = .name
            return
        }

        let amount: MoneyAmount
        switch draft.amountParseResult {
        case .valid(let parsed):
            amount = parsed
        case .exceedsMaximum:
            validationMessage = "Amount cannot exceed \(SproutFormatters.currency(SproutMoneyText.maximum))."
            focusedField = .amount
            return
        case .invalid:
            validationMessage = "Enter an amount greater than zero."
            focusedField = .amount
            return
        }

        // Saving a gift against nobody has to be a decision, not a default.
        guard hasPickedRecipient || store.holidayRecipients.isEmpty else {
            validationMessage = draft.isReturn
                ? "Choose who this return is for, or tap \u{201C}Not for one person\u{201D}."
                : "Choose who this gift is for, or tap \u{201C}Not for one person\u{201D}."
            return
        }

        validationMessage = nil
        isSubmitting = true
        draft.name = trimmedName
        draft.amountText = SproutMoneyText.editable(amount)

        guard onSubmit(draft) else {
            isSubmitting = false
            validationMessage = draft.isReturn
                ? "Sprout couldn't save this return. Check the amount and try again."
                : "Sprout couldn't save this gift. Check the amount and try again."
            return
        }
    }

    private enum Field {
        case amount
        case name
        case note
    }
}
