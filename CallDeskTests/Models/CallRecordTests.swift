import Foundation
import Testing
@testable import CallDesk

@Suite("Call record domain model")
struct CallRecordTests {
    private let recordID = UUID(uuidString: "88888888-8888-8888-8888-888888888888")!
    private let actionID = UUID(uuidString: "99999999-9999-9999-9999-999999999999")!
    private let boardID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
    private let startedAt = Date(timeIntervalSinceReferenceDate: 100)

    @Test("Initializer defaults the first call to a queued record")
    func initializerCreatesFirstQueuedRecord() throws {
        let record = try makeRecord()

        #expect(record.id == recordID)
        #expect(record.actionID == actionID)
        #expect(record.boardID == boardID)
        #expect(record.repeatIndex == 0)
        #expect(record.result == .queued)
        #expect(record.completedAt == nil)
    }

    @Test("Initializer retains a nonnegative repeat index")
    func initializerRetainsRepeatIndex() throws {
        let record = try makeRecord(repeatIndex: 2)

        #expect(record.repeatIndex == 2)
    }

    @Test("Initializer rejects a negative repeat index")
    func initializerRejectsNegativeRepeatIndex() {
        #expect(throws: DomainValidationError.invalidRepeatIndex) {
            try makeRecord(repeatIndex: -1)
        }
    }

    @Test("Initializer rejects blank required snapshots")
    func initializerRejectsBlankRequiredSnapshots() {
        #expect(throws: DomainValidationError.emptyName(field: "actionTitleSnapshot")) {
            try CallRecord(
                id: recordID,
                actionTitleSnapshot: " \n ",
                spokenTextSnapshot: "Call A021",
                startedAt: startedAt
            )
        }
        #expect(throws: DomainValidationError.emptyText(field: "spokenTextSnapshot")) {
            try CallRecord(
                id: recordID,
                actionTitleSnapshot: "A021",
                spokenTextSnapshot: " \t ",
                startedAt: startedAt
            )
        }
    }

    @Test("Initializer rejects a completion date before the start date")
    func initializerRejectsInvalidDateOrder() {
        #expect(throws: DomainValidationError.invalidDateRange) {
            try makeRecord(
                completedAt: startedAt.addingTimeInterval(-1),
                result: .completed
            )
        }
    }

    @Test("Queued records reject a completion date")
    func queuedRecordRejectsCompletionDate() {
        #expect(throws: DomainValidationError.invalidDateRange) {
            try makeRecord(completedAt: startedAt.addingTimeInterval(1))
        }
    }

    @Test("Final results require a completion date", arguments: [
        CallResult.completed,
        .cancelled,
        .interrupted,
        .failed
    ])
    func initializerRequiresCompletionDateForFinalResult(result: CallResult) {
        #expect(throws: DomainValidationError.invalidDateRange) {
            try makeRecord(result: result)
        }
    }

    @Test("Failed records require a nonblank error description", arguments: [nil, " \n "])
    func failedRecordRequiresErrorDescription(errorDescription: String?) {
        #expect(throws: DomainValidationError.emptyText(field: "errorDescription")) {
            try CallRecord(
                id: recordID,
                actionTitleSnapshot: "A021",
                spokenTextSnapshot: "Call A021",
                startedAt: startedAt,
                completedAt: startedAt.addingTimeInterval(1),
                result: .failed,
                errorDescription: errorDescription
            )
        }
    }

    @Test("Initializer normalizes blank optional snapshots")
    func initializerNormalizesBlankOptionalSnapshots() throws {
        let record = try CallRecord(
            id: recordID,
            actionTitleSnapshot: "A021",
            spokenTextSnapshot: "Call A021",
            startedAt: startedAt,
            audioRouteName: " \t ",
            errorDescription: " \n "
        )

        #expect(record.audioRouteName == nil)
        #expect(record.errorDescription == nil)
    }

    @Test("Completing produces a terminal snapshot")
    func completingProducesTerminalSnapshot() throws {
        let queued = try makeRecord()
        let completed = try queued.completing(at: startedAt.addingTimeInterval(1))

        #expect(completed.result == .completed)
        #expect(completed.completedAt == startedAt.addingTimeInterval(1))
        #expect(completed.id == recordID)
        #expect(completed.actionID == actionID)
        #expect(completed.boardID == boardID)
        #expect(completed.repeatIndex == 0)
        #expect(completed.actionTitleSnapshot == "A021")
        #expect(completed.spokenTextSnapshot == "Please proceed to counter two.")
        #expect(completed.audioRouteName == "Built-in Speaker")
    }

    @Test("Failing produces a detached terminal snapshot")
    func failingProducesDetachedSnapshot() throws {
        let queued = try makeRecord()
        let failed = try queued.failing(
            at: startedAt.addingTimeInterval(1),
            message: " Audio unavailable "
        )

        #expect(queued.result == .queued)
        #expect(queued.completedAt == nil)
        #expect(failed.result == .failed)
        #expect(failed.completedAt == startedAt.addingTimeInterval(1))
        #expect(failed.errorDescription == "Audio unavailable")
        #expect(failed.actionTitleSnapshot == "A021")
        #expect(failed.spokenTextSnapshot == "Please proceed to counter two.")
        #expect(failed.audioRouteName == "Built-in Speaker")
    }

    @Test("Cancellation and interruption produce their terminal results")
    func terminalMethodsProduceTheirResults() throws {
        let queued = try makeRecord()

        let cancelled = try queued.cancelling(at: startedAt.addingTimeInterval(1))
        let interrupted = try queued.interrupting(at: startedAt.addingTimeInterval(2))

        #expect(cancelled.result == .cancelled)
        #expect(cancelled.completedAt == startedAt.addingTimeInterval(1))
        #expect(interrupted.result == .interrupted)
        #expect(interrupted.completedAt == startedAt.addingTimeInterval(2))
    }

    @Test("Terminal methods reject invalid dates and blank failure messages")
    func terminalMethodsRejectInvalidInputs() throws {
        let queued = try makeRecord()

        #expect(throws: DomainValidationError.invalidDateRange) {
            try queued.completing(at: startedAt.addingTimeInterval(-1))
        }
        #expect(throws: DomainValidationError.emptyText(field: "errorDescription")) {
            try queued.failing(at: startedAt.addingTimeInterval(1), message: " \n ")
        }
    }

    @Test("Terminal methods only transition queued records")
    func terminalMethodsOnlyTransitionQueuedRecords() throws {
        let completed = try makeRecord().completing(at: startedAt.addingTimeInterval(1))

        #expect(throws: DomainValidationError.invalidStateTransition) {
            try completed.cancelling(at: startedAt.addingTimeInterval(2))
        }
    }

    @Test("Codable round trip retains a valid record")
    func codableRoundTripRetainsRecord() throws {
        let record = try makeRecord()

        let decodedRecord = try JSONDecoder().decode(
            CallRecord.self,
            from: JSONEncoder().encode(record)
        )

        #expect(decodedRecord == record)
    }

    private func makeRecord(
        repeatIndex: Int = 0,
        completedAt: Date? = nil,
        result: CallResult = .queued
    ) throws -> CallRecord {
        try CallRecord(
            id: recordID,
            actionID: actionID,
            boardID: boardID,
            actionTitleSnapshot: "  A021  ",
            spokenTextSnapshot: " Please proceed to counter two. ",
            startedAt: startedAt,
            completedAt: completedAt,
            result: result,
            repeatIndex: repeatIndex,
            audioRouteName: " Built-in Speaker "
        )
    }
}
