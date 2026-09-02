import Foundation
import Testing
@testable import CallDesk

@Suite("Voice template domain model")
struct VoiceTemplateTests {
    private let templateID = UUID(uuidString: "77777777-7777-7777-7777-777777777777")!
    private let date = Date(timeIntervalSinceReferenceDate: 100)

    @Test("Initializer extracts flat placeholders from a Chinese template")
    func initializerExtractsChinesePlaceholders() throws {
        let template = try VoiceTemplate(
            id: templateID,
            name: "  Queue  ",
            templateText: "请 {number} 到 {counter}。",
            localeIdentifier: "  zh-Hans  ",
            now: date
        )

        #expect(template.id == templateID)
        #expect(template.name == "Queue")
        #expect(template.localeIdentifier == "zh-Hans")
        #expect(template.isBuiltIn == false)
        #expect(template.placeholders == ["number", "counter"])
        #expect(
            try template.render(values: [
                "number": " A021 ",
                "counter": " 3号窗口 "
            ]) == "请 A021 到 3号窗口。"
        )
    }

    @Test("Render trims supplied values in an English template")
    func renderTrimsValuesInEnglishTemplate() throws {
        let template = try VoiceTemplate(
            id: templateID,
            name: "Queue",
            templateText: "Now serving {number} at {counter}.",
            localeIdentifier: "en-US",
            now: date
        )

        let text = try template.render(values: [
            "number": " A021 ",
            "counter": " 3 ",
            "unused": "ignored"
        ])

        #expect(text == "Now serving A021 at 3.")
    }

    @Test("Render reports the first missing placeholder value")
    func renderReportsMissingValue() throws {
        let template = try VoiceTemplate(
            id: templateID,
            name: "Queue",
            templateText: "请 {number} 到 {counter}。",
            localeIdentifier: "zh-Hans",
            now: date
        )

        #expect(throws: DomainValidationError.missingTemplateValue("number")) {
            try template.render(values: [:])
        }
    }

    @Test("Initializer rejects malformed placeholder syntax", arguments: [
        "Call {}",
        "Call {number",
        "Call number}",
        "Call {{number}}",
        "Call {number{suffix}}",
        "Call {queue-number}"
    ])
    func initializerRejectsMalformedTemplate(templateText: String) {
        #expect(throws: DomainValidationError.malformedTemplate) {
            try VoiceTemplate(
                id: templateID,
                name: "Queue",
                templateText: templateText,
                localeIdentifier: "en-US",
                now: date
            )
        }
    }

    @Test("Initializer rejects blank required template fields")
    func initializerRejectsBlankRequiredFields() {
        #expect(throws: DomainValidationError.emptyName(field: "name")) {
            try VoiceTemplate(
                id: templateID,
                name: " \n ",
                templateText: "Call {number}",
                localeIdentifier: "en-US",
                now: date
            )
        }
        #expect(throws: DomainValidationError.emptyText(field: "templateText")) {
            try VoiceTemplate(
                id: templateID,
                name: "Queue",
                templateText: " \t ",
                localeIdentifier: "en-US",
                now: date
            )
        }
        #expect(throws: DomainValidationError.emptyText(field: "localeIdentifier")) {
            try VoiceTemplate(
                id: templateID,
                name: "Queue",
                templateText: "Call {number}",
                localeIdentifier: " \n ",
                now: date
            )
        }
    }

    @Test("Initializer rejects an update date before creation")
    func initializerRejectsInvalidDateOrder() {
        #expect(throws: DomainValidationError.invalidDateRange) {
            try VoiceTemplate(
                id: templateID,
                name: "Queue",
                templateText: "Call {number}",
                localeIdentifier: "en-US",
                createdAt: date,
                updatedAt: date.addingTimeInterval(-1)
            )
        }
    }

    @Test("Built-in templates deduplicate placeholder names while rendering every occurrence")
    func builtInTemplateDeduplicatesPlaceholderNames() throws {
        let template = try VoiceTemplate(
            id: templateID,
            name: "Queue",
            templateText: "{number}, please proceed. {number}.",
            localeIdentifier: "en-US",
            isBuiltIn: true,
            now: date
        )

        #expect(template.isBuiltIn == true)
        #expect(template.placeholders == ["number"])
        #expect(try template.render(values: ["number": " A021 "]) == "A021, please proceed. A021.")
    }

    @Test("Render detects missing values after earlier placeholders are supplied")
    func renderDetectsLaterMissingValue() throws {
        let template = try VoiceTemplate(
            id: templateID,
            name: "Queue",
            templateText: "{number} at {counter}",
            localeIdentifier: "en-US",
            now: date
        )

        #expect(throws: DomainValidationError.missingTemplateValue("counter")) {
            try template.render(values: ["number": "A021"])
        }
    }

    @Test("Render rejects malformed text introduced after initialization")
    func renderRejectsMalformedMutatedTemplate() throws {
        var template = try VoiceTemplate(
            id: templateID,
            name: "Queue",
            templateText: "Call {number}",
            localeIdentifier: "en-US",
            now: date
        )
        template.templateText = "Call {number"

        #expect(throws: DomainValidationError.malformedTemplate) {
            try template.render(values: ["number": "A021"])
        }
    }

    @Test("Codable round trip retains a valid template")
    func codableRoundTripRetainsTemplate() throws {
        let template = try VoiceTemplate(
            id: templateID,
            name: "Queue",
            templateText: "Call {number}",
            localeIdentifier: "en-US",
            now: date
        )

        let decodedTemplate = try JSONDecoder().decode(
            VoiceTemplate.self,
            from: JSONEncoder().encode(template)
        )

        #expect(decodedTemplate == template)
    }
}
