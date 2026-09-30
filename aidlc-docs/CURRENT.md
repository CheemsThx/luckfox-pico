# DW-012 当前状态快照（SDK 仓 / `codex/dw-012-v015-emmc-adaptation`）

- 生成日期：2026-09-30（初版为只读复核；本节随 DW-012 / S1「4 位 Wi-Fi SDIO 与 force_jtag_sdmmc」切片更新，该切片含源码/配置最小修复与内核构建）
- 仓库与工作树：`/home/henry/rv1106/luckfox-pico-v015-main-axiarz`（`git worktree list` 实测，主仓为 `/home/henry/rv1106/luckfox-pico`）
- 分支：`codex/dw-012-v015-emmc-adaptation`
- 起点/HEAD（本切片改动前）：`077b56b3d1dbc906c36d259f9a2f3e10e9370ae4`（"限制 Claude 工作切片不得写入仓库外记忆"）
- 工作区：本切片开始与结束时均无未提交脏文件；本分支**无 upstream**（`git rev-parse @{u}` → `fatal: no upstream configured`）
- 相对本树基线 `main_axiarz`（`7b9a33dc7`）领先 4 个提交（本切片提交另计）
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
| `project/cfg/BoardConfig_IPC/BoardConfig-EMMC-Buildroot-RV1106_DW_TLY_V015-IPC.mk` | V015 eMMC 板级配置（含内核 fragment 挂接） |
| `project/cfg/BoardConfig_IPC/dw-tly-v015-disable-smb-post.sh` | V015 专属 rootfs 后处理（关闭 Samba 开机自启） |
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

### 3.1 SMB/NMB 开机服务关闭（DW-012 / S1）

- 实现：`project/cfg/BoardConfig_IPC/dw-tly-v015-disable-smb-post.sh` —— `rm -f "${rootfs}/etc/init.d/S91smb"`；
  仅 V015 BoardConfig 第 128 行 `RK_POST_BUILD_SCRIPT=dw-tly-v015-disable-smb-post.sh` 选用，**共享 Buildroot defconfig 未改**，
  其他板型不受影响。Samba 二进制仍随包，关闭的只是开机自动启动。
- 生效顺序（`build.sh`）：`__RUN_POST_BUILD_SCRIPT`（:2579）→ `post_overlay`（:2580）→ `build_mkimg $GLOBAL_ROOT_FILESYSTEM_NAME`（:2593）
  生成 `rootfs.img`。删除发生在 rootfs 成像**之前**；V015 的 5 个 `RK_POST_OVERLAY` 目录内均无 `S91smb`（`grep -rl` 为空），
  后续 overlay 不会把它加回。
- 本次独立复核（只读）：
  - 打包源目录 `output/out/rootfs_uclibc_rv1106/etc/init.d/` 中**无** `S91smb`（`S20linkmount`、`S20pstore` 等在）。
  - `debugfs -R "stat /etc/init.d/S91smb"` 对**候选** `IMAGES/rootfs.img` → `File not found`；`stat` 脚本可正常列出，
    同一镜像内 `/usr/sbin/smbd` inode 存在（二进制保留）。
  - 同一命令对**上一版**候选 `IMAGE/..._20260929.1330_RELEASE_TEST/IMAGES/rootfs.img` → `S91smb` inode 4469 **存在**：
    即 `20260929.1330` 候选仍会开机拉起 Samba，**已被 `20260930.1022` 取代，不得交付**。
  - 构建日志 `/tmp/dw012-v015-smb-off-allsave.log`（171,621 B，mtime 2026-09-30 10:22）第 1745 行含
    `dw-tly-v015-disable-smb-post: SMB/NMB autostart disabled`，第 1996 行 `Running build_allsave succeeded.`。
- 完整推导与首次记录见 `aidlc-docs/evidence/2026-09-30-v015-smb-nmb-autostart-disabled.md`。

### 3.2 候选镜像与哈希（本次独立复算，与既有证据一致）

| 产物 | 大小 | SHA-256 | 交叉复核 |
|---|---|---|---|
| `IMAGE/IPC_EMMC_BUILDROOT_RV1106_DW_TLY_V015_20260930.1022_RELEASE_TEST/IMAGES/update.img` | 476,355,146 B | `de90f9deea52bb3e904999dddb3a03f414d54752a13d3e14e31e884e869bf68f` | 与证据文件记录一致 |
| 同目录 `rootfs.img` | 421,441,536 B | `552c62f16e16fb1d89c9cb99d788ef998c6e7802fe1885552ce614c9e0710f9c` | **= `output/image/rootfs.img`**（哈希、大小、mtime 10:22:21 均一致） |
| 同目录 `boot.img` 内 FIT `fdt` 子镜像 | 0x12f52 B @ 0x800 | `d540ab24319e7fe210e888a5ec7f888564941bc319fa2bf8aed5c5b60a2806e5` | **= 构建产出的 `sysdrv/out/bin/board_uclibc_rv1106/rv1106g-dw-tly-v015.dtb`**（两处构建副本同哈希） |

- `boot.img` 是 FIT（不是 Android boot 镜像）：`dtc -I dtb -O dts` 读出 `fdt` 的 `data-position=0x800 / data-size=0x12f52`，
  切出后哈希与 FIT 头内 `hash value` 自证一致。反编译该**实际打包**的 DTB：`model = "Dongwei DW-TLY-V015 eMMC"`、
  `compatible = "dongwei,dw-tly-v015"...`、`mmc@ffa90000` 为 `bus-width = <0x08>`、`ramoops@d00000` 存在 —— 即镜像内的
  DTB 确实来自本分支 V015 DTS，而不是别的板型。
- 双层解包（`rkImageMaker -unpack` + `afptool -unpack`）包内 ext4 `rootfs.img` 与 `output/image/rootfs.img` 逐字节一致，
  见 3.1 所述证据文件。
- 构建来源：从干净功能提交执行 `PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin ./build.sh allsave`，
  退出码 0；`IMAGE/`、`output/` 均在 `.gitignore` 内，不进入 Git。

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
  DTB 哈希 `d540ab24…` 与既有 20260930.1022 候选内 FIT `fdt` 一致（DTS 仅加注释）；本次未产新镜像、既有候选未覆盖。
- 详见 `aidlc-docs/evidence/2026-09-30-v015-wifi-sdio-force-jtag.md`。

## 4. 未验证 / 未决（不得写成已通过）

- **实板验证全部缺失**：候选镜像从未烧录，且**没有 V015 硬件**。eMMC 8 位枚举、分区挂载与读写、启动到应用、
  ADB、双路 RTSP（主路 H.265 / 子路 H.264）、SD 本地录像、摄像头出流、Wi-Fi/BT、ESP32-C3 串口，**均未在真机确认**。
  当前证据止于源码、构建日志与包内静态核验。
- **硬件签核缺口（阻塞量产）**：U17 VCCQ 电压与焊球映射未签核；DT 目前假定 `vmmc`/`vqmmc` 都取固定 3.3V
  （`vcc_3v3`），这**是软件假设，不是实测结论**。另：8GB eMMC 标称容量与 `6G(rootfs)` 等分区布局的实际可用容量、
  以及 DTS 注释自认沿用的 "V014 256MB DRAM" 假设，都需 V015 实板核对。
- **无网络首启**：镜像不预置 Wi-Fi 凭据是刻意决定，但"设备端受控配网"流程未验证。
- **V015 4 位 Wi-Fi SDIO 的 force_jtag_sdmmc 风险**：分析与最小移植见 3.4，**仍属未实板验证**。
  - 代码事实：该位（RV1106 GPIO3 IOC `force_jtag_sdmmc`，偏移 `0x02f4`，HIWORD 掩码，POR 默认 1）在本树 U-Boot/内核均无写入；
    V015 的 Wi-Fi SDIO 在 SDMMC0/GPIO3_A1..A7、4 位 ⇒ 若 POR 默认确为 1，4 位传输必 SBE（1 位可枚举）。
  - 推断（高置信，非实测）：V015 上该位启动后为 1、Wi-Fi 4 位不可用。**没有 V015 硬件**，未 devmem、未实测。
  - 已处理：`grf.c` + V015 fragment + BoardConfig 已移植（3.4），内核构建通过。
  - 待办：上板时优先 `devmem 0xFF5582F4`（应为 `0x0`）与 Wi-Fi SDIO 4 位枚举/吞吐复核。
  - 注：旁证（同族旧板 `rv1106g-luckfox-pico-ultra-spi-nand.dts` 同布线、提交 `6831d9024` 自述 "wifi 还是异常"）方向一致但未定位根因，**不作结论**。
- **旧候选**：`IMAGE/..._20260929.1330_RELEASE_TEST/`（`update.img` 476,359,242 B）仍含 `S91smb`，只可作历史对照，不得交付。

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

## 6. 本分支证据文件索引

- `aidlc-docs/evidence/2026-09-30-v015-wifi-sdio-force-jtag.md`（4 位 Wi-Fi SDIO / force_jtag 分析与最小移植；现行结论）
- `aidlc-docs/evidence/2026-09-30-v015-smb-nmb-autostart-disabled.md`（SMB/NMB 关闭）
- `aidlc-docs/evidence/2026-09-03-dw-sdk-003-pstore-ramoops.md`、`2026-09-02-csi-i2c4-disabled-root-cause.md`（更早切片，
  随 `main_axiarz` 继承，非 V015 专属）
- 本文件第 4 节所列其余接口（eMMC 供电签核、实板启动、Wi-Fi/BT 实机）**尚无证据文件**，属已知缺口。
