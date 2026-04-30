#!/usr/bin/env bash
# ==============================================================================
#  clash-manager.sh — mihomo 代理管理脚本
#  系统：OpenCloudOS 9 / RHEL系 x86_64
#  内核：mihomo (Clash Meta)
# ==============================================================================

set -euo pipefail

# ── 配置 ──────────────────────────────────────────────────────────────────────
CONFIG_DIR="/etc/mihomo"
CONFIG_FILE="$CONFIG_DIR/config.yaml"
URL_FILE="$CONFIG_DIR/.subscription_url"
BINARY="/usr/local/bin/mihomo"
SERVICE="mihomo"
SERVICE_FILE="/etc/systemd/system/${SERVICE}.service"
LOG_FILE="/var/log/mihomo.log"

# ── 颜色 ──────────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

# ── 工具函数 ──────────────────────────────────────────────────────────────────
info()    { echo -e "  ${CYAN}▸${RESET} $*"; }
success() { echo -e "  ${GREEN}✓${RESET} $*"; }
warn()    { echo -e "  ${YELLOW}!${RESET} $*"; }
error()   { echo -e "  ${RED}✗${RESET} $*"; }
die()     { error "$*"; exit 1; }

require_root() {
    [[ $EUID -eq 0 ]] || die "需要 root 权限，请用 sudo bash $0"
}

service_status() {
    if ! systemctl list-unit-files 2>/dev/null | grep -q "^${SERVICE}\.service"; then
        echo "not-installed"
    else
        systemctl is-active "$SERVICE" 2>/dev/null || echo "inactive"
    fi
}

# ── 状态面板 ──────────────────────────────────────────────────────────────────
show_status() {
    clear
    echo ""
    echo -e "${BOLD}┌─────────────────────────────────────────────┐${RESET}"
    echo -e "${BOLD}│           mihomo 代理管理器                  │${RESET}"
    echo -e "${BOLD}└─────────────────────────────────────────────┘${RESET}"
    echo ""

    # mihomo 版本
    if [[ -x "$BINARY" ]]; then
        local ver
        ver=$("$BINARY" -v 2>/dev/null | awk '{print $2}' | head -1)
        success "mihomo 已安装  ${DIM}v${ver}${RESET}"
    else
        error "mihomo 未安装  ${DIM}(${BINARY})${RESET}"
    fi

    # 服务状态
    local status
    status=$(service_status)
    case "$status" in
        active)
            success "服务状态：${GREEN}运行中${RESET}"
            # 显示 PID
            local pid
            pid=$(systemctl show -p MainPID "$SERVICE" 2>/dev/null | cut -d= -f2)
            [[ -n "$pid" && "$pid" != "0" ]] && info "进程 PID：$pid"
            ;;
        inactive)
            warn "服务状态：${YELLOW}已停止${RESET}"
            ;;
        not-installed)
            warn "服务状态：${DIM}未配置 systemd${RESET}"
            ;;
    esac

    # 订阅 URL
    if [[ -f "$URL_FILE" ]]; then
        local url
        url=$(cat "$URL_FILE")
        local short
        short="${url:0:55}"
        [[ ${#url} -gt 55 ]] && short="${short}..."
        info "订阅链接：${DIM}${short}${RESET}"
    else
        warn "订阅链接：${DIM}未设置${RESET}"
    fi

    # 配置文件 & 更新时间
    if [[ -f "$CONFIG_FILE" ]]; then
        local mtime
        mtime=$(stat -c '%y' "$CONFIG_FILE" | cut -d'.' -f1)
        success "配置文件：${DIM}更新于 ${mtime}${RESET}"
    else
        warn "配置文件：${DIM}不存在${RESET}"
    fi

    # 代理端口
    if [[ -f "$CONFIG_FILE" ]]; then
        local http_port socks_port mixed_port
        http_port=$(grep -E '^port:' "$CONFIG_FILE" 2>/dev/null | awk '{print $2}' | head -1 || true)
        socks_port=$(grep -E '^socks-port:' "$CONFIG_FILE" 2>/dev/null | awk '{print $2}' | head -1 || true)
        mixed_port=$(grep -E '^mixed-port:' "$CONFIG_FILE" 2>/dev/null | awk '{print $2}' | head -1 || true)
        [[ -n "$mixed_port" ]] && info "Mixed 端口：${BOLD}127.0.0.1:${mixed_port}${RESET}  ${DIM}(http+socks5)${RESET}"
        [[ -n "$http_port" ]]  && info "HTTP  端口：127.0.0.1:${http_port}"
        [[ -n "$socks_port" ]] && info "SOCKS 端口：127.0.0.1:${socks_port}"
    fi

    # bashrc 代理状态
    if grep -q "mihomo proxy begin" "$HOME/.bashrc" 2>/dev/null; then
        success "系统代理：${GREEN}已写入 ~/.bashrc${RESET}"
    else
        warn "系统代理：${DIM}未写入 ~/.bashrc${RESET}"
    fi

    echo ""
    echo -e "${DIM}──────────────────────────────────────────────${RESET}"
    echo ""
}

# ── 创建 systemd 服务 ─────────────────────────────────────────────────────────
setup_systemd() {
    cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=mihomo Clash Meta Proxy Daemon
Documentation=https://wiki.metacubex.one
After=network.target NetworkManager.service

[Service]
Type=simple
ExecStart=${BINARY} -d ${CONFIG_DIR}
ExecReload=/bin/kill -HUP \$MAINPID
Restart=on-failure
RestartSec=5
LimitNOFILE=1048576
StandardOutput=append:${LOG_FILE}
StandardError=append:${LOG_FILE}

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable "$SERVICE" &>/dev/null
    success "systemd 服务已创建 → $SERVICE_FILE"
}

# ── bashrc 代理标记 ───────────────────────────────────────────────────────────
BASHRC_MARK_BEGIN="# >>> mihomo proxy begin <<<"
BASHRC_MARK_END="# >>> mihomo proxy end <<<"
BASHRC="$HOME/.bashrc"

get_proxy_port() {
    local mixed_port http_port
    mixed_port=$(grep -E '^mixed-port:' "$CONFIG_FILE" 2>/dev/null | awk '{print $2}' | head -1 || true)
    http_port=$(grep -E '^port:' "$CONFIG_FILE" 2>/dev/null | awk '{print $2}' | head -1 || true)
    echo "${mixed_port:-$http_port}"
}

write_proxy_to_bashrc() {
    local port="$1"
    remove_proxy_from_bashrc  # 防止重复写入
    cat >> "$BASHRC" <<EOF

${BASHRC_MARK_BEGIN}
export http_proxy=http://127.0.0.1:${port}
export https_proxy=http://127.0.0.1:${port}
export all_proxy=socks5://127.0.0.1:${port}
${BASHRC_MARK_END}
EOF
    success "代理环境变量已写入 ~/.bashrc"
}

remove_proxy_from_bashrc() {
    if grep -q "$BASHRC_MARK_BEGIN" "$BASHRC" 2>/dev/null; then
        sed -i "/${BASHRC_MARK_BEGIN}/,/${BASHRC_MARK_END}/d" "$BASHRC"
        success "已从 ~/.bashrc 移除代理环境变量"
    fi
}

# ── 开启 ──────────────────────────────────────────────────────────────────────
start_mihomo() {
    require_root

    [[ -x "$BINARY" ]] || die "mihomo 未安装，请先确认 $BINARY 存在"
    [[ -f "$CONFIG_FILE" ]] || die "配置文件不存在，请先选 [3] 更新订阅"

    if [[ $(service_status) == "not-installed" ]]; then
        info "首次启动，正在创建 systemd 守护进程..."
        setup_systemd
    fi

    if [[ $(service_status) == "active" ]]; then
        warn "mihomo 已经在运行中"
        return
    fi

    systemctl start "$SERVICE"

    # 等待最多 10 秒，检测日志中出现 "listening" 作为真正启动成功的信号
    info "正在启动，稍候..."
    local i=0
    while [[ $i -lt 10 ]]; do
        sleep 1
        i=$((i + 1))
        # 优先检查日志里是否出现监听端口（最可靠的成功信号）
        if grep -q "proxy listening at" "$LOG_FILE" 2>/dev/null; then
            break
        fi
    done

    # 判断：systemd active 或日志中有 listening 均视为成功
    local is_active is_listening
    is_active=$(service_status)
    is_listening=$(grep -c "proxy listening at" "$LOG_FILE" 2>/dev/null || echo "0")

    if [[ "$is_active" == "active" ]] || [[ "$is_listening" -gt 0 ]]; then
        success "mihomo 启动成功！"
        # 显示监听端口
        local listen_line
        listen_line=$(grep "proxy listening at" "$LOG_FILE" 2>/dev/null | tail -1 || true)
        if [[ -n "$listen_line" ]]; then
            local addr
            addr=$(echo "$listen_line" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:[0-9]+' | head -1)
            [[ -n "$addr" ]] && info "代理地址：${addr}  ${DIM}(http+socks5)${RESET}"
        fi
        info "节点健康检测在后台进行，属正常现象"
        # 写入 bashrc 并提示 source
        local port
        port=$(get_proxy_port)
        if [[ -n "$port" ]]; then
            write_proxy_to_bashrc "$port"
            echo ""
            warn "新终端窗口自动生效；当前窗口请执行："
            echo -e "  ${BOLD}source ~/.bashrc${RESET}"
        fi
    else
        error "启动失败，最近日志："
        echo ""
        tail -20 "$LOG_FILE" 2>/dev/null || journalctl -u "$SERVICE" -n 20 --no-pager
    fi
}

# ── 关闭 ──────────────────────────────────────────────────────────────────────
stop_mihomo() {
    require_root

    if [[ $(service_status) != "active" ]]; then
        warn "mihomo 当前未在运行"
        return
    fi

    systemctl stop "$SERVICE"
    success "mihomo 已停止"
    remove_proxy_from_bashrc
    echo ""
    warn "当前终端窗口请执行以立即取消代理："
    echo -e "  ${BOLD}source ~/.bashrc${RESET}"
}

# ── 更新订阅 ──────────────────────────────────────────────────────────────────
update_subscription() {
    require_root
    mkdir -p "$CONFIG_DIR"

    local url=""

    if [[ -f "$URL_FILE" ]]; then
        url=$(cat "$URL_FILE")
        echo ""
        info "当前订阅链接："
        echo -e "  ${DIM}${url}${RESET}"
        echo ""
        read -rp "  按 Enter 继续使用，或粘贴新链接：" input
        [[ -n "$input" ]] && url="$input"
    else
        echo ""
        read -rp "  请粘贴 Clash 订阅链接：" url
        [[ -z "$url" ]] && die "链接不能为空"
    fi

    # 保存 URL
    echo "$url" > "$URL_FILE"
    chmod 600 "$URL_FILE"

    info "正在下载配置文件..."
    echo ""

    local tmp_config
    tmp_config=$(mktemp)

    if curl -sSL --connect-timeout 15 --max-time 60 \
        -A "ClashMeta" \
        -o "$tmp_config" "$url"; then

        # 简单验证是否是 yaml
        if grep -qE '^(proxies|proxy-groups|rules|port|mixed-port):' "$tmp_config" 2>/dev/null; then
            mv "$tmp_config" "$CONFIG_FILE"
            chmod 600 "$CONFIG_FILE"
            success "配置文件已更新 → $CONFIG_FILE"

            # 如果服务在运行则重启
            if [[ $(service_status) == "active" ]]; then
                info "正在重启服务以应用新配置..."
                systemctl restart "$SERVICE"
                sleep 1
                [[ $(service_status) == "active" ]] && success "服务重启成功" || error "重启失败，请检查日志"
            fi
        else
            rm -f "$tmp_config"
            die "下载内容不像有效的 Clash 配置，请检查订阅链接"
        fi
    else
        rm -f "$tmp_config"
        die "下载失败，请检查链接是否有效或网络是否正常"
    fi
}

# ── 查看日志 ──────────────────────────────────────────────────────────────────
show_logs() {
    echo ""
    info "最近 50 行日志（按 q 退出）："
    echo ""
    if [[ -f "$LOG_FILE" ]]; then
        tail -50 "$LOG_FILE" | less -R
    else
        journalctl -u "$SERVICE" -n 50 --no-pager 2>/dev/null \
            || warn "暂无日志（服务未曾启动过）"
    fi
}

# ── 主菜单 ────────────────────────────────────────────────────────────────────
main() {
    while true; do
        show_status

        echo -e "  ${BOLD}请选择操作：${RESET}"
        echo ""
        echo -e "  ${GREEN}1${RESET}) 开启 mihomo  ${DIM}(启动服务 + 写入代理到 ~/.bashrc)${RESET}"
        echo -e "  ${RED}2${RESET}) 关闭 mihomo  ${DIM}(停止服务 + 清除 ~/.bashrc 代理)${RESET}"
        echo -e "  ${CYAN}3${RESET}) 更新订阅链接"
        echo -e "  ${YELLOW}4${RESET}) 查看运行日志"
        echo -e "  ${DIM}0) 退出${RESET}"
        echo ""
        read -rp "  输入选项 [0-4]：" choice
        echo ""

        case "$choice" in
            1) start_mihomo ;;
            2) stop_mihomo ;;
            3) update_subscription ;;
            4) show_logs ;;
            0) info "再见！"; echo ""; exit 0 ;;
            *) warn "无效选项" ;;
        esac

        echo ""
        read -rp "  按 Enter 返回菜单..." _
    done
}

main
