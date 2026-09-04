# iOS 16 叫号页显式渲染宿主设计

## 问题

在 iPhone 8 Plus（iOS 16.7.16）的 TestFlight 包中，叫号加载已在约 31ms
完成并进入空状态，但页面仍显示初始加载指示器。数据层、任务和 ViewModel
状态机均已验证正常；失效边界是 SwiftUI 首屏对外部 `ObservableObject` 的
状态观察。

## 目标

让叫号页面在 iOS 16 的 Release/TestFlight 环境中可靠渲染最新状态，同时
保持既有呼叫、Core Data、语音和导航行为不变。

## 设计

1. 新增一个仅用于叫号内容区域的 UIKit 宿主控制器，并以
   `UIViewControllerRepresentable` 嵌入 `CallingView`。
2. 宿主控制器持有 ViewModel 的 Combine 订阅。每个状态变更都会在主线程
   创建当前内容快照，并显式更新子 `UIHostingController` 的根视图。
3. 叫号内容保持 SwiftUI 实现；UIKit 只承担状态变更到渲染树的可靠边界。
   `CallingView` 继续拥有导航栏、工具栏、确认对话框和页面级交互状态。
4. 宿主首次加入窗口后再请求加载，保证订阅已建立；重复出现仍由
   ViewModel 的单飞加载逻辑合并。
5. 宿主销毁时取消订阅，防止 ViewModel 与视图控制器形成循环引用。

## 不做的事

- 不变更数据仓库、Core Data 调度或朗读实现。
- 不变更 TestFlight 签名、网络、账号或用户数据。
- 不将整个应用迁移到 UIKit。

## 验证

- 回归测试：初始 loading 快照收到 empty 后，宿主渲染快照为 empty。
- 构建：连接的 iPhone 8 Plus 目标使用 Release 构建成功。
- 最终验收：TestFlight 上的 iOS 16.7.16 真机在空配置启动和手动重新加载后
  显示空状态，而非持续转圈。
