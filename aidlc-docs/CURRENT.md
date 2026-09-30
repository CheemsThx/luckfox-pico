# DW-012 当前状态快照（SDK 仓 / `codex/dw-012-v020-nand-validation`）

- 生成日期：2026-09-30（本文件由一次只读复核产生；除本文件外未改动任何仓库文件）
- 仓库与工作树：`/home/henry/rv1106/luckfox-pico-v020-main-axiarz`（git worktree）
- 分支：`codex/dw-012-v020-nand-validation`
- 起点/HEAD：`f2fd2dee9b339ba044f7813aaac9f1c10f57a58d`（"为 SDK 工作分支固化 Claude 执行规则"）
- 工作区：`git status --short --branch` 干净；本分支**无 upstream**（未 push、未设跟踪）
- 相对 `main`：领先 22 个提交
- 本文件**不是**验收结论或交付说明，只登记截至上述 HEAD 的现状、已验证项、未验证项与已知证据缺口

## 1. 边界：V020 NAND 验证板 ≠ V015 eMMC 量产

- DW-012 的**量产目标是 V015 eMMC**。V020 NAND 是**尚未定型的验证板**；用户手头的 V020 板移用了
  V014 样品芯片，且**没有 V015 量产板**。
- 本分支只承载 **V020 SPI NAND** 的验证性改动。本分支内**不存在** V015 / eMMC 的 BoardConfig、
  DTS 或提交（`git ls-files | grep -i v015` 无板级产物；`rv1106g-dw-tly-v015.dts` 不在本树）。
- V015 eMMC 适配在**另一个 worktree**：`/home/henry/rv1106/luckfox-pico-v015-main-axiarz`，
  分支 `codex/dw-012-v015-emmc-adaptation` @ `fd97d65cb`（`git worktree list` 实测）。该树的改动、
  构建与证据**不属于本分支**，本文件不代其背书。
- 因此：**本分支产出的 V020 候选镜像只能供用户自行烧录验证，不得称其为 V015 量产固件，
  也不得称 V015 eMMC 已获硬件签核或可刷到 V020。**

## 2. 本分支承载的板级事实（代码事实，可在本树复核）

| 项 | 值 |
|---|---|
| BoardConfig | `project/cfg/BoardConfig_IPC/BoardConfig-SPI_NAND-Buildroot-RV1106_DW-TLY-V020-IPC.mk` |
| 顶层 DTS | `sysdrv/source/kernel/arch/arm/boot/dts/rv1106g-dw-tly-v020.dts`（`model = "DW-TLY-V020 W"`） |
| 板级 dtsi | `sysdrv/source/kernel/arch/arm/boot/dts/rv1106-dw-tly-v020-ipc.dtsi` |
| 内核 fragment | `sysdrv/source/kernel/arch/arm/configs/rv1106-v020.config` |
| 内核 | Linux 5.10.160 |
| rootfs / 介质 | Buildroot（`luckfox_pico_ultra_spi_nand_ipc_defconfig`）/ SPI NAND（UBIFS） |
| 存储布局 | `256K(env),256K@256K(idblock),512K(uboot),4M(boot),30M(oem),32M(userdata),188M(rootfs)`；无 misc、无 recovery，`RK_ENABLE_RECOVERY=` 空（本版不交付 OTA） |
| 关键外设 | SD 走 sdmmc0、WiFi(SDIO) 走 sdmmc1m0；BLE HCI 走 uart0m1，靠别名 `serial1=&uart0` 落到 `/dev/ttyS1`；I2C0 上 `cw2015@62` + `ti,bq25601@6b`；PWM3/PWM4 激光/补光；backlight/pwm1 disabled |

## 3. 已验证（本分支内可复现；不含任何实板结论）

### 3.1 SMB/NMB 开机服务关闭（DW-012 / S2）

- 实现：`project/cfg/BoardConfig_IPC/luckfox-buildroot-ble-fix-post.sh:40-45`，仅当
  `RK_KERNEL_DTS = rv1106g-dw-tly-v020.dts` 时 `rm -f "${ROOTFS}/etc/init.d/S91smb"`。
- 生效顺序（`project/build.sh`）：`__RUN_POST_BUILD_SCRIPT`（:2579）→ `post_overlay`（:2580）→
  `build_mkimg $GLOBAL_ROOT_FILESYSTEM_NAME`（:2592）生成 `rootfs.img`。删除发生在 rootfs 成像**之前**。
- V020 的 `RK_POST_OVERLAY` 五个 overlay 均不含 `S91smb`（只有未启用的 `overlay-luckfox-buildroot-tiny`
  有），故后续 overlay 不会把开机入口加回。
- 本次独立复核（新建 `/tmp` 夹具、两种 DTS 各跑一次脚本）结果：V020 DTS → `S91smb` 被移除；
  V014 DTS（`rv1106g-luckfox-pico-ultra-spi-nand.dts`）→ `S91smb` 保留。与
  `2026-09-30-v020-smb-nmb-autostart-disabled.md` 的夹具结论一致。
- 构建日志 `/tmp/dw012-v020-smb-off-allsave.log`（310210 B，仍在）内：`luckfox-buildroot-ble-fix-post:
  V020 SMB/NMB autostart disabled`（:3485）出现在 rootfs 的 `mkfs.ubifs`/ubinize 打包之前；
  随后 `Running build_allsave succeeded.`（:4002），退出码 0。

### 3.2 V020 CPU 动态调频/调压撤销（DW-012 / S2）

- 板级 dtsi `&cpu0` 删除 `operating-points-v2`、`cpu-supply`，并 `/delete-node/ &cpu0_opp_table;`
  （`rv1106-dw-tly-v020-ipc.dtsi:260-265`）。
- 内核 fragment 关闭 `CPU_FREQ` / `CPUFREQ_DT` / `ARM_ROCKCHIP_CPUFREQ`；构建出的
  `sysdrv/source/objs_kernel/.config:445` = `# CONFIG_CPU_FREQ is not set`，
  `CONFIG_ROCKCHIP_THERMAL=y` 保留。
- `grep -c cpufreq sysdrv/source/objs_kernel/System.map` = 0。
- 交付 DTB 反编译：`cpu@0` 只剩 `device_type/compatible/reg/clocks`，
  `cpu-supply` / `operating-points` 计数 0；`hw-tshut-temp`、`soc-crit` 仍在。
- 该结论的完整推导、以及"U-Boot 默认 816MHz / Linux 运行期预期 1.104GHz"的更正，见
  `2026-09-30-v020-cpu-dvfs-removed.md`。

### 3.3 候选镜像与哈希（本次独立复算，全部一致）

| 产物 | SHA-256 | 交叉复核 |
|---|---|---|
| `IMAGE/IPC_SPI_NAND_TLY_V020_20260930.1010_RELEASE_TEST/IMAGES/update.img`（81,013,322 B） | `d9cf335afcbb4bd0969e3ee515354423fa827e1beee988009d0dafc1875fe47f` | = Windows 候选目录同名文件 |
| 同上目录 `rootfs.img` | `5f5cbc7231b8190b6e3344fc86c1d194c3e0d7d4b644d96d8e7a1c9451a1e813` | = `output/image/rootfs.img`；= `afptool`/`rkImageMaker` 双层解包所得包内 rootfs |
| 同上目录 `boot.img` | `003e4f28a969791bbb09570ea6935240cb8629299581978dae7e95fcf55155b2` | = Windows 候选目录同名文件 |
| `output/out/sysdrv_out/board_uclibc_rv1106/rv1106g-dw-tly-v020.dtb` | `2677c4e2f7cdff23a85c36443529034f6566c1944f8362cc959f5c060e5f3704` | = `boot.img` 内 FIT `fdt` 的 hash（`mkimage -l`）= Windows 候选目录 `.dtb` |
| Windows 候选 `C:\Users\henry\Documents\Linux\DW-TLY-V020-5.10.160-candidate-d9cf335a\` | — | `sha256sum -c SHA256SUMS` 三项全 `OK`（update.img / boot.img / dtb） |

- 构建来源：从干净功能提交 `ebf61369f` 运行 `PATH=/usr/local/sbin:... ./build.sh allsave`（退出码 0）。
- 静态包内检查：打包源目录 `output/out/rootfs_uclibc_rv1106/etc/init.d/` 内**无** `S91smb`。
- Windows 候选目录的 `MANIFEST.txt` 明确标注：未 push、未烧录、仅供 V020 NAND 验证板自行烧录，
  量产目标仍为 V015 eMMC。

## 4. 未验证 / 未决（不得写成已通过）

- **实板验证全部缺失**：候选镜像从未烧录。SMB/NMB 是否真的不启动、`smbd`/`nmbd` 是否不运行、
  串口是否不再打印 `Starting SMB/NMB services`，以及 ADB / 双路 RTSP / SD 本地录像 / 充电与电量计
  是否正常，均**未在真机确认**。当前证据止于源码、构建日志与包内静态核验。
- **CPU 运行频点未实测**：静态预期运行期 1.104GHz@0.9V（U-Boot 默认 816MHz），稳定性待上板确认。
- **V020 板级未决现象（背景，非本分支证据）**：该板自 2026-09-23 起存在无 panic 的间歇硬复位
  （约 18s 停在摄像头出流）排查记录；本分支 `aidlc-docs/evidence/` 内**没有**对应文件。本候选
  （含已恢复的 BQ25601 驱动与 BQ25601 QON 复位通路）是否复发**未知**，烧录前应知晓此风险。
- **WiFi/SDIO 性能与"4 位 SD 读"实板复测**：相关补丁在本分支（`grf.c` force_jtag 修复、AIC8800
  固件打包），但本分支证据目录内没有实测数据文件；性能/稳定性结论不在此登记。
- **V015 eMMC**：本分支未做任何 V015 适配或验证；V015 的 SMB 关闭由**另一 worktree/branch** 的
  独立脚本实现（`/tmp/dw012-v015-smb-off-allsave.log` 内的标记为 `dw-tly-v015-disable-smb-post`），
  与本分支 V020 的 `luckfox-buildroot-ble-fix-post.sh` 实现**不是同一处代码**，不能互相代替验证。

## 5. 已知证据缺口（本次复核发现）

- `2026-09-30-v020-smb-nmb-autostart-disabled.md` 第 8 节称"新镜像 rootfs 字节中找不到 `S91smb`
  文件名，而前一候选 rootfs 中可找到"的**字节扫描辅助检查不成立，应弃用**：
  `rootfs.img` 是 `UBI image, version 1`（UBIFS，目录项被压缩），对**任何**存在的脚本名都匹配不到。
  实测在对所有 6 个 V020 候选（含改动前的 0936、0905 等）扫描 `S91smb`、`S40network`、`S50sshd`、
  `smbd`、`nmbd`，结果**一律为 0**，说明该方法无区分力；前一候选 `176faa8c` 目录内甚至不含
  `rootfs.img`。该条不否定主论据（打包源目录无 `S91smb` + 包内 rootfs 与 `output/image/rootfs.img`
  逐字节一致 + 构建日志顺序），但**不应作为独立证据引用**。
- 受上述限制，本复核**未能**在离线环境内直接解包 UBI/UBIFS 以列出包内 `/etc/init.d`（`ubireader`
  未安装，WSL 内核无 `nandsim`/`ubifs` 模块）；包内 `S91smb` 缺失目前由"打包源目录 + 成像顺序"
  推定，而非对 UBI 内容逐一枚举。

## 6. 本分支证据文件索引

- `aidlc-docs/evidence/2026-09-30-v020-smb-nmb-autostart-disabled.md`（SMB/NMB 关闭；其字节扫描结论见第 5 节更正）
- `aidlc-docs/evidence/2026-09-30-v020-cpu-dvfs-removed.md`（CPU DVFS 撤销；现行结论）
- `aidlc-docs/evidence/2026-09-30-v020-cpu-dvfs-fixed-0v9.md`（原"限频"方案，**结论已被上一条取代**，仅根因分析可参考）
- `aidlc-docs/evidence/2026-09-03-dw-sdk-003-pstore-ramoops.md`、`2026-09-02-csi-i2c4-disabled-root-cause.md`（更早切片）
