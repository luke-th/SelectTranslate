import AppKit
import SwiftUI
import Translation

/// `TranslationSession` is only handed out through SwiftUI's `.translationTask`, so we keep an invisible
/// window hosting a tiny view alive and drive it by changing its configuration. The window is only made
/// visible when macOS needs to show the language-pack download sheet.
@MainActor
final class TranslationHost: ObservableObject {
    @Published var configuration: TranslationSession.Configuration?
    @Published var statusMessage = "Preparing translation…"

    private struct Job {
        enum Kind {
            case translate(String)
            case download
        }
        let id: UUID
        let kind: Kind
        let needsDownload: Bool
        let continuation: CheckedContinuation<TranslationSession.Response?, Error>
    }

    private var job: Job?
    private let window: NSWindow

    init() {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 190),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.title = AppInfo.name
        window.isReleasedWhenClosed = false
        window.isExcludedFromWindowsMenu = true
        window.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]
        window.contentViewController = NSHostingController(rootView: TranslationHostView(host: self))
        park()
    }

    func translate(_ text: String, source: Locale.Language?, target: Locale.Language, needsDownload: Bool) async throws -> TranslationSession.Response {
        guard let response = try await run(.translate(text), source: source, target: target, needsDownload: needsDownload) else {
            throw TranslationEngineError.unexpected
        }
        return response
    }

    func prepare(source: Locale.Language, target: Locale.Language) async throws {
        _ = try await run(.download, source: source, target: target, needsDownload: true)
    }

    private func run(_ kind: Job.Kind, source: Locale.Language?, target: Locale.Language, needsDownload: Bool) async throws -> TranslationSession.Response? {
        if let stale = job {
            job = nil
            stale.continuation.resume(throwing: TranslationEngineError.superseded)
        }
        let id = UUID()
        return try await withCheckedThrowingContinuation { continuation in
            job = Job(id: id, kind: kind, needsDownload: needsDownload, continuation: continuation)
            if needsDownload, let source {
                statusMessage = "Downloading \(source.displayName) → \(target.displayName) language pack…"
            } else {
                statusMessage = needsDownload ? "Downloading \(target.displayName) language pack…" : "Translating…"
            }
            if needsDownload { present() } else { window.orderBack(nil) }

            if var existing = configuration, existing.source == source, existing.target == target {
                existing.invalidate()
                configuration = existing
            } else {
                configuration = TranslationSession.Configuration(source: source, target: target)
            }

            Task { [weak self] in
                try? await Task.sleep(for: .seconds(needsDownload ? 600 : 20))
                guard let self, let pending = self.job, pending.id == id else { return }
                self.job = nil
                self.park()
                pending.continuation.resume(throwing: TranslationEngineError.timeout)
            }
        }
    }

    fileprivate func perform(with session: TranslationSession) async {
        guard let current = job else { return }
        job = nil
        do {
            if current.needsDownload { try await session.prepareTranslation() }
            switch current.kind {
            case .translate(let text):
                let response = try await session.translate(text)
                park()
                current.continuation.resume(returning: response)
            case .download:
                park()
                current.continuation.resume(returning: nil)
            }
        } catch {
            park()
            current.continuation.resume(throwing: error)
        }
    }

    private func park() {
        window.alphaValue = 0
        window.ignoresMouseEvents = true
        window.level = .normal
        window.setFrameOrigin(.zero)
        window.orderBack(nil)
    }

    private func present() {
        window.alphaValue = 1
        window.ignoresMouseEvents = false
        window.level = .floating
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

private struct TranslationHostView: View {
    @ObservedObject var host: TranslationHost

    var body: some View {
        VStack(spacing: 14) {
            ProgressView().controlSize(.large)
            Text(host.statusMessage).font(.headline)
            Text("macOS asks once to download each language pack. Translation always runs on this Mac.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(width: 420, height: 190)
        .translationTask(host.configuration) { session in
            await host.perform(with: session)
        }
    }
}
