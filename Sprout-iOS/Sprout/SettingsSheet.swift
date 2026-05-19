import SwiftUI
import UniformTypeIdentifiers

struct SettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: BudgetStore

    @State private var isShowingCategorySettings = false
    @State private var isExportingBackup = false
    @State private var isImportingBackup = false
    @State private var exportDocument: SproutBackupDocument?
    @State private var statusMessage: SettingsStatusMessage?

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    settingsSectionTitle(
                        title: "Organize",
                        subtitle: "Keep your categories tidy and easy to recognize."
                    )

                    Button {
                        isShowingCategorySettings = true
                    } label: {
                        SettingsRow(
                            symbol: "square.grid.2x2",
                            title: "Manage Categories",
                            subtitle: "Edit names and choose icons for personal spending."
                        )
                    }
                    .buttonStyle(.plain)

                    settingsSectionTitle(
                        title: "Backup",
                        subtitle: "Export a copy of your budget data or restore from a previous backup."
                    )

                    VStack(spacing: 12) {
                        Button {
                            exportBackup()
                        } label: {
                            SettingsRow(
                                symbol: "square.and.arrow.up",
                                title: "Export Backup",
                                subtitle: "Save a JSON backup to Files or another destination."
                            )
                        }
                        .buttonStyle(.plain)

                        Button {
                            isImportingBackup = true
                        } label: {
                            SettingsRow(
                                symbol: "square.and.arrow.down",
                                title: "Import Backup",
                                subtitle: "Restore your budget data from a previous Sprout backup."
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(20)
            }
            .background(Color.sproutBackground.ignoresSafeArea())
            .navigationTitle("Settings")
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
        .sheet(isPresented: $isShowingCategorySettings) {
            CategorySettingsSheet()
                .environmentObject(store)
        }
        .fileExporter(
            isPresented: $isExportingBackup,
            document: exportDocument,
            contentType: .json,
            defaultFilename: backupFileName
        ) { result in
            switch result {
            case .success:
                statusMessage = SettingsStatusMessage(
                    title: "Backup Exported",
                    message: "Your Sprout backup was exported successfully."
                )
            case .failure(let error):
                guard !isUserCancelled(error) else { return }
                statusMessage = SettingsStatusMessage(
                    title: "Export Failed",
                    message: error.localizedDescription
                )
            }
            exportDocument = nil
        }
        .fileImporter(
            isPresented: $isImportingBackup,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                importBackup(from: url)
            case .failure(let error):
                guard !isUserCancelled(error) else { return }
                statusMessage = SettingsStatusMessage(
                    title: "Import Failed",
                    message: error.localizedDescription
                )
            }
        }
        .alert(item: $statusMessage) { status in
            Alert(
                title: Text(status.title),
                message: Text(status.message),
                dismissButton: .default(Text("OK"))
            )
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var backupFileName: String {
        "Sprout-Backup-\(dateStamp(from: Date()))"
    }

    private func exportBackup() {
        do {
            exportDocument = SproutBackupDocument(data: try store.exportBackupData())
            isExportingBackup = true
        } catch {
            statusMessage = SettingsStatusMessage(
                title: "Export Failed",
                message: error.localizedDescription
            )
        }
    }

    private func importBackup(from url: URL) {
        let didStartSecurityScope = url.startAccessingSecurityScopedResource()
        defer {
            if didStartSecurityScope {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let data = try Data(contentsOf: url)
            try store.importBackupData(data)
            statusMessage = SettingsStatusMessage(
                title: "Backup Imported",
                message: "Your Sprout data has been restored from the selected backup."
            )
        } catch {
            statusMessage = SettingsStatusMessage(
                title: "Import Failed",
                message: error.localizedDescription
            )
        }
    }

    private func settingsSectionTitle(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(.title3, design: .serif, weight: .semibold))
                .foregroundStyle(Color.sproutText)

            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(Color.sproutTextSecondary)
        }
    }

    private func dateStamp(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = .current
        formatter.locale = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private func isUserCancelled(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == NSCocoaErrorDomain && nsError.code == NSUserCancelledError
    }
}

private struct SettingsRow: View {
    let symbol: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.sageMist)
                    .frame(width: 48, height: 48)

                Image(systemName: symbol)
                    .font(.headline)
                    .foregroundStyle(Color.sageDark)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(Color.sproutText)

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(Color.sproutTextSecondary)
                    .multilineTextAlignment(.leading)
            }

            Spacer(minLength: 8)

            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.sproutTextMuted)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.sproutCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.sproutBorder, lineWidth: 1)
        )
        .shadow(color: Color.sproutShadow, radius: 14, x: 0, y: 8)
    }
}

private struct SettingsStatusMessage: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}
