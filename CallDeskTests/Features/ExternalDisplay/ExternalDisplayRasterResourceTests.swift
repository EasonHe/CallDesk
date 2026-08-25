import Testing
@testable import CallDesk

@MainActor
@Suite("External display raster resources")
struct ExternalDisplayRasterResourceTests {
    @Test("Loads the packaged restaurant scene PNG")
    func loadsRestaurantScene() {
        #expect(ExternalDisplayRasterResource.load(named: "pickup-scene-v2") != nil)
    }

    @Test("Loads the packaged botanical PNG")
    func loadsBotanicalFrame() {
        #expect(ExternalDisplayRasterResource.load(named: "botanical-bottom-v2") != nil)
    }
}
