# iOS 16 叫号状态恢复 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让空配置的新安装不依赖 SwiftUI 生命周期也能离开叫号加载态。

**Architecture:** 根视图继续唯一持有 `CallingViewModel`。ViewModel 在构造完成后启动现有单飞刷新；`CallingView` 从环境读取它，不再接收依赖、`@ObservedObject` 或自行触发首次刷新。

**Tech Stack:** Swift 6、SwiftUI、Combine、Swift Testing、Core Data。

**Spec:** `docs/superpowers/specs/2026-09-03-ios16-calling-state-design.md`

## Global Constraints

- iOS 16+；不新增依赖，不改变 Core Data、音频、面板或业务规则。
- 保留现有单飞 `requestRefresh()` 与加载诊断；营销版本保持 `1.0.3`，构建号变为 `6`。

---

### Task 1: 用自动启动回归测试锁定行为

**Files:**
- Modify: `CallDeskTests/ViewModels/CallingViewModelTests.swift`
- Modify: `CallDesk/Features/Calling/CallingViewModel.swift`

**Interfaces:** `CallingViewModel(dependencies:)` 在构造后自行进入一次刷新；其 `state` 对空仓库变为 `.empty`。

- [ ] **Step 1: 写失败测试**

在既有空仓库测试旁添加：

```swift
@Test("A new empty calling view model loads without a view lifecycle callback")
func newEmptyViewModelLoadsWithoutLifecycleCallback() async throws {
    let store = try InMemoryCallDeskStore()
    let viewModel = Fixture.makeViewModel(store: store)

    #expect(await waitForEmptyState(of: viewModel))
}
```

该测试捕获的生产回归是：移除自动启动后，新安装永久停在 `.loading`。

- [ ] **Step 2: 验证红灯**

Run:

```bash
xcodebuild test -quiet -project CallDesk.xcodeproj -scheme CallDesk -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing:CallDeskTests/CallingViewModelTests/newEmptyViewModelLoadsWithoutLifecycleCallback -enableCodeCoverage NO
```

Expected: 超时失败，因为构造后没有任何刷新请求。

- [ ] **Step 3: 最小实现**

在 `CallingViewModel.init` 所有储存属性初始化后调用已有入口：

```swift
requestRefresh()
```

不创建第二个任务或加载实现；既有入口负责单飞、错误和诊断。

- [ ] **Step 4: 验证绿灯**

重新运行 Step 2 的命令。Expected: PASS。

### Task 2: 以根环境注入共享叫号状态

**Files:**
- Modify: `CallDesk/App/AppRootView.swift`
- Modify: `CallDesk/Features/Calling/CallingView.swift`

**Interfaces:** `CallingView()` 使用 `@EnvironmentObject private var viewModel: CallingViewModel`；根视图负责 `.environmentObject(callingViewModel)`。

- [ ] **Step 1: 制造边界变更的编译失败**

在 `CallingView` 将现有属性和 initializer 替换为：

```swift
@EnvironmentObject private var viewModel: CallingViewModel
```

- [ ] **Step 2: 验证编译失败**

Run:

```bash
xcodebuild build -quiet -project CallDesk.xcodeproj -scheme CallDesk -configuration Debug -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO
```

Expected: 根视图仍传递 `viewModel:`，因此出现缺少匹配 initializer 的错误。

- [ ] **Step 3: 完成根注入**

根视图改为：

```swift
NavigationStack {
    CallingView()
        .environmentObject(callingViewModel)
}
```

删除 `CallingView` 的 `onAppear { viewModel.requestRefresh() }`；根视图保留前台、切换 Tab 的后续刷新。

- [ ] **Step 4: 验证编译绿灯**

重新运行 Step 2。Expected: PASS。

### Task 3: 准备并验证 TestFlight 构建 6

**Files:**
- Modify: `CallDesk.xcodeproj/project.pbxproj`

**Interfaces:** 应用的 `CFBundleShortVersionString` 为 `1.0.3`，`CFBundleVersion` 为 `6`。

- [ ] **Step 1: 改版本号**

将各配置的 `CURRENT_PROJECT_VERSION = 5` 改为 `CURRENT_PROJECT_VERSION = 6`；不改 `MARKETING_VERSION = 1.0.3`。

- [ ] **Step 2: 运行叫号 ViewModel 测试**

Run:

```bash
xcodebuild test -quiet -project CallDesk.xcodeproj -scheme CallDesk -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing:CallDeskTests/CallingViewModelTests -enableCodeCoverage NO
```

Expected: PASS，包含自动启动与加载诊断测试。

- [ ] **Step 3: 构建 Release 并检查版本**

Run:

```bash
xcodebuild build -quiet -project CallDesk.xcodeproj -scheme CallDesk -configuration Release -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO
plutil -p build/Release-iphoneos/CallDesk.app/Info.plist | rg 'CFBundleShortVersionString|CFBundleVersion'
```

Expected: 构建退出码为 `0`，版本为 `1.0.3 (6)`。

- [ ] **Step 4: 审查改动范围**

Run:

```bash
git diff --check
git status --short
```

Expected: 无空白错误；保留并单独报告既有无关工作树文件。
