#!/bin/bash
# Remove PulseAudio D-Bus policy (no pulse user on IPC rootfs → dbus-daemon fails).
# Add BlueZ main.conf for AIC8800 UART HCI.
# ADB 提前到 S15：S20linkmount 扩 UBI 若卡住，板子仍能被 USB 识别。

ROOTFS="${RK_PROJECT_PACKAGE_ROOTFS_DIR}"

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

# V020 的视频、SD 本地录像和传感器业务不使用 SMB/NMB 文件共享。
# 仅在此板的镜像中移除开机入口；共享脚本服务的 V014 保持原状。
if [ "${RK_KERNEL_DTS}" = "rv1106g-dw-tly-v020.dts" ]; then
	rm -f "${ROOTFS}/etc/init.d/S91smb"
	echo "luckfox-buildroot-ble-fix-post: V020 SMB/NMB autostart disabled"
fi

echo "luckfox-buildroot-ble-fix-post: removed pulseaudio-system.conf, wrote /etc/bluetooth/main.conf"
