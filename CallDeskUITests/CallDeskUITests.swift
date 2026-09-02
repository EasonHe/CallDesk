//
//  CallDeskUITests.swift
//  CallDeskUITests
//
//  Created by 何玮 on 2026/7/30.
//

import XCTest

final class CallDeskUITests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    @MainActor
    func testDisplaysFourPrimaryTabs() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "-calldesk-ui-test",
            "-AppleLanguages", "(zh-Hans)",
            "-AppleLocale", "zh_CN"
        ]
        app.launch()

        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(
            tabBar.waitForExistence(timeout: 5),
            "System tab bar did not appear within 5 seconds"
        )
        for title in ["叫号", "数据", "面板", "设置"] {
            XCTAssertTrue(
                tabBar.buttons[title].waitForExistence(timeout: 5),
                "Missing \(title) tab"
            )
        }
    }

    @MainActor
    func testAboutScreenShowsPrivacyAndSupportLinks() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "-calldesk-ui-test",
            "-AppleLanguages", "(zh-Hans)",
            "-AppleLocale", "zh_CN"
        ]
        app.launch()

        let settingsButton = app.tabBars.firstMatch.buttons["设置"]
        XCTAssertTrue(
            settingsButton.waitForExistence(timeout: 5),
            "Settings tab did not appear within 5 seconds"
        )
        XCTAssertTrue(settingsButton.isHittable, "Settings tab was not hittable")
        settingsButton.tap()
        XCTAssertTrue(
            app.navigationBars["设置"].waitForExistence(timeout: 5),
            "Settings screen did not appear within 5 seconds"
        )

        let aboutButton = app.buttons["关于 CallDesk"]
        for _ in 0..<5 {
            if aboutButton.exists && aboutButton.isHittable {
                break
            }
            app.swipeUp()
        }
        XCTAssertTrue(
            aboutButton.waitForExistence(timeout: 5),
            "About CallDesk link did not appear within 5 seconds"
        )
        XCTAssertTrue(aboutButton.isHittable, "About CallDesk link was not hittable")
        aboutButton.tap()

        XCTAssertTrue(app.links["隐私政策"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.links["技术支持"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testCallingContentSupportsAccessibilityTextSize() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "-calldesk-ui-test",
            "-AppleLanguages", "(zh-Hans)",
            "-AppleLocale", "zh_CN",
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge"
        ]
        app.launch()

        let sampleAction = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "A021")
        ).firstMatch
        XCTAssertTrue(
            sampleAction.waitForExistence(timeout: 5),
            "Sample calling action did not appear within 5 seconds"
        )

        XCTAssertTrue(
            app.scrollViews.firstMatch.waitForExistence(timeout: 2),
            "Calling content did not provide a scroll view within 2 seconds"
        )
    }

    @MainActor
    func testClearCalledActionsShowsConfirmation() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "-calldesk-ui-test",
            "-AppleLanguages", "(zh-Hans)",
            "-AppleLocale", "zh_CN"
        ]
        app.launch()

        performCall(app, title: "A021")

        let clearButton = app.navigationBars.buttons["清除已呼叫"]
        XCTAssertTrue(
            clearButton.waitForExistence(timeout: 5),
            "Calling screen did not expose the clear button"
        )
        clearButton.tap()

        let confirmationAction = app.buttons["清除"]
        XCTAssertTrue(
            confirmationAction.waitForExistence(timeout: 5),
            "Clearing called actions did not present a confirmation dialog"
        )
    }

    @MainActor
    func testBoardAndActionManagementFlow() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "-calldesk-ui-test",
            "-AppleLanguages", "(zh-Hans)",
            "-AppleLocale", "zh_CN"
        ]
        app.launch()

        let boardsTab = app.tabBars.firstMatch.buttons["面板"]
        XCTAssertTrue(
            boardsTab.waitForExistence(timeout: 5),
            "Boards tab did not appear within 5 seconds"
        )
        boardsTab.tap()

        // Create a board.
        let addBoardButton = app.navigationBars.buttons["新建面板"]
        XCTAssertTrue(
            addBoardButton.waitForExistence(timeout: 5),
            "Add Board button did not appear within 5 seconds"
        )
        addBoardButton.tap()

        let nameField = app.textFields["名称"]
        XCTAssertTrue(
            nameField.waitForExistence(timeout: 5),
            "Board name field did not appear within 5 seconds"
        )
        nameField.tap()
        nameField.typeText("Smoke Board")
        app.navigationBars.buttons["保存"].tap()

        let boardRow = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "Smoke Board")
        ).firstMatch
        XCTAssertTrue(
            boardRow.waitForExistence(timeout: 5),
            "Created board did not appear within 5 seconds"
        )

        // Create an action inside the new board.
        if !boardRow.isHittable {
            app.swipeUp()
        }
        boardRow.tap()
        // The add entry is a toolbar menu whose label matches its first
        // item, so the menu button is tapped first and then the item
        // that appears inside the opened menu (the last match).
        let addMenu = app.navigationBars.buttons["添加叫号项"]
        XCTAssertTrue(
            addMenu.waitForExistence(timeout: 5),
            "Add Action menu did not appear within 5 seconds"
        )
        addMenu.tap()

        // The opened menu exposes both items; waiting for the second one
        // guarantees the menu is up before the first item is tapped.
        XCTAssertTrue(
            app.buttons["批量添加"].waitForExistence(timeout: 5),
            "Add Action menu did not open within 5 seconds"
        )
        let addItemMatches = app.buttons.matching(
            NSPredicate(format: "label == %@", "添加叫号项")
        )
        let addItem = addItemMatches.element(boundBy: addItemMatches.count - 1)
        addItem.tap()

        let titleField = app.textFields["标题"]
        XCTAssertTrue(
            titleField.waitForExistence(timeout: 5),
            "Action title field did not appear within 5 seconds"
        )
        titleField.tap()
        titleField.typeText("Z001")

        let speechField = app.textViews["播报文本"].exists
            ? app.textViews["播报文本"]
            : app.textFields["播报文本"]
        speechField.tap()
        speechField.typeText("Please call Z001")
        app.navigationBars.buttons["保存"].tap()

        let actionRow = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "Z001")
        ).firstMatch
        XCTAssertTrue(
            actionRow.waitForExistence(timeout: 5),
            "Created action did not appear within 5 seconds"
        )
    }

    @MainActor
    func testHistoryManagementFlow() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "-calldesk-ui-test",
            "-AppleLanguages", "(zh-Hans)",
            "-AppleLocale", "zh_CN"
        ]
        app.launch()

        // History starts empty by design, so real calls create the records.
        performCall(app, title: "A021")
        performCall(app, title: "A022")
        openHistoryTab(app)

        // Both calls show up in the history list.
        let firstRow = historyRow(app, containing: "A021")
        XCTAssertTrue(
            firstRow.waitForExistence(timeout: 5),
            "First history record did not appear within 5 seconds"
        )
        let secondRow = historyRow(app, containing: "A022")
        XCTAssertTrue(
            secondRow.waitForExistence(timeout: 5),
            "Second history record did not appear within 5 seconds"
        )

        // Open the detail page from a row.
        openHistoryDetail(app, row: secondRow)
        XCTAssertTrue(
            app.buttons["再次呼叫"].waitForExistence(timeout: 5),
            "History detail did not show the Call Again button within 5 seconds"
        )
        XCTAssertTrue(
            app.staticTexts["结果"].exists,
            "History detail did not show the result row"
        )
        app.navigationBars.buttons.element(boundBy: 0).tap()

        // Filtering by a result that has no records shows the empty filter
        // state, and clearing the filters restores the list.
        let filterButton = app.navigationBars.buttons["筛选"]
        XCTAssertTrue(
            filterButton.waitForExistence(timeout: 5),
            "Filter button did not appear within 5 seconds"
        )
        filterButton.tap()
        let failedFilter = app.buttons["失败"]
        XCTAssertTrue(
            failedFilter.waitForExistence(timeout: 5),
            "Failed filter option did not appear within 5 seconds"
        )
        failedFilter.tap()
        XCTAssertTrue(
            app.staticTexts["没有匹配的记录"].waitForExistence(timeout: 5),
            "Filtered empty state did not appear within 5 seconds"
        )
        app.buttons["清除筛选"].tap()
        XCTAssertTrue(
            historyRow(app, containing: "A021").waitForExistence(timeout: 5),
            "Records did not come back after clearing the filters"
        )

        // Delete one record with a swipe and a confirmation.
        let rowToDelete = historyRow(app, containing: "A022")
        XCTAssertTrue(
            rowToDelete.waitForExistence(timeout: 5),
            "Record to delete did not appear within 5 seconds"
        )
        rowToDelete.swipeLeft()
        let deleteAction = app.buttons["删除"]
        XCTAssertTrue(
            deleteAction.waitForExistence(timeout: 5),
            "Swipe delete action did not appear within 5 seconds"
        )
        deleteAction.tap()
        confirmDialogAction(app, "删除")
        waitForDisappearance(historyRow(app, containing: "A022"))

        // Clear the remaining history from edit mode.
        app.navigationBars.buttons["编辑"].tap()
        let clearButton = app.buttons["清空历史"]
        XCTAssertTrue(
            clearButton.waitForExistence(timeout: 5),
            "Clear History button did not appear within 5 seconds"
        )
        clearButton.tap()
        confirmDialogAction(app, "删除")
        XCTAssertTrue(
            app.staticTexts["暂无历史"].waitForExistence(timeout: 5),
            "Empty state did not appear after clearing the history"
        )
    }

    @MainActor
    func testHistoryRecallFromDetailFlow() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "-calldesk-ui-test",
            "-AppleLanguages", "(zh-Hans)",
            "-AppleLocale", "zh_CN"
        ]
        app.launch()

        // One real call seeds the record that the recall replays.
        performCall(app, title: "A021")
        openHistoryTab(app)

        let seededRow = historyRow(app, containing: "A021")
        XCTAssertTrue(
            seededRow.waitForExistence(timeout: 5),
            "History record did not appear within 5 seconds"
        )
        openHistoryDetail(app, row: seededRow)

        // Recall from the detail page writes a second record.
        let callAgainButton = app.buttons["再次呼叫"]
        XCTAssertTrue(
            callAgainButton.waitForExistence(timeout: 5),
            "Call Again button did not appear within 5 seconds"
        )
        callAgainButton.tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()

        let duplicatedRow = historyRows(app, containing: "A021").element(boundBy: 1)
        XCTAssertTrue(
            duplicatedRow.waitForExistence(timeout: 10),
            "Recalled record did not appear as a second row within 10 seconds"
        )
    }

    // MARK: - History helpers

    /// Taps an action tile on the Calling tab and waits for the resulting
    /// call to finish, so its history record is written before moving on.
    @MainActor
    private func performCall(_ app: XCUIApplication, title: String) {
        let tile = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", title)
        ).firstMatch
        XCTAssertTrue(
            tile.waitForExistence(timeout: 5),
            "Calling action \(title) did not appear within 5 seconds"
        )
        tile.tap()
        // The live call banner disappears once the call is over.
        waitForDisappearance(app.staticTexts["正在播报…"])
    }

    @MainActor
    private func openHistoryTab(_ app: XCUIApplication) {
        // History now lives inside each board: open the Boards tab,
        // enter the seeded board, then its log.
        let boardsTab = app.tabBars.firstMatch.buttons["面板"]
        XCTAssertTrue(
            boardsTab.waitForExistence(timeout: 5),
            "Boards tab did not appear within 5 seconds"
        )
        boardsTab.tap()
        // Match the board row through its combined accessibility label.
        let boardCell = app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "综合服务大厅")
        ).firstMatch
        XCTAssertTrue(
            boardCell.waitForExistence(timeout: 5),
            "Seeded board did not appear within 5 seconds"
        )
        boardCell.tap()
        let logLink = app.buttons["日志"]
        XCTAssertTrue(
            logLink.waitForExistence(timeout: 5),
            "Board log entry did not appear within 5 seconds"
        )
        logLink.tap()
    }

    /// History rows expose their combined content as the NavigationLink
    /// button, which carries a stable identifier.
    @MainActor
    private func historyRows(_ app: XCUIApplication, containing text: String) -> XCUIElementQuery {
        app.buttons
            .matching(identifier: "history-record-row")
            .matching(NSPredicate(format: "label CONTAINS %@", text))
    }

    @MainActor
    private func historyRow(_ app: XCUIApplication, containing text: String) -> XCUIElement {
        historyRows(app, containing: text).firstMatch
    }

    /// Opens the record's detail page once the push animation settles,
    /// since taps made mid-animation are dropped.
    @MainActor
    private func openHistoryDetail(_ app: XCUIApplication, row: XCUIElement) {
        XCTAssertTrue(
            app.navigationBars["日志"].waitForExistence(timeout: 5),
            "History page did not finish its transition within 5 seconds"
        )
        let settled = expectation(
            for: NSPredicate(format: "exists == true AND isHittable == true"),
            evaluatedWith: row
        )
        wait(for: [settled], timeout: 5)
        row.tap()
    }

    /// Taps the given action inside the confirmation dialog, which renders
    /// as an action sheet on iPhone and as a plain button list on iPad.
    @MainActor
    private func confirmDialogAction(_ app: XCUIApplication, _ action: String) {
        let sheet = app.sheets.firstMatch
        if sheet.waitForExistence(timeout: 2) {
            sheet.buttons[action].tap()
        } else {
            let button = app.buttons[action]
            XCTAssertTrue(
                button.waitForExistence(timeout: 5),
                "Confirmation action \(action) did not appear within 5 seconds"
            )
            button.tap()
        }
    }

    @MainActor
    private func waitForDisappearance(_ element: XCUIElement) {
        let gone = NSPredicate(format: "exists == false")
        let disappearance = expectation(for: gone, evaluatedWith: element)
        wait(for: [disappearance], timeout: 5)
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
