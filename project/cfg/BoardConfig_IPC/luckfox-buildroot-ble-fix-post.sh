#!/bin/bash
# RK_POST_BUILD_SCRIPT：由 build.sh 的 __RUN_POST_BUILD_SCRIPT 在
# __COPY_FILES 把 OEM 目录复制进 rootfs、且成像（build_mkimg）之前执行。
# 同时被 V020(SPI NAND) 与 Luckfox Pico Ultra(SPI NAND) 的 BoardConfig 引用；
# 凡仅适用于本板的行为，一律用 RK_KERNEL_DTS 判断后再做。
# Remove PulseAudio D-Bus policy (no pulse user on IPC rootfs → dbus-daemon fails).
# Add BlueZ main.conf for AIC8800 UART HCI.
# ADB 提前到 S15：S20linkmount 扩 UBI 若卡住，板子仍能被 USB 识别。

ROOTFS="${RK_PROJECT_PACKAGE_ROOTFS_DIR}"
APP_OUT="${RK_PROJECT_PATH_APP}"

rm -f "${ROOTFS}/etc/dbus-1/system.d/pulseaudio-system.conf"

mkdir -p "${ROOTFS}/etc/bluetooth"
cat >"${ROOTFS}/etc/bluetooth/main.conf" <<'EOF'
[General]
AutoEnable=true
Privacy=off
Name = Luckfox-BLE

[Policy]
AutoEnable=true
EOF

USB50="${ROOTFS}/etc/init.d/S50usbdevice"
if [ -f "$USB50" ] && [ ! -f "${ROOTFS}/etc/init.d/S50usbdevice.real" ]; then
	cp -a "$USB50" "${ROOTFS}/etc/init.d/S15usbdevice"
	mv "$USB50" "${ROOTFS}/etc/init.d/S50usbdevice.real"
	cat >"$USB50" <<'EOF'
#!/bin/sh
# S15 已拉起 gadget 则跳过 start，避免 configfs 绑两次。
if [ "$1" = "start" ]; then
	udc=$(cat /sys/kernel/config/usb_gadget/rockchip/UDC 2>/dev/null)
	if [ -n "$udc" ]; then
		exit 0
	fi
fi
exec /etc/init.d/S50usbdevice.real "$@"
EOF
	chmod 0755 "$USB50" "${ROOTFS}/etc/init.d/S15usbdevice"
	echo "luckfox-buildroot-ble-fix-post: USB gadget S15 early start"
fi

if [ "${RK_KERNEL_DTS}" = "rv1106g-dw-tly-v020.dts" ]; then
	# V020 的视频、SD 本地录像和传感器业务不使用 SMB/NMB 文件共享。
	# 仅在此板的镜像中移除开机入口；共享脚本服务的 V014 保持原状。
	rm -f "${ROOTFS}/etc/init.d/S91smb"
	echo "luckfox-buildroot-ble-fix-post: V020 SMB/NMB autostart disabled"

	# --- 恢复 rkipc 运行所需但被共享前置脚本删掉的 freetype ---
	# 共享的 luckfox-buildroot-oem-pre.sh（V020 与 V014 都用）无条件执行
	# `rm -rf ${RK_PROJECT_PACKAGE_OEM_DIR}/usr/lib/libfreetype*`，而该脚本在
	# __PACKAGE_OEM 之后、`__COPY_FILES $RK_PROJECT_PACKAGE_OEM_DIR
	# $RK_PROJECT_PACKAGE_ROOTFS_DIR/oem` 之前运行（project/build.sh 的
	# __RUN_PRE_BUILD_OEM_SCRIPT 在 :2551 附近）。V020 的 rkipc 有硬依赖：
	#   readelf -d output/out/app_out/bin/rkipc → NEEDED libfreetype.so.6
	#   （另有 libiconv.so.2，见下方一并恢复）
	# 缺库时动态链接器直接失败，rkipc 无法启动，OSD 叠加（默认 dateTime）全废。
	# 前置脚本是跨板共享文件，故只在此板的 post 里补回；V014 行为不变。
	OEMLIB="/oem/usr/lib"
	FT_VERSION="6.17.0"
	for f in libfreetype.so."$FT_VERSION" libiconv.so.2.6.1; do
		[ -f "${APP_OUT}/lib/${f}" ] || continue
		install -D -m 0755 "${APP_OUT}/lib/${f}" "${ROOTFS}${OEMLIB}/${f}"
	done
	if [ -f "${ROOTFS}${OEMLIB}/libfreetype.so.${FT_VERSION}" ]; then
		ln -sfn "libfreetype.so.${FT_VERSION}" "${ROOTFS}${OEMLIB}/libfreetype.so.6"
		ln -sfn "libfreetype.so.${FT_VERSION}" "${ROOTFS}${OEMLIB}/libfreetype.so"
		echo "luckfox-buildroot-ble-fix-post: V020 restored libfreetype.so.6 -> libfreetype.so.${FT_VERSION}"
	fi
	if [ -f "${ROOTFS}${OEMLIB}/libiconv.so.2.6.1" ]; then
		ln -sfn "libiconv.so.2.6.1" "${ROOTFS}${OEMLIB}/libiconv.so.2"
		ln -sfn "libiconv.so.2.6.1" "${ROOTFS}${OEMLIB}/libiconv.so"
		echo "luckfox-buildroot-ble-fix-post: V020 restored libiconv.so.2 -> libiconv.so.2.6.1"
	fi
fi

# --- V020 不默认启动 rkipc ---
# rkipc 由 rootfs 的 /etc/init.d/S21appinit 在开机 start 时拉起
# （S21appinit 在 build.sh 的 __PACKAGE_OEM 里生成，内容固定为
# `sh /oem/usr/bin/RkLunch.sh`）。默认关闭的做法是把入口脚本改名加 `.disabled`
# 后缀，保留文件与内容，便于现场/恢复脚本原地改回。
# 因为 post 在 post_overlay 之前运行，而各 overlay 均不含 S21appinit，
# 改名不会被后续步骤撤销。
#
# 恢复开机自动启动（板端，root 执行）：
#   mv /etc/init.d/S21appinit.disabled /etc/init.d/S21appinit && sync
# 立即手动启动（不重启）：
#   /oem/usr/bin/RkLunch.sh            # 已跑过同目录 rcS，重复执行只会重跑 rkipc
# 如需改回“默认自动启动”，在板端 `touch /etc/init.d/S21appinit.enable` 后由
# /etc/init.d/S20pstore 在启动时自动还原（该 overlay 属本板，见 S20pstore 末尾）。
if [ "${RK_KERNEL_DTS}" = "rv1106g-dw-tly-v020.dts" ]; then
	if [ -f "${ROOTFS}/etc/init.d/S21appinit" ]; then
		mv "${ROOTFS}/etc/init.d/S21appinit" "${ROOTFS}/etc/init.d/S21appinit.disabled"
		echo "luckfox-buildroot-ble-fix-post: V020 rkipc autostart disabled (S21appinit.disabled)"
	fi
fi

echo "luckfox-buildroot-ble-fix-post: removed pulseaudio-system.conf, wrote /etc/bluetooth/main.conf"
if [ "${RK_KERNEL_DTS}" = "rv1106g-dw-tly-v020.dts" ]; then
	echo "luckfox-buildroot-ble-fix-post: V020 post done (freetype restored, rkipc autostart off)"
fi
