#!/bin/bash
# auto-setup-kmods.sh - 自动配置 kmods 源并安装插件的 uci-defaults 脚本

cat > auto-setup-kmods.sh <<'EOF'
#!/bin/sh
# /etc/uci-defaults/99-auto-setup
# 自动配置 kmods 源并安装常用插件

# 配置参数
KMODS_URL="KMODS_URL_PLACEHOLDER"
LOG_FILE="/tmp/auto-setup.log"
DELAY_TIME=600  # 延迟10分钟（600秒）

# 需要安装的插件列表
PACKAGES_TO_INSTALL="
    luci-app-ddns
    luci-app-passwall
    luci-app-wechatpush
"

# 测试网络的 IP 列表
TEST_IPS="223.5.5.5 114.114.114.114 8.8.8.8"

# 日志函数
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
    logger -t "auto-setup" "$1"
}

# 主设置函数
do_setup() {
    log "======================================"
    log "开始自动配置"
    log "======================================"
    
    # 第一步：添加 kmods 源
    log "步骤1: 添加 kmods 源到 distfeeds.conf"
    
    if [ ! -f /etc/opkg/distfeeds.conf ]; then
        log "错误: /etc/opkg/distfeeds.conf 不存在"
        return 1
    fi
    
    # 检查是否已添加
    if grep -q "immortalwrt_kmods" /etc/opkg/distfeeds.conf; then
        log "kmods 源已存在，跳过添加"
    else
        # 在第2行后面（即第3行）插入 kmods 源
        if [ -n "$KMODS_URL" ] && [ "$KMODS_URL" != "KMODS_URL_PLACEHOLDER" ]; then
            # 使用 awk 在第2行后插入
            awk -v line="$KMODS_URL" 'NR==2{print; print line; next}1' /etc/opkg/distfeeds.conf > /tmp/distfeeds.conf.tmp
            
            if [ -s /tmp/distfeeds.conf.tmp ]; then
                mv /tmp/distfeeds.conf.tmp /etc/opkg/distfeeds.conf
                log "✅ kmods 源添加成功"
                log "添加的内容: $KMODS_URL"
                
                # 记录修改后的文件内容
                log "修改后的 distfeeds.conf:"
                cat /etc/opkg/distfeeds.conf >> "$LOG_FILE"
            else
                log "错误: 添加 kmods 源失败"
                return 1
            fi
        else
            log "警告: kmods URL 未配置或无效"
        fi
    fi
    
    # 第二步：检查网络
    log "步骤2: 检查网络连接"
    local network_ok=0
    local retry=0
    
    while [ $retry -lt 5 ]; do
        for ip in $TEST_IPS; do
            if ping -c 1 -W 2 "$ip" >/dev/null 2>&1; then
                log "✅ 网络连接正常 (通过 $ip)"
                network_ok=1
                break 2
            fi
        done
        retry=$((retry + 1))
        log "网络不通，等待30秒后重试 ($retry/5)..."
        sleep 30
    done
    
    if [ $network_ok -eq 0 ]; then
        log "网络不可用，跳过软件包安装"
        return 1
    fi
    
    # 第三步：更新软件源
    log "步骤3: 更新软件源"
    if opkg update >> "$LOG_FILE" 2>&1; then
        log "✅ 软件源更新成功"
    else
        log "软件源更新失败"
        return 1
    fi
    
    # 第四步：安装软件包
    log "步骤4: 安装软件包"
    for pkg in $PACKAGES_TO_INSTALL; do
        [ -z "$pkg" ] && continue
        
        if opkg list-installed | grep -q "^$pkg "; then
            log "$pkg 已安装，跳过"
        else
            log "安装 $pkg..."
            if opkg install "$pkg" >> "$LOG_FILE" 2>&1; then
                log "✅ $pkg 安装成功"
            else
                log "❌ $pkg 安装失败"
            fi
        fi
    done
    
    log "======================================"
    log "自动配置完成"
    log "======================================"
    
    return 0
}

# 创建后台执行脚本
create_background_script() {
    cat > /tmp/auto-setup-background.sh <<'SCRIPT'
#!/bin/sh

# 等待10分钟
sleep 600

# 执行设置函数
. /etc/uci-defaults/99-auto-setup
do_setup

# 根据结果决定是否删除脚本
if [ $? -eq 0 ]; then
    # 成功，删除 uci-defaults 脚本
    rm -f /etc/uci-defaults/99-auto-setup
    logger -t "auto-setup" "配置成功，脚本已删除"
else
    # 失败，保留脚本下次启动再试
    logger -t "auto-setup" "配置未完成，下次启动继续"
fi

# 删除自己
rm -f /tmp/auto-setup-background.sh
SCRIPT
    
    chmod +x /tmp/auto-setup-background.sh
}

# 主入口
main() {
    log "系统启动，准备延迟10分钟后执行自动配置"
    
    # 创建后台脚本
    create_background_script
    
    # 在后台执行（不阻塞启动过程）
    /tmp/auto-setup-background.sh > /dev/null 2>&1 &
    
    # uci-defaults 脚本立即返回成功（但不删除自己）
    # 删除操作由后台脚本根据执行结果决定
    exit 1  # 返回非0，暂时保留脚本
}

# 如果是后台脚本调用，不执行main
if [ "$1" != "background" ]; then
    main
fi
EOF
