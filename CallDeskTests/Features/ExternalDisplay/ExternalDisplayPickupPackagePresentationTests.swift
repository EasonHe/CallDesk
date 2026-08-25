import CoreGraphics
import SwiftUI
import Testing
@testable import CallDesk

@MainActor
@Suite("External display pickup-package presentation")
struct ExternalDisplayPickupPackagePresentationTests {
    @Test("Pickup package keeps the current call number on its ticket")
    func pickupPackageKeepsCurrentCallNumber() {
        let presentation = ExternalDisplayPickupPackagePresentation(currentNumber: "A027")

        #expect(presentation.ticketNumber == "A027")
    }

    @Test("Pickup ticket keeps the restaurant name above its number")
    func pickupTicketKeepsRestaurantName() {
        let presentation = ExternalDisplayPickupPackagePresentation(
            currentNumber: "01",
            storeName: "美味餐厅"
        )

        #expect(presentation.storeName == "美味餐厅")
    }

    @Test("Pickup ticket follows the package front tilt")
    func pickupTicketFollowsPackageTilt() {
        let presentation = ExternalDisplayPickupPackagePresentation(currentNumber: "01")

        #expect(presentation.rotationDegrees == 3)
    }

    @Test("Speaker waves occupy the right side of the glyph, separately from the horn")
    func speakerWavesOccupyRightSideOfGlyph() {
        let path = ExternalDisplaySpeakerWavePair().path(in: CGRect(x: 0, y: 0, width: 100, height: 80))

        #expect(path.boundingRect.minX > 46)
        #expect(path.boundingRect.maxX > 90)
    }
}
