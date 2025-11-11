#!/bin/sh

# soga Alpine Linux 安装脚本
# 适配 OpenRC 服务管理
# 完全兼容官方 soga 命令行管理方式

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
PLAIN='\033[0m'

# 检查是否为 root 用户
if [ "$(id -u)" != "0" ]; then
    echo -e "${RED}错误：${PLAIN} 必须使用 root 用户运行此脚本！"
    exit 1
fi

# 检查是否为 Alpine Linux
if [ ! -f /etc/alpine-release ]; then
    echo -e "${RED}错误：${PLAIN} 此脚本仅支持 Alpine Linux！"
    exit 1
fi

echo -e "${GREEN}检测到 Alpine Linux 系统${PLAIN}"

# 检测架构
ARCH=$(uname -m)
if [ "$ARCH" = "x86_64" ]; then
    ARCH="amd64"
elif [ "$ARCH" = "aarch64" ]; then
    ARCH="arm64"
else
    echo -e "${YELLOW}警告：未识别的架构 $ARCH，使用默认架构 amd64${PLAIN}"
    ARCH="amd64"
fi

echo -e "${GREEN}检测到系统架构：${ARCH}${PLAIN}"

# 安装必要的依赖
install_dependencies() {
    echo -e "${GREEN}正在安装必要的依赖...${PLAIN}"
    apk update
    apk add --no-cache wget curl ca-certificates openrc jq
    
    # 检查是否需要安装 gcompat (用于运行 glibc 程序)
    if ! apk info gcompat >/dev/null 2>&1; then
        echo -e "${YELLOW}安装 gcompat 以支持 glibc 程序...${PLAIN}"
        apk add --no-cache gcompat
    fi
}

# 获取最新版本
get_latest_version() {
    echo -e "${GREEN}正在获取 soga 最新版本...${PLAIN}"
    LATEST_VERSION=$(wget -qO- --no-check-certificate https://api.github.com/repos/vaxilu/soga/releases/latest | grep 'tag_name' | cut -d'"' -f4)
    
    if [ -z "$LATEST_VERSION" ]; then
        echo -e "${RED}获取版本失败，可能是 GitHub API 限制${PLAIN}"
        echo -e "${YELLOW}请手动指定版本号，或稍后重试${PLAIN}"
        exit 1
    fi
    
    echo -e "${GREEN}最新版本：${LATEST_VERSION}${PLAIN}"
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
    
    echo -e "${GREEN}正在下载 soga ${version}...${PLAIN}"
    
    DOWNLOAD_URL="https://github.com/vaxilu/soga/releases/download/${version}/soga-linux-${ARCH}.tar.gz"
    
    cd /tmp
    wget --no-check-certificate -O soga.tar.gz "$DOWNLOAD_URL"
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}下载失败，请检查网络连接或版本号是否正确${PLAIN}"
        exit 1
    fi
    
    echo -e "${GREEN}下载完成${PLAIN}"
}

# 安装 soga
install_soga() {
    echo -e "${GREEN}正在安装 soga...${PLAIN}"
    
    # 解压
    cd /tmp
    tar -xzf soga.tar.gz
    cd soga
    
    # 停止旧服务（如果存在）
    if [ -f /etc/init.d/soga ]; then
        rc-service soga stop 2>/dev/null || true
    fi
    
    # 复制二进制文件
    cp soga /usr/local/bin/
    chmod +x /usr/local/bin/soga
    
    # 创建配置目录
    mkdir -p /etc/soga
    
    # 复制配置文件（如果不存在）
    if [ ! -f /etc/soga/soga.conf ]; then
        cp soga.conf /etc/soga/
        echo -e "${YELLOW}配置文件已创建：/etc/soga/soga.conf${PLAIN}"
        echo -e "${YELLOW}请编辑配置文件后启动服务${PLAIN}"
    else
        echo -e "${GREEN}保留现有配置文件${PLAIN}"
    fi
    
    # 复制其他配置文件
    [ -f blockList ] && cp blockList /etc/soga/ 2>/dev/null || true
    [ -f dns.yml ] && cp dns.yml /etc/soga/ 2>/dev/null || true
    
    # 创建日志目录
    mkdir -p /var/log/soga
    
    # 清理
    cd /tmp
    rm -rf soga soga.tar.gz
    
    echo -e "${GREEN}soga 安装完成${PLAIN}"
}

# 创建 OpenRC 服务
create_openrc_service() {
    echo -e "${GREEN}正在创建 OpenRC 服务...${PLAIN}"
    
    cat > /etc/init.d/soga << 'EOF'
#!/sbin/openrc-run

name="soga"
description="Soga Proxy Backend Service"

command="/usr/local/bin/soga"
command_args="-c /etc/soga/soga.conf"
command_background=true
pidfile="/run/soga.pid"
command_user="root"

output_log="/var/log/soga/output.log"
error_log="/var/log/soga/error.log"

depend() {
    need net
    after firewall
}

start_pre() {
    checkpath --directory --mode 0755 --owner root:root /var/log/soga
    checkpath --file --mode 0644 --owner root:root "$output_log"
    checkpath --file --mode 0644 --owner root:root "$error_log"
    
    # 检查配置文件是否存在
    if [ ! -f /etc/soga/soga.conf ]; then
        eerror "配置文件不存在：/etc/soga/soga.conf"
        return 1
    fi
}

start_post() {
    einfo "soga 已启动"
    einfo "使用 'soga log' 查看日志"
}

stop_post() {
    einfo "soga 已停止"
}
EOF

    chmod +x /etc/init.d/soga
    
    echo -e "${GREEN}OpenRC 服务创建完成${PLAIN}"
}

# 创建官方风格的管理脚本
create_management_script() {
    echo -e "${GREEN}正在创建 soga 管理脚本...${PLAIN}"
    
    cat > /usr/bin/soga << 'EOF'
#!/bin/sh

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
PLAIN='\033[0m'

cur_dir=$(pwd)

# 检查 root 权限
[[ $EUID -ne 0 ]] && echo -e "${RED}错误：${PLAIN} 必须使用root用户运行此脚本！\n" && exit 1

# 显示使用帮助
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

# 检查状态
check_status() {
    if rc-service soga status >/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

# 显示菜单
show_menu() {
    echo ""
    echo -e "${GREEN}================================${PLAIN}"
    echo -e "${GREEN}    soga 管理脚本 (Alpine)     ${PLAIN}"
    echo -e "${GREEN}================================${PLAIN}"
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
    echo -e "${GREEN}================================${PLAIN}"
    echo ""
    
    read -p "请输入选择 [0-13]: " num
    
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
        *) echo -e "${RED}请输入正确的数字 [0-13]${PLAIN}" ;;
    esac
}

# 确认重启
confirm_restart() {
    read -p "是否重启soga [Y/n]: " confirm
    if [ -z "$confirm" ] || [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
        restart
    else
        before_show_menu
    fi
}

# 返回主菜单前等待
before_show_menu() {
    echo ""
    read -p "按回车键返回主菜单..." 
    show_menu
}

# 安装
install() {
    bash <(wget -qO- --no-check-certificate https://raw.githubusercontent.com/vaxilu/soga/master/install.sh)
    if [ $? -eq 0 ]; then
        if [ $# -eq 0 ]; then
            start
        else
            start 0
        fi
    fi
}

# 更新
update() {
    local version=$1
    
    # 检测架构
    ARCH=$(uname -m)
    if [ "$ARCH" = "x86_64" ]; then
        ARCH="amd64"
    elif [ "$ARCH" = "aarch64" ]; then
        ARCH="arm64"
    else
        ARCH="amd64"
    fi
    
    if [ -z "$version" ]; then
        # 获取最新版本
        LATEST_VERSION=$(wget -qO- --no-check-certificate https://api.github.com/repos/vaxilu/soga/releases/latest | grep 'tag_name' | cut -d'"' -f4)
        
        if [ -z "$LATEST_VERSION" ]; then
            echo -e "${RED}检测 soga 版本失败${PLAIN}"
            return 1
        fi
        
        echo -e "检测到 soga 最新版本：${GREEN}${LATEST_VERSION}${PLAIN}，开始更新"
    else
        LATEST_VERSION=$version
        echo -e "开始更新到 soga ${GREEN}${LATEST_VERSION}${PLAIN}"
    fi
    
    cd /tmp
    wget --no-check-certificate -O soga.tar.gz "https://github.com/vaxilu/soga/releases/download/${LATEST_VERSION}/soga-linux-${ARCH}.tar.gz"
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}下载 soga 失败${PLAIN}"
        return 1
    fi
    
    rc-service soga stop 2>/dev/null || true
    
    tar -xzf soga.tar.gz
    cd soga
    cp soga /usr/local/bin/
    chmod +x /usr/local/bin/soga
    
    cd /tmp
    rm -rf soga soga.tar.gz
    
    echo -e "${GREEN}soga 已更新到 ${LATEST_VERSION}${PLAIN}"
    
    if [ $# -eq 0 ]; then
        confirm_restart
    fi
}

# 卸载
uninstall() {
    read -p "确定要卸载 soga 吗？(y/n): " confirm
    if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
        if [ $# -eq 0 ]; then
            show_menu
        fi
        return 0
    fi
    
    rc-service soga stop 2>/dev/null || true
    rc-update del soga default 2>/dev/null || true
    rm -f /etc/init.d/soga
    rm -f /usr/local/bin/soga
    rm -f /usr/bin/soga
    rm -rf /etc/soga
    rm -rf /var/log/soga
    
    echo -e "${GREEN}soga 已卸载${PLAIN}"
    echo ""
}

# 启动
start() {
    check_status
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}soga 已运行，无需再次启动${PLAIN}"
    else
        rc-service soga start
        sleep 2
        check_status
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}soga 启动成功，请使用 soga log 查看运行日志${PLAIN}"
        else
            echo -e "${RED}soga 可能启动失败，请稍后使用 soga log 查看日志信息${PLAIN}"
        fi
    fi
    
    if [ $# -eq 0 ]; then
        before_show_menu
    fi
}

# 停止
stop() {
    check_status
    if [ $? -eq 1 ]; then
        echo -e "${GREEN}soga 已停止，无需再次停止${PLAIN}"
    else
        rc-service soga stop
        sleep 2
        check_status
        if [ $? -eq 1 ]; then
            echo -e "${GREEN}soga 停止成功${PLAIN}"
        else
            echo -e "${RED}soga 停止失败，可能是因为停止时间超过了2秒，请稍后查看日志信息${PLAIN}"
        fi
    fi
    
    if [ $# -eq 0 ]; then
        before_show_menu
    fi
}

# 重启
restart() {
    rc-service soga stop
    sleep 2
    rc-service soga start
    sleep 2
    check_status
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}soga 重启成功，请使用 soga log 查看运行日志${PLAIN}"
    else
        echo -e "${RED}soga 可能启动失败，请稍后使用 soga log 查看日志信息${PLAIN}"
    fi
    
    if [ $# -eq 0 ]; then
        before_show_menu
    fi
}

# 查看状态
status() {
    rc-service soga status
    
    if [ $# -eq 0 ]; then
        before_show_menu
    fi
}

# 设置开机自启
enable() {
    rc-update add soga default
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}soga 设置开机自启成功${PLAIN}"
    else
        echo -e "${RED}soga 设置开机自启失败${PLAIN}"
    fi
    
    if [ $# -eq 0 ]; then
        before_show_menu
    fi
}

# 取消开机自启
disable() {
    rc-update del soga default
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}soga 取消开机自启成功${PLAIN}"
    else
        echo -e "${RED}soga 取消开机自启失败${PLAIN}"
    fi
    
    if [ $# -eq 0 ]; then
        before_show_menu
    fi
}

# 查看日志
show_log() {
    echo -e "${YELLOW}正在查看日志，按 Ctrl+C 退出${PLAIN}"
    tail -f /var/log/soga/output.log
    
    if [ $# -eq 0 ]; then
        before_show_menu
    fi
}

# 编辑配置
edit_config() {
    if command -v vi >/dev/null 2>&1; then
        vi /etc/soga/soga.conf
    elif command -v nano >/dev/null 2>&1; then
        nano /etc/soga/soga.conf
    else
        echo -e "${RED}未找到文本编辑器${PLAIN}"
    fi
    
    if [ $# -eq 0 ]; then
        before_show_menu
    fi
}

# 显示配置
show_config() {
    cat /etc/soga/soga.conf
    
    if [ $# -eq 0 ]; then
        before_show_menu
    fi
}

# 设置配置（自动设置配置项）
set_config() {
    for arg in "$@"; do
        key=$(echo $arg | cut -d'=' -f1)
        value=$(echo $arg | cut -d'=' -f2-)
        
        # 检查配置项是否存在
        if grep -q "^${key}=" /etc/soga/soga.conf; then
            # 替换现有配置
            sed -i "s|^${key}=.*|${key}=${value}|g" /etc/soga/soga.conf
            echo -e "${GREEN}已设置 ${key}=${value}${PLAIN}"
        else
            # 添加新配置
            echo "${key}=${value}" >> /etc/soga/soga.conf
            echo -e "${GREEN}已添加 ${key}=${value}${PLAIN}"
        fi
    done
}

# 显示版本
show_version() {
    /usr/local/bin/soga -v
    
    if [ $# -eq 0 ]; then
        before_show_menu
    fi
}

# 主函数
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
EOF

    chmod +x /usr/bin/soga
    
    echo -e "${GREEN}soga 管理脚本创建完成${PLAIN}"
}

# 主安装流程
main() {
    echo -e "${GREEN}================================${PLAIN}"
    echo -e "${GREEN}  soga Alpine Linux 安装脚本   ${PLAIN}"
    echo -e "${GREEN}================================${PLAIN}"
    echo ""
    
    install_dependencies
    get_latest_version
    download_soga
    install_soga
    create_openrc_service
    create_management_script
    
    echo ""
    echo -e "${GREEN}================================${PLAIN}"
    echo -e "${GREEN}        安装完成！             ${PLAIN}"
    echo -e "${GREEN}================================${PLAIN}"
    echo ""
    echo -e "soga 管理脚本使用方法: "
    echo -e "------------------------------------------"
    echo -e "soga                    - 显示管理菜单 (功能更多)"
    echo -e "soga start              - 启动 soga"
    echo -e "soga stop               - 停止 soga"
    echo -e "soga restart            - 重启 soga"
    echo -e "soga enable             - 设置 soga 开机自启"
    echo -e "soga disable            - 取消 soga 开机自启"
    echo -e "soga log                - 查看 soga 日志"
    echo -e "soga update             - 更新 soga 最新版"
    echo -e "soga update x.x.x       - 安装 soga 指定版本"
    echo -e "soga config             - 显示配置文件内容"
    echo -e "soga config xx=xx yy=yy - 自动设置配置文件"
    echo -e "soga uninstall          - 卸载 soga"
    echo -e "soga version            - 查看 soga 版本"
    echo -e "------------------------------------------"
    echo ""
    echo -e "${YELLOW}下一步：编辑配置文件并启动服务${PLAIN}"
    echo -e "1. ${GREEN}vi /etc/soga/soga.conf${PLAIN}    - 编辑配置"
    echo -e "2. ${GREEN}soga start${PLAIN}                 - 启动服务"
    echo -e "3. ${GREEN}soga enable${PLAIN}                - 设置开机自启"
    echo ""
}

# 运行主函数
main
