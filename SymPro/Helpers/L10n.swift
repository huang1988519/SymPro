import Foundation

/// Simple i18n helper for both SwiftUI (dynamic strings) and AppKit (assigned titles).
/// - Note: For `Text("...")` / `Button("...")` literal usage, SwiftUI can localize automatically
///   if the key exists in `Localizable.strings`.
enum L10n {
    private static var bundle: Bundle { .main }
    private static let tableName = "Localizable"

    /// Returns the localized string for `key`. Falls back to `key` if missing.
    static func t(_ key: String) -> String {
        NSLocalizedString(key, tableName: tableName, bundle: bundle, value: key, comment: "")
    }

    /// Returns the localized template for `key` formatted with `args`.
    /// Template should use C-style format placeholders: `%@`, `%d`, etc.
    static func tFormat(_ key: String, _ args: CVarArg...) -> String {
        String(format: t(key), arguments: args)
    }
}

