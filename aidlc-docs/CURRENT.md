# DW-012 当前状态快照（SDK 仓 / `codex/dw-012-v020-nand-validation`）

- 生成日期：2026-09-30（初版由只读复核产生；2026-09-30 晚追加 rkipc 门控返工记录）
- 仓库与工作树：`/home/henry/rv1106/luckfox-pico-v020-main-axiarz`（git worktree）
- 分支：`codex/dw-012-v020-nand-validation`
- 起点/HEAD：初版 `f2fd2dee9b339ba044f7813aaac9f1c10f57a58d`；现 HEAD 见 `git log -1`
- 工作区：构建会重写受版本控制的 `project/app/wifi_app/wifi/librkwifibt.so`（`allsave` 既有副作用）；
  本分支**无 upstream**（未 push、未设跟踪）
- 相对 `main`：领先若干提交
- 2026-09-30 二次复核：第 5 节原"字节扫描无区分力"结论系 `grep` 包装函数误判，**已更正**（见第 5 节）
- 2026-09-30 三次追加：**`20260930.2054` 候选镜像门控失效**（详见第 7 节）。该镜像 rkipc 仍开机
  自启，**不可作候选**；修复版 `20260930.2112` 已构建并静态核验。
- 本文件**不是**验收结论或交付说明，只登记截至当前 HEAD 的现状、已验证项、未验证项与已知证据缺口

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

### 3.3 V020 rkipc 默认自启门控（DW-012 / S2）—— 2026-09-30 返工

> **结论更正**：前一提交 `00018c57a` 用"把 `S21appinit` 改名为 `S21appinit.disabled`"关闭自启，
> **无效**。`20260930.2054` 镜像 rkipc 仍会开机启动。详见第 7 节与证据文件
> `2026-09-30-v020-rkipc-autostart-gate-rework.md`。

- 根因：rootfs 的 `etc/init.d/rcS` 用 `for i in /etc/init.d/S??* ;do` 枚举，`S??*` 只要求
  `S`+两位数字、后缀任意，`S21appinit.disabled` **仍匹配**；rcS 只跳过目录/悬空链接，
  普通文件照常 `$i start`。
- 现行实现：保留 `S21appinit` 文件名，改用 V020 专属覆盖件
  `project/cfg/BoardConfig_IPC/overlay/overlay-luckfox-buildroot-config/etc/init.d/S21appinit`
  （sha256 `cd45ebe1…0817ef`），`start)` 判 `/userdata/.rkipc-enable` 为**普通文件**才启动；
  覆盖件经 `RK_POST_OVERLAY` 末位在 rootfs 成像前覆盖生成器产物。共享脚本/V014 不动。
- 时序：`S20linkmount` 先挂 `/userdata`（UBI volume，`ubiattach`+`ubirsvol` 扩满再 mount），
  再到 `S21appinit`；挂载失败时 rcS 不中止，门控按"关闭"处理。
- 起点提交正文"由 S20pstore 按 `.enable` 自动还原入口"为**错误陈述**：S20pstore 全文无
  `.enable`/`mv`/`S21`，且该提交未改 S20pstore。已删除该说法。

### 3.4 候选镜像与哈希（本次独立复算，全部一致）

| 产物 | SHA-256 | 交叉复核 |
|---|---|---|
| `IMAGE/IPC_SPI_NAND_TLY_V020_20260930.1010_RELEASE_TEST/IMAGES/update.img`（81,013,322 B） | `d9cf335afcbb4bd0969e3ee515354423fa827e1beee988009d0dafc1875fe47f` | = Windows 候选目录同名文件 |
| 同上目录 `rootfs.img` | `5f5cbc7231b8190b6e3344fc86c1d194c3e0d7d4b644d96d8e7a1c9451a1e813` | = `output/image/rootfs.img`；= `afptool`/`rkImageMaker` 双层解包所得包内 rootfs |
| 同上目录 `boot.img` | `003e4f28a969791bbb09570ea6935240cb8629299581978dae7e95fcf55155b2` | = Windows 候选目录同名文件 |
| `output/out/sysdrv_out/board_uclibc_rv1106/rv1106g-dw-tly-v020.dtb` | `2677c4e2f7cdff23a85c36443529034f6566c1944f8362cc959f5c060e5f3704` | = `boot.img` 内 FIT `fdt` 的 hash（`mkimage -l`）= Windows 候选目录 `.dtb` |
| Windows 候选 `C:\Users\henry\Documents\Linux\DW-TLY-V020-5.10.160-candidate-d9cf335a\` | — | `sha256sum -c SHA256SUMS` 三项全 `OK`（update.img / boot.img / dtb） |

- 构建来源：从干净功能提交 `ebf61369f` 运行 `PATH=/usr/local/sbin:... ./build.sh allsave`（退出码 0）。
- 静态包内检查：打包源目录 `output/out/rootfs_uclibc_rv1106/etc/init.d/` 内**无** `S91smb`。
- **注**：上表为 `20260930.1010` 候选；**`20260930.2054` 不得再作候选**（门控失效）。最新为
  `20260930.2112`，见第 7.3 节。
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

## 5. 证据缺口与二次复核更正

### 5.1 更正：字节对照并非"无区分力"

- **撤销**本文件先前登记的"对所有 6 个候选扫描 `S91smb`/`S40network`/`S50sshd`/`smbd`/`nmbd`
  一律为 0、字节扫描无区分力"这一结论。该结论**系工具误判，不成立**。
- 误判成因：本环境交互 shell 中的 `grep` 是**包装函数**（转发到自带 `ugrep`，并前置 `-I` 跳过
  二进制文件）。对 `file` 判定为二进制（`UBI image, version 1`）的 `rootfs.img`，它一律返回
  rc=1、计数 0；而系统 `/usr/bin/grep`（GNU grep 3.7）`grep -c` 即使**不加** `-a` 也能正常计数
  （0936 得 1）。前次"一律为 0"由此产生。
- 二进制安全复验（`LC_ALL=C grep -aob -m1`，显式 `-a`，6 个候选逐一扫描）：

  | 候选 | `S91smb` | `S40network` | `S50sshd` |
  |---|---|---|---|
  | 2230 / 2309 / 2354 / 0905 / 0936 | `55999064` | `55994928` | `55996416` |
  | 1010 | **未命中** | `55994928` | `55996416` |

- 结论：该**原始字节对照在 0936 与 1010 这两个具体候选之间有区分力**（1010 起少了 `S91smb`，
  其余脚本名偏移不变），与 `2026-09-30-v020-smb-nmb-autostart-disabled.md` 第 8 节的**原表述一致**，
  后者无需改动。
- **机理与限度**：命中的是 UBIFS 中未压缩存储的目录项名（0936 中 `S91smb` 名称之后紧跟其数据
  znode，可见 `LUCKFOX_FDT_DTB=/tmp/...` 等压缩后的脚本内容）。但整文件字节扫描**不是对 UBIFS 树
  的枚举**（本复核未解析 UBIFS，目录项可能落在不同 LEB），因此**"未命中"仍不能单独证明 UBIFS 中
  绝对不存在该脚本**。该对照**只作辅助检查**。
- 主论据不变：打包源目录 `output/out/rootfs_uclibc_rv1106/etc/init.d/` 内无 `S91smb` + 包内
  `rootfs.img` 与 `output/image/rootfs.img` 逐字节一致（SHA-256 `5f5cbc72…`）+ 删除发生在
  `mkfs.ubifs`/ubinize 成像**之前**的构建日志顺序。

### 5.2 其余缺口

- 本文件先前"前一候选 `176faa8c` 目录内甚至不含 `rootfs.img`"一句**无法在本树复核，已删除**；
  `IMAGE/` 下现存的 6 个候选目录**全部**含 `rootfs.img`（各 59,899,904 字节）。
- 本复核**未能**在离线环境内解包 UBI/UBIFS 逐一列出包内 `/etc/init.d`（`ubireader` 未安装，
  WSL 内核无 `nandsim`/`ubifs` 模块）；包内 `S91smb` 缺失由"打包源目录 + 成像顺序 + 上述辅助字节
  对照"推定，而非对 UBI 内容枚举。

## 6. 本分支证据文件索引

- `aidlc-docs/evidence/2026-09-30-v020-rkipc-autostart-gate-rework.md`（rkipc 门控返工；现行结论）
- `aidlc-docs/evidence/2026-09-30-v020-smb-nmb-autostart-disabled.md`（SMB/NMB 关闭；其第 8 节字节扫描表述经二进制安全复验成立，说明见第 5.1 节）
- `aidlc-docs/evidence/2026-09-30-v020-cpu-dvfs-removed.md`（CPU DVFS 撤销；现行结论）
- `aidlc-docs/evidence/2026-09-30-v020-cpu-dvfs-fixed-0v9.md`（原"限频"方案，**结论已被上一条取代**，仅根因分析可参考）
- `aidlc-docs/evidence/2026-09-03-dw-sdk-003-pstore-ramoops.md`、`2026-09-02-csi-i2c4-disabled-root-cause.md`（更早切片）

## 7. rkipc 门控返工（2026-09-30 晚）

### 7.1 受影响的旧候选

- `20260930.2054` 及更早的候选均用 `S21appinit.disabled` 方案，**门控失效**，rkipc 仍开机启动。
  **不得**把 `2054` 称作可烧录候选。`1010` 及更早同样不含本门控（那时尚未引入）。

### 7.2 修复版镜像与哈希（`20260930.2112`）

| 产物 | SHA-256 |
|---|---|
| `IMAGE/IPC_SPI_NAND_TLY_V020_20260930.2112_RELEASE_TEST/IMAGES/update.img`（81,406,538 B） | `cb1de8decdc18828f717d9fc29ec88cb4d76f804302df268298423b548350155` |
| 同目录 `rootfs.img`（60,293,120 B） | `08aca2821bca1f2fa0638b1334731248222766ce0c158e803fb3bd55ed8dfa78` |
| 同目录 `boot.img`（3,866,112 B） | `04a067f0de82465a4df53a6ed54e017458639039e7c67dd58915f703e8f86f21` |

- 构建：`./build.sh allsave`，退出码 0；日志 `/tmp/dw012-v020-rkipc-gate-allsave.log`。
- 静态核验（详见证据文件）：打包源 `etc/init.d/S21appinit` 即门控覆盖件（sha256 与源码一致）、
  **无 `.disabled`**；包内 `Image/rootfs.img` 与 `output/image/rootfs.img` 逐字节一致；
  直接解析包内 UBIFS 卷 0（458 LEB，与 `mkfs.ubifs leb_cnt` 一致）检出门控脚本正文；
  `rkipc` 的 `libfreetype.so.6`/`libiconv.so.2` 依赖在 `oem/usr/lib/` 有闭包。
- **仍未实板验证**；仅供 V020 NAND 验证板自行烧录，非 V015 量产固件。
