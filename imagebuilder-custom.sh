#!/bin/bash
# imagebuilder-custom.sh

echo "执行ImageBuilder自定义配置..."

# 添加自定义软件源（可选）
cat >> repositories.conf <<EOF
# src/gz custom https://your-repo.com/packages
EOF

# 下载额外的ipk包到packages目录
mkdir -p packages
# wget https://github.com/xxx/releases/download/xxx/package.ipk -P packages/

# 添加更多自定义文件
mkdir -p files/etc/banner
echo "Custom Build with ImageBuilder" > files/etc/banner

echo "自定义配置完成"
