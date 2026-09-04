# iOS 16 Calling Render Host Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Render the calling page's latest ViewModel state reliably on iOS 16 TestFlight builds without changing calling, persistence, or speech behavior.

**Architecture:** `CallingView` becomes a UIKit-backed SwiftUI representable. Its host controller owns the Combine subscriptions, installs them before requesting the first refresh, and explicitly replaces a child `UIHostingController` root with a SwiftUI content snapshot after every ViewModel change. The existing SwiftUI calling UI remains the presentation layer, but it reads the supplied state snapshot rather than depending on SwiftUI to observe the long-lived ViewModel.

**Tech Stack:** Swift 6, SwiftUI, UIKit, Combine, Testing, Xcode Release build.

**Spec:** `docs/superpowers/specs/2026-09-04-calldesk-ios16-calling-render-host-design.md`

## Global Constraints

- Support iOS 16.0 and later, including iPhone 8 Plus on iOS 16.7.16.
- Use SwiftUI for calling content; UIKit is limited to the rendering-host workaround.
- Do not add dependencies or alter Core Data, speech, user settings, or other tabs.
- The calling ViewModel remains the single owner of loading and calling business state.
- Release build number advances from 18 to 19 for a distinct TestFlight artifact.

---

### Task 1: Add a testable UIKit calling render host

**Files:**
- Create: `CallDesk/Features/Calling/CallingRenderHost.swift`
- Create: `CallDeskTests/ViewModels/CallingRenderHostTests.swift`

**Interfaces:**
- Consumes: `CallingViewModel`, `FeatureLoadState<CallingViewModel.Content>`.
- Produces: `CallingRenderHostController`, initialized with `init(viewModel:)`, and test-visible `renderedState` representing the latest root-view snapshot.

- [ ] **Step 1: Write the failing test**

```swift
@MainActor
@Test("The render host replaces its initial loading snapshot with an empty result")
func emptyResultReplacesInitialSnapshot() async {
    let viewModel = CallingViewModel(dependencies: .preview())
    let host = CallingRenderHostController(viewModel: viewModel)
    host.loadViewIfNeeded()

    await viewModel.load()

    #expect(host.renderedState == .empty)
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run:

```bash
xcodebuild test -project CallDesk.xcodeproj -scheme CallDesk \
  -destination 'platform=iOS Simulator,id=25251C7F-BD1B-4D8E-90F7-2EB698F22019' \
  -only-testing:CallDeskTests/CallingRenderHostTests \
  -derivedDataPath /tmp/CallDesk-calling-render-host-red
```

Expected: compilation fails because `CallingRenderHostController` does not exist.

- [ ] **Step 3: Implement the smallest host boundary**

```swift
@MainActor
final class CallingRenderHostController: UIViewController {
    private let viewModel: CallingViewModel
    private var subscriptions = Set<AnyCancellable>()
    private let contentHost: UIHostingController<CallingScreenContent>
    private(set) var renderedState: FeatureLoadState<CallingViewModel.Content>

    init(viewModel: CallingViewModel) { /* create initial loading snapshot */ }

    override func viewDidLoad() {
        super.viewDidLoad()
        installContentHost()
        subscribeToViewModel()
        renderCurrentState()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        viewModel.requestRefresh()
    }
}
```

`subscribeToViewModel()` must receive `objectWillChange` on the main queue and schedule `renderCurrentState()` after the mutation; it must not retain the controller. `renderCurrentState()` assigns `renderedState = viewModel.state` and replaces `contentHost.rootView` with `CallingScreenContent(viewModel:state:)`.

- [ ] **Step 4: Run the focused test to verify it passes**

Run the command from Step 2 with derived data path `/tmp/CallDesk-calling-render-host-green`.

Expected: the test passes and `host.renderedState` becomes `.empty`.

- [ ] **Step 5: Commit the host and test**

```bash
git add CallDesk/Features/Calling/CallingRenderHost.swift \
  CallDeskTests/ViewModels/CallingRenderHostTests.swift
git commit -m "fix: host calling state outside SwiftUI observation"
```

### Task 2: Move existing calling presentation behind the host snapshot

**Files:**
- Modify: `CallDesk/Features/Calling/CallingView.swift:5-565`
- Modify: `CallDesk/Features/Calling/CallingRenderHost.swift`

**Interfaces:**
- Consumes: `CallingRenderHostController` from Task 1.
- Produces: `CallingView` conforming to `UIViewControllerRepresentable`, plus `CallingScreenContent(viewModel:state:)` that renders the current snapshot.

- [ ] **Step 1: Write the failing test**

```swift
@MainActor
@Test("A loaded calling render snapshot is retained by the host")
func loadedResultReplacesInitialSnapshot() async {
    let dependencies = AppDependencies.preview()
    let viewModel = CallingViewModel(dependencies: dependencies)
    let host = CallingRenderHostController(viewModel: viewModel)
    host.loadViewIfNeeded()

    await viewModel.load()

    #expect(host.renderedState != .loading)
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run:

```bash
xcodebuild test -project CallDesk.xcodeproj -scheme CallDesk \
  -destination 'platform=iOS Simulator,id=25251C7F-BD1B-4D8E-90F7-2EB698F22019' \
  -only-testing:CallDeskTests/CallingRenderHostTests \
  -derivedDataPath /tmp/CallDesk-calling-content-red
```

Expected: it fails until snapshot replacement is used by the hosted calling content.

- [ ] **Step 3: Move only presentation code**

```swift
struct CallingView: UIViewControllerRepresentable {
    let viewModel: CallingViewModel

    func makeUIViewController(context: Context) -> CallingRenderHostController {
        CallingRenderHostController(viewModel: viewModel)
    }

    func updateUIViewController(_ controller: CallingRenderHostController, context: Context) {}
}

private struct CallingScreenContent: View {
    let viewModel: CallingViewModel
    let state: FeatureLoadState<CallingViewModel.Content>

    var body: some View {
        content
            .navigationTitle(AppTab.calling.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { /* existing route picker and reset toolbar */ }
    }
}
```

Move the existing `content`, loading/empty/loaded/failed views, action grid, confirmation dialog, and haptic interaction helpers into `CallingScreenContent`. Change its state switch from `screenState.state` to the injected `state`. Keep existing labels, accessibility behavior, and action methods unchanged. Remove `CallingScreenState.swift` and its test because the UIKit host is now the only render bridge.

- [ ] **Step 4: Run focused tests to verify they pass**

Run:

```bash
xcodebuild test -project CallDesk.xcodeproj -scheme CallDesk \
  -destination 'platform=iOS Simulator,id=25251C7F-BD1B-4D8E-90F7-2EB698F22019' \
  -only-testing:CallDeskTests/CallingRenderHostTests \
  -only-testing:CallDeskTests/CallingViewModelTests \
  -derivedDataPath /tmp/CallDesk-calling-content-green
```

Expected: all selected tests pass.

- [ ] **Step 5: Commit the presentation migration**

```bash
git add CallDesk/Features/Calling/CallingView.swift \
  CallDesk/Features/Calling/CallingRenderHost.swift \
  CallDesk/Features/Calling/CallingScreenState.swift \
  CallDeskTests/ViewModels/CallingScreenStateTests.swift \
  CallDeskTests/ViewModels/CallingRenderHostTests.swift
git commit -m "fix: render calling content from host snapshots"
```

### Task 3: Produce and verify the TestFlight-ready Release artifact

**Files:**
- Modify: `CallDesk.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: host-backed `CallingView` from Task 2.
- Produces: version `1.0.3 (19)` with the existing Release incremental compilation setting.

- [ ] **Step 1: Update the build number**

Set every `CURRENT_PROJECT_VERSION = 18;` entry in `CallDesk.xcodeproj/project.pbxproj` to `CURRENT_PROJECT_VERSION = 19;`. Do not change `MARKETING_VERSION` or unrelated build settings.

- [ ] **Step 2: Verify the effective Release compiler command**

Run:

```bash
xcodebuild -project CallDesk.xcodeproj -scheme CallDesk -configuration Release -showBuildSettings \
  | rg 'CURRENT_PROJECT_VERSION|SWIFT_COMPILATION_MODE'
```

Expected: `CURRENT_PROJECT_VERSION = 19` and `SWIFT_COMPILATION_MODE = incremental`.

- [ ] **Step 3: Build against the connected iPhone 8 Plus**

Run:

```bash
xcodebuild -project CallDesk.xcodeproj -scheme CallDesk -configuration Release \
  -destination 'platform=iOS,id=1931c815e4b427dcd2b71c58f3488be0dfab13f8' \
  -derivedDataPath /tmp/CallDesk-iOS16-render-host-release \
  -allowProvisioningUpdates build
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Inspect the final patch and commit**

Run:

```bash
git diff --check
git status --short
```

Expected: no whitespace errors; stage only calling-host files and the project file, leaving user-owned workspace state untouched.

- [ ] **Step 5: Commit and push the TestFlight-ready fix**

```bash
git add CallDesk.xcodeproj/project.pbxproj
git commit -m "build: prepare calling render host testflight build"
git push origin main
```
