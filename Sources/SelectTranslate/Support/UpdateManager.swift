import Combine
import Foundation
import Sparkle

/// Thin wrapper around Sparkle so the menu and Settings can share one updater.
@MainActor
final class UpdateManager: ObservableObject {
    static let shared = UpdateManager()

    let controller: SPUStandardUpdaterController
    @Published var automaticallyChecks: Bool {
        didSet {
            if controller.updater.automaticallyChecksForUpdates != automaticallyChecks {
                controller.updater.automaticallyChecksForUpdates = automaticallyChecks
            }
        }
    }
    private var cancellables = Set<AnyCancellable>()

    private init() {
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        automaticallyChecks = controller.updater.automaticallyChecksForUpdates
        controller.updater.publisher(for: \.automaticallyChecksForUpdates)
            .receive(on: RunLoop.main)
            .sink { [weak self] value in
                if self?.automaticallyChecks != value { self?.automaticallyChecks = value }
            }
            .store(in: &cancellables)
    }

    var canCheckForUpdates: Bool { controller.updater.canCheckForUpdates }

    func checkForUpdates() { controller.checkForUpdates(nil) }
}
