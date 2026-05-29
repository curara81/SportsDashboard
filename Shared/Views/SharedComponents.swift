import SwiftUI

// MARK: - Status Badge (shared between iOS and watchOS)

struct StatusBadge: View {
    let label: String

    var body: some View {
        Text(label)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(badgeTextColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(badgeBgColor)
            .clipShape(Capsule())
    }

    private var badgeBgColor: Color {
        switch label {
        case "우수", "최상 컨디션", "양호", "적정", "Balanced", "가벼운 회복":
            return Color(red: 0.3, green: 0.85, blue: 0.45).opacity(0.2)
        case "주의", "보통", "하루 회복", "개선 필요":
            return Color(red: 1.0, green: 0.65, blue: 0.2).opacity(0.2)
        default:
            return Color(red: 1.0, green: 0.35, blue: 0.35).opacity(0.2)
        }
    }

    private var badgeTextColor: Color {
        switch label {
        case "우수", "최상 컨디션", "양호", "적정", "Balanced", "가벼운 회복":
            return Color(red: 0.3, green: 0.85, blue: 0.45)
        case "주의", "보통", "하루 회복", "개선 필요":
            return Color(red: 1.0, green: 0.65, blue: 0.2)
        default:
            return Color(red: 1.0, green: 0.35, blue: 0.35)
        }
    }
}

// MARK: - Card View (watchOS style, also usable on iOS for shared views)

struct CardView<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(white: 0.12))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.white.opacity(0.06), lineWidth: 0.5)
            )
    }
}
