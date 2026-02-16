import SwiftUI

struct AvatarView: View {
    let name: String
    var isBot: Bool = false
    var isGroup: Bool = false
    var size: CGFloat = 40

    private var initials: String {
        let first = name.prefix(1).uppercased()
        return first.isEmpty ? "?" : String(first)
    }

    private var bgColor: Color {
        if isBot { return CatColor.primary }
        if isGroup { return CatColor.primary }
        let colors: [Color] = [.orange, .pink, .teal, CatColor.primary, .mint, .cyan, .indigo, .brown]
        let hash = abs(name.hashValue)
        return colors[hash % colors.count]
    }

    private var icon: String? {
        if isBot { return "cpu" }
        if isGroup { return "person.3.fill" }
        return nil
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: CatLayout.avatarRadius)
                .fill(bgColor.gradient)
                .frame(width: size, height: size)

            if let icon {
                Image(systemName: icon)
                    .font(.system(size: size * 0.4))
                    .foregroundStyle(.white)
            } else {
                Text(initials)
                    .font(.system(size: size * 0.4, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
    }
}
