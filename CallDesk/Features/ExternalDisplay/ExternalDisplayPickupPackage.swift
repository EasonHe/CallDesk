import SwiftUI

/// The rendered ticket makes the right-hand takeaway package part of the live
/// call state instead of a decorative, static icon.
struct ExternalDisplayPickupPackagePresentation: Equatable {
    /// The photographed bag front slopes gently down toward its right edge.
    /// Keep the live print aligned to that physical plane rather than level
    /// with the screen.
    static let frontTiltDegrees = 3.0

    let ticketNumber: String
    let storeName: String?

    var rotationDegrees: Double {
        Self.frontTiltDegrees
    }

    init(currentNumber: String, storeName: String? = nil) {
        ticketNumber = currentNumber
        self.storeName = storeName
    }
}

/// Direct ink-style copy on the package front. There is intentionally no
/// synthetic sticker or card layered over the photographed kraft paper.
struct ExternalDisplayPickupTicket: View {
    let presentation: ExternalDisplayPickupPackagePresentation

    var body: some View {
        VStack(spacing: 4) {
            if let storeName = presentation.storeName, !storeName.isEmpty {
                Text(storeName)
                    .font(.system(size: 26, weight: .heavy, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.45)
                    .tracking(1.2)
                    .foregroundStyle(ExternalDisplayTheme.deepBrown)
            }

            HStack(spacing: 5) {
                Capsule()
                    .fill(ExternalDisplayTheme.orange.opacity(0.70))
                    .frame(width: 25, height: 1)
                Circle()
                    .fill(ExternalDisplayTheme.orange.opacity(0.82))
                    .frame(width: 4, height: 4)
                Capsule()
                    .fill(ExternalDisplayTheme.orange.opacity(0.70))
                    .frame(width: 25, height: 1)
            }

            Text("\(presentation.ticketNumber)号")
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .minimumScaleFactor(0.48)
                .lineLimit(1)
                .foregroundStyle(ExternalDisplayTheme.orange)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .rotationEffect(.degrees(presentation.rotationDegrees))
        .blendMode(.multiply)
        .opacity(0.82)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("取餐包装，号码 \(presentation.ticketNumber)")
    }
}
