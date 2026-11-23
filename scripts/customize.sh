#!/bin/bash
# 默认主题 argon + iStore 市场（强制中文）+ 无线增强（在源码根目录执行）
#
# 与 .github/scripts/vendor.sh 保持同一套策略，避免两条注入路径走偏：
#   - 主题：用 feeds 自带的 luci-theme-argon（immortalwrt/luci themes/luci-theme-argon），
#           不再 vendor 外部 vantage，也不再改写 luci-light 的 bootstrap 依赖
#   - 商店：istore feed + luci-app-store + luci-i18n-store-zh-cn
#   - 语言：CONFIG_LUCI_LANG_zh_Hans=y + 全量 zh-cn 语言包 + 首启 luci.main.lang=zh_cn
#   - 无线：首启 99-wifi-boost（CN 国码、5G HE160 / 2.4G HE40、802.11k/v/r、beamformee）
set -e
cd "${1:-.}"

echo "== 1/5 默认主题 argon（沿用 feeds 自带，清理 vantage 残留）=="
rm -rf package/luci-theme-vantage package/luci-app-vantage
if [ -d feeds/luci/themes/luci-theme-argon ]; then
  echo "   使用 feeds/luci/themes/luci-theme-argon"
else
  echo "   ::warning::feeds 里没找到 luci-theme-argon（feeds install 是否已执行？）"
fi

echo "== 2/5 引入 iStore feed =="
grep -q '^src-git istore ' feeds.conf.default || \
  echo 'src-git istore https://github.com/linkease/istore.git' >> feeds.conf.default
./scripts/feeds update -a
./scripts/feeds install -a -p istore || true
./scripts/feeds install -a

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
