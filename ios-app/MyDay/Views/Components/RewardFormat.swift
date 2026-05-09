import Foundation

/// Locale-aware reward formatting. Cash rewards render with the user's
/// regional currency symbol (£ in en-GB, € in EU locales, $ in en-US, etc.)
/// instead of the prior hardcoded $.
enum RewardFormat {
    /// Render a cash amount as e.g. "£10" / "$10" with no decimal places.
    static func cash(_ amount: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.locale = .current
        f.maximumFractionDigits = 0
        f.minimumFractionDigits = 0
        return f.string(from: NSNumber(value: amount)) ?? "\(Int(amount))"
    }

    /// "10 pts" — fixed, points are not localized.
    static func points(_ amount: Double) -> String {
        "\(Int(amount)) pts"
    }

    /// Helper: pick cash vs points based on the reward type string.
    static func format(amount: Double, type: String) -> String {
        type == "cash" ? cash(amount) : points(amount)
    }
}
