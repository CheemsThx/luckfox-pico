# DW-TLY-V015：8 位 eMMC 实验候选；U17 VCCQ 电压与焊球映射须硬件签核后才能烧录。
# 镜像不预置 Wi-Fi 凭据，由设备端受控配网。
#!/bin/bash

#################################################
# 	Board Config
#################################################
export LF_ORIGIN_BOARD_CONFIG=BoardConfig-EMMC-Buildroot-RV1106_DW_TLY_V015-IPC.mk
# Target CHIP
export RK_CHIP=rv1106

# app config
export RK_APP_TYPE=RKIPC_RV1106

# Config CMA size in environment
export RK_BOOTARGS_CMA_SIZE="66M"

# Kernel dts
export RK_KERNEL_DTS=rv1106g-dw-tly-v015.dts

#################################################
#	BOOT_MEDIUM
#################################################

# Target boot medium
export RK_BOOT_MEDIUM=emmc

# Uboot defconfig fragment
export RK_UBOOT_DEFCONFIG_FRAGMENT="rk-emmc.config rv1106-luckfox-rgb-reset.config"

# specify post.sh for delete/overlay files
# export RK_PRE_BUILD_OEM_SCRIPT=rv1103-spi_nor-post.sh

# config partition in environment
# RK_PARTITION_CMD_IN_ENV format:
#     <partdef>[,<partdef>]
#       <partdef> := <size>[@<offset>](part-name)
# Note:
#   If the first partition offset is not 0x0, it must be added. Otherwise, it needn't adding.
export RK_PARTITION_CMD_IN_ENV="32K(env),512K@32K(idblock),256K(uboot),32M(boot),512M(oem),256M(userdata),6G(rootfs)"

# config partition's filesystem type (squashfs is readonly)
# emmc:    squashfs/ext4
# nand:    squashfs/ubifs
# spi nor: squashfs/jffs2
# RK_PARTITION_FS_TYPE_CFG format:
#     AAAA:/BBBB/CCCC@ext4
#         AAAA ----------> partition name
#         /BBBB/CCCC ----> partition mount point
#         ext4 ----------> partition filesystem type
export RK_PARTITION_FS_TYPE_CFG=rootfs@IGNORE@ext4,userdata@/userdata@ext4,oem@/oem@ext4

# config filesystem compress (Just for squashfs or ubifs)
# squashfs: lz4/lzo/lzma/xz/gzip, default xz
# ubifs:    lzo/zlib, default lzo
# export RK_SQUASHFS_COMP=xz
# export RK_UBIFS_COMP=lzo

#################################################
#	TARGET_ROOTFS
#################################################

# Target rootfs
export LF_TARGET_ROOTFS=buildroot

# Buildroot defconfig
export RK_BUILDROOT_DEFCONFIG=luckfox_pico_w_defconfig

#################################################
# 	Defconfig
#################################################

# Target arch
export RK_ARCH=arm

# Target Toolchain Cross Compile
export RK_TOOLCHAIN_CROSS=arm-rockchip830-linux-uclibcgnueabihf

#misc image
export RK_MISC=wipe_all-misc.img

# Uboot defconfig
export RK_UBOOT_DEFCONFIG=luckfox_rv1106_uboot_defconfig

# Kernel defconfig
export RK_KERNEL_DEFCONFIG=luckfox_rv1106_linux_defconfig

# Kernel defconfig fragment
# rv1106-v015.config 打开 CONFIG_ROCKCHIP_GRF，使 grf.c 在 postcore_initcall
# 阶段清掉 RV1106 GPIO3 SDMMC0 的 force_jtag 占用（V015 的 Wi-Fi SDIO 就跑在
# 这个控制器/引脚组上）。只加在 V015，共享的 rv1106-bt.config 不改，其他板型不受影响。
export RK_KERNEL_DEFCONFIG_FRAGMENT="rv1106-bt.config rv1106-v015.config"

# Config sensor IQ files
# RK_CAMERA_SENSOR_IQFILES format:
#     "iqfile1 iqfile2 iqfile3 ..."
# ./build.sh media and copy <SDK root dir>/output/out/media_out/isp_iqfiles/$RK_CAMERA_SENSOR_IQFILES
export RK_CAMERA_SENSOR_IQFILES="sc4336_OT01_40IRC_F16.json sc3336_CMK-OT2119-PC1_30IRC-F16.json mis5001_CMK-OT2115-PC1_30IRC-F16.json"
#export RK_CAMERA_SENSOR_IQFILES="sc4336_OT01_40IRC_F16.json sc3336_CMK-OT2119-PC1_30IRC-F16.json sc530ai_CMK-OT2115-PC1_30IRC-F16.json"

# Config sensor lens CAC calibrattion bin files
export RK_CAMERA_SENSOR_CAC_BIN="CAC_sc4336_OT01_40IRC_F16"
#export RK_CAMERA_SENSOR_CAC_BIN="CAC_sc4336_OT01_40IRC_F16 CAC_sc530ai_CMK-OT2115-PC1_30IRC-F16"

# build ipc web backend
#export RK_APP_IPCWEB_BACKEND=y

# enable install app to oem partition
export RK_BUILD_APP_TO_OEM_PARTITION=y

# enable rockchip test
export RK_ENABLE_ROCKCHIP_TEST=y

# enable rockchip wifi
export RK_ENABLE_WIFI=y
export RK_ENABLE_WIFI_CHIP=AIC8800DC

# config wifi ssid and passwd

#################################################
#  PRE and POST
#################################################

# specify pre.sh for delete/overlay files
export RK_PRE_BUILD_OEM_SCRIPT=luckfox-buildroot-oem-pre.sh

# specify post.sh for delete/overlay files
export RK_PRE_BUILD_USERDATA_SCRIPT=luckfox-userdata-pre.sh

# V015 板级后处理：关闭 SMB/NMB 开机自启，并把 rkipc 默认自启改为显式开关。
# 仅本板选用；共享 Buildroot defconfig 与其他板型 BoardConfig 均不改。
export RK_POST_BUILD_SCRIPT=dw-tly-v015-post.sh

# declare overlay directory
# 末尾的 overlay-dw-tly-v015 只含 V015 专属 /etc/init.d/S21appinit（rkipc 启动门控），
# 置于末位以确保覆盖共享 build.sh 生成的那一份。
export RK_POST_OVERLAY="overlay-luckfox-config overlay-luckfox-buildroot-init overlay-luckfox-buildroot-shadow overlay-luckfox-buildroot-rgb overlay-luckfox-wifibt-firmware overlay-dw-tly-v015"
