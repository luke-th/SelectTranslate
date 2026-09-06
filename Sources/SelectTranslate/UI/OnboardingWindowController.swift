import AppKit
import SwiftUI

@MainActor
final class OnboardingModel: ObservableObject {
    @Published var granted = AccessibilityPermission.isTrusted

    var onClose: (() -> Void)?
    private let onGranted: () -> Void
    private var timer: Timer?
    private var notified = false

    init(onGranted: @escaping () -> Void) {
        self.onGranted = onGranted
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.check() }
        }
    }

    func requestAccess() {
        AccessibilityPermission.prompt()
        AccessibilityPermission.openSystemSettings()
    }

    private func check() {
        let trusted = AccessibilityPermission.isTrusted
        if trusted != granted { granted = trusted }
        guard trusted, !notified else { return }
        notified = true
        timer?.invalidate()
        timer = nil
        onGranted()
    }
}

final class OnboardingWindowController: NSWindowController {
    private let model: OnboardingModel

    init(onGranted: @escaping () -> Void) {
        model = OnboardingModel(onGranted: onGranted)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 440),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(rootView: OnboardingView(model: model))
        window.center()
        super.init(window: window)
        model.onClose = { [weak self] in self?.close() }
    }

    required init?(coder: NSCoder) { fatalError("Not supported") }
}

struct OnboardingView: View {
    @ObservedObject var model: OnboardingModel

    var body: some View {
        VStack(spacing: 18) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 84, height: 84)
            VStack(spacing: 6) {
                Text("Welcome to \(AppInfo.name)").font(.title.weight(.semibold))
                Text("Select text in any app and click Translate. Everything happens on your Mac.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(alignment: .leading, spacing: 14) {
                step(number: 1, title: "Allow Accessibility access", done: model.granted) {
                    Text("\(AppInfo.name) needs it to read the text you select. It never records what you type.")
                    if !model.granted {
                        Button("Open System Settings…") { model.requestAccess() }
                            .controlSize(.regular)
                        Text("Turn on \(AppInfo.name) under Privacy & Security → Accessibility.")
                            .font(.caption).foregroundStyle(.tertiary)
                    }
                }
                step(number: 2, title: "Select some text", done: false) {
                    Text("A Translate button appears next to your selection. Click it, or press ⌥⌘T, or hit ⌘C twice.")
                }
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.05)))

            Spacer(minLength: 0)
            HStack {
                Button("Skip for now") { model.onClose?() }.buttonStyle(.plain).foregroundStyle(.secondary)
                Spacer()
                Button("Get Started") { model.onClose?() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!model.granted)
            }
        }
        .padding(28)
        .padding(.top, 8)
        .frame(width: 480, height: 440)
    }

    private func step<Content: View>(number: Int, title: String, done: Bool, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle().fill(done ? Color.green : Brand.accent).frame(width: 24, height: 24)
                if done {
                    Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
                } else {
                    Text("\(number)").font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.headline)
                content()
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
