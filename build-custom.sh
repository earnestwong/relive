#!/bin/bash
# ============================================================
# Relive 自定义镜像构建脚本（本地源码版）
# 使用方法：先上传 relive-source.tar.gz 到同目录，再执行本脚本
# 修复内容：
#   1. Caption 生成复用配置的 MaxTokens，上限提升至 32000
#   2. 省份 FIPS 映射修正（18→贵州, 19→辽宁, 31→海南, 32→四川, 33→重庆）
#   3. 全彩图自适应尺寸（横版 1024×768，竖版 768×1024）
#   4. 墨水屏保持 480×800 不变
# ============================================================

set -e

WORK_DIR="/mnt/user/appdata/relive-custom"
SRC_DIR="$WORK_DIR/relive-source"
SRC_TAR="$WORK_DIR/relive-source.tar.gz"

echo ""
echo "╔════════════════════════════════════════════╗"
echo "║   Relive 自定义镜像构建工具               ║"
echo "╚════════════════════════════════════════════╝"
echo ""

# ============================================
# 1. 检查源码包
# ============================================
echo -e "\033[0;34m[1/6]\033[0m 检查源码包..."
if [ ! -f "$SRC_TAR" ]; then
    echo -e "\033[0;31m❌ 未找到 relive-source.tar.gz\033[0m"
    echo "  请先将 relive-source.tar.gz 上传到 $WORK_DIR/"
    exit 1
fi
echo -e "\033[0;32m  ✓\033[0m 源码包已就绪 ($(du -h "$SRC_TAR" | cut -f1))"

# ============================================
# 2. 解压源码
# ============================================
echo -e "\033[0;34m[2/6]\033[0m 解压源码..."
rm -rf "$SRC_DIR"
mkdir -p "$SRC_DIR"
tar -xzf "$SRC_TAR" -C "$SRC_DIR"
echo -e "\033[0;32m  ✓\033[0m 源码已解压到 $SRC_DIR"

cd "$SRC_DIR"

# ============================================
# 3. 验证修改（源码已包含所有修复，这里仅做确认）
# ============================================
echo -e "\033[0;34m[3/6]\033[0m 验证代码修改..."

if grep -q 'p.config.MaxTokens' backend/internal/provider/openai.go; then
    echo -e "\033[0;32m  ✓\033[0m openai.go: MaxTokens 修复已确认"
else
    echo -e "\033[0;31m  ✗\033[0m openai.go: MaxTokens 修复未找到"
fi

if grep -q 'p.config.MaxTokens' backend/internal/provider/vllm.go; then
    echo -e "\033[0;32m  ✓\033[0m vllm.go: MaxTokens 修复已确认"
else
    echo -e "\033[0;31m  ✗\033[0m vllm.go: MaxTokens 修复未找到"
fi

if grep -q '"32": "四川省"' backend/internal/geocode/offline.go; then
    echo -e "\033[0;32m  ✓\033[0m offline.go: 省份映射修复已确认（32→四川, 33→重庆）"
else
    echo -e "\033[0;31m  ✗\033[0m offline.go: 省份映射修复未找到"
fi

if grep -q 'BuildDisplayCanvasAdaptive' backend/internal/util/display_assets.go; then
    echo -e "\033[0;32m  ✓\033[0m display_assets.go: 自适应 Canvas 函数已确认"
else
    echo -e "\033[0;31m  ✗\033[0m display_assets.go: 自适应 Canvas 函数未找到"
fi

# ============================================
# 4. 构建镜像
# ============================================
echo -e "\033[0;34m[4/6]\033[0m 构建 Docker 镜像..."
echo "  这可能需要 10-30 分钟，请耐心等待..."

docker build -t relive-custom:latest . 2>&1 | tail -30

if [ $? -ne 0 ]; then
    echo -e "\033[0;31m❌ 镜像构建失败\033[0m"
    exit 1
fi

echo -e "\033[0;32m  ✓\033[0m 镜像构建完成: relive-custom:latest"

# ============================================
# 5. 停止旧容器
# ============================================
echo -e "\033[0;34m[5/6]\033[0m 停止旧容器..."

if docker ps -a | grep -q "relive"; then
    docker stop relive 2>/dev/null || true
    docker rm relive 2>/dev/null || true
    echo -e "\033[0;32m  ✓\033[0m 旧容器已停止并删除"
else
    echo "  未找到现有的 relive 容器"
fi

# ============================================
# 6. 启动新容器
# ============================================
echo -e "\033[0;34m[6/6]\033[0m 启动新容器..."

# 读取现有配置
if [ -f "/mnt/user/appdata/relive/.env" ]; then
    source /mnt/user/appdata/relive/.env
fi

JWT_SECRET="${JWT_SECRET:-relive-default-secret-change-me}"

# 检查网络是否存在
if ! docker network ls | grep -q "relive-network"; then
    docker network create relive-network
    echo -e "\033[0;32m  ✓\033[0m 创建网络: relive-network"
fi

docker run -d \
  --name relive \
  --restart unless-stopped \
  --network relive-network \
  -p 3002:8080 \
  -v /mnt/user/appdata/relive/backend/config.prod.yaml:/app/config.yaml:ro \
  -v /mnt/user/appdata/relive/data/backend:/app/data \
  -v /mnt/user/relive-photos:/app/photos:ro \
  -e TZ=Asia/Shanghai \
  -e "JWT_SECRET=${JWT_SECRET}" \
  -e GOMAXPROCS=2 \
  -e MAX_SCAN_WORKERS=2 \
  -e MAX_THUMBNAIL_WORKERS=1 \
  -e MAX_GEOCODE_WORKERS=1 \
  -e AUTO_IMPORT_CITIES=true \
  relive-custom:latest

echo -e "\033[0;32m  ✓\033[0m 新容器已启动"

echo ""
echo "╔════════════════════════════════════════════╗"
echo "║   ✅ 构建和部署完成！                     ║"
echo "╚════════════════════════════════════════════╝"
echo ""
echo "📌 访问地址：http://192.168.50.94:3002"
echo ""
echo "📝 修复内容："
echo "   1. Caption MaxTokens 复用配置值（上限 32000）"
echo "   2. 省份映射修正（成都→四川, 重庆→重庆 等）"
echo "   3. 全彩图自适应尺寸（横版 1024×768，竖版 768×1024）"
echo "   4. 墨水屏保持 480×800 不变"
echo ""
echo "💡 建议在 WebUI 中将「最大 Tokens」设为 8000-16000"
echo ""
