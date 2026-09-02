import Testing
@testable import CallDesk

@Suite("Matcha engine integration")
struct MatchaEngineIntegrationTests {
    @Test("Matcha renders Chinese speech on device")
    func rendersChineseSpeech() async throws {
        let synthesizer = MatchaSynthesizer()
        let cancellation = MatchaSynthesizer.CancellationFlag()
        let speech = try await synthesizer.synthesize(
            "请 零幺 号前来取餐",
            speakerID: 0,
            speed: 1,
            cancellation: cancellation
        )
        #expect(speech.samples.count > 0)
        #expect(speech.sampleRate == 22050)
    }
}
