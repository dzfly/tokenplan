#!/usr/bin/env bash
set -euo pipefail

PRODUCT="TalTokenPlan"
HELPER="CookieReaderHelper"
APP_NAME="Token Plan.app"
RESOURCES="Resources"
ENTITLEMENTS="${RESOURCES}/TalTokenPlan.entitlements"
ARM64_BUILD=".build/arm64-build"
X86_BUILD=".build/x86-build"
ARM64_BIN="${ARM64_BUILD}/arm64-apple-macosx/release/${PRODUCT}"
X86_BIN="${X86_BUILD}/x86_64-apple-macosx/release/${PRODUCT}"
ARM64_HELPER="${ARM64_BUILD}/arm64-apple-macosx/release/${HELPER}"
X86_HELPER="${X86_BUILD}/x86_64-apple-macosx/release/${HELPER}"
UNIVERSAL_BIN=".build/${PRODUCT}-universal"
UNIVERSAL_HELPER=".build/${HELPER}-universal"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"

echo "→ 编译 arm64..."
swift build -c release --triple arm64-apple-macosx --build-path "$ARM64_BUILD"

echo "→ 编译 x86_64..."
swift build -c release --triple x86_64-apple-macosx --build-path "$X86_BUILD"

echo "→ 合并通用二进制..."
lipo -create -output "$UNIVERSAL_BIN" "$ARM64_BIN" "$X86_BIN"
lipo -create -output "$UNIVERSAL_HELPER" "$ARM64_HELPER" "$X86_HELPER"
lipo -info "$UNIVERSAL_BIN"
lipo -info "$UNIVERSAL_HELPER"

# Sparkle 通过 @rpath 链接，打包后 framework 在 Contents/Frameworks
if ! otool -l "$UNIVERSAL_BIN" | grep -q '@executable_path/../Frameworks'; then
    install_name_tool -add_rpath "@executable_path/../Frameworks" "$UNIVERSAL_BIN"
fi

echo "→ 打包 .app bundle..."
rm -rf "$APP_NAME"
mkdir -p "${APP_NAME}/Contents/MacOS"
mkdir -p "${APP_NAME}/Contents/Helpers"
mkdir -p "${APP_NAME}/Contents/Resources"

cp "$UNIVERSAL_BIN" "${APP_NAME}/Contents/MacOS/${PRODUCT}"
cp "$UNIVERSAL_HELPER" "${APP_NAME}/Contents/Helpers/${HELPER}"
cp "${RESOURCES}/Info.plist" "${APP_NAME}/Contents/"
cp "${RESOURCES}/AppIcon.icns" "${APP_NAME}/Contents/Resources/"

embed_sparkle_framework() {
    local build_path="$1"
    local framework
    framework=$(find "$build_path" -path "*/Sparkle.framework" -type d 2>/dev/null | head -1)
    if [[ -z "$framework" ]]; then
        echo "⚠️  未找到 Sparkle.framework，跳过嵌入（请先 swift package resolve）"
        return
    fi
    echo "→ 嵌入 Sparkle.framework..."
    mkdir -p "${APP_NAME}/Contents/Frameworks"
    rm -rf "${APP_NAME}/Contents/Frameworks/Sparkle.framework"
    cp -R "$framework" "${APP_NAME}/Contents/Frameworks/"
}

embed_sparkle_framework "$ARM64_BUILD"

echo "→ 代码签名 (${SIGN_IDENTITY})..."
SIGN_ARGS=(--force --sign "$SIGN_IDENTITY" --entitlements "$ENTITLEMENTS")
if [ "$SIGN_IDENTITY" != "-" ]; then
  SIGN_ARGS+=(--options runtime --timestamp)
fi

codesign "${SIGN_ARGS[@]}" "${APP_NAME}/Contents/Helpers/${HELPER}"
if [[ -d "${APP_NAME}/Contents/Frameworks/Sparkle.framework" ]]; then
  codesign "${SIGN_ARGS[@]}" "${APP_NAME}/Contents/Frameworks/Sparkle.framework"
fi
codesign "${SIGN_ARGS[@]}" "${APP_NAME}/Contents/MacOS/${PRODUCT}"
codesign --force --sign "$SIGN_IDENTITY" "${APP_NAME}"

echo "→ 验证签名..."
codesign --verify --deep --strict --verbose=2 "${APP_NAME}"

echo "✅ 打包完成：${APP_NAME} (Universal: arm64 + x86_64)"
echo "   运行: open \"${APP_NAME}\""
if [ "$SIGN_IDENTITY" = "-" ]; then
  echo ""
  echo "   分发签名示例:"
  echo "   SIGN_IDENTITY=\"Developer ID Application: Your Name (TEAMID)\" ./build.sh"
fi
