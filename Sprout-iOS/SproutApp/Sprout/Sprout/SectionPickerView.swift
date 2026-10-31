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
    /// label, and a large Dynamic Type setting takes the rest.
    ///
    /// The fallback chain ends in icon-only rather than in scaled text, because
    /// at AX4/AX5 even "Personal" at a 0.7 scale factor needs roughly twice the
    /// width a third of the capsule provides — so the previous two-candidate
    /// chain still truncated to exactly the "Perso…" it was meant to avoid. The
    /// symbols are distinct and `accessibilityLabel` carries the name either
    /// way, so an icon is a better last resort than a clipped word.
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
                .fixedSize()

            Image(systemName: section.symbolName)
                .font(.subheadline.weight(.semibold))
                .fixedSize()
        }
    }
}
