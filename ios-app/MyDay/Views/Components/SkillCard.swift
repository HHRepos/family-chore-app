import SwiftUI

/// Compact skill card for the profile page. Shows the skill name, current
/// level, and a progress bar toward the next threshold.
struct SkillCard: View {
    let skill: Skill

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: skill.icon)
                    .font(.system(size: 18))
                    .foregroundStyle(skill.swiftUIColor)
                    .frame(width: 28, height: 28)
                    .background(skill.swiftUIColor.opacity(0.12))
                    .clipShape(Circle())
                VStack(alignment: .leading, spacing: 0) {
                    Text(skill.name)
                        .font(.system(size: 13, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                    Text(skill.levelName)
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(skill.swiftUIColor)
                }
                Spacer()
                Text(skill.displayValue)
                    .font(.system(size: 14, weight: .black, design: .rounded))
                    .foregroundStyle(.white.opacity(0.8))
            }

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3).fill(Color.gameCard).frame(height: 6)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(LinearGradient(
                            colors: [skill.swiftUIColor.opacity(0.7), skill.swiftUIColor],
                            startPoint: .leading, endPoint: .trailing
                        ))
                        .frame(width: max(6, geo.size.width * skill.progress), height: 6)
                }
            }
            .frame(height: 6)

            Text(skill.description)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.4))
                .lineLimit(2)
        }
        .padding(12)
        .background(Color.gameCardLight)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(skill.swiftUIColor.opacity(0.2), lineWidth: 1))
    }
}
