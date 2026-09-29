import AppKit
import Foundation
import S2TCore

extension AppState {
    func applyCreditBalance(_ balance: CreditBalance) {
        creditBalance = balance
        creditStatusRefreshable = balance.paused || balance.frozen || balance.available <= 0 || (balance.keyLimit?.remainingCredits.map { $0 <= 0 } ?? false)
        creditOpenRouterCatalog = balance.openRouterCatalog == true
        creditModels = balance.models ?? CreditModel.defaults
        let defaultCleanup = CreditModel.defaults[0]
        if !creditOpenRouterCatalog, creditCleanupProvider == .openRouter,
           creditCleanupModel == defaultCleanup.model, creditCleanupHost.isEmpty,
           !creditModels.contains(where: { $0.provider == "openrouter" && $0.operation == "cleanup" && $0.model == creditCleanupModel && $0.host.isEmpty }),
           creditModels.contains(where: { $0.id == defaultCleanup.id }) {
            creditCleanupHost = defaultCleanup.host
        }
    }
    func usesCredits(for category: String) -> Bool {
        category == "speech" ? speechUsesCredits : category == "text" && cleanupUsesCredits
    }

    func setUsesCredits(_ enabled: Bool, for category: String) {
        if category == "speech" { speechUsesCredits = enabled }
        else if category == "text" { cleanupUsesCredits = enabled }
    }

    func saveCreditsKey() {
        guard !phase.busy, phase != .recording else { return }
        creditsKey = creditsKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let revision = UUID()
        keyRevisions["s2t"] = revision
        let connection: CreditConnection
        do {
            guard !creditsAddress.isEmpty else { throw ServiceError.message("This build has no S2T credits service configured.") }
            connection = try CreditConnection(address: creditsAddress, key: creditsKey)
            guard creditsChecksEnabled else { throw ServiceError.message("Network checks are disabled in preview.") }
        } catch { keyStatuses["s2t"] = .issue(error.localizedDescription); return }
        keyStatuses["s2t"] = .checking
        keyChecks["s2t"] = Task { [weak self, creditsAPI] in
            do {
                let balance = try await creditsAPI.balance(connection)
                try Task.checkCancellation()
                guard let self, self.keyRevisions["s2t"] == revision else { return }
                guard self.phase != .recording, !self.phase.busy else {
                    self.keyStatuses["s2t"] = .issue("Finish dictation, then save the key again.")
                    self.keyChecks["s2t"] = nil
                    return
                }
                if !self.isPreview {
                    let encoded = String(decoding: try JSONEncoder().encode(connection), as: UTF8.self)
                    try Keychain.save(encoded, account: "s2t-credits-connection")
                }
                self.creditConnection = connection
                self.applyCreditBalance(balance)
                self.savedKeyAccounts.insert("s2t")
                self.keyStatuses["s2t"] = Self.creditStatus(balance)
                self.keyChecks["s2t"] = nil
            } catch {
                guard !Task.isCancelled, let self, self.keyRevisions["s2t"] == revision else { return }
                self.keyStatuses["s2t"] = .issue(error.localizedDescription)
                self.keyChecks["s2t"] = nil
            }
        }
    }

    func refreshCredits(force: Bool = false) async {
        guard let connection = creditConnection, creditsChecksEnabled, keyStatuses["s2t"] != .checking,
              connection.key == creditsKey, savedKeyAccounts.contains("s2t"), (force || keyStatuses["s2t"]?.needsAttention != true || creditStatusRefreshable) else { return }
        let revision = keyRevisions["s2t"]
        do {
            await refreshHistoricalStreamingReceipts()
            let balance = try await creditsAPI.balance(connection)
            guard keyRevisions["s2t"] == revision else { return }
            applyCreditBalance(balance)
            keyStatuses["s2t"] = Self.creditStatus(balance)
        } catch {
            guard keyRevisions["s2t"] == revision else { return }
            creditBalance = nil
            creditStatusRefreshable = (error as? CreditAccountError)?.automaticallyRefreshable ?? true
            keyStatuses["s2t"] = .issue(error.localizedDescription)
        }
    }

    func improveWritingWithCredits(_ text: String, kind: WritingDocumentKind, instruction: String,
                                   settings: WritingAISettings, requestID: String) async throws -> String {
        guard creditsChecksEnabled, let connection = creditConnection else {
            throw ServiceError.message("Connect your S2T account in API keys to use credits for Writing.")
        }
        let model = settings.model.trimmingCharacters(in: .whitespacesAndNewlines)
        let host = settings.isOpenRouter ? settings.selectedHost.trimmingCharacters(in: .whitespacesAndNewlines) : ""
        guard settings.usesCredits, supportsWritingCreditModel(provider: settings.selectedProvider, model: model, host: host) else {
            throw ServiceError.message("This model and host are not available with S2T credits. Choose an available Writing model or refresh your S2T account in API keys.")
        }
        defer { Task { await refreshCredits() } }
        do {
            return try await creditsAPI.improveWritingDocument(text, kind: kind, instruction: instruction,
                model: model, endpoint: host, options: settings.router, provider: settings.selectedProvider,
                connection: connection, requestID: requestID)
        } catch {
            if !(error is CancellationError) { recordKeyFailure(error, using: connection.key) }
            throw error
        }
    }

    private static func creditStatus(_ balance: CreditBalance) -> APIKeyStatus {
        if balance.frozen { return .issue("Your S2T account is frozen. Open your S2T account for details.") }
        if balance.paused { return .issue("S2T billing is temporarily paused while a billing issue is checked. Your API key is still saved.") }
        if balance.available <= 0 { return .issue("No S2T credits available. Open your S2T account to add credits.") }
        if let limit = balance.keyLimit, let remaining = limit.remainingCredits, remaining <= 0 {
            let reset = limit.resetsAt.map { " Resets " + Date(timeIntervalSince1970: $0 / 1000).formatted() + "." } ?? ""
            return .issue("This key has reached its credit limit." + reset + " Manage limits in your S2T account.")
        }
        return .accepted
    }

    func loadSavedKeys(allowInteraction: Bool = false) {
        guard !isPreview else { return }
        savedKeysLocked = false
        for account in APIAccount.allCases {
            if !keyValue(account.rawValue).isEmpty && !savedKeyAccounts.contains(account.rawValue) { continue }
            do {
                let value = try Keychain.read(account.rawValue, allowInteraction: allowInteraction)
                guard !value.isEmpty else { continue }
                switch account {
                case .artificialAnalysis: artificialAnalysisKey = value
                case .assemblyAI: assemblyKey = value
                case .xai: xaiKey = value
                case .openRouter: routerKey = value
                case .typeSafe: typeSafeKey = value
                }
                savedKeyAccounts.insert(account.rawValue)
                keyStatuses[account.rawValue] = nil
            } catch {
                savedKeysLocked = true
                keyStatuses[account.rawValue] = .issue("Saved key is locked. Choose Unlock saved keys under API keys. Existing keys are preserved.")
                if allowInteraction { break }
            }
        }
        if allowInteraction && !savedKeysLocked && clipboardMonitor.persistenceError != nil {
            do {
                _ = try Keychain.read("clipboard-history-encryption", allowInteraction: true)
                if clipboardContextEnabled { clipboardMonitor.poll() }
            } catch { savedKeysLocked = true }
        }
        if creditsKey.isEmpty || savedKeyAccounts.contains("s2t") {
            do {
                let saved = try Keychain.read("s2t-credits-connection", allowInteraction: allowInteraction)
                if !saved.isEmpty {
                    let decoded = try JSONDecoder().decode(CreditConnection.self, from: Data(saved.utf8))
                    creditConnection = try CreditConnection(address: decoded.origin.absoluteString, key: decoded.key)
                    creditsAddress = decoded.origin.absoluteString
                    creditsKey = decoded.key
                    savedKeyAccounts.insert("s2t")
                    keyStatuses["s2t"] = nil
                }
            } catch {
                savedKeysLocked = true
                keyStatuses["s2t"] = .issue("Saved S2T key is locked or unreadable. Choose Unlock saved keys to reconnect. Your saved key is preserved.")
            }
        }
        credentialsSaved = !transcriptionKey.isEmpty
    }

    var processingKey: String {
        switch processingProvider {
        case .xai: return xaiKey
        case .openRouter: return routerKey
        case .local, .codex, nil: return ""
        }
    }
    func keyEdited(_ account: String) {
        if account == "s2t" { creditStatusRefreshable = false; creditBalance = nil; creditModels = CreditModel.defaults }
        savedKeyAccounts.remove(account)
        keyChecks[account]?.cancel()
        keyChecks[account] = nil
        keyRevisions[account] = UUID()
        keyStatuses[account] = nil
    }

    func keyValue(_ account: String) -> String {
        switch account {
        case "artificialanalysis": return artificialAnalysisKey
        case "s2t": return creditsKey
        case "assemblyai": return assemblyKey
        case "xai": return xaiKey
        case "openrouter": return routerKey
        case "typesafe": return typeSafeKey
        default: return ""
        }
    }

    @discardableResult func clearAPIKey(account: String) -> Bool {
        guard !savedKeysLocked, !phase.busy, phase != .recording,
              account == "s2t" || APIAccount(rawValue: account) != nil else { return false }
        do {
            if !isPreview { try Keychain.save("", account: account == "s2t" ? "s2t-credits-connection" : account) }
        } catch {
            keyStatuses[account] = .issue("Could not remove the saved key. \(error.localizedDescription)")
            return false
        }
        switch account {
        case "s2t": creditsKey = ""; creditConnection = nil
        case "artificialanalysis": artificialAnalysisKey = ""
        case "assemblyai": assemblyKey = ""
        case "xai": xaiKey = ""
        case "openrouter": routerKey = ""
        case "typesafe": typeSafeKey = ""
        default: break
        }
        keyEdited(account)
        credentialsSaved = !transcriptionKey.isEmpty
        return true
    }

    func saveAPIKey(account: String) {
        guard !savedKeysLocked, !phase.busy, phase != .recording else { return }
        if keyValue(account).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            clearAPIKey(account: account)
            return
        }
        if account == "s2t" { saveCreditsKey(); return }
        guard let provider = APIAccount(rawValue: account) else { return }
        let value = keyValue(account).trimmingCharacters(in: .whitespacesAndNewlines)
        switch provider {
        case .artificialAnalysis: artificialAnalysisKey = value
        case .assemblyAI: assemblyKey = value
        case .xai: xaiKey = value
        case .openRouter: routerKey = value
        case .typeSafe: typeSafeKey = value
        }
        do {
            if !isPreview { try Keychain.save(value, account: account) }
            savedKeyAccounts.insert(account)
            credentialsSaved = !transcriptionKey.isEmpty
        } catch {
            keyStatuses[account] = .issue("Could not save in Keychain. \(error.localizedDescription)")
            return
        }
        let revision = UUID()
        keyRevisions[account] = revision
        keyStatuses[account] = .checking
        keyChecks[account] = Task { [weak self, api] in
            let status: APIKeyStatus
            do {
                try await api.validateKey(value, account: provider)
                status = .accepted
            } catch is CancellationError { return }
            catch {
                if case .account = error as? ServiceError {
                    status = .issue(error.localizedDescription)
                } else {
                    status = .issue("Couldn't check the key. Check your connection or try saving again.")
                }
            }
            guard !Task.isCancelled, let self, self.keyRevisions[account] == revision else { return }
            self.keyStatuses[account] = status
            self.keyChecks[account] = nil
        }
    }

    @discardableResult func recordKeyFailure(_ error: Error, using value: String) -> Bool {
        if let error = error as? CreditAccountError {
            guard creditConnection?.key == value, creditsKey == value else { return true }
            creditBalance = nil
            creditStatusRefreshable = error.automaticallyRefreshable
            keyChecks["s2t"]?.cancel()
            keyRevisions["s2t"] = UUID()
            keyStatuses["s2t"] = .issue(error.localizedDescription)
            return true
        }
        guard case .account(let account, _) = error as? ServiceError else { return false }
        guard keyValue(account.rawValue).trimmingCharacters(in: .whitespacesAndNewlines) == value else { return true }
        keyChecks[account.rawValue]?.cancel()
        keyRevisions[account.rawValue] = UUID()
        keyStatuses[account.rawValue] = .issue(error.localizedDescription)
        return true
    }

    func recordKeySuccess(account: String, using value: String) {
        guard keyValue(account).trimmingCharacters(in: .whitespacesAndNewlines) == value else { return }
        keyChecks[account]?.cancel()
        keyRevisions[account] = UUID()
        keyStatuses[account] = .accepted
    }

}
