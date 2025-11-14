#!/bin/bash

# 3proxy 快速部署脚本
# 使用方法: 
#   ./deploy.sh
#   ./deploy.sh --http-port 3128 --socks-port 1080 --admin-port 8080
#   或使用环境变量: HTTP_PORT=3128 SOCKS_PORT=1080 ADMIN_PORT=8080 ./deploy.sh

set -e

# 解析命令行参数
while [[ $# -gt 0 ]]; do
    case $1 in
        --http-port=*)
            HTTP_PORT="${1#*=}"
            shift
            ;;
        --http-port)
            HTTP_PORT="$2"
            shift 2
            ;;
        --socks-port=*)
            SOCKS_PORT="${1#*=}"
            shift
            ;;
        --socks-port)
            SOCKS_PORT="$2"
            shift 2
            ;;
        --admin-port=*)
            ADMIN_PORT="${1#*=}"
            shift
            ;;
        --admin-port)
            ADMIN_PORT="$2"
            shift 2
            ;;
        --admin-user=*)
            ADMIN_USER="${1#*=}"
            shift
            ;;
        --admin-user)
            ADMIN_USER="$2"
            shift 2
            ;;
        --admin-pass=*)
            ADMIN_PASS="${1#*=}"
            shift
            ;;
        --admin-pass)
            ADMIN_PASS="$2"
            shift 2
            ;;
        --proxy-user=*)
            PROXY_USER="${1#*=}"
            shift
            ;;
        --proxy-user)
            PROXY_USER="$2"
            shift 2
            ;;
        --proxy-pass=*)
            PROXY_PASS="${1#*=}"
            shift
            ;;
        --proxy-pass)
            PROXY_PASS="$2"
            shift 2
            ;;
        -h|--help)
            echo "使用方法:"
            echo "  ./deploy.sh [选项]"
            echo ""
            echo "选项:"
            echo "  --http-port PORT     HTTP 代理端口 (默认: 3128)"
            echo "  --socks-port PORT    SOCKS5 代理端口 (默认: 1080)"
            echo "  --admin-port PORT    管理面板端口 (默认: 8080)"
            echo "  --admin-user USER    管理员用户名 (默认: admin，未设置则自动生成)"
            echo "  --admin-pass PASS    管理员密码 (默认: 自动生成随机密码)"
            echo "  --proxy-user USER    代理用户名 (默认: user1，未设置则自动生成)"
            echo "  --proxy-pass PASS    代理用户密码 (默认: 自动生成随机密码)"
            echo "  -h, --help           显示帮助信息"
            echo ""
            echo "示例:"
            echo "  ./deploy.sh --http-port 3128 --socks-port 1080 --admin-port 8080"
            echo "  ./deploy.sh --http-port=3128 --socks-port=1080 --admin-port=8080"
            echo "  HTTP_PORT=3128 SOCKS_PORT=1080 ADMIN_PORT=8080 ./deploy.sh"
            exit 0
            ;;
        *)
            echo "未知参数: $1"
            echo "使用 --help 查看帮助信息"
            exit 1
            ;;
    esac
done

# 配置变量（可根据需要修改）
CONFIG_DIR="./conf"
IMAGE_NAME="youfak/3proxy:latest"
CONTAINER_NAME="3proxy"

# 端口配置（可通过命令行参数或环境变量设置，未设置则使用默认值）
HTTP_PORT="${HTTP_PORT:-3128}"
SOCKS_PORT="${SOCKS_PORT:-1080}"
ADMIN_PORT="${ADMIN_PORT:-8080}"

# 生成随机密码函数
generate_password() {
    # 生成16位随机密码（包含大小写字母、数字）
    openssl rand -base64 12 | tr -d "=+/" | cut -c1-16 2>/dev/null || \
    cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 16 | head -n 1
}

# 生成随机用户名函数
generate_username() {
    # 生成8位随机用户名（小写字母和数字）
    cat /dev/urandom | tr -dc 'a-z0-9' | fold -w 8 | head -n 1
}

# 用户配置（可通过命令行参数或环境变量设置，未设置则自动生成）
ADMIN_USER="${ADMIN_USER:-admin}"
if [ -z "${ADMIN_PASS}" ]; then
    ADMIN_PASS=$(generate_password)
    ADMIN_PASS_GENERATED=true
else
    ADMIN_PASS_GENERATED=false
fi

PROXY_USER="${PROXY_USER:-user1}"
if [ -z "${PROXY_PASS}" ]; then
    PROXY_PASS=$(generate_password)
    PROXY_PASS_GENERATED=true
else
    PROXY_PASS_GENERATED=false
fi

# 流量限制配置（单位：MB，10GB = 10240 MB）
TRAFFIC_LIMIT="10240"
TRAFFIC_LIMIT_TYPE="M"  # M=每月, D=每天, W=每周

echo "=========================================="
echo "3proxy 快速部署脚本"
echo "=========================================="
echo ""
echo "端口配置:"
echo "  - HTTP 代理:  ${HTTP_PORT}"
echo "  - SOCKS5 代理: ${SOCKS_PORT}"
echo "  - 管理面板:   ${ADMIN_PORT}"
echo ""

# 创建配置目录
echo "[1/7] 创建配置目录..."
mkdir -p "${CONFIG_DIR}"

# 创建密码文件
echo "[2/7] 创建密码文件..."
cat > "${CONFIG_DIR}/passwd" << EOF
${ADMIN_USER}:CL:${ADMIN_PASS}
${PROXY_USER}:CL:${PROXY_PASS}
EOF
echo "✓ 密码文件已创建: ${CONFIG_DIR}/passwd"
if [ "$ADMIN_PASS_GENERATED" = true ]; then
    echo "  - 管理员: ${ADMIN_USER} / ${ADMIN_PASS} (自动生成)"
else
    echo "  - 管理员: ${ADMIN_USER} / ${ADMIN_PASS}"
fi
if [ "$PROXY_PASS_GENERATED" = true ]; then
    echo "  - 代理用户: ${PROXY_USER} / ${PROXY_PASS} (自动生成)"
else
    echo "  - 代理用户: ${PROXY_USER} / ${PROXY_PASS}"
fi

# 创建主配置文件
echo "[3/7] 创建配置文件..."
cat > "${CONFIG_DIR}/3proxy.cfg" << 'EOF'
# DNS 配置
nserver 8.8.8.8
nserver 8.8.4.4
nscache 65536

# 日志配置（输出到 stdout，方便 docker logs 查看，避免权限问题）
log

# 流量计数器
counter /count/3proxy.3cf

# 从文件加载用户
users $/conf/passwd

# 包含流量限制和带宽限制配置
include /conf/counters
include /conf/bandlimiters

# HTTP/SOCKS 代理配置
auth strong
allow *
proxy -p3128
socks -p1080

# 管理面板配置
flush
auth strong
allow admin
admin -p8080
EOF
echo "✓ 配置文件已创建: ${CONFIG_DIR}/3proxy.cfg"

# 创建流量限制配置文件
echo "[4/7] 创建流量限制配置..."
cat > "${CONFIG_DIR}/counters" << EOF
# 流量限制配置文件
# 格式: countin "编号/名称" 类型 限制(MB) 用户列表 源地址 目标地址 目标端口 操作
# 类型: D=每天, W=每周, M=每月, H=每小时

# 不统计内网流量（192.168.0.0/16 和 10.0.0.0/8）
nocountin * * 192.168.0.0/16,10.0.0.0/8

# 为每个用户设置 ${TRAFFIC_LIMIT}MB (${TRAFFIC_LIMIT_TYPE}) 流量限制
# 注意：需要为每个用户单独配置，编号必须唯一
countin "1/${ADMIN_USER}" ${TRAFFIC_LIMIT_TYPE} ${TRAFFIC_LIMIT} ${ADMIN_USER} * * *
countin "2/${PROXY_USER}" ${TRAFFIC_LIMIT_TYPE} ${TRAFFIC_LIMIT} ${PROXY_USER} * * *
EOF
echo "✓ 流量限制配置已创建: ${CONFIG_DIR}/counters"
echo "  - 默认限制: ${TRAFFIC_LIMIT}MB/${TRAFFIC_LIMIT_TYPE}"

# 创建带宽限制配置文件
echo "[5/7] 创建带宽限制配置..."
cat > "${CONFIG_DIR}/bandlimiters" << 'EOF'
# 带宽限制配置文件
# 格式: bandlimin 带宽(bps) 用户列表 源地址 目标地址 目标端口
# 带宽单位: bits per second (bps)
# 例如: 1048576 = 1Mbps, 10485760 = 10Mbps

# 不限制内网带宽
nobandlimin * * 192.168.0.0/16,10.0.0.0/8

# 如果需要限制带宽，取消下面的注释并修改数值
# 示例：限制每个用户带宽为 10Mbps (10485760 bps)
# bandlimin 10485760 * * * *
EOF
echo "✓ 带宽限制配置已创建: ${CONFIG_DIR}/bandlimiters"

# 创建 docker-compose.yml
echo "[6/7] 创建 docker-compose.yml..."
cat > docker-compose.yml << EOF
services:
  3proxy:
    image: ${IMAGE_NAME}
    container_name: ${CONTAINER_NAME}
    restart: unless-stopped
    ports:
      - "${HTTP_PORT}:3128"   # HTTP 代理
      - "${SOCKS_PORT}:1080"  # SOCKS5 代理
      - "${ADMIN_PORT}:8080"  # 管理面板
    volumes:
      - ${CONFIG_DIR}:/usr/local/3proxy/conf
      - ./data:/usr/local/3proxy
    command: >
      sh -c "
        mkdir -p /usr/local/3proxy/count &&
        chmod 777 /usr/local/3proxy/count &&
        /bin/3proxy /etc/3proxy/3proxy.cfg
      "
    healthcheck:
      test: ["CMD", "wget", "--spider", "-q", "http://localhost:8080"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 10s
EOF
echo "✓ docker-compose.yml 已创建"

# 创建数据目录（用于存储计数器数据）
mkdir -p ./data/count
# 设置目录权限，确保容器内的用户（uid 65535）可以写入
chmod 777 ./data/count 2>/dev/null || true

# 检测 docker compose 命令
if docker compose version >/dev/null 2>&1; then
    DOCKER_COMPOSE_CMD="docker compose"
elif command -v docker-compose >/dev/null 2>&1 && docker-compose version >/dev/null 2>&1; then
    DOCKER_COMPOSE_CMD="docker-compose"
else
    echo ""
    echo "=========================================="
    echo "✗ 错误: 未找到 docker compose 或 docker-compose"
    echo "=========================================="
    echo ""
    echo "请安装 Docker Compose:"
    echo "  - 新版本 Docker: docker compose 已包含在内"
    echo "  - 旧版本: 请安装 docker-compose"
    echo ""
    echo "检查命令:"
    echo "  docker compose version"
    echo "  或"
    echo "  docker-compose --version"
    exit 1
fi

echo "使用命令: ${DOCKER_COMPOSE_CMD}"

# 停止并删除旧容器（如果存在）
echo "[7/7] 启动容器..."
if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    echo "  停止并删除旧容器..."
    # 先尝试使用 docker compose down
    ${DOCKER_COMPOSE_CMD} down 2>/dev/null || true
    # 如果还有残留，强制删除容器
    if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        echo "  强制删除残留容器..."
        docker stop "${CONTAINER_NAME}" 2>/dev/null || true
        docker rm -f "${CONTAINER_NAME}" 2>/dev/null || true
    fi
fi

# 启动容器
${DOCKER_COMPOSE_CMD} up -d

# 等待容器启动
echo "  等待容器启动..."
sleep 3

# 检查容器状态
if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    echo ""
    echo "=========================================="
    echo "✓ 部署成功！"
    echo "=========================================="
    echo ""
    echo "服务信息："
    echo "  - HTTP 代理:  ${HTTP_PORT}"
    echo "  - SOCKS5 代理: ${SOCKS_PORT}"
    echo "  - 管理面板:   http://localhost:${ADMIN_PORT}"
    echo ""
    echo "登录信息："
    echo "  - 管理员用户名: ${ADMIN_USER}"
    echo "  - 管理员密码: ${ADMIN_PASS}"
    if [ "$ADMIN_PASS_GENERATED" = true ] || [ "$PROXY_PASS_GENERATED" = true ]; then
        echo "    ⚠️  密码已自动生成，请妥善保存！"
    fi
    echo ""
    echo "代理用户信息："
    echo "  - 用户名: ${PROXY_USER}"
    echo "  - 密码: ${PROXY_PASS}"
    echo ""
    echo "流量限制："
    echo "  - 默认限制: ${TRAFFIC_LIMIT}MB/${TRAFFIC_LIMIT_TYPE}"
    echo "  - 配置文件: ${CONFIG_DIR}/counters"
    echo ""
    echo "常用命令："
    echo "  - 查看日志: docker logs -f ${CONTAINER_NAME}"
    echo "  - 停止服务: ${DOCKER_COMPOSE_CMD} down"
    echo "  - 重启服务: ${DOCKER_COMPOSE_CMD} restart"
    echo ""
else
    echo ""
    echo "=========================================="
    echo "✗ 部署失败，请检查日志"
    echo "=========================================="
    echo "查看日志: docker logs ${CONTAINER_NAME}"
    exit 1
fi

