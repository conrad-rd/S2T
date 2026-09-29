import Foundation
import S2TCore

@MainActor final class DictionaryLearningController {
    typealias Judge = @Sendable (DictionaryLearningPlan) async throws -> DictionaryLearningDecision
    private let judge: Judge?
    private let save: ([DictionaryCorrection]) -> Bool
    private let status: (String) -> Void
    private var task: Task<Void, Never>?
    private var revision = UUID()
    private var cache: [DictionaryCorrection: DictionaryLearningDecision] = [:]
    private var hasResult = false
    private var savedEntries: [DictionaryCorrection] = []

    init(judge: Judge? = nil, save: @escaping ([DictionaryCorrection]) -> Bool, status: @escaping (String) -> Void) {
        self.judge = judge; self.save = save; self.status = status
    }

    func invalidate() {
        revision = UUID()
        task?.cancel()
        task = nil
    }

    func finishObservation() {
        let unfinished = task != nil
        invalidate()
        if unfinished { status("Correction watching ended. Saved corrections are kept; pending categories were cancelled.") }
        else if !hasResult { status("Correction watching ended. Dictate again to learn further corrections.") }
    }

    func submit(_ corrections: [DictionaryCorrection], isCurrent: @escaping @Sendable () async -> Bool,
                onValidationFailure: @escaping () -> Void = {}) {
        invalidate()
        let generation = revision
        task = Task { [weak self] in
            guard let self else { return }
            defer { if revision == generation { task = nil } }
            guard await isCurrent() else {
                if revision == generation, !Task.isCancelled { onValidationFailure() }
                return
            }
            guard revision == generation, !Task.isCancelled else { return }
            @MainActor func accepted() -> [DictionaryCorrection] {
                corrections.map { correction in
                    if case .accepted(let entry) = self.cache[correction] { return entry }
                    return self.savedEntries.first {
                        $0.original == correction.original && $0.replacement == correction.replacement
                    } ?? correction
                }
            }
            @MainActor func persist() -> Bool {
                let entries = accepted()
                guard self.save(entries) else { return false }
                self.savedEntries = entries
                return true
            }
            guard persist() else { status("Dictionary could not be saved. Check the dictionary file and try again."); return }
            hasResult = true
            guard !corrections.isEmpty else { status("No corrections to learn."); return }
            let savedStatus = "\(corrections.count) correction(s) saved to Dictionary."
            guard let judge else { status(savedStatus); return }
            status(savedStatus + " Adding categories with Jev…")
            do {
                // Let pauses inside a word pass before starting a paid decision request.
                try await Task.sleep(nanoseconds: 600_000_000)
                for correction in corrections where cache[correction] == nil {
                    try Task.checkCancellation()
                    guard await isCurrent(), revision == generation, !Task.isCancelled else { return }
                    let decision = try await judge(DictionaryLearningPlan(correction: correction))
                    try Task.checkCancellation()
                    guard await isCurrent(), revision == generation, !Task.isCancelled else { return }
                    cache[correction] = decision
                    guard persist() else { throw ServiceError.message("The dictionary file could not be saved.") }
                }
                let categorized = accepted().filter { !$0.categories.isEmpty }.count
                status(savedStatus + (categorized > 0 ? " \(categorized) categorized." : " No confident category found."))
            } catch is CancellationError { }
            catch {
                guard await isCurrent(), revision == generation, !Task.isCancelled else { return }
                hasResult = true
                status("Corrections saved. Categorization unavailable. " + error.localizedDescription)
            }
        }
    }
}
