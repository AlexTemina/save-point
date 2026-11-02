import SwiftUI

/// Material-style surfaces: flat tonal fills, soft elevation, solid dots that check themselves when done.

/// A solid dot: hollow while open, filled in its color when active or done, with a check when done.
struct StatusDot: View {
    let color: Color
    var filled = true
    var check = false
    var size: CGFloat = 14

    var body: some View {
        ZStack {
            if filled {
                Circle().fill(color)
                if check {
                    Image(systemName: "checkmark")
                        .font(.system(size: size * 0.55, weight: .heavy))
                        .foregroundStyle(.white)
                }
            } else {
                Circle().strokeBorder(Color.secondary.opacity(0.55), lineWidth: max(1.5, size * 0.12))
            }
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(filled ? 0.18 : 0), radius: 1.5, y: 1)
    }
}

/// A solid surface in one color: a pill when no radius is given.
struct FilledSurface: View {
    let tint: Color
    var radius: CGFloat? = nil

    var body: some View {
        RoundedRectangle(cornerRadius: radius ?? 999, style: .continuous)
            .fill(tint)
            .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
    }
}

struct FilledButtonStyle: ButtonStyle {
    var tint: Color = .accentColor

    func makeBody(configuration: Configuration) -> some View {
        FilledButtonBody(configuration: configuration, tint: tint)
    }
}

private struct FilledButtonBody: View {
    @Environment(\.isEnabled) private var isEnabled
    let configuration: ButtonStyleConfiguration
    let tint: Color

    var body: some View {
        configuration.label
            .font(.callout.weight(.medium))
            .foregroundStyle(isEnabled ? .white : .secondary)
            .padding(.horizontal, 16).padding(.vertical, 7)
            .background(FilledSurface(tint: isEnabled ? tint : Color.secondary.opacity(0.18)))
            .overlay(Capsule().fill(.white.opacity(configuration.isPressed ? 0.14 : 0)))
    }
}

/// A tonal card: the surface tinted by its color, rounded, one level of elevation.
struct TonalCard: ViewModifier {
    var tint: Color? = nil
    var radius: CGFloat = 16
    var strong = false

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .background {
                shape.fill(.background.secondary.opacity(0.6))
                    .overlay(shape.fill((tint ?? .clear).opacity(strong ? 0.16 : 0.08)))
            }
            .shadow(color: .black.opacity(0.10), radius: 3, y: 1)
    }
}

/// A tonal chip for sizes, dates and time slots.
struct TonalChip: ViewModifier {
    var tint: Color? = nil

    func body(content: Content) -> some View {
        content.background((tint ?? .secondary).opacity(0.16), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

extension View {
    func tonalCard(_ tint: Color? = nil, radius: CGFloat = 16, strong: Bool = false) -> some View {
        modifier(TonalCard(tint: tint, radius: radius, strong: strong))
    }

    func tonalChip(_ tint: Color? = nil) -> some View { modifier(TonalChip(tint: tint)) }
}
