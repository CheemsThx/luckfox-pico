#!/bin/bash

#################################################
# 	Board Config — Ultra + SPI NAND (基于 EMMC Ultra 板级)
#################################################
export LF_ORIGIN_BOARD_CONFIG=BoardConfig-SPI_NAND-Buildroot-RV1106_Luckfox_Pico_Ultra-IPC.mk
# Target CHIP
export RK_CHIP=rv1106

# app config
export RK_APP_TYPE=RKIPC_RV1106

# Config CMA size in environment
export RK_BOOTARGS_CMA_SIZE="66M"

# Kernel dts
export RK_KERNEL_DTS=rv1106g-luckfox-pico-ultra-spi-nand.dts

#################################################
#	BOOT_MEDIUM
#################################################

# Target boot medium
export RK_BOOT_MEDIUM=spi_nand

# Uboot defconfig fragment
export RK_UBOOT_DEFCONFIG_FRAGMENT="rk-sfc.config rv1106-luckfox-rgb-reset.config"

# config partition in environment
# W25N02KVZEIR = 256MB (2Gbit)，分区合计约 255MB
export RK_PARTITION_CMD_IN_ENV="256K(env),256K@256K(idblock),512K(uboot),4M(boot),30M(oem),10M(userdata),210M(rootfs)"

# SPI NAND 使用 ubifs
export RK_PARTITION_FS_TYPE_CFG=rootfs@IGNORE@ubifs,oem@/oem@ubifs,userdata@/userdata@ubifs

#################################################
#	TARGET_ROOTFS
#################################################

export LF_TARGET_ROOTFS=buildroot

# WiFi/BT 版本 rootfs
export RK_BUILDROOT_DEFCONFIG=luckfox_pico_w_defconfig

#################################################
# 	Defconfig
#################################################

export RK_ARCH=arm
export RK_TOOLCHAIN_CROSS=arm-rockchip830-linux-uclibcgnueabihf
export RK_MISC=wipe_all-misc.img
export RK_UBOOT_DEFCONFIG=luckfox_rv1106_uboot_defconfig
export RK_KERNEL_DEFCONFIG=luckfox_rv1106_linux_defconfig
export RK_KERNEL_DEFCONFIG_FRAGMENT=rv1106-bt.config

export RK_CAMERA_SENSOR_IQFILES="sc4336_OT01_40IRC_F16.json sc3336_CMK-OT2119-PC1_30IRC-F16.json mis5001_CMK-OT2115-PC1_30IRC-F16.json"
export RK_CAMERA_SENSOR_CAC_BIN="CAC_sc4336_OT01_40IRC_F16"

export RK_BUILD_APP_TO_OEM_PARTITION=y
export RK_ENABLE_ROCKCHIP_TEST=y

export RK_ENABLE_WIFI=y
export RK_ENABLE_WIFI_CHIP=AIC8800DC

export LF_WIFI_SSID="Your wifi ssid"
export LF_WIFI_PSK="Your wifi password"

#################################################
#  PRE and POST
#################################################

export RK_PRE_BUILD_OEM_SCRIPT=luckfox-buildroot-oem-pre.sh
export RK_PRE_BUILD_USERDATA_SCRIPT=luckfox-userdata-pre.sh
export RK_POST_OVERLAY="overlay-luckfox-config overlay-luckfox-buildroot-init overlay-luckfox-buildroot-shadow overlay-luckfox-buildroot-rgb overlay-luckfox-wifibt-firmware"
