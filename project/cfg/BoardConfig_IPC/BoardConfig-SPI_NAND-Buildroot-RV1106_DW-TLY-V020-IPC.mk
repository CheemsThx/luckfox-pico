# DW-TLY-V020 板级。从 V014 的 BoardConfig-SPI_NAND-Buildroot-RV1106_Luckfox_Pico_Ultra-IPC.mk
# 逐行复制而来，只改了下面标注 [V020] 的几处。V014 那份保持原样、可继续构建。
#
# V014 与 V020 的板级差异全部落在 DTS（rv1106g-dw-tly-v020.dts）里，
# 分区表 / rootfs / WiFi / overlay / 打包流程两者一致，故不改。
#
# 切板：./build.sh lunch 重写 .BoardConfig.mk 符号链接，不需要改动任何文件。
#
# [V014 遗留备注] RK_ENABLE_RECOVERY 关闭的原因：sysdrv Makefile RAMDISK recipe 的 tab bug。
#!/bin/bash

#################################################
# 	Board Config — DW-TLY-V020 + SPI NAND
#################################################
# [V020] 指向自身，避免与 V014 混淆
export LF_ORIGIN_BOARD_CONFIG=BoardConfig-SPI_NAND-Buildroot-RV1106_DW-TLY-V020-IPC.mk
# Target CHIP
export RK_CHIP=rv1106

# app config
export RK_APP_TYPE=RKIPC_RV1106

# Config CMA size in environment
export RK_BOOTARGS_CMA_SIZE="66M"

# Kernel dts
# [V020] 新板级 DTS。与 V014 并列存在，内容独立。
export RK_KERNEL_DTS=rv1106g-dw-tly-v020.dts

#################################################
#	BOOT_MEDIUM
#################################################

# Target boot medium
export RK_BOOT_MEDIUM=spi_nand

# Uboot defconfig fragment
# [V020] 去掉 rv1106-luckfox-rgb-reset.config：经核实它是空操作 ——
# 其唯一内容 CONFIG_LUCKFOX_EXECUTE_CMD 在整个 u-boot 源码里没有任何定义或引用，
# 只在那个 fragment 文件自身出现过。本板也无 RGB 屏。
export RK_UBOOT_DEFCONFIG_FRAGMENT="rk-sfc.config"

# config partition in environment
# W25N02KVZEIR = 256MB (2Gbit)，分区合计 255MB。改分区必须 wipe all。
# 与 V014 同型号 NAND，布局沿用。
# 实际构成：env / idblock / uboot / boot / oem / userdata / rootfs，共 6 个卷。
# **没有 misc，也没有 recovery 分区** —— 本版不交付 OTA（见下方 RK_ENABLE_RECOVERY 处）。
# userdata 只放 ini/wpa；32M（UBI 后大约 20M+）。S20linkmount 仍会 ubirsvol 扩满卷。
export RK_PARTITION_CMD_IN_ENV="256K(env),256K@256K(idblock),512K(uboot),4M(boot),30M(oem),32M(userdata),188M(rootfs)"

# SPI NAND 使用 ubifs
export RK_PARTITION_FS_TYPE_CFG=rootfs@IGNORE@ubifs,oem@/oem@ubifs,userdata@/userdata@ubifs

#################################################
#	TARGET_ROOTFS
#################################################

export LF_TARGET_ROOTFS=buildroot

# [V020] 沿用同一份 buildroot defconfig：rootfs 内容需求与 V014 相同，
# 另建一份只是复制。若 V020 将来有单独的包集需求再拆。
export RK_BUILDROOT_DEFCONFIG=luckfox_pico_ultra_spi_nand_ipc_defconfig

#################################################
# 	Defconfig
#################################################

export RK_ARCH=arm
export RK_TOOLCHAIN_CROSS=arm-rockchip830-linux-uclibcgnueabihf
# [V020] recovery / OTA 刻意关闭 —— 本版不交付 OTA。
# 保留 RK_ENABLE_RECOVERY 这一行本身作为显式开关（空值 = 关闭）。
# 它同时是 build_ota 的门控之一（build.sh:921），所以下列 OTA/recovery 变量
# 在本板恒不被读取，属死变量，已一并删除：
#   RK_MISC（被 RK_ENABLE_RECOVERY 门控，build.sh:2067）
#   RK_RECOVERY_KERNEL_DEFCONFIG_FRAGMENT
#   RK_OTA_RESOURCE（在 build_ota 的 early-return 之后，build.sh:934）
# 另注：另一个门控 RK_ENABLE_OTA 全树未被任何文件定义，故恒为假。
export RK_ENABLE_RECOVERY=
export RK_UBOOT_DEFCONFIG=luckfox_rv1106_uboot_defconfig
export RK_KERNEL_DEFCONFIG=luckfox_rv1106_linux_defconfig
# [V020] 追加板级片段：开 CONFIG_BATTERY_CW2015（U7 电量计）。
# 片段内容见 sysdrv/source/kernel/arch/arm/configs/rv1106-v020.config
export RK_KERNEL_DEFCONFIG_FRAGMENT="rv1106-bt.config rv1106-v020.config"

# U1 型号已由网表确认 = SC3336（DeviceName/FootprintName 均是），35 pin 且逐脚与
# 共享 dtsi 的 sc3336 节点一致，详见 rv1106g-dw-tly-v020.dts 里 &i2c4 的注释。
# 残余待确认的是**变体**（镜头/IR-CUT），它体现在 IQ 文件名里 —— 30IRC = 30° 红外截止。
# TODO(U1 变体): 与 BOM 核对模组具体料号后再定这两个文件，否则会挂错 IQ/CAC 参数。
export RK_CAMERA_SENSOR_IQFILES="sc3336_CMK-OT2119-PC1_30IRC-F16.json"
export RK_CAMERA_SENSOR_CAC_BIN="CAC_sc3336_CMK-OT2119-PC1_30IRC-F16"

export RK_BUILD_APP_TO_OEM_PARTITION=y
export RK_ENABLE_ROCKCHIP_TEST=y

export RK_ENABLE_WIFI=y
# AIC8800DC 是 SDIO 驱动包名；运行时按 SDIO ID 兼容 DC 与 D80/D80L，两套固件一起打包
export RK_ENABLE_WIFI_CHIP=AIC8800DC
export LF_WIFI_SSID="${LF_WIFI_SSID:-}"
export LF_WIFI_PSK="${LF_WIFI_PSK:-}"
# [V020] 蓝牙 HCI 串口编号：本板 BLE 走 uart0，而 S35wifibt / S99hciinit 把 HCI
# 写死在 /dev/ttyS1（这两处是跨板共享文件，不能为单板改）。解决办法是在 DTS 里
# 给 uart0 分配别名 serial1，使 /dev/ttyS1 == uart0。详见 rv1106g-dw-tly-v020.dts
# 顶部的 aliases 注释。上板排查蓝牙时的坑点：别再按 V014 的思路以为 ttyS1 是 uart1。

#################################################
#  PRE and POST
#################################################

# [V020] 不用共享 luckfox-buildroot-oem-pre.sh，改用 V020 专属包装脚本：
# 共享脚本会删掉 ${RK_PROJECT_PACKAGE_OEM_DIR}/usr/lib/libfreetype* 与 libiconv*，
# 而本板 RK_BUILD_APP_TO_OEM_PARTITION=y ⇒ /oem 是独立分区（mtd4），rkipc 的这两个
# 硬依赖必须在 `build_mkimg oem` 之前放回 OEM 打包目录；post 阶段补只进 rootfs 内被
# 挂载盖住的 /oem。包装脚本先跑共享脚本（保留其裁剪行为）再把两库装回。
# 共享 OEM pre 脚本、V014 及其他板型均不引用本包装脚本，行为不变。
export RK_PRE_BUILD_OEM_SCRIPT=luckfox-buildroot-v020-oem-pre.sh
export RK_PRE_BUILD_USERDATA_SCRIPT=luckfox-userdata-pre.sh
export RK_POST_BUILD_SCRIPT=luckfox-buildroot-ble-fix-post.sh
# [V020] 原样沿用。其中 overlay-luckfox-buildroot-rgb 在本板是惰性的：
# 它的 S25backlight 只在 /oem/usr/ko/pwm_bl.ko 存在时 insmod，而 DTS 里 backlight/pwm1
# 都是 disabled，驱动无处绑定。保留是为了与 V014 少一处差异；日后可去掉。
# [V020] 末尾的 overlay-luckfox-buildroot-config 承载 V020 专属
# /etc/init.d/S21appinit（rkipc 启动门控）。post_overlay 按本列表顺序 rsync
# 覆盖，故本 overlay 放在最后，确保覆盖 project/build.sh 的 __PACKAGE_OEM
# 生成的那一份 S21appinit（生成 → __RUN_POST_BUILD_SCRIPT → post_overlay →
# rootfs 成像，覆盖发生在成像之前）。
# 门控语义：默认（无 /userdata/.rkipc-enable）只跑 /oem/usr/ko/insmod_ko.sh
# 装载相机/媒体模块，不启 rkipc；有该标志文件时整条走原厂 RkLunch.sh。
# 关闭分支必须装载模块，否则 dw-rec 与 rkipc 共用的 /dev/video*、/dev/media*
# 都不会出现（20260930.2112 实测缺 video_rkcif/rkisp/mpp/rockit）。
export RK_POST_OVERLAY="overlay-luckfox-config overlay-luckfox-buildroot-init overlay-luckfox-buildroot-shadow overlay-luckfox-buildroot-rgb overlay-luckfox-wifibt-firmware overlay-luckfox-buildroot-config"
