#!/bin/sh
set -e

# Docker 鍏ュ彛鐐硅剼鏈?
# 鍔熻兘锛?
# 1. 妫€鏌ラ厤缃枃浠讹紝浣跨敤榛樿閰嶇疆浣滀负鍚庡
# 2. 鍚姩涓诲簲鐢紙鍩庡競鏁版嵁鍦ㄥ惎鍔ㄦ椂鑷姩浠庡祵鍏ユ暟鎹鍏ワ級

# 閰嶇疆鏂囦欢璺緞
CONFIG_FILE="${CONFIG_FILE:-/app/config.yaml}"
DEFAULT_CONFIG="/app/config.base.yaml"

# 濡傛灉娌℃湁澶栭儴閰嶇疆鏂囦欢锛屼娇鐢ㄩ粯璁ら厤缃?
if [ ! -f "$CONFIG_FILE" ]; then
    echo "No external config found, using base config"
    CONFIG_FILE="$DEFAULT_CONFIG"
fi

echo "Using config: $CONFIG_FILE"

# 纭繚鏁版嵁鐩綍瀛樺湪
mkdir -p /app/data/logs /app/data/photos

# 鍚姩涓诲簲鐢?
echo "Starting Relive..."
exec /app/relive --config "$CONFIG_FILE"
