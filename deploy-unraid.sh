#!/bin/bash
# ============================================================
# Relive 智能相册 - Unraid 一键部署脚本
# ============================================================
# 使用方法：
#   1. 将此脚本上传到 Unraid（或通过 SSH 直接执行）
#   2. chmod +x deploy-unraid.sh && ./deploy-unraid.sh
# ============================================================

set -e

# 颜色定义
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

DEPLOY_DIR="/mnt/user/appdata/relive"

echo ""
echo "╔════════════════════════════════════════════╗"
echo "║   🚀 Relive 智能相册 - Unraid 部署工具    ║"
echo "╚════════════════════════════════════════════╝"
echo ""

# ============================================
# 1. 环境检查
# ============================================
echo -e "${BLUE}[1/6]${NC} 检查部署环境..."

if ! command -v docker &> /dev/null; then
    echo -e "${RED}❌ Docker 未安装，请先在 Unraid 插件管理中安装 Docker${NC}"
    exit 1
fi
echo -e "${GREEN}  ✓${NC} Docker 已安装: $(docker --version)"

# 检测 Docker Compose 版本（Unraid 使用旧版 docker-compose）
if docker compose version &> /dev/null; then
    DOCKER_COMPOSE_CMD="docker compose"
    echo -e "${GREEN}  ✓${NC} Docker Compose (v2) 已安装"
elif docker-compose --version &> /dev/null; then
    DOCKER_COMPOSE_CMD="docker-compose"
    echo -e "${GREEN}  ✓${NC} Docker Compose (v1) 已安装"
else
    echo -e "${RED}❌ Docker Compose 未安装${NC}"
    exit 1
fi

ARCH=$(uname -m)
echo -e "${GREEN}  ✓${NC} 系统架构: $ARCH"

echo ""

# ============================================
# 2. 创建目录结构
# ============================================
echo -e "${BLUE}[2/6]${NC} 创建部署目录..."

mkdir -p "$DEPLOY_DIR/data/backend/logs"
mkdir -p "$DEPLOY_DIR/data/backend/thumbnails"
mkdir -p "$DEPLOY_DIR/data/ml-models"

echo -e "${GREEN}  ✓${NC} 部署目录已创建: $DEPLOY_DIR"
echo "    - data/backend/logs"
echo "    - data/backend/thumbnails"
echo "    - data/ml-models"

echo ""

# ============================================
# 3. 生成 .env 文件
# ============================================
echo -e "${BLUE}[3/6]${NC} 生成环境变量..."

if [ -f "$DEPLOY_DIR/.env" ]; then
    echo -e "${YELLOW}  ⚠️  .env 已存在，跳过生成${NC}"
else
    # 生成随机 JWT 密钥
    if command -v openssl &> /dev/null; then
        JWT_SECRET=$(openssl rand -base64 32)
    else
        JWT_SECRET=$(head -c 32 /dev/urandom | base64)
    fi

    cat > "$DEPLOY_DIR/.env" << EOF
# Relive 环境变量配置
# 生成时间: $(date '+%Y-%m-%d %H:%M:%S')

# JWT 密钥（自动生成，请勿泄露）
JWT_SECRET=${JWT_SECRET}

# 服务端口
RELIVE_PORT=3002

# 外部访问地址（可选，用于反向代理场景）
# RELIVE_EXTERNAL_URL=http://192.168.50.94:3002
EOF

    echo -e "${GREEN}  ✓${NC} .env 已生成（JWT 密钥已自动创建）"
fi

echo ""

# ============================================
# 4. 生成 config.prod.yaml
# ============================================
echo -e "${BLUE}[4/6]${NC} 生成生产配置文件..."

if [ -f "$DEPLOY_DIR/backend/config.prod.yaml" ]; then
    echo -e "${YELLOW}  ⚠️  config.prod.yaml 已存在，跳过生成${NC}"
else
    mkdir -p "$DEPLOY_DIR/backend"
    cat > "$DEPLOY_DIR/backend/config.prod.yaml" << 'EOF'
# 生产环境配置
server:
  mode: "release"
  external_url: ""
  static_path: "/app/frontend/dist"

database:
  path: "/app/data/relive.db"
  log_mode: false

photos:
  root_path: "/app/photos"
  thumbnail_path: "/app/data/thumbnails"

logging:
  level: "info"
  file: "/app/data/logs/relive.log"
  console: true

security:
  jwt_Secret: "${JWT_SECRET:-relive-production-secret-change-me}"
  api_key_prefix: "sk-relive-"

performance:
  max_scan_workers: 2
  max_analyze_workers: 1
  max_thumbnail_workers: 1
  max_geocode_workers: 1
  cache_size: 1000

people:
  ml_endpoint: "http://relive-ml:5050"
  timeout: 15
  merge_suggestion_threshold: 0.58
  merge_suggestion_max_pairs_per_run: 200
  merge_suggestion_batch_size: 100
  merge_suggestion_cooldown_seconds: 300
EOF

    echo -e "${GREEN}  ✓${NC} config.prod.yaml 已生成"
fi

echo ""

# ============================================
# 5. 生成 docker-compose.yml
# ============================================
echo -e "${BLUE}[5/6]${NC} 生成 Docker Compose 配置..."

cat > "$DEPLOY_DIR/docker-compose.yml" << 'EOF'
services:
  relive-ml:
    image: davidhu/relive-ml:latest
    container_name: relive-ml
    restart: unless-stopped
    environment:
      - RELIVE_ML_ONNX_DEVICE=cpu
      - RELIVE_ML_MODEL_PACK=buffalo_sc
    volumes:
      # InsightFace 模型缓存持久化
      - ./data/ml-models:/app/models
    networks:
      - relive-network
    healthcheck:
      test: ["CMD", "wget", "--no-verbose", "--tries=1", "--spider", "http://localhost:5050/api/v1/health"]
      interval: 30s
      timeout: 3s
      retries: 3
      start_period: 120s

  relive:
    image: davidhu/relive:latest
    container_name: relive
    restart: unless-stopped
    stop_grace_period: 60s
    depends_on:
      - relive-ml
    ports:
      - "${RELIVE_PORT:-3002}:8080"
    volumes:
      # 配置文件
      - ./backend/config.prod.yaml:/app/config.yaml:ro
      # 数据目录（数据库、日志、缩略图）
      - ./data/backend:/app/data
      # =============================================================================
      # 照片目录挂载（取消注释并修改为你实际的路径）
      # 使用方法：
      #   1. 修改冒号左边的宿主机路径为你实际的照片目录
      #   2. 容器内路径 /app/photos 保持不变
      #   3. 在 Web 界面中添加扫描路径时使用容器内路径：/app/photos
      #
      # Unraid 示例：
      #   - /mnt/user/photos:/app/photos:ro
      #   - /mnt/user/Media/Photos:/app/photos:ro
      #   - /mnt/disk1/photos:/app/photos:ro
      # =============================================================================
      # - /mnt/user/photos:/app/photos:ro
    environment:
      - TZ=Asia/Shanghai
      - JWT_SECRET=${JWT_SECRET}
      - RELIVE_EXTERNAL_URL=${RELIVE_EXTERNAL_URL:-}
      - GOMAXPROCS=2
      - MAX_SCAN_WORKERS=2
      - MAX_THUMBNAIL_WORKERS=1
      - MAX_GEOCODE_WORKERS=1
      - AUTO_IMPORT_CITIES=true
    networks:
      - relive-network
    healthcheck:
      test: ["CMD", "wget", "--no-verbose", "--tries=1", "--spider", "http://localhost:8080/api/v1/system/health"]
      interval: 30s
      timeout: 3s
      retries: 3
      start_period: 10s
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"

networks:
  relive-network:
    driver: bridge
EOF

echo -e "${GREEN}  ✓${NC} docker-compose.yml 已生成"

echo ""

# ============================================
# 6. 拉取镜像并启动服务
# ============================================
echo -e "${BLUE}[6/6]${NC} 拉取镜像并启动服务..."

cd "$DEPLOY_DIR"

echo -e "${YELLOW}  正在拉取 Docker 镜像（首次可能需要几分钟）...${NC}"
$DOCKER_COMPOSE_CMD pull

echo -e "${YELLOW}  正在启动服务...${NC}"
$DOCKER_COMPOSE_CMD up -d

echo ""
echo "╔════════════════════════════════════════════╗"
echo "║   ✅ 部署完成！                           ║"
echo "╚════════════════════════════════════════════╝"
echo ""

# 获取本机 IP
LOCAL_IP=$(hostname -I 2>/dev/null | awk '{print $1}' || echo "你的Unraid IP")

echo "📌 访问地址："
echo "   🌐 http://${LOCAL_IP}:3002"
echo "   💚 健康检查：http://${LOCAL_IP}:3002/api/v1/system/health"
echo ""
echo "🔐 默认管理员账号："
echo "   用户名：admin"
echo "   密码：admin"
echo "   ⚠️  首次登录会强制修改密码"
echo ""
echo "📁 部署目录：$DEPLOY_DIR"
echo ""
echo "📝 常用命令："
echo "   查看日志：cd $DEPLOY_DIR && $DOCKER_COMPOSE_CMD logs -f"
echo "   停止服务：cd $DEPLOY_DIR && $DOCKER_COMPOSE_CMD down"
echo "   重启服务：cd $DEPLOY_DIR && $DOCKER_COMPOSE_CMD restart"
echo "   查看状态：cd $DEPLOY_DIR && $DOCKER_COMPOSE_CMD ps"
echo ""
echo "📚 下一步："
echo "   1. 浏览器访问 http://${LOCAL_IP}:3002"
echo "   2. 使用 admin/admin 登录（首次登录需修改密码）"
echo "   3. 在「配置管理」中添加照片扫描路径"
echo "   4. 开始扫描照片"
echo "   5. （可选）配置 AI 提供者进行智能分析"
echo ""
echo "💡 配置照片目录："
echo "   编辑 $DEPLOY_DIR/docker-compose.yml"
echo "   取消注释照片目录挂载行并修改路径，然后执行："
echo "   cd $DEPLOY_DIR && $DOCKER_COMPOSE_CMD down && $DOCKER_COMPOSE_CMD up -d"
echo ""
