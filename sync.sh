#!/bin/bash
# ============================================================
# Flux-Panel 外部同步规则脚本
# ============================================================
# 功能：统一管理项目各模块间的版本号、配置参数同步
# 使用方式：
#   ./sync.sh status       - 检查所有同步状态
#   ./sync.sh sync         - 执行同步（将所有配置同步到最新版本）
#   ./sync.sh env          - 生成 .env.example 模板文件
#   ./sync.sh version X.Y.Z - 更新版本号为 X.Y.Z 并同步
# ============================================================

set -e

# ------ 颜色定义 ------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# ------ 项目根目录 ------
PROJECT_ROOT="$(cd "$(dirname "$0")" && pwd)"

# ============================================================
# 第一部分：源数据定义（唯一真实来源 Single Source of Truth）
# ============================================================

# 面板版本号 - 修改此处即可同步到所有模块
PANEL_VERSION="1.4.3"

# GOST 核心版本号
GOST_VERSION="3.1.0"

# 应用内部版本号（前端 APP 版本）
APP_VERSION="1.0.3"

# Docker 镜像版本（通常与面板版本一致）
DOCKER_IMAGE_VERSION="${PANEL_VERSION}"

# 后端内部端口（Docker 内部和 application.yml 保持一致）
BACKEND_INTERNAL_PORT="6365"

# 前端内部端口（Nginx）
FRONTEND_INTERNAL_PORT="80"

# MySQL 版本
MYSQL_VERSION="5.7"

# Node 构建版本
NODE_VERSION="20.19.0"

# Java 版本
JAVA_VERSION="21"

# Spring Boot 版本
SPRINGBOOT_VERSION="2.7.18"

# ============================================================
# 第二部分：文件路径定义
# ============================================================

DOCKER_COMPOSE_V4="${PROJECT_ROOT}/docker-compose-v4.yml"
DOCKER_COMPOSE_V6="${PROJECT_ROOT}/docker-compose-v6.yml"
PANEL_INSTALL="${PROJECT_ROOT}/panel_install.sh"
NODE_INSTALL="${PROJECT_ROOT}/install.sh"
FRONTEND_SITE="${PROJECT_ROOT}/vite-frontend/src/config/site.ts"
GOST_VERSION_FILE="${PROJECT_ROOT}/go-gost/version.go"
BACKEND_POM="${PROJECT_ROOT}/springboot-backend/pom.xml"
BACKEND_YML="${PROJECT_ROOT}/springboot-backend/src/main/resources/application.yml"
BACKEND_DOCKERFILE="${PROJECT_ROOT}/springboot-backend/Dockerfile"
FRONTEND_DOCKERFILE="${PROJECT_ROOT}/vite-frontend/Dockerfile"
FRONTEND_ENV_DEV="${PROJECT_ROOT}/vite-frontend/.env.development"
FRONTEND_ENV_PROD="${PROJECT_ROOT}/vite-frontend/.env.production"
NGINX_CONF="${PROJECT_ROOT}/vite-frontend/nginx.conf"

# ============================================================
# 第三部分：辅助函数
# ============================================================

print_header() {
    echo -e "\n${CYAN}============================================${NC}"
    echo -e "${CYAN}  $1${NC}"
    echo -e "${CYAN}============================================${NC}"
}

print_status() {
    local label="$1"
    local expected="$2"
    local actual="$3"
    local file="$4"

    if [ "$expected" = "$actual" ]; then
        echo -e "  ${GREEN}✓${NC} ${label}: ${expected} ${GREEN}(一致)${NC}"
    else
        echo -e "  ${RED}✗${NC} ${label}: ${RED}期望=${expected}, 实际=${actual}${NC}"
        echo -e "    ${YELLOW}位置: ${file}${NC}"
    fi
}

print_synced() {
    local label="$1"
    local value="$2"
    echo -e "  ${GREEN}✓${NC} ${label}: ${value}"
}

backup_file() {
    local file="$1"
    if [ -f "$file" ]; then
        local backup="${file}.bak.$(date +%Y%m%d%H%M%S)"
        cp "$file" "$backup"
        echo -e "  ${BLUE}备份:${NC} $(basename $file) → $(basename $backup)"
    fi
}

# ============================================================
# 第四部分：检查函数
# ============================================================

check_docker_compose() {
    local compose_file="$1"
    local file_label="$2"

    if [ ! -f "$compose_file" ]; then
        echo -e "  ${YELLOW}⚠ 文件不存在: ${compose_file}${NC}"
        return
    fi

    local backend_image="bqlpfy/springboot-backend:${DOCKER_IMAGE_VERSION}"
    local frontend_image="bqlpfy/vite-frontend:${DOCKER_IMAGE_VERSION}"

    local actual_backend=$(grep -E "image: bqlpfy/springboot-backend:" "$compose_file" | head -1 | awk '{print $2}')
    local actual_frontend=$(grep -E "image: bqlpfy/vite-frontend:" "$compose_file" | head -1 | awk '{print $2}')

    echo -e "  ${BLUE}文件: ${file_label}${NC}"
    print_status "后端镜像" "${backend_image}" "${actual_backend}" "$compose_file"
    print_status "前端镜像" "${frontend_image}" "${actual_frontend}" "$compose_file"
}

check_panel_install() {
    if [ ! -f "$PANEL_INSTALL" ]; then
        echo -e "  ${YELLOW}⚠ 文件不存在: ${PANEL_INSTALL}${NC}"
        return
    fi

    local expected_url_v4="https://github.com/bqlpfy/flux-panel/releases/download/${PANEL_VERSION}/docker-compose-v4.yml"
    local expected_url_v6="https://github.com/bqlpfy/flux-panel/releases/download/${PANEL_VERSION}/docker-compose-v6.yml"
    local expected_url_sql="https://github.com/bqlpfy/flux-panel/releases/download/${PANEL_VERSION}/gost.sql"

    local actual_v4=$(grep -E "DOCKER_COMPOSEV4_URL=" "$PANEL_INSTALL" | head -1 | grep -oP 'download/\K[^/]+')
    local actual_v6=$(grep -E "DOCKER_COMPOSEV6_URL=" "$PANEL_INSTALL" | head -1 | grep -oP 'download/\K[^/]+')
    local actual_sql=$(grep -E "GOST_SQL_URL=" "$PANEL_INSTALL" | head -1 | grep -oP 'download/\K[^/]+')

    echo -e "  ${BLUE}文件: panel_install.sh${NC}"
    print_status "docker-compose-v4 URL版本" "${PANEL_VERSION}" "${actual_v4}" "$PANEL_INSTALL"
    print_status "docker-compose-v6 URL版本" "${PANEL_VERSION}" "${actual_v6}" "$PANEL_INSTALL"
    print_status "gost.sql URL版本" "${PANEL_VERSION}" "${actual_sql}" "$PANEL_INSTALL"
}

check_node_install() {
    if [ ! -f "$NODE_INSTALL" ]; then
        echo -e "  ${YELLOW}⚠ 文件不存在: ${NODE_INSTALL}${NC}"
        return
    fi

    local expected_url="https://github.com/bqlpfy/flux-panel/releases/download/${PANEL_VERSION}/gost-"

    local actual=$(grep -E "releases/download/" "$NODE_INSTALL" | head -1 | grep -oP 'download/\K[^/]+')

    echo -e "  ${BLUE}文件: install.sh${NC}"
    print_status "GOST 下载 URL 版本" "${PANEL_VERSION}" "${actual}" "$NODE_INSTALL"
}

check_frontend_site() {
    if [ ! -f "$FRONTEND_SITE" ]; then
        echo -e "  ${YELLOW}⚠ 文件不存在: ${FRONTEND_SITE}${NC}"
        return
    fi

    local actual_version=$(grep -E 'VERSION\s*=' "$FRONTEND_SITE" | grep -oP '"\K[^"]+')
    local actual_app=$(grep -E 'APP_VERSION\s*=' "$FRONTEND_SITE" | grep -oP '"\K[^"]+')

    echo -e "  ${BLUE}文件: vite-frontend/src/config/site.ts${NC}"
    print_status "面板版本 (VERSION)" "${PANEL_VERSION}" "${actual_version}" "$FRONTEND_SITE"
    print_status "应用版本 (APP_VERSION)" "${APP_VERSION}" "${actual_app}" "$FRONTEND_SITE"
}

check_gost_version() {
    if [ ! -f "$GOST_VERSION_FILE" ]; then
        echo -e "  ${YELLOW}⚠ 文件不存在: ${GOST_VERSION_FILE}${NC}"
        return
    fi

    local actual=$(grep -E 'version\s*=' "$GOST_VERSION_FILE" | grep -oP '"\K[^"]+')

    echo -e "  ${BLUE}文件: go-gost/version.go${NC}"
    print_status "GOST 核心版本" "${GOST_VERSION}" "${actual}" "$GOST_VERSION_FILE"
}

check_backend_port() {
    if [ ! -f "$BACKEND_YML" ]; then
        echo -e "  ${YELLOW}⚠ 文件不存在: ${BACKEND_YML}${NC}"
        return
    fi

    local actual=$(grep -E "^\s+port:" "$BACKEND_YML" | head -1 | awk '{print $2}')

    echo -e "  ${BLUE}文件: application.yml${NC}"
    print_status "后端端口" "${BACKEND_INTERNAL_PORT}" "${actual}" "$BACKEND_YML"
}

check_frontend_env() {
    echo -e "  ${BLUE}文件: .env.development${NC}"
    if [ -f "$FRONTEND_ENV_DEV" ]; then
        local actual=$(grep "VITE_API_BASE" "$FRONTEND_ENV_DEV" | head -1)
        local expected="VITE_API_BASE=http://127.0.0.1:${BACKEND_INTERNAL_PORT}"
        if [ "$actual" = "$expected" ]; then
            echo -e "  ${GREEN}✓${NC} 开发环境 API 地址: ${actual} ${GREEN}(一致)${NC}"
        else
            echo -e "  ${RED}✗${NC} 开发环境 API 地址: ${RED}期望=${expected}, 实际=${actual}${NC}"
        fi
    fi
}

# ============================================================
# 第五部分：同步函数
# ============================================================

sync_docker_compose() {
    local compose_file="$1"

    if [ ! -f "$compose_file" ]; then
        echo -e "  ${YELLOW}⚠ 跳过: $(basename $compose_file) 不存在${NC}"
        return
    fi

    backup_file "$compose_file"

    # 同步后端镜像版本
    sed -i "s|image: bqlpfy/springboot-backend:[0-9.]*|image: bqlpfy/springboot-backend:${DOCKER_IMAGE_VERSION}|g" "$compose_file"

    # 同步前端镜像版本
    sed -i "s|image: bqlpfy/vite-frontend:[0-9.]*|image: bqlpfy/vite-frontend:${DOCKER_IMAGE_VERSION}|g" "$compose_file"

    print_synced "$(basename $compose_file) 镜像版本" "${DOCKER_IMAGE_VERSION}"
}

sync_panel_install() {
    if [ ! -f "$PANEL_INSTALL" ]; then
        echo -e "  ${YELLOW}⚠ 跳过: panel_install.sh 不存在${NC}"
        return
    fi

    backup_file "$PANEL_INSTALL"

    # 同步下载 URL 中的版本号
    sed -i "s|releases/download/[0-9.]*/docker-compose-v4.yml|releases/download/${PANEL_VERSION}/docker-compose-v4.yml|g" "$PANEL_INSTALL"
    sed -i "s|releases/download/[0-9.]*/docker-compose-v6.yml|releases/download/${PANEL_VERSION}/docker-compose-v6.yml|g" "$PANEL_INSTALL"
    sed -i "s|releases/download/[0-9.]*/gost.sql|releases/download/${PANEL_VERSION}/gost.sql|g" "$PANEL_INSTALL"

    print_synced "panel_install.sh 下载 URL 版本" "${PANEL_VERSION}"
}

sync_node_install() {
    if [ ! -f "$NODE_INSTALL" ]; then
        echo -e "  ${YELLOW}⚠ 跳过: install.sh 不存在${NC}"
        return
    fi

    backup_file "$NODE_INSTALL"

    # 同步 GOST 下载 URL 版本号
    sed -i "s|releases/download/[0-9.]*/gost-|releases/download/${PANEL_VERSION}/gost-|g" "$NODE_INSTALL"

    print_synced "install.sh 下载 URL 版本" "${PANEL_VERSION}"
}

sync_frontend_site() {
    if [ ! -f "$FRONTEND_SITE" ]; then
        echo -e "  ${YELLOW}⚠ 跳过: site.ts 不存在${NC}"
        return
    fi

    backup_file "$FRONTEND_SITE"

    # 同步版本号
    sed -i "s|VERSION = \"[0-9.]*\"|VERSION = \"${PANEL_VERSION}\"|g" "$FRONTEND_SITE"
    sed -i "s|APP_VERSION = \"[0-9.]*\"|APP_VERSION = \"${APP_VERSION}\"|g" "$FRONTEND_SITE"

    print_synced "site.ts 面板版本" "${PANEL_VERSION}"
    print_synced "site.ts 应用版本" "${APP_VERSION}"
}

sync_gost_version() {
    if [ ! -f "$GOST_VERSION_FILE" ]; then
        echo -e "  ${YELLOW}⚠ 跳过: version.go 不存在${NC}"
        return
    fi

    backup_file "$GOST_VERSION_FILE"

    sed -i "s|version = \"[0-9.]*\"|version = \"${GOST_VERSION}\"|g" "$GOST_VERSION_FILE"

    print_synced "go-gost/version.go GOST 版本" "${GOST_VERSION}"
}

# ============================================================
# 第六部分：生成 .env.example 模板
# ============================================================

generate_env_example() {
    local env_file="${PROJECT_ROOT}/.env.example"

    cat > "$env_file" << EOF
# ============================================================
# Flux-Panel 环境变量配置模板
# ============================================================
# 复制此文件为 .env 并修改配置
# cp .env.example .env
# ============================================================

# ----- 数据库配置 -----
# MySQL 数据库名称
DB_NAME=gost
# MySQL 用户名
DB_USER=gost
# MySQL 密码（请修改为强密码）
DB_PASSWORD=your_strong_password_here

# ----- JWT 密钥 -----
# JWT 签名密钥（请修改为随机字符串）
JWT_SECRET=your_jwt_secret_here_change_this

# ----- 端口映射 -----
# 面板后端映射端口（默认 6365）
BACKEND_PORT=6365
# 面板前端映射端口（默认 80）
FRONTEND_PORT=80

# ----- 高级配置（可选） -----
# MySQL 容器名称（默认自动生成）
# DB_CONTAINER_NAME=gost-mysql
# Docker 网络名称（默认自动生成）
# NETWORK_NAME=gost-network
EOF

    echo -e "  ${GREEN}✓${NC} 已生成 .env.example"

    # 如果存在 .env，检查两者差异
    if [ -f "${PROJECT_ROOT}/.env" ]; then
        echo ""
        echo -e "  ${YELLOW}ℹ 检测到已有 .env 文件，请手动检查是否需要更新:${NC}"
        echo -e "  ${YELLOW}   diff .env.example .env${NC}"
    fi
}

# ============================================================
# 第七部分：同步状态总览
# ============================================================

status_all() {
    print_header "Flux-Panel 同步状态检查"
    echo -e "  当前定义版本: ${GREEN}${PANEL_VERSION}${NC}"
    echo -e "  GOST 核心版本: ${GREEN}${GOST_VERSION}${NC}"
    echo -e ""

    print_header "1. Docker Compose 镜像版本"
    echo -e "  ${CYAN}期望镜像标签:${NC} bqlpfy/springboot-backend:${DOCKER_IMAGE_VERSION}, bqlpfy/vite-frontend:${DOCKER_IMAGE_VERSION}"
    echo ""
    check_docker_compose "$DOCKER_COMPOSE_V4" "docker-compose-v4.yml"
    echo ""
    check_docker_compose "$DOCKER_COMPOSE_V6" "docker-compose-v6.yml"

    print_header "2. 安装脚本版本号"
    echo ""
    check_panel_install
    echo ""
    check_node_install

    print_header "3. 前端版本配置"
    echo ""
    check_frontend_site

    print_header "4. GOST 核心版本"
    echo ""
    check_gost_version

    print_header "5. 后端端口配置"
    echo ""
    check_backend_port

    print_header "6. 前端环境变量"
    echo ""
    check_frontend_env

    print_header "7. 关键依赖版本"
    echo -e "  ${BLUE}项目${NC}        | ${BLUE}当前版本${NC}"
    echo -e "  -----------------------|----------"
    echo -e "  Spring Boot            | ${SPRINGBOOT_VERSION}"
    echo -e "  Java                   | ${JAVA_VERSION}"
    echo -e "  MySQL                  | ${MYSQL_VERSION}"
    echo -e "  Node.js (构建)         | ${NODE_VERSION}"
    echo ""
}

# ============================================================
# 第八部分：执行同步
# ============================================================

sync_all() {
    print_header "Flux-Panel 配置同步"

    echo -e "${YELLOW}即将同步以下版本到所有配置文件:${NC}"
    echo -e "  面板版本: ${GREEN}${PANEL_VERSION}${NC}"
    echo -e "  GOST 版本: ${GREEN}${GOST_VERSION}${NC}"
    echo -e "  APP 版本: ${GREEN}${APP_VERSION}${NC}"
    echo ""

    # 创建备份目录
    local backup_dir="${PROJECT_ROOT}/.sync_backups"
    mkdir -p "$backup_dir"

    echo -e "${BLUE}[1/6]${NC} 同步 Docker Compose 镜像版本..."
    sync_docker_compose "$DOCKER_COMPOSE_V4"
    sync_docker_compose "$DOCKER_COMPOSE_V6"

    echo -e "${BLUE}[2/6]${NC} 同步 panel_install.sh 下载 URL..."
    sync_panel_install

    echo -e "${BLUE}[3/6]${NC} 同步 install.sh 下载 URL..."
    sync_node_install

    echo -e "${BLUE}[4/6]${NC} 同步前端 site.ts 版本号..."
    sync_frontend_site

    echo -e "${BLUE}[5/6]${NC} 同步 GOST version.go 版本号..."
    sync_gost_version

    echo ""
    print_header "同步完成"
    echo -e "  ${GREEN}所有配置已同步到版本 ${PANEL_VERSION}${NC}"
    echo -e "  ${YELLOW}备份文件保存在: ${PROJECT_ROOT}/.sync_backups/${NC}"
    echo -e "  ${YELLOW}建议运行 ./sync.sh status 验证同步结果${NC}"
}

# ============================================================
# 第九部分：更新版本号
# ============================================================

update_version() {
    local new_version="$1"

    # 验证版本号格式
    if ! [[ "$new_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo -e "${RED}错误: 版本号格式无效。请使用 X.Y.Z 格式 (例如 1.5.0)${NC}"
        exit 1
    fi

    local old_version="$PANEL_VERSION"

    echo -e "${YELLOW}将版本号从 ${old_version} 更新为 ${new_version}${NC}"
    echo -n -e "${CYAN}确认继续? (y/N): ${NC}"
    read -r confirm

    if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
        echo -e "${YELLOW}已取消${NC}"
        exit 0
    fi

    # 更新本脚本中的版本号
    sed -i "s|PANEL_VERSION=\"${old_version}\"|PANEL_VERSION=\"${new_version}\"|g" "$0"
    # 也更新 DOCKER_IMAGE_VERSION (它引用 PANEL_VERSION)
    # 这个变量是动态引用的，不需要改

    echo -e "${GREEN}✓${NC} 本脚本版本号已更新"

    # 将新版本号导出供后续使用
    export PANEL_VERSION="$new_version"
    export DOCKER_IMAGE_VERSION="$new_version"

    # 执行同步
    sync_all

    echo ""
    echo -e "${GREEN}============================================${NC}"
    echo -e "${GREEN}  版本已从 ${old_version} 升级到 ${new_version}${NC}"
    echo -e "${GREEN}  所有文件已同步完成${NC}"
    echo -e "${GREEN}============================================${NC}"
}

# ============================================================
# 第十部分：主入口
# ============================================================

show_usage() {
    echo -e "${CYAN}Flux-Panel 同步规则脚本${NC}"
    echo -e "用法:"
    echo -e "  ${GREEN}./sync.sh status${NC}        检查所有配置的同步状态"
    echo -e "  ${GREEN}./sync.sh sync${NC}          执行同步（将所有配置同步到当前版本）"
    echo -e "  ${GREEN}./sync.sh env${NC}           生成 .env.example 环境变量模板"
    echo -e "  ${GREEN}./sync.sh version X.Y.Z${NC} 将版本号更新为 X.Y.Z 并同步到所有文件"
    echo -e "  ${GREEN}./sync.sh help${NC}          显示此帮助信息"
    echo ""
    echo -e "当前版本: ${CYAN}${PANEL_VERSION}${NC}"
}

case "${1:-help}" in
    status)
        status_all
        ;;
    sync)
        sync_all
        ;;
    env)
        generate_env_example
        ;;
    version)
        if [ -z "$2" ]; then
            echo -e "${RED}错误: 请指定版本号 (例如 ./sync.sh version 1.5.0)${NC}"
            exit 1
        fi
        update_version "$2"
        ;;
    help|--help|-h)
        show_usage
        ;;
    *)
        echo -e "${RED}未知命令: $1${NC}"
        show_usage
        exit 1
        ;;
esac
