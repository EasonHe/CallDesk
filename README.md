# CallDesk

A lightweight, offline-first console for on-site calling and voice broadcasting on iPhone and iPad.

一款面向 iPhone 与 iPad 的轻量级、离线优先的现场叫号与语音播报控制台。

---

## English

### Overview

CallDesk 1.0 is feature complete: a native, reliable on-site calling tool that does not depend on a network service.

### Platform

- iPhone and iPad
- iOS 16+

### Technology

- Swift 6
- SwiftUI
- MVVM foundation
- Swift Concurrency (`async`/`await`)
- Core Data
- AVFoundation

### Completed

- Feature-first project structure
- `AppRootView` with four primary modules: Calling, Boards, History, and Settings
- Skeleton views for Calling, Boards, History, and Settings
- Minimal dependency-injection boundary
- Semantic layout constants for consistent, accessible sizing
- English and Simplified Chinese (`zh-Hans`) localization
- Unit and UI test foundations for navigation, layout constants, localization, and accessibility behavior
- Core domain models, validated voice templates, call-record snapshots, runtime/display state, audio-route descriptions, and settings value objects
- Deterministic sample data and focused domain-layer tests
- Async repository protocols backed by one shared actor-isolated in-memory store
- Deterministic repository queries, filtering, sorting, exact-set reordering, history retention, typed error injection, and repository-layer tests
- `AppDependencies` with `production()`, `preview()`, and `test()` factories
- Core Data persistence: a versioned data model, `PersistenceController`, six Core Data repositories behind the unchanged repository protocols, and one-time first-launch seeding of the base catalog
- Production runs on Core Data so boards, actions, templates, and history survive app restarts; previews and tests stay on isolated in-memory data
- Core Data repository tests covering CRUD, relationship rules, reorder atomicity, delete protection, history snapshots, retention, seeding idempotence, and error mapping
- `CallingViewModel`, `BoardsViewModel`, `HistoryViewModel`, and `SettingsViewModel` with loading, empty, loaded, and error states
- The four primary screens now load and display sample data through their view models: Calling shows the current board and its actions, Boards lists boards with an archived toggle, History supports search and result filtering, and Settings displays the default values with "not connected yet" hardware placeholders
- View model unit tests covering loading, empty data, filtering, board switching, and repository failures
- Board and action management: create, edit, delete, and reorder boards and actions from the Boards tab, with enable/disable for actions, scene-grouped board sections, and system-native edit interactions
- All management operations go through the repositories and write to Core Data immediately, keeping the existing delete-protection, ordering, and history semantics
- Management view model unit tests and an end-to-end UI test that creates a board and an action against an isolated in-memory store
- `CallService` calling flow: tapping an action runs one coordinated call through a `MainActor` service that owns the `LiveCallState` lifecycle (idle → preparing → speaking → completed / cancelled / interrupted / failed), resolves consecutive requests with the active-speech policy, supports cancellation, and writes one `CallRecord` per call through the history repository
- `CallingViewModel` now drives calls only through `CallService` and observes the live call state; audio, prompt tones, and external display are intentionally out of scope
- `CallService` unit tests covering the full lifecycle, cancellation, interrupt/queue/ignore policies, disabled and missing actions, speech failures, repeats, and best-effort history writes
- Real voice announcements: `AVSpeechSynthesizerSpeechDriver` replaces the silent placeholder and drives `AVSpeechSynthesizer` with the configured locale, rate, pitch, and volume, plays a system prompt tone before each utterance, and supports cancellation and completion callbacks — all behind the unchanged `CallSpeechDriving` protocol so `CallService` keeps its logic
- `AVAudioSession` is encapsulated behind an `AudioSessionManaging` abstraction that activates `.playback`/`.spokenAudio` on the system's current output route and deactivates around each utterance
- Driver unit tests covering session activation, prompt-tone gating, voice configuration, activation and speech failures, the completion callback, and mid-utterance cancellation
- Scene management: create, edit, delete, and drag-reorder scenes from a dedicated manager on the Boards tab, with enable/disable per scene, board counts per row, and delete protection for scenes that still contain boards
- The board editor selects scenes live: scene changes show up immediately, and a new scene can be created inline and is assigned to the board right away
- Scene view model unit tests and an end-to-end UI test covering the scene manager and inline scene creation from the board editor
- Settings persistence: a `SettingsStore` protocol with a `UserDefaultsSettingsStore` for production and an `InMemorySettingsStore` for previews and tests, so settings survive app restarts while previews and tests never touch the real `UserDefaults`
- The Settings tab is fully editable: voice language, rate, pitch, and volume, prompt tone with volume and delay, active-speech policy with repeat count and delay, history retention, recent-call count, and a confirmed "Restore Defaults" action — every change is saved immediately through the store
- Persisted settings decode each section independently, so payloads from older or newer app versions and single corrupt sections fall back to defaults without discarding the rest
- Settings store and view model unit tests covering round-trips, defaults, corrupt and partial payloads, immediate saves, invalid-value rejection, and restore defaults
- Live settings: every change on the Settings tab takes effect from the very next call — `SettingsStore` exposes a `settingsPublisher`, `CallService` reads the latest settings when resolving concurrent requests and takes one snapshot when a session starts, and the speech driver receives voice and prompt-tone settings with every utterance instead of caching them
- A running call session keeps the settings snapshot it started with; the prompt-tone delay now pauses between the tone and the speech; history retention is enforced after every saved record using the current history settings (zero disables a limit)
- Live-settings unit tests covering policy, repeat-count, voice, and retention changes between calls, snapshot immunity during a session, per-call driver settings, and settings publishers
- History management: the History tab now supports keyword search, result-status and time-range filters, single-record swipe deletion, multi-select batch deletion in edit mode, and a confirmed "Clear History" action — every operation goes through `CallHistoryRepository`, refreshes the list immediately, and persists to Core Data
- History details: each record opens a snapshot-based detail page that keeps working after the original action, board, or scene has been deleted, with clear empty, no-match, load-failure, and operation-failure states
- Recall from history: "Call Again" replays a record through `CallService` using the stored snapshot (title, speech text, destination) without touching the original action; when the original action or board no longer exists, the new record is saved as a detached snapshot without identifiers, so recall never bypasses the service or breaks referential integrity
- History view model and call service unit tests covering search, filters, deletion, clearing, recall, detached-snapshot degradation, and retention interplay, plus end-to-end UI tests for the management and recall flows
- Device audio output: announcements automatically follow the system output route — built-in speaker, receiver, wired headphones, Bluetooth, and AirPlay — through the existing `.playback` audio session, with no change to the `CallService` protocol
- An `AudioEnvironmentMonitoring` abstraction mirrors the live `AVAudioSession` route and interruptions: route changes (headphones plugged or unplugged, Bluetooth or AirPlay devices connecting) update the published route on the main actor, and the very next announcement plays on the new device
- Interruption handling per the audio session guidelines: an incoming phone call or another app claiming the output ends the running announcement as `interrupted` and records it in history; because the session activates per utterance, the next call recovers the audio session on its own, and a media services reset rebuilds the speech synthesizer
- Every `CallRecord` now stores the output route name (`audioRouteName`), and the history detail page shows which device the call went out on
- The Settings tab shows the live output device (name and type) and embeds the system `AVRoutePickerView` for switching to Bluetooth or AirPlay outputs
- Unit tests covering the system monitor (port mapping, route-change, reset, and interruption notifications), route recording and interruption termination in the call service, and the live route in the settings view model
- External display (second screen): connecting a screen via cable or AirPlay automatically shows a read-only signage view — the current call in very large type, the destination, and the recent completed calls — driven by an `ExternalDisplayPresenter` that mirrors `CallService` and the history repository without touching the calling flow; the Settings tab shows the live connection state
- Release hardening: a corrupted Core Data store no longer crashes the app at launch — the broken file is destroyed and recreated, with an in-memory fallback as the last resort; startup runs a one-off history-retention pass off the critical path
- App icon, accent color, About page (version, purpose, privacy, license), proprietary `LICENSE` file, privacy manifest (`PrivacyInfo.xcprivacy`: no tracking, no data collection), and `ITSAppUsesNonExemptEncryption = NO` for TestFlight
- App Store metadata drafts and a TestFlight checklist under `docs/release/`
- Accessibility pass: VoiceOver labels and combined elements across all screens, a hint on the call tiles, Dynamic Type–friendly layouts, and dark-mode support throughout
- Unit tests for the external display presenter, the settings connection state, and the startup maintenance

### Planned

- Cloud sync, import/export, and remote control remain future ideas beyond 1.0

The app announces calls out loud on the system-selected output device and mirrors them to a second screen; 1.0 is ready for TestFlight.

---

## 中文

### 项目简介

CallDesk 1.0 功能已完备：一款原生、可靠且无需依赖网络服务的现场叫号工具。

### 支持平台

- iPhone 与 iPad
- iOS 16 及以上

### 技术栈

- Swift 6
- SwiftUI
- MVVM 基础架构
- Swift Concurrency（`async`/`await`）
- Core Data
- AVFoundation

### 当前已完成

- 按功能划分的项目结构
- 包含叫号、面板、记录和设置四个主要模块的 `AppRootView`
- 叫号、面板、记录和设置的界面骨架
- 最小化的依赖注入边界
- 支持一致布局及符合无障碍要求的尺寸的语义化布局常量
- 英文与简体中文（`zh-Hans`）本地化
- 覆盖导航、布局常量、本地化和无障碍行为的单元测试与 UI 测试基础
- 核心领域模型、带校验的语音模板、叫号历史快照、运行时/展示状态、音频路由描述与设置值对象
- 确定性样例数据与聚焦的领域层测试
- 基于单一共享 Actor 隔离内存存储的异步 Repository 协议
- 确定性的 Repository 查询、筛选、排序、完整集合重排、历史保留策略、类型化错误注入与 Repository 层测试
- 提供 `production()`、`preview()` 和 `test()` 工厂方法的 `AppDependencies`
- Core Data 持久化：带版本化基础的数据模型、`PersistenceController`、在保持 Repository 协议不变的前提下实现的六个 Core Data Repository，以及首次启动时一次性写入基础数据
- production 运行在 Core Data 上，面板、叫号项、模板与历史记录在应用重启后保留；Preview 与测试继续使用相互隔离的内存数据
- 覆盖增删改查、关系规则、重排原子性、删除保护、历史快照、保留策略、初始化幂等与错误映射的 Core Data Repository 测试
- 具备加载、空态、已加载和错误状态的 `CallingViewModel`、`BoardsViewModel`、`HistoryViewModel` 与 `SettingsViewModel`
- 四个一级页面已通过 ViewModel 加载并展示样例数据：叫号页展示当前面板及其叫号项，面板页展示面板列表并支持切换显示归档，记录页支持搜索与结果筛选，设置页展示默认设置值及“尚未接入”的硬件占位状态
- 覆盖加载、空数据、筛选、面板切换与 Repository 失败场景的 ViewModel 单元测试
- 面板与叫号项管理：在面板页中新增、编辑、删除和排序面板与叫号项，支持叫号项启用/禁用、按场景分组展示面板，并采用系统原生编辑体验
- 所有管理操作均通过 Repository 完成并实时写入 Core Data，保持既有的删除保护、排序与历史记录语义
- 管理相关的 ViewModel 单元测试，以及基于隔离内存存储、覆盖创建面板与叫号项完整流程的 UI 测试
- `CallService` 叫号流程：点击叫号项后由一个 `MainActor` 服务统一接管，管理 `LiveCallState` 生命周期（idle → preparing → speaking → completed / cancelled / interrupted / failed），按活动语音策略处理连续请求，支持取消，并通过历史 Repository 为每次叫号写入一条 `CallRecord`
- `CallingViewModel` 现在只通过 `CallService` 发起叫号并观察实时叫号状态；音频、提示音与外接显示暂不在本次范围
- `CallService` 单元测试覆盖完整生命周期、取消、打断/排队/忽略策略、禁用与缺失的叫号项、语音失败、重复播报以及尽力而为的历史写入
- 真实语音播报：`AVSpeechSynthesizerSpeechDriver` 取代静默占位驱动，使用配置的语言、语速、音高与音量驱动 `AVSpeechSynthesizer`，在每次播报前播放系统提示音，并支持取消与播报完成回调——全部隐藏在保持不变的 `CallSpeechDriving` 协议之后，`CallService` 业务逻辑无需改动
- `AVAudioSession` 被封装在 `AudioSessionManaging` 抽象之后，在系统当前输出路由上以 `.playback`/`.spokenAudio` 激活，并在每次播报前后停用
- 驱动单元测试覆盖音频会话激活、提示音开关、语音参数配置、激活与播报失败、播报完成回调以及播报中途取消
- 场景管理：在面板页的独立管理入口中新增、编辑、删除和拖拽排序场景，支持按场景启用/禁用、每行展示面板数量，并对仍包含面板的场景提供删除保护
- 面板编辑器实时选择场景：场景变更立即生效，并支持在编辑器内直接新建场景且立刻分配给当前面板
- 场景 ViewModel 单元测试，以及覆盖场景管理与面板编辑器内联新建场景的端到端 UI 测试
- 设置持久化：`SettingsStore` 协议配合 production 使用的 `UserDefaultsSettingsStore` 与 Preview/测试使用的 `InMemorySettingsStore`，设置在应用重启后保留，且 Preview 与测试不会读写真实 `UserDefaults`
- 设置页全面可编辑：语音语言、语速、音高与音量，提示音开关、音量与延迟，播报策略、重复次数与重复间隔，历史保留策略，最近叫号数量，以及带确认的“恢复默认设置”操作——每次修改都会通过 Store 立即保存
- 持久化的设置按分区独立解码：来自旧版或新版应用的数据以及单个损坏的分区都会回退到默认值，而不影响其余分区
- 设置 Store 与 ViewModel 单元测试覆盖读写往返、默认值、损坏与部分数据、立即保存、非法值拒绝以及恢复默认设置
- 设置实时生效：设置页的每次修改从下一次叫号起立即生效——`SettingsStore` 暴露 `settingsPublisher`，`CallService` 在处理并发请求时读取最新设置并在会话开始时获取一次快照，语音驱动在每次播报时接收语音与提示音设置而不再缓存
- 正在进行的叫号会话保持其开始时的设置快照；提示音延迟现在会在提示音与语音之间生效；每次保存历史记录后按当前历史设置执行保留策略（0 表示不限制）
- 实时设置单元测试覆盖两次叫号之间的策略、重复次数、语音与保留策略变化、会话内快照免疫、驱动逐次传参以及设置发布者
- 历史管理：记录页支持关键词搜索、按结果状态与时间范围筛选、滑动删除单条记录、编辑模式下多选批量删除，以及带确认的“清空全部历史”——所有操作均通过 `CallHistoryRepository` 完成，列表立即刷新并持久化到 Core Data
- 历史详情：每条记录可打开基于快照的详情页，即使原始叫号项、面板或场景已被删除仍可正常展示，并为空态、无匹配结果、加载失败与操作失败提供明确提示
- 历史重新叫号：“再次叫号”通过 `CallService` 使用保存的快照（标题、播报文本、目的地）重新播报，不读取原始叫号项；当原叫号项或面板已不存在时，新记录会降级为不带标识符的独立快照保存，重新叫号既不绕过服务也不破坏引用完整性
- 历史 ViewModel 与叫号服务单元测试覆盖搜索、筛选、删除、清空、重新叫号、独立快照降级与保留策略交互，另有覆盖管理与重新叫号主流程的端到端 UI 测试
- 设备音频输出：播报自动跟随系统输出路由——内置扬声器、听筒、有线耳机、Bluetooth 与 AirPlay——复用既有的 `.playback` 音频会话，`CallService` 对外协议保持不变
- `AudioEnvironmentMonitoring` 抽象实时镜像 `AVAudioSession` 的路由与中断：路由变化（插拔耳机、连接 Bluetooth 或 AirPlay 设备）在主 Actor 上更新已发布的路由，下一次播报即自动使用新设备
- 按音频会话规范处理中断：来电或其他应用占用输出时，正在进行的播报以 `interrupted` 结束并写入历史；由于会话按次播报激活，下一次叫号会自行恢复音频会话，媒体服务重置后会重建语音合成器
- 每条 `CallRecord` 现在记录输出设备名称（`audioRouteName`），历史详情页可展示该次叫号使用的输出设备
- 设置页实时展示当前输出设备（名称与类型），并内嵌系统 `AVRoutePickerView` 用于切换到 Bluetooth 或 AirPlay 输出
- 单元测试覆盖系统监视器（端口映射、路由变化、重置与中断通知）、叫号服务的路由记录与中断终止，以及设置 ViewModel 的实时路由
- 外接显示（第二屏）：通过线缆或 AirPlay 连接屏幕后自动展示只读展示画面——超大字号的当前叫号、目的地与最近完成的叫号记录——由镜像 `CallService` 与历史 Repository 的 `ExternalDisplayPresenter` 驱动，完全不改动叫号流程；设置页实时展示连接状态
- 发布加固：Core Data 存储损坏不再导致启动崩溃——损坏文件会被销毁重建，最终兜底为本次会话的内存存储；启动时在关键路径之外执行一次历史保留清理
- 应用图标、强调色、关于页面（版本、简介、隐私、许可）、专有 `LICENSE` 文件、隐私清单（`PrivacyInfo.xcprivacy`：无跟踪、无数据收集），以及用于 TestFlight 的 `ITSAppUsesNonExemptEncryption = NO`
- `docs/release/` 下的 App Store 元数据草稿与 TestFlight 检查清单
- 无障碍梳理：全部页面的 VoiceOver 标签与元素合并、叫号按钮的操作提示、适配动态字体的布局以及全程深色模式支持
- 覆盖外接显示 Presenter、设置页连接状态与启动维护的单元测试

### 后续计划

- 云同步、导入/导出与远程控制等 1.0 之后的方向

应用已在系统所选输出设备上出声播报叫号，并可镜像到第二块屏幕；1.0 已具备 TestFlight 发布条件。

---

## License / 许可证

This project is proprietary. See [LICENSE](LICENSE).

本项目为专有软件，详见 [LICENSE](LICENSE)。
