import Foundation

extension Bundle {
	/// SwiftPM's generated `Bundle.module` only looks next to the executable, which breaks once the
	/// binary is wrapped in an `.app`. Prefer `Contents/Resources`, then fall back to SwiftPM's lookup.
	static let keyboardShortcutsResources: Bundle = {
		let name = "KeyboardShortcuts_KeyboardShortcuts.bundle"
		let candidates = [
			Bundle.main.resourceURL?.appendingPathComponent(name),
			Bundle.main.bundleURL.appendingPathComponent(name),
		]
		for case let url? in candidates {
			if let bundle = Bundle(url: url) {
				return bundle
			}
		}
		return Bundle.module
	}()
}
