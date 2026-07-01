#!/usr/bin/env bash
# 打包 zip、签名，并更新 appcast.xml，发布到 GitHub Releases
# 仓库: git@github.com:dzfly/tokenplan.git
set -euo pipefail

APP_NAME="Token Plan.app"
ZIP_NAME="TokenPlan.zip"
RELEASES_DIR="releases"
GITHUB_REPO="dzfly/tokenplan"
APPCAST_RAW_URL="https://raw.githubusercontent.com/${GITHUB_REPO}/main/releases/appcast.xml"

SHORT_VERSION="${1:-}"
BUILD_VERSION="${2:-}"
TAG="v${SHORT_VERSION}"

if [[ -z "$SHORT_VERSION" || -z "$BUILD_VERSION" ]]; then
  echo "用法: $0 <shortVersion> <buildNumber>"
  echo "示例: $0 1.0.1 2"
  exit 1
fi

if [[ ! -d "$APP_NAME" ]]; then
  echo "未找到 ${APP_NAME}，请先运行 ./build.sh"
  exit 1
fi

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${SHORT_VERSION}" "${APP_NAME}/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${BUILD_VERSION}" "${APP_NAME}/Contents/Info.plist"

mkdir -p "$RELEASES_DIR"
rm -f "${RELEASES_DIR}/${ZIP_NAME}"
ditto -c -k --sequesterRsrc --keepParent "$APP_NAME" "${RELEASES_DIR}/${ZIP_NAME}"

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
echo "  # 1. 推送 appcast.xml（仅元数据，不含安装包）"
echo "  git add releases/appcast.xml"
echo "  git commit -m \"release: ${TAG}\""
echo "  git push github main"
echo ""
echo "  # 2. 创建 Release 并上传 zip（安装包不进 git）"
echo "  gh release create ${TAG} \\"
echo "    --repo ${GITHUB_REPO} \\"
echo "    --title \"Token Plan ${SHORT_VERSION}\" \\"
echo "    --notes \"Token Plan ${SHORT_VERSION}\" \\"
echo "    \"${RELEASES_DIR}/${ZIP_NAME}\""
echo ""
echo "Appcast 地址（Info.plist SUFeedURL）："
echo "  ${APPCAST_RAW_URL}"
echo ""
echo "⚠️  切勿提交：TokenPlan.zip、EdDSA 私钥、JWT/凭证、.env"
