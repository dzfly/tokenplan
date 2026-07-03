# TalTokenPlan

macOS 菜单栏应用，从浏览器（Chrome / Edge / Arc / Tabbit / Safari）自动读取 Claude API Token，在状态栏展示用量计划与账单信息。

## 功能

- 状态栏实时展示用量百分比、剩余/花费金额（可切换），橙色进度环
- 下拉菜单卡片化展示：账单总览、今日用量 Top5（含模型、token、费用）
- 一键从浏览器读取登录凭证，无需手动粘贴 token
- 自动刷新数据（间隔可在设置页通过滑块调节，30s–15min，默认 1min）
- 首次启动自动提示钥匙串授权，后续静默读取
- 设置页：状态栏显示项开关、刷新间隔、检查更新

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

## 发版流程

代码仓库在内网 GitLab（`origin`），Sparkle 更新源指向 GitHub `dzfly/tokenplan`（只放 release zip + appcast.xml，不含代码）。

### 1. 升版本号

`Resources/Info.plist` 的 `CFBundleShortVersionString` 和 `CFBundleVersion` 各 +1。

### 2. 打包

`./build.sh` 同时生成 `Token Plan.app` 和 `TokenPlan.dmg`（含 /Applications 软链接，支持拖拽安装）。

```bash
# ad-hoc 打包（Universal Binary，需 Full Disk Access 运行）
./build.sh

# 签名分发（需 Developer ID Application 证书）
SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" ./build.sh
```

### 3. 生成 zip 与签名

```bash
zip -qr releases/TokenPlan.zip "Token Plan.app"
cp TokenPlan.dmg releases/TokenPlan.dmg

SIGN_UPDATE=$(find .build -path "*/artifacts/sparkle/Sparkle/bin/sign_update" 2>/dev/null | head -1)
"${SIGN_UPDATE}" releases/TokenPlan.zip
```

`sign_update` 输出 `sparkle:edSignature="..."` 和 `length="..."`，用于 appcast。

> `sign_update` 实际路径：`.build/arm64-build/artifacts/sparkle/Sparkle/bin/sign_update`（或 x86-build），`find` 命令自动定位。

### 4. 更新 appcast.xml

在 `releases/appcast.xml` 顶部新增 `<item>`，填入版本号、edSignature、length，enclosure url 指向 GitHub release：

```xml
<item>
    <title>Version X.Y.Z</title>
    <sparkle:version>BUILD</sparkle:version>
    <sparkle:shortVersionString>X.Y.Z</sparkle:shortVersionString>
    <pubDate>RFC822 日期</pubDate>
    <enclosure
        url="https://github.com/dzfly/tokenplan/releases/download/vX.Y.Z/TokenPlan.zip"
        sparkle:edSignature="..."
        length="..."
        type="application/octet-stream" />
</item>
```

### 5. 提交并打 tag

```bash
git add Resources/Info.plist releases/appcast.xml
git commit -m "release:X.Y.Z"
git tag vX.Y.Z
git push origin master
git push origin vX.Y.Z
```

### 6. 同步 appcast 到 GitHub

GitHub 仓库 `dzfly/tokenplan` 只用于更新分发，main 分支仅含 `releases/appcast.xml` + LICENSE + README。用 API 更新 appcast（`SUFeedURL` 指向这里的 raw 文件）：

```bash
SHA=$(gh api repos/dzfly/tokenplan/contents/releases/appcast.xml --jq '.sha')
CONTENT=$(base64 -i releases/appcast.xml | tr -d '\n')
gh api repos/dzfly/tokenplan/contents/releases/appcast.xml \
  --method PUT \
  --field message="release:X.Y.Z update appcast" \
  --field "content=${CONTENT}" \
  --field sha="${SHA}" \
  --jq '.commit.sha'
```

### 7. 上传 release zip 与 dmg

```bash
gh release create vX.Y.Z releases/TokenPlan.zip releases/TokenPlan.dmg \
  --repo dzfly/tokenplan \
  --title "X.Y.Z" \
  --notes "更新说明"
```

zip 供 Sparkle 自动更新用，dmg 供新用户手动下载安装。已装旧版本的用户，Sparkle 会通过 `SUFeedURL` 拉到新 appcast 自动提示更新。
