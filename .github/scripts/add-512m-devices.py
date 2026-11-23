#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""派生三台 MT7986 512MB NAND 机型（在当前 openwrt 源码根执行）。

机型来源：
  xiaomi_redmi-router-ax6000-512rom / netcore_n60-pro-512rom
      → 取自 tvliving/immortalwrt-mt798x-action 的 openwrt/scripts/05-add-missing-devices.sh
        （dts 由现成 dts 派生，只改 model / compatible / ubi 分区大小）
  ruijie_rg-x60-pro-512rom
      → 上游没有 512M 版，按同一规则从 ruijie_rg-x60-pro 派生

三台的 ubi 都按 512MiB 器件边界收口：
  AX6000   ubi 起点 0x600000 → 0x1EA00000（490.0 MiB）
  N60 Pro  ubi 起点 0x0580000 → 0x1EA80000（490.5 MiB）
  X60 Pro  ubi 起点 0x680000 → 0x1E980000（489.5 MiB）

全部幂等：dts 已存在、filogic.mk 已有同名 define、02_network 已有条目都跳过。
"""

import io
import os
import sys

DTS = 'target/linux/mediatek/dts'
MK = 'target/linux/mediatek/image/filogic.mk'
NW = 'target/linux/mediatek/filogic/base-files/etc/board.d/02_network'

# dev, 源 dts, 新 dts, 旧 model, 新 model, 旧 compatible, 新 compatible, 旧 ubi reg, 新 ubi reg
DEVS = [
    ('xiaomi_redmi-router-ax6000-512rom',
     'mt7986a-xiaomi-redmi-router-ax6000-ubootmod.dts',
     'mt7986a-xiaomi-redmi-router-ax6000-512rom.dts',
     'model = "Xiaomi Redmi Router AX6000 (OpenWrt U-Boot layout)";',
     'model = "Xiaomi Redmi Router AX6000 (OpenWrt U-Boot layout, 512MB NAND)";',
     'compatible = "xiaomi,redmi-router-ax6000-ubootmod", "mediatek,mt7986a";',
     'compatible = "xiaomi,redmi-router-ax6000-512rom", "mediatek,mt7986a";',
     'reg = <0x600000 0x6e00000>;',
     'reg = <0x600000 0x1EA00000>;'),
    ('netcore_n60-pro-512rom',
     'mt7986a-netcore-n60-pro.dts',
     'mt7986a-netcore-n60-pro-512rom.dts',
     'model = "Netcore N60 Pro";',
     'model = "Netcore N60 Pro (512MB NAND)";',
     'compatible = "netcore,n60-pro", "mediatek,mt7986a";',
     'compatible = "netcore,n60-pro-512rom", "mediatek,mt7986a";',
     'reg = <0x0580000 0x7280000>;',
     'reg = <0x0580000 0x1EA80000>;'),
    ('ruijie_rg-x60-pro-512rom',
     'mt7986a-ruijie-rg-x60-pro.dts',
     'mt7986a-ruijie-rg-x60-pro-512rom.dts',
     'model = "Ruijie RG-X60 Pro";',
     'model = "Ruijie RG-X60 Pro (512MB NAND)";',
     'compatible = "ruijie,rg-x60-pro", "mediatek,mt7986a";',
     'compatible = "ruijie,rg-x60-pro-512rom", "mediatek,mt7986a";',
     'reg = <0x680000 0x3f00000>;',
     'reg = <0x680000 0x1E980000>;'),
]

BLOCKS = {
    'xiaomi_redmi-router-ax6000-512rom': """
define Device/xiaomi_redmi-router-ax6000-512rom
  DEVICE_VENDOR := Xiaomi
  DEVICE_MODEL := Redmi Router AX6000
  DEVICE_VARIANT := (OpenWrt U-Boot layout, 512MB NAND)
  DEVICE_DTS := mt7986a-xiaomi-redmi-router-ax6000-512rom
  DEVICE_DTS_DIR := ../dts
  DEVICE_PACKAGES := kmod-leds-ws2812b kmod-mt7915e kmod-mt7986-firmware mt7986-wo-firmware
  UBINIZE_OPTS := -E 5
  BLOCKSIZE := 128k
  PAGESIZE := 2048
  KERNEL_INITRAMFS_SUFFIX := -recovery.itb
  ARTIFACTS := initramfs-factory.ubi
  ARTIFACT/initramfs-factory.ubi := append-image-stage initramfs-recovery.itb | ubinize-kernel
  IMAGE/sysupgrade.bin := sysupgrade-tar | append-metadata
endef
TARGET_DEVICES += xiaomi_redmi-router-ax6000-512rom
""",
    'netcore_n60-pro-512rom': """
define Device/netcore_n60-pro-512rom
  DEVICE_VENDOR := Netcore
  DEVICE_MODEL := N60 Pro
  DEVICE_VARIANT := (512MB NAND)
  DEVICE_DTS := mt7986a-netcore-n60-pro-512rom
  DEVICE_DTS_DIR := ../dts
  UBINIZE_OPTS := -E 5
  BLOCKSIZE := 128k
  PAGESIZE := 2048
  DEVICE_PACKAGES := kmod-mt7915e kmod-mt7986-firmware mt7986-wo-firmware kmod-usb3 automount kmod-usb-ledtrig-usbport
  IMAGE/sysupgrade.bin := sysupgrade-tar | append-metadata
endef
TARGET_DEVICES += netcore_n60-pro-512rom
""",
    'ruijie_rg-x60-pro-512rom': """
define Device/ruijie_rg-x60-pro-512rom
  DEVICE_VENDOR := Ruijie
  DEVICE_MODEL := RG-X60 Pro
  DEVICE_VARIANT := (512MB NAND)
  DEVICE_DTS := mt7986a-ruijie-rg-x60-pro-512rom
  DEVICE_DTS_DIR := ../dts
  UBINIZE_OPTS := -E 5
  BLOCKSIZE := 128k
  PAGESIZE := 2048
  DEVICE_PACKAGES := kmod-mt7915e kmod-mt7986-firmware mt7986-wo-firmware
  IMAGE/sysupgrade.bin := sysupgrade-tar | append-metadata
endef
TARGET_DEVICES += ruijie_rg-x60-pro-512rom
""",
}


def load(p):
    return io.open(p, encoding='utf-8', newline='').read()


def save(p, s):
    io.open(p, 'w', encoding='utf-8', newline='').write(s)


def die(msg):
    print('::error::%s' % msg)
    sys.exit(1)


def chk(path):
    if not os.path.isfile(path):
        die('找不到 %s（当前目录不是 openwrt 源码根？）' % path)


chk(MK)
chk(NW)


def derive_dts():
    for dev, sname, dname, omodel, nmodel, ocomp, ncomp, oubi, nubi in DEVS:
        src, dst = os.path.join(DTS, sname), os.path.join(DTS, dname)
        chk(src)
        t = load(src)
        if nubi in t and ncomp in t:
            print('· dts %s 已派生，跳过' % dname)
            continue
        assert t.count(omodel) == 1, '%s 的 model 锚点异常（%d 处）' % (dev, t.count(omodel))
        assert t.count(ocomp) == 1, '%s 的 compatible 锚点异常（%d 处）' % (dev, t.count(ocomp))
        assert t.count(oubi) == 1, '%s 的 ubi 分区锚点异常（%d 处）' % (dev, t.count(oubi))
        save(dst, t.replace(omodel, nmodel, 1).replace(ocomp, ncomp, 1).replace(oubi, nubi, 1))
        fin = load(dst)
        if ncomp not in fin or nubi not in fin:
            die('%s：dts 替换失败' % dev)
        print('✔ dts %s（%s → %s）' % (dname, oubi, nubi))


def append_blocks():
    mk = load(MK)
    for dev, _, _, _, _, _, _, _, _ in DEVS:
        marker = 'define Device/%s\n' % dev
        if marker in mk:
            print('· filogic.mk 已有 %s，跳过' % dev)
            continue
        mk += BLOCKS[dev]
        print('✔ filogic.mk 追加 %s' % dev)
    save(MK, mk)
    mk = load(MK)
    for dev, _, _, _, _, _, _, _, _ in DEVS:
        if 'define Device/%s\n' % dev not in mk:
            die('filogic.mk 缺少 %s' % dev)
        if 'TARGET_DEVICES += %s\n' % dev not in mk:
            die('filogic.mk 缺少 TARGET_DEVICES += %s' % dev)


def patch_network():
    t = load(NW)

    # netcore,n60-pro 后面补一行 512rom（同组网口映射）
    if 'netcore,n60-pro-512rom' not in t:
        a = '\tnetcore,n60-pro|\\\n'
        if t.count(a) != 1:
            die('02_network 里 netcore,n60-pro 锚点异常（%d 处）' % t.count(a))
        t = t.replace(a, a + '\tnetcore,n60-pro-512rom|\\\n', 1)
        print('✔ 02_network: netcore,n60-pro-512rom')

    # AX6000 512rom：接口映射组 + MAC 组各补一行
    if 'xiaomi,redmi-router-ax6000-512rom' not in t:
        a_if = ('\txiaomi,redmi-router-ax6000-stock|\\\n'
                '\txiaomi,redmi-router-ax6000-ubootmod)\n'
                '\t\tucidef_set_interfaces_lan_wan "lan2 lan3 lan4" wan\n')
        n_if = ('\txiaomi,redmi-router-ax6000-stock|\\\n'
                '\txiaomi,redmi-router-ax6000-ubootmod|\\\n'
                '\txiaomi,redmi-router-ax6000-512rom)\n'
                '\t\tucidef_set_interfaces_lan_wan "lan2 lan3 lan4" wan\n')
        if t.count(a_if) != 1:
            die('02_network 里 ax6000 接口组锚点异常（%d 处）' % t.count(a_if))
        t = t.replace(a_if, n_if, 1)

        a_mac = ('\txiaomi,redmi-router-ax6000-stock|\\\n'
                 '\txiaomi,redmi-router-ax6000-ubootmod)\n'
                 '\t\twan_mac=$(mtd_get_mac_ascii Bdata ethaddr_wan)\n')
        n_mac = ('\txiaomi,redmi-router-ax6000-stock|\\\n'
                 '\txiaomi,redmi-router-ax6000-ubootmod|\\\n'
                 '\txiaomi,redmi-router-ax6000-512rom)\n'
                 '\t\twan_mac=$(mtd_get_mac_ascii Bdata ethaddr_wan)\n')
        if t.count(a_mac) != 1:
            die('02_network 里 ax6000 MAC 组锚点异常（%d 处）' % t.count(a_mac))
        t = t.replace(a_mac, n_mac, 1)
        print('✔ 02_network: xiaomi,redmi-router-ax6000-512rom（接口 + MAC）')

    save(NW, t)
    t = load(NW)
    if 'netcore,n60-pro-512rom|' not in t:
        die('02_network 缺少 netcore,n60-pro-512rom')
    if t.count('xiaomi,redmi-router-ax6000-512rom)') != 2:
        die('02_network 里 ax6000 512rom 只补到 %d 处（应为 2）' % t.count('xiaomi,redmi-router-ax6000-512rom)'))
    if 'ruijie,rg-x60-pro*' not in t:
        die('02_network 里 ruijie,rg-x60-pro* 通配分支不存在，X60 Pro 512rom 会没有网口映射')
    print('✔ 02_network 校验通过（X60 Pro 512rom 走 ruijie,rg-x60-pro* 通配）')


def main():
    derive_dts()
    append_blocks()
    patch_network()
    print('三台 512MB NAND 机型派生完成：')
    for dev, _, dname, _, _, _, _, _, nubi in DEVS:
        print('  · %-34s %s  ubi %s' % (dev, dname, nubi))


if __name__ == '__main__':
    main()