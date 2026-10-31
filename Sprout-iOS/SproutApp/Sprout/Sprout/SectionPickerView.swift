import SwiftUI

/// The three top-level sections: two monthly budget tabs and the holiday
/// tracker, which is not a monthly budget at all.
struct SectionPickerView: View {
    @Binding var selection: AppSection

    var body: some View {
        HStack(spacing: 4) {
            ForEach(AppSection.allCases) { section in
                Button {
                    withAnimation(.snappy(duration: 0.25)) {
                        selection = section
                    }
                } label: {
                    label(for: section)
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .padding(.vertical, 6)
                        .foregroundStyle(selection == section ? Color.white : Color.sproutTextSecondary)
                        .background(
                            Capsule()
                                .fill(selection == section ? section.accentDarkColor : .clear)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(section.shortTitle)
                .accessibilityAddTraits(selection == section ? .isSelected : [])
            }
        }
        .padding(4)
        .background(Color.sproutCard, in: Capsule())
        .overlay(Capsule().stroke(Color.sproutBorder, lineWidth: 1))
    }

    /// Three segments where there used to be two leaves much less room per
    /// label, and a large Dynamic Type setting takes the rest. Rather than let
    /// the names truncate to "Perso…", the icon is dropped first and only then
    /// does the text scale.
    private func label(for section: AppSection) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) {
                Image(systemName: section.symbolName)
                    .font(.caption.weight(.semibold))
                Text(section.shortTitle)
                    .font(.subheadline.weight(.semibold))
            }
            .lineLimit(1)
            .fixedSize()

            Text(section.shortTitle)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }
}
