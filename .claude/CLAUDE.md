# TalTokenPlan 项目配置

作者：wwj

## 项目概述

macOS 菜单栏应用，从浏览器（Chrome/Safari）自动读取 Claude API Token 并展示用量计划。包含主应用（TalTokenPlan）和辅助进程（CookieReaderHelper）两个 target。

## 技术栈

| 层级 | 技术 | 说明 |
|------|------|------|
| 语言 | Swift 5.9 | macOS 原生 |
| 平台 | macOS 12+ | Menu Bar App，无前端框架 |
| 构建 | Swift Package Manager | Package.swift |
| 自动更新 | Sparkle 2.6.4 | 通过 AppUpdaterManager 管理 |
| 存储 | SQLite3 (系统库) | CookieReaderHelper 读取浏览器 Cookie DB |
| 架构 | Universal Binary | arm64 + x86_64，build.sh 打包 |

## 目录结构

```
TalTokenPlan/
├── Sources/
│   ├── TalTokenPlan/          # 主应用 target（Menu Bar UI）
│   │   ├── main.swift
│   │   ├── AppDelegate.swift
│   │   ├── MenuBuilder.swift
│   │   ├── StatusBarProgressView.swift
│   │   ├── TokenParser.swift
│   │   ├── TokenStore.swift
│   │   ├── APIClient.swift
│   │   ├── CookieReaderClient.swift  # 与 Helper 通信
│   │   ├── AppSettings.swift
│   │   ├── AppUpdaterManager.swift
│   │   ├── SettingsWindowController.swift
│   │   ├── DefaultBrowserInfo.swift
│   │   └── FDAGuide.swift
│   └── CookieReaderHelper/    # 辅助进程 target（读取浏览器 Cookie）
│       ├── main.swift
│       ├── CookieReader.swift
│       ├── CookieDatabase.swift
│       ├── ChromiumCookieQuery.swift
│       ├── ChromiumDecryptor.swift
│       ├── ChromiumLocalStorageReader.swift
│       ├── SafariBinaryCookiesReader.swift
│       ├── DefaultBrowserDetector.swift
│       ├── JWTHelper.swift
│       ├── TokenNormalizer.swift
│       ├── CookieDebugContext.swift
│       └── CookieDiagnostics.swift
├── Resources/
│   ├── Info.plist
│   ├── AppIcon.icns
│   └── TalTokenPlan.entitlements
├── Package.swift
├── Package.resolved
└── build.sh                   # 打包 Universal .app bundle
```

## 开发约定

| 约定 | 说明 |
|------|------|
| 调试运行 | `swift run TalTokenPlan` |
| 正式打包 | `./build.sh`（生成 Universal `Token Plan.app`） |
| 签名分发 | `SIGN_IDENTITY="Developer ID Application: ..." ./build.sh` |
| 进程通信 | 主应用通过 `CookieReaderClient` 启动/调用 Helper 子进程 |
| 浏览器适配 | Safari 用 `.binarycookies`，Chromium 用 SQLite + AES 解密 |

## 架构要点

- **两个 target 独立编译**：TalTokenPlan（主进程）和 CookieReaderHelper（Helper 子进程），打包后 Helper 在 `Contents/Helpers/`
- **Sparkle 框架**：通过 `@rpath` 链接，打包后在 `Contents/Frameworks/Sparkle.framework`
- **沙盒权限**：需要 Full Disk Access 才能读取浏览器 Cookie，`FDAGuide.swift` 处理引导

## 与 Claude Code 协作

### 期望主动做的

- 发现 Swift 类型错误和潜在崩溃（force unwrap、竞态条件）
- 提示更 Swifty 的写法
- 补充缺失的错误处理（特别是文件 I/O 和进程通信）

### 不希望做的

- 不要过度重构已工作的代码
- 不要添加未要求的功能
- 不要主动创建文档文件
- 不要将 SQLite 操作改为第三方 ORM
