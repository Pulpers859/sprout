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
    @EnvironmentObject private var store: BudgetStore
    @State var category: PersonalCategory
    @State private var isShowingEmojiPicker = false

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
            .sheet(isPresented: $isShowingEmojiPicker) {
                EmojiPickerSheet(selectedEmoji: $category.emoji)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
            .onChange(of: category.emoji) { _, _ in
                if category.emoji.isEmpty {
                    category.emoji = "🪴"
                }
                store.updateCategory(category)
            }

            TextField("Category name", text: $category.label)
                .font(.body)
                .foregroundStyle(Color.sproutText)
                .onChange(of: category.label) { _, _ in
                    store.updateCategory(category)
                }

            if store.categories(for: .personal).count > 1 {
                Button(role: .destructive) {
                    store.removeCategory(category)
                } label: {
                    Image(systemName: "minus.circle")
                        .font(.body)
                }
                .buttonStyle(.plain)
            }
        }
        .onDisappear {
            store.updateCategory(category)
        }
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
