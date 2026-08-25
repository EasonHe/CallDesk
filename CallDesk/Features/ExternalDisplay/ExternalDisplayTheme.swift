import SwiftUI

enum ExternalDisplayTheme {
    // The reference uses layered warm paper tones, not a pure-white dashboard.
    static let background = Color(red: 1.0, green: 0.956, blue: 0.898)
    static let deepBrown = Color(red: 0.20, green: 0.09, blue: 0.045)
    // Match the reference board's luminous saffron, avoiding the red cast that
    // makes the calling panel compete with the number itself on a TV.
    static let orange = Color(red: 1.0, green: 0.431, blue: 0.0) // #FF6E00
    static let paleOrange = Color(red: 1.0, green: 0.89, blue: 0.72)
    static let highlightCream = Color(red: 1.0, green: 0.83, blue: 0.45)
    static let stripCream = Color(red: 1.0, green: 0.92, blue: 0.78)
    static let orangeGradient = LinearGradient(
        colors: [
            Color(red: 1.0, green: 0.639, blue: 0.125), // #FFA320
            Color(red: 1.0, green: 0.518, blue: 0.035),
            orange
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    static let mainCardGradient = LinearGradient(
        colors: [Color(red: 1.0, green: 0.978, blue: 0.928), Color(red: 1.0, green: 0.945, blue: 0.866)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    static let recentCardCream = Color(red: 1.0, green: 0.972, blue: 0.916)
    static let sceneWash = Color(red: 1.0, green: 0.955, blue: 0.86)

    enum Layout {
        static let heightToWidth: CGFloat = 9 / 16
        static let widthToHeight: CGFloat = 16 / 9
        static let mainCardWidthRatio: CGFloat = 1520 / 1672
        static let headerWidthRatio: CGFloat = 1500 / 1672
        static let recentRowWidthRatio: CGFloat = 1477 / 1672
        static let headerHeight: CGFloat = 0.14
        static let headerCenter: CGFloat = 0.075
        static let headerSideWidth: CGFloat = 232
        static let currentCardHeight: CGFloat = 0.42
        static let currentCardCenter: CGFloat = 0.372
        static let mainCardRadius: CGFloat = 30
        static let currentLeftWidth: CGFloat = 0.23
        static let currentCenterWidth: CGFloat = 0.52
        static let currentPhotoWidth: CGFloat = 0.25
        static let currentStatusVisualWidth: CGFloat = 0.30
        static let currentStatusContentWidth: CGFloat = 178
        static let currentStatusContentCenterX: CGFloat = 180 / (1520 * currentStatusVisualWidth)
        static let currentStatusContentCenterY: CGFloat = 0.465
        static let recentHeadingHeight: CGFloat = 0.05
        static let recentHeadingCenter: CGFloat = 0.635
        static let recentCardsHeight: CGFloat = 223 / 941
        static let recentCardsCenter: CGFloat = 738.5 / 941
        static let recentCardSpacing: CGFloat = 25
        static let recentCardRadius: CGFloat = 20
        static let footerHeight: CGFloat = 0.04
        static let footerCenter: CGFloat = 0.962
        static let pickupTicketWidthRatio: CGFloat = 0.125
        static let pickupTicketHeightRatio: CGFloat = 0.19
        static let pickupTicketXRatio: CGFloat = 0.864
        static let pickupTicketYRatio: CGFloat = 0.515

        // Background artwork stays outside the content-safe area so the plants
        // remain a natural frame rather than another foreground element.
        static let leftLeafFrame = CGSize(width: 116, height: 146)
        static let leftLeafCenter = CGPoint(x: 39, y: 66)
        static let leftLeafHorizontalScale: CGFloat = 1.55
        static let leftLeafGroupSize = CGSize(width: 106, height: 146)
        static let leftLeafPrimarySize = CGSize(width: 54, height: 146)
        static let leftLeafSecondarySize = CGSize(width: 44, height: 119)
        static let leftLeafSecondaryOpacity: CGFloat = 0.30
        static let botanicalVerticalScale: CGFloat = 0.58
        static let botanicalOpacity: CGFloat = 0.78
    }

    static func timeText(for date: Date) -> String {
        date.formatted(.dateTime.locale(Locale(identifier: "zh_Hans")).hour().minute())
    }

    static func dateText(for date: Date) -> String {
        date.formatted(.dateTime.locale(Locale(identifier: "zh_Hans")).year().month(.wide).day().weekday(.wide))
    }
}

struct ExternalDisplayClocheMark: View {
    var color: Color = ExternalDisplayTheme.orange

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            ZStack {
                Path { path in
                    path.move(to: CGPoint(x: width * 0.18, y: height * 0.67))
                    path.addCurve(to: CGPoint(x: width * 0.82, y: height * 0.67), control1: CGPoint(x: width * 0.23, y: height * 0.24), control2: CGPoint(x: width * 0.77, y: height * 0.24))
                }
                .stroke(color, style: StrokeStyle(lineWidth: width * 0.10, lineCap: .round))
                Circle().fill(color).frame(width: width * 0.14, height: width * 0.14).offset(y: -height * 0.21)
                Capsule().fill(color).frame(width: width * 0.78, height: height * 0.11).offset(y: height * 0.30)
            }
        }
        .aspectRatio(1.25, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

struct ExternalDisplaySpeakerGlyph: View {
    var color: Color = ExternalDisplayTheme.orange

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            ZStack {
                RoundedRectangle(cornerRadius: width * 0.035, style: .continuous)
                    .fill(color)
                    .frame(width: width * 0.26, height: height * 0.25)
                    .position(x: width * 0.18, y: height * 0.50)
                Path { path in
                    path.move(to: CGPoint(x: width * 0.27, y: height * 0.35))
                    path.addLine(to: CGPoint(x: width * 0.55, y: height * 0.15))
                    path.addLine(to: CGPoint(x: width * 0.55, y: height * 0.85))
                    path.addLine(to: CGPoint(x: width * 0.27, y: height * 0.65))
                    path.closeSubpath()
                }.fill(color)
                ExternalDisplaySpeakerWavePair()
                    .stroke(color, style: StrokeStyle(lineWidth: width * 0.075, lineCap: .round))
            }
        }
        .aspectRatio(1.18, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

/// Two separate sound-wave strokes, positioned to the right of the horn to
/// match the compact call icon used by the external-display reference.
struct ExternalDisplaySpeakerWavePair: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.width * 0.64, y: rect.height * 0.34))
        path.addCurve(
            to: CGPoint(x: rect.width * 0.64, y: rect.height * 0.66),
            control1: CGPoint(x: rect.width * 0.78, y: rect.height * 0.40),
            control2: CGPoint(x: rect.width * 0.78, y: rect.height * 0.60)
        )
        path.move(to: CGPoint(x: rect.width * 0.76, y: rect.height * 0.18))
        path.addCurve(
            to: CGPoint(x: rect.width * 0.76, y: rect.height * 0.82),
            control1: CGPoint(x: rect.width * 0.99, y: rect.height * 0.31),
            control2: CGPoint(x: rect.width * 0.99, y: rect.height * 0.69)
        )
        return path
    }
}

struct ExternalDisplayClockGlyph: View {
    var color: Color = ExternalDisplayTheme.orange

    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            ZStack {
                Circle().stroke(color, lineWidth: size * 0.12)
                Path { path in
                    path.move(to: CGPoint(x: size * 0.5, y: size * 0.24))
                    path.addLine(to: CGPoint(x: size * 0.5, y: size * 0.51))
                    path.addLine(to: CGPoint(x: size * 0.68, y: size * 0.62))
                }.stroke(color, style: StrokeStyle(lineWidth: size * 0.12, lineCap: .round, lineJoin: .round))
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

struct ExternalDisplayBellGlyph: View {
    var color: Color = ExternalDisplayTheme.orange

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            ZStack {
                Path { path in
                    path.move(to: CGPoint(x: width * 0.23, y: height * 0.69))
                    path.addCurve(to: CGPoint(x: width * 0.77, y: height * 0.69), control1: CGPoint(x: width * 0.27, y: height * 0.35), control2: CGPoint(x: width * 0.73, y: height * 0.35))
                    path.addLine(to: CGPoint(x: width * 0.84, y: height * 0.81))
                    path.addLine(to: CGPoint(x: width * 0.16, y: height * 0.81))
                    path.closeSubpath()
                }.fill(color)
                Circle().fill(color).frame(width: width * 0.15, height: width * 0.15).offset(y: -height * 0.22)
                Circle().fill(color).frame(width: width * 0.13, height: width * 0.13).offset(y: height * 0.39)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

struct ExternalDisplayPickupBagGlyph: View {
    var color: Color = ExternalDisplayTheme.orange

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            ZStack {
                RoundedRectangle(cornerRadius: width * 0.10, style: .continuous)
                    .fill(color)
                    .frame(width: width * 0.78, height: height * 0.64)
                    .offset(y: height * 0.12)
                Path { path in
                    path.move(to: CGPoint(x: width * 0.31, y: height * 0.36))
                    path.addCurve(to: CGPoint(x: width * 0.69, y: height * 0.36), control1: CGPoint(x: width * 0.34, y: height * 0.06), control2: CGPoint(x: width * 0.66, y: height * 0.06))
                }
                .stroke(color, style: StrokeStyle(lineWidth: width * 0.09, lineCap: .round))
                Capsule().fill(.white).frame(width: width * 0.08, height: height * 0.31).offset(x: -width * 0.14, y: height * 0.17)
                Circle().fill(.white).frame(width: width * 0.21, height: width * 0.21).offset(x: -width * 0.14, y: -height * 0.01)
                Capsule().fill(.white).frame(width: width * 0.06, height: height * 0.37).offset(x: width * 0.15, y: height * 0.17)
                HStack(spacing: width * 0.025) {
                    Rectangle().fill(.white).frame(width: width * 0.035, height: height * 0.16)
                    Rectangle().fill(.white).frame(width: width * 0.035, height: height * 0.16)
                    Rectangle().fill(.white).frame(width: width * 0.035, height: height * 0.16)
                }
                .offset(x: width * 0.15, y: -height * 0.06)
            }
        }
        .aspectRatio(0.85, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

struct ExternalDisplayFlourish: View {
    var mirrored = false

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            ZStack {
                Path { path in
                    path.move(to: CGPoint(x: width * 0.03, y: height * 0.58))
                    path.addCurve(to: CGPoint(x: width * 0.96, y: height * 0.48), control1: CGPoint(x: width * 0.31, y: height * 0.12), control2: CGPoint(x: width * 0.68, y: height * 0.85))
                }.stroke(ExternalDisplayTheme.orange, style: StrokeStyle(lineWidth: 1.7, lineCap: .round))
                Ellipse().fill(ExternalDisplayTheme.orange).frame(width: width * 0.19, height: height * 0.43).rotationEffect(.degrees(-35)).position(x: width * 0.34, y: height * 0.34)
                Ellipse().fill(ExternalDisplayTheme.orange).frame(width: width * 0.17, height: height * 0.37).rotationEffect(.degrees(35)).position(x: width * 0.58, y: height * 0.64)
            }
        }
        .scaleEffect(x: mirrored ? -1 : 1, y: 1)
        .accessibilityHidden(true)
    }
}

struct ExternalDisplayStatusPanelShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX * 0.80, y: rect.minY))
        // The dividing edge deliberately bulges right at mid-height. A gentle
        // diagonal looks like a cut-off panel on a TV; this arc matches the
        // reference board's continuous, welcoming status shape.
        path.addCurve(
            to: CGPoint(x: rect.maxX * 0.56, y: rect.maxY),
            control1: CGPoint(x: rect.maxX * 1.04, y: rect.height * 0.20),
            control2: CGPoint(x: rect.maxX * 1.00, y: rect.height * 0.75)
        )
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

struct ExternalDisplayStatusRibbons: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.20),
            control1: CGPoint(x: rect.width * 0.24, y: rect.height * 0.55),
            control2: CGPoint(x: rect.width * 0.55, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

struct ExternalDisplayHalftoneDots: View {
    var color: Color
    let columns: Int
    let rows: Int

    var body: some View {
        GeometryReader { proxy in
            let horizontalStep = proxy.size.width / CGFloat(max(columns, 1))
            let verticalStep = proxy.size.height / CGFloat(max(rows, 1))
            ForEach(0 ..< rows, id: \.self) { row in
                ForEach(0 ..< columns, id: \.self) { column in
                    let scale = CGFloat(row + column + 2) / CGFloat(rows + columns + 1)
                    Circle()
                        .fill(color)
                        .frame(width: 3 + scale * 6, height: 3 + scale * 6)
                        .position(
                            x: horizontalStep * (CGFloat(column) + 0.5),
                            y: verticalStep * (CGFloat(row) + 0.5)
                        )
                }
            }
        }
        .accessibilityHidden(true)
    }
}

struct ExternalDisplayRadiatingMarks: View {
    var color: Color

    var body: some View {
        GeometryReader { proxy in
            let center = CGPoint(x: proxy.size.width * 0.30, y: proxy.size.height * 0.70)
            ForEach([-62.0, -31.0, 0.0], id: \.self) { angle in
                Capsule()
                    .fill(color)
                    .frame(width: 7, height: proxy.size.height * 0.36)
                    .position(x: center.x, y: center.y - proxy.size.height * 0.20)
                    .rotationEffect(.degrees(angle), anchor: .bottom)
            }
        }
        .accessibilityHidden(true)
    }
}

struct ExternalDisplayRuleDot: View {
    var mirrored = false

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: mirrored ? .trailing : .leading) {
                Rectangle().fill(ExternalDisplayTheme.orange.opacity(0.48)).frame(height: 1)
                Circle().fill(ExternalDisplayTheme.orange).frame(width: 6, height: 6)
            }
        }
        .scaleEffect(x: mirrored ? -1 : 1, y: 1)
        .accessibilityHidden(true)
    }
}

struct ExternalDisplayCardRule: View {
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Rectangle().fill(ExternalDisplayTheme.orange.opacity(0.38)).frame(height: 1)
                Circle().fill(ExternalDisplayTheme.orange.opacity(0.72)).frame(width: 4, height: 4)
            }
        }
        .accessibilityHidden(true)
    }
}

struct ExternalDisplayWaveStrip: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.25))
        let segment = rect.width / 3
        for index in 0 ..< 3 {
            let start = rect.minX + CGFloat(index) * segment
            path.addCurve(to: CGPoint(x: start + segment, y: rect.minY + rect.height * 0.25), control1: CGPoint(x: start + segment * 0.28, y: rect.minY), control2: CGPoint(x: start + segment * 0.72, y: rect.minY + rect.height * 0.57))
        }
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
