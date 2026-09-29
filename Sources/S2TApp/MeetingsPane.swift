import AppKit
import SwiftUI
import CoreText
import UniformTypeIdentifiers
import S2TCore

@MainActor final class MeetingsPane: NSHostingController<MeetingsView> {
    let navigation: MeetingPageNavigation
    init(state: AppState) {
        let navigation = MeetingPageNavigation()
        self.navigation = navigation
        super.init(rootView: MeetingsView(state: state, meetings: state.meetings, navigation: navigation))
        sizingOptions = []
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }
}

@MainActor final class MeetingPageNavigation: ObservableObject {
    @Published var showingModels = false
}

struct MeetingsView: View {
    @ObservedObject var state: AppState
    @ObservedObject var meetings: MeetingRecorder
    @ObservedObject var navigation: MeetingPageNavigation
    @State private var title = ""
    @State private var speakerDrafts: [String: String] = [:]
    @State private var showingSpeakers = false
    @State private var showingOriginal = false
    var body: some View {
        if navigation.showingModels { MeetingModelsView(state: state, meetings: meetings) { navigation.showingModels = false } }
        else { library }
    }
    private var library: some View {
        VStack(alignment: .leading, spacing: 18) {
            if meetings.isActive {
                Text(MeetingRecord.timestamp(meetings.elapsed)).monospacedDigit()
            }
            if !meetings.error.isEmpty {
                Text(meetings.error).foregroundStyle(.red).textSelection(.enabled)
            }
            if meetings.records.isEmpty {
                ContentUnavailableView {
                    Label("No meetings yet", systemImage: "person.2.wave.2")
                } description: {
                    Text("Record a conversation to get a transcript with speakers.")
                } actions: {
                    Button(meetings.starting ? "Starting…" : "Record meeting") { meetings.start(state: state) }
                        .disabled(meetings.isActive || state.phase.busy || state.phase == .recording)
                }
            } else {
            HSplitView {
                List(selection: $meetings.selectedID) {
                    ForEach(meetings.records) { record in
                        VStack(alignment: .leading, spacing: 5) {
                            Text(record.title).lineLimit(2)
                            Text(record.createdAt.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                        }.padding(.vertical, 5).tag(record.id)
                    }
                }.frame(minWidth: 150, idealWidth: 200, maxWidth: 240)
                    .accessibilityLabel("Saved meetings")
                VStack(alignment: .leading, spacing: 12) {
                    if let record = meetings.selected {
                        HStack {
                            TextField("Meeting title", text: $title).font(.headline)
                                .textFieldStyle(.roundedBorder).onSubmit { meetings.renameMeeting(title) }
                            if meetings.processing { ProgressView().controlSize(.small).accessibilityLabel("Transcribing meeting") }
                            if record.chunks.contains(where: { $0.ready && (!$0.completed || (record.processingSettings?.enabled == true && $0.processingCompleted != true)) }) {
                                Button("Retry") { meetings.retry(state: state) }.disabled(meetings.processing)
                            }
                            Menu {
                                Button("Rename speakers") { showingSpeakers.toggle() }
                                if record.processingSettings?.enabled == true {
                                    Toggle("Original transcript", isOn: $showingOriginal)
                                }
                            } label: { Image(systemName: "ellipsis") }
                                .menuIndicator(.hidden).fixedSize().accessibilityLabel("Transcript options")
                            Menu("Export") {
                                ForEach(MeetingExport.Format.allCases, id: \.self) { format in
                                    Button(format.title) {
                                        do { try MeetingExport.save(exportRecord(record), format: format) }
                                        catch { meetings.error = error.localizedDescription }
                                    }
                                }
                            }.disabled(record.utterances.isEmpty)
                        }
                        if record.processingSettings?.enabled == true {
                            if let issue = record.chunks.compactMap(\.processingError).first { Text(issue).font(.caption).foregroundStyle(.red) }
                        }
                        if showingSpeakers {
                            ScrollView {
                                VStack(alignment: .leading) {
                                    ForEach(record.speakers, id: \.self) { speaker in
                                        HStack {
                                            Text(speaker).font(.caption).frame(maxWidth: 150, alignment: .leading)
                                            TextField("Name", text: Binding(get: { speakerDrafts[speaker] ?? record.name(for: speaker) }, set: { speakerDrafts[speaker] = $0 }))
                                                .onSubmit { meetings.renameSpeaker(speaker, name: speakerDrafts[speaker] ?? record.name(for: speaker)) }
                                                .help("Press Return to save the speaker name")
                                        }
                                    }
                                }
                            }.frame(maxHeight: 150)
                        }
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 18) {
                                if record.utterances.isEmpty {
                                    Text(meetings.isActive ? "The first transcript appears after two minutes, or when you stop." : "No transcript yet. Saved audio remains available for retry.")
                                        .foregroundStyle(.secondary).padding(.top, 24)
                                }
                                ForEach(record.utterances.sorted { $0.start < $1.start }) { utterance in
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text("\(MeetingRecord.timestamp(utterance.start))  \(record.name(for: utterance.speaker))")
                                            .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                                        Text(showingOriginal ? utterance.text : utterance.displayText).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                }
                            }.padding(.vertical, 16)
                        }
                    } else {
                        Text("Your recorded meetings will appear here.").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }.padding(.leading, 14).frame(minWidth: 320)
            }
            }
        }
        .padding(24)
        .background(.background)
        .nativeGlassButtons()
        .onAppear { title = meetings.selected?.title ?? "" }
        .onChange(of: meetings.selectedID) { _, _ in title = meetings.selected?.title ?? ""; speakerDrafts = [:]; showingSpeakers = false; showingOriginal = false }
        .accessibilityIdentifier("meetings.pane")
    }
    private func exportRecord(_ record: MeetingRecord) -> MeetingRecord {
        guard showingOriginal else { return record }
        var original = record
        for index in original.utterances.indices { original.utterances[index].processedText = nil }
        return original
    }
}

@MainActor enum MeetingExport {
    enum Format: String, CaseIterable {
        case markdown = "md", pdf, word = "docx", text = "txt", rtf
        var title: String {
            switch self { case .markdown: return "Markdown"; case .pdf: return "PDF"; case .word: return "Word"; case .text: return "Plain text"; case .rtf: return "Rich text" }
        }
        var type: UTType { UTType(filenameExtension: rawValue) ?? .data }
    }
    static func save(_ record: MeetingRecord, format: Format) throws {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [format.type]
        panel.nameFieldStringValue = record.title.replacingOccurrences(of: "/", with: "-") + "." + format.rawValue
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try data(record, format: format).write(to: url, options: .atomic)
    }
    static func data(_ record: MeetingRecord, format: Format) throws -> Data {
        if format == .markdown { return Data(record.markdown.utf8) }
        if format == .text { return Data(record.plainText.utf8) }
        let paragraph = NSMutableParagraphStyle(); paragraph.paragraphSpacing = 8
        let attributed = NSAttributedString(string: record.plainText, attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.black, .paragraphStyle: paragraph])
        if format == .word || format == .rtf {
            return try attributed.data(from: NSRange(location: 0, length: attributed.length), documentAttributes: [.documentType: format == .word ? NSAttributedString.DocumentType.officeOpenXML : .rtf])
        }
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data) else { throw ServiceError.message("Could not create the PDF.") }
        var page = CGRect(x: 0, y: 0, width: 595, height: 842)
        guard let context = CGContext(consumer: consumer, mediaBox: &page, nil) else { throw ServiceError.message("Could not create the PDF.") }
        let framesetter = CTFramesetterCreateWithAttributedString(attributed)
        var position = 0
        while position < attributed.length {
            context.beginPDFPage(nil)
            let path = CGPath(rect: page.insetBy(dx: 48, dy: 48), transform: nil)
            let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: position, length: 0), path, nil)
            CTFrameDraw(frame, context)
            let visible = CTFrameGetVisibleStringRange(frame)
            guard visible.length > 0 else { context.endPDFPage(); context.closePDF(); throw ServiceError.message("A transcript paragraph could not fit in the PDF.") }
            position += visible.length; context.endPDFPage()
        }
        context.closePDF(); return data as Data
    }
}
