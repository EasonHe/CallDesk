import Foundation

extension Array {
    /// Reorders elements the same way SwiftUI's `move(fromOffsets:toOffset:)`
    /// does, without requiring a SwiftUI import in view models.
    mutating func applyMove(fromOffsets offsets: IndexSet, toOffset destination: Int) {
        let movedElements = offsets.sorted().map { self[$0] }
        let adjustedDestination = destination - offsets.count { $0 < destination }
        for offset in offsets.sorted(by: >) {
            remove(at: offset)
        }
        insert(contentsOf: movedElements, at: adjustedDestination)
    }
}
