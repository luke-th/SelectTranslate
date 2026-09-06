import AppKit
import SwiftUI

private struct ContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// SwiftUI's `onHover` only tracks reliably in key windows; the result panel usually isn't one.
private struct HoverTracker: NSViewRepresentable {
    @Binding var isHovering: Bool

    func makeNSView(context: Context) -> TrackingView {
        let view = TrackingView()
        view.onChange = { hovering in Task { @MainActor in isHovering = hovering } }
        return view
    }

    func updateNSView(_ nsView: TrackingView, context: Context) {}

    final class TrackingView: NSView {
        var onChange: ((Bool) -> Void)?

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            trackingAreas.forEach(removeTrackingArea)
            addTrackingArea(NSTrackingArea(
                rect: .zero,
                options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                owner: self,
                userInfo: nil
            ))
        }

        override func mouseEntered(with event: NSEvent) { onChange?(true) }
        override func mouseExited(with event: NSEvent) { onChange?(false) }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}

struct TranslationView: View {
    @ObservedObject var model: TranslationPanelModel
    @ObservedObject var settings: AppSettings
    @ObservedObject var catalog: LanguageCatalog

    @State private var hoveringTop = false
    @State private var hoveringBottom = false
    @State private var copiedTop = false
    @State private var copiedBottom = false

    var body: some View {
        ScrollView(.vertical) {
            VStack(spacing: 0) {
                topSection
                Divider()
                bottomSection
                if case .online(let modelName) = model.provider {
                    Divider()
                    onlineFooter(modelName: modelName)
                }
            }
            .background(GeometryReader { proxy in
                Color.clear.preference(key: ContentHeightKey.self, value: proxy.size.height)
            })
        }
        .onPreferenceChange(ContentHeightKey.self) { height in
            Task { @MainActor in model.contentHeight = height }
        }
        .frame(width: TranslationPanel.width)
        .background(Brand.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: Brand.cornerRadius, style: .continuous))
    }

    // MARK: Translated half

    private var topSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                targetMenu.frame(maxWidth: .infinity, alignment: .leading)
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 27, height: 27)
                HStack(spacing: 2) {
                    if let text = model.resultText {
                        copyButton(text, visible: hoveringTop, copied: $copiedTop)
                        speakButton(text, language: model.targetLanguage)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            phaseContent.padding(.top, 14)
        }
        .padding(EdgeInsets(top: 12, leading: 16, bottom: 20, trailing: 12))
        .background(Color(nsColor: .textBackgroundColor))
        .background(HoverTracker(isHovering: $hoveringTop))
    }

    @ViewBuilder
    private var phaseContent: some View {
        switch model.phase {
        case .translating:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Translating…").foregroundStyle(.secondary)
            }
            .padding(.vertical, 2)
        case .result(let text):
            Text(text)
                .font(.system(size: settings.bubbleFontSize, weight: .medium))
                .lineSpacing(settings.bubbleFontSize * 0.22)
                .foregroundStyle(Brand.accent)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .failure(let message):
            VStack(alignment: .leading, spacing: 8) {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Try Again") { model.onRetry?() }.controlSize(.small)
            }
        }
    }

    private var targetMenu: some View {
        Menu {
            ForEach(catalog.supported, id: \.self) { language in
                Button(language.displayName) { model.onRetarget?(language) }
            }
        } label: {
            HStack(spacing: 4) {
                Text(model.targetLanguage.displayName)
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold)).opacity(0.6)
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Translate into a different language")
    }

    // MARK: Source half

    private var bottomSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 2) {
                Text(model.sourceLanguage?.displayName ?? "Auto Detect")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                copyButton(model.sourceText, visible: hoveringBottom, copied: $copiedBottom)
                speakButton(model.sourceText, language: model.sourceLanguage)
            }
            Text(model.sourceText)
                .font(.system(size: max(settings.bubbleFontSize - 3, 11)))
                .lineSpacing(max(settings.bubbleFontSize - 3, 11) * 0.22)
                .foregroundStyle(.secondary)
                .lineLimit(6)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(EdgeInsets(top: 12, leading: 16, bottom: 20, trailing: 12))
        .background(HoverTracker(isHovering: $hoveringBottom))
    }

    // MARK: Online footer

    private func onlineFooter(modelName: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "cloud")
                Text("Translated online via \(modelName)")
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)

            if let language = model.packSuggestion {
                HStack(spacing: 8) {
                    Text("Translate from \(language.displayName) often?")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Button(model.isDownloadingPack ? "Downloading…" : "Download") {
                        model.onDownloadPack?()
                    }
                    .controlSize(.small)
                    .disabled(model.isDownloadingPack)
                    Spacer()
                    Button { model.onDismissPackSuggestion?() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.tertiary)
                            .frame(width: 20, height: 20)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Don't suggest this language again")
                }
            } else if model.packDownloaded {
                Text("Offline pack installed — future translations from this language run on your Mac.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(EdgeInsets(top: 8, leading: 16, bottom: 10, trailing: 12))
        .background(Color.primary.opacity(0.045))
    }

    // MARK: Controls

    private func copyButton(_ text: String, visible: Bool, copied: Binding<Bool>) -> some View {
        iconButton(copied.wrappedValue ? "checkmark" : "doc.on.doc", help: "Copy") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            copied.wrappedValue = true
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1.2))
                copied.wrappedValue = false
            }
        }
        .opacity(visible || copied.wrappedValue ? 1 : 0)
        .animation(.easeInOut(duration: 0.15), value: visible)
    }

    private func speakButton(_ text: String, language: Locale.Language?) -> some View {
        iconButton("speaker.wave.2", help: "Speak") {
            Speaker.shared.speak(text, language: language)
        }
    }

    private func iconButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
