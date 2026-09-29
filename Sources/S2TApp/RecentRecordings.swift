import AppKit
import Combine
import SwiftUI
import S2TCore

@MainActor final class RecentRecordings: ObservableObject {
    @Published private(set) var entries: [RecentTranscript] = []
    @Published private(set) var error: String?
    private let store: TranscriptHistoryStore?
    private var loaded = false

    init(store: TranscriptHistoryStore? = nil) {
        self.store = store
        loadIfNeeded()
    }

    private func loadIfNeeded() {
        guard !loaded else { return }
        do {
            let saved = try store?.load() ?? []
            let unsavedIDs = Set(entries.map(\.id))
            entries += saved.filter { !unsavedIDs.contains($0.id) }
            loaded = true
            error = store?.notice
        } catch { self.error = "Saved transcripts could not be opened. Existing files are preserved. " + error.localizedDescription }
    }

    func record(id: UUID, text: String, appName: String?, bundleID: String?, date: Date = Date(), copiedValues: [String] = []) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        loadIfNeeded()
        let prior = entries.first { $0.id == id }
        let entry = RecentTranscript(id: id, date: prior?.date ?? date,
            text: TranscriptPrivacy.redacted(text, copiedValues: copiedValues), appName: prior?.appName ?? appName,
            bundleID: prior?.bundleID ?? bundleID, clipboardDerived: copiedValues.contains { !$0.isEmpty && text.contains($0) })
        entries.removeAll { $0.id == id }
        entries.insert(entry, at: 0)
        persist()
    }

    func remove(_ id: UUID) { loadIfNeeded(); entries.removeAll { $0.id == id }; persist() }
    func clear() {
        do { try store?.clear(); entries = []; loaded = true; error = nil }
        catch { self.error = "Some saved transcripts could not be deleted. " + error.localizedDescription }
    }
    func clearClipboardContent(_ values: [String]) {
        loadIfNeeded()
        entries.removeAll { entry in entry.clipboardDerived == true || values.contains { !$0.isEmpty && entry.text.contains($0) } }
        persist()
    }
    private func persist() {
        guard loaded else { return }
        do {
            entries = try store?.save(entries) ?? TranscriptHistoryStore.bounded(entries)
            error = store?.notice
        } catch { self.error = "Recent transcripts have unsaved changes. " + error.localizedDescription }
    }
}

final class RecentRecordingsFilter: ObservableObject {
    @Published var query = ""

    func matches(_ entry: RecentTranscript) -> Bool {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return query.isEmpty || entry.text.localizedCaseInsensitiveContains(query) ||
            entry.appName?.localizedCaseInsensitiveContains(query) == true
    }
}

struct RecentRecordingsView: View {
    @ObservedObject var history: RecentRecordings
    @ObservedObject var filter: RecentRecordingsFilter
    let copy: (String) -> Void
    @State private var copiedID: UUID?

    var visibleEntries: [RecentTranscript] { history.entries.filter(filter.matches) }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("Saved for 30 days, up to 500 transcripts.").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Clear all", role: .destructive) { history.clear() }
            }
            if let error = history.error { Text(error).foregroundStyle(.red) }
            if history.entries.isEmpty {
                ContentUnavailableView("No recordings yet", systemImage: "waveform",
                    description: Text("Your completed transcripts will appear here."))
            } else if visibleEntries.isEmpty {
                ContentUnavailableView.search(text: filter.query)
            } else {
                List {
                        ForEach(visibleEntries) { entry in
                            VStack(alignment: .leading, spacing: 10) {
                                HStack(spacing: 8) {
                                    if let bundle = entry.bundleID, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) {
                                        Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 20, height: 20)
                                    }
                                    if let name = entry.appName { Text(name).fontWeight(.medium) }
                                    Text(entry.date.formatted(date: .abbreviated, time: .shortened)).foregroundStyle(.secondary)
                                    Spacer()
                                    Button(copiedID == entry.id ? "Copied" : "Copy") { copy(entry.text); copiedID = entry.id }
                                        .accessibilityLabel("Copy transcript from \(entry.date.formatted())")
                                    Button("Delete", role: .destructive) { history.remove(entry.id) }
                                        .accessibilityLabel("Delete transcript from \(entry.date.formatted())")
                                }.font(.system(size: 12))
                                Text(entry.text).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                            }.padding(.vertical, 8)
                                .listRowBackground(Color.clear)
                        }
                }.listStyle(.inset)
                    .scrollContentBackground(.hidden)
            }
        }.padding(16).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(SettingsPageBackground())
    }
}
