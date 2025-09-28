#!/bin/bash
# auto-setup.sh - 自动配置 kmods 源并安装插件

cat > auto-setup.sh <<'EOF'
#!/bin/sh /etc/rc.common
# Auto setup script for ImmortalWrt
# 自动配置 kmods 源并安装插件

START=99
STOP=01

USE_PROCD=1
PROG=/usr/bin/auto-setup-worker

# 配置参数
KMODS_URL="KMODS_URL_PLACEHOLDER"
LOG_FILE="/tmp/auto-setup.log"
LOCK_FILE="/var/lock/auto-setup.lock"
MAX_RETRY=10
RETRY_DELAY=30

# 需要安装的插件列表（可以自定义）
PACKAGES_TO_INSTALL="
    luci-app-ddns
    luci-app-upnp
    luci-app-firewall
    luci-app-wol
    luci-i18n-base-zh-cn
    luci-i18n-firewall-zh-cn
"

# 测试网络连接的 IP 列表
TEST_IPS="
    223.5.5.5
    114.114.114.114
    8.8.8.8
    1.1.1.1
"

log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

check_network() {
    log_message "检查网络连接..."
    
    for ip in $TEST_IPS; do
        if ping -c 1 -W 2 "$ip" >/dev/null 2>&1; then
            log_message "✅ 网络连接正常 (通过 $ip)"
            return 0
        fi
    done
    
    log_message "❌ 网络连接失败"
    return 1
}

wait_for_network() {
    local retry_count=0
    
    while [ $retry_count -lt $MAX_RETRY ]; do
        if check_network; then
            return 0
        fi
        
        retry_count=$((retry_count + 1))
        log_message "等待网络... (尝试 $retry_count/$MAX_RETRY)"
        sleep $RETRY_DELAY
    done
    
    log_message "❌ 网络连接超时"
    return 1
}

setup_kmods_feed() {
    log_message "配置 kmods 软件源..."
    
    if [ -z "$KMODS_URL" ] || [ "$KMODS_URL" = "KMODS_URL_PLACEHOLDER" ]; then
        log_message "⚠️ kmods URL 未配置，跳过"
        return 0
    fi
    
    if [ -f /etc/opkg/distfeeds.conf ]; then
        if grep -q "immortalwrt_kmods" /etc/opkg/distfeeds.conf; then
            log_message "kmods 源已存在"
        else
            # 在第3行插入 kmods 源
            sed -i "2a\\$KMODS_URL" /etc/opkg/distfeeds.conf
            log_message "✅ kmods 源添加成功"
        fi
    else
        log_message "❌ /etc/opkg/distfeeds.conf 不存在"
        return 1
    fi
    
    return 0
}

update_package_list() {
    log_message "更新软件包列表..."
    
    if opkg update >/dev/null 2>&1; then
        log_message "✅ 软件包列表更新成功"
        return 0
    else
        log_message "❌ 软件包列表更新失败"
        return 1
    fi
}

install_package() {
    local package=$1
    
    # 检查是否已安装
    if opkg list-installed | grep -q "^$package "; then
        log_message "⏭️  $package 已安装，跳过"
        return 0
    fi
    
    # 检查包是否存在
    if ! opkg list | grep -q "^$package "; then
        log_message "⚠️  $package 不在软件源中，跳过"
        return 0
    fi
    
    # 安装包
    log_message "📦 正在安装 $package..."
    if opkg install "$package" >/dev/null 2>&1; then
        log_message "✅ $package 安装成功"
        return 0
    else
        log_message "❌ $package 安装失败"
        return 1
    fi
}

install_packages() {
    log_message "开始安装软件包..."
    
    local success_count=0
    local fail_count=0
    
    for package in $PACKAGES_TO_INSTALL; do
        if install_package "$package"; then
            success_count=$((success_count + 1))
        else
            fail_count=$((fail_count + 1))
        fi
    done
    
    log_message "安装完成: 成功 $success_count 个，失败 $fail_count 个"
    
    if [ $fail_count -eq 0 ]; then
        return 0
    else
        return 1
    fi
}

disable_self() {
    log_message "禁用自动配置服务..."
    
    # 禁用服务
    /etc/init.d/auto-setup disable
    
    # 停止服务
    /etc/init.d/auto-setup stop
    
    # 创建完成标记
    touch /etc/auto-setup.done
    
    log_message "✅ 自动配置服务已禁用"
}

main_setup() {
    # 检查是否已经运行过
    if [ -f /etc/auto-setup.done ]; then
        log_message "自动配置已完成，退出"
        return 0
    fi
    
    # 检查锁文件，防止重复运行
    if [ -f "$LOCK_FILE" ]; then
        log_message "另一个实例正在运行，退出"
        return 1
    fi
    
    # 创建锁文件
    touch "$LOCK_FILE"
    
    log_message "======================================"
    log_message "开始自动配置"
    log_message "======================================"
    
    # 等待网络连接
    if ! wait_for_network; then
        log_message "网络不可用，退出"
        rm -f "$LOCK_FILE"
        return 1
    fi
    
    # 配置 kmods 源
    setup_kmods_feed
    
    # 更新软件包列表
    if ! update_package_list; then
        log_message "无法更新软件包列表，退出"
        rm -f "$LOCK_FILE"
        return 1
    fi
    
    # 安装软件包
    install_packages
    
    log_message "======================================"
    log_message "自动配置完成"
    log_message "======================================"
    
    # 保存日志到持久化位置
    if [ -d /etc/log ]; then
        cp "$LOG_FILE" "/etc/log/auto-setup-$(date +%Y%m%d-%H%M%S).log"
    fi
    
    # 清理
    rm -f "$LOCK_FILE"
    
    # 禁用自己
    disable_self
    
    return 0
}

start_service() {
    # 创建工作脚本
    cat > "$PROG" <<'WORKER'
#!/bin/sh
# Worker script for auto-setup

# 延迟启动，等待系统完全启动
sleep 30

# 执行主设置函数
. /etc/init.d/auto-setup
main_setup

# 清理自己
rm -f "$0"
WORKER
    
    chmod +x "$PROG"
    
    procd_open_instance
    procd_set_param command "$PROG"
    procd_set_param respawn 0 0 0
    procd_close_instance
}

stop_service() {
    log_message "停止自动配置服务"
    killall -9 auto-setup-worker 2>/dev/null
    rm -f "$PROG"
}

# 如果直接执行脚本，运行主函数
if [ "$1" = "run" ]; then
    main_setup
fi
EOF
