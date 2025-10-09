#!/bin/bash
set -e

# 如果存在 immortalwrt 目录则进入
[ -d immortalwrt ] && cd immortalwrt

echo "[INFO] 在 $(pwd) 目录中运行 part2.sh"

##-----------------修改默认IP-----------------
#sed -i 's/192.168.1.1/192.168.50.5/g' package/base-files/files/bin/config_generate

##-----------------删除重复的软件包------------------
rm -rf feeds/packages/net/open-app-filter
echo "[INFO] 已删除重复的软件包: open-app-filter"

##-----------------添加 OpenClash 开发核心------------------
#curl -sL -m 30 --retry 2 https://raw.githubusercontent.com/vernesong/OpenClash/core/master/dev/clash-linux-arm64.tar.gz -o /tmp/clash.tar.gz
#tar zxvf /tmp/clash.tar.gz -C /tmp >/dev/null 2>&1
#chmod +x /tmp/clash >/dev/null 2>&1
#mkdir -p feeds/luci/applications/luci-app-openclash/root/etc/openclash/core
#mv /tmp/clash feeds/luci/applications/luci-app-openclash/root/etc/openclash/core/clash >/dev/null 2>&1
#rm -rf /tmp/clash.tar.gz >/dev/null 2>&1
#echo "[INFO] 已添加 OpenClash 开发核心"

##-----------------删除 DDNS 示例配置-----------------
sed -i '/myddns_ipv4/,$d' feeds/packages/net/ddns-scripts/files/etc/config/ddns
echo "[INFO] 已清理 DDNS 示例配置"

##-----------------修补 luci-app-lucky Makefile-----------------
LUCI_LUCKY_MK=$(find feeds package -type f -path "*/luci-app-lucky/Makefile" | head -n 1)

if [ -n "$LUCI_LUCKY_MK" ]; then
  echo "[INFO] 找到 luci-app-lucky Makefile 位于: $LUCI_LUCKY_MK"

  echo "[INFO] 修补前 (LUCI_DEPENDS 行):"
  grep '^LUCI_DEPENDS' "$LUCI_LUCKY_MK" || echo "  (未找到)"

  # 修改依赖
  sed -i 's/LUCI_DEPENDS:=+lucky +luci-compat/LUCI_DEPENDS:=+luci-compat/' "$LUCI_LUCKY_MK"

  # 删除 install 段落
  sed -i '/^define Package\/$(PKG_NAME)\/install/,/^endef/d' "$LUCI_LUCKY_MK"

  echo "[INFO] 修补后 (LUCI_DEPENDS 行):"
  grep '^LUCI_DEPENDS' "$LUCI_LUCKY_MK" || echo "  (未找到)"

  echo "[INFO] 检查 install 段落是否还存在:"
  grep -A2 '^define Package/$(PKG_NAME)/install' "$LUCI_LUCKY_MK" || echo "  (install 段落已成功删除)"

  echo "[INFO] 修补应用成功。"
else
  echo "[警告] 在 feeds/ 或 package/ 中未找到 luci-app-lucky Makefile！"
fi

##-----------------修改 luci-app-tailscale 的 Makefile，移除 tailscale 依赖-----------------
LUCI_MAKEFILE="package/luci-app-tailscale/Makefile"

if [ -f "$LUCI_MAKEFILE" ]; then
    echo "[INFO] 正在修改 $LUCI_MAKEFILE，移除 tailscale 依赖..."
    
    # 方法1: 直接注释掉原行并添加新行
    sed -i 's/^LUCI_DEPENDS:=+tailscale$/# LUCI_DEPENDS:=+tailscale\nLUCI_DEPENDS:=/g' "$LUCI_MAKEFILE"
    
    # 或者方法2: 直接替换整行
    # sed -i 's/^LUCI_DEPENDS:=+tailscale$/LUCI_DEPENDS:=/g' "$LUCI_MAKEFILE"
    
    echo "[INFO] 修改完成，当前 LUCI_DEPENDS 设置："
    grep "LUCI_DEPENDS" "$LUCI_MAKEFILE"
else
    echo "[警告] $LUCI_MAKEFILE 不存在"
fi

echo "[INFO] part2.sh 执行完成"
