import AppKit
import SwiftUI

enum Brand {
    static let accent = Color(red: 0.36, green: 0.35, blue: 0.93)
    static let accentHover = Color(red: 0.43, green: 0.41, blue: 0.97)
    static let cornerRadius: CGFloat = 14
    /// Source half + card body: #F2F2F7 in light, #2C2C2E in dark.
    static let cardBackground = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 0.173, green: 0.173, blue: 0.180, alpha: 1)
            : NSColor(srgbRed: 0.949, green: 0.949, blue: 0.969, alpha: 1)
    })
}

enum AppInfo {
    static let name = "SelectTranslate"
    static var version: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        return build.map { "\(short) (\($0))" } ?? short
    }
    static let repositoryURL: URL? = URL(string: "https://github.com/luke-th/SelectTranslate")
}
