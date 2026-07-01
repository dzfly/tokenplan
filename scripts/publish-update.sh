#!/usr/bin/env bash
# 打包 zip 并输出 Sparkle 签名信息，用于更新 GitLab 上的 appcast.xml
set -euo pipefail

APP_NAME="Token Plan.app"
ZIP_NAME="TokenPlan.zip"
RELEASES_DIR="releases"

SHORT_VERSION="${1:-}"
BUILD_VERSION="${2:-}"

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

echo ""
echo "✅ 已生成: ${RELEASES_DIR}/${ZIP_NAME} (${ZIP_LENGTH} bytes)"
echo "   版本: ${SHORT_VERSION} (${BUILD_VERSION})"
echo ""
echo "下一步（GitLab）："
echo "  1. 创建 GitLab Release（例如 tag v${SHORT_VERSION}）"
echo "  2. 上传 ${RELEASES_DIR}/${ZIP_NAME} 为 Release 附件"
echo "  3. 更新 ${RELEASES_DIR}/appcast.xml 中 enclosure 的 url / length / edSignature"
echo ""

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

if [[ -n "$SPARKLE_SIGN" ]]; then
  echo "Sparkle 签名（填入 appcast.xml sparkle:edSignature）："
  "$SPARKLE_SIGN" "$ZIP_PATH" || true
else
  echo "未找到 sign_update。可从 Sparkle release 解压 bin/，或："
  echo "  brew install --cask sparkle"
fi

echo ""
echo "Appcast 地址（已在 Info.plist SUFeedURL 配置）："
echo "  https://git.100tal.com/bigclass_xueyanios_tools/tal-token-plan/-/raw/main/releases/appcast.xml"
