#!/bin/bash
set -e

# 如果存在 immortalwrt 目录则进入
[ -d immortalwrt ] && cd immortalwrt

echo "[INFO] Running part2.sh in $(pwd)"

##-----------------Modify default IP-----------------
#sed -i 's/192.168.1.1/192.168.50.5/g' package/base-files/files/bin/config_generate

##-----------------Del duplicate packages------------------
rm -rf feeds/packages/net/open-app-filter
echo "[INFO] Removed duplicate package: open-app-filter"

##-----------------Add OpenClash dev core------------------
#curl -sL -m 30 --retry 2 https://raw.githubusercontent.com/vernesong/OpenClash/core/master/dev/clash-linux-arm64.tar.gz -o /tmp/clash.tar.gz
#tar zxvf /tmp/clash.tar.gz -C /tmp >/dev/null 2>&1
#chmod +x /tmp/clash >/dev/null 2>&1
#mkdir -p feeds/luci/applications/luci-app-openclash/root/etc/openclash/core
#mv /tmp/clash feeds/luci/applications/luci-app-openclash/root/etc/openclash/core/clash >/dev/null 2>&1
#rm -rf /tmp/clash.tar.gz >/dev/null 2>&1
#echo "[INFO] OpenClash dev core added"

##-----------------Delete DDNS's examples-----------------
sed -i '/myddns_ipv4/,$d' feeds/packages/net/ddns-scripts/files/etc/config/ddns
echo "[INFO] Cleaned DDNS example configs"

##-----------------Patch luci-app-lucky Makefile-----------------
LUCI_LUCKY_MK=$(find feeds package -type f -path "*/luci-app-lucky/Makefile" | head -n 1)

if [ -n "$LUCI_LUCKY_MK" ]; then
  echo "[INFO] Found luci-app-lucky Makefile at: $LUCI_LUCKY_MK"

  echo "[INFO] Before patch (LUCI_DEPENDS line):"
  grep '^LUCI_DEPENDS' "$LUCI_LUCKY_MK" || echo "  (not found)"

  # 修改依赖
  sed -i 's/LUCI_DEPENDS:=+lucky +luci-compat/LUCI_DEPENDS:=+luci-compat/' "$LUCI_LUCKY_MK"

  # 删除 install 段落
  sed -i '/^define Package\/$(PKG_NAME)\/install/,/^endef/d' "$LUCI_LUCKY_MK"

  echo "[INFO] After patch (LUCI_DEPENDS line):"
  grep '^LUCI_DEPENDS' "$LUCI_LUCKY_MK" || echo "  (not found)"

  echo "[INFO] Checking if install section still exists:"
  grep -A2 '^define Package/$(PKG_NAME)/install' "$LUCI_LUCKY_MK" || echo "  (install section removed successfully)"

  echo "[INFO] Patch applied successfully."
else
  echo "[WARN] luci-app-lucky Makefile not found in feeds/ or package/!"
fi
