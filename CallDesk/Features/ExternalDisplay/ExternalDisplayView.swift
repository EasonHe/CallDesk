import SwiftUI

/// The 16:9 restaurant call board shown on a connected external display.
struct ExternalDisplayView: View {
    @ObservedObject var presenter: ExternalDisplayPresenter

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .body) private var typeScale: CGFloat = 1

    var body: some View {
        GeometryReader { proxy in
            let canvasHeight = min(proxy.size.height, proxy.size.width * ExternalDisplayTheme.Layout.heightToWidth)
            let canvasWidth = canvasHeight * ExternalDisplayTheme.Layout.widthToHeight
            let canvasSize = CGSize(width: canvasWidth, height: canvasHeight)
            let mainCardWidth = canvasWidth * ExternalDisplayTheme.Layout.mainCardWidthRatio
            let headerWidth = canvasWidth * ExternalDisplayTheme.Layout.headerWidthRatio
            let recentRowWidth = canvasWidth * ExternalDisplayTheme.Layout.recentRowWidthRatio

            ZStack {
                ExternalDisplayTheme.background.ignoresSafeArea()

                ZStack {
                    backgroundFoliage(in: canvasSize)

                    header
                        .frame(width: headerWidth, height: canvasHeight * ExternalDisplayTheme.Layout.headerHeight)
                        .position(x: canvasWidth / 2, y: canvasHeight * ExternalDisplayTheme.Layout.headerCenter)

                    currentCallCard
                        .frame(width: mainCardWidth, height: canvasHeight * ExternalDisplayTheme.Layout.currentCardHeight)
                        .position(x: canvasWidth / 2, y: canvasHeight * ExternalDisplayTheme.Layout.currentCardCenter)

                    if showsRecentCalls {
                        recentHeading
                            .frame(width: recentRowWidth, height: canvasHeight * ExternalDisplayTheme.Layout.recentHeadingHeight)
                            .position(x: canvasWidth / 2, y: canvasHeight * ExternalDisplayTheme.Layout.recentHeadingCenter)

                        recentCallsRow
                            .frame(width: recentRowWidth, height: canvasHeight * ExternalDisplayTheme.Layout.recentCardsHeight)
                            .position(x: canvasWidth / 2, y: canvasHeight * ExternalDisplayTheme.Layout.recentCardsCenter)
                    }

                    bottomNotice
                        .frame(width: recentRowWidth, height: canvasHeight * ExternalDisplayTheme.Layout.footerHeight)
                        .position(x: canvasWidth / 2, y: canvasHeight * ExternalDisplayTheme.Layout.footerCenter)
                }
                .frame(width: canvasWidth, height: canvasHeight)
            }
        }
        .environment(\.colorScheme, .light)
    }

    private var liveCall: LiveCallState { presenter.presentation.liveCall }
    private var visibleRecentCalls: [RecentCallPresentation] { presenter.presentation.recentCalls }

    private var showsRecentCalls: Bool {
        presenter.displaySettings.recentCallCount > 0
    }

    private var isCallActive: Bool {
        switch liveCall.phase {
        case .queued, .preparing, .playingPrompt, .speaking: true
        case .idle, .completed, .cancelled, .interrupted, .failed: false
        }
    }

    private var currentCallLayout: ExternalDisplayCurrentCallLayout {
        ExternalDisplayCurrentCallLayout.make(
            for: liveCall,
            mostRecentNumber: visibleRecentCalls.first?.title
        )
    }

    private var currentNumber: String { currentCallLayout.title }

    private var header: some View {
        HStack(alignment: .center, spacing: 18) {
            HStack(spacing: 10) {
                ZStack {
                    Circle().fill(ExternalDisplayTheme.orangeGradient)
                    ExternalDisplayClocheMark(color: .white)
                        .frame(width: 37, height: 30)
                }
                .frame(width: 72, height: 72)
                .shadow(color: ExternalDisplayTheme.orange.opacity(0.18), radius: 8, y: 4)

                VStack(alignment: .leading, spacing: 1) {
                    Text(presenter.displaySettings.restaurantTitle)
                        .font(.system(size: 37 * typeScale, weight: .heavy, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.56)
                    Text("DELICIOUS RESTAURANT")
                        .font(.system(size: 13 * typeScale, weight: .semibold, design: .rounded))
                        .tracking(0.7)
                        .foregroundStyle(ExternalDisplayTheme.deepBrown)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
            }
            .frame(width: ExternalDisplayTheme.Layout.headerSideWidth, alignment: .leading)

            VStack(spacing: 2) {
                HStack(spacing: 12) {
                    ExternalDisplayFlourish()
                        .frame(width: 43, height: 17)
                    Text("欢迎光临 · 请留意叫号信息")
                        .font(.system(size: 42 * typeScale, weight: .heavy, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.58)
                    ExternalDisplayFlourish(mirrored: true)
                        .frame(width: 43, height: 17)
                }
                Text("WELCOME · PLEASE PAY ATTENTION TO YOUR PICKUP NUMBER")
                    .font(.system(size: 14 * typeScale, weight: .semibold, design: .rounded))
                    .tracking(0.7)
                    .foregroundStyle(ExternalDisplayTheme.deepBrown)
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)

            TimelineView(.periodic(from: .now, by: 60)) { context in
                VStack(alignment: .trailing, spacing: 1) {
                    Text(ExternalDisplayTheme.timeText(for: context.date))
                        .font(.system(size: 56 * typeScale, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                    Text(ExternalDisplayTheme.dateText(for: context.date))
                        .font(.system(size: 17 * typeScale, weight: .semibold, design: .rounded))
                        .foregroundStyle(ExternalDisplayTheme.orange)
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                }
                .frame(width: ExternalDisplayTheme.Layout.headerSideWidth, alignment: .trailing)
            }
        }
        .foregroundStyle(ExternalDisplayTheme.deepBrown)
        .accessibilityElement(children: .combine)
    }

    private var currentCallCard: some View {
        GeometryReader { proxy in
            ZStack {
                // Fade the restaurant scene into the cream centre. This avoids
                // a hard, vertical split between the live number and its
                // takeaway setting on a large external display.
                pickupScene
                    .frame(width: proxy.size.width * 0.47, height: proxy.size.height)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)

                currentNumberPanel
                    .frame(width: proxy.size.width * 0.62, height: proxy.size.height)
                    .position(x: proxy.size.width * 0.50, y: proxy.size.height / 2)

                currentStatusPanel
                    .frame(width: proxy.size.width * ExternalDisplayTheme.Layout.currentStatusVisualWidth)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)

                currentCardDecorations(in: proxy.size)

                pickupTicket
                    .frame(
                        width: proxy.size.width * ExternalDisplayTheme.Layout.pickupTicketWidthRatio,
                        height: proxy.size.height * ExternalDisplayTheme.Layout.pickupTicketHeightRatio
                    )
                    .position(
                        x: proxy.size.width * ExternalDisplayTheme.Layout.pickupTicketXRatio,
                        y: proxy.size.height * ExternalDisplayTheme.Layout.pickupTicketYRatio
                    )
            }
        }
        .background(ExternalDisplayTheme.mainCardGradient)
        .clipShape(RoundedRectangle(cornerRadius: ExternalDisplayTheme.Layout.mainCardRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: ExternalDisplayTheme.Layout.mainCardRadius, style: .continuous)
                .stroke(.white, lineWidth: 1.5)
        }
        .shadow(color: ExternalDisplayTheme.deepBrown.opacity(0.16), radius: 14, y: 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("当前叫号 \(currentNumber)，请前往取餐台取餐")
    }

    private var currentStatusPanel: some View {
        GeometryReader { proxy in
            ZStack {
                ExternalDisplayStatusPanelShape()
                    .fill(ExternalDisplayTheme.orangeGradient)

                VStack(spacing: 10) {
                    Circle()
                        .fill(.white.opacity(0.96))
                        .frame(width: 136, height: 136)
                        .shadow(color: ExternalDisplayTheme.deepBrown.opacity(0.12), radius: 5, y: 3)
                        .overlay {
                            ExternalDisplaySpeakerGlyph(color: ExternalDisplayTheme.orange)
                                .frame(width: 70, height: 61)
                        }
                    Text("正在叫号")
                        .font(.system(size: 42 * typeScale, weight: .heavy, design: .rounded))
                    Text("NOW CALLING")
                        .font(.system(size: 21 * typeScale, weight: .semibold, design: .rounded))
                        .tracking(0.35)
                    Capsule()
                        .fill(.white.opacity(0.9))
                        .frame(width: 52, height: 6)
                        .padding(.top, 2)
                }
                .foregroundStyle(.white)
                .frame(width: ExternalDisplayTheme.Layout.currentStatusContentWidth)
                .position(
                    x: proxy.size.width * ExternalDisplayTheme.Layout.currentStatusContentCenterX,
                    y: proxy.size.height * ExternalDisplayTheme.Layout.currentStatusContentCenterY
                )
            }
        }
        .accessibilityHidden(true)
    }

    private func currentCardDecorations(in size: CGSize) -> some View {
        ZStack {
            ExternalDisplayHalftoneDots(color: .white.opacity(0.22), columns: 5, rows: 4)
                .frame(width: size.width * 0.043, height: size.height * 0.15)
                .position(x: size.width * 0.043, y: size.height * 0.17)

            ExternalDisplayStatusRibbons()
                .fill(.white.opacity(0.12))
                .frame(width: size.width * ExternalDisplayTheme.Layout.currentStatusVisualWidth, height: size.height * 0.27)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)

            ExternalDisplayRadiatingMarks(color: ExternalDisplayTheme.orange)
                .frame(width: 58, height: 56)
                .position(x: size.width * 0.79, y: size.height * 0.15)

            ExternalDisplayHalftoneDots(color: ExternalDisplayTheme.orange.opacity(0.18), columns: 5, rows: 5)
                .frame(width: size.width * 0.09, height: size.height * 0.27)
                .position(x: size.width * 0.80, y: size.height * 0.77)
        }
        .accessibilityHidden(true)
    }

    private var pickupTicket: some View {
        ExternalDisplayPickupTicket(
            presentation: ExternalDisplayPickupPackagePresentation(
                currentNumber: currentNumber,
                storeName: presenter.displaySettings.restaurantTitle
            )
        )
    }

    private var currentNumberPanel: some View {
        VStack(spacing: 2) {
            Text(currentNumber)
                .font(.system(size: currentCallLayout.titleFontSize * typeScale, weight: .black, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.2)
                .foregroundStyle(ExternalDisplayTheme.orangeGradient)
                .padding(.top, 8)

            HStack(spacing: 11) {
                ExternalDisplayRuleDot()
                .frame(width: 138, height: 9)
                Text("请前往取餐台取餐")
                    .font(.system(size: 39 * typeScale, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                ExternalDisplayRuleDot(mirrored: true)
                    .frame(width: 138, height: 9)
            }
            .foregroundStyle(ExternalDisplayTheme.deepBrown)
            .padding(.bottom, 15)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private var pickupScene: some View {
        GeometryReader { proxy in
            ZStack {
                ExternalDisplayRasterImage(name: "pickup-scene-direct-print-v5")
                    .scaledToFill()
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()
                    // A cream wash keeps the restaurant photo present without
                    // letting its contrast overpower the white number panel.
                    .overlay(ExternalDisplayTheme.sceneWash.opacity(0.25))
            }
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .white.opacity(0.12), location: 0.18),
                        .init(color: .white, location: 0.48)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
        }
        .clipped()
        .accessibilityHidden(true)
    }

    private var recentHeading: some View {
        HStack(spacing: 11) {
            Rectangle().fill(ExternalDisplayTheme.orange.opacity(0.34)).frame(width: 64, height: 1)
            ExternalDisplayFlourish().frame(width: 35, height: 16)
            Text("最近叫号")
                .font(.system(size: 34 * typeScale, weight: .heavy, design: .rounded))
            ExternalDisplayFlourish(mirrored: true).frame(width: 35, height: 16)
            Rectangle().fill(ExternalDisplayTheme.orange.opacity(0.34)).frame(width: 64, height: 1)
        }
        .foregroundStyle(ExternalDisplayTheme.deepBrown)
        .accessibilityElement(children: .combine)
    }

    private var recentCallsRow: some View {
        GeometryReader { proxy in
            let layout = ExternalDisplayRecentCallGridLayout.make(
                in: proxy.size,
                itemCount: visibleRecentCalls.count
            )

            if layout.columns > 0 {
                LazyVGrid(
                    columns: Array(
                        repeating: GridItem(.flexible(), spacing: layout.horizontalSpacing),
                        count: layout.columns
                    ),
                    spacing: layout.verticalSpacing
                ) {
                    ForEach(visibleRecentCalls) { call in
                        recentCallCard(call, layout: layout)
                            .frame(height: layout.cardSize.height)
                    }
                }
            }
        }
    }

    private func recentCallCard(
        _ call: RecentCallPresentation,
        layout: ExternalDisplayRecentCallGridLayout
    ) -> some View {
        let appearance = ExternalDisplayRecentCallStyle.cardAppearance(for: call, during: liveCall)
        let horizontalPadding = min(17, max(8, layout.cardSize.width * 0.07))
        let verticalPadding = min(12, max(6, layout.cardSize.height * 0.08))
        let iconSize = min(25, max(12, layout.metadataFontSize * 1.1))
        let stripHeight = min(35, max(18, layout.cardSize.height * 0.18))
        let cardRadius = min(ExternalDisplayTheme.Layout.recentCardRadius, layout.cardSize.height * 0.2)

        return VStack(spacing: 0) {
            HStack(spacing: 4) {
                ExternalDisplayClockGlyph(color: ExternalDisplayTheme.orange)
                    .frame(width: iconSize, height: iconSize)
                Text(call.calledAt.formatted(date: .omitted, time: .shortened))
                    .font(.system(size: layout.metadataFontSize * typeScale, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                Spacer(minLength: 0)
                ExternalDisplaySpeakerGlyph(color: ExternalDisplayTheme.orange)
                    .frame(width: iconSize * 1.2, height: iconSize)
            }
            .foregroundStyle(ExternalDisplayTheme.deepBrown)

            Spacer(minLength: 4)
            Text(call.title)
                .font(.system(size: layout.numberFontSize * typeScale, weight: .black, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.3)
                .foregroundStyle(ExternalDisplayTheme.deepBrown)
            Spacer(minLength: 3)
            VStack(spacing: 1) {
                ExternalDisplayCardRule()
                    .frame(width: min(88, layout.cardSize.width * 0.55), height: max(3, layout.metadataFontSize * 0.25))
                Text("已叫号")
                    .font(.system(size: layout.metadataFontSize * typeScale, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
            }
            .foregroundStyle(ExternalDisplayTheme.deepBrown)
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, verticalPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(alignment: .bottom) {
            ExternalDisplayWaveStrip()
                .fill(ExternalDisplayTheme.stripCream)
                .frame(height: stripHeight)
        }
        .background(
            RoundedRectangle(cornerRadius: cardRadius, style: .continuous)
                .fill(appearance.isHighlighted ? ExternalDisplayTheme.highlightCream : ExternalDisplayTheme.recentCardCream)
        )
        .clipShape(RoundedRectangle(cornerRadius: cardRadius, style: .continuous))
        .shadow(color: ExternalDisplayTheme.deepBrown.opacity(0.09), radius: 6, y: 3)
        .overlay {
            RecentCallGlow(isHighlighted: appearance.isHighlighted, reduceMotion: reduceMotion)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("已叫号 \(call.title)，时间 \(call.calledAt.formatted(date: .omitted, time: .shortened))")
    }

    private var bottomNotice: some View {
        HStack(spacing: 11) {
            ExternalDisplayRuleDot()
                .frame(width: 105, height: 7)
            ExternalDisplayBellGlyph(color: ExternalDisplayTheme.orange)
                .frame(width: 19, height: 19)
            Text("请留意叫号信息，感谢您的耐心等待！")
                .font(.system(size: 24 * typeScale, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.65)
            ExternalDisplayRuleDot(mirrored: true)
                .frame(width: 105, height: 7)
        }
        .foregroundStyle(ExternalDisplayTheme.deepBrown)
        .accessibilityElement(children: .combine)
    }

    private func backgroundFoliage(in size: CGSize) -> some View {
        return ZStack {
            ExternalDisplayRasterImage(name: "botanical-bottom-v2")
                .scaledToFill()
                .frame(width: size.width, height: size.height)
                // The artwork is a full-canvas source. Compress it against
                // the lower edge so only the subdued ground and corner plants
                // remain in the lowest fifth of the display.
                .scaleEffect(
                    x: 1,
                    y: ExternalDisplayTheme.Layout.botanicalVerticalScale,
                    anchor: .bottom
                )
                .opacity(ExternalDisplayTheme.Layout.botanicalOpacity)

            ExternalDisplayRasterImage(name: "top-left-branch-crop-v4")
                .scaledToFit()
                .frame(width: 180, height: 205)
                .opacity(0.86)
                .position(x: 65, y: 78)

        }
        .frame(width: size.width, height: size.height)
        .clipped()
        .accessibilityHidden(true)
    }
}

private struct RecentCallGlow: View {
    let isHighlighted: Bool
    let reduceMotion: Bool

    @State private var opacity = 0.18

    private var shouldGlow: Bool { isHighlighted && !reduceMotion }

    var body: some View {
        Group {
            if shouldGlow {
                RoundedRectangle(cornerRadius: ExternalDisplayTheme.Layout.recentCardRadius, style: .continuous)
                    .stroke(ExternalDisplayTheme.orange.opacity(opacity), lineWidth: 5)
                    .blur(radius: 5)
                    .onAppear {
                        opacity = 0.18
                        withAnimation(.easeInOut(duration: 0.85).repeatForever(autoreverses: true)) {
                            opacity = 0.72
                        }
                    }
            }
        }
        .animation(.none, value: shouldGlow)
    }
}
