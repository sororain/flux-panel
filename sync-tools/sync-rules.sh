#!/bin/bash
# ============================================================
# Flux-Panel 转发规则外部同步脚本
# ============================================================
# 功能：通过调用面板 API，将所有转发规则重新同步到 gost 节点
# 适用场景：更换服务器、节点重连后规则未自动同步
# 
# 使用方式：
#   ./sync-rules.sh                                 # 交互式输入
#   ./sync-rules.sh -c config.json                  # 从 JSON 配置文件读取 (Linux/Windows 通用)
#   ./sync-rules.sh -u URL -T TOKEN                 # 直接使用 token（无需账号密码）
#   ./sync-rules.sh -u URL -U admin -P password     # 使用账号密码登录
#   ./sync-rules.sh --dry-run                       # 试运行，只检查不同步
#   ./sync-rules.sh --new-config                    # 生成 JSON 配置模板
#
# 可配合定时任务 (crontab)：
#   0 */6 * * * /path/to/sync-rules.sh -c /path/to/config.json
# ============================================================

set -e

# ============================================================
# 默认配置
# ============================================================
PANEL_URL=""
USERNAME=""
PASSWORD=""
TOKEN=""
DRY_RUN=false
VERBOSE=false
TIMEOUT=30
API_PREFIX="/api/v1"

# ============================================================
# 颜色定义
# ============================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# ============================================================
# 辅助函数
# ============================================================

print_banner() {
    echo -e "${CYAN}"
    echo "============================================"
    echo "   Flux-Panel 转发规则同步脚本"
    echo "============================================"
    echo -e "${NC}"
}

log_info()  { echo -e "${BLUE}[INFO]${NC}  $1"; }
log_ok()    { echo -e "${GREEN}[OK]${NC}    $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $1"; }
log_err()   { echo -e "${RED}[ERROR]${NC} $1"; }
log_verbose() { $VERBOSE && echo -e "  ${CYAN}[DEBUG]${NC} $1"; }

show_usage() {
    echo "用法: $0 [选项]"
    echo ""
    echo "选项:"
    echo "  -u <URL>          面板地址 (例如: https://panel.example.com)"
    echo "  -T <token>        直接指定 API Token（与账号密码二选一）"
    echo "  -U <username>     管理员用户名（与 Token 二选一）"
    echo "  -P <password>     管理员密码"
    echo "  -c <config>       配置文件路径 (支持 .json 或 .conf)"
    echo "  -t <seconds>      HTTP 请求超时时间 (默认: 30s)"
    echo "  --dry-run         试运行模式，只展示将同步的规则不同步"
    echo "  --new-config      生成 JSON 配置文件模板"
    echo "  --verbose         输出详细日志"
    echo "  -h, --help        显示帮助"
    echo ""
    echo "配置文件格式 (JSON，Linux/Windows 通用):"
    echo '  {'
    echo '    "url": "https://panel.example.com",'
    echo '    "token": "your_token_here"'
    echo '  }'
    echo ""
    echo "示例:"
    echo "  $0 -u https://192.168.1.100:6365 -T eyJxxx..."
    echo "  $0 -u https://192.168.1.100:6365 -U admin_user -P admin_user"
    echo "  $0 -c /etc/gost/sync.json"
    echo "  $0 --dry-run -u https://panel.example.com -T eyJxxx..."
    exit 0
}

# ============================================================
# 解析命令行参数
# ============================================================

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -u|--url)
                PANEL_URL="$2"
                shift 2
                ;;
            -T|--token)
                TOKEN="$2"
                shift 2
                ;;
            -U|--username)
                USERNAME="$2"
                shift 2
                ;;
            -P|--password)
                PASSWORD="$2"
                shift 2
                ;;
            -c|--config)
                CONFIG_FILE="$2"
                if [ ! -f "$CONFIG_FILE" ]; then
                    log_err "配置文件不存在: $CONFIG_FILE"
                    exit 1
                fi
                load_json_config "$CONFIG_FILE"
                shift 2
                ;;
            -t|--timeout)
                TIMEOUT="$2"
                shift 2
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --new-config)
                ACTION="new-config"
                shift
                ;;
            --verbose)
                VERBOSE=true
                shift
                ;;
            -h|--help)
                show_usage
                ;;
            *)
                log_err "未知参数: $1"
                show_usage
                ;;
        esac
    done
}

# ============================================================
# JSON 配置文件加载
# ============================================================

load_json_config() {
    local json_file="$1"
    log_info "加载 JSON 配置: $json_file"

    if ! command -v python3 &> /dev/null && ! command -v python &> /dev/null; then
        log_err "解析 JSON 需要 python3，请先安装"
        exit 1
    fi

    local py_cmd="python3"
    if ! command -v python3 &> /dev/null; then
        py_cmd="python"
    fi

    # 检查 JSON 是否有效
    if ! $py_cmd -c "import json; json.load(open('$json_file'))" 2>/dev/null; then
        log_err "JSON 格式无效: $json_file"
        exit 1
    fi

    # 读取字段（仅当命令行未指定时使用配置文件的值）
    if [ -z "$PANEL_URL" ]; then
        PANEL_URL=$($py_cmd -c "import json; print(json.load(open('$json_file')).get('url', '') or '')" 2>/dev/null)
    fi
    if [ -z "$TOKEN" ]; then
        TOKEN=$($py_cmd -c "import json; print(json.load(open('$json_file')).get('token', '') or '')" 2>/dev/null)
    fi
    if [ -z "$USERNAME" ]; then
        USERNAME=$($py_cmd -c "import json; print(json.load(open('$json_file')).get('username', '') or '')" 2>/dev/null)
    fi
    if [ -z "$PASSWORD" ]; then
        PASSWORD=$($py_cmd -c "import json; print(json.load(open('$json_file')).get('password', '') or '')" 2>/dev/null)
    fi

    log_info "JSON 配置加载完成"
}

# ============================================================
# API 请求封装
# ============================================================

# 发送 API 请求
# 参数: $1 = 路径, $2 = POST 数据 (JSON 字符串), $3 = 是否需要认证
api_request() {
    local path="$1"
    local data="$2"
    local url="${PANEL_URL}${API_PREFIX}${path}"
    
    local headers=("-H" "Content-Type: application/json")
    
    if [ "$3" != "noauth" ]; then
        headers+=("-H" "Authorization: ${TOKEN}")
    fi
    
    log_verbose "请求: POST ${url}"
    log_verbose "数据: ${data}"
    
    local result
    if [ -n "$data" ]; then
        result=$(curl -s -m "$TIMEOUT" -X POST "${headers[@]}" -d "$data" "$url" 2>&1)
    else
        result=$(curl -s -m "$TIMEOUT" -X POST "${headers[@]}" "$url" 2>&1)
    fi
    
    local curl_exit=$?
    if [ $curl_exit -ne 0 ]; then
        log_err "请求失败: $url (curl退出码: $curl_exit)"
        return 1
    fi
    
    echo "$result"
}

# 解析 JSON 字段
# 参数: $1 = JSON 字符串, $2 = 字段路径 (如 .data 或 .data.token)
parse_json() {
    echo "$1" | python3 -c "import sys,json; d=json.load(sys.stdin); print($2)" 2>/dev/null || \
    echo "$1" | python -c "import sys,json; d=json.load(sys.stdin); print($2)" 2>/dev/null || {
        log_err "JSON 解析失败 (需要安装 python3)"
        return 1
    }
}

# ============================================================
# 登录面板
# ============================================================

login() {
    # 如果已有 Token，跳过登录
    if [ -n "$TOKEN" ]; then
        log_info "使用已有 Token 进行认证"
        log_verbose "Token: ${TOKEN:0:20}..."
        return 0
    fi

    log_info "正在登录面板: ${PANEL_URL}"
    
    local login_data="{\"username\":\"${USERNAME}\",\"password\":\"${PASSWORD}\"}"
    local response
    response=$(api_request "/user/login" "$login_data" "noauth") || return 1
    
    local code
    code=$(parse_json "$response" "d.get('code', -1)")
    
    if [ "$code" != "0" ]; then
        local msg
        msg=$(parse_json "$response" "d.get('msg', '未知错误')")
        log_err "登录失败: ${msg}"
        return 1
    fi
    
    TOKEN=$(parse_json "$response" "d['data'].get('token', '')")
    
    if [ -z "$TOKEN" ]; then
        log_err "登录成功但未获取到 Token"
        return 1
    fi
    
    local name
    name=$(parse_json "$response" "d['data'].get('name', '')")
    log_ok "登录成功，用户: ${name}"
    return 0
}

# ============================================================
# 获取转发列表
# ============================================================

get_forwards() {
    log_info "正在获取转发规则列表..."
    
    local response
    response=$(api_request "/forward/list" "") || return 1
    
    local code
    code=$(parse_json "$response" "d.get('code', -1)")
    
    if [ "$code" != "0" ]; then
        local msg
        msg=$(parse_json "$response" "d.get('msg', '未知错误')")
        log_err "获取转发列表失败: ${msg}"
        return 1
    fi
    
    # 提取数据
    echo "$response"
}

# ============================================================
# 同步转发规则
# ============================================================

sync_forwards() {
    local response="$1"
    
    # 提取转发规则列表
    local forwards_json
    forwards_json=$(echo "$response" | python3 -c "
import sys, json
d = json.load(sys.stdin)
data = d.get('data', [])
if not isinstance(data, list):
    data = []
# 只同步已启用的转发 (status=1)
for f in data:
    if f.get('status') == 1:
        print(json.dumps(f))
" 2>/dev/null) || {
        # 尝试 python
        forwards_json=$(echo "$response" | python -c "
import sys, json
d = json.load(sys.stdin)
data = d.get('data', [])
if not isinstance(data, list):
    data = []
for f in data:
    if f.get('status') == 1:
        print(json.dumps(f))
" 2>/dev/null)
    }
    
    if [ -z "$forwards_json" ]; then
        log_warn "没有需要同步的活跃转发规则"
        return 0
    fi
    
    # 统计
    local total=0
    local success=0
    local fail=0
    
    # 逐条处理转发规则
    while IFS= read -r forward; do
        [ -z "$forward" ] && continue
        total=$((total + 1))
        
        local id name tunnel_id remote_addr strategy in_port interface_name user_id
        
        id=$(echo "$forward" | python3 -c "import sys,json; print(json.load(sys.stdin).get('id',''))" 2>/dev/null)
        name=$(echo "$forward" | python3 -c "import sys,json; print(json.load(sys.stdin).get('name',''))" 2>/dev/null)
        tunnel_id=$(echo "$forward" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tunnelId',''))" 2>/dev/null)
        remote_addr=$(echo "$forward" | python3 -c "import sys,json; print(json.load(sys.stdin).get('remoteAddr',''))" 2>/dev/null)
        strategy=$(echo "$forward" | python3 -c "import sys,json; print(json.load(sys.stdin).get('strategy','fifo'))" 2>/dev/null)
        in_port=$(echo "$forward" | python3 -c "import sys,json; print(json.load(sys.stdin).get('inPort','null'))" 2>/dev/null)
        interface_name=$(echo "$forward" | python3 -c "import sys,json; s=json.load(sys.stdin).get('interfaceName'); print(s if s else '')" 2>/dev/null)
        user_id=$(echo "$forward" | python3 -c "import sys,json; print(json.load(sys.stdin).get('userId',''))" 2>/dev/null)
        
        log_info "[${total}] 正在同步: ${name} (ID: ${id})"
        
        if $DRY_RUN; then
            echo -e "       ☐ 隧道: ${tunnel_id}, 端口: ${in_port}, 目标: ${remote_addr}"
            echo -e "       ${YELLOW}(试运行，跳过实际同步)${NC}"
            continue
        fi
        
        # 构建更新请求数据
        local update_data="{\"id\":${id},\"userId\":${user_id},\"name\":\"${name}\",\"tunnelId\":${tunnel_id},\"remoteAddr\":\"${remote_addr}\""
        
        if [ "$strategy" != "null" ] && [ -n "$strategy" ]; then
            update_data="${update_data},\"strategy\":\"${strategy}\""
        fi
        if [ "$in_port" != "null" ] && [ -n "$in_port" ]; then
            update_data="${update_data},\"inPort\":${in_port}"
        fi
        if [ -n "$interface_name" ]; then
            update_data="${update_data},\"interfaceName\":\"${interface_name}\""
        fi
        update_data="${update_data}}"
        
        log_verbose "更新数据: ${update_data}"
        
        # 调用更新 API 触发同步
        local update_response
        update_response=$(api_request "/forward/update" "$update_data") || {
            log_err "  请求失败: ${name}"
            fail=$((fail + 1))
            continue
        }
        
        local update_code
        update_code=$(parse_json "$update_response" "d.get('code', -1)")
        
        if [ "$update_code" = "0" ]; then
            log_ok "  同步成功: ${name}"
            success=$((success + 1))
        else
            local update_msg
            update_msg=$(parse_json "$update_response" "d.get('msg', '未知错误')")
            log_err "  同步失败: ${name} - ${update_msg}"
            fail=$((fail + 1))
        fi
        
        # 稍微延迟，避免请求过快
        sleep 0.5
        
    done <<< "$forwards_json"
    
    # 输出汇总
    echo ""
    echo -e "${CYAN}--------------------------------------------${NC}"
    echo -e "  同步完成: 总计 ${total}, 成功 ${GREEN}${success}${NC}, 失败 ${RED}${fail}${NC}"
    echo -e "${CYAN}--------------------------------------------${NC}"
    
    if [ $fail -gt 0 ]; then
        return 1
    fi
    return 0
}

# ============================================================
# 节点状态检查
# ============================================================

check_nodes() {
    log_info "正在检查节点状态..."
    
    local response
    response=$(api_request "/node/list" "") || return 1
    
    local code
    code=$(parse_json "$response" "d.get('code', -1)")
    
    if [ "$code" != "0" ]; then
        log_warn "获取节点列表失败，跳过节点检查"
        return 0
    fi
    
    local nodes_info
    nodes_info=$(echo "$response" | python3 -c "
import sys, json
d = json.load(sys.stdin)
nodes = d.get('data', [])
if not isinstance(nodes, list):
    nodes = []
online = [n.get('name','?') for n in nodes if n.get('status') == 1]
offline = [n.get('name','?') for n in nodes if n.get('status') != 1]
print(json.dumps({'online': online, 'offline': offline, 'total': len(nodes)}))
" 2>/dev/null)
    
    local total_online
    total_online=$(echo "$nodes_info" | python3 -c "import sys,json; d=json.load(sys.stdin); print(len(d['online']))" 2>/dev/null)
    local total_offline
    total_offline=$(echo "$nodes_info" | python3 -c "import sys,json; d=json.load(sys.stdin); print(len(d['offline']))" 2>/dev/null)
    local total_all
    total_all=$(echo "$nodes_info" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['total'])" 2>/dev/null)
    
    echo -e "  节点总数: ${total_all}"
    echo -e "  ${GREEN}在线节点: ${total_online}${NC}"
    echo -e "  ${RED}离线节点: ${total_offline}${NC}"
    echo ""
    
    if [ "$total_online" = "0" ] && [ "$total_all" != "0" ]; then
        log_warn "所有节点均离线，同步可能不会生效"
        return 0
    fi
}

# ============================================================
# 交互式输入
# ============================================================

interactive_input() {
    if [ -z "$PANEL_URL" ]; then
        echo -n "请输入面板地址 (例如: https://panel.example.com): "
        read -r PANEL_URL
    fi
    
    # 如果没有 Token 且没有账号密码，才提示输入
    if [ -z "$TOKEN" ] && [ -z "$USERNAME" ]; then
        echo ""
        echo "请选择认证方式:"
        echo "  1. 使用 Token（已有面板 Token）"
        echo "  2. 使用账号密码登录"
        echo -n "请选择 (1/2, 默认 2): "
        read -r auth_mode
        
        if [ "$auth_mode" = "1" ]; then
            echo -n "请输入 API Token: "
            read -rs TOKEN
            echo ""
        else
            if [ -z "$USERNAME" ]; then
                echo -n "请输入管理员用户名 (默认: admin_user): "
                read -r USERNAME
                USERNAME="${USERNAME:-admin_user}"
            fi
            if [ -z "$PASSWORD" ]; then
                echo -n "请输入管理员密码: "
                read -rs PASSWORD
                echo ""
            fi
        fi
    elif [ -z "$TOKEN" ] && [ -z "$PASSWORD" ]; then
        # 有用户名但没有密码，提示输入密码
        if [ -z "$PASSWORD" ]; then
            echo -n "请输入管理员密码: "
            read -rs PASSWORD
            echo ""
        fi
    fi
    
    # 去除末尾斜杠
    PANEL_URL="${PANEL_URL%/}"
}

# ============================================================
# 环境检查
# ============================================================

check_environment() {
    local has_error=false
    
    if ! command -v curl &> /dev/null; then
        log_err "需要 curl，请先安装"
        has_error=true
    fi
    
    if ! command -v python3 &> /dev/null && ! command -v python &> /dev/null; then
        log_err "需要 python3，请先安装"
        has_error=true
    fi
    
    if [ -z "$PANEL_URL" ]; then
        log_err "面板地址未指定"
        has_error=true
    fi
    
    if [ -z "$TOKEN" ] && ( [ -z "$USERNAME" ] || [ -z "$PASSWORD" ] ); then
        log_err "认证信息不完整，请提供 Token 或用户名+密码"
        has_error=true
    fi
    
    if $has_error; then
        exit 1
    fi
}

# ============================================================
# 生成 JSON 配置模板
# ============================================================

generate_json_config() {
    local config_file="${1:-sync-config.json}"
    cat > "$config_file" << 'EOF'
{
    "url": "https://your-panel-domain.com",
    "token": "your_token_here"
}
EOF
    log_ok "JSON 配置模板已生成: $config_file"
    echo ""
    echo "请编辑 $config_file 填入实际信息，然后运行:"
    echo "  $0 -c $config_file"
}

# ============================================================
# 主流程
# ============================================================

main() {
    print_banner

    # 处理 --new-config
    if [ "$ACTION" = "new-config" ]; then
        generate_json_config
        return
    fi

    # 交互式输入（如果没有通过参数指定）
    interactive_input
    
    # 检查环境
    check_environment
    
    log_info "面板地址: ${PANEL_URL}"
    log_info "超时设置: ${TIMEOUT}s"
    $DRY_RUN && log_info "${YELLOW}试运行模式: 仅检查不同步${NC}"
    $VERBOSE && log_info "详细日志: 已开启"
    echo ""
    
    # 1. 登录
    login || exit 1
    echo ""
    
    # 2. 检查节点状态
    check_nodes
    echo ""
    
    # 3. 获取转发列表
    local forwards_response
    forwards_response=$(get_forwards) || exit 1
    echo ""
    
    # 4. 同步转发规则
    sync_forwards "$forwards_response"
    local sync_result=$?
    
    echo ""
    if [ $sync_result -eq 0 ]; then
        log_ok "全部同步完成！"
    else
        log_warn "部分同步失败，请检查日志"
    fi
}

# ============================================================
# 入口
# ============================================================

parse_args "$@"
main
