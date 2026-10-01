#!/bin/bash
# RK_POST_BUILD_SCRIPT：由 build.sh 的 __RUN_POST_BUILD_SCRIPT 在
# __COPY_FILES 把 OEM 目录复制进 rootfs、且成像（build_mkimg）之前执行。
# 同时被 V020(SPI NAND) 与 Luckfox Pico Ultra(SPI NAND) 的 BoardConfig 引用；
# 凡仅适用于本板的行为，一律用 RK_KERNEL_DTS 判断后再做。
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

if [ "${RK_KERNEL_DTS}" = "rv1106g-dw-tly-v020.dts" ]; then
	# V020 的视频、SD 本地录像和传感器业务不使用 SMB/NMB 文件共享。
	# 仅在此板的镜像中移除开机入口；共享脚本服务的 V014 保持原状。
	rm -f "${ROOTFS}/etc/init.d/S91smb"
	echo "luckfox-buildroot-ble-fix-post: V020 SMB/NMB autostart disabled"

	# --- rkipc 所需的 freetype/iconv 不再在此处补 ---
	# 原先这里把 libfreetype/libiconv 装到 "${ROOTFS}/oem/usr/lib"。那是**无效修复**：
	# 本板 RK_BUILD_APP_TO_OEM_PARTITION=y，/oem 是独立分区（mtd4），
	# S20linkmount 的 `mount_part oem /oem ubifs` 会把 rootfs 内这份 /oem 整个盖住，
	# 板端永远读不到。20260930.2112 候选镜像因此仍缺 freetype，rkipc 起不来。
	# 现在改由 V020 专属 pre-OEM 包装脚本 luckfox-buildroot-v020-oem-pre.sh 在
	# `build_mkimg oem` **之前**装进 ${RK_PROJECT_PACKAGE_OEM_DIR}/usr/lib，
	# 即真正被打进 oem.img 的那份。
fi

# --- V020 不默认启动 rkipc ---
# 门控由 V020 专属覆盖件 overlay-luckfox-buildroot-config/etc/init.d/S21appinit
# 经 RK_POST_OVERLAY 覆盖进 rootfs（见 BoardConfig 的 RK_POST_OVERLAY 注释与
# S20linkmount/S21appinit 的启动顺序）。这里只做构建期断言：
#   1) 覆盖件存在且带 RkLunch.sh 与相机模块装载入口 /oem/usr/ko/insmod_ko.sh，
#      覆盖确实发生在 post_overlay 之后；
#   2) 覆盖件保留 S21appinit 文件名，且产物里没有会被 rcS 的 S??* 误匹配的
#      S21appinit.disabled 残留。
# 断言 insmod_ko.sh 的原因：关闭 rkipc 时若不装载 video_rkcif/video_rkisp/
# sensor/mpp_vcodec/rockit 等模块，板端连 /dev/video*、/dev/media* 都不会出现，
# dw-rec 的本地录像也会一起失效（20260930.2112 实测）。把这条钉在构建期。
# 为什么不能用“改名加 .disabled”关闭自启：rootfs 的 /etc/init.d/rcS 用
#   `for i in /etc/init.d/S??* ;do`
# 枚举（本分支已构建的 output/out/rootfs_uclibc_rv1106/etc/init.d/rcS 第 7 行），
# `S??*` 只要求 S + 两位数字，S21appinit.disabled **仍然匹配**，且 rcS 只跳过
# 目录/悬空链接（[ ! -f "$i" ] && continue），普通文件照样 `$i start`。
# 先前 20260930.2054 候选镜像正是因此仍然开机启动 rkipc；改名为不生效的死路。
if [ "${RK_KERNEL_DTS}" = "rv1106g-dw-tly-v020.dts" ]; then
	# 注意脚本末尾会执行到此处，且本脚本此前若有失败不得静默放过。
	gate_src="$(dirname "$(realpath "$0")")/overlay/overlay-luckfox-buildroot-config/etc/init.d/S21appinit"
	gate_dst="${ROOTFS}/etc/init.d/S21appinit"
	gate_bad="${ROOTFS}/etc/init.d/S21appinit.disabled"

	if [ ! -f "$gate_src" ]; then
		echo "luckfox-buildroot-ble-fix-post: ERROR V020 rkipc gate overlay missing: $gate_src" >&2
		exit 1
	fi
	mkdir -p "${ROOTFS}/etc/init.d"
	install -m 0755 "$gate_src" "$gate_dst"
	grep -q 'RkLunch\.sh' "$gate_dst" ||
		{ echo "luckfox-buildroot-ble-fix-post: ERROR V020 rkipc gate lacks RkLunch.sh" >&2; exit 1; }
	grep -q '\.rkipc-enable' "$gate_dst" ||
		{ echo "luckfox-buildroot-ble-fix-post: ERROR V020 rkipc gate lacks /userdata/.rkipc-enable" >&2; exit 1; }
	grep -q 'insmod_ko\.sh' "$gate_dst" ||
		{ echo "luckfox-buildroot-ble-fix-post: ERROR V020 rkipc gate lacks camera module loader insmod_ko.sh" >&2; exit 1; }
	grep -q 'KO_DIR=/oem/usr/ko' "$gate_dst" ||
		{ echo "luckfox-buildroot-ble-fix-post: ERROR V020 rkipc gate KO_DIR is not /oem/usr/ko" >&2; exit 1; }
	if [ -e "$gate_bad" ]; then
		echo "luckfox-buildroot-ble-fix-post: ERROR stale ${gate_bad} matches rcS S??* glob" >&2
		exit 1
	fi
	echo "luckfox-buildroot-ble-fix-post: V020 rkipc autostart gated by /userdata/.rkipc-enable (S21appinit kept, camera modules loaded when gated off)"
fi

# 说明：覆盖件由 post_overlay 在 __RUN_POST_BUILD_SCRIPT（本脚本）之后写入，
# 故此处只校验源覆盖件；对成像结果的断言（rcS glob 不会误匹配、门控内容确实
# 在 rootfs 内）见 aidlc-docs/evidence/ 中本次切片的包内静态核验记录。

echo "luckfox-buildroot-ble-fix-post: removed pulseaudio-system.conf, wrote /etc/bluetooth/main.conf"
if [ "${RK_KERNEL_DTS}" = "rv1106g-dw-tly-v020.dts" ]; then
	echo "luckfox-buildroot-ble-fix-post: V020 post done (SMB off, rkipc autostart gated; freetype in oem.img handled by v020-oem-pre)"
fi
