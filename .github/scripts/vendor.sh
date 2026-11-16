#!/usr/bin/env bash
#
# 全仓库统一的「默认主题 + iStore 市场 + 中文包」注入助手，供 .github/workflows/*.yml 调用。
#
# 主题：luci-theme-vantage（https://github.com/anothaDev/luci-theme-vantage）
#   该主题 README 明确支持 OpenWrt 25.12 和 24.10，包结构是
#   htdocs/luci-static/vantage + ucode/template/themes/vantage（新式 ucode 模板，
#   不是老 LuCI 的 Lua .htm 模板），所以能在本仓库的 24.10 上编译。
#   若克隆失败或结构不符（例如上游改回老式布局），自动回退 argon，构建不中断。
#
# 用法（在 feed / 配置生成的不同阶段分别调用）：
#   vendor.sh feed              # 在 feeds.conf.default 里追加 istore 源（feeds update 之前）
#   vendor.sh store             # feeds update 之后：安装 iStore 市场与中文语言包
#   vendor.sh theme             # 克隆/校验主题包，结果写入 $PWD/.theme（vantage|argon）
#   vendor.sh collections       # 把 feeds/luci 集合对 bootstrap 的依赖改成本次主题
#   vendor.sh config <file>     # 在生成的 .config 里切换主题（argon -> vantage 或反之）
#   vendor.sh uci-defaults      # 写 files/etc/uci-defaults/99-luci-theme-<theme>
#
set -uo pipefail

THEME_REPO="${THEME_REPO:-https://github.com/anothaDev/luci-theme-vantage}"
THEME_FILE="${THEME_FILE:-$PWD/.theme}"
ISTORE_FEED='src-git istore https://github.com/linkease/istore;main'

log()  { echo ">>> $*"; }
warn() { echo "::warning::$*"; }
err()  { echo "::error::$*"; }

current_theme() {
  if [ -f "$THEME_FILE" ]; then cat "$THEME_FILE"; else echo vantage; fi
}

cmd_feed() {
  if grep -q 'src-git istore' feeds.conf.default; then
    log "istore 源已存在"
  else
    echo "$ISTORE_FEED" >> feeds.conf.default
    log "已追加 istore 源: $ISTORE_FEED"
  fi
}

cmd_store() {
  # feeds install -a 不一定装上 istore feed 的包，显式再装一遍
  ./scripts/feeds install -d y -p istore luci-app-store || warn "luci-app-store 安装失败"
  ./scripts/feeds install -d y -p istore luci-i18n-store-zh-cn || warn "luci-i18n-store-zh-cn 安装失败"
  found=""
  for p in package/feeds/istore/luci-app-store package/feeds/luci/luci-app-store feeds/istore/luci-app-store; do
    [ -f "$p/Makefile" ] && found="$p" && break
  done
  if [ -n "$found" ]; then
    log "iStore 市场就绪: $found"
  else
    # 不在这里硬失败：配置阶段会校验 CONFIG_PACKAGE_luci-app-store=y
    warn "没找到 luci-app-store 包目录（istore 源可能没拉到），配置阶段会再校验"
  fi
}

cmd_theme() {
  local theme=vantage
  rm -rf /tmp/vantage-theme package/luci-theme-vantage package/luci-app-vantage
  # 必须保证 package/ 存在：否则 `cp -a src package/` 会把 src 的内容摊平到 package/
  mkdir -p package
  # 只取两个包目录（blob 不全下载），比整仓克隆快很多
  if git clone -q --depth 1 --filter=blob:none --sparse "$THEME_REPO" /tmp/vantage-theme 2>/dev/null \
     && ( cd /tmp/vantage-theme && git sparse-checkout set luci-theme-vantage luci-app-vantage >/dev/null 2>&1 ) \
     && [ -d /tmp/vantage-theme/luci-theme-vantage ]; then
    cp -a /tmp/vantage-theme/luci-theme-vantage package/
    [ -d /tmp/vantage-theme/luci-app-vantage ] && cp -a /tmp/vantage-theme/luci-app-vantage package/
  else
    warn "克隆 $THEME_REPO 失败"
  fi

  if [ -f package/luci-theme-vantage/Makefile ] \
     && [ -d package/luci-theme-vantage/htdocs/luci-static/vantage ] \
     && [ -d package/luci-theme-vantage/ucode/template/themes/vantage ]; then
    log "vantage 主题结构符合 24.10（ucode 模板 + luci-static/vantage）"
    grep -E '^PKG_VERSION|^LUCI_DEPENDS' package/luci-theme-vantage/Makefile 2>/dev/null || true
  else
    warn "vantage 主题不可用（结构不兼容 24.10），回退 argon"
    rm -rf package/luci-theme-vantage package/luci-app-vantage
    theme=argon
  fi
  echo "$theme" > "$THEME_FILE"
  log "本次默认主题: $theme"
}

cmd_collections() {
  local theme f; theme=$(current_theme)
  f=feeds/luci/collections/luci-light/Makefile
  if [ ! -f "$f" ]; then
    warn "找不到 $f，跳过集合依赖改写（.config 里已显式指定主题）"
    return 0
  fi
  # 先清掉之前注入过的主题行（vantage/argon 二选一时必须换掉，否则回退到
  # argon 后集合仍然依赖已被删除的 luci-theme-vantage，构建直接失败）
  sed -i -E '/^[[:space:]]*\+luci-theme-(vantage|argon)[[:space:]]*\\?[[:space:]]*$/d' "$f"
  if grep -q "luci-theme-$theme" "$f"; then
    log "集合包已包含 luci-theme-$theme"
    return 0
  fi
  # 只做「加法」：保留 luci-theme-bootstrap 作运行时兜底，把本次主题追加进
  # LUCI_DEPENDS 列表。插在 bootstrap 那一行前面，两行都以 " \" 结尾，
  # 不会破坏 Makefile 的续行。
  if grep -qE '^[[:space:]]*\+luci-theme-bootstrap[[:space:]]*\\?[[:space:]]*$' "$f"; then
    awk -v t="+luci-theme-$theme" '
      /^[[:space:]]*\+luci-theme-bootstrap/ && !done { printf "\t%s \\\n", t; done=1 }
      { print }
    ' "$f" > "$f.new" && mv "$f.new" "$f"
    log "已把 luci-theme-$theme 加入 luci-light 依赖（bootstrap 保留兜底）"
  else
    warn "$f 里没有 luci-theme-bootstrap 行，不改写（.config 已显式指定主题）"
  fi
  grep -nE "luci-theme-(bootstrap|$theme)" "$f" || true
}

cmd_config() {
  local theme f="${1:-.config}"
  theme=$(current_theme)
  [ -f "$f" ] || { err "配置文件不存在: $f"; return 1; }
  if [ "$theme" = "vantage" ]; then
    sed -i -E 's|^CONFIG_PACKAGE_luci-theme-argon=y|CONFIG_PACKAGE_luci-theme-vantage=y|' "$f"
    sed -i -E 's|^CONFIG_PACKAGE_luci-app-argon-config=y|# CONFIG_PACKAGE_luci-app-argon-config is not set|' "$f"
    grep -q '^CONFIG_PACKAGE_luci-theme-vantage=y$' "$f" || echo 'CONFIG_PACKAGE_luci-theme-vantage=y' >> "$f"
    # 仪表盘（luci-app-vantage）是可选加分项：只有当它自己以及全部 +依赖
    # 都在本次配置里存在时才启用，避免缺包导致整份 .config 编译失败
    if [ -f package/luci-app-vantage/Makefile ]; then
      missing=""
      for dep in luci-base rpcd rpcd-mod-iwinfo rpcd-mod-ucode \
                 ucode-mod-uci ucode-mod-ubus ucode-mod-fs ucode-mod-rtnl ucode-mod-nl80211; do
        if [ -f tmp/.config-package.in ] && ! grep -q "^config PACKAGE_${dep}\$" tmp/.config-package.in; then
          missing="$missing $dep"
        fi
      done
      if [ -z "$missing" ]; then
        grep -q '^CONFIG_PACKAGE_luci-app-vantage=y$' "$f" || echo 'CONFIG_PACKAGE_luci-app-vantage=y' >> "$f"
        log "启用 luci-app-vantage 仪表盘"
      else
        warn "luci-app-vantage 依赖缺失:$missing，跳过仪表盘（主题照常启用）"
      fi
    fi
  else
    grep -q '^CONFIG_PACKAGE_luci-theme-argon=y$' "$f" || echo 'CONFIG_PACKAGE_luci-theme-argon=y' >> "$f"
  fi
  # 全量简体中文语言包（只对本次构建里存在的包生效；注意要补 CONFIG_ 前缀，
  # tmp/.config-package.in 里的行是 "config PACKAGE_xxx"）
  # 该文件由 make defconfig 的前置目标 prepare-tmpinfo 生成；如果调用时机在
  # defconfig 之前（本仓库的 workflow 都是这样），先手工生成一次。
  if [ ! -f tmp/.config-package.in ]; then
    log "tmp/.config-package.in 不存在，先生成包元数据（make prepare-tmpinfo）"
    if ! make prepare-tmpinfo > /tmp/prepare-tmpinfo.log 2>&1; then
      warn "prepare-tmpinfo 失败，中文语言包可能不全（日志尾部如下）"
      tail -5 /tmp/prepare-tmpinfo.log >&2 || true
    fi
  fi
  if [ -f tmp/.config-package.in ]; then
    awk '/^config PACKAGE_luci-i18n-.+-zh-cn$/{print "CONFIG_"$2"=y"}' tmp/.config-package.in > /tmp/zh-i18n.txt || true
    while IFS= read -r line; do
      [ -n "$line" ] || continue
      grep -qxF "$line" "$f" || echo "$line" >> "$f"
    done < /tmp/zh-i18n.txt
    log "简体中文语言包: $(wc -l < /tmp/zh-i18n.txt) 个候选"
  fi
  log "已按主题 $theme 处理 $f"
}

cmd_uci_defaults() {
  local theme; theme=$(current_theme)
  mkdir -p files/etc/uci-defaults
  if [ "$theme" = "vantage" ]; then
    cat > files/etc/uci-defaults/99-luci-theme-vantage <<'SH'
#!/bin/sh
uci -q set luci.themes.Vantage='/luci-static/vantage'
uci -q set luci.main.mediaurlbase='/luci-static/vantage'
uci -q commit luci
exit 0
SH
    chmod +x files/etc/uci-defaults/99-luci-theme-vantage
  else
    cat > files/etc/uci-defaults/99-luci-theme-argon <<'SH'
#!/bin/sh
uci -q set luci.themes.Argon='/luci-static/argon'
uci -q set luci.main.mediaurlbase='/luci-static/argon'
uci -q commit luci
exit 0
SH
    chmod +x files/etc/uci-defaults/99-luci-theme-argon
  fi
  log "已写入 99-luci-theme-$theme"
}

case "${1:-}" in
  feed)         cmd_feed ;;
  store)        cmd_store ;;
  theme)        cmd_theme ;;
  collections)  cmd_collections ;;
  config)       shift; cmd_config "${1:-.config}" ;;
  uci-defaults) cmd_uci_defaults ;;
  *) echo "用法: $0 {feed|store|theme|collections|config <file>|uci-defaults}"; exit 2 ;;
esac
