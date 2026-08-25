import Foundation
import Testing

@testable import CallDesk

@Suite(.serialized)
struct CallDeskSampleDataTests {
    @Test
    func catalogUsesFixedAndConsistentRelationships() {
        let catalog = CallDeskSampleData.catalog

        #expect(catalog.workspace.id == UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
        #expect(Set(catalog.actions.map(\.id)).count == catalog.actions.count)
        #expect(Set(catalog.boards.map(\.id)).isSuperset(of: Set(catalog.actions.map(\.boardID))))
    }

    @Test
    func staticCatalogAndFactoryAreDeterministic() {
        #expect(CallDeskSampleData.catalog == CallDeskSampleData.catalog)
        #expect(CallDeskSampleData.makeCatalog() == CallDeskSampleData.catalog)
        #expect(CallDeskSampleData.actions == CallDeskSampleData.makeActions())
    }

    @Test
    func templatesRenderInChinese() throws {
        #expect(try CallDeskSampleData.diningQueueTemplate.render(values: [
            "number": "A021"
        ]) == "请，A021 号，前来取餐。")
    }

}
