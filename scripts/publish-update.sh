#!/usr/bin/env bash
# 打包 zip、签名，并更新 appcast.xml，发布到 GitHub Releases
# 仓库: git@github.com:dzfly/tokenplan.git
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP_NAME="Token Plan.app"
ZIP_NAME="TokenPlan.zip"
RELEASES_DIR="releases"
RESOURCES="Resources/Info.plist"
GITHUB_REPO="dzfly/tokenplan"
APPCAST_RAW_URL="https://raw.githubusercontent.com/${GITHUB_REPO}/main/releases/appcast.xml"

SHORT_VERSION="${1:-}"
BUILD_VERSION="${2:-}"
TAG="v${SHORT_VERSION}"

if [[ -z "$SHORT_VERSION" || -z "$BUILD_VERSION" ]]; then
  echo "用法: $0 <shortVersion> <buildNumber>"
  echo "示例: $0 1.0.3 4"
  exit 1
fi

echo "→ 更新版本号并重新编译签名..."
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${SHORT_VERSION}" "$RESOURCES"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${BUILD_VERSION}" "$RESOURCES"
./build.sh

echo "→ 验证 .app 代码签名..."
if ! codesign --verify --deep --strict "${APP_NAME}" 2>/dev/null; then
  echo "❌ .app 代码签名无效，Sparkle 更新会失败" >&2
  codesign --verify --deep --strict --verbose=2 "${APP_NAME}" || true
  exit 1
fi

mkdir -p "$RELEASES_DIR"
rm -f "${RELEASES_DIR}/${ZIP_NAME}"
# --norsrc 避免 __MACOSX 元数据目录
ditto -c -k --norsrc --keepParent "$APP_NAME" "${RELEASES_DIR}/${ZIP_NAME}"

ZIP_PATH="$(cd "$RELEASES_DIR" && pwd)/${ZIP_NAME}"
ZIP_LENGTH=$(stat -f%z "$ZIP_PATH")
RELEASE_DOWNLOAD_URL="https://github.com/${GITHUB_REPO}/releases/download/${TAG}/${ZIP_NAME}"

SPARKLE_SIGN=""
for candidate in \
  "./.build/arm64-build/artifacts/sparkle/Sparkle/bin/sign_update" \
  "./.build/x86-build/artifacts/sparkle/Sparkle/bin/sign_update" \
  "./.build/artifacts/sparkle/Sparkle/bin/sign_update" \
  "$(command -v sign_update 2>/dev/null || true)"; do
  if [[ -n "$candidate" && -x "$candidate" ]]; then
    SPARKLE_SIGN="$candidate"
    break
  fi
done

ED_SIGNATURE=""
if [[ -n "$SPARKLE_SIGN" ]]; then
  SIGN_OUTPUT=$("$SPARKLE_SIGN" "$ZIP_PATH")
  echo "$SIGN_OUTPUT"
  ED_SIGNATURE=$(echo "$SIGN_OUTPUT" | sed -n 's/.*edSignature="\([^"]*\)".*/\1/p')
  if [[ -n "$ED_SIGNATURE" ]]; then
    "$SPARKLE_SIGN" --verify "$ZIP_PATH" "$ED_SIGNATURE"
    echo "✅ Sparkle EdDSA 签名验证通过"
  fi
fi

if [[ -z "$ED_SIGNATURE" ]]; then
  echo "⚠️  未能获取 Sparkle 签名，请手动运行 sign_update 并更新 appcast.xml"
else
  PUB_DATE=$(LC_TIME=C date -u "+%a, %d %b %Y %H:%M:%S +0000")
  cat > "${RELEASES_DIR}/appcast.xml" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/">
    <channel>
        <title>Token Plan Updates</title>
        <link>https://github.com/${GITHUB_REPO}</link>
        <description>Token Plan for macOS</description>
        <language>zh-Hans</language>
        <item>
            <title>Version ${SHORT_VERSION}</title>
            <sparkle:version>${BUILD_VERSION}</sparkle:version>
            <sparkle:shortVersionString>${SHORT_VERSION}</sparkle:shortVersionString>
            <pubDate>${PUB_DATE}</pubDate>
            <enclosure
                url="${RELEASE_DOWNLOAD_URL}"
                sparkle:edSignature="${ED_SIGNATURE}"
                length="${ZIP_LENGTH}"
                type="application/octet-stream" />
        </item>
    </channel>
</rss>
EOF
  echo "✅ 已更新 ${RELEASES_DIR}/appcast.xml"
fi

echo ""
echo "✅ 已生成: ${RELEASES_DIR}/${ZIP_NAME} (${ZIP_LENGTH} bytes)"
echo "   版本: ${SHORT_VERSION} (${BUILD_VERSION})"
echo ""
echo "发布到 GitHub（${GITHUB_REPO}）："
echo ""
echo "  gh release create ${TAG} --repo ${GITHUB_REPO} \\"
echo "    --title \"Token Plan ${SHORT_VERSION}\" \\"
echo "    TokenPlan.dmg ${RELEASES_DIR}/${ZIP_NAME}"
echo ""
echo "  # 并推送 appcast.xml 到 GitHub main 分支"
echo ""
echo "Appcast: ${APPCAST_RAW_URL}"
