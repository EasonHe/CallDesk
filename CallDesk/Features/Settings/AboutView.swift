import SwiftUI

/// Reads the app's display metadata from the main bundle so the About
/// screen never hard-codes a version number.
struct AppInfo {
    let version: String
    let build: String

    init(bundle: Bundle = .main) {
        version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    }
}

/// Static information about the app: version, purpose, and privacy.
struct AboutView: View {
    private let appInfo = AppInfo()

    var body: some View {
        List {
            Section {
                VStack(spacing: 12) {
                    Image(systemName: "megaphone.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(Color.accentColor)
                    Text(verbatim: "顺发叫号")
                        .font(.title.weight(.bold))
                    Text("版本 \(appInfo.version) (\(appInfo.build))")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .accessibilityElement(children: .combine)
                .listRowBackground(Color.clear)
            }
            Section {
                Text("顺发叫号是一款面向一线员工的轻量、离线优先叫号应用。点击一项，语音即刻播报，队列继续前进。")
            } header: {
                Label("什么是顺发叫号", systemImage: "questionmark.circle")
            }
            Section {
                Text("所有面板、叫号项与呼叫历史都保存在此设备上。顺发叫号不收集任何数据，不使用任何追踪，也不需要联网。")
                if let privacyPolicyURL = URL(string: "https://easonhe.github.io/app-support/CallDesk/privacy.html") {
                    Link(destination: privacyPolicyURL) {
                        Label("隐私政策", systemImage: "arrow.up.right.square")
                    }
                }
            } header: {
                Label("隐私", systemImage: "lock.shield")
            }
            Section {
                if let supportURL = URL(string: "https://easonhe.github.io/app-support/CallDesk/support.html") {
                    Link(destination: supportURL) {
                        Label("技术支持", systemImage: "questionmark.circle")
                    }
                }
                LabeledContent("许可") {
                    Text("专有")
                }
                LabeledContent("版权") {
                    Text(verbatim: "© 2026 Wayne Ho")
                }
            } header: {
                Label("法律信息", systemImage: "doc.text")
            }
        }
        .navigationTitle(Text("关于"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        AboutView()
    }
}
