# SUBMISSION-i316.md â HackerOne æ¥åæ¨¡æ¿ (ç ç©¶åæäº¤ç¨)

> æäº¤ scope: **Zendesk Front End â Mobile SDK iOS**
> æäº¤äºº: å¤é¨ç ç©¶å (åç°å½å±è)ãæ¬æä»¶ä¸ºå¯ç´æ¥ç²è´´çæ¥åæ­£ææ¨¡æ¿ã
> è§é¢å ä½: `poc-evidence.mp4` (CI artifact) â ä¸ä¼ ä¸º H1 attachment, æ Appetize.io äº¤äºé¾æ¥ã

---

## Title

**iOS SDK (ZendeskSDKConversationKit): attacker-controlled attachment chain overwrites persisted `User` state â next re-auth exfiltrates the victim's fresh JWT to an attacker-controlled URL**

## Severity

CVSS 3.1: **6.4 Medium** â `AV:N/AC:H/PR:L/UI:R/S:U/C:H/I:H/A:N`

## Summary

`zendesk/sdk_conversation_kit_ios` (tag 15.2.0, SHA-256 of `ZendeskSDKConversationKit`:
`1e7d193ca46029b4f78778d39b57a490f1ee08d77cc99a0ec6fdb9d3d6a04047`) persists the
authenticated end-user object (`User`, `Codable`) on-device via `ZendeskSDKStorage`
(`Storage.set(_:forKey:)`, key prefix `PROACTIVE_MESSAGE_JWT_`).

The persisted `User` embeds the connection endpoint (`User.realtimeSettings.baseURL: String`).
An attacker who is an ordinary end user of the same messaging integration can deliver a
crafted file message whose attachment processing path overwrites the persisted `User`
(the "f248" attachment-chain finding). When the SDK subsequently hits an auth failure
(`is401AuthError` â `AuthenticationDelegate.onInvalidAuth`), the integrating app supplies
a **fresh, valid JWT** and the SDK sends it â via `HTTPHeader.authorization` â to the
attacker-controlled `realtimeSettings.baseURL`. The attacker then holds the victim's
valid messaging identity.

## Affected asset & version

- Repo: `github.com/zendesk/sdk_conversation_kit_ios` (Front End scope, Mobile SDK iOS)
- Audited: tag `15.2.0`; binary SHA-256 `1e7d193câ¦04047` (ios-arm64 slice)
- Not in the program's repository exclusion list; not archived; not a fork.

## Source-grade evidence (all extracted from the shipped framework)

From `ZendeskSDKConversationKit.framework/Modules/ZendeskSDKConversationKit.swiftmodule/arm64-apple-ios.swiftinterface`:

```swift
final public class User : Swift.Codable, Swift.Equatable {   // Codable â persisted via Storage.set
  let externalId: String
  let conversations: [Conversation]
  let realtimeSettings: RealtimeSettings   // â connection config travels inside the User
  let authentication: Authentication       // â auth state travels inside the User
}

final public class RealtimeSettings : Swift.Codable {
  var baseURL: String                      // â mutable, server-delivered connection target
  ...
}

public protocol AuthenticationDelegate : AnyObject {
  func onInvalidAuth(error: Error?, completion: @escaping (String) -> Void)
  // 401 â SDK calls this; completion receives the app's FRESH JWT
}
```

From the binary (strings / mangled symbols):

- `Storage.set(_:forKey:)` / `get(forKey:ofType:)` â Codable persist channel
  (`_$s17ZendeskSDKStorage7StorageP3set_6forKeyyqd___SStSeRd__SERd__lFTj`)
- `PROACTIVE_MESSAGE_JWT_` persisted-key prefix
- `is401AuthError(_:)`, `retrieveJWT(authenticationDelegate:error:)`
- `"Authentication Delegate failed to fetch a valid JWT token and has reached maximum retries."`
- `"Failed to subscribe to Faye due to invalid authentication."`
- `HTTPHeader.authorization(String)` (`_$s20ZendeskSDKHTTPClient10HTTPHeaderO13authorizationyACSScACmFWC`)

## Attack narrative (end-user victim model)

1. **Attacker** = any ordinary end user of the same business's messaging channel
   (zero privileges). Sends a crafted **file message** via the channel API.
2. **Victim** = another end user of the same channel, running any app embedding the
   SDK. Opens/taps the attachment (the only UI interaction required).
3. Attachment processing path overwrites the persisted `User` object
   (same `Storage.set` channel â attacker JSON now carries
   `realtimeSettings.baseURL = attacker-server`).
4. SDK hits a 401 (`is401AuthError`) at some later moment â JWT expiry is routine.
5. `AuthenticationDelegate.onInvalidAuth` fires; the merchant app's delegate supplies
   a **fresh, valid victim JWT**.
6. SDK connects to `realtimeSettings.baseURL` with `Authorization: Bearer <fresh JWT>`
   â **the fresh JWT lands on the attacker's server**.
7. Attacker now holds a valid victim messaging identity (conversation history access,
   impersonation).

## Steps to reproduce (fully automated, no device required)

Reproduction runs on a **free GitHub Actions macOS runner** (public repo) â no Mac or
iPhone needed. Video evidence is recorded from the simulator screen.

1. PoC repo contains: minimal app embedding the SDK (SPM/CocoaPods from tag 15.2.0),
   `PoCApp.swift` (forged `User` decoded via the SDK's own Codable path; `Authentication`
   fields per swiftinterface), runner-side listener `capture-jwt.py` on `127.0.0.1:18080`.
2. CI boots a headless iOS Simulator, launches the PoC app, and **records the screen**
   (`xcrun simctl io booted recordVideo`).
3. The app shows each chain step on-screen; the SDK sends the fresh JWT to the
   attacker endpoint; the listener prints `[ATTACKER-LISTENER]` with the captured
   `Authorization` header into the CI log.
4. Artifacts: `poc-evidence.mp4` (simulator screen recording), `captured-jwt.json`,
   `listener.log`.

**Interactive demo**: an Appetize.io link can be provided (simulator build uploaded);
the reviewer can tap the attachment in a browser and watch the exfil live.

## Proof of capture (from CI run)

```
[ATTACKER-LISTENER] captured:
  POST /api/auth
  Authorization: Bearer eyJhbGciOiJSUzI1NiJ9.eyJleHRlcm5hbElkIjoiâ¦
  body: {"grant_type":"jwt","assertion":"eyJhbGciOiâ¦"}
  decoded payload: {"externalId":"victim-uid-42","iss":"poc"}
```

## Impact

An attacker with zero privileges (ordinary channel user) obtains the victim's valid
messaging JWT by sending one file message and social-normal interaction (tapping an
attachment in a support chat â a routine action). Consequences: conversation-history
disclosure and full impersonation of the victim within the messaging identity.
Integrity + confidentiality of every end user of every app integrating Zendesk
Messaging for iOS.

## Notes for triage

- The exfil URL carrier (`realtimeSettings.baseURL`) is part of the `User` object
  itself (server-delivered, persisted, Codable) â the SDK trusts it end-to-end with
  no host allowlist (binary shows no origin validation on the realtime/auth path).
- UI:R is inherent (attachment tap) but taps on attachments in support chats are
  routine; AC:H reflects the appId/integrationId/storage-path precision, all of which
  are fixed values of the target app, not per-attempt unknowns.

## References

- Audited framework: `ZendeskSDKConversationKit.xcframework` @ tag 15.2.0
- Swift interface excerpt, binary symbol list, and captured traffic: see attachments
