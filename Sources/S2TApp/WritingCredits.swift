import Foundation
import S2TCore

extension AppState {
    /// The authenticated service catalog remains authoritative; the server rechecks every request.
    func supportsWritingCreditModel(provider: ProcessingProvider, model: String, host: String) -> Bool {
        guard [.openRouter, .xai].contains(provider), provider.validModelID(model) else { return false }
        if provider == .openRouter && creditOpenRouterCatalog { return true }
        return creditModels.contains { $0.operation == "cleanup" && $0.provider == provider.rawValue && $0.model == model && $0.host == (provider == .openRouter ? host : "") }
    }
}

extension WritingEditor {
    func selectFunding(_ funding: WritingFunding) {
        guard !busy else { return }
        var next = settings
        next.funding = funding
        if funding == .credits, next.credit == nil,
           !state.supportsWritingCreditModel(provider: next.selectedProvider, model: next.model, host: next.selectedHost),
           let first = state.creditModels.first(where: { $0.operation == "cleanup" && ["openrouter", "xai"].contains($0.provider) }) {
            next.creditSettings = .init(provider: first.provider, model: first.model, host: first.host)
        }
        settings = next
        if funding == .credits, !state.isPreview { Task { await state.refreshCredits() } }
    }

    func canSelectModel(_ choice: WritingModelChoice) -> Bool {
        state.isProviderVisible(choice.provider.rawValue) && (!state.isProviderVisible("s2t") || !settings.usesCredits || state.supportsWritingCreditModel(provider: choice.provider, model: choice.model, host: choice.host))
    }

    var creditModelChoices: [WritingModelChoice] {
        var choices = state.creditModels.compactMap { entry -> WritingModelChoice? in
            guard entry.operation == "cleanup", let provider = ProcessingProvider(rawValue: entry.provider),
                  [.openRouter, .xai].contains(provider) else { return nil }
            return .init(provider: provider, model: entry.model, title: entry.title, host: entry.host)
        }
        if state.creditOpenRouterCatalog {
            choices += ModelRecommendations.cleanup.map { .init(provider: .openRouter, model: $0.model, title: $0.title, host: $0.host, detail: $0.detail) }
            choices += state.routerTextModels.map { .init(provider: .openRouter, model: $0.id, title: $0.name) }
            choices += favorites.compactMap { favorite in
                guard favorite.hasPrefix("openrouter|") else { return nil }
                let model = String(favorite.dropFirst("openrouter|".count))
                return .init(provider: .openRouter, model: model, title: model)
            }
        }
        choices.append(.init(provider: settings.selectedProvider, model: settings.model, title: settings.model, host: settings.selectedHost))
        var seen = Set<String>()
        return choices.filter { canSelectModel($0) && seen.insert($0.id).inserted }
    }
}
