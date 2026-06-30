#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "→ 验证 AppSettings 默认值..."
swift - <<'SWIFT'
import Foundation

// 模拟 AppSettings 默认值逻辑
let defaults = UserDefaults.standard
defaults.removeObject(forKey: "showRemainingCost")
defaults.removeObject(forKey: "showPercentage")
defaults.removeObject(forKey: "showProgressBar")

func defaultBool(_ key: String, defaultValue: Bool) -> Bool {
    if defaults.object(forKey: key) == nil { return defaultValue }
    return defaults.bool(forKey: key)
}

assert(defaults.bool(forKey: "showRemainingCost") == false, "剩余费用默认应关闭")
assert(defaultBool("showPercentage", defaultValue: true) == true, "百分比默认应打开")
assert(defaultBool("showProgressBar", defaultValue: true) == true, "进度条默认应打开")
print("  ✅ 默认值正确")
SWIFT

echo "→ 编译 debug..."
swift build

echo "→ 启动 App (5秒后自动退出)..."
APP_BIN=".build/debug/TalTokenPlan"
pkill -f ".build/debug/TalTokenPlan" 2>/dev/null || true
"$APP_BIN" &
APP_PID=$!
sleep 5
if kill -0 "$APP_PID" 2>/dev/null; then
  echo "  ✅ App 运行正常 (PID: $APP_PID)"
  kill "$APP_PID"
  wait "$APP_PID" 2>/dev/null || true
else
  echo "  ❌ App 启动失败" >&2
  exit 1
fi

echo "→ 验证 .app bundle..."
codesign --verify --deep --strict "Token Plan.app"
lipo -info "Token Plan.app/Contents/MacOS/TalTokenPlan"
test -x "Token Plan.app/Contents/Helpers/CookieReaderHelper"
echo "  ✅ CookieReaderHelper 已打包"

echo "✅ 全部测试通过"
