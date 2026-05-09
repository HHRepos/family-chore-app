import Foundation
import SwiftUI

/// A derived skill score on the user's profile. Computed server-side from
/// existing chore + job activity (no separate progress table) — values get
/// recomputed on every fetch, levels are bucket-based.
struct Skill: Decodable, Identifiable {
    let id: String
    let name: String
    let icon: String
    let color: String
    let description: String
    let value: Int
    let unit: String?
    let level: Int
    let levelName: String
    let nextThreshold: Int
    let progress: Double

    var swiftUIColor: Color {
        switch color {
        case "neonOrange": return .neonOrange
        case "neonGreen":  return .neonGreen
        case "neonBlue":   return .neonBlue
        case "neonPurple": return .neonPurple
        case "neonPink":   return .neonPink
        case "neonYellow": return .neonYellow
        case "neonRed":    return .neonRed
        default:           return .neonBlue
        }
    }

    /// "12" or "85%" depending on the skill.
    var displayValue: String { "\(value)\(unit ?? "")" }
}

struct SkillsResponse: Decodable {
    let skills: [Skill]
}
