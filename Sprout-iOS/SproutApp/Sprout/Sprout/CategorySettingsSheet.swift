import SwiftUI

struct CategorySettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: BudgetStore

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(store.categories(for: .personal)) { category in
                        CategoryRow(category: category)
                    }
                } header: {
                    Text("Personal spending")
                } footer: {
                    Text("Tap an icon to change it. Categories are available when adding personal expenses.")
                }

                if store.categories(for: .personal).count < 10 {
                    Section {
                        Button("Add category", systemImage: "plus") {
                            store.addCategory()
                        }
                        .foregroundStyle(Color.sageDark)
                    }
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .background(Color.sproutBackground.ignoresSafeArea())
            .navigationTitle("Categories")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundStyle(Color.sageDark)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

private struct CategoryRow: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var store: BudgetStore
    @State var category: PersonalCategory
    @State private var isShowingEmojiPicker = false
    @State private var isRemoved = false

    var body: some View {
        HStack(spacing: 12) {
            Button {
                isShowingEmojiPicker = true
            } label: {
                Text(category.emoji)
                    .font(.title3)
                    .frame(width: 40, height: 40)
                    .background(Color.sproutCardSoft, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Icon for \(category.label)")
            .sheet(isPresented: $isShowingEmojiPicker) {
                EmojiPickerSheet(selectedEmoji: $category.emoji)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
            .onChange(of: category.emoji) { _, _ in
                if category.emoji.isEmpty {
                    category.emoji = "🪴"
                }
                // An icon change must land even while the name field is mid-edit,
                // so it bypasses the blank-label guard rather than being swallowed
                // by it.
                commit(allowBlankLabel: true)
            }

            TextField("Category name", text: $category.label)
                .font(.body)
                .foregroundStyle(Color.sproutText)
                .submitLabel(.done)
                .onSubmit { commit() }

            if store.categories(for: .personal).count > 1 {
                Button(role: .destructive) {
                    isRemoved = true
                    store.removeCategory(category)
                } label: {
                    Image(systemName: "minus.circle")
                        .font(.body)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove \(category.label)")
            }
        }
        // Renaming used to write the whole budget file to disk on every keystroke
        // — a full JSON encode plus a backup rotation per character. The label is
        // now committed once the typing pauses.
        .task(id: category.label) {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            commit()
        }
        .onDisappear { commit() }
        // `.onDisappear` does not fire when the app is backgrounded, so without
        // this a rename made in the last half second was simply lost.
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { commit() }
        }
    }

    private func commit(allowBlankLabel: Bool = false) {
        guard !isRemoved else { return }
        // `.task(id:)` also fires on first appearance, so an unchanged row must not
        // trigger a save just because the sheet opened.
        guard store.categories(for: .personal).first(where: { $0.id == category.id }) != category else { return }

        // A half-typed empty name is not written, so the row keeps its old label
        // until the user commits a real one. The store no longer deletes blank
        // rows either, so this is a courtesy rather than the safety net it was.
        if !allowBlankLabel, category.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return
        }
        store.updateCategory(category)
    }
}

private struct EmojiPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedEmoji: String
    @State private var customEmoji = ""

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                Text("Switch to the emoji keyboard, search for an icon, and enter one emoji.")
                    .font(.subheadline)
                    .foregroundStyle(Color.sproutTextSecondary)

                HStack(spacing: 12) {
                    TextField("Emoji", text: $customEmoji)
                        .font(.system(size: 36))
                        .multilineTextAlignment(.center)
                        .frame(width: 76, height: 64)
                        .background(Color.sproutCard, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color.sproutBorderDark, lineWidth: 1)
                        )
                        .onChange(of: customEmoji) { _, newValue in
                            let firstCharacter = newValue.first.map(String.init) ?? ""
                            if firstCharacter != newValue {
                                customEmoji = firstCharacter
                            }
                        }

                    Button("Use Emoji") {
                        selectedEmoji = customEmoji
                        dismiss()
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .buttonStyle(.borderedProminent)
                    .tint(Color.sageDark)
                    .disabled(customEmoji.isEmpty)
                }
            }
            .padding(20)
            .frame(maxHeight: .infinity, alignment: .top)
            .background(Color.sproutBackground.ignoresSafeArea())
            .navigationTitle("Choose Icon")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                    .foregroundStyle(Color.sageDark)
                }
            }
            .onAppear {
                customEmoji = selectedEmoji
            }
        }
    }
}
