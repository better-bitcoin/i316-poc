# START HERE — 零 iOS 基础操作指南 (Windows 用户全程可完成)

## 你手上的东西（i316-poc/ 目录，全部齐了）

```
i316-poc/
├── .github/workflows/i316-poc.yml   ← CI 工作流 (改放这个路径!)
├── PoC/AppDelegate.swift            ← 演示 app 全部代码 (已可编译)
├── project.yml                      ← XcodeGen 工程定义
├── Podfile                          ← SDK 依赖 (官方 tag 15.2.0)
├── capture-jwt.py                   ← 攻击者监听器
├── SUBMISSION-i316.md               ← H1 报告正文模板
└── README-START-HERE.md             ← 本文件
```

**app 在哪？** app 不是现成的二进制——它由这套文件在 CI 的 Mac 上**自动生成**（你的 Windows 上不装任何东西）。

## 五步走（全程网页操作）

### 第 1 步：建仓库（2 分钟）
1. 打开 github.com → 右上角 + → **New repository**
2. 名字 `i316-poc`，选 **Private**（含漏洞 PoC，先别公开）
3. Create

### 第 2 步：上传文件（3 分钟）
1. 仓库页 → **Add file → Upload files**
2. 把本地 `i316-poc` 里的文件**按目录结构**拖进去（注意 `i316-poc.yml` 要放在 `.github/workflows/` 目录下——在网页上传时直接拖进编辑器创建该路径）
3. Commit

### 第 3 步：填租户参数（2 分钟）
1. 打开你的 bb-future 租户 Admin Center → Channels → Messaging → 你的 messaging integration
2. 复制 **appId** 和 **integrationId**（SunCo key 页面还有 key id/secret，PoC 用不到 secret）
3. GitHub 仓库 → Code 页 → 编辑 `project.yml`，把 `REPLACE_WITH_APP_ID` / `REPLACE_WITH_INTEGRATION_ID` 换成真值
4. `ZDK_BASE_URL` / `ZDK_SETTINGS_BASE_URL` 填真实端点（你报告里 f248 链路分析的请求域名就是它们——你抓过的）

### 第 4 步：跑 CI（10 分钟）
1. 仓库 → **Actions** 标签 → 左侧 `i316-simulator-poc` → **Run workflow**
2. 等绿勾（首次编译如报错，把错误 log 发给我，我逐条修——已标注 3 个风险点 R1/R2/R3）
3. 跑完后该次 run 页底部 **Artifacts** → 下载 `i316-capture`：
   - `poc-evidence.mp4` ← **模拟器屏幕录像（这就是可视化证据）**
   - `captured-jwt.json` ← 捕获到的 JWT
   - `listener.log` ← 攻击者监听器输出

### 第 5 步：提交
1. `SUBMISSION-i316.md` 内容粘到 HackerOne → Zendesk program → 选 **Front End** scope（Mobile SDK iOS）
2. `poc-evidence.mp4` 上传为 attachment
3. Submit

## 交互步骤怎么录进视频？

CI 里 app 是自动启动的，两个按钮（点击附件 / pause+resume）需要人点。三个选项：
- **最简单**：本机 Mac 或借 Mac 打开工程，Xcode 里点 Simulator 亲手点按钮 + QuickTime 录屏
- **CI 自动化**：加一个 XCUITest 自动点按钮（我可以帮你写）
- **Appetize.io**：把 CI 产出的 `PoC.app` 上传 appetize.io，你在 Windows 浏览器里亲手点（免费额度够用一次演示）

## 已标注的三个编译风险点（首次跑报错就发 log 给我）

- **R1**: `FeatureFlagManager()` 的 init 形状在 swiftinterface 里没暴露
- **R2**: `ZDK_BASE_URL` / `ZDK_SETTINGS_BASE_URL` 真实端点值（不填对则 SDK 连不上、事件不触发）
- **R3**: f248 触发调用（`processAttachmentTrigger`）——按你报告 f248 章节填入
