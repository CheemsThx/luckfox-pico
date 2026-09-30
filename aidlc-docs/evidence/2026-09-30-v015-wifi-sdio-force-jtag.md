# DW-012 / S1：V015 4 位 Wi-Fi SDIO 的 force_jtag_sdmmc 风险分析与最小移植

- 日期：2026-09-30
- 仓库/工作树：`/home/henry/rv1106/luckfox-pico-v015-main-axiarz`（worktree，主仓 `/home/henry/rv1106/luckfox-pico`）
- 分支：`codex/dw-012-v015-emmc-adaptation`
- 起点/HEAD：`077b56b3d1dbc906c36d259f9a2f3e10e9370ae4`（工作区干净；本分支无 upstream）
- 本次性质：**写入型**（源码/配置最小修复 + 内核构建 + 文档）。**未**烧录、**未**操作设备、**未** push、**未**联网、**未**触碰 V020 树或应用仓库、**未**读/写 `~/.claude/projects/`。
- **本次不产出新候选镜像**：既有 `IMAGE/..._20260930.1022_RELEASE_TEST/` 保持原样（哈希复核未变），本次只做内核与 DTB 构建。

## 0. 工作项与验收

**要回答的问题**：V020 上实测确认的 RV1106 SDMMC0 `force_jtag_sdmmc`（GPIO3_A1..A7 被 JTAG 占用 → 4 位传输必 SBE）风险，是否同样适用于 V015？若适用，移植最小必要修复，且不得改变其他板型行为。

**验收**：① 用源码与构建配置判明适用性，区分代码事实/推断/实板；② 证据足够则最小移植并做针对性静态检查与内核或完整镜像构建，记录命令/退出码/BoardConfig/DTS/工具链/产物哈希/脏状态；③ 证据不足则停在分析并标待实板验证，不做猜测性改动。

**结论摘要**：风险**适用于 V015**（代码与配置层面证据充分，属高置信推断，**非** V015 实板实测——当前**没有 V015 硬件**）。已按 V020 同一做法最小移植：`grf.c` 增 `rockchip,rv1106-ioc` 条目 + V015 专属内核 fragment 打开 `CONFIG_ROCKCHIP_GRF` + BoardConfig 挂接；内核构建通过。

---

## 1. 代码/配置事实（本树可直接复核）

### 1.1 寄存器与引脚

| 事实 | 出处（本树） |
|---|---|
| `force_jtag_sdmmc` 属 GPIO3 IOC，结构体偏移 `0x02f4` | `sysdrv/source/uboot/u-boot/arch/arm/include/asm/arch-rockchip/ioc_rv1106.h:173,175`（`struct rv1106_gpio3_ioc`，`check_member(..., 0x02f4)`） |
| GPIO3 IOC 绝对基址 `0xFF558000` | `sysdrv/source/uboot/u-boot/arch/arm/mach-rockchip/rv1106/rv1106.c:124`（`GPIO3_IOC_BASE`） |
| ⇒ 寄存器绝对地址 `0xFF558000 + 0x2f4 = 0xFF5582F4` | 上式 |
| 内核侧 IOC syscon 基址 `0xff538000`、`compatible = "rockchip,rv1106-ioc"`，覆盖 0x40000 | `sysdrv/source/kernel/arch/arm/boot/dts/rv1106.dtsi:1103` ⇒ 相对 syscon 偏移 `0x202f4 = 0xFF5582F4`，与 U-Boot 口径一致 |
| 它是 HIWORD 掩码寄存器（低 16 位值 / 高 16 位写使能）：写 `0x0` 无效，须写 `0x00010000` 才清 bit0 | `HIWORD_UPDATE(val,mask,shift) = (val<<shift)|(mask<<(shift+16))`，`grf.c:107`；`HIWORD_UPDATE(0,1,0)=0x10000` |

### 1.2 V015 的 Wi-Fi SDIO 正落在这组脚上

`sysdrv/source/kernel/arch/arm/boot/dts/rv1106g-dw-tly-v015.dts`：

- `&sdmmc`（`rv1106.dtsi` 的 `mmc@ffaa0000`，即 **SDMMC0**）：`bus-width = <4>`、`supports-sdio`、`non-removable`、`max-frequency = <50000000>`。
- `pinctrl-0 = <&sdmmc0_clk &sdmmc0_cmd &sdmmc0_bus4 &sdmmc0_det>`；据 `rv1106-pinctrl.dtsi:702-732` 与 DTS 注释：CLK=A4、CMD=A5、D0=A3、D1=A2、D2=A7、D3=A6、DET=A1 —— **正好是 GPIO3_A1..A7**，与该位强制交给 JTAG 的引脚组完全重合。
- 对照：V015 的 TF 卡在 `&sdio`（`mmc@ff9a0000`，SDMMC1，GPIO2 sdmmc1m0），**不**受该位影响。

### 1.3 本树没有任何代码清这一位

- 内核：`grep -rn force_jtag` 只命中 `drivers/pinctrl/pinctrl-rk628.c` 与 arm64 的 rk3399 dtsi 注释，无 RV1106 写入。
- U-Boot：全树 `force_jtag` 只命中 `px30/px30.c`（清 px30 的）、`grf_rk3288.h`、`ioc_rv1106.h` 定义；`rv1106.c` 只写各 GPIOx IOMUX/DS 等，**无** `+0x2f4` 写入。
- 内核 `grf.c` 的匹配表原先只有 `rv1126-grf` 等，**没有** `rockchip,rv1106-ioc` 条目 ⇒ 即便编译进来也不会匹配 RV1106 的 `ioc` 节点。
- 因此该位停在 **POR 默认值**。

### 1.4 该位在 RV1106 上的行为（来自 V020 实板实测，只读引用，不在本树）

V020 树提交 `2e55b494e`（"kernel: 清掉 RV1106 的 force_jtag_sdmmc，修好 SD 4 位读"）记录：RV1106 上电后该位恒为 `0x1`、运行期不变；置位时 SDMMC0 的 4 位数据块每个都报 SBE（RINTSTS 0x2000），1 位只用 D0 所以正常；写 `0x00010000` 清零后 4 位 49.5MHz 顺序读 64MB 约 2.95s（≈21.7MB/s）、零 SBE。该实测是**位语义与后果**的来源；本次只引用，未在 V020 树做任何改动。

### 1.5 旁证（弱，仅作参考，不作结论）

本分支前一版自研板 DTS `rv1106g-luckfox-pico-ultra-spi-nand.dts` 采用**同样**的 Wi-Fi 布线（`&sdmmc`/GPIO3/SDMMC0，`bus-width=<4>`，与 V015 DTS 注释结构一致）。其引入提交 `6831d9024` 的标题即为「蓝牙可用 就是会出现reboot，**wifi还是异常的情况，后续再修**」。这是同族板在同类布线下的历史遗留现象，方向一致，但当时未定位根因，**不能**单独据此定性。

---

## 2. 适用性判定（区分事实/推断）

- **代码事实（1.1–1.4）**：该位属 SoC 级寄存器，POR 默认 1；本 SDK 的 U-Boot 与内核都不写它；V015 的 Wi-Fi SDIO 恰在受影响控制器/引脚组上且为 4 位。
- **推断（高置信）**：由于没有代码改写、且 POR 值与板型无关（SoC 硅片属性），V015 上该位在启动后应为 1 ⇒ **V015 的 Wi-Fi SDIO 4 位传输会同样失败（1 位可能可枚举）**。
- **未验证**：V015 无实板，未 devmem 读 `0xFF5582F4`、未实测 SDIO 枚举/吞吐。**不得**把上面推断写成 V015 实板故障或已修复通过。
- 该位只影响 GPIO3_A1..A7；V015 上这组脚由网表证实只连 Wi-Fi 模组（见
  `2026-09-30-v015-netlist-sdio-pad-cross-check.md`），BT/WiFi 唤醒在 GPIO3_B0/B1、MIPI 在 GPIO3_B6/B7/C0..C3，**不**受影响；
  清位代价仅是不再向 JTAG 让出这几个脚（网表上未引出 JTAG；"本板确无 JTAG 调试需求"属设计意图，待硬件签核）。

**决定**：证据足够，按最小必要做移植；并在证据与状态页中标注"待 V015 实板复核"。

---

## 3. 本次改动（4 个文件）

| 文件 | 改动 | 对其他板型的边界 |
|---|---|---|
| `sysdrv/source/kernel/drivers/soc/rockchip/grf.c` | 新增 `rv1106_ioc_defaults` + `rv1106_ioc_grf`，并在 `rockchip_grf_dt_match` 增加 `rockchip,rv1106-ioc` 条目；写入 `0x202f4 = HIWORD_UPDATE(0,1,0) = 0x10000` | 该文件由 `CONFIG_ROCKCHIP_GRF` 控制编译（`soc/rockchip/Makefile:7`）。本分支**仅 V015** 打开该符号，其他板型的 .config 与二进制**不变**；即便将来别的板打开该符号，也只是"默认关闭 force_jtag"（与上游 RK3399/3588/3576 同做法） |
| `sysdrv/source/kernel/arch/arm/configs/rv1106-v015.config`（新增） | `CONFIG_ROCKCHIP_GRF=y`（取 `=y`：`rockchip_grf_init` 是 `postcore_initcall`，必须早于 mmc controller probe） | 新文件，仅被 V015 BoardConfig 引用；共享的 `rv1106-bt.config` **未改** |
| `project/cfg/BoardConfig_IPC/BoardConfig-EMMC-Buildroot-RV1106_DW_TLY_V015-IPC.mk` | `RK_KERNEL_DEFCONFIG_FRAGMENT="rv1106-bt.config rv1106-v015.config"`（原为单个 `rv1106-bt.config`） | 仅 V015 BoardConfig；其他 BoardConfig 的 fragment 行未动（其中 5 个仍引用共享的 `rv1106-bt.config`） |
| `sysdrv/source/kernel/arch/arm/boot/dts/rv1106g-dw-tly-v015.dts` | 仅在 `&sdmmc` 注释中增加该根因与配套要求的说明 | 纯注释；cpp 后不进 DTB（见 §4.3 DTB 哈希与旧候选一致） |

未改动：`rv1106-bt.config`、其他 BoardConfig、其他板型 DTS、U-Boot、Buildroot defconfig、应用仓库、V020 分支。

---

## 4. 验证（全部为构建/静态级，**非**实板）

### 4.1 内核构建

```
$ cd /home/henry/rv1106/luckfox-pico-v015-main-axiarz
$ ./build.sh kernel        # .BoardConfig.mk → BoardConfig-EMMC-Buildroot-RV1106_DW_TLY_V015-IPC.mk
EXIT=0                     # 日志末尾 "Running build_kernel succeeded."
```
- 构建日志：`/tmp/dw012-v015-jtag-kernel.log`（149 行，退出码 0）。
- BoardConfig：`BoardConfig-EMMC-Buildroot-RV1106_DW_TLY_V015-IPC.mk`；内核 `luckfox_rv1106_linux_defconfig` + `rv1106-bt.config rv1106-v015.config`；DTS `rv1106g-dw-tly-v015.dts`；内核 Linux 5.10.160。
- 工具链：`arm-rockchip830-linux-uclibcgnueabihf-gcc (crosstool-NG 1.24.0) 8.3.0`（`tools/linux/toolchain/...`，由 build.sh 自行入 PATH）。
- 关键日志行：
  - `TARGET_KERNEL_CONFIG_FRAGMENT =rv1106-bt.config rv1106-v015.config`
  - `Merging .../arch/arm/configs/rv1106-v015.config`
  - `Value of CONFIG_ROCKCHIP_GRF is redefined by fragment .../rv1106-v015.config`（**良性**：`merge_config.sh` 用 `grep -w` 取值，而 fragment 注释里多次出现该符号名，故打印了多行；最终值经 olddefconfig 归一。若需消除该提示，可精简注释）
  - DTS 唯一 warning 是早已存在的 `rv1106-luckfox-pico-ultra-ipc.dtsi:446 touchscreen I2C 单元地址`，与本次无关。

### 4.2 修复确实进入构建

```
$ grep -n CONFIG_ROCKCHIP_GRF sysdrv/source/objs_kernel/.config
4232:CONFIG_ROCKCHIP_GRF=y
$ ls sysdrv/source/objs_kernel/drivers/soc/rockchip/grf.o        # 存在（此前 ROCKCHIP_GRF=n 时无此文件）
$ grep rv1106_ioc sysdrv/source/objs_kernel/System.map
80991:... t rv1106_ioc_grf
80992:... t rv1106_ioc_defaults
$ strings .../grf.o | grep -i "jtag\|rv1106"
rockchip,rv1106-ioc
jtag sdmmc force
```
同类修复在 V020 上曾对照 `CONFIG_ROCKCHIP_GRF` 未开时"无 grf.o、System.map 无符号"，此处正好相反，说明 `grf.c` 已编译并含目标条目。

### 4.3 产物与哈希（本次实算）

| 产物 | 路径 | SHA-256 |
|---|---|---|
| grf.o | `sysdrv/source/objs_kernel/drivers/soc/rockchip/grf.o` | `19b30d65c702681dc9930406859004e252a09d50b0988e4dd9bbd8ddc50f94e9` |
| vmlinux | `sysdrv/source/objs_kernel/vmlinux` | `17254dfe6c3fd7f183f3fdd6ab90953b2485b90f4e5dacff54ab374a56501bc1` |
| Image | `sysdrv/source/objs_kernel/arch/arm/boot/Image` | `f0b7e0a604edf2b47d2bc6aa0caceb5c4d5a8e18bbeafb43116943269c2c1aa0` |
| DTB | `sysdrv/out/bin/board_uclibc_rv1106/rv1106g-dw-tly-v015.dtb` | `d540ab24319e7fe210e888a5ec7f888564941bc319fa2bf8aed5c5b60a2806e5` |
| boot.img（内核构建重生成，`output/` 内，不进 Git） | `output/image/boot.img`（3,876,352 B） | `db6eb6e68908f78c25e1617439dd48fd86cb476798d9176b267d63a0e47e8eaf` |

- 反编译 `rv1106g-dw-tly-v015.dtb`：`model = "Dongwei DW-TLY-V015 eMMC"`；`mmc@ffaa0000` `bus-width = <0x04>`；`syscon@ff538000`（ioc）reg `<0xff538000 0x40000>` 存在。
- DTB 哈希 `d540ab24…` **与既有 20260930.1022 候选镜像内 FIT `fdt` 逐字节一致** ⇒ 本次 DTS 仅加注释，未改变 DTB。
- 新 `boot.img` FIT：`fdt` `data-position=0x800 / data-size=0x12f52`，切出后哈希 = `d540ab24…`（与 DTB 自洽），与旧候选 boot.img 哈希不同（内核因新增 grf.o 而变化）。

### 4.4 静态/边界复查

- `git diff --check` 通过；改动仅 4 个文件（3 改 1 增）。
- 本分支仅 `rv1126_defconfig`、`rockchip_linux_defconfig`、`rk3308_linux_aarch32_defconfig` 含 `ROCKCHIP_GRF`，均非本分支任一 BoardConfig 使用的基座 ⇒ 本分支除 V015 外无板型会打开该符号。
- 共享 `rv1106-bt.config` 未改（`git status` 无该文件）。
- 既有候选镜像未被触碰：`IMAGE/..._20260930.1022_RELEASE_TEST/IMAGES/update.img` 哈希仍为 `de90f9deea52bb3e904999dddb3a03f414d54752a13d3e14e31e884e869bf68f`。
- 构建只写 `output/`、`sysdrv/out/`、`sysdrv/source/objs_kernel/`（均被 .gitignore 覆盖），**未**改写任何已跟踪二进制（未运行 allsave）。

---

## 5. 未验证 / 未决（不得写成已通过）

- **无 V015 实板**：该位清零、Wi-Fi SDIO 4 位枚举、吞吐、启动到应用、eMMC/SD/USB/摄像头等**全部未在真机验证**。本次结论止于源码、配置与构建。
- 上板后优先项：`devmem 0xFF5582F4` 应为 `0x0`（此前 V020 上为 `0x1`）；再看 Wi-Fi SDIO 是否 4 位枚举与稳定吞吐。
- **候选镜像未含本修复**：现行 `IMAGE/..._20260930.1022_RELEASE_TEST/` 生成于修复之前，若要把修复纳入交付必须另做一次完整镜像构建（本次刻意不覆盖既有候选、不产新候选）。
- 未核对该位在 **V015 具体板级**是否被 BootROM/硬件 strap 改变（本树 U-Boot 无相关写入，但不能排除硅片外因素）；该项只能由实板 devmem 关闭。
- 旁证（§1.5）中的旧板"wifi 异常"未定位根因，与本修复的相关性**未证实**。

## 6. 证据路径

- 本文件：`aidlc-docs/evidence/2026-09-30-v015-wifi-sdio-force-jtag.md`
- 状态页：`aidlc-docs/CURRENT.md`（同步更新）
- 只读参考（V020 树，未改动）：`/home/henry/rv1106/luckfox-pico-v020-main-axiarz` 提交 `2e55b494e`（grf.c 修复与实测）
