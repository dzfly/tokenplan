# TalTokenPlan

macOS 菜单栏应用，从浏览器（Chrome / Edge / Arc / Tabbit / Safari）自动读取 Claude API Token，在状态栏展示用量计划与账单信息。

## 功能

- 状态栏实时展示用量百分比、剩余/花费金额（可切换），橙色进度环
- 下拉菜单卡片化展示：账单总览、今日用量 Top5（含模型、token、费用）
- 一键从浏览器读取登录凭证，无需手动粘贴 token
- 每分钟自动刷新数据，每日自动检查新版本
- 设置页：状态栏显示项开关、检查更新

## 技术栈

| 层级 | 技术 |
|------|------|
| 语言 | Swift 5.9 |
| 平台 | macOS 12+ |
| 构建 | Swift Package Manager |
| 自动更新 | Sparkle 2.6.4 |
| 浏览器适配 | Safari `.binarycookies` / Chromium SQLite + AES 解密 |

## 架构

两个独立编译的 target：

- `TalTokenPlan` — 主应用（Menu Bar UI），通过 `CookieReaderClient` 启动并调用 Helper 子进程
- `CookieReaderHelper` — 辅助进程，读取浏览器 Cookie / LocalStorage，输出 token 到 stdout

打包后 Helper 位于 `Contents/Helpers/`，Sparkle.framework 位于 `Contents/Frameworks/`。

## 开发

```bash
# 调试运行
swift run TalTokenPlan

# 正式打包（Universal Binary: arm64 + x86_64）
./build.sh

# 签名分发
SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" ./build.sh
```

首次读取浏览器 Cookie 需要 Full Disk Access 权限，应用内 `FDAGuide` 会引导授权。

## 权限

- Full Disk Access（读取浏览器 Cookie 数据库）
- 钥匙串（解密 Chromium 加密 Cookie 时的 Safe Storage 密钥）
