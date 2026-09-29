import SwiftUI
import S2TCore

struct DictionaryListView: View {
    @ObservedObject var editing: WritingEditor
    @State private var search = ""
    @State private var newTerm = ""
    @State private var newContext = ""
    @State private var newReplaces = ""
    @State private var filter = "All"
    @FocusState private var newField: NewField?

    private enum NewField { case term, replaces, context }
    private var entries: [DictionaryListEntry] { editing.dictionaryEntries }
    private var filtered: [DictionaryListEntry] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        let subset = entries.filter { filter == "All" || (filter == "Corrections" ? $0.learnedFrom != nil : $0.learnedFrom == nil) }
        guard !query.isEmpty else { return subset }
        return subset.filter {
            $0.term.localizedCaseInsensitiveContains(query)
                || $0.context.localizedCaseInsensitiveContains(query)
                || ($0.learnedFrom?.localizedCaseInsensitiveContains(query) ?? false)
                || $0.categories.compactMap { DictionaryCategory.title(for: $0) }.contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }

    var body: some View {
        GeometryReader { geometry in
            let wordWidth = min(190, max(120, geometry.size.width * 0.27))
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 16) {
                    Text("Words").font(.system(size: 16, weight: .semibold))
                    Picker("Show entries", selection: $filter) {
                        Text("All").tag("All"); Text("Corrections").tag("Corrections"); Text("Words").tag("Words")
                    }.labelsHidden().frame(width: 115).accessibilityIdentifier("dictionary.filter")
                    Spacer()
                    HStack(spacing: 7) {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField("Search dictionary", text: $search)
                            .textFieldStyle(.plain)
                            .accessibilityIdentifier("dictionary.search")
                        if !search.isEmpty {
                            Button { search = "" } label: { Image(systemName: "xmark.circle.fill") }
                                .buttonStyle(.plain).foregroundStyle(.secondary).accessibilityLabel("Clear search")
                        }
                    }
                    .padding(.horizontal, 10).frame(maxWidth: 230).frame(height: 30)
                    .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
                }.padding(.top, 20).padding(.bottom, 18)

                HStack(spacing: 10) {
                    TextField("Add a word or name", text: $newTerm)
                        .focused($newField, equals: .term).frame(width: wordWidth)
                        .accessibilityLabel("New word").accessibilityIdentifier("dictionary.new.term")
                    TextField("Often heard as", text: $newReplaces)
                        .focused($newField, equals: .replaces).frame(width: wordWidth)
                        .accessibilityLabel("Often heard as, optional").accessibilityIdentifier("dictionary.new.replaces")
                    TextField("Context, optional", text: $newContext)
                        .focused($newField, equals: .context)
                        .accessibilityLabel("Context for new word").accessibilityIdentifier("dictionary.new.context")
                    Button("Add", action: add)
                        .buttonStyle(.borderedProminent)
                        .disabled(newTerm.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !editing.enabled)
                        .accessibilityLabel("Add word").accessibilityIdentifier("dictionary.add")
                }
                .textFieldStyle(.roundedBorder).controlSize(.large)
                .disabled(!editing.enabled).onSubmit { add() }
                .padding(.bottom, 22)

                HStack(spacing: 10) {
                    Text("Word or name").frame(width: wordWidth, alignment: .leading)
                    Text("Often heard as").frame(width: wordWidth, alignment: .leading)
                    Text("Context").frame(maxWidth: .infinity, alignment: .leading)
                    Color.clear.frame(width: 28, height: 1)
                }
                .font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                .padding(.horizontal, 8).padding(.bottom, 10)
                Divider()
                ScrollView {
                    LazyVStack(spacing: 0) {
                        if filtered.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(search.isEmpty ? "Names worth getting right" : "No matching words")
                                    .font(.system(size: 14, weight: .medium))
                                Text(search.isEmpty ? "Add names, terms and preferred spellings above." : "Try another word or clear the search.")
                                    .font(.system(size: 12)).foregroundStyle(.secondary)
                            }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 32).padding(.horizontal, 8)
                        } else {
                            ForEach(filtered) { entry in
                                DictionaryEntryRow(entry: entry, wordWidth: wordWidth, enabled: editing.enabled,
                                    update: { editing.updateDictionaryEntry(entry, term: $0, context: $1, replaces: $2) },
                                    remove: { editing.removeDictionaryEntry(entry) })
                                Divider().opacity(0.45)
                            }
                        }
                    }.padding(.top, 2)
                }.frame(maxHeight: .infinity)
            }
        }
        .accessibilityIdentifier("dictionary.list")
    }

    private func add() {
        guard !newTerm.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              editing.addDictionaryEntry(term: newTerm, context: newContext, replaces: newReplaces) else { return }
        newTerm = ""
        newContext = ""
        newReplaces = ""
        newField = .term
    }
}

private struct DictionaryEntryRow: View {
    let entry: DictionaryListEntry
    let wordWidth: CGFloat
    let enabled: Bool
    let update: (String, String, String) -> Void
    let remove: () -> Void
    @State private var term: String
    @State private var context: String
    @State private var replaces: String
    @State private var hovering = false
    @State private var confirmRemoval = false
    @FocusState private var focused: Field?

    private enum Field { case term, replaces, context }
    init(entry: DictionaryListEntry, wordWidth: CGFloat, enabled: Bool, update: @escaping (String, String, String) -> Void,
         remove: @escaping () -> Void) {
        self.entry = entry; self.wordWidth = wordWidth; self.enabled = enabled
        self.update = update; self.remove = remove
        _term = State(initialValue: entry.term); _context = State(initialValue: entry.context)
        _replaces = State(initialValue: entry.learnedFrom ?? "")
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                TextField("Word", text: $term).font(.system(size: 13, weight: .medium))
                    .focused($focused, equals: .term).accessibilityLabel("Word")
            }.frame(width: wordWidth, alignment: .leading)
            TextField("Optional", text: $replaces).font(.system(size: 12))
                .focused($focused, equals: .replaces).frame(width: wordWidth)
                .accessibilityLabel("Often heard as for \(entry.term)")
            VStack(alignment: .leading, spacing: 3) {
                TextField("Add context", text: $context).font(.system(size: 12))
                    .foregroundStyle(.secondary).focused($focused, equals: .context)
                    .accessibilityLabel("Context for \(entry.term)")
                if !entry.categories.isEmpty {
                    Text(entry.categories.compactMap { DictionaryCategory.title(for: $0) }.joined(separator: " · "))
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                        .accessibilityLabel("Categories for \(entry.term)")
                }
            }
            Button { confirmRemoval = true } label: {
                Image(systemName: "minus.circle").frame(width: 28, height: 28)
            }
            .buttonStyle(.plain).foregroundStyle(.secondary)
            .help("Remove \(entry.term)").accessibilityLabel("Remove \(entry.term)")
        }
        .textFieldStyle(.plain).padding(.horizontal, 8).frame(minHeight: 48)
        .background((focused != nil ? Color.accentColor.opacity(0.055) : Color.primary.opacity(hovering ? 0.025 : 0)), in: RoundedRectangle(cornerRadius: 6))
        .disabled(!enabled)
        .onHover { hovering = $0 }
        .onSubmit { commit() }
        .onChange(of: focused) { old, new in if old != nil && new == nil { commit() } }
        .confirmationDialog("Remove \"\(entry.term)\" from the dictionary?", isPresented: $confirmRemoval) {
            Button("Remove word", role: .destructive, action: remove)
        }
    }

    private func commit() {
        guard term != entry.term || context != entry.context || replaces != (entry.learnedFrom ?? "") else { return }
        update(term, context, replaces)
    }
}
