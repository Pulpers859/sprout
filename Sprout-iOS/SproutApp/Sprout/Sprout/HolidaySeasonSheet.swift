import SwiftUI

/// Renames the current holiday season, or closes it and opens a new one.
///
/// Starting a new season is the only way out of a one-shot tracker: without it,
/// next December still shows this December's gifts and the only way to start
/// over is deleting them one at a time. Nothing is thrown away — the closing
/// season moves into history — and the copy below says exactly what moves,
/// what carries, and what the limit is.
struct HolidaySeasonSheet: View {
    @Environment(\.dismiss) private var dismiss

    enum Mode {
        case rename
        case startNew
    }

    let mode: Mode
    let currentLabel: String
    let giftCount: Int
    let personCount: Int
    let budget: MoneyAmount
    let archivedCount: Int
    /// `label` and, for a new season, whether to keep the same people.
    let onSubmit: (String, Bool) -> Bool

    @FocusState private var isNameFocused: Bool
    @State private var label: String
    @State private var carryRecipients = true
    @State private var validationMessage: String?
    @State private var isSubmitting = false

    init(
        mode: Mode,
        currentLabel: String,
        giftCount: Int,
        personCount: Int,
        budget: MoneyAmount,
        archivedCount: Int,
        onSubmit: @escaping (String, Bool) -> Bool
    ) {
        self.mode = mode
        self.currentLabel = currentLabel
        self.giftCount = giftCount
        self.personCount = personCount
        self.budget = budget
        self.archivedCount = archivedCount
        self.onSubmit = onSubmit
        _label = State(initialValue: mode == .rename ? currentLabel : "")
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    nameField

                    if mode == .startNew {
                        carryToggle
                        consequences
                    }

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
            .navigationTitle(mode == .rename ? "Rename Season" : "New Season")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .onAppear {
                isNameFocused = true
            }
        }
    }

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel(mode == .rename ? "Season name" : "New season name")

            TextField(placeholder, text: $label)
                .textInputAutocapitalization(.words)
                .font(.headline)
                .foregroundStyle(Color.sproutText)
                .focused($isNameFocused)
                .submitLabel(.done)
                .padding(.horizontal, 14)
                .padding(.vertical, 14)
                .background(Color.sproutCard, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.sproutBorder, lineWidth: 1))

            if mode == .startNew {
                Text("Leave it empty to use \u{201C}\(HolidaySeason.defaultLabel())\u{201D}.")
                    .font(.caption)
                    .foregroundStyle(Color.sproutTextMuted)
            }
        }
    }

    private var placeholder: String {
        mode == .rename ? currentLabel : HolidaySeason.defaultLabel()
    }

    private var carryToggle: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Keep the same people")
                    .font(.headline)
                    .foregroundStyle(Color.sproutText)

                Text(personCount == 0
                     ? "No people on the list yet."
                     : "Carries \(personCount) \(personCount == 1 ? "person" : "people") and their targets, without their gifts.")
                    .font(.footnote)
                    .foregroundStyle(Color.sproutTextMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            Toggle("", isOn: $carryRecipients)
                .labelsHidden()
                .tint(Color.sproutBerryDark)
                .disabled(personCount == 0)
        }
        .padding(16)
        .background(Color.sproutBerryLight, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var consequences: some View {
        VStack(alignment: .leading, spacing: 8) {
            consequence(
                "arrow.down.doc",
                "\(currentLabel) moves to your past seasons"
                    + (giftCount == 0 ? "." : " with its \(giftCount) gift\(giftCount == 1 ? "" : "s").")
            )
            consequence(
                "dollarsign.circle",
                budget > .zero
                    ? "Your \(SproutFormatters.currency(budget)) holiday budget carries over — you can change it afterwards."
                    : "The new season starts with no budget set."
            )
            consequence(
                "clock.arrow.circlepath",
                "Sprout keeps your \(BudgetStore.holidaySeasonHistoryLimit) most recent seasons"
                    + (archivedCount >= BudgetStore.holidaySeasonHistoryLimit
                       ? ", so the oldest one will be dropped."
                       : ".")
            )
            consequence("lock", "Your monthly budgets are not affected.")
        }
        .padding(16)
        .background(Color.sproutCard, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.sproutBorder, lineWidth: 1))
    }

    private func consequence(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: symbol)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.sproutBerryDark)
                .frame(width: 18)

            Text(text)
                .font(.footnote)
                .foregroundStyle(Color.sproutTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var saveButton: some View {
        Button {
            submit()
        } label: {
            Label(
                mode == .rename ? "Save name" : "Start new season",
                systemImage: mode == .rename ? "checkmark.circle.fill" : "sparkles"
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
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)

        // A rename needs a name; a new season falls back to the default label.
        if mode == .rename, trimmed.isEmpty {
            validationMessage = "Give this season a name."
            isNameFocused = true
            return
        }

        validationMessage = nil
        isSubmitting = true
        guard onSubmit(trimmed, carryRecipients && personCount > 0) else {
            isSubmitting = false
            validationMessage = "Sprout couldn't save that. Try again."
            return
        }
    }
}
