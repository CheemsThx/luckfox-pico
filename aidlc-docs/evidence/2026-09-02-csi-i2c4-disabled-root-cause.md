# RV1106 CSI/sensor 未启动：源码与真机 DTB 对照

日期：2026-09-02  
范围：只读分析。未烧写、未 `./build.sh` 整包、未从其他机器拷 rkipc、未改应用 MQTT/UART。  
未把 U10 标完成，未进 U11。

## 0. 仓库与对照材料

| 项 | 值 |
|---|---|
| SDK | `CheemsThx/luckfox-pico`，分支 `main_axiarz` |
| 工作区 HEAD | `c3d54a05a2c60aec578f3ad849c42243c98ba09e` |
| HEAD 说明 | `board: enable SD card and disable conflicting display nodes`（2026-08-24） |
| BoardConfig | `project/cfg/BoardConfig_IPC/BoardConfig-SPI_NAND-Buildroot-RV1106_Luckfox_Pico_Ultra-IPC.mk` |
| 板级 DTS | `sysdrv/source/kernel/arch/arm/boot/dts/rv1106g-luckfox-pico-ultra-spi-nand.dts` |
| dtsi | `sysdrv/source/kernel/arch/arm/boot/dts/rv1106-luckfox-pico-ultra-ipc.dtsi`（与 `upstream/main` 无 diff） |
| 已编 DTB | `output/out/sysdrv_out/board_uclibc_rv1106/rv1106g-luckfox-pico-ultra-spi-nand.dtb`（2026-08-24 17:36，与 HEAD 同日） |
| 真机 | serial `f7019dc975b276a7`，会话内只读 dmesg + `/proc/device-tree`（由应用侧 DW-007 已核实，本会话未再 ADB） |

应用仓库：用户指定 `/home/henry/dw/dongwei-camera-rv1106` **本机不存在**。`/home/henry/rv1106/dongwei-camera-rv1106` 是旧 Gitee 仓（无 `aidlc-docs/`、无 `docs/sdk/luckfox-sdk.md`），因此证据写在 SDK 本路径。

现场口述（不覆盖真机验证）：开发者认为当前远程设备没有录制功能，且「这份 SDK 的 rkipc 估计没有录像 Unix socket」。下文用源码证明 socket/storage **有**；真机看不到 `/var/tmp/rkipc` 是因为 CSI 关着、rkipc 起不来，不能据此说「没有录像接口」。

---

## 1. 代码事实：谁把通路写成 disabled

### 1.1 结论先行

**关掉摄像头的不是「关显示、开 SD」那次提交，也不是 BoardConfig 宏，也不是构建脚本另生成的 dtb。**

关掉的是板级 DTS `rv1106g-luckfox-pico-ultra-spi-nand.dts` 里一组显式 `status = "disabled"`，来自更早的 WiFi/BT 提交 `6831d9024`（2026-06-02），注释写的是 GPIO3_B0/B1 给唤醒、因此禁用 MIPI。

`i2c@ff470000` = SoC `i2c4`（`rv1106.dtsi:892`）。

### 1.2 分层：默认 disabled → dtsi 打开 → 板级再关

| 节点 | SoC `rv1106.dtsi` | Ultra dtsi（上游同板默认） | 自研板 DTS | 已编 DTB / 真机 |
|---|---|---|---|---|
| `csi2-dphy-hw` | disabled:812-820 | **okay:226-228** | 未再改 | okay（probe 成功） |
| `csi2-dphy0` | disabled:188-192 | **okay:230-266**（2-lane，接 sc3336/mis5001） | **disabled:111-113** | disabled |
| `csi2-dphy1` / `csi2-dphy2` | disabled:195-206 | 未打开 | 未打开 | disabled（单摄预期，不是这次的 bug） |
| `mipi0-csi2` | disabled:243-247 | **okay:317-346** | **disabled:115-117** | disabled |
| `mipi1-csi2` | disabled:249-253 | 未打开 | 未打开 | disabled（单摄预期） |
| `rkcif` / `rkisp` | disabled:1196-1240 | **okay:348-350 / 376-378** | 未再改 | okay（probe 成功） |
| `rkcif-mipi-lvds` | disabled:283-287 | **okay:352-363** | **disabled:119-121** | disabled |
| `rkcif-mipi-lvds-sditf` | disabled:289-293 | **okay:365-374** | **disabled:123-125** | disabled |
| `rkcif-mipi-lvds1` / `rkisp-vir1` | disabled:295-318 | 未打开 | 未打开 | disabled（单摄预期） |
| `rkisp-vir0` | disabled:307-312 | **okay:380-388** | **disabled:127-129** | disabled |
| `i2c4` `i2c@ff470000` | disabled:892-903 | **okay:268-315**，pinctrl `i2c4m2` | **disabled:131-133** | 父总线 disabled；子节点 sc3336@30 / mis5001@31 仍为 okay |
| `mipi-csi2-hw@ffa20000/ffa30000` | okay:1243-1268 | — | — | okay（probe 成功） |

板级关掉 CSI 的原文：

```110:133:sysdrv/source/kernel/arch/arm/boot/dts/rv1106g-luckfox-pico-ultra-spi-nand.dts
// 自研板: GPIO3_B0/B1 给 WiFi/BT 唤醒，禁用 MIPI 摄像头
&csi2_dphy0 {
	status = "disabled";
};
...
&i2c4 {
	status = "disabled";
};
```

对应唤醒脚（同一文件更早处）：

```30:47:sysdrv/source/kernel/arch/arm/boot/dts/rv1106g-luckfox-pico-ultra-spi-nand.dts
	/* WL_HOST_WAKE → GPIO3_B1 */
	wireless_wlan: wireless-wlan {
		...
		WIFI,host_wake_irq = <&gpio3 RK_PB1 GPIO_ACTIVE_HIGH>;
...
		/* BT_WAKE_HOST → GPIO3_B0 */
		BT,wake_gpio     = <&gpio3 RK_PB0 GPIO_ACTIVE_HIGH>;
```

`git blame`：上述 110–133 行全部是 `6831d9024`（HenryLiang, 2026-06-02），**不是** HEAD `c3d54a05`。

### 1.3 「关显示、开 SD」没有误伤 CSI

HEAD `c3d54a05` 只改了这一个 DTS，+55/-1。它做的是：

- `&sdio`：由 disabled 改为 SD 卡 okay（GPIO2 `sdmmc1m0`）
- 关掉 **显示/触摸**：`panel`、`backlight`、`display_subsystem`、`rgb`、`rgb_in_vop`、`route_rgb`、`vop`、`pwm1`、`i2c3`

这些是 135–174 行，与 CSI 块分开。没有改 `csi2_dphy0` / `i2c4`。

显示冲突的是 GPIO2_A0–A5（RGB `lcd_d8~d13` vs SD）。摄像头 I2C 默认是 **i2c4m2 = GPIO3_PC7/PD0**，不走 GPIO2。

### 1.4 BoardConfig / overlay / 构建生成

- `RK_KERNEL_DTS=rv1106g-luckfox-pico-ultra-spi-nand.dts`：就是这份会关 CSI 的文件。
- `RK_APP_TYPE=RKIPC_RV1106`：会编 `src/rv1106_ipc`，**想要**摄像头。
- `RK_CAMERA_SENSOR_IQFILES` 含 `sc3336_...json` 和 `mis5001_...json`。
- `RK_POST_OVERLAY`：`overlay-luckfox-config` 等，**没有**在 rootfs overlay 里再关 CSI 节点。
- `luckfox-config luckfox_csi_app()`（`overlay-luckfox-config/usr/bin/luckfox-config:2052`）能往 boot 介质写 overlay，但只改 `i2c@ff470000` 的 status（关掉时甚至拼写为 `disbaled`），**不会**去关 `csi2-dphy0` / `mipi0-csi2` / `rkisp-vir0`。真机这整条链都是 disabled，与源码板级 DTS 一致，不是 config overlay 单独造成的。
- 本树没有「构建时另写一份 DTS」的步骤。已编 DTB 就是该 DTS 的编译产物。

### 1.5 上游 LuckfoxTECH 同板默认：摄像头应该 okay

`git diff upstream/main -- .../rv1106-luckfox-pico-ultra-ipc.dtsi` 为空。

官方板 DTS `rv1106g-luckfox-pico-ultra.dts`（eMMC Ultra）：

- **不** override CSI / i2c4，因此继承 dtsi 的 okay。
- BT wake 用 `GPIO0_PA2`，**不用** GPIO3_B0/B1。
- 没有「为 WiFi 关摄像头」这段。

自研板把 BT/WiFi 唤醒挪到 GPIO3_B0/B1 后，把整条 MIPI+I2C 关掉，这是 fork 相对上游的差异，不是 SoC 默认。

### 1.6 引脚：关整条 CSI 过宽

`rkcif_mipi_lvds` 在 dtsi 里 `pinctrl-0 = <&mipi_pins>`。`mipi_pins`（`rv1106-pinctrl.dtsi:373-399`）含 4 lane：

| 脚 | MIPI 功能 | 自研板现用 |
|---|---|---|
| GPIO3_PC0/PC1 | ck0 | CSI 时钟，2-lane 需要 |
| GPIO3_PC2/PC3 | d0 | 2-lane 需要 |
| GPIO3_PB6/PB7 | d1 | 2-lane 需要 |
| GPIO3_PB2–PB5 | ck1/d2 | 2-lane 通常不需要 |
| **GPIO3_PB0/PB1** | **d3n/d3p** | **WiFi/BT 唤醒 GPIO** |

Sensor `data-lanes = <1 2>`，只要 lane 0/1，**不需要 d3**。  
i2c4m2（GPIO3_PC7/PD0）、reset GPIO3_PC5、mclk GPIO3_PC4 与 SDIO（GPIO3_A*）和唤醒脚无冲突。

因此：注释把「d3 与唤醒冲突」放大成了「整条摄像头必须关」。2-lane 可以开 CSI+I2C，同时保留 GPIO3_B0/B1 为 GPIO。  
反过来：若原样 `status=okay` 且仍用完整 `mipi_pins`，内核会把 B0/B1 mux 成 MIPI d3，唤醒会坏。

i2c4 **不要**落到 m0：`i2c4m0` 是 GPIO2_A0/A1，与 SD 卡冲突。dtsi 已设 `pinctrl-0 = <&i2c4m2_xfer>`，已编 DTB 中 `i2c@ff470000` 的 pinctrl-0 phandle `0x3d` = `i2c4m2-xfer`。打开 i2c4 时保持 m2。

---

## 2. 与运行中 dtb / 真机现象对比

本会话未再 ADB。对照的是：应用侧已核实的 `/proc/device-tree` + dmesg，以及本树 2026-08-24 编出的 DTB（`dtc -I dtb`）。

| 真机 | 源码板级 DTS | 已编 DTB |
|---|---|---|
| 无 `/dev/video*` `/dev/media*` `/dev/v4l-subdev*` | vir0/dphy0/mipi0/cif-lvds/i2c4 disabled，sensor 不会 bind | 同上 |
| `rkcifhw` / `rkisp_hw` / `mipi-csi2-hw` / `csi2-dphy-hw` probe 成功 | 对应 hw 节点 okay | `csi2-dphy-hw`/`rkisp@ffa00000`/`rkcif@ffa10000`/`mipi-csi2-hw` = okay |
| `rkisp_hw max input:0x0@0fps` | vir0 disabled，无输入 | vir0 disabled |
| `isp_rockit` `rockit_cfg is null` | 无 sensor 实体 | 无 subdev |
| 无 sc3336 / mis5001 bind | 父 i2c4 disabled，子节点 okay 不 probe | 父 disabled，子 okay |
| `csi2-dphy0/1/2`、`mipi0/1-csi2`、`rkcif-mipi-lvds`/`lvds1`、`rkisp-vir0/vir1` 均为 disabled | dphy0/mipi0/lvds/vir0 被板级关掉；其余 SoC 默认关 | 完全一致 |
| `i2c@ff470000` disabled；`sc3336@30`/`mis5001@31` okay；`/sys/class/i2c-adapter` 空 | 正是 dts 合并结果 | 正是已编 DTB |
| `/oem/usr/bin/rkipc` 在；`rkipc -a /oem/usr/share/iqfiles` 因 sensor 空名退出；无 `/var/tmp/rkipc` | 见第 4 节：socket 在源码里，进程没跑到 listen | — |

**一致。** 不是「烧进去的 dtb 和这份源码对不上」，也不是 rkipc 没连上已经在跑的摄像头。

`dphy1/2`、`mipi1`、`lvds1`、`vir1` 在官方 Ultra 上同样是 disabled（单摄只用 dphy0）。它们保持 disabled **不是**故障。故障是 **dphy0 这一路和 i2c4 被板级关掉**。

---

## 3. 候选原因（按可信度）

1. **直接原因（已证实）**：`6831d9024` 在自研板 DTS 把 CSI0 通路和 `i2c4` 设为 disabled，编译进 DTB，内核不 probe sensor / CIF 虚拟通道 / ISP vir。
2. **动机**：GPIO3_B0/B1 给 WiFi/BT 唤醒，与完整 `mipi_pins` 的 d3 冲突。关整条链路是过度规避。
3. **不是**：HEAD 关显示/开 SD；BoardConfig 宏；构建另写 dtb；luckfox-config overlay 单独关掉整条 CSI。
4. **rkipc 空 sensor 名**：`rk_isp_init` → `rk_aiq_uapi2_sysctl_enumStaticMetasByPhyId` 在没有 v4l-subdev 时得到空名字（`common/isp/rv1106/isp.c:94-101`）。这是 CSI 关闭的后果，不是独立根因。
5. **口述「没有录像 socket」**：源码有；真机没有 socket 文件是因为 rkipc 在 ISP 初始化阶段退出，没执行到 `rkipc_server_init()`。

---

## 4. rkipc：`/var/tmp/rkipc` 与 storage 录像（有证据，不猜）

板型 `RKIPC_RV1106` → `project/app/rkipc/Makefile:47-48` → `-DCOMPILE_FOR_RV1106_IPC=ON` → `src/rv1106_ipc`。

**有 Unix socket server：**

- 路径宏：`common/socket_server/socket.h:13` `#define CS_PATH "/var/tmp/rkipc"`
- `serv_listen()`：`socket.c:28-51`，`AF_UNIX` bind 该路径，`chmod 0666`，`listen`
- 线程：`server.c:5812-5819` `rkipc_server_thread` → `serv_listen(CS_PATH)`
- `main.c:172` `rkipc_server_init()`（在 `rk_isp_init` / `rk_video_init` **之后**）

**有 storage 录像命令（应用侧拼写 `statue` 与源码一致）：**

- 命令表 `server.c:5693-5695`：`rk_storage_record_start` / `stop` / `statue_get`
- 实现 `server.c:4394-4429` → `rk_storage_record_*`（`common/storage/storage.c:1833-1870`）
- `src/rv1106_ipc/CMakeLists.txt:22,30` 编进 `socket_server` 和 `storage`
- `RkLunch.sh:151-155` 启动 `rkipc -a /oem/usr/share/iqfiles`

**有，但默认 ini 未开自动录像线程：**

- `rkipc-300w.ini` / `rkipc-mis5001-500w.ini` 等 `[storage.0] enable = 0`
- `rk_storage_muxer_init_by_id` 在 enable==0 时提前 return（`storage.c:1734-1737`），不建 record 线程
- socket 命令 `rk_storage_record_start()` 本身不读这个 enable，会直接 `rkmuxer_init`；这是 CSI 起来之后的 DW-008 问题，不能当成「没有接口」

真机没有 `/var/tmp/rkipc`：`main.c` 顺序是 param → network → system → **isp** → MPI → video → **server** → storage。sensor 空名时进程在 isp 阶段退出，listen 不会发生。这不能证明这份树删了 socket。

不要从另一台电脑静默拷 rkipc。这份树已经有 server + storage。

---

## 5. 若要让摄像头起来：最小改哪些节点

只改 `rv1106g-luckfox-pico-ultra-spi-nand.dts`。不要重开显示节点（`panel`/`rgb`/`vop`/`i2c3`/`pwm1` 等），不要动 `&sdio`。

**改为 okay（或删掉 110–133 行覆盖，让 dtsi 生效）：**

- `&i2c4`（保持 dtsi 的 `i2c4m2`，不要 m0）
- `&csi2_dphy0`
- `&mipi0_csi2`
- `&rkcif_mipi_lvds`
- `&rkcif_mipi_lvds_sditf`
- `&rkisp_vir0`

**不要打开：** `csi2_dphy1/2`、`mipi1_csi2`、`rkcif_mipi_lvds1`、`rkisp_vir1`（官方单摄也不开）。

**必须同时改 pinctrl（否则抢 WiFi/BT 唤醒脚）：** 为 2-lane 增加不含 GPIO3_PB0/PB1 的 pin 组，赋给 `&rkcif_mipi_lvds`。至少包含 ck0（PC0/PC1）+ d0（PC2/PC3）+ d1（PB6/PB7）。不要把完整 `mipi_pins` 原样打开。

分析补丁示例（**未合入、未编译、未烧写**）：

```dts
/* 2-lane only: do not mux GPIO3_B0/B1 (MIPI d3), those are WiFi/BT wake */
&pinctrl {
	mipi {
		mipi_pins_2lane: mipi-pins-2lane {
			rockchip,pins =
				<3 RK_PC0 2 &pcfg_pull_none>, /* ck0n */
				<3 RK_PC1 2 &pcfg_pull_none>, /* ck0p */
				<3 RK_PC2 2 &pcfg_pull_none>, /* d0n */
				<3 RK_PC3 2 &pcfg_pull_none>, /* d0p */
				<3 RK_PB6 2 &pcfg_pull_none>, /* d1n */
				<3 RK_PB7 2 &pcfg_pull_none>; /* d1p */
		};
	};
};

&csi2_dphy0 { status = "okay"; };
&mipi0_csi2 { status = "okay"; };
&rkcif_mipi_lvds {
	status = "okay";
	pinctrl-0 = <&mipi_pins_2lane>;
};
&rkcif_mipi_lvds_sditf { status = "okay"; };
&rkisp_vir0 { status = "okay"; };
&i2c4 { status = "okay"; };
```

烧写前还需确认原理图：模组是否确为 sc3336 或 mis5001、I2C 是否 i2c4m2、reset 是否 GPIO3_PC5。dtsi 里两个 sensor 同时 okay 是上游写法，内核会 probe 到的那颗。

合入 / 只编 dtb / 烧写须再问。不要顺带重开 LCD。

---

## 6. 建议下一步

**先只开 CSI，验证出图。** 不要把「没有录像接口」当成 CSI 可以不管。

建议顺序：

1. 按第 5 节改板级 DTS（2-lane pinctrl + 打开 i2c4/CSI0），**单独问准**后只编 kernel dtb 验证，不要整包、不要重开显示。
2. 烧写后只读检查：`i2c-adapter` 出现、`sc3336` 或 `mis5001` bind、`/dev/video*` `/dev/media*`、`rkisp_hw max input` 不再是 0x0。
3. 再跑 `rkipc -a /oem/usr/share/iqfiles`，确认进程还在且 `/var/tmp/rkipc` 出现。这仍属 CSI/出图，不算录像验收。
4. **媒体/录像另开 DW-008**：socket 命令在这份树里已有；还要处理默认 `storage.0 enable=0`、录像路径（ini 是 `/userdata`，板子有 SD）、以及应用是否真的连上 socket。不要从别的电脑拷 rkipc。

U10 不标完成。不进 U11。
