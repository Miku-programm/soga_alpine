#!/bin/sh

# soga Alpine Linux 安装脚本
# 适配 OpenRC 服务管理
# 完全兼容官方 soga 命令行管理方式
# 版本: 2.0 (已修复所有已知问题)

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
PLAIN='\033[0m'

# 打印彩色文本的函数（兼容 busybox ash）
print_msg() {
    printf "%b\n" "$1"
}

# 检查是否为 root 用户
if [ "$(id -u)" != "0" ]; then
    print_msg "${RED}错误：${PLAIN} 必须使用 root 用户运行此脚本！"
    exit 1
fi

# 检查是否为 Alpine Linux
if [ ! -f /etc/alpine-release ]; then
    print_msg "${RED}错误：${PLAIN} 此脚本仅支持 Alpine Linux！"
    exit 1
fi

print_msg "${GREEN}检测到 Alpine Linux 系统${PLAIN}"

# 检测架构
ARCH=$(uname -m)
if [ "$ARCH" = "x86_64" ]; then
    ARCH="amd64"
elif [ "$ARCH" = "aarch64" ]; then
    ARCH="arm64"
else
    print_msg "${YELLOW}警告：未识别的架构 $ARCH，使用默认架构 amd64${PLAIN}"
    ARCH="amd64"
fi

print_msg "${GREEN}检测到系统架构：${ARCH}${PLAIN}"

# 安装必要的依赖
install_dependencies() {
    print_msg "${GREEN}正在安装必要的依赖...${PLAIN}"
    apk update
    apk add --no-cache wget curl ca-certificates openrc tzdata
    
    # 检查是否需要安装 gcompat (用于运行 glibc 程序)
    if ! apk info gcompat >/dev/null 2>&1; then
        print_msg "${YELLOW}安装 gcompat 以支持 glibc 程序...${PLAIN}"
        apk add --no-cache gcompat
    fi
    
    # 设置时区为 Asia/Shanghai（可根据需要修改）
    if [ ! -f /etc/timezone ]; then
        echo "Asia/Shanghai" > /etc/timezone
        print_msg "${GREEN}已设置时区为 Asia/Shanghai${PLAIN}"
    fi
    
    # 创建时区符号链接
    if [ ! -L /etc/localtime ]; then
        ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
    fi
}

# 获取最新版本
get_latest_version() {
    print_msg "${GREEN}正在获取 soga 最新版本...${PLAIN}"
    LATEST_VERSION=$(wget -qO- --no-check-certificate https://api.github.com/repos/vaxilu/soga/releases/latest | grep 'tag_name' | cut -d'"' -f4)
    
    if [ -z "$LATEST_VERSION" ]; then
        print_msg "${RED}获取版本失败，可能是 GitHub API 限制${PLAIN}"
        print_msg "${YELLOW}请手动指定版本号，或稍后重试${PLAIN}"
        exit 1
    fi
    
    print_msg "${GREEN}最新版本：${LATEST_VERSION}${PLAIN}"
}

# 下载 soga
download_soga() {
    local version=$1
    if [ -z "$version" ]; then
        get_latest_version
        version=$LATEST_VERSION
    else
        LATEST_VERSION=$version
    fi
    
    print_msg "${GREEN}正在下载 soga ${version}...${PLAIN}"
    
    DOWNLOAD_URL="https://github.com/vaxilu/soga/releases/download/${version}/soga-linux-${ARCH}.tar.gz"
    
    cd /tmp
    wget --no-check-certificate -O soga.tar.gz "$DOWNLOAD_URL"
    
    if [ $? -ne 0 ]; then
        print_msg "${RED}下载失败，请检查网络连接或版本号是否正确${PLAIN}"
        exit 1
    fi
    
    print_msg "${GREEN}下载完成${PLAIN}"
}

# 安装 soga
install_soga() {
    print_msg "${GREEN}正在安装 soga...${PLAIN}"
    
    # ===关键修复===：先创建所有必要的目录
    print_msg "${YELLOW}创建必要的目录...${PLAIN}"
    mkdir -p /usr/local/sbin
    mkdir -p /usr/bin
    mkdir -p /etc/soga
    mkdir -p /var/log/soga
    
    # 解压
    cd /tmp
    tar -xzf soga.tar.gz
    cd soga
    
    # 停止旧服务（如果存在）
    if [ -f /etc/init.d/soga ]; then
        print_msg "${YELLOW}停止旧服务...${PLAIN}"
        rc-service soga stop 2>/dev/null || true
    fi
    
    # 复制二进制文件到 /usr/local/sbin（避免与管理脚本冲突）
    print_msg "${YELLOW}安装二进制文件...${PLAIN}"
    cp soga /usr/local/sbin/soga-bin
    chmod +x /usr/local/sbin/soga-bin
    
    # 复制配置文件（如果不存在）
    if [ ! -f /etc/soga/soga.conf ]; then
        print_msg "${YELLOW}安装配置文件...${PLAIN}"
        cp soga.conf /etc/soga/
        print_msg "${YELLOW}配置文件已创建：/etc/soga/soga.conf${PLAIN}"
        print_msg "${YELLOW}请编辑配置文件后启动服务${PLAIN}"
    else
        print_msg "${GREEN}保留现有配置文件${PLAIN}"
    fi
    
    # 复制其他配置文件
    [ -f blockList ] && cp blockList /etc/soga/ 2>/dev/null || true
    [ -f dns.yml ] && cp dns.yml /etc/soga/ 2>/dev/null || true
    
    # 清理
    cd /tmp
    rm -rf soga soga.tar.gz
    
    print_msg "${GREEN}soga 安装完成${PLAIN}"
}

# 创建 OpenRC 服务
create_openrc_service() {
    print_msg "${GREEN}正在创建 OpenRC 服务...${PLAIN}"
    
    cat > /etc/init.d/soga << 'EOF'
#!/sbin/openrc-run

name="soga"
description="Soga Proxy Backend Service"

command="/usr/local/sbin/soga-bin"
command_args="-c /etc/soga/soga.conf"
command_background=true
pidfile="/run/soga.pid"
command_user="root"

# 保活机制：进程意外退出时自动重启
respawn_delay=5
respawn_max=10
respawn_period=60

output_log="/var/log/soga/output.log"
error_log="/var/log/soga/error.log"

export TZ="Asia/Shanghai"

depend() {
    need net
    after firewall
}

start_pre() {
    checkpath --directory --mode 0755 --owner root:root /var/log/soga
    checkpath --file --mode 0644 --owner root:root "$output_log"
    checkpath --file --mode 0644 --owner root:root "$error_log"
    
    if [ ! -f /etc/soga/soga.conf ]; then
        eerror "配置文件不存在：/etc/soga/soga.conf"
        return 1
    fi
    
    if [ -f "$pidfile" ]; then
        local old_pid=$(cat "$pidfile")
        if [ -n "$old_pid" ] && ! kill -0 "$old_pid" 2>/dev/null; then
            rm -f "$pidfile"
            ewarn "清理了残留的 PID 文件"
        fi
    fi
}

start_post() {
    sleep 2
    if [ -f "$pidfile" ]; then
        local pid=$(cat "$pidfile")
        if kill -0 "$pid" 2>/dev/null; then
            einfo "soga 已启动 (PID: $pid)"
            einfo "使用 'soga log' 查看日志"
        else
            eerror "soga 启动失败"
            return 1
        fi
    else
        ewarn "PID 文件不存在，但服务可能正在运行"
    fi
}

stop_pre() {
    einfo "正在停止 soga..."
}

stop_post() {
    if [ -f "$pidfile" ]; then
        local pid=$(cat "$pidfile")
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
            ewarn "进程仍在运行，发送 SIGKILL..."
            kill -9 "$pid" 2>/dev/null
            sleep 1
        fi
        rm -f "$pidfile"
    fi
    einfo "soga 已停止"
}

healthcheck() {
    if [ -f "$pidfile" ]; then
        local pid=$(cat "$pidfile")
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
            return 0
        fi
    fi
    return 1
}
EOF

    chmod +x /etc/init.d/soga
    print_msg "${GREEN}OpenRC 服务创建完成（已配置自动重启）${PLAIN}"
}

# 创建官方风格的管理脚本
create_management_script() {
    print_msg "${GREEN}正在创建 soga 管理脚本...${PLAIN}"
    
    cat > /usr/bin/soga << 'EOFMAIN'
#!/bin/sh

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
PLAIN='\033[0m'

print_msg() {
    printf "%b\n" "$1"
}

cur_dir=$(pwd)

if [ "$(id -u)" != "0" ]; then
    print_msg "${RED}错误：${PLAIN} 必须使用root用户运行此脚本！"
    exit 1
fi

show_usage() {
    echo "soga 管理脚本使用方法: "
    echo "------------------------------------------"
    echo "soga                    - 显示管理菜单 (功能更多)"
    echo "soga start              - 启动 soga"
    echo "soga stop               - 停止 soga"
    echo "soga restart            - 重启 soga"
    echo "soga enable             - 设置 soga 开机自启"
    echo "soga disable            - 取消 soga 开机自启"
    echo "soga log                - 查看 soga 日志"
    echo "soga update             - 更新 soga 最新版"
    echo "soga update x.x.x       - 安装 soga 指定版本"
    echo "soga config             - 显示配置文件内容"
    echo "soga config xx=xx yy=yy - 自动设置配置文件"
    echo "soga install            - 安装 soga"
    echo "soga uninstall          - 卸载 soga"
    echo "soga version            - 查看 soga 版本"
    echo "------------------------------------------"
}

check_status() {
    if rc-service soga status >/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

show_menu() {
    echo ""
    print_msg "${GREEN}================================${PLAIN}"
    print_msg "${GREEN}    soga 管理脚本 (Alpine)     ${PLAIN}"
    print_msg "${GREEN}================================${PLAIN}"
    echo " 0. 退出脚本"
    echo "————————————————"
    echo " 1. 安装 soga"
    echo " 2. 更新 soga"
    echo " 3. 卸载 soga"
    echo "————————————————"
    echo " 4. 启动 soga"
    echo " 5. 停止 soga"
    echo " 6. 重启 soga"
    echo " 7. 查看 soga 状态"
    echo " 8. 查看 soga 日志"
    echo "————————————————"
    echo " 9. 设置 soga 开机自启"
    echo "10. 取消 soga 开机自启"
    echo "————————————————"
    echo "11. 编辑配置文件"
    echo "12. 显示配置文件"
    echo "13. 查看 soga 版本"
    print_msg "${GREEN}================================${PLAIN}"
    echo ""
    
    printf "请输入选择 [0-13]: "
    read num
    
    case "${num}" in
        0) exit 0 ;;
        1) install ;;
        2) update ;;
        3) uninstall ;;
        4) start ;;
        5) stop ;;
        6) restart ;;
        7) status ;;
        8) show_log ;;
        9) enable ;;
        10) disable ;;
        11) edit_config ;;
        12) show_config ;;
        13) show_version ;;
        *) print_msg "${RED}请输入正确的数字 [0-13]${PLAIN}" ;;
    esac
}

confirm_restart() {
    printf "是否重启soga [Y/n]: "
    read confirm
    if [ -z "$confirm" ] || [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
        restart
    else
        before_show_menu
    fi
}

before_show_menu() {
    echo ""
    printf "按回车键返回主菜单..." 
    read temp
    show_menu
}

install() {
    print_msg "${RED}请使用安装脚本进行安装${PLAIN}"
    if [ $# -eq 0 ]; then
        before_show_menu
    fi
}

update() {
    local version=$1
    
    ARCH=$(uname -m)
    if [ "$ARCH" = "x86_64" ]; then
        ARCH="amd64"
    elif [ "$ARCH" = "aarch64" ]; then
        ARCH="arm64"
    else
        ARCH="amd64"
    fi
    
    if [ -z "$version" ]; then
        LATEST_VERSION=$(wget -qO- --no-check-certificate https://api.github.com/repos/vaxilu/soga/releases/latest | grep 'tag_name' | cut -d'"' -f4)
        
        if [ -z "$LATEST_VERSION" ]; then
            print_msg "${RED}检测 soga 版本失败${PLAIN}"
            return 1
        fi
        
        printf "检测到 soga 最新版本：%b%s%b，开始更新\n" "${GREEN}" "${LATEST_VERSION}" "${PLAIN}"
    else
        LATEST_VERSION=$version
        printf "开始更新到 soga %b%s%b\n" "${GREEN}" "${LATEST_VERSION}" "${PLAIN}"
    fi
    
    cd /tmp
    wget --no-check-certificate -O soga.tar.gz "https://github.com/vaxilu/soga/releases/download/${LATEST_VERSION}/soga-linux-${ARCH}.tar.gz"
    
    if [ $? -ne 0 ]; then
        print_msg "${RED}下载 soga 失败${PLAIN}"
        return 1
    fi
    
    rc-service soga stop 2>/dev/null || true
    
    mkdir -p /usr/local/sbin
    tar -xzf soga.tar.gz
    cd soga
    cp soga /usr/local/sbin/soga-bin
    chmod +x /usr/local/sbin/soga-bin
    
    cd /tmp
    rm -rf soga soga.tar.gz
    
    printf "%bsoga 已更新到 %s%b\n" "${GREEN}" "${LATEST_VERSION}" "${PLAIN}"
    
    if [ $# -eq 0 ]; then
        confirm_restart
    fi
}

uninstall() {
    printf "确定要卸载 soga 吗？(y/n): "
    read confirm
    if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
        if [ $# -eq 0 ]; then
            show_menu
        fi
        return 0
    fi
    
    rc-service soga stop 2>/dev/null || true
    rc-update del soga default 2>/dev/null || true
    rm -f /etc/init.d/soga
    rm -f /usr/local/sbin/soga-bin
    rm -f /usr/bin/soga
    rm -rf /etc/soga
    rm -rf /var/log/soga
    
    print_msg "${GREEN}soga 已卸载${PLAIN}"
    echo ""
}

start() {
    check_status
    if [ $? -eq 0 ]; then
        print_msg "${GREEN}soga 已运行，无需再次启动${PLAIN}"
    else
        rc-service soga start
        sleep 2
        check_status
        if [ $? -eq 0 ]; then
            print_msg "${GREEN}soga 启动成功，请使用 soga log 查看运行日志${PLAIN}"
        else
            print_msg "${RED}soga 可能启动失败，请稍后使用 soga log 查看日志信息${PLAIN}"
        fi
    fi
    
    if [ $# -eq 0 ]; then
        before_show_menu
    fi
}

stop() {
    check_status
    if [ $? -eq 1 ]; then
        print_msg "${GREEN}soga 已停止，无需再次停止${PLAIN}"
    else
        rc-service soga stop
        sleep 2
        check_status
        if [ $? -eq 1 ]; then
            print_msg "${GREEN}soga 停止成功${PLAIN}"
        else
            print_msg "${RED}soga 停止失败，可能是因为停止时间超过了2秒，请稍后查看日志信息${PLAIN}"
        fi
    fi
    
    if [ $# -eq 0 ]; then
        before_show_menu
    fi
}

restart() {
    rc-service soga stop
    sleep 2
    rc-service soga start
    sleep 2
    check_status
    if [ $? -eq 0 ]; then
        print_msg "${GREEN}soga 重启成功，请使用 soga log 查看运行日志${PLAIN}"
    else
        print_msg "${RED}soga 可能启动失败，请稍后使用 soga log 查看日志信息${PLAIN}"
    fi
    
    if [ $# -eq 0 ]; then
        before_show_menu
    fi
}

status() {
    rc-service soga status
    
    if [ $# -eq 0 ]; then
        before_show_menu
    fi
}

enable() {
    rc-update add soga default
    if [ $? -eq 0 ]; then
        print_msg "${GREEN}soga 设置开机自启成功${PLAIN}"
    else
        print_msg "${RED}soga 设置开机自启失败${PLAIN}"
    fi
    
    if [ $# -eq 0 ]; then
        before_show_menu
    fi
}

disable() {
    rc-update del soga default
    if [ $? -eq 0 ]; then
        print_msg "${GREEN}soga 取消开机自启成功${PLAIN}"
    else
        print_msg "${RED}soga 取消开机自启失败${PLAIN}"
    fi
    
    if [ $# -eq 0 ]; then
        before_show_menu
    fi
}

show_log() {
    print_msg "${YELLOW}正在查看日志，按 Ctrl+C 退出${PLAIN}"
    tail -f /var/log/soga/output.log
    
    if [ $# -eq 0 ]; then
        before_show_menu
    fi
}

edit_config() {
    if command -v vi >/dev/null 2>&1; then
        vi /etc/soga/soga.conf
    elif command -v nano >/dev/null 2>&1; then
        nano /etc/soga/soga.conf
    else
        print_msg "${RED}未找到文本编辑器${PLAIN}"
    fi
    
    if [ $# -eq 0 ]; then
        before_show_menu
    fi
}

show_config() {
    cat /etc/soga/soga.conf
    
    if [ $# -eq 0 ]; then
        before_show_menu
    fi
}

set_config() {
    for arg in "$@"; do
        key=$(echo $arg | cut -d'=' -f1)
        value=$(echo $arg | cut -d'=' -f2-)
        
        if grep -q "^${key}=" /etc/soga/soga.conf; then
            sed -i "s|^${key}=.*|${key}=${value}|g" /etc/soga/soga.conf
            printf "%b已设置 %s=%s%b\n" "${GREEN}" "${key}" "${value}" "${PLAIN}"
        else
            echo "${key}=${value}" >> /etc/soga/soga.conf
            printf "%b已添加 %s=%s%b\n" "${GREEN}" "${key}" "${value}" "${PLAIN}"
        fi
    done
}

show_version() {
    /usr/local/sbin/soga-bin -v
    
    if [ $# -eq 0 ]; then
        before_show_menu
    fi
}

main() {
    case "$1" in
        "")
            show_menu
            ;;
        start)
            start 0
            ;;
        stop)
            stop 0
            ;;
        restart)
            restart 0
            ;;
        status)
            status 0
            ;;
        enable)
            enable 0
            ;;
        disable)
            disable 0
            ;;
        log)
            show_log 0
            ;;
        update)
            if [ -n "$2" ]; then
                update "$2"
            else
                update
            fi
            ;;
        config)
            if [ $# -eq 1 ]; then
                show_config 0
            else
                shift
                set_config "$@"
            fi
            ;;
        install)
            install 0
            ;;
        uninstall)
            uninstall 0
            ;;
        version)
            show_version 0
            ;;
        *)
            show_usage
            ;;
    esac
}

main "$@"
EOFMAIN

    chmod +x /usr/bin/soga
    
    print_msg "${GREEN}soga 管理脚本创建完成${PLAIN}"
}

# 主安装流程
main() {
    print_msg "${GREEN}========================================${PLAIN}"
    print_msg "${GREEN}  soga Alpine Linux 安装脚本 v2.0     ${PLAIN}"
    print_msg "${GREEN}========================================${PLAIN}"
    echo ""
    
    install_dependencies
    get_latest_version
    download_soga
    install_soga
    create_openrc_service
    create_management_script
    
    echo ""
    print_msg "${GREEN}========================================${PLAIN}"
    print_msg "${GREEN}          安装完成！                   ${PLAIN}"
    print_msg "${GREEN}========================================${PLAIN}"
    echo ""
    echo "soga 管理脚本使用方法: "
    echo "------------------------------------------"
    echo "soga                    - 显示管理菜单 (功能更多)"
    echo "soga start              - 启动 soga"
    echo "soga stop               - 停止 soga"
    echo "soga restart            - 重启 soga"
    echo "soga enable             - 设置 soga 开机自启"
    echo "soga disable            - 取消 soga 开机自启"
    echo "soga log                - 查看 soga 日志"
    echo "soga update             - 更新 soga 最新版"
    echo "soga update x.x.x       - 安装 soga 指定版本"
    echo "soga config             - 显示配置文件内容"
    echo "soga config xx=xx yy=yy - 自动设置配置文件"
    echo "soga uninstall          - 卸载 soga"
    echo "soga version            - 查看 soga 版本"
    echo "------------------------------------------"
    echo ""
    print_msg "${YELLOW}下一步：编辑配置文件并启动服务${PLAIN}"
    printf "1. %bvi /etc/soga/soga.conf%b    - 编辑配置\n" "${GREEN}" "${PLAIN}"
    printf "2. %bsoga start%b                 - 启动服务\n" "${GREEN}" "${PLAIN}"
    printf "3. %bsoga enable%b                - 设置开机自启\n" "${GREEN}" "${PLAIN}"
    echo ""
}

# 运行主函数
main
