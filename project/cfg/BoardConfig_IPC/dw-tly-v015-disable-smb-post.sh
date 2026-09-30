#!/bin/sh
set -eu

rootfs="${RK_PROJECT_PACKAGE_ROOTFS_DIR:?}"
# V015 的视频、SD 本地录像和传感器业务不使用 SMB/NMB。
rm -f "${rootfs}/etc/init.d/S91smb"
echo "dw-tly-v015-disable-smb-post: SMB/NMB autostart disabled"
