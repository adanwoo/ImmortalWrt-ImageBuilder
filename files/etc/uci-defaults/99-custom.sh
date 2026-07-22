#!/bin/sh
# 99-custom.sh (针对旁路由定制版)
LOGFILE="/etc/config/uci-defaults-log.txt"
echo "Starting 99-custom.sh at $(date)" >>$LOGFILE

# 1. 允许 WAN 口访问（对旁路由来说是保险操作）
uci set firewall.@zone[1].input='ACCEPT'
uci commit firewall

# 2. 设置主机名映射，解决安卓原生 TV 无法联网的问题
uci add dhcp domain
uci set "dhcp.@domain[-1].name=time.android.com"
uci set "dhcp.@domain[-1].ip=203.107.6.88"
uci commit dhcp

# 3. 设置所有网口可访问网页终端 (ttyd)
uci delete ttyd.@ttyd[0].interface 2>/dev/null
uci commit ttyd

# 4. 设置所有网口可连接 SSH (dropbear)
uci set dropbear.@dropbear[0].Interface=''
uci commit dropbear

# 5. 设置编译作者信息
FILE_PATH="/etc/openwrt_release"
NEW_DESCRIPTION="Packaged for PVE Bypass Router"
if [ -f "$FILE_PATH" ]; then
    sed -i "s/DISTRIB_DESCRIPTION='[^']*'/DISTRIB_DESCRIPTION='$NEW_DESCRIPTION'/" "$FILE_PATH"
fi

# 6. 修复部分插件的 zsh 报错
if [ -f /usr/lib/lua/luci/controller/advancedplus.lua ]; then
    sed -i '/\/usr\/bin\/zsh/d' /etc/profile 2>/dev/null
    sed -i '/\/bin\/zsh/d' /etc/init.d/advancedplus 2>/dev/null
    sed -i '/\/usr\/bin\/zsh/d' /etc/init.d/advancedplus 2>/dev/null
    echo "fix ttyd show msg: /usr/bin/zsh: not found" >>$LOGFILE
fi

# 7. 若安装了 dockerd 则设置 Docker 的防火墙规则
if command -v dockerd >/dev/null 2>&1; then
    echo "检测到 Docker，正在配置防火墙规则..." >>$LOGFILE
    FW_FILE="/etc/config/firewall"

    # 删除所有名为 docker 的 zone
    uci delete firewall.docker 2>/dev/null

    # 清理旧的转发规则
    for idx in $(uci show firewall | grep "=forwarding" | cut -d[ -f2 | cut -d] -f1 | sort -rn); do
        src=$(uci get firewall.@forwarding[$idx].src 2>/dev/null)
        dest=$(uci get firewall.@forwarding[$idx].dest 2>/dev/null)
        if [ "$src" = "docker" ] || [ "$dest" = "docker" ]; then
            uci delete firewall.@forwarding[$idx]
        fi
    done
    uci commit firewall

# 追加新的 Docker 防火墙配置
cat <<EOF >>"$FW_FILE"

config zone 'docker'
  option input 'ACCEPT'
  option output 'ACCEPT'
  option forward 'ACCEPT'
  option name 'docker'
  list subnet '172.16.0.0/12'

config forwarding
  option src 'docker'
  option dest 'lan'

config forwarding
  option src 'docker'
  option dest 'wan'

config forwarding
  option src 'lan'
  option dest 'docker'
EOF

else
    echo "未检测到 Docker，跳过防火墙配置。" >>$LOGFILE
fi

exit 0