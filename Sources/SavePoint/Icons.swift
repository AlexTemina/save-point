import SwiftUI

/// A small robot head, drawn so it matches any text size and both themes.
struct RobotHead: View {
    var body: some View {
        GeometryReader { g in
            let s = min(g.size.width, g.size.height)
            ZStack {
                Capsule().frame(width: s * 0.08, height: s * 0.22).offset(y: -s * 0.40)
                Circle().frame(width: s * 0.16).offset(y: -s * 0.52)
                RoundedRectangle(cornerRadius: s * 0.18)
                    .frame(width: s * 0.82, height: s * 0.62)
                    .offset(y: s * 0.08)
                HStack(spacing: s * 0.18) {
                    Circle().frame(width: s * 0.15)
                    Circle().frame(width: s * 0.15)
                }
                .foregroundStyle(.background)
                .offset(y: s * 0.04)
                Capsule().frame(width: s * 0.30, height: s * 0.06).foregroundStyle(.background).offset(y: s * 0.24)
            }
            .frame(width: g.size.width, height: g.size.height)
        }
    }
}

enum RobotBadge { case none, talk, plus }

struct RobotIcon: View {
    var badge: RobotBadge = .none
    var size: CGFloat = 18

    var body: some View {
        RobotHead()
            .frame(width: size, height: size)
            .overlay(alignment: .topTrailing) {
                switch badge {
                case .none: EmptyView()
                case .talk:
                    Image(systemName: "bubble.left.fill")
                        .font(.system(size: size * 0.52, weight: .bold))
                        .offset(x: size * 0.38, y: -size * 0.28)
                case .plus:
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: size * 0.52, weight: .bold))
                        .offset(x: size * 0.38, y: -size * 0.28)
                }
            }
            .padding(.trailing, badge == .none ? 0 : size * 0.3)
    }
}

struct IconButton<Label: View>: View {
    let help: String
    let action: () -> Void
    @ViewBuilder let label: () -> Label
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            label()
                .foregroundStyle(hover ? Color.accentColor : .secondary)
                .frame(width: 30, height: 26)
                .background(hover ? Color.accentColor.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { hover = $0 }
    }
}
