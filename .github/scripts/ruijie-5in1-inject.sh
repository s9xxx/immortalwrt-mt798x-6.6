#!/bin/bash
# 锐捷 5 机型统一注入（lede / Kwrt / immortalwrt-mt798x-action / immortalwrt-mt798x-6.6 通用）
#
#   SLUG=<slug> [SOURCE_ROOT=openwrt] bash .github/scripts/ruijie-5in1-inject.sh
#
# 机型：EW-6000GX PRO / RG-X60 New / RG-X30E Pro / RG-X30E / RG-BE72 Pro
#
# 设计：
#   1. 设备定义（DTS、filogic.mk 设备块、board.d 网口映射）全部来自本仓库
#      devices-pack/<slug>/，由 scripts/apply-pack.py 注入，不在 workflow 里重复维护。
#   2. 网口期望值在下方 case 里集中声明：任何一台机型的 LAN/WAN 与预期不符就直接失败，
#      不再产出“能启动但 WAN 不通”的固件。
#   3. 无线：首启脚本 97-ruijie-wifi 按 band 判断（不写死 path/phy，跨内核通用），
#      保证 /etc/config/wireless 有双频 AP 且启用；后续 99-wifi-boost 再做增强。
set -euo pipefail

SLUG="${SLUG:?SLUG 未设置（ew6000gx|x60new|x30epro|rgx30e|be72pro）}"
SRC="${SOURCE_ROOT:-${1:-openwrt}}"
[ -d "$SRC" ] || { echo "::error::源码树不存在: $SRC"; exit 1; }
# 全程用绝对路径：后面会 cd 到设备包目录里铺 files/，相对路径会写错位置
SRC="$(cd "$SRC" && pwd)"
PACK="$(pwd)/devices-pack/$SLUG"

[ -d "$PACK" ] || { echo "::error::找不到设备包 $PACK"; exit 1; }
[ -d "$SRC/target/linux/mediatek" ] || { echo "::error::$SRC 不是 OpenWrt 源码树（缺 target/linux/mediatek）"; exit 1; }

# ---------------------------------------------------------------------------
# 机型元数据：网口期望 + SSID 前缀（唯一来源）
#   EW-6000GX PRO：MT7531 lan1-4 + gmac1(Airoha EN8811H 2.5G) eth1 作 WAN
#   RG-X60 New   ：MT7531 lan1-3 + eth1 作 WAN
#   RG-X30E Pro  ：MT7531 wan + lan1-3
#   RG-X30E      ：MT7531 wan + lan1-3
#   RG-BE72 Pro  ：RTL837x(swconfig) lan1-4 + eth2.2/eth1 作 LAN，eth2.1 作 WAN
# ---------------------------------------------------------------------------
case "$SLUG" in
  ew6000gx) LAN_EXPECT='lan1 lan2 lan3 lan4';                    WAN_EXPECT='eth1';   SSID_BASE='EW6000GX' ;;
  x60new)   LAN_EXPECT='lan1 lan2 lan3';                         WAN_EXPECT='eth1';   SSID_BASE='X60NEW' ;;
  x30epro)  LAN_EXPECT='lan1 lan2 lan3';                         WAN_EXPECT='wan';    SSID_BASE='X30EPRO' ;;
  rgx30e)   LAN_EXPECT='lan1 lan2 lan3';                         WAN_EXPECT='wan';    SSID_BASE='X30E' ;;
  be72pro)  LAN_EXPECT='lan1 lan2 lan3 lan4 eth2.2 eth1';        WAN_EXPECT='eth2.1'; SSID_BASE='BE72PRO' ;;
  *) echo "::error::不支持的 SLUG=$SLUG"; exit 1 ;;
esac

DEV=$(sed -n 's/^CONFIG_TARGET_DEVICE_mediatek_filogic_DEVICE_\(.*\)=y$/\1/p' "$PACK/config.fragment" | head -1 | tr -d '\r')
[ -n "$DEV" ] || { echo "::error::$PACK/config.fragment 里没有 CONFIG_TARGET_DEVICE_...=y"; exit 1; }
echo ">>> SLUG=$SLUG DEVICE=$DEV"

# ---------------------------------------------------------------------------
# 1) 设备包注入（DTS / filogic.mk 设备块 / files 覆盖层含 board.d 网口映射）
# ---------------------------------------------------------------------------
python3 scripts/apply-pack.py "$SRC" "$SLUG"

# 兼容老版 apply-pack.py：mt798x-action / mt798x-6.6 的版本会把 files/ 覆盖层铺到
# 源码根（<src>/etc/board.d），而构建只读 <src>/files/...，结果 board.d 从不执行、
# WAN 直接消失。这里统一自己铺一遍，幂等且不依赖各仓库脚本版本。
if [ -d "$PACK/files" ]; then
  ( cd "$PACK/files" && find . -type f -print0 | while IFS= read -r -d '' f; do
      dst="$SRC/files/${f#./}"
      mkdir -p "$(dirname "$dst")"
      cp -f "$f" "$dst"
    done )
  find "$SRC/files/etc/board.d" -type f -exec chmod 755 {} + 2>/dev/null || true
  find "$SRC/files/etc/uci-defaults" -type f -exec chmod 755 {} + 2>/dev/null || true
  echo ">>> 覆盖层就绪：$SRC/files（$(find "$SRC/files" -type f | wc -l) 个文件）"
fi

# ---------------------------------------------------------------------------
# 2) BE72 Pro 专用 RTL837x 交换芯片驱动（包内 packages/ 可选）
# ---------------------------------------------------------------------------
if [ -d "$PACK/packages" ]; then
  mkdir -p "$SRC/package/kernel"
  cp -r "$PACK"/packages/* "$SRC/package/kernel/"
  echo ">>> 已注入交换芯片驱动: $(ls "$PACK/packages" | tr '\n' ' ')"
fi

# ---------------------------------------------------------------------------
# 2.5) 去掉 factory 产物：这 5 台都是多分区 U-Boot，升级/首次刷入都用 sysupgrade
#      （RG-X30E 的 stock 布局包里带 `IMAGES += factory.bin`，必须摘掉）
# ---------------------------------------------------------------------------
python3 - "$SRC" "$DEV" <<'PY'
import io
import re
import sys

src, dev = sys.argv[1], sys.argv[2]
p = src + '/target/linux/mediatek/image/filogic.mk'
s = io.open(p, encoding='utf-8', newline='').read()
start = 'define Device/' + dev + '\n'
assert start in s, 'filogic.mk 缺 ' + start.strip()


def block(text):
    i = text.index(start)
    j = text.index('TARGET_DEVICES += ' + dev, i)
    return i, j


i, j = block(s)
blk = s[i:j]
kept = [ln for ln in blk.split('\n')
        if not re.match(r'\s*IMAGES \+= factory\.bin\s*$', ln)
        and not re.match(r'\s*IMAGE/factory\.bin\s*:=', ln)]
new = '\n'.join(kept)
if new != blk:
    s = s[:i] + new + s[j:]
    io.open(p, 'w', encoding='utf-8', newline='').write(s)
    print('>>> 已从 %s 摘掉 factory 产物定义' % dev)

i, j = block(s)
assert 'factory' not in s[i:j], dev + ' 仍残留 factory 产物定义'
print('✔ factory 已移除（多分区 U-Boot：只发 sysupgrade）')
PY

# ---------------------------------------------------------------------------
# 3) 首启无线：生成/修正双频 AP（band 驱动，绝不写死 path/phy）
# ---------------------------------------------------------------------------
mkdir -p "$SRC/files/etc/uci-defaults"
cat > "$SRC/files/etc/uci-defaults/97-ruijie-wifi" <<'EOS'
#!/bin/sh
# Ruijie 首启无线：确保 /etc/config/wireless 存在、双频 AP 启用、SSID 按机型命名
# 设计：不写死 path/phy（不同内核/机型探测出来的名字不一样），一律按 band 判断
SSID_BASE='@SSID@'

# 等无线模块就绪（kmodloader 已加载，这里只做兜底）
i=0
while [ "$i" -lt 10 ]; do
	[ -n "$(ls -A /sys/class/ieee80211 2>/dev/null)" ] && break
	i=$((i + 1)); sleep 1
done

[ -f /etc/config/wireless ] || wifi config >/dev/null 2>&1 || true
[ -f /etc/config/wireless ] || exit 0

radios=$(uci -q show wireless | grep -c '=wifi-device$' || true)
[ "${radios:-0}" -gt 0 ] || exit 0

uci -q show wireless | sed -n 's/^wireless\.\([^.=]*\)=wifi-device$/\1/p' | while read -r r; do
	[ -n "$r" ] || continue
	band=$(uci -q get "wireless.$r.band")
	if [ -z "$band" ]; then
		case "$(uci -q get "wireless.$r.hwmode")" in
			11a|11ac|11ax|11be) band=5g ;;
			*) band=2g ;;
		esac
	fi
	suffix=2.4G
	[ "$band" = "5g" ] && suffix=5G
	[ "$band" = "6g" ] && suffix=6G

	uci -q set "wireless.$r.disabled=0"
	uci -q set "wireless.$r.country=CN"
	uci -q set "wireless.$r.ieee80211d=1"
	uci -q set "wireless.$r.cell_density=0"
	case "$band" in
	5g)
		# CN 法规下 5G 的 160MHz 只能落在 36-64（含 DFS 52-64）。不开 DFS 时
		# hostapd 找不到可用 160MHz 信道会直接启动失败 —— 表现就是
		# “2.4G 正常、5G 打不开”。这里固定 36 信道 + HE80，保证 5G 能起来。
		uci -q set "wireless.$r.channel=36"
		uci -q set "wireless.$r.htmode=HE80"
		uci -q set "wireless.$r.ieee80211h=0"
		;;
	6g)
		uci -q set "wireless.$r.channel=auto"
		uci -q set "wireless.$r.htmode=HE160"
		;;
	*)
		uci -q set "wireless.$r.channel=auto"
		uci -q set "wireless.$r.htmode=HE40"
		;;
	esac
	uci -q commit wireless

	# 该 radio 若没有任何 AP，补一个开放 AP（首启可用，密码请自行设置）
	if ! uci -q show wireless | grep -q "\.device='$r'"; then
		uci -q add wireless wifi-iface >/dev/null
		uci -q set "wireless.@wifi-iface[-1].device=$r"
		uci -q set "wireless.@wifi-iface[-1].network=lan"
		uci -q set "wireless.@wifi-iface[-1].mode=ap"
		uci -q set "wireless.@wifi-iface[-1].encryption=none"
		uci -q set "wireless.@wifi-iface[-1].disabled=0"
		uci -q commit wireless
	fi

	idx=0
	while uci -q get "wireless.@wifi-iface[$idx]" >/dev/null 2>&1; do
		if [ "$(uci -q get "wireless.@wifi-iface[$idx].device")" = "$r" ]; then
			uci -q set "wireless.@wifi-iface[$idx].ssid=${SSID_BASE}-${suffix}"
			uci -q set "wireless.@wifi-iface[$idx].network=lan"
			uci -q set "wireless.@wifi-iface[$idx].disabled=0"
		fi
		idx=$((idx + 1))
	done
	uci -q commit wireless
done

exit 0
EOS
sed -i "s/@SSID@/$SSID_BASE/" "$SRC/files/etc/uci-defaults/97-ruijie-wifi"
chmod 755 "$SRC/files/etc/uci-defaults/97-ruijie-wifi"
echo ">>> 首启无线脚本就绪：97-ruijie-wifi（SSID 前缀 $SSID_BASE）"

# 5G 修复：老配置里 5g 是 HE160+auto（CN 下没有合法 160MHz 信道），升级保留配置
# 时 97 号脚本不会再跑，所以单独放一个 98 号，保证刷完新固件后 5G 也能起来。
cat > "$SRC/files/etc/uci-defaults/98-ruijie-wifi-5g" <<'EOS'
#!/bin/sh
# 把 5G 从 HE160/channel=auto 修正为 36 信道 + HE80（幂等）
[ -f /etc/config/wireless ] || exit 0
for r in $(uci -q show wireless | sed -n 's/^wireless\.\([^.=]*\)=wifi-device$/\1/p'); do
	[ "$(uci -q get "wireless.$r.band")" = "5g" ] || continue
	uci -q set "wireless.$r.channel=36"
	uci -q set "wireless.$r.htmode=HE80"
	uci -q set "wireless.$r.ieee80211h=0"
	uci -q set "wireless.$r.disabled=0"
done
uci -q commit wireless
exit 0
EOS
chmod 755 "$SRC/files/etc/uci-defaults/98-ruijie-wifi-5g"
echo ">>> 5G 修正脚本就绪：98-ruijie-wifi-5g"

# ---------------------------------------------------------------------------
# 4) 硬断言：网口映射 / 设备块 / DTS / 无线配置
# ---------------------------------------------------------------------------
NWO="$SRC/files/etc/board.d"
if ! grep -rqs "ucidef_set_interfaces_lan_wan \"$LAN_EXPECT\" \"$WAN_EXPECT\"" "$NWO"; then
  echo "::error::网口映射与预期不符：期望 LAN=\"$LAN_EXPECT\" WAN=\"$WAN_EXPECT\""
  echo "---- 实际 board.d 内容 ----"
  grep -rn "ucidef_set_interfaces_lan_wan" "$NWO" || echo "（没有找到任何 lan_wan 配置）"
  exit 1
fi
echo "✔ 网口映射: LAN=\"$LAN_EXPECT\" WAN=\"$WAN_EXPECT\""

python3 - "$SRC" "$DEV" "$SLUG" <<'PY'
import io
import os
import re
import sys

src, dev, slug = sys.argv[1], sys.argv[2], sys.argv[3]
start = 'define Device/' + dev + '\n'
mkp = os.path.join(src, 'target/linux/mediatek/image/filogic.mk')
mk = io.open(mkp, encoding='utf-8').read()
assert start in mk, 'filogic.mk 缺 ' + start.strip()
end = mk.index('TARGET_DEVICES += ' + dev, mk.index(start))
blk = mk[mk.index(start):end]

# WiFi 驱动/固件必须写进设备块，避免 kconfig 静默丢包
if slug == 'be72pro':
    need = ('kmod-mt7992-firmware', 'mt7988-wo-firmware')
else:
    need = ('kmod-mt7915e',)
    need += ('kmod-mt7981-firmware', 'mt7981-wo-firmware') if slug in ('x30epro', 'rgx30e') else ('kmod-mt7986-firmware', 'mt7986-wo-firmware')
for token in need:
    assert token in blk, '%s 的 DEVICE_PACKAGES 缺 %s' % (dev, token)
print('✔ 设备块 WiFi 依赖:', ' '.join(need))

# DTS 落地 + 带 WiFi 节点与校准（否则驱动起来了也没有合法射频参数）
#   MT7986/MT7981：&wifi 节点（mainline mt76）
#   MT7988（BE72）：PCIe 挂 mt7992，nvmem 指向 factory eeprom
dts = None
for line in blk.splitlines():
    line = line.strip()
    if line.startswith('DEVICE_DTS :='):
        dts = line.split(':=', 1)[1].strip()
        break
assert dts, dev + ' 没有 DEVICE_DTS'
dtsdir = os.path.join(src, 'target/linux/mediatek/dts')
path = os.path.join(dtsdir, dts + '.dts')
assert os.path.exists(path), 'DTS 未落地: ' + path

text = ''
seen = set()
queue = [path]
while queue and len(seen) < 40:
    cur = queue.pop(0)
    if cur in seen or not os.path.exists(cur):
        continue
    seen.add(cur)
    body = io.open(cur, encoding='utf-8', errors='ignore').read()
    text += body
    for inc in re.findall(r'#include\s+["<]([^">]+)[">]', body):
        nxt = os.path.join(dtsdir, inc)
        if os.path.exists(nxt):
            queue.append(nxt)

has_wifi = any(t in text for t in ('&wifi', 'wifi {', 'wifi@', 'mt7915', 'mt7992', 'mt7990'))
assert has_wifi, dts + ' 及包含的 dtsi 里没有 WiFi 节点'
assert ('eeprom' in text) or ('nvmem-cells' in text) or ('calibration' in text), dts + ' 没有 WiFi 校准(eeprom) 引用'
print('✔ DTS:', dts, '（含 WiFi 节点与校准，展开 %d 个文件）' % len(seen))
PY

WIFI_SH="$SRC/files/etc/uci-defaults/97-ruijie-wifi"
[ -x "$WIFI_SH" ] || { echo "::error::97-ruijie-wifi 不存在或不可执行"; exit 1; }
grep -q 'htmode=HE80' "$WIFI_SH" || { echo "::error::无线脚本 5G 未使用 HE80（HE160 在 CN 下起不来）"; exit 1; }
grep -q 'channel=36' "$WIFI_SH" || { echo "::error::无线脚本 5G 未固定 36 信道"; exit 1; }
FIX5G="$SRC/files/etc/uci-defaults/98-ruijie-wifi-5g"
[ -x "$FIX5G" ] || { echo "::error::缺少 98-ruijie-wifi-5g（升级场景 5G 不会被修正）"; exit 1; }
grep -q 'htmode=HE80' "$FIX5G" || { echo "::error::98 号脚本未修正 htmode"; exit 1; }
grep -q 'country=CN' "$WIFI_SH" || { echo "::error::无线脚本缺 CN 国码"; exit 1; }
grep -q "SSID_BASE='$SSID_BASE'" "$WIFI_SH" || { echo "::error::无线脚本 SSID 前缀不对"; exit 1; }
echo "✔ 无线脚本断言通过"

# board.d 覆盖脚本必须可执行，否则 board_detect 直接跳过 → WAN 缺失
chmod 755 "$NWO"/* 2>/dev/null || true

echo "✔ $SLUG 注入完成：$DEV（网口 + 双频无线 + 无线增强预留）"
