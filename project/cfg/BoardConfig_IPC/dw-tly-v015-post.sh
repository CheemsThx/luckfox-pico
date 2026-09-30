#!/bin/sh
# DW-TLY-V015 板级 rootfs 后处理（仅本板 BoardConfig 选用）。
#
# 1) 关闭 SMB/NMB 开机自启（视频、SD 本地录像与传感器业务不使用 Samba）。
# 2) rkipc 默认不自启：S21appinit 是共享 build.sh 生成的，start) 会直接跑
#    /oem/usr/bin/RkLunch.sh 并无条件拉起 rkipc。这里用 V015 专属覆盖件换掉它，
#    保留“可显式打开”的持久开关 /userdata/.rkipc-enable（见覆盖件内注释）。
#    共享 build.sh、共享 Buildroot defconfig 与 rv1106_ipc/RkLunch.sh 均不改，
#    其他板型行为不变。
set -eu

rootfs="${RK_PROJECT_PACKAGE_ROOTFS_DIR:?}"
overlay_dir=$(dirname "$(realpath "$0")")/overlay/overlay-dw-tly-v015

# 1) SMB/NMB 不随开机启动；Samba 二进制仍随包。
rm -f "${rootfs}/etc/init.d/S91smb"

# 2) rkipc 启动门控：用 V015 覆盖件替换共享生成器产出的 S21appinit。
src="${overlay_dir}/etc/init.d/S21appinit"
if [ ! -f "$src" ]; then
	echo "dw-tly-v015-post: ERROR overlay S21appinit missing: $src" >&2
	exit 1
fi
mkdir -p "${rootfs}/etc/init.d"
cp -f "$src" "${rootfs}/etc/init.d/S21appinit"
chmod 755 "${rootfs}/etc/init.d/S21appinit"

grep -q 'RkLunch.sh' "${rootfs}/etc/init.d/S21appinit" ||
	{ echo "dw-tly-v015-post: ERROR S21appinit override lacks RkLunch.sh" >&2; exit 1; }

echo "dw-tly-v015-post: rkipc autostart gated by /userdata/.rkipc-enable; SMB/NMB autostart disabled"
