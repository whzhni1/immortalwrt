#!/bin/sh /etc/rc.common
# auto-setup-init.sh - 自动配置 kmods 源、安装软件包和 Lucky 的 init.d 脚本
# 此脚本会被放置到 /etc/init.d/auto-setup

START=99  # 最后启动，确保网络服务已经就绪
STOP=01

# 配置参数（会被工作流替换）
KMODS_URL="KMODS_URL_PLACEHOLDER"
LOG_FILE="/tmp/auto-setup-$(date +%Y%m%d-%H%M%S).log"
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

# 删除或禁用自己
remove_self() {
    log "准备清理自动配置脚本..."
    
    # 先禁用服务
    /etc/init.d/auto-setup disable 2>/dev/null
    
    # 尝试删除脚本
    if rm -f /etc/init.d/auto-setup 2>/dev/null; then
        log " 自动配置脚本已删除"
    else
        log " 无法删除脚本，已禁用服务"
    fi
    
    # 删除 rc.d 链接
    rm -f /etc/rc.d/S99auto-setup 2>/dev/null
    rm -f /etc/rc.d/K01auto-setup 2>/dev/null
}

# 添加 kmods 源
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
        log " kmods 源添加成功"
        log "添加的内容: $KMODS_URL"
        return 0
    else
        log " 添加 kmods 源失败"
        return 1
    fi
}

# 检查网络（带重试机制）
check_network_with_retry() {
    log "步骤2: 检查网络连接（最多重试 ${PING_RETRY} 次）"
    
    local retry=0
    while [ $retry -lt $PING_RETRY ]; do
        retry=$((retry + 1))
        log "网络检测 (第 $retry/$PING_RETRY 次)..."
        
        for ip in $TEST_IPS; do
            if ping -c 1 -W 2 "$ip" >/dev/null 2>&1; then
                log " 网络正常 (通过 $ip)"
                return 0
            fi
        done
        
        if [ $retry -lt $PING_RETRY ]; then
            log "网络不通，等待 ${PING_WAIT} 秒后重试..."
            sleep $PING_WAIT
        fi
    done
    
    log " 网络检测失败（已重试 ${PING_RETRY} 次）"
    return 1
}

# 安装软件包
install_packages() {
    log "步骤3: 安装软件包"
    
    # 直接检查包列表是否有效
    if [ -z "$PACKAGES_TO_INSTALL" ] || [ "$PACKAGES_TO_INSTALL" = "PACKAGES_LIST_PLACEHOLDER" ]; then
        log "软件包列表为空或未正确配置"
        return 1
    fi
    
    log "需要安装的插件: $PACKAGES_TO_INSTALL"
    
    # 更新软件源
    log "更新软件源..."
    if ! opkg update >> "$LOG_FILE" 2>&1; then
        log "软件源更新失败"
        return 1
    fi
    log "软件源更新成功"
    
    # 安装包
    local failed=0
    local success=0
    local skipped=0
    
    for pkg in $PACKAGES_TO_INSTALL; do
        # 清理包名中的空格
        pkg=$(echo "$pkg" | xargs)
        [ -z "$pkg" ] && continue
        
        # 检查是否已安装
        if opkg list-installed | grep -q "^$pkg "; then
            log "$pkg 已安装，跳过"
            skipped=$((skipped + 1))
            continue
        fi
        
        log "安装 $pkg..."
        if opkg install "$pkg" >> "$LOG_FILE" 2>&1; then
            log "$pkg 安装成功"
            success=$((success + 1))
        else
            log "$pkg 安装失败"
            failed=$((failed + 1))
        fi
    done
    
    log "软件包安装完成: 成功 $success 个，跳过 $skipped 个，失败 $failed 个"
    
    if [ $failed -gt 0 ]; then
        return 1
    fi
    return 0
}

# 安装 Lucky
install_lucky() {
    log "步骤4: 安装 Lucky"
    log "======================================"
    
    download_base_url="http://release.66666.host"
    luckydir="/usr/bin/lucky"  # 修改安装目录
    
    # URL 解码
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
    
    # 下载文件
    webget() {
        if curl --version >/dev/null 2>&1; then
            result=$(curl -w %{http_code} --connect-timeout 5 -L -o $1 $2 2>> "$LOG_FILE")
            [ -n "$(echo $result | grep -e ^2)" ] && result="200"
        else
            if wget --version >/dev/null 2>&1; then
                wget -q --no-check-certificate --timeout=3 -O $1 $2 >> "$LOG_FILE" 2>&1
            fi
            [ $? -eq 0 ] && result="200"
        fi
    }
    
    # 获取CPU架构
    getcpucore
    if [ -z "$cpucore" ]; then
        log '错误: 未能识别系统架构'
        return 1
    fi
    log "系统架构: $cpucore"
    
    # 获取最新正式版本
    log "获取最新正式版本..."
    if curl --version >/dev/null 2>&1; then
        versions=$(curl -s "$download_base_url/" | sed -n 's/.*href="\.\///p' | sed -E 's/\/.*//g' | grep '^v' | sort -Vr)
    elif wget --version >/dev/null 2>&1; then
        versions=$(wget -qO- "$download_base_url/" | sed -n 's/.*href="\.\///p' | sed -E 's/\/.*//g' | grep '^v' | sort -Vr)
    else
        log "无法获取版本列表"
        return 1
    fi
    
    # 调试信息：显示获取到的所有版本
    log "获取到的所有版本:"
    echo "$versions" | while read v; do log "  - $v"; done
    
    stable_versions=$(echo "$versions" | grep -v -i "beta")
    
    if [ -z "$stable_versions" ]; then
        log "未找到正式版本，可用的版本:"
        echo "$versions" | while read v; do log "  - $v"; done
        return 1
    fi
    
    version=$(echo "$stable_versions" | head -1)
    log "选择的版本: $version"
    
    # 获取 wanji 子目录
    log "获取子目录..."
    if curl --version >/dev/null 2>&1; then
        subdirs=$(curl -s "$download_base_url/$version/" | sed -n 's/.*href="\.\///p' | sed -E 's/\/.*//g' | grep '^[0-9].*_' | sort -u | grep -v '^$')
    elif wget --version >/dev/null 2>&1; then
        subdirs=$(wget -qO- "$download_base_url/$version/" | sed -n 's/.*href="\.\///p' | sed -E 's/\/.*//g' | grep '^[0-9].*_' | sort -u | grep -v '^$')
    fi
    
    # 调试信息：显示获取到的所有子目录
    log "获取到的所有子目录:"
    echo "$subdirs" | while read s; do log "  - $s"; done
    
    decoded_subdirs=$(decode_url "$subdirs")
    subdir=$(echo "$decoded_subdirs" | grep "wanji" | head -1)
    
    if [ -z "$subdir" ]; then
        log "未找到 wanji 子目录，可用的子目录:"
        echo "$decoded_subdirs" | while read s; do log "  - $s"; done
        return 1
    fi
    log "选择的子目录: $subdir"
    
    # 查找匹配的文件
    log "查找安装包..."
    if curl --version >/dev/null 2>&1; then
        file_list=$(curl -s "$download_base_url/$version/$subdir/" | sed -n 's/.*href="\([^"]*\)".*/\1/p' | grep -iE 'tar\.gz' | sort -u)
    elif wget --version >/dev/null 2>&1; then
        file_list=$(wget -qO- "$download_base_url/$version/$subdir/" | sed -n 's/.*href="\([^"]*\)".*/\1/p' | grep -iE 'tar\.gz' | sort -u)
    fi
    
    file_list=$(echo "$file_list" | grep -v '^$')
    
    if [ -z "$file_list" ]; then
        log "未找到安装包文件"
        return 1
    fi
    
    log "可用的安装包:"
    echo "$file_list" | while read file; do log "  - $file"; done
    
    # 根据架构选择文件
    case "$cpucore" in
        "x86_64")
            selected_file=$(echo "$file_list" | grep -i "linux.*x86_64.*wanji" | head -1)
            ;;
        "arm64")
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
        log "未找到匹配架构 ($cpucore) 的安装包"
        log "尝试使用第一个可用文件..."
        selected_file=$(echo "$file_list" | head -1)
    fi
    
    if [ -z "$selected_file" ]; then
        log " 没有可用的安装包"
        return 1
    fi
    
    log "选择的安装包: $selected_file"
    
    download_url="$download_base_url/$version/$subdir/$selected_file"
    log "下载链接: $download_url"
    
    # 下载并安装
    log "开始下载..."
    webget /tmp/lucky.tar.gz "$download_url"
    if [ "$result" != "200" ]; then
        log " 下载失败 (HTTP: $result)"
        return 1
    fi
    
    log "下载成功，开始解压..."
    mkdir -p "$luckydir"
    if ! tar -zxf '/tmp/lucky.tar.gz' -C "$luckydir/" >> "$LOG_FILE" 2>&1; then
        log " 解压失败"
        rm -f /tmp/lucky.tar.gz
        return 1
    fi
    
    log "设置权限..."
    chmod +x "$luckydir/lucky"
    chmod +x "$luckydir/scripts/"* 2>/dev/null
    rm -f /tmp/lucky.tar.gz
    
    # 创建符号链接到 /usr/bin 让系统能直接识别 lucky 命令
    log "创建符号链接..."
    ln -sf "$luckydir/lucky" /usr/bin/lucky 2>/dev/null
    
    # 设置环境变量（简化，因为已经有符号链接了）
    log "设置环境变量..."
    sed -i '/alias lucky=*/d' /etc/profile
    sed -i '/export luckydir=*/d' /etc/profile
    echo "alias lucky=\"/usr/bin/lucky\"" >> /etc/profile
    echo "export luckydir=\"$luckydir\"" >> /etc/profile
    
    # 设置服务 - 修改服务脚本路径
    if [ -f "$luckydir/scripts/luckyservice" ]; then
        log "设置开机自启服务..."
        ln -sf "$luckydir/scripts/luckyservice" /etc/init.d/lucky
        chmod 755 /etc/init.d/lucky
        /etc/init.d/lucky enable
        /etc/init.d/lucky restart >> "$LOG_FILE" 2>&1
        log " Lucky 服务已启动"
    else
        log " 未找到 luckyservice 脚本，请手动启动 Lucky"
    fi
    
    # 创建 LuCI 检测文件（可选）
    log "创建 LuCI 检测文件..."
    mkdir -p /usr/share/luci/menu.d
    cat > /usr/share/luci/menu.d/luci-lucky.json << EOF
{
    "admin/services/lucky": {
        "title": "Lucky",
        "order": 70,
        "action": {
            "type": "firstchild",
            "recurse": true
        }
    }
}
EOF
    
    log " Lucky 安装完成"
    log "访问地址: http://你的路由器IP:16601"
    log "Lucky 命令位置: /usr/bin/lucky"
    
    return 0
}

# 主执行函数
boot() {
    log "======================================"
    log "开始自动配置 (PID: $$)"
    log "日志文件: $LOG_FILE"
    log "======================================"
    
    # 执行配置流程
    FAILED=0
    
    # 添加 kmods 源
    if ! add_kmods; then
        log "kmods 源添加失败"
        FAILED=1
    fi
    
    # 检查网络
    if ! check_network_with_retry; then
        log "网络不可用，停止执行"
        exit 0  # 下次启动继续
    fi
    
    # 安装软件包
    if ! install_packages; then
        log "软件包安装失败"
        FAILED=1
    fi
    
    # 安装 Lucky
    if ! install_lucky; then
        log "Lucky 安装失败"
        FAILED=1
    fi
    
    if [ $FAILED -eq 0 ]; then
        log "======================================"
        log " 所有配置成功完成"
        log "======================================"
        
        # 删除自己
        remove_self
    else
        log " 配置未完全成功，下次启动继续"
    fi
}

start() {
    boot
}

stop() {
    log "停止自动配置服务"
}
