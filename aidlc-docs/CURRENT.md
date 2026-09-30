# DW-012 当前状态快照（SDK 仓 / `codex/dw-012-v015-emmc-adaptation`）

- 生成日期：2026-09-30（初版为只读复核；随后按 DW-012 / S1 切片更新：网表对照与注释缩句、CPUFreq 关闭、完整 `allsave` 构建与新候选静态核验）
- 最近更新：2026-09-30 深夜（第三轮）—— 在 `b1998ddfe`（rkipc 默认不自启门控）上重跑 `check`+`allsave`，
  新候选 `20260930.2056`（`163abefa…`）取代 `90e77d72…`（20260930.2013）；
  本版**唯一实质变化**是 rootfs 内 rkipc 启动门控（`/etc/init.d/S21appinit` 换为带 `/userdata/.rkipc-enable` 的
  V015 覆盖件），**内核与 DTB 逐字节未变**（FIT `fdt` `e3b00deb…` / `kernel` `c3d6b6c9…` 与上一候选相同）。
  另新增供用户自行烧录的 Windows 交付目录（`update.img` + 中文说明 + `SHA256SUMS`，复制后 hash 已复核）。
- 说明（澄清）：`libfreetype.so.6` 缺失报错来自 **V020 NAND** 启动日志，与 V015 无关；本候选 rootfs 的
  freetype 与 rkipc 全依赖闭包（10 个直接 + 6 个二级）已逐件复核齐备（见 §3.2 与 2056 证据 §6）。
- 仓库与工作树：`/home/henry/rv1106/luckfox-pico-v015-main-axiarz`（`git worktree list` 实测，主仓为 `/home/henry/rv1106/luckfox-pico`）
- 分支：`codex/dw-012-v015-emmc-adaptation`
- 起点/HEAD（本切片改动前）：`077b56b3d1dbc906c36d259f9a2f3e10e9370ae4`（"限制 Claude 工作切片不得写入仓库外记忆"）
- 工作区：本切片开始与结束时均无未提交脏文件；本分支**无 upstream**（`git rev-parse @{u}` → `fatal: no upstream configured`）
- 相对本树基线 `main_axiarz`（`7b9a33dc7`）领先 5 个提交（本切片提交另计）
- 本文件**不是**验收结论，也不是交付说明或烧录授权；只登记当前现状、已验证项、未验证项与已知证据缺口

## 1. 边界：V015 eMMC 量产候选 ≠ V020 NAND 验证板

- DW-012 的**量产目标是 V015 eMMC**。V020 NAND 是**尚未定型的验证板**；用户手头的 V020 板移用了 V014 样品芯片，
  且**没有 V015 量产板**，本分支的候选镜像**没有任何可用的实板**。
- **U17 VCCQ 电压与焊球映射仍未获硬件签核**（本分支提交 `cd9cc3e9f`、`5e237add4` 及 DTS 注释均如此标注）。
  因此本分支产出的 `update.img` **只能做包内静态验证，不得烧录，也不得称其为量产固件或已获签核**。
- V020 的板级文件、构建与实测证据**不在本树**：`git ls-files | grep -i v020` 为空。V020 相关工作在
  另一 worktree `/home/henry/rv1106/luckfox-pico-v020-main-axiarz`（分支 `codex/dw-012-v020-nand-validation`）。
  两个分支的 SMB 关闭实现也**不是同一处代码**，不能互相代替验证。
- 反向同样成立：V020 分支不得把 V015 eMMC 称为已签核或可刷到 V020 板；本文件同样不代 V020 背书。

## 2. 本分支承载的板级事实（代码/配置事实，可在本树逐条复核）

V015 板级适配涉及下列源码/配置文件；分支还包含证据、状态和 Claude 规则文件（以 `git diff --name-only main_axiarz..HEAD` 为准）：

| 文件 | 作用 |
|---|---|
| `project/cfg/BoardConfig_IPC/BoardConfig-EMMC-Buildroot-RV1106_DW_TLY_V015-IPC.mk` | V015 eMMC 板级配置（含内核 fragment 挂接、`RK_POST_OVERLAY` 末位的 V015 overlay） |
| `project/cfg/BoardConfig_IPC/dw-tly-v015-post.sh` | V015 专属 rootfs 后处理：关 Samba 开机自启 + 换装 rkipc 启动门控（取代旧 `dw-tly-v015-disable-smb-post.sh`） |
| `project/cfg/BoardConfig_IPC/overlay/overlay-dw-tly-v015/etc/init.d/S21appinit` | V015 专属启动脚本：rkipc 默认不自启，`/userdata/.rkipc-enable` 为持久开关 |
| `sysdrv/source/kernel/arch/arm/boot/dts/rv1106g-dw-tly-v015.dts` | V015 顶层 DTS（`model = "Dongwei DW-TLY-V015 eMMC"`） |
| `sysdrv/source/kernel/arch/arm/boot/dts/Makefile` | 注册 `rv1106g-dw-tly-v015.dtb`（Makefile:987） |
| `sysdrv/source/kernel/arch/arm/configs/rv1106-v015.config`（3.4 新增） | V015 专属内核 fragment：`CONFIG_ROCKCHIP_GRF=y` |
| `sysdrv/source/kernel/drivers/soc/rockchip/grf.c`（3.4 改，**共享**内核文件） | 增 `rockchip,rv1106-ioc` 条目，清 SDMMC0 的 force_jtag；仅当 `CONFIG_ROCKCHIP_GRF=y` 时参与编译 |

关键配置（`BoardConfig-EMMC-Buildroot-RV1106_DW_TLY_V015-IPC.mk`）：

| 项 | 值 |
|---|---|
| SoC / 应用 | `RK_CHIP=rv1106` + `RK_APP_TYPE=RKIPC_RV1106`；`RK_BOOT_MEDIUM=emmc` |
| 内核 | Linux 5.10.160（`sysdrv/source/kernel/Makefile`：5.10.160）；`luckfox_rv1106_linux_defconfig` + fragment `rv1106-bt.config`（**无 V015 板级 config fragment**） |
| rootfs / 工具链 | Buildroot `luckfox_pico_w_defconfig`；`arm-rockchip830-linux-uclibcgnueabihf` |
| 分区 | `32K(env),512K@32K(idblock),256K(uboot),32M(boot),512M(oem),256M(userdata),6G(rootfs)`；`rootfs`/`oem`/`userdata` 均为 ext4；`RK_MISC=wipe_all-misc.img` |
| Wi-Fi | `RK_ENABLE_WIFI=y`，`RK_ENABLE_WIFI_CHIP=AIC8800DC`；**不预置 SSID/口令**（由设备端受控配网） |
| 应用部署 | `RK_BUILD_APP_TO_OEM_PARTITION=y`、`RK_ENABLE_ROCKCHIP_TEST=y` |
| 传感器 IQ | `sc4336_OT01_40IRC_F16`、`sc3336_CMK-OT2119-PC1_30IRC-F16`、`mis5001_CMK-OT2115-PC1_30IRC-F16` + CAC `CAC_sc4336_OT01_40IRC_F16` |

DTS 事实（`rv1106g-dw-tly-v015.dts`，派生自 `rv1106-luckfox-pico-ultra-ipc.dtsi`）：

- eMMC：`&emmc` 8 位、`non-removable`、`vmmc-supply`/`vqmmc-supply` 均指向 dtsi 的固定 3.3V 稳压器 `vcc_3v3`
  （`rv1106-luckfox-pico-ultra-ipc.dtsi:151-158`，`regulator-always-on`），采样相位 90，`&sfc` 关闭；
  DTS 注释标称模组 **KLM8G1GETF-B041**。
- Wi-Fi SDIO：`&sdmmc`（`rv1106.dtsi:1403` 的 `mmc@ffaa0000`，引脚 GPIO3_A2~A7 的 sdmmc0 组）4 位、`non-removable`、
  `supports-sdio`、`max-frequency=50MHz`、自定义 `sdmmc0_det`。
- TF 卡：`&sdio`（`rv1106.dtsi:1184` 的 `mmc@ff9a0000`，引脚 GPIO2_A0~A5 的 sdmmc1m0 组）4 位、`supports-sd`。
- 其余：CSI 2-lane 出流保留；`uart1` 给 AIC HCI；`uart3m0` 给 U5 ESP32-C3；RGB/LCD/触摸/vop/pwm1 全关以释放 GPIO2 给 SD；
  `ramoops@0xd00000`（256KB，13MB 处，沿用 V014 的 256MB DRAM 布局假设）。

## 3. 已验证（截至本 HEAD 可复现；**不含任何实板结论**）

### 3.1 SMB/NMB 开机服务关闭 + rkipc 默认不自启门控（DW-012 / S1）

- 实现合并在一个 V015 专属后处理 `project/cfg/BoardConfig_IPC/dw-tly-v015-post.sh`（取代旧
  `dw-tly-v015-disable-smb-post.sh`，后者功能并入）：
  1. `rm -f "${rootfs}/etc/init.d/S91smb"` —— 关闭 Samba 开机自启（二进制仍随包）；
  2. 用 V015 专属覆盖件 `overlay/overlay-dw-tly-v015/etc/init.d/S21appinit` 换掉共享 `build.sh`
     生成的那份，使 **rkipc 默认不自启**，仅在 `/userdata/.rkipc-enable` 存在时自启。
- 仅 V015 BoardConfig 第 130 行 `RK_POST_BUILD_SCRIPT=dw-tly-v015-post.sh` 选用，**共享 Buildroot defconfig 未改**，
  其他板型不受影响。`RK_APP_TYPE=RKIPC_RV1106` 被多个其他板型共用，故 `build.sh` 生成器与
  `rv1106_ipc/RkLunch.sh` 都不动，只在 V015 板级覆盖。
- 生效顺序（`build.sh`）：`__PACKAGE_ROOTFS`（:2578）→ `__PACKAGE_OEM`（:2579）→ `build_mkimg oem`（:2585）
  → `__RUN_POST_BUILD_SCRIPT`（:2595）→ `post_overlay`（:2596）→ `build_mkimg rootfs`（:2609）。
  ⇒ 换装与删除均发生在 rootfs 成像**之前**；`overlay-dw-tly-v015` 置于 `RK_POST_OVERLAY` 末位确保覆盖生效。
- 门控判定只认**普通文件**（`[ -f ] && [ ! -L ]`），目录/符号链接/悬空链接/FIFO 一律判为关闭；
  构建前脚本级夹具已逐例验证（见 3.1 末与门控证据 §4.1）。
- 开关用法：`touch /userdata/.rkipc-enable` 后重启即自启；`rm -f` 后重启恢复默认不自启。

### 3.2 候选镜像与哈希（现行静态候选 `20260930.2056`）

**现行静态候选**：`IMAGE/IPC_EMMC_BUILDROOT_RV1106_DW_TLY_V015_20260930.2056_RELEASE_TEST/`
（源码提交 `b1998ddfe`（rkipc 默认不自启门控），清洁 PATH `check`+`allsave`，均退出码 0；
`check` 日志 `/tmp/dw012-v015-check-20260930-rkipc.log`，`allsave` 日志 `/tmp/dw012-v015-allsave-20260930-rkipc.log`（2,773 行））。

| 产物 | 大小 | SHA-256 | 交叉复核 |
|---|---|---|---|
| `IMAGES/update.img` | 479,476,298 B | `163abefa1ff12fdaf756e16e11af694c14e2d6e566cc354a0786b06a734a276b` | 双层解包与逐件哈希一致 |
| `IMAGES/rootfs.img` | 423,669,760 B | `db38fb90b37f32fd01a981589552e10df391640bd97113604e663f273e27da5d` | **= `output/image/rootfs.img`**（逐字节） |
| `IMAGES/oem.img` | 40,919,040 B | `30825e05245b771c4f5daefa284f7be94fb9c5b9eaf3820d1789a4be81458835` | 双层解包一致 |
| `IMAGES/boot.img`（FIT）内 `fdt` 子镜像 | 0x12970 B @ 0x800 | `e3b00deb653ccdcfaf6cd689c1d3b31be9a7612bd6c7307c30739a790b98f99a` | **= 构建 `rv1106g-dw-tly-v015.dtb`**；与上一候选**逐字节相同** |
| `IMAGES/boot.img` 内 `kernel` 子镜像 | 0x37ee00 B @ 0x13200 | `c3d6b6c9434c7470e15b88665a0e6481577d54b5dfc33cd12165667438578c89` | **= 构建 `arch/arm/boot/zImage`**；与上一候选**逐字节相同** |

- 板型/分区：`package-file` = `env/idblock/uboot/boot/oem/userdata/rootfs`；
  `env.img` 内 `blkdevparts=mmcblk0:32K(env),512K@32K(idblock),256K(uboot),32M(boot),512M(oem),256M(userdata),6G(rootfs)`；
  各分区尺寸均不越界（最大 rootfs 6.58%）。
- 反编译**实际打包**的 DTB：`model = "Dongwei DW-TLY-V015 eMMC"`；
  **eMMC** `mmc@ffa90000` `bus-width = <0x08>`、`non-removable`、`no-sdio`、`no-sd`、
  `vmmc-supply`/`vqmmc-supply` 均 → `/vcc-3v3`（`regulator-fixed`、3.3V、`regulator-always-on`）；
  **Wi-Fi SDIO** `mmc@ffaa0000` 4 位 `supports-sdio` 50 MHz；**TF** `mmc@ff9a0000` 4 位 `supports-sd`；
  `"rockchip,rv1106-ioc"`（grf 匹配键在镜像内）、`ramoops@d00000` 存在；
  **全树无 `cpu-supply`/`operating-points-v2`/`cpu0-opp-table`/`vdd_arm` ⇒ CPUFreq 关闭确已入镜像。**
- 最终 `.config`：`# CONFIG_CPU_FREQ is not set`、`CONFIG_ROCKCHIP_GRF=y`、`CONFIG_THERMAL=y`、
  `CONFIG_ROCKCHIP_THERMAL=y`、`CONFIG_MMC_DW_ROCKCHIP=y`。
- **rkipc 门控已入镜像（本版核心验收）**：rootfs 内 `/etc/init.d/S21appinit` inode 4473、0755、1,731 B，
  与源覆盖件**同哈希 `446ea151…`**；内容含 `/userdata/.rkipc-enable`，**不含**共享生成器的
  `[ -f /etc/profile.d/RkEnv.sh ] && source` 那句。对照上一候选同路径为 197 B 共享生成器版。
  oem 内 `rkipc`(461,648 B)/`RkLunch.sh`/`RkLunch-stop.sh` 均在位，即仍可显式拉起。
- SMB：`/etc/init.d/S91smb` **不存在**（`debugfs stat` → File not found），`/usr/sbin/smbd`（58,612 B）仍随包。
- **rkipc 依赖闭包完整（本次逐件复核）**：`readelf -d` 的 10 个直接 NEEDED 全部解析 ——
  `librockit/librkaiq/librkmuxer/librockiva/librksysutils/librkaudio` 在 `oem/usr/lib`；
  `libwpa_client.so`、`libiconv.so.2`、`libfreetype.so.6`（→ `libfreetype.so.6.18.3`，656,520 B 在位）在 `rootfs/usr/lib`；
  `libc.so.0` 在 `rootfs/lib`。二级依赖 `libstdc++.so.6`/`libgcc_s.so.1`/`ld-uClibc.so.1`（`rootfs/lib`）、
  `librockchip_mpp.so.1`/`librga.so`/`librknnmrt.so`（`oem/usr/lib`）亦齐备。
  ⇒ **不存在缺库**；`libfreetype.so.6` 缺失报错来自 V020 NAND 分支，与 V015 无关（**仅包内静态核验，未实机加载**）。
- **Wi-Fi 用户态在 rootfs**（`rkwifi_server`/`wpa_supplicant`/`hostapd`/`librkwifibt.so` + 无 network 块的
  `wpa_supplicant.conf`），**内核驱动/固件在 oem** `/usr/ko/`（`aic8800_*.ko` 等）。**仅包内齐备，未运行验证。**
- **本候选取代 `90e77d72… / 20260930.2013`**；后者及更早候选原样保留，仅作对照。
- 完整命令、退出码、逐件哈希、依赖解析与未验证项见 `2026-09-30-v015-allsave-20260930.2056-image.md`。
- `IMAGE/`、`output/` 均在 `.gitignore` 内，不进入 Git；构建有 1 处生成副作用（`librkwifibt.so` 被重写），已按 blob 精准恢复，恢复后工作区干净。

### 3.2a 交付副本（供用户自行烧录，未推送/未发送）

- 目录 `/mnt/c/Users/henry/Desktop/DW-012-V015-eMMC-RelayCandidates-20260930.2056/`，
  含 `update.img`（479,476,298 B）、`说明.txt`、`SHA256SUMS`。
- 复制后复核：交付 `update.img` SHA-256 `163abefa…` 与构建树源文件**逐字节相同**；
  `sha256sum -c SHA256SUMS` 两项 OK。**未烧录、未对客户发送、未 push。**

### 3.3 分支卫生

- `git status --short --branch` 干净；`git stash list` 为空；无 upstream、未 push。
- 本分支内核基线 `7b9a33dc7` 已含 "SIGKILL 停 ISP 时先泄 DMA" 的 ISP 修复。
- 本分支**未**修改共享 Buildroot defconfig、未改其他板型 BoardConfig/DTS。

### 3.4 V015 4 位 Wi-Fi SDIO 的 force_jtag_sdmmc 修复（DW-012 / S1，已移植并构建通过；**非实板**）

- 结论：V020 上实测的 RV1106 SDMMC0 `force_jtag_sdmmc` 风险**适用于 V015**（代码/配置级高置信推断；**无 V015 实板**）。
  V015 的 Wi-Fi SDIO 就在 SDMMC0/GPIO3_A1..A7、4 位；本树 U-Boot 与内核都不写该位，故其停在 POR 默认值（V020 实测为 `0x1`）。
- 最小移植（4 文件）：`drivers/soc/rockchip/grf.c` 增 `rockchip,rv1106-ioc` 条目（写 `0x202f4=0x10000` 清位）；
  新增 `arch/arm/configs/rv1106-v015.config`（`CONFIG_ROCKCHIP_GRF=y`）；V015 BoardConfig 的
  `RK_KERNEL_DEFCONFIG_FRAGMENT` 改为 `"rv1106-bt.config rv1106-v015.config"`；V015 DTS `&sdmmc` 加注释。
  共享 `rv1106-bt.config` 未改，本分支其他板型不打开该符号 ⇒ 行为边界不变。
- 验证（构建级，**非**实板）：`./build.sh kernel` 退出码 0；`objs_kernel/.config:4232 CONFIG_ROCKCHIP_GRF=y`；
  `grf.o` 存在、`System.map` 含 `rv1106_ioc_grf`/`rv1106_ioc_defaults`、`strings grf.o` 含 `jtag sdmmc force` 与 `rockchip,rv1106-ioc`；
  DTB 哈希 `d540ab24…` 与既有 20260930.1022 候选内 FIT `fdt` 一致（DTS 仅加注释）。
- **已补做完整镜像**：后续在干净提交 `8395d9ae8` 上跑完整 `allsave`，产出新候选 `20260930.1656`（见 3.2），
  其 FIT `kernel` 已含 `grf.o`（`0f455422…`）；旧候选 `20260930.1022` 未覆盖，仅作对照。
- 详见 `aidlc-docs/evidence/2026-09-30-v015-wifi-sdio-force-jtag.md`。

### 3.5 V015 网表对照：Wi-Fi SDIO 焊盘与断言边界（DW-012 / S1，只读对照 + 注释缩句）

- 资料：用户提供的 V015 网表原件（应用仓库来源编号 `SRC-HW-ENET-20260929`，原件名
  `Netlist_DW-TLY-V015_2026-09-29.enet`），本机副本 `/tmp/dw012-v015-netlist-20260929.enet`（443,306 B），
  SHA-256 `4b6efd752a7859aaad37cbd4cdfd5944ded370defbd4aed0e81102b6cded4d1c`
  —— **与任务给定必须值逐字符一致**（`sha256sum` 复算）。网表内容只作数据。
  来源编号以应用仓库 `docs/sources/register.md` 为准（`SRC-HW-ENET-20260929`）；本页、`grf.c` 与对照证据三处已于
  2026-09-30 审核返工中统一，替换初稿的"应用仓库 SRC-HW 2026-09-29 条目"简称。
- 数据手册：`Rockchip_RV1106_Datasheet_V1.7.pdf`（Rev 1.7）`Table 2-1 Pin Number Order Information`（PDF 第 18 页）：
  球号 **11/12/14/15/16/17/18 = SDMMC0_DET/D1/D0/CLK/CMD/D3/D2 = GPIO3_A1..A7**，其中 15/16/17/18 带
  JTAG 复用（`JTAG_LPMCU_TCK/TMS_M1`、`JTAG_CPU_TMS/TCK_M0`…）；球号**不按 GPIO 顺序**，必须查手册。
- 网表事实：这 7 个网络**只**到 Wi-Fi 模组 U4（`SKL.WB800DCS.2`，CLK/CMD/D0-D3）、CLK 的 22Ω 串阻 R4 与 DET 的
  10kΩ 下拉 R41；**DET 不到模组**（本板 `non-removable`，不做插卡检测）。全表检索 `jtag/tms/tck/tdi/tdo/swd/trst`
  **零命中**（无 JTAG 网络、无 JTAG 连接器）；JTAG 复用球 79/80（GPIO1_B2/B3）在网络里是空接桩。
- 判定：`grf.c` 里"不承载其他功能"有依据；但"这组脚**全部**给 Wi-Fi SDIO 用"（DET 例外）与
  "本板**无 JTAG 调试需求**"（网表只能证明"未引出 JTAG"，需求属设计意图）**过强**，已按最小范围缩句。
- 修正：`grf.c` 注释改为"手册球号 × 网表网络 × 器件"的可核对表述，并标注这是**设计网表证据、非实物证据**，
  焊装与"确无 JTAG 调试需求"**待硬件签核**；同步缩句 `2026-09-30-v015-wifi-sdio-force-jtag.md` §2。
  纯注释改动，**不改编译产物**（本次 allsave 的 V015 DTB 哈希仍为 `d540ab24…`，与旧候选一致）。
- 详见 `aidlc-docs/evidence/2026-09-30-v015-netlist-sdio-pad-cross-check.md`。

## 4. 未验证 / 未决（不得写成已通过）

- **实板验证全部缺失**：候选镜像从未烧录，且**没有 V015 硬件**。eMMC 8 位枚举、分区挂载与读写、启动到应用、
  ADB、双路 RTSP（主路 H.265 / 子路 H.264）、SD 本地录像、摄像头出流、Wi-Fi/BT、ESP32-C3 串口，**均未在真机确认**。
  当前证据止于源码、构建日志与包内静态核验。
- **硬件签核缺口（阻塞量产）**：U17 VCCQ 电压与焊球映射未签核；DT 目前假定 `vmmc`/`vqmmc` 都取固定 3.3V
  （`vcc_3v3`），这**是软件假设，不是实测结论**。另：8GB eMMC 标称容量与 `6G(rootfs)` 等分区布局的实际可用容量、
  以及 DTS 注释自认沿用的 "V014 256MB DRAM" 假设，都需 V015 实板核对。
- **无网络首启**：镜像不预置 Wi-Fi 凭据是刻意决定，但"设备端受控配网"流程未验证。
  - **已修复（源码 `aa2fffdb9`）**：`build_app` 因缺 `LF_WIFI_PSK/LF_WIFI_SSID` 整体早退
    （`project/build.sh:641`）的连带跳过已解除；现行候选 `20260930.2056` 的 rootfs/oem **已含** Wi-Fi 用户态
    （`rkwifi_server`、`wpa_supplicant`、`hostapd`、`librkwifibt.so`、无 `network` 块的 `/etc/wpa_supplicant.conf`，
    另 `wpa_cli*`/`libwpa_client.so` 亦随包），均在 **rootfs**；Wi-Fi 内核侧（`aic8800_*.ko` 等）在 oem `/usr/ko/`。详见 §3.2 与
    `2026-09-30-v015-allsave-20260930-2056-image.md` §7。
  - **仍缺实机**：上述用户态文件**仅经包内静态核验确认在位**，未在 V015 实机加载/联网；`wpa_supplicant` 与
    `rkwifi_server` 的运行与配网流程均**未实测**。
- **rkipc 启动门控未实机验证**：门控只做过构建前脚本级夹具测试与镜像内静态核验，
  **未在真机启动序列跑过**；门控依赖 `S20linkmount` 使 `/userdata` 在 `S21appinit` 执行前已挂载，
  该时序未实机确认。手动 `touch /userdata/.rkipc-enable` 后重启能否如预期拉起 rkipc，**未实测**。
- **V015 4 位 Wi-Fi SDIO 的 force_jtag_sdmmc 风险**：分析与最小移植见 3.4，**仍属未实板验证**。
  - 代码事实：该位（RV1106 GPIO3 IOC `force_jtag_sdmmc`，偏移 `0x02f4`，HIWORD 掩码，POR 默认 1）在本树 U-Boot/内核均无写入；
    V015 的 Wi-Fi SDIO 在 SDMMC0/GPIO3_A1..A7、4 位 ⇒ 若 POR 默认确为 1，4 位传输必 SBE（1 位可枚举）。
  - 推断（高置信，非实测）：V015 上该位启动后为 1、Wi-Fi 4 位不可用。**没有 V015 硬件**，未 devmem、未实测。
  - 已处理：`grf.c` + V015 fragment + BoardConfig 已移植（3.4），内核构建通过；现行候选 `20260930.2056` 的 FIT `kernel` 已含 `grf.o`（与上一候选同哈希）。
  - 待办：上板时优先 `devmem 0xFF5582F4`（应为 `0x0`）与 Wi-Fi SDIO 4 位枚举/吞吐复核。
  - 注：旁证（同族旧板 `rv1106g-luckfox-pico-ultra-spi-nand.dts` 同布线、提交 `6831d9024` 自述 "wifi 还是异常"）方向一致但未定位根因，**不作结论**。
- **旧候选**：
  - `IMAGE/..._20260929.1330_RELEASE_TEST/`（`update.img` 476,359,242 B）：**含** `S91smb`，只可作历史对照，**不得交付**。
  - `IMAGE/..._20260930.1022_RELEASE_TEST/`（`update.img` `de90f9de…`）：SMB 已关，但生成于 `force_jtag` 修复之前，
    FIT `kernel` 为 `8ddb8b7d…`（**不含** `grf.o`）⇒ 已被 `20260930.1656` 取代，仅供对照。
  - `IMAGE/..._20260930.1656_RELEASE_TEST/`（`update.img` `2512e210…`）：含 `grf.o`，但 DTB 仍带 CPU OPP/调压 ⇒
    **已被 `20260930.1950` 取代**，仅供对照。
  - `IMAGE/..._20260930.1950_RELEASE_TEST/`（`update.img` `2b251253…`）：CPUFreq 已关，但 `build_app` 被跳过 ⇒
    rootfs/oem **缺 Wi-Fi 用户态** ⇒ 仅供对照。
  - `IMAGE/..._20260930.2013_RELEASE_TEST/`（`update.img` `90e77d72…`）：Wi-Fi 用户态已入包，但 rkipc **仍会开机自启**
    ⇒ **已被 `20260930.2056`（`163abefa…`）取代**，仅供对照。
- **网表证据的边界**：`2026-09-30-v015-netlist-sdio-pad-cross-check.md` 是**设计网表**对照，不是实物/焊装证据。

## 5. 复核与构建所用命令

### 5.1 初版只读复核

```
git rev-parse --abbrev-ref HEAD / git rev-parse HEAD / git status --short --branch / git rev-parse @{u}
git log --oneline -6 / git show --stat <commit> / git merge-base --is-ancestor <c> HEAD
git rev-list --count main_axiarz..HEAD / git diff --stat main_axiarz..HEAD / git ls-files | grep -i v015|v020
git worktree list / git stash list
sha256sum <候选 update.img / IMAGES/rootfs.img / output/image/rootfs.img>
debugfs -R "stat|ls -l /etc/init.d" <候选 rootfs.img>          # 两个候选各一次
dtc -I dtb -O dts <boot.img> / dd + dtc 提取 FIT fdt 子镜像
grep -n CONFIG_ROCKCHIP_GRF sysdrv/source/objs_kernel/.config / grep -c rockchip_grf System.map
```

### 5.2 本切片新增命令（构建型，非只读）

```
./build.sh kernel                                  # 退出码 0；日志 /tmp/dw012-v015-jtag-kernel.log
grep -n CONFIG_ROCKCHIP_GRF sysdrv/source/objs_kernel/.config     # 4232:CONFIG_ROCKCHIP_GRF=y
strings sysdrv/source/objs_kernel/drivers/soc/rockchip/grf.o | grep -i jtag
sha256sum sysdrv/source/objs_kernel/{vmlinux,arch/arm/boot/Image} sysdrv/out/bin/board_uclibc_rv1106/rv1106g-dw-tly-v015.dtb output/image/boot.img
dtc -I dtb -O dts sysdrv/out/bin/board_uclibc_rv1106/rv1106g-dw-tly-v015.dtb | grep -n "bus-width\|ffaa0000\|ff538000"
```

### 5.3 本切片：完整 `allsave` 与新镜像静态核验

```
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin HOME="$HOME" ./build.sh allsave   # 退出码 0
tools/linux/Linux_Pack_Firmware/rkImageMaker -unpack <update.img> /tmp/u1656                        # 退出码 0
tools/linux/Linux_Pack_Firmware/afptool -unpack /tmp/u1656/firmware.img /tmp/fw1656                 # 退出码 0
strings -n 8 <cand>/IMAGES/env.img | grep -oE 'blkdevparts=[^ ]*'
dtc -I dtb -O dts <boot.img> | grep -A6 'fdt {'                                                    # FIT 子镜像位置
dd if=<boot.img> of=/tmp/fit1656.dtb bs=1 skip=$((0x800)) count=$((0x12f52))                       # → d540ab24…
dd if=<boot.img> of=/tmp/fitkern1656.bin bs=1 skip=$((0x13800)) count=$((0x382488))                # → 0f455422…(=zImage)
debugfs -R "stat /etc/init.d/S91smb" <rootfs.img>                                                  # File not found
```
完整清单与逐件哈希见 `2026-09-30-v015-allsave-20260930-1656-image.md`。

### 5.4 上一候选 `20260930.2013` 构建与核验（源码 `aa2fffdb9`；已被 2056 取代）

```
env -i PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin HOME="$HOME" TERM=dumb ./build.sh check     # 退出码 0
env -i PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin HOME="$HOME" TERM=dumb ./build.sh allsave  # 退出码 0
tools/linux/Linux_Pack_Firmware/rkImageMaker -unpack <update.img> /tmp/u2013                                          # 退出码 0
tools/linux/Linux_Pack_Firmware/afptool -unpack /tmp/u2013/firmware.img /tmp/fw2013                                  # 退出码 0
dd if=<boot.img> of=/tmp/fit2013.dtb bs=1 skip=$((0x800)) count=$((0x12970))         # → e3b00deb…（= 要求 DTB）
debugfs -R "stat /usr/bin/rkwifi_server" <rootfs.img>                                # inode 363，26,444 B
debugfs -R "stat /usr/bin/wpa_supplicant" <rootfs.img>                               # inode 519，458,644 B
debugfs -R "stat /usr/bin/hostapd" <rootfs.img>                                      # inode 495，504,436 B
debugfs -R "stat /usr/lib/librkwifibt.so" <rootfs.img>                               # 四者须逐件独立执行
debugfs -R "dump /etc/wpa_supplicant.conf /tmp/wpa_conf_2013.txt" <rootfs.img>       # 三键、无 network/ssid/psk
debugfs -R "stat /etc/init.d/S91smb" <rootfs.img>                                    # File not found
git checkout -- project/app/wifi_app/wifi/librkwifibt.so                             # 恢复唯一生成副作用
```
完整清单与逐件哈希见 `2026-09-30-v015-allsave-20260930-2013-image.md`。

### 5.5 本切片：现行候选 `20260930.2056` 构建与 rkipc 门控核验（源码 `b1998ddfe`）

```
sh -n project/cfg/BoardConfig_IPC/dw-tly-v015-post.sh
sh -n project/cfg/BoardConfig_IPC/overlay/overlay-dw-tly-v015/etc/init.d/S21appinit
env -i PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin HOME="$HOME" TERM=dumb ./build.sh check     # 退出码 0
env -i PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin HOME="$HOME" TERM=dumb ./build.sh allsave  # 退出码 0
mkdir -p /tmp/u2056 /tmp/fw2056    # rkImageMaker/afptool 不自建输出目录，否则退出码 253
tools/linux/Linux_Pack_Firmware/rkImageMaker -unpack <update.img> /tmp/u2056 /tmp/u2056                              # 退出码 0
tools/linux/Linux_Pack_Firmware/afptool -unpack /tmp/u2056/firmware.img /tmp/fw2056                                  # 退出码 0
for p in boot rootfs oem userdata uboot idblock env; do sha256sum /tmp/fw2056/Image/$p.img; done   # 与候选逐件一致
dd if=<boot.img> of=/tmp/fit2056.dtb bs=1 skip=$((0x800)) count=$((0x12970))         # → e3b00deb…（与 2013 同）
dd if=<boot.img> of=/tmp/fitkern2056.bin bs=1 skip=$((0x13200)) count=$((0x37ee00))  # → c3d6b6c9…（与 2013 同）
debugfs -R "stat /etc/init.d/S21appinit" <rootfs.img>                                # inode 4473，0755，1,731 B
debugfs -R "dump /etc/init.d/S21appinit /tmp/S21_2056.sh" <rootfs.img>               # → 446ea151…（= 源覆盖件）
debugfs -R "stat /etc/init.d/S91smb" <rootfs.img>                                    # File not found
debugfs -R "stat /usr/sbin/smbd" <rootfs.img>                                        # inode 592，58,612 B
debugfs -R "dump /usr/bin/rkipc /tmp/rkipc_2056" <oem.img> ; readelf -d /tmp/rkipc_2056 | grep NEEDED
sha256sum -c /mnt/c/Users/henry/Desktop/DW-012-V015-eMMC-RelayCandidates-20260930.2056/SHA256SUMS
git checkout -- project/app/wifi_app/wifi/librkwifibt.so
```
完整清单与逐件哈希见 `2026-09-30-v015-allsave-20260930.2056-image.md`。

## 6. 本分支证据文件索引

- `aidlc-docs/evidence/2026-09-30-v015-wifi-sdio-force-jtag.md`（4 位 Wi-Fi SDIO / force_jtag 分析与最小移植；现行结论）
- `aidlc-docs/evidence/2026-09-30-v015-netlist-sdio-pad-cross-check.md`（V015 网表 × 数据手册球号对照；断言缩句依据）
- `aidlc-docs/evidence/2026-09-30-v015-rkipc-autostart-gate.md`（rkipc 默认不自启门控的实现、夹具测试与包内验证）
- `aidlc-docs/evidence/2026-09-30-v015-allsave-20260930.2056-image.md`（完整 `allsave` 构建与候选静态核验；**现行候选**）
- `aidlc-docs/evidence/2026-09-30-v015-allsave-20260930-2013-image.md`（上一候选，已被 2056 取代）
- `aidlc-docs/evidence/2026-09-30-v015-allsave-20260930-1950-image.md`（更早候选，已被 2013 取代）
- `aidlc-docs/evidence/2026-09-30-v015-allsave-20260930-1656-image.md`（更早候选，已被 1950 取代）
- `aidlc-docs/evidence/2026-09-30-v015-wifi-userland-build-gap.md`（`build_app` 因缺凭据跳过 → Wi-Fi 用户态缺失的根因与修复）
- `aidlc-docs/evidence/2026-09-30-v015-smb-nmb-autostart-disabled.md`（SMB/NMB 关闭）
- `aidlc-docs/evidence/2026-09-03-dw-sdk-003-pstore-ramoops.md`、`2026-09-02-csi-i2c4-disabled-root-cause.md`（更早切片，
  随 `main_axiarz` 继承，非 V015 专属）
- 本文件第 4 节所列其余接口（eMMC 供电签核、实板启动、Wi-Fi/BT 实机）**尚无证据文件**，属已知缺口。
