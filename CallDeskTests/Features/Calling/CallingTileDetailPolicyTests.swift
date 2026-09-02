import Foundation
import Testing
@testable import CallDesk

@Suite("Calling tile detail policy")
struct CallingTileDetailPolicyTests {
    @Test("Audio actions do not show their stored fallback speech text")
    func audioActionsSuppressFallbackSpeechText() throws {
        let boardID = UUID()
        let audioAction = try CallAction(
            boardID: boardID,
            title: "A001",
            speechText: "请 A001 号顾客前来取餐。",
            playbackMode: .audio,
            audioFileName: "01.mp3"
        )
        let textAction = try CallAction(
            boardID: boardID,
            title: "A001",
            speechText: "请 A001 号顾客前来取餐。",
            playbackMode: .text
        )

        #expect(!CallingTileDetailPolicy.shouldShow(for: audioAction, isEnabled: true))
        #expect(CallingTileDetailPolicy.shouldShow(for: textAction, isEnabled: true))
    }
}
