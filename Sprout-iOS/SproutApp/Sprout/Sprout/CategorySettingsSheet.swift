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

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 5)

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(PersonalCategory.emojiOptions, id: \.self) { emoji in
                        Button {
                            selectedEmoji = emoji
                            dismiss()
                        } label: {
                            Text(emoji)
                                .font(.system(size: 28))
                                .frame(maxWidth: .infinity)
                                .frame(height: 56)
                                .background(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .fill(selectedEmoji == emoji ? Color.sageLight : Color.sproutCardSoft)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .stroke(selectedEmoji == emoji ? Color.sage : Color.sproutBorder, lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(20)
            }
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
        }
    }
}
