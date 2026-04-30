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
    sleep 1

    if [[ $(service_status) == "active" ]]; then
        success "mihomo 启动成功！"
        # 显示端口提示
        local mixed_port
        mixed_port=$(grep -E '^mixed-port:' "$CONFIG_FILE" 2>/dev/null | awk '{print $2}' | head -1 || true)
        [[ -n "$mixed_port" ]] && info "代理地址：127.0.0.1:${mixed_port}"
    else
        error "启动失败，查看日志："
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

# ── 设置系统代理环境变量 ───────────────────────────────────────────────────────
set_proxy_env() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        warn "配置文件不存在，无法读取端口"
        return
    fi

    local mixed_port http_port
    mixed_port=$(grep -E '^mixed-port:' "$CONFIG_FILE" 2>/dev/null | awk '{print $2}' | head -1 || true)
    http_port=$(grep -E '^port:' "$CONFIG_FILE" 2>/dev/null | awk '{print $2}' | head -1 || true)

    local port="${mixed_port:-$http_port}"
    [[ -z "$port" ]] && die "无法从配置文件读取端口号"

    echo ""
    success "复制以下命令到终端执行（让当前 shell 走代理）："
    echo ""
    echo -e "  ${BOLD}export http_proxy=http://127.0.0.1:${port}${RESET}"
    echo -e "  ${BOLD}export https_proxy=http://127.0.0.1:${port}${RESET}"
    echo -e "  ${BOLD}export all_proxy=socks5://127.0.0.1:${port}${RESET}"
    echo ""
    info "取消代理："
    echo -e "  ${BOLD}unset http_proxy https_proxy all_proxy${RESET}"
    echo ""
    info "永久写入 ~/.bashrc："
    echo -e "  ${DIM}echo 'export http_proxy=http://127.0.0.1:${port}' >> ~/.bashrc${RESET}"
}

# ── 主菜单 ────────────────────────────────────────────────────────────────────
main() {
    while true; do
        show_status

        echo -e "  ${BOLD}请选择操作：${RESET}"
        echo ""
        echo -e "  ${GREEN}1${RESET}) 开启 mihomo"
        echo -e "  ${RED}2${RESET}) 关闭 mihomo"
        echo -e "  ${CYAN}3${RESET}) 更新订阅链接"
        echo -e "  ${YELLOW}4${RESET}) 查看运行日志"
        echo -e "  ${YELLOW}5${RESET}) 显示代理环境变量"
        echo -e "  ${DIM}0) 退出${RESET}"
        echo ""
        read -rp "  输入选项 [0-5]：" choice
        echo ""

        case "$choice" in
            1) start_mihomo ;;
            2) stop_mihomo ;;
            3) update_subscription ;;
            4) show_logs ;;
            5) set_proxy_env ;;
            0) info "再见！"; echo ""; exit 0 ;;
            *) warn "无效选项" ;;
        esac

        echo ""
        read -rp "  按 Enter 返回菜单..." _
    done
}

main