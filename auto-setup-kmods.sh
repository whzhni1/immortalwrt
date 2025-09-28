#!/bin/bash
# auto-setup-kmods.sh - 自动配置 kmods 源并安装插件的 uci-defaults 脚本

cat > auto-setup-kmods.sh <<'EOF'
#!/bin/sh
# 自动配置 kmods 源并安装常用插件
# 返回 0 时脚本会被删除，返回非 0 会保留到下次启动继续执行

# 配置参数
KMODS_URL="KMODS_URL_PLACEHOLDER"
LOG_FILE="/tmp/auto-setup-$(date +%Y%m%d-%H%M%S).log"
MAX_PING_RETRY=5

# 需要安装的插件列表
PACKAGES_TO_INSTALL="
    luci-app-ddns
    wget-ssl
    curl
"

# 测试网络的 IP 列表
TEST_IPS="223.5.5.5 114.114.114.114 8.8.8.8 1.1.1.1"

log() {
    echo "[$(date '+%H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# 检查网络连接
check_network() {
    local retry=0
    
    while [ $retry -lt $MAX_PING_RETRY ]; do
        for ip in $TEST_IPS; do
            if ping -c 1 -W 2 "$ip" >/dev/null 2>&1; then
                log "✅ 网络正常 ($ip)"
                return 0
            fi
        done
        retry=$((retry + 1))
        log "网络检测失败，等待 10 秒后重试 ($retry/$MAX_PING_RETRY)..."
        sleep 10
    done
    
    log "❌ 网络不可用，退出"
    return 1
}

# 配置 kmods 源
setup_kmods() {
    if [ -z "$KMODS_URL" ] || [ "$KMODS_URL" = "KMODS_URL_PLACEHOLDER" ]; then
        log "⚠️ kmods URL 未配置"
        return 0
    fi
    
    if [ ! -f /etc/opkg/distfeeds.conf ]; then
        log "❌ distfeeds.conf 不存在"
        return 1
    fi
    
    if grep -q "immortalwrt_kmods" /etc/opkg/distfeeds.conf; then
        log "kmods 源已存在"
    else
        sed -i "2a\\$KMODS_URL" /etc/opkg/distfeeds.conf
        log "✅ kmods 源添加成功"
    fi
    
    return 0
}

# 安装软件包
install_packages() {
    # 更新软件源
    log "更新软件源..."
    if ! opkg update >/dev/null 2>&1; then
        log "❌ 软件源更新失败"
        return 1
    fi
    
    local failed=0
    
    for pkg in $PACKAGES_TO_INSTALL; do
        # 跳过空行
        [ -z "$pkg" ] && continue
        
        # 检查是否已安装
        if opkg list-installed | grep -q "^$pkg "; then
            log "⏭️  $pkg 已安装"
            continue
        fi
        
        # 检查包是否存在
        if ! opkg list | grep -q "^$pkg "; then
            log "⚠️  $pkg 不存在，跳过"
            continue
        fi
        
        # 安装包
        log "📦 安装 $pkg..."
        if opkg install "$pkg" >/dev/null 2>&1; then
            log "✅ $pkg 安装成功"
        else
            log "❌ $pkg 安装失败"
            failed=$((failed + 1))
        fi
    done
    
    if [ $failed -gt 0 ]; then
        log "⚠️ 有 $failed 个包安装失败"
        return 1
    fi
    
    return 0
}

# 主函数
main() {
    log "======================================"
    log "开始自动配置"
    log "======================================"
    
    # 等待系统启动完成
    sleep 20
    
    # 检查网络
    if ! check_network; then
        log "网络不可用，下次启动再试"
        return 1  # 返回非0，脚本不会被删除
    fi
    
    # 配置 kmods 源
    setup_kmods
    
    # 安装软件包
    if ! install_packages; then
        log "软件包安装未完全成功，下次启动再试"
        return 1  # 返回非0，脚本不会被删除
    fi
    
    log "======================================"
    log "✅ 所有配置完成"
    log "======================================"
    
    # 保存日志
    if [ -d /root ]; then
        cp "$LOG_FILE" "/root/auto-setup-success.log"
        log "日志已保存到 /root/auto-setup-success.log"
    fi
    
    return 0  # 返回0，脚本会被自动删除
}

# 执行主函数
main
exit $?
EOF
