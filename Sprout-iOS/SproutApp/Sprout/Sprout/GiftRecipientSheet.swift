import SwiftUI

/// Adds or edits one person on the holiday list.
///
/// Writes only on Save. That matters: `BudgetStore` normalizes holiday data on
/// every persist, and normalization renames a blank name rather than deleting
/// the row — but a sheet that saved on every keystroke would still rewrite
/// someone's name to "Someone" the moment they cleared the field to retype it,
/// which is the bug the category editor had to be fixed for.
struct GiftRecipientSheet: View {
    @Environment(\.dismiss) private var dismiss

    let isEditing: Bool
    let onSubmit: (GiftRecipientDraft) -> Bool

    @FocusState private var focusedField: Field?
    @State private var draft: GiftRecipientDraft
    @State private var validationMessage: String?
    @State private var isSubmitting = false

    init(isEditing: Bool = false, initialDraft: GiftRecipientDraft, onSubmit: @escaping (GiftRecipientDraft) -> Bool) {
        self.isEditing = isEditing
        self.onSubmit = onSubmit
        _draft = State(initialValue: initialDraft)
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    nameField
                    emojiPicker
                    plannedField

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
            .navigationTitle(isEditing ? "Edit Person" : "Add Person")
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
                focusedField = .name
            }
        }
    }

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Name")

            HStack(spacing: 12) {
                Text(draft.emoji.isEmpty ? GiftRecipient.defaultEmoji : draft.emoji)
                    .font(.title3)
                    .frame(width: 40, height: 40)
                    .background(Color.sproutCardSoft, in: Circle())

                TextField("Mom, Dad, Sam…", text: $draft.name)
                    .textInputAutocapitalization(.words)
                    .font(.headline)
                    .foregroundStyle(Color.sproutText)
                    .focused($focusedField, equals: .name)
                    .submitLabel(.done)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color.sproutCard, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.sproutBorder, lineWidth: 1))
        }
    }

    private var emojiPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Icon")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(GiftRecipient.emojiChoices, id: \.self) { emoji in
                        let isSelected = draft.emoji == emoji
                        Button {
                            draft.emoji = emoji
                        } label: {
                            Text(emoji)
                                .font(.title3)
                                // 44pt rather than the visual 40pt, so the tap
                                // target clears the minimum.
                                .frame(width: 44, height: 44)
                                .background(
                                    isSelected ? Color.sproutBerryLight : Color.sproutCard,
                                    in: Circle()
                                )
                                .overlay(
                                    Circle().stroke(
                                        isSelected ? Color.sproutBerryDark : Color.sproutBorder,
                                        lineWidth: isSelected ? 2 : 1
                                    )
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Icon \(emoji)")
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                    }
                }
            }
            .contentMargins(.horizontal, 1, for: .scrollContent)
        }
    }

    private var plannedField: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Planned spend (optional)")

            HStack(spacing: 8) {
                Text(SproutFormatters.currencySymbol)
                    .font(.headline)
                    .foregroundStyle(Color.sproutTextSecondary)

                TextField("No target", text: $draft.plannedAmountText)
                    .keyboardType(.decimalPad)
                    .font(.system(.headline, design: .rounded, weight: .semibold))
                    .foregroundStyle(Color.sproutText)
                    .focused($focusedField, equals: .planned)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .background(Color.sproutCard, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.sproutBorder, lineWidth: 1))

            // Leaving it empty is a real choice with a real consequence, so the
            // difference between "no target" and "a target of nothing" is
            // spelled out rather than left for the user to infer.
            Text("Leave this empty if you don't want a per-person target. It only affects the \u{201C}left to plan\u{201D} figure — gifts always count against the holiday budget.")
                .font(.caption)
                .foregroundStyle(Color.sproutTextMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var saveButton: some View {
        Button {
            submit()
        } label: {
            Label(
                isEditing ? "Save changes" : "Add person",
                systemImage: isEditing ? "checkmark.circle.fill" : "person.badge.plus"
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

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.bold))
            .foregroundStyle(Color.sproutTextMuted)
            .textCase(.uppercase)
    }

    private func submit() {
        guard !isSubmitting else { return }

        let trimmedName = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            validationMessage = "Give this person a name first."
            focusedField = .name
            return
        }

        switch draft.plannedAmountResult {
        case .none, .amount:
            break
        case .exceedsMaximum:
            validationMessage = "Planned spend cannot exceed \(SproutFormatters.currency(SproutMoneyText.maximum))."
            focusedField = .planned
            return
        case .invalid:
            validationMessage = "Enter a planned amount like \(SproutMoneyText.editableWhole(MoneyAmount(dollars: 100))), or leave it empty."
            focusedField = .planned
            return
        }

        validationMessage = nil
        isSubmitting = true
        draft.name = trimmedName

        guard onSubmit(draft) else {
            isSubmitting = false
            validationMessage = "Sprout couldn't save this person. Try again."
            return
        }
    }

    private enum Field {
        case name
        case planned
    }
}
