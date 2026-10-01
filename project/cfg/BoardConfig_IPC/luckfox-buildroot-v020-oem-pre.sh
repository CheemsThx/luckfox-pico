#!/bin/bash
# [V020] V020(SPI NAND) 专属的 pre-OEM 包装脚本。
#
# 为什么需要包装层：build.sh 的 __RUN_PRE_BUILD_OEM_SCRIPT（project/build.sh:2525）在
#   __PACKAGE_OEM(:2563，把 app_out/lib 等拷进 ${RK_PROJECT_PACKAGE_OEM_DIR}/usr/lib)
# 之后、`build_mkimg oem ${RK_PROJECT_PACKAGE_OEM_DIR}`(:2572) 之前执行本脚本。
# 共享的 luckfox-buildroot-oem-pre.sh 无条件 `rm -rf .../usr/lib/libfreetype*`
# 与 `libiconv*`（该脚本第 28、31 行）。V014 等板型不装 rkipc，故共享脚本对它们成立；
# 但 V020 的 rkipc 硬依赖这两个库：
#   readelf -d output/out/app_out/bin/rkipc → NEEDED libfreetype.so.6 / libiconv.so.2
# 缺库时动态链接器直接失败，rkipc 起不来，OSD 叠加（默认 dateTime）全废。
#
# 为什么不能在 post 脚本里补：V020 的 RK_BUILD_APP_TO_OEM_PARTITION=y，
# /oem 是独立分区（RK_PARTITION_CMD_IN_ENV 的 30M(oem) → 启动后 /dev/mtd4）。
# `build_mkimg oem` 在 post 脚本之前就把 oem.img 定了型；post 里再补只会写进
# ${RK_PROJECT_PACKAGE_ROOTFS_DIR}/oem/usr/lib，而 rootfs 内那份 /oem 会被
# S20linkmount 的 `mount_part oem /oem ubifs` 整个盖住，板端永远看不到。
# 故必须在 build_mkimg oem **之前**把库放回 ${RK_PROJECT_PACKAGE_OEM_DIR}/usr/lib。
#
# 本脚本只被 V020 的 BoardConfig 引用；共享 OEM pre 脚本与 V014 等板型一字未改。
set -e

# 1) 先执行共享前置脚本（保持既有裁剪行为：drm/kms/avs/jpeg/png/aiisp/data/... 照旧删除）。
#    注意：共享脚本会删掉 libfreetype* 与 libiconv*，下一步再补回。
SELF_DIR="$(dirname "$(realpath "$0")")"
SHARED_PRE="${SELF_DIR}/luckfox-buildroot-oem-pre.sh"
if [ ! -f "$SHARED_PRE" ]; then
	echo "luckfox-buildroot-v020-oem-pre: ERROR shared pre missing: $SHARED_PRE" >&2
	exit 1
fi
# shellcheck source=luckfox-buildroot-oem-pre.sh
source "$SHARED_PRE"

# 2) 从 app_out 库源把 rkipc 需要的两个库装回 OEM 打包目录，并建 SONAME/开发链接。
#    源目录与 __PACKAGE_RESOURCES 用的 ${RK_PROJECT_PATH_APP}/lib（build.sh:1399）同源。
APP_OUT="${RK_PROJECT_PATH_APP}"
OEMLIB="${RK_PROJECT_PACKAGE_OEM_DIR}/usr/lib"

install_lib() {
	local ver="$1" soname="$2" devlink="$3"
	local src="${APP_OUT}/lib/${ver}"
	if [ ! -f "$src" ]; then
		echo "luckfox-buildroot-v020-oem-pre: ERROR required source library missing: $src" >&2
		exit 1
	fi
	install -D -m 0755 "$src" "${OEMLIB}/${ver}"
	ln -sfn "$ver" "${OEMLIB}/${soname}"
	ln -sfn "$ver" "${OEMLIB}/${devlink}"
	echo "luckfox-buildroot-v020-oem-pre: restored ${soname} -> ${ver} into oem package dir"
}

# rkipc 的 NEEDED 是 SONAME：libfreetype.so.6 / libiconv.so.2（soname 见两库 ELF）。
install_lib "libfreetype.so.6.17.0" "libfreetype.so.6" "libfreetype.so"
install_lib "libiconv.so.2.6.1" "libiconv.so.2" "libiconv.so"

echo "luckfox-buildroot-v020-oem-pre: done (shared pre + restored freetype/iconv into OEM package dir)"
