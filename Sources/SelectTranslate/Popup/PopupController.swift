import AppKit
import KeyboardShortcuts
import SelectedTextKit
import Translation
import os

/// Glues gesture detection, selection reading, the button and the result panel together.
@MainActor
final class PopupController {
    private let settings = AppSettings.shared
    private let monitor = SelectionMonitor()
    private let button = PopupButtonPanel()
    private lazy var panel = TranslationPanel()
    private var pending: Task<Void, Never>?
    private var translation: Task<Void, Never>?
    private var dismissMonitors: [Any] = []
    private var started = false
    private var current: SelectionSnapshot?
    private let log = Logger(subsystem: "app.selecttranslate", category: "popup")

    private enum Route {
        case apple
        case online(appleStatus: LanguageAvailability.Status)
    }

    func start() {
        guard !started, AccessibilityPermission.isTrusted else { return }
        started = true

        monitor.onSelectionGesture = { [weak self] location in self?.selectionGesture(at: location) }
        monitor.onDoubleCopy = { [weak self] in self?.doubleCopy() }
        monitor.start()

        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown], handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.pointerClickedElsewhere() }
        }) { dismissMonitors.append(monitor) }

        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: [.scrollWheel], handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.button.hide() }
        }) { dismissMonitors.append(monitor) }

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.button.hide() }
        }

        KeyboardShortcuts.onKeyUp(for: .translateSelection) { [weak self] in
            self?.translateSelectionNow()
        }

        panel.model.onRetarget = { [weak self] language in self?.retranslate(to: language) }
        panel.model.onRetry = { [weak self] in self?.retry() }
        panel.model.onDownloadPack = { [weak self] in self?.downloadPack() }
        panel.model.onDismissPackSuggestion = { [weak self] in self?.dismissPackSuggestion() }
        log.notice("Selection monitoring started")
    }

    /// Menu item / keyboard shortcut entry point.
    func translateSelectionNow() {
        guard AccessibilityPermission.isTrusted else { return }
        Task { [weak self] in
            let mouse = NSEvent.mouseLocation
            guard let text = await SelectionReader.readText(strategies: [.auto, .shortcut]) else { return }
            self?.translate(SelectionReader.snapshot(text: text, mouse: mouse))
        }
    }

    // MARK: Triggers

    private var frontmostIsExcluded: Bool {
        guard let id = NSWorkspace.shared.frontmostApplication?.bundleIdentifier else { return false }
        return id == Bundle.main.bundleIdentifier || settings.excludedBundleIDs.contains(id)
    }

    private func pointerClickedElsewhere() {
        pending?.cancel()
        button.hide()
        panel.hide()
    }

    private func selectionGesture(at location: NSPoint) {
        guard settings.popupEnabled, !frontmostIsExcluded else { return }
        pending?.cancel()
        let delay = settings.popupDelay
        pending = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(Int(delay * 1000)))
            guard let self, !Task.isCancelled else { return }
            guard let text = await SelectionReader.readText(strategies: [.auto]) else {
                self.button.hide()
                return
            }
            guard !Task.isCancelled, !self.isAlreadyInTargetLanguage(text) else { return }
            let snapshot = SelectionReader.snapshot(text: text, mouse: location)
            self.current = snapshot
            self.button.show(for: snapshot) { [weak self] in self?.translate(snapshot) }
        }
    }

    /// Nothing to offer when the selection is confidently in the target language already —
    /// unless second-language mode is on, in which case that's exactly what the user wants translated.
    private func isAlreadyInTargetLanguage(_ text: String) -> Bool {
        guard settings.secondLanguage == nil,
              let detected = LanguageDetector.detect(text, minimumConfidence: 0.7) else { return false }
        return detected.isEquivalent(to: settings.targetLanguage)
    }

    private func doubleCopy() {
        guard settings.doubleCopyEnabled, !frontmostIsExcluded else { return }
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(120))
            guard let self,
                  let text = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !text.isEmpty else { return }
            self.translate(SelectionReader.snapshot(text: text, mouse: NSEvent.mouseLocation))
        }
    }

    // MARK: Translating

    private func translate(_ snapshot: SelectionSnapshot, to explicitTarget: Locale.Language? = nil) {
        button.hide()
        current = snapshot

        let hints = [settings.targetLanguage, settings.secondLanguage].compactMap { $0 }
        let detected = LanguageDetector.detect(snapshot.text, hints: hints)
        var plan = LanguageDirection.plan(detected: detected, settings: settings)
        if let explicitTarget { plan = TranslationPlan(source: detected, target: explicitTarget) }

        panel.model.begin(text: snapshot.text, source: plan.source ?? detected, target: plan.target)
        if !panel.isVisible { panel.show(anchoredTo: snapshot) }

        translation?.cancel()
        translation = Task { [weak self] in
            guard let self else { return }
            let route = await self.route(text: snapshot.text, plan: plan)
            guard !Task.isCancelled else { return }
            switch route {
            case .apple:
                await self.translateWithApple(snapshot.text, plan: plan, detected: detected)
            case .online(let appleStatus):
                await self.translateOnline(snapshot.text, plan: plan, detected: detected, appleStatus: appleStatus)
            }
        }
    }

    /// Apple when the pack is installed (instant, offline); OpenRouter otherwise — unless the user said always/never.
    private func route(text: String, plan: TranslationPlan) async -> Route {
        guard settings.onlineTranslationAvailable else { return .apple }
        let status = await TranslationEngine.shared.appleStatus(text: text, source: plan.source, target: plan.target)
        if settings.onlineMode == .always { return .online(appleStatus: status) }
        return status == .installed ? .apple : .online(appleStatus: status)
    }

    private func translateWithApple(_ text: String, plan: TranslationPlan, detected: Locale.Language?) async {
        do {
            let response = try await TranslationEngine.shared.translate(text, from: plan.source, to: plan.target)
            guard !Task.isCancelled else { return }
            panel.model.finish(response)
        } catch {
            guard !Task.isCancelled, !(error is CancellationError) else { return }
            if case TranslationEngineError.superseded = error { return }
            panel.model.fail(Self.message(for: error, detected: detected, target: plan.target))
        }
    }

    private func translateOnline(_ text: String, plan: TranslationPlan, detected: Locale.Language?, appleStatus: LanguageAvailability.Status) async {
        let client = OpenRouterClient(apiKey: settings.openRouterAPIKey)
        panel.model.provider = .online(model: settings.onlineModelName)
        panel.model.isStreaming = true

        var output = ""
        var reportedSource: Locale.Language?
        do {
            let stream = client.streamTranslation(
                text,
                target: plan.target,
                sourceHint: plan.source,
                model: settings.onlineModelID,
                instructions: settings.onlineInstructions
            )
            for try await event in stream {
                guard !Task.isCancelled else { return }
                switch event {
                case .sourceLanguage(let language):
                    reportedSource = language
                    if let language { panel.model.sourceLanguage = language }
                case .delta(let chunk):
                    output += chunk
                    panel.model.phase = .result(output)
                }
            }
            guard !Task.isCancelled else { return }
            panel.model.isStreaming = false

            let final = output.trimmingCharacters(in: .whitespacesAndNewlines)
            let source = reportedSource ?? detected
            guard !final.isEmpty else {
                panel.model.fail("The model returned an empty translation.")
                return
            }
            if let source, source.isEquivalent(to: plan.target), settings.secondLanguage == nil,
               final == text.trimmingCharacters(in: .whitespacesAndNewlines) {
                panel.model.fail(TranslationEngineError.sameLanguage(plan.target).localizedDescription)
                return
            }
            panel.model.phase = .result(final)
            await offerOfflinePack(source: source, target: plan.target)
        } catch {
            guard !Task.isCancelled, !(error is CancellationError) else { return }
            log.error("Online translation failed: \(error.localizedDescription, privacy: .public)")
            panel.model.isStreaming = false
            if appleStatus != .unsupported {
                // Apple can handle this pair (possibly after a download) — fall back to it.
                panel.model.provider = .apple
                panel.model.phase = .translating
                await translateWithApple(text, plan: plan, detected: detected)
            } else {
                panel.model.fail(error.localizedDescription)
            }
        }
    }

    /// If Apple could translate this pair offline after a download, offer it once per language.
    private func offerOfflinePack(source: Locale.Language?, target: Locale.Language) async {
        guard let source,
              !settings.dismissedPackSuggestions.contains((source.languageCode?.identifier ?? source.minimalIdentifier)) else { return }
        let status = await TranslationEngine.shared.appleStatus(text: "", source: source, target: target)
        guard !Task.isCancelled, status == .supported else { return }
        panel.model.packSuggestion = source
    }

    private func downloadPack() {
        guard let source = panel.model.packSuggestion, !panel.model.isDownloadingPack else { return }
        let target = panel.model.targetLanguage
        panel.model.isDownloadingPack = true
        Task { [weak self] in
            guard let self else { return }
            do {
                try await TranslationEngine.shared.downloadPack(source: source, target: target)
                self.panel.model.packSuggestion = nil
                self.panel.model.packDownloaded = true
            } catch {
                self.log.error("Pack download failed: \(error.localizedDescription, privacy: .public)")
            }
            self.panel.model.isDownloadingPack = false
        }
    }

    private func dismissPackSuggestion() {
        guard let source = panel.model.packSuggestion else { return }
        settings.dismissedPackSuggestions.append((source.languageCode?.identifier ?? source.minimalIdentifier))
        panel.model.packSuggestion = nil
    }

    private func retranslate(to language: Locale.Language) {
        guard let current else { return }
        translate(current, to: language)
    }

    private func retry() {
        guard let current else { return }
        translate(current, to: panel.model.targetLanguage)
    }

    private static func message(for error: Error, detected: Locale.Language?, target: Locale.Language) -> String {
        switch error {
        case TranslationError.unsupportedLanguagePairing:
            if let detected, detected.isEquivalent(to: target) {
                return TranslationEngineError.sameLanguage(target).localizedDescription
            }
            return "This language pair isn't supported by Apple Translation."
        case TranslationError.unableToIdentifyLanguage:
            return "Couldn't identify the language of the selected text."
        case TranslationError.nothingToTranslate:
            return "Nothing to translate."
        default:
            return error.localizedDescription
        }
    }
}
