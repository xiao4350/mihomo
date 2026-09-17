#!/bin/bash

# ============================================================
# Flux Agent 管理脚本
# 支持：
#   - Debian / Ubuntu / CentOS / RHEL / Fedora
#   - Alpine Linux (OpenRC)
# ============================================================

INSTALL_DIR="/etc/flux_agent"
SERVICE_NAME="flux_agent"

# ------------------------------------------------------------
# 获取系统架构
# ------------------------------------------------------------
get_architecture() {
    ARCH=$(uname -m)

    case "$ARCH" in
        x86_64)
            echo "amd64"
            ;;
        aarch64|arm64)
            echo "arm64"
            ;;
        *)
            echo "amd64"
            ;;
    esac
}

# ------------------------------------------------------------
# 判断是否 Alpine
# ------------------------------------------------------------
is_alpine() {
    [[ -f /etc/alpine-release ]]
}

# ------------------------------------------------------------
# 构建下载地址
# ------------------------------------------------------------
build_download_url() {
    local ARCH
    ARCH=$(get_architecture)

    echo "https://github.com/bqlpfy/flux-panel/releases/download/2.0.7-beta/gost-${ARCH}"
}

DOWNLOAD_URL=$(build_download_url)

# ------------------------------------------------------------
# 中国地区使用 ghfast
# ------------------------------------------------------------
COUNTRY=$(curl -s --max-time 5 https://ipinfo.io/country 2>/dev/null)

if [ "$COUNTRY" = "CN" ]; then
    DOWNLOAD_URL="https://ghfast.top/${DOWNLOAD_URL}"
fi


# ============================================================
# 安装基础依赖
# ============================================================

install_basic_dependencies() {

    # Alpine
    if is_alpine; then

        echo "🐧 检测到 Alpine Linux"

        # Alpine 默认可能没有 bash
        if ! command -v bash >/dev/null 2>&1; then
            echo "📦 安装 bash..."
            apk add --no-cache bash
        fi

        if ! command -v curl >/dev/null 2>&1; then
            echo "📦 安装 curl..."
            apk add --no-cache curl
        fi

        return 0
    fi

    # 其他 Linux
    if ! command -v curl >/dev/null 2>&1; then

        echo "📦 未检测到 curl，尝试安装..."

        if command -v apt >/dev/null 2>&1; then
            apt update
            apt install -y curl

        elif command -v dnf >/dev/null 2>&1; then
            dnf install -y curl

        elif command -v yum >/dev/null 2>&1; then
            yum install -y curl

        fi
    fi
}


# ============================================================
# 检查并安装 tcpkill
# ============================================================

check_and_install_tcpkill() {

    if command -v tcpkill >/dev/null 2>&1; then
        return 0
    fi

    echo "📦 未检测到 tcpkill，开始安装 dsniff..."

    # --------------------------------------------------------
    # Alpine
    # --------------------------------------------------------
    if is_alpine; then
        apk add --no-cache dsniff
        return 0
    fi

    # --------------------------------------------------------
    # 检测 sudo
    # --------------------------------------------------------
    if [[ $EUID -ne 0 ]]; then
        SUDO_CMD="sudo"
    else
        SUDO_CMD=""
    fi

    # --------------------------------------------------------
    # 检测系统
    # --------------------------------------------------------
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        DISTRO=$ID
    elif [ -f /etc/redhat-release ]; then
        DISTRO="rhel"
    elif [ -f /etc/debian_version ]; then
        DISTRO="debian"
    else
        return 0
    fi

    case "$DISTRO" in

        ubuntu|debian)
            $SUDO_CMD apt update
            $SUDO_CMD apt install -y dsniff
            ;;

        centos|rhel|fedora)
            if command -v dnf >/dev/null 2>&1; then
                $SUDO_CMD dnf install -y dsniff
            elif command -v yum >/dev/null 2>&1; then
                $SUDO_CMD yum install -y dsniff
            fi
            ;;

        arch|manjaro)
            $SUDO_CMD pacman -S --noconfirm dsniff
            ;;

        opensuse*|sles)
            $SUDO_CMD zypper install -y dsniff
            ;;

        gentoo)
            $SUDO_CMD emerge --ask=n net-analyzer/dsniff
            ;;

        void)
            $SUDO_CMD xbps-install -Sy dsniff
            ;;

    esac

    return 0
}


# ============================================================
# 服务管理函数
# ============================================================

service_exists() {

    if is_alpine; then
        [[ -f "/etc/init.d/$SERVICE_NAME" ]]
    else
        systemctl list-unit-files 2>/dev/null \
            | grep -q "^${SERVICE_NAME}.service"
    fi
}


service_stop() {

    if is_alpine; then

        if rc-service "$SERVICE_NAME" status >/dev/null 2>&1; then
            echo "🛑 停止 $SERVICE_NAME..."
            rc-service "$SERVICE_NAME" stop 2>/dev/null
        fi

    else

        if systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null; then
            echo "🛑 停止 $SERVICE_NAME..."
            systemctl stop "$SERVICE_NAME" 2>/dev/null
        fi

    fi
}


service_disable() {

    if is_alpine; then

        if rc-update show default 2>/dev/null \
            | grep -q "$SERVICE_NAME"; then

            echo "🚫 禁用开机启动..."
            rc-update del "$SERVICE_NAME" default 2>/dev/null
        fi

    else

        systemctl disable "$SERVICE_NAME" 2>/dev/null
    fi
}


service_enable() {

    if is_alpine; then

        echo "🚀 设置 Alpine 开机启动..."
        rc-update add "$SERVICE_NAME" default

    else

        systemctl enable "$SERVICE_NAME"
    fi
}


service_start() {

    if is_alpine; then

        echo "▶️ 启动 $SERVICE_NAME..."
        rc-service "$SERVICE_NAME" start

    else

        systemctl start "$SERVICE_NAME"
    fi
}


service_restart() {

    if is_alpine; then

        echo "🔄 重启 $SERVICE_NAME..."
        rc-service "$SERVICE_NAME" restart

    else

        systemctl restart "$SERVICE_NAME"
    fi
}


service_is_active() {

    if is_alpine; then
        rc-service "$SERVICE_NAME" status >/dev/null 2>&1
    else
        systemctl is-active --quiet "$SERVICE_NAME"
    fi
}


# ============================================================
# 创建服务
# ============================================================

create_service() {

    # --------------------------------------------------------
    # Alpine / OpenRC
    # --------------------------------------------------------
    if is_alpine; then

        SERVICE_FILE="/etc/init.d/$SERVICE_NAME"

        echo "📄 创建 OpenRC 服务: $SERVICE_FILE"

        cat > "$SERVICE_FILE" <<EOF
#!/sbin/openrc-run

name="Flux Agent"
description="Flux_agent Proxy Service"

command="$INSTALL_DIR/flux_agent"
command_args=""
command_background=true

pidfile="/run/\$RC_SVCNAME.pid"

directory="$INSTALL_DIR"

output_log="/var/log/flux_agent.log"
error_log="/var/log/flux_agent.error.log"

depend() {
    need net
    after firewall
}

start_pre() {
    checkpath --directory --owner root:root --mode 0755 "$INSTALL_DIR"
}

EOF

        chmod +x "$SERVICE_FILE"

        return 0
    fi


    # --------------------------------------------------------
    # systemd
    # --------------------------------------------------------
    SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"

    echo "📄 创建 systemd 服务: $SERVICE_FILE"

    cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Flux_agent Proxy Service
After=network.target

[Service]
WorkingDirectory=$INSTALL_DIR
ExecStart=$INSTALL_DIR/flux_agent
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
}


# ============================================================
# 获取配置参数
# ============================================================

get_config_params() {

    if [[ -z "$SERVER_ADDR" || -z "$SECRET" ]]; then

        echo "请输入配置参数："

        if [[ -z "$SERVER_ADDR" ]]; then
            read -p "服务器地址: " SERVER_ADDR
        fi

        if [[ -z "$SECRET" ]]; then
            read -p "密钥: " SECRET
        fi

        if [[ -z "$SERVER_ADDR" || -z "$SECRET" ]]; then
            echo "❌ 参数不完整，操作取消。"
            exit 1
        fi
    fi
}


# ============================================================
# 解析命令行参数
# ============================================================

while getopts "a:s:" opt; do

    case $opt in

        a)
            SERVER_ADDR="$OPTARG"
            ;;

        s)
            SECRET="$OPTARG"
            ;;

        *)
            echo "❌ 无效参数"
            exit 1
            ;;

    esac

done


# ============================================================
# 显示菜单
# ============================================================

show_menu() {

    echo "==============================================="
    echo "              Flux Agent 管理脚本"
    echo "==============================================="
    echo "请选择操作："
    echo "1. 安装"
    echo "2. 更新"
    echo "3. 卸载"
    echo "4. 退出"
    echo "==============================================="
}


# ============================================================
# 安装
# ============================================================

install_flux_agent() {

    echo "🚀 开始安装 flux_agent..."

    get_config_params

    install_basic_dependencies

    check_and_install_tcpkill

    mkdir -p "$INSTALL_DIR"


    # --------------------------------------------------------
    # 停止旧服务
    # --------------------------------------------------------

    if service_exists; then

        echo "🔍 检测到已存在的 $SERVICE_NAME 服务"

        service_stop
        service_disable

    fi


    # --------------------------------------------------------
    # 删除旧程序
    # --------------------------------------------------------

    if [[ -f "$INSTALL_DIR/flux_agent" ]]; then

        echo "🧹 删除旧文件 flux_agent"

        rm -f "$INSTALL_DIR/flux_agent"

    fi


    # --------------------------------------------------------
    # 下载
    # --------------------------------------------------------

    echo "⬇️ 下载 flux_agent 中..."

    echo "📥 下载地址: $DOWNLOAD_URL"

    curl -L --fail --retry 3 \
        "$DOWNLOAD_URL" \
        -o "$INSTALL_DIR/flux_agent"

    if [[ ! -f "$INSTALL_DIR/flux_agent" ||
          ! -s "$INSTALL_DIR/flux_agent" ]]; then

        echo "❌ 下载失败，请检查网络或下载链接。"
        exit 1

    fi

    chmod +x "$INSTALL_DIR/flux_agent"

    echo "✅ 下载完成"


    # --------------------------------------------------------
    # 检查程序是否能执行
    # --------------------------------------------------------

    echo "🔎 flux_agent 版本："

    if ! "$INSTALL_DIR/flux_agent" -V; then
        echo "❌ flux_agent 无法执行"
        exit 1
    fi


    # --------------------------------------------------------
    # config.json
    # --------------------------------------------------------

    CONFIG_FILE="$INSTALL_DIR/config.json"

    echo "📄 创建新配置: config.json"

    cat > "$CONFIG_FILE" <<EOF
{
  "addr": "$SERVER_ADDR",
  "secret": "$SECRET"
}
EOF


    # --------------------------------------------------------
    # gost.json
    # --------------------------------------------------------

    GOST_CONFIG="$INSTALL_DIR/gost.json"

    if [[ -f "$GOST_CONFIG" ]]; then

        echo "⏭️ 跳过配置文件: gost.json (已存在)"

    else

        echo "📄 创建新配置: gost.json"

        cat > "$GOST_CONFIG" <<EOF
{}
EOF

    fi


    chmod 600 "$INSTALL_DIR"/*.json


    # --------------------------------------------------------
    # 创建服务
    # --------------------------------------------------------

    create_service


    # --------------------------------------------------------
    # 启动
    # --------------------------------------------------------

    service_enable
    service_start


    # --------------------------------------------------------
    # 检查状态
    # --------------------------------------------------------

    echo "🔄 检查服务状态..."

    if service_is_active; then

        echo "✅ 安装完成"

        if is_alpine; then
            echo "🐧 系统: Alpine Linux"
            echo "🔧 服务: OpenRC"
        else
            echo "🔧 服务: systemd"
        fi

        echo "📁 配置目录: $INSTALL_DIR"
        echo "🔧 服务状态: 运行中"

    else

        echo "❌ flux_agent 服务启动失败"

        if is_alpine; then
            echo "请执行："
            echo "rc-service flux_agent status"
            echo "tail -f /var/log/flux_agent.log"
            echo "tail -f /var/log/flux_agent.error.log"
        else
            echo "请执行："
            echo "journalctl -u flux_agent -f"
        fi

    fi
}


# ============================================================
# 更新
# ============================================================

update_flux_agent() {

    echo "🔄 开始更新 flux_agent..."


    if [[ ! -d "$INSTALL_DIR" ]]; then

        echo "❌ flux_agent 未安装，请先选择安装。"

        return 1

    fi


    install_basic_dependencies

    check_and_install_tcpkill


    echo "📥 使用下载地址: $DOWNLOAD_URL"


    # --------------------------------------------------------
    # 下载新版本
    # --------------------------------------------------------

    echo "⬇️ 下载最新版本..."

    curl -L --fail --retry 3 \
        "$DOWNLOAD_URL" \
        -o "$INSTALL_DIR/flux_agent.new"


    if [[ ! -f "$INSTALL_DIR/flux_agent.new" ||
          ! -s "$INSTALL_DIR/flux_agent.new" ]]; then

        echo "❌ 下载失败。"

        rm -f "$INSTALL_DIR/flux_agent.new"

        return 1

    fi


    # --------------------------------------------------------
    # 停止
    # --------------------------------------------------------

    service_stop


    # --------------------------------------------------------
    # 替换
    # --------------------------------------------------------

    mv "$INSTALL_DIR/flux_agent.new" \
       "$INSTALL_DIR/flux_agent"

    chmod +x "$INSTALL_DIR/flux_agent"


    # --------------------------------------------------------
    # 版本
    # --------------------------------------------------------

    echo "🔎 新版本："

    "$INSTALL_DIR/flux_agent" -V


    # --------------------------------------------------------
    # 启动
    # --------------------------------------------------------

    echo "🔄 重启服务..."

    service_start


    if service_is_active; then
        echo "✅ 更新完成，服务已重新启动。"
    else
        echo "❌ 更新完成，但服务启动失败。"

        if is_alpine; then
            echo "rc-service flux_agent status"
            echo "tail -f /var/log/flux_agent.error.log"
        else
            echo "journalctl -u flux_agent -f"
        fi
    fi
}


# ============================================================
# 卸载
# ============================================================

uninstall_flux_agent() {

    echo "🗑️ 开始卸载 flux_agent..."

    read -p \
        "确认卸载 flux_agent 吗？此操作将删除所有相关文件 (y/N): " \
        confirm


    if [[ "$confirm" != "y" &&
          "$confirm" != "Y" ]]; then

        echo "❌ 取消卸载"

        return 0

    fi


    # --------------------------------------------------------
    # 停止服务
    # --------------------------------------------------------

    if service_exists; then

        echo "🛑 停止服务..."

        service_stop

        echo "🚫 禁用开机启动..."

        service_disable

    fi


    # --------------------------------------------------------
    # 删除服务
    # --------------------------------------------------------

    if is_alpine; then

        SERVICE_FILE="/etc/init.d/$SERVICE_NAME"

    else

        SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"

    fi


    if [[ -f "$SERVICE_FILE" ]]; then

        rm -f "$SERVICE_FILE"

        echo "🧹 删除服务文件: $SERVICE_FILE"

    fi


    # --------------------------------------------------------
    # 删除安装目录
    # --------------------------------------------------------

    if [[ -d "$INSTALL_DIR" ]]; then

        rm -rf "$INSTALL_DIR"

        echo "🧹 删除安装目录: $INSTALL_DIR"

    fi


    # --------------------------------------------------------
    # systemd 重载
    # --------------------------------------------------------

    if ! is_alpine; then
        systemctl daemon-reload
    fi


    echo "✅ 卸载完成"
}


# ============================================================
# 删除脚本自身
# ============================================================

delete_self() {

    echo ""
    echo "🗑️ 操作已完成，正在清理脚本文件..."

    SCRIPT_PATH="$(
        readlink -f "$0" 2>/dev/null ||
        realpath "$0" 2>/dev/null ||
        echo "$0"
    )"

    sleep 1

    rm -f "$SCRIPT_PATH" &&
        echo "✅ 脚本文件已删除" ||
        echo "❌ 脚本文件删除失败"
}


# ============================================================
# 主逻辑
# ============================================================

main() {

    # --------------------------------------------------------
    # 命令行参数安装
    # --------------------------------------------------------

    if [[ -n "$SERVER_ADDR" &&
          -n "$SECRET" ]]; then

        install_flux_agent

        delete_self

        exit 0

    fi


    # --------------------------------------------------------
    # 交互菜单
    # --------------------------------------------------------

    while true; do

        show_menu

        read -p "请输入选项 (1-4): " choice

        case "$choice" in

            1)

                install_flux_agent

                delete_self

                exit 0

                ;;

            2)

                update_flux_agent

                delete_self

                exit 0

                ;;

            3)

                uninstall_flux_agent

                delete_self

                exit 0

                ;;

            4)

                echo "👋 退出脚本"

                delete_self

                exit 0

                ;;

            *)

                echo "❌ 无效选项，请输入 1-4"

                echo ""

                ;;

        esac

    done
}


# ============================================================
# 执行
# ============================================================

main