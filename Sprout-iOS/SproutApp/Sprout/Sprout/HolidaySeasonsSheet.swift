import SwiftUI

/// Read-only look back at closed holiday seasons.
///
/// Matches `RecentMonthsSheet`: archived data is never editable here, only
/// removable, so a number you look up next December is the number you closed
/// the season with.
struct HolidaySeasonsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: BudgetStore

    @State private var selectedSeason: HolidaySeason?
    @State private var pendingDelete: HolidaySeason?

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                if store.holidaySeasonHistory.isEmpty {
                    ContentUnavailableView(
                        "No past seasons yet",
                        systemImage: "gift",
                        description: Text("When you start a new holiday season, Sprout keeps the one you closed here for reference.")
                    )
                    .padding(.top, 60)
                    .padding(.horizontal, 20)
                } else {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("These snapshots are read-only and limited to your \(BudgetStore.holidaySeasonHistoryLimit) most recent seasons.")
                            .font(.subheadline)
                            .foregroundStyle(Color.sproutTextSecondary)

                        ForEach(store.holidaySeasonHistory) { season in
                            Button {
                                selectedSeason = season
                            } label: {
                                ArchivedSeasonRow(season: season)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button("Delete this season", systemImage: "trash", role: .destructive) {
                                    pendingDelete = season
                                }
                            }
                        }
                    }
                    .padding(20)
                }
            }
            .background(Color.sproutBackground.ignoresSafeArea())
            .navigationTitle("Past Seasons")
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
        .sheet(item: $selectedSeason) { season in
            ArchivedSeasonDetailView(season: season)
        }
        .alert("Delete this season?", isPresented: Binding(
            get: { pendingDelete != nil },
            set: { if !$0 { pendingDelete = nil } }
        ), presenting: pendingDelete) { season in
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                HapticFeedback.warning()
                store.removeArchivedHolidaySeason(season)
                pendingDelete = nil
            }
        } message: { season in
            Text("\(season.label) and its \(season.purchaseCount) gift\(season.purchaseCount == 1 ? "" : "s") will be removed. This can't be undone.")
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

private struct ArchivedSeasonRow: View {
    let season: HolidaySeason

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(season.label)
                        .font(.system(.title3, design: .serif, weight: .semibold))
                        .foregroundStyle(Color.sproutText)

                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(Color.sproutTextMuted)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.sproutTextMuted)
            }

            HStack(spacing: 10) {
                pill(title: "Spent", value: SproutFormatters.currency(season.spent), tint: .sproutText)

                pill(
                    title: season.hasBudget ? (season.remaining < .zero ? "Over" : "Left") : "Budget",
                    value: season.hasBudget
                        ? SproutFormatters.currency(season.remaining.magnitude)
                        : "Not set",
                    tint: season.hasBudget && season.remaining < .zero ? .sproutRed : .sproutText
                )
            }
        }
        .padding(16)
        .background(Color.sproutCard, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.sproutBorder, lineWidth: 1))
    }

    private var subtitle: String {
        let gifts = season.purchaseCount
        let people = season.recipients.count
        let giftText = "\(gifts) gift\(gifts == 1 ? "" : "s")"
        guard people > 0 else { return "\(giftText) saved" }
        return "\(giftText) for \(people) \(people == 1 ? "person" : "people")"
    }

    private func pill(title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.sproutTextMuted)
                .textCase(.uppercase)

            Text(value)
                .font(.system(.subheadline, design: .rounded, weight: .bold))
                .foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.sproutBerryLight, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct ArchivedSeasonDetailView: View {
    @Environment(\.dismiss) private var dismiss

    let season: HolidaySeason

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    header

                    if season.purchases.isEmpty {
                        Text("No gifts were logged in this season.")
                            .font(.subheadline)
                            .foregroundStyle(Color.sproutTextMuted)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 24)
                    } else {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(season.purchasesNewestFirst.enumerated()), id: \.element.id) { index, purchase in
                                let recipient = season.recipient(with: purchase.recipientID)

                                HStack(alignment: .center, spacing: 12) {
                                    Text(recipient?.emoji ?? "🎁")
                                        .font(.title3)
                                        .frame(width: 40, height: 40)
                                        .background(Color.sproutCardSoft, in: Circle())

                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(purchase.name)
                                            .font(.body.weight(.semibold))
                                            .foregroundStyle(Color.sproutText)
                                            .lineLimit(1)

                                        Text("\(recipient?.name ?? "Not for one person") · \(SproutDate.shortDate(purchase.date))")
                                            .font(.footnote)
                                            .foregroundStyle(Color.sproutTextMuted)
                                            .lineLimit(1)
                                    }

                                    Spacer(minLength: 10)

                                    Text(SproutFormatters.currency(purchase.amount))
                                        .font(.system(.subheadline, design: .rounded, weight: .bold))
                                        .foregroundStyle(Color.sproutText)
                                }
                                .padding(.vertical, 12)
                                .accessibilityElement(children: .combine)

                                if index < season.purchases.count - 1 {
                                    Divider()
                                        .padding(.leading, 54)
                                }
                            }
                        }
                    }
                }
                .padding(20)
            }
            .background(Color.sproutBackground.ignoresSafeArea())
            .navigationTitle(season.label)
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
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("SPENT")
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.white.opacity(0.80))

            Text(SproutFormatters.currency(season.spent))
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                .foregroundStyle(Color.white)
                .minimumScaleFactor(0.7)

            Text(season.hasBudget
                 ? "of a \(SproutFormatters.currency(season.budget)) budget"
                 : "No budget was set for this season")
                .font(.caption.weight(.medium))
                .foregroundStyle(Color.white.opacity(0.85))

            if let closedAt = season.closedAt, closedAt > .distantPast {
                Text("Closed \(SproutDate.shortDate(closedAt))")
                    .font(.caption)
                    .foregroundStyle(Color.white.opacity(0.75))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(AppSection.holiday.heroGradient, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}
