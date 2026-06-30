#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

PRODUCT="TalTokenPlan"
APP_NAME="Token Plan.app"
DMG_NAME="TokenPlan"
VOLUME_NAME="Token Plan"
BACKGROUND="${ROOT}/Resources/dmg-background.png"
RW_DMG="${ROOT}/.build/${DMG_NAME}-temp.dmg"
FINAL_DMG="${ROOT}/${DMG_NAME}.dmg"
MOUNT_POINT="/Volumes/${VOLUME_NAME}"

if [ ! -f "$BACKGROUND" ]; then
  echo "错误: 找不到 ${BACKGROUND}" >&2
  exit 1
fi

if [ ! -d "$APP_NAME" ]; then
  echo "→ 未找到 ${APP_NAME}，先执行 build.sh..."
  ./build.sh
fi

mkdir -p .build
rm -f "$RW_DMG" "$FINAL_DMG"

APP_SIZE=$(du -sm "$APP_NAME" | cut -f1)
DMG_SIZE=$((APP_SIZE + 50))

echo "→ 创建 DMG (${DMG_SIZE}MB)..."
hdiutil create -size "${DMG_SIZE}m" -fs HFS+ -volname "$VOLUME_NAME" -layout SPUD "$RW_DMG"

hdiutil detach "$MOUNT_POINT" -quiet 2>/dev/null || true

echo "→ 挂载 DMG..."
DEVICE=$(hdiutil attach -readwrite -noverify -noautoopen "$RW_DMG" | grep "^/dev/" | head -1 | awk '{print $1}')
sleep 2

echo "→ 写入文件..."
mkdir -p "${MOUNT_POINT}/.background"
cp "$BACKGROUND" "${MOUNT_POINT}/.background/background.png"
cp -R "$APP_NAME" "$MOUNT_POINT/"
ln -s /Applications "${MOUNT_POINT}/Applications"

echo "→ 配置拖拽安装引导..."
BG_PATH="${MOUNT_POINT}/.background/background.png"
osascript <<APPLESCRIPT
set bgFile to POSIX file "${BG_PATH}" as alias
tell application "Finder"
    tell disk "${VOLUME_NAME}"
        open
        set dmgWindow to container window
        tell dmgWindow
            set current view to icon view
            set toolbar visible to false
            set statusbar visible to false
            set bounds to {100, 100, 760, 500}
        end tell
        tell icon view options of dmgWindow
            set arrangement to not arranged
            set icon size to 128
            set background picture to bgFile
        end tell
        set position of item "${APP_NAME}" of dmgWindow to {180, 200}
        set position of item "Applications" of dmgWindow to {480, 200}
        update without registering applications
        delay 2
        close
    end tell
end tell
APPLESCRIPT

sync
sleep 2

echo "→ 卸载 DMG..."
hdiutil detach "$DEVICE"

echo "→ 压缩 DMG..."
hdiutil convert "$RW_DMG" -format UDZO -imagekey zlib-level=9 -o "$FINAL_DMG"
rm -f "$RW_DMG"

echo "✅ DMG 已生成: ${FINAL_DMG}"
echo "   打开: open ${FINAL_DMG}"
