import SwiftUI

/// Full-body avatar for a family member. Generated deterministically from
/// the user's id by DiceBear's open-peeps style — same seed always renders
/// the same character, so kids get a stable identity from day one without
/// any setup. Customizations (hats, outfits, accessories bought with
/// points) get appended as query params here later.
struct AvatarView: View {
    let seed: String
    let size: CGFloat
    /// Optional customizations to layer onto the avatar — e.g. ["hat-1",
    /// "glasses-3"]. Empty for now; wire-up for the future shop economy.
    var customizations: [String] = []
    /// First-letter fallback if the network image hasn't loaded yet.
    var fallbackInitial: String? = nil
    /// Set false when placing the avatar on a transparent host (e.g. a
    /// quest card). Default true gives it a soft circular pad so it sits
    /// nicely in a row.
    var showBackground: Bool = true

    private var url: URL? {
        // Render at 2x size for retina sharpness, capped to DiceBear's
        // typical max. The seed is URL-safe via .addingPercentEncoding.
        let pixelSize = Int(min(size * 2, 512))
        var components = URLComponents(string: "https://api.dicebear.com/9.x/open-peeps/png")
        var query: [URLQueryItem] = [
            URLQueryItem(name: "seed", value: seed),
            URLQueryItem(name: "size", value: String(pixelSize)),
            URLQueryItem(name: "backgroundColor", value: "transparent")
        ]
        // Future shop items map to query params here.
        for item in customizations {
            let parts = item.split(separator: ":", maxSplits: 1).map(String.init)
            if parts.count == 2 {
                query.append(URLQueryItem(name: parts[0], value: parts[1]))
            }
        }
        components?.queryItems = query
        return components?.url
    }

    var body: some View {
        ZStack {
            if showBackground {
                Circle()
                    .fill(LinearGradient(colors: [.neonBlue.opacity(0.18), .neonPurple.opacity(0.18)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay(Circle().stroke(.white.opacity(0.08), lineWidth: 1))
            }
            AsyncImage(url: url, transaction: Transaction(animation: .easeInOut(duration: 0.25))) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFit()
                        .padding(size * 0.05)
                case .failure:
                    placeholder
                case .empty:
                    placeholder.opacity(0.6)
                @unknown default:
                    placeholder
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    private var placeholder: some View {
        Text(fallbackInitial?.prefix(1).uppercased() ?? "?")
            .font(.system(size: size * 0.42, weight: .black, design: .rounded))
            .foregroundStyle(.white.opacity(0.45))
    }
}

extension AvatarView {
    /// Tiny avatar for inline lists, leaderboards, chore approvals.
    static func small(seed: String, fallback: String? = nil) -> AvatarView {
        AvatarView(seed: seed, size: 36, fallbackInitial: fallback)
    }

    /// Standard avatar for headers + member rows.
    static func medium(seed: String, fallback: String? = nil) -> AvatarView {
        AvatarView(seed: seed, size: 56, fallbackInitial: fallback)
    }

    /// Large avatar for the user's own profile screen.
    static func hero(seed: String, fallback: String? = nil) -> AvatarView {
        AvatarView(seed: seed, size: 160, fallbackInitial: fallback)
    }
}
