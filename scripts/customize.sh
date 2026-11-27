#!/bin/bash
# 默认主题 argon + iStore 市场（强制中文）+ 无线增强（在源码根目录执行）
#
# 与 .github/scripts/vendor.sh 保持同一套策略，避免两条注入路径走偏：
#   - 主题：优先用 feeds 自带的 luci-theme-argon（immortalwrt/luci themes/luci-theme-argon）；
#           源码树是上游 openwrt/openwrt 时 luci feed 没有该主题，则从 immortalwrt/luci
#           把 themes/luci-theme-argon 补进 feeds/luci 再 install
#   - 商店：istore feed + luci-app-store + luci-i18n-store-zh-cn
#   - 语言：CONFIG_LUCI_LANG_zh_Hans=y + 全量 zh-cn 语言包 + 首启 luci.main.lang=zh_cn
#   - 无线：首启 99-wifi-boost（CN 国码、5G HE160 / 2.4G HE40、802.11k/v/r、beamformee）
set -e
cd "${1:-.}"

echo "== 1/5 默认主题 argon（清理 vantage 残留）=="
rm -rf package/luci-theme-vantage package/luci-app-vantage

echo "== 2/5 引入 iStore feed =="
grep -q '^src-git istore ' feeds.conf.default || \
  echo 'src-git istore https://github.com/linkease/istore.git' >> feeds.conf.default
./scripts/feeds update -a
./scripts/feeds install -a -p istore || true
./scripts/feeds install -a

#------------------------------------------------------------------------------
# argon 主题兜底
#   immortalwrt/luci 自带 themes/luci-theme-argon，本仓库 feeds.conf 指向的 24.10 分支就有；
#   但 build-mt798x.yml 是从上游 openwrt/openwrt 克隆源码，上游 luci feed 一直没有该主题，
#   于是 argon 缺失 → "argon 主题未生效" 断言失败（run 45214204501）。
#   注意：theme 的 Makefile 是 `include ../../luci.mk`，相对路径只在 feeds/luci 下成立，
#   不能直接丢进 package/；补进 feeds/luci 后用 `feeds update -i`（仅重建索引，不联网）
#   再 install，才能拿到正确的包路径。
#------------------------------------------------------------------------------
if [ ! -d feeds/luci/themes/luci-theme-argon ]; then
  echo "   feeds/luci 里没有 luci-theme-argon，从 immortalwrt/luci 补进 feeds"
  tmp=$(mktemp -d)
  got=0
  for i in 1 2 3; do
    if git clone -q --depth 1 --filter=blob:none --sparse \
         -b openwrt-24.10 https://github.com/immortalwrt/luci "$tmp/luci"; then
      got=1; break
    fi
    echo "::warning::克隆 immortalwrt/luci 第 $i 次失败，重试"
    rm -rf "$tmp/luci"; sleep 10
  done
  if [ "$got" != 1 ]; then
    rm -rf "$tmp"
    echo "::error::luci-theme-argon 无法补齐（feeds 没有，且 immortalwrt/luci 克隆失败）"
    exit 1
  fi
  ( cd "$tmp/luci" && git sparse-checkout set themes/luci-theme-argon >/dev/null )
  cp -a "$tmp/luci/themes/luci-theme-argon" feeds/luci/themes/
  rm -rf "$tmp"
  ./scripts/feeds update -i -a
  ./scripts/feeds install -p luci luci-theme-argon || {
    echo "::error::luci-theme-argon 补进 feeds/luci 后仍安装失败"; exit 1; }
  echo "   ✔ 已从 immortalwrt/luci 补齐 luci-theme-argon"
else
  echo "   ✔ feeds 自带 luci-theme-argon"
fi

echo "== 3/5 iStore 市场 + 中文语言包 =="
./scripts/feeds install -d y -p istore luci-app-store || true
./scripts/feeds install -d y -p istore luci-i18n-store-zh-cn || true
# 打开 luci-i18n-*-zh-cn 生成（部分树把该 foreach 注释掉了）
if [ -f feeds/luci/luci.mk ]; then
  sed -i 's/^# \$(foreach lang,\$(LUCI_LANGUAGES)/$(foreach lang,$(LUCI_LANGUAGES)/' feeds/luci/luci.mk || true
fi

echo "== 4/5 写入配置（argon / iStore / 中文开关）=="
cat >> .config <<'EOF'
CONFIG_PACKAGE_luci-theme-argon=y
CONFIG_PACKAGE_luci-theme-vantage=n
CONFIG_LUCI_LANG_zh_Hans=y
CONFIG_PACKAGE_luci-app-store=y
CONFIG_PACKAGE_luci-i18n-store-zh-cn=y
CONFIG_PACKAGE_luci-i18n-base-zh-cn=y
# squid 7.1 链接 libpam.so.0，默认配置未选 libpam，打包阶段会报缺依赖并拖挂 make world；
# 该代理服务不是路由器固件必需，所有机型统一关掉。
# CONFIG_PACKAGE_squid is not set
# CONFIG_PACKAGE_luci-app-squid is not set
EOF

echo "== 5/5 写入首启脚本（默认主题 / 中文界面 / 无线增强）=="
# vendor.sh 在仓库根的 .github/scripts/ 下；本脚本可能从 openwrt/ 子目录调用，
# 所以两个位置都找一遍
V=""
for c in ".github/scripts/vendor.sh" "../.github/scripts/vendor.sh" "$(dirname "$0")/../.github/scripts/vendor.sh"; do
  [ -f "$c" ] && V="$c" && break
done
if [ -n "$V" ]; then
  # 统一由 vendor.sh 生成，argon + zh_cn + wifi-boost 三个脚本一次到位
  bash "$V" uci-defaults
else
  echo "   ::warning::找不到 .github/scripts/vendor.sh，退化成本地写 argon 主题脚本"
  mkdir -p files/etc/uci-defaults
  cat > files/etc/uci-defaults/99-default-theme <<'EOS'
#!/bin/sh
uci -q set luci.themes.Argon='/luci-static/argon'
uci -q set luci.main.mediaurlbase='/luci-static/argon'
uci -q set luci.main.lang='zh_cn'
uci -q commit luci
exit 0
EOS
  chmod +x files/etc/uci-defaults/99-default-theme
fi
echo "[done] customize"
