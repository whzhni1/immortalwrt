#!/bin/sh
# auto-setup-uci.sh - 自动配置 kmods 源、安装软件包和 Lucky 的 uci-defaults 脚本
# 此脚本会被放置到 /etc/uci-defaults/99-auto-setup

# 配置参数（会被工作流替换）
KMODS_URL="KMODS_URL_PLACEHOLDER"
LOG_FILE="/tmp/auto-setup-$(date +%Y%m%d-%H%M%S).log"
SUCCESS_FLAG="/etc/auto-setup.success"
WAIT_TIME=180  # 等待3分钟（180秒）
PING_RETRY=5   # ping重试次数
PING_WAIT=60   # 每次ping失败等待60秒

# 从 packages.txt 读取的软件包列表（会被工作流替换）
PACKAGES_TO_INSTALL="PACKAGES_LIST_PLACEHOLDER"

# 测试网络的 IP 列表
TEST_IPS="223.5.5.5 114.114.114.114 8.8.8.8 1.1.1.1"

# 日志函数
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
    logger -t "auto-setup" "$1"
}

# 检查是否已经成功执行过
if [ -f "$SUCCESS_FLAG" ]; then
    log "自动配置已经成功完成过，跳过"
    exit 0  # 返回0删除自己
fi

log "======================================"
log "开始自动配置 (PID: $$)"
log "日志文件: $LOG_FILE"
log "======================================"

# 第一步：添加 kmods 源
add_kmods() {
    log "步骤1: 添加 kmods 软件源"
    
    if [ ! -f /etc/opkg/distfeeds.conf ]; then
        log "错误: distfeeds.conf 不存在"
        return 1
    fi
    
    if grep -q "immortalwrt_kmods" /etc/opkg/distfeeds.conf; then
        log "kmods 源已存在"
        return 0
    fi
    
    # 在第2行后插入（成为第3行）
    awk -v line="$KMODS_URL" 'NR==2{print; print line; next}1' /etc/opkg/distfeeds.conf > /tmp/distfeeds.tmp
    if [ -s /tmp/distfeeds.tmp ]; then
        mv /tmp/distfeeds.tmp /etc/opkg/distfeeds.conf
        log "✅ kmods 源添加成功"
        log "添加的内容: $KMODS_URL"
        return 0
    else
        log "❌ 添加 kmods 源失败"
        return 1
    fi
}

# 第二步：等待系统稳定
wait_system_ready() {
    log "步骤2: 等待系统稳定（${WAIT_TIME}秒）..."
    
    # 显示倒计时
    remaining=$WAIT_TIME
    while [ $remaining -gt 0 ]; do
        if [ $((remaining % 30)) -eq 0 ]; then
            log "等待中... 剩余 ${remaining} 秒"
        fi
        sleep 10
        remaining=$((remaining - 10))
    done
    
    log "系统等待完成，开始执行后续操作"
}

# 第三步：检查网络（带重试机制）
check_network_with_retry() {
    log "步骤3: 检查网络连接（最多重试 ${PING_RETRY} 次）"
    
    local retry=0
    while [ $retry -lt $PING_RETRY ]; do
        retry=$((retry + 1))
        log "网络检测 (第 $retry/$PING_RETRY 次)..."
        
        for ip in $TEST_IPS; do
            if ping -c 1 -W 2 "$ip" >/dev/null 2>&1; then
                log "✅ 网络正常 (通过 $ip)"
                return 0
            fi
        done
        
        if [ $retry -lt $PING_RETRY ]; then
            log "网络不通，等待 ${PING_WAIT} 秒后重试..."
            sleep $PING_WAIT
        fi
    done
    
    log "❌ 网络检测失败（已重试 ${PING_RETRY} 次）"
    return 1
}

# 第四步：安装软件包
install_packages() {
    if [ -z "$PACKAGES_TO_INSTALL" ] || [ "$PACKAGES_TO_INSTALL" = " " ] || [ "$PACKAGES_TO_INSTALL" = "PACKAGES_LIST_PLACEHOLDER" ]; then
        log "没有需要安装的软件包，跳过"
        return 0
    fi
    
    log "步骤4: 安装软件包"
    
    # 更新软件源
    log "更新软件源..."
    if ! opkg update >> "$LOG_FILE" 2>&1; then
        log "❌ 软件源更新失败"
        return 1
    fi
    log "✅ 软件源更新成功"
    
    # 安装包
    local failed=0
    local success=0
    for pkg in $PACKAGES_TO_INSTALL; do
        [ -z "$pkg" ] && continue
        
        if opkg list-installed | grep -q "^$pkg "; then
            log "⏭️  $pkg 已安装"
        else
            log "📦 安装 $pkg..."
            if opkg install "$pkg" >> "$LOG_FILE" 2>&1; then
                log "✅ $pkg 安装成功"
                success=$((success + 1))
            else
                log "❌ $pkg 安装失败"
                failed=$((failed + 1))
            fi
        fi
    done
    
    log "软件包安装完成: 成功 $success 个，失败 $failed 个"
    
    if [ $failed -gt 0 ]; then
        return 1
    fi
    return 0
}

# 第五步：安装 Lucky（集成的脚本）
install_lucky() {
    log "步骤5: 安装 Lucky"
    log "======================================"
    
    # Lucky 安装脚本
    echo='echo -e' && [ -n "$(echo -e | grep e)" ] && echo=echo
    
    luckPathSuff='lucky.daji'
    download_base_url="http://release.66666.host"
    version=""
    subdir=""
    cpucore=""
    luckydir="/etc/lucky.daji"
    
    # URL 解码函数
    decode_url() {
        echo "$1" | sed 's/%/\\x/g' | while read -r line; do printf "%b\n" "$line"; done
    }
    
    # 获取系统架构
    getcpucore() {
        cputype=$(uname -ms | tr ' ' '_' | tr '[A-Z]' '[a-z]')
        [ -n "$(echo $cputype | grep -E "linux.*armv.*")" ] && cpucore="armv5"
        [ -n "$(echo $cputype | grep -E "linux.*armv7.*")" ] && [ -n "$(cat /proc/cpuinfo | grep vfp)" ] && [ ! -d /jffs/clash ] && cpucore="armv7"
        [ -n "$(echo $cputype | grep -E "linux.*aarch64.*|linux.*armv8.*")" ] && cpucore="arm64"
        [ -n "$(echo $cputype | grep -E "linux.*86.*")" ] && cpucore="i386"
        [ -n "$(echo $cputype | grep -E "linux.*86_64.*")" ] && cpucore="x86_64"
        if [ -n "$(echo $cputype | grep -E "linux.*mips.*")" ]; then
            mipstype=$(echo -n I | hexdump -o 2>/dev/null | awk '{ print substr($2,6,1); exit}')
            [ "$mipstype" = "0" ] && cpucore="mips_softfloat" || cpucore="mipsle_softfloat"
        fi
    }
    
    # 获取CPU架构
    getcpucore
    if [ -z "$cpucore" ]; then
        log '错误: 未能正确识别当前系统CPU架构！'
        return 1
    fi
    log "当前系统架构: $cpucore"
    
    # 获取最新正式版本
    log "正在获取最新正式版本（跳过beta版本）..."
    if curl --version >/dev/null 2>&1; then
        versions=$(curl -s "$download_base_url/" | sed -n 's/.*href="\.\///p' | sed -E 's/\/.*//g' | grep '^v' | sort -Vr)
    elif wget --version >/dev/null 2>&1; then
        versions=$(wget -qO- "$download_base_url/" | sed -n 's/.*href="\.\///p' | sed -E 's/\/.*//g' | grep '^v' | sort -Vr)
    else
        log "无法获取版本列表"
        return 1
    fi
    
    if [ -z "$versions" ]; then
        log "未能获取可用的版本"
        return 1
    fi
    
    # 过滤掉包含 beta 的版本
    stable_versions=$(echo "$versions" | grep -v -i "beta")
    
    if [ -z "$stable_versions" ]; then
        log "错误: 未找到正式版本"
        return 1
    fi
    
    version=$(echo "$stable_versions" | head -1)
    log "自动选择最新正式版本: $version"
    
    # 获取 wanji 子目录
    log "正在获取 $version 版本的子目录..."
    if curl --version >/dev/null 2>&1; then
        subdirs=$(curl -s "$download_base_url/$version/" | sed -n 's/.*href="\.\///p' | sed -E 's/\/.*//g' | grep '^[0-9].*_' | sort -u | grep -v '^$')
    elif wget --version >/dev/null 2>&1; then
        subdirs=$(wget -qO- "$download_base_url/$version/" | sed -n 's/.*href="\.\///p' | sed -E 's/\/.*//g' | grep '^[0-9].*_' | sort -u | grep -v '^$')
    else
        log "无法获取子目录列表"
        return 1
    fi
    
    if [ -z "$subdirs" ]; then
        log "未能获取可用的子目录"
        return 1
    fi
    
    decoded_subdirs=$(decode_url "$subdirs")
    subdir=$(echo "$decoded_subdirs" | grep "wanji" | head -1)
    
    if [ -z "$subdir" ]; then
        log "错误: 未找到包含 'wanji' 的子目录"
        return 1
    fi
    
    log "自动选择子目录: $subdir"
    
    # 获取匹配的二进制文件
    log "正在查找匹配的二进制文件..."
    if curl --version >/dev/null 2>&1; then
        file_list=$(curl -s "$download_base_url/$version/$subdir/" | sed -n 's/.*href="KATEX_INLINE_OPEN[^"]*KATEX_INLINE_CLOSE".*/\1/p' | grep -iE 'tar\.gz' | sort -u)
    elif wget --version >/dev/null 2>&1; then
        file_list=$(wget -qO- "$download_base_url/$version/$subdir/" | sed -n 's/.*href="KATEX_INLINE_OPEN[^"]*KATEX_INLINE_CLOSE".*/\1/p' | grep -iE 'tar\.gz' | sort -u)
    else
        log "无法获取文件列表"
        return 1
    fi
    
    file_list=$(echo "$file_list" | grep -v '^$')
    
    if [ -z "$file_list" ]; then
        log "错误: 未找到安装包文件"
        return 1
    fi
    
    # 根据架构选择文件
    case "$cpucore" in
        "x86_64")
            selected_file=$(echo "$file_list" | grep -i "linux.*x86_64.*wanji" | head -1)
            ;;
        "arm64"|"aarch64")
            selected_file=$(echo "$file_list" | grep -i "linux.*arm64.*wanji" | head -1)
            ;;
        "armv7")
            selected_file=$(echo "$file_list" | grep -i "linux.*arm.*wanji" | head -1)
            ;;
        "i386")
            selected_file=$(echo "$file_list" | grep -i "linux.*386.*wanji" | head -1)
            ;;
        "mips_softfloat"|"mipsle_softfloat")
            selected_file=$(echo "$file_list" | grep -i "linux.*mips.*wanji" | head -1)
            ;;
        *)
            selected_file=""
            ;;
    esac
    
    if [ -z "$selected_file" ]; then
        log "错误: 未找到匹配当前架构 ($cpucore) 的 wanji 版本安装包"
        return 1
    fi
    
    log "找到匹配的安装包: $selected_file"
    
    download_url="$download_base_url/$version/$subdir/$selected_file"
    log "下载链接: $download_url"
    
    # 下载文件
    log "正在下载 Lucky 安装包..."
    if curl --version >/dev/null 2>&1; then
        curl -L -o /tmp/lucky.tar.gz "$download_url" >> "$LOG_FILE" 2>&1
    elif wget --version >/dev/null 2>&1; then
        wget -O /tmp/lucky.tar.gz "$download_url" >> "$LOG_FILE" 2>&1
    else
        log "没有可用的下载工具"
        return 1
    fi
    
    if [ ! -f /tmp/lucky.tar.gz ]; then
        log "错误: 文件下载失败"
        return 1
    fi
    log "Lucky 安装包下载完成"
    
    # 解压安装
    log "开始解压文件..."
    mkdir -p "$luckydir" > /dev/null
    tar -zxf '/tmp/lucky.tar.gz' -C "$luckydir/" >> "$LOG_FILE" 2>&1
    if [ $? -ne 0 ]; then
        log "错误: 文件解压失败"
        rm -rf /tmp/lucky.tar.gz
        return 1
    fi
    
    log "已解压到 $luckydir"
    chmod +x "$luckydir/lucky"
    chmod +x "$luckydir/scripts/"* 2>/dev/null
    rm -rf /tmp/lucky.tar.gz
    
    # 设置环境变量和启动服务
    log "设置环境变量和开机自启..."
    profile="/etc/profile"
    
    sed -i '/alias lucky=*/d' $profile
    sed -i '/export luckydir=*/d' $profile
    
    echo "alias lucky=\"$luckydir/lucky\"" >> $profile 
    echo "export luckydir=\"$luckydir\"" >> $profile 
    log "环境变量已设置"
    
    # 设置 init.d 服务
    if [ -f "$luckydir/scripts/luckyservice" ]; then
        log "设置 init.d 服务..."
        ln -sf $luckydir/scripts/luckyservice /etc/init.d/lucky.daji
        chmod 755 /etc/init.d/lucky.daji
        
        /etc/init.d/lucky.daji enable
        /etc/init.d/lucky.daji restart >> "$LOG_FILE" 2>&1
        log "Lucky 服务启动完成"
    else
        log "警告: 未找到 luckyservice 脚本"
    fi
    
    log "Lucky 安装完成！"
    log "安装目录: $luckydir"
    log "版本: $version"
    log "访问地址: http://你的IP:16601"
    
    return 0
}

# 主执行流程
main() {
    # 添加 kmods 源
    if ! add_kmods; then
        log "kmods 源添加失败，下次启动重试"
        exit 1  # 返回非0，保留脚本
    fi
    
    # 等待系统稳定
    wait_system_ready
    
    # 检查网络
    if ! check_network_with_retry; then
        log "网络不可用，下次启动重试"
        exit 1  # 返回非0，保留脚本
    fi
    
    # 安装软件包
    if ! install_packages; then
        log "软件包安装失败，下次启动重试"
        exit 1  # 返回非0，保留脚本
    fi
    
    # 安装 Lucky
    if ! install_lucky; then
        log "Lucky 安装失败，下次启动重试"
        exit 1  # 返回非0，保留脚本
    fi
    
    # 所有任务完成
    log "======================================"
    log "✅ 所有配置成功完成"
    log "======================================"
    
    # 创建成功标记
    touch "$SUCCESS_FLAG"
    
    # 保存日志副本
    cp "$LOG_FILE" "/tmp/auto-setup-success.log"
    log "完整日志已保存到: /tmp/auto-setup-success.log"
    
    # 返回0，让系统删除此脚本
    exit 0
}

# 执行主函数
main
