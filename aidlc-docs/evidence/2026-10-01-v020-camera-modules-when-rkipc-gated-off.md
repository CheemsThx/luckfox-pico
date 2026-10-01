# V020 第二个出厂缺陷：门控关闭 rkipc 连带关掉相机/媒体模块装载

> **[已取代 / SUPERSEDED，2026-10-01]** 本文件记录的候选镜像 `20261001.1026`
> （`update.img` sha256 `c8961d02…aeef`）已被
> `2026-10-01-v020-codex-review-s21appinit-fixes.md` 中记录的 **20261001.1051**
> 候选取代（Codex 复审发现本文件对应的 `b8485375f` 源码有两处门控行为缺口，
> 修复提交 `278545e14`）。本文件保留作为历史证据，其中“模块装载退出码即可判定
> 成功”的说法已被证伪。

- 工作项：DW-012 / V020 SPI NAND 验证板
- 分支：`codex/dw-012-v020-nand-validation`（worktree `/home/henry/rv1106/luckfox-pico-v020-main-axiarz`）
- 起点：`b684dc30e3569223a9079855ae3ac167d7e0c1df`（"fix(dw-012): V020 rkipc freetype 改在 oem.img 打包前装入 OEM 目录"）
- 修复提交：`b8485375f7b7cb2ec74773679de3dbf336611321`
- 执行日期：2026-10-01
- 边界：**未烧录、未 push、未改设备**；本文件为源码 + 夹具级证据，实板验证缺失。

## 1. 两个已烧录镜像（20260930.2112）暴露的出厂缺陷

两个缺陷都在同一个已烧录候选 `20260930.2112` 上经独立只读 ADB 核对发现。

### 缺陷 A（已由 b684dc30e 修复）：独立 /oem 分区缺 libfreetype.so.6

- **事实（实板只读）**：`20260930.2112` 的 `/oem`（mtd4 UBI 卷）内没有
  `libfreetype.so.6`，`rkipc` 动态链接失败。
- **事实（代码/构建）**：共享 `luckfox-buildroot-oem-pre.sh` 无条件
  `rm -rf ${RK_PROJECT_PACKAGE_OEM_DIR}/usr/lib/libfreetype*`（第 28、31 行），
  而旧 V020 post 脚本只把库补到 `${ROOTFS}/oem/usr/lib`（rootfs 内嵌副本）。
- **推断（已由构建证据支撑）**：因 V020 `RK_BUILD_APP_TO_OEM_PARTITION=y`，
  `/oem` 是独立分区，`S20linkmount` 的 `mount_part oem /oem ubifs` 会盖住
  rootfs 里的 `/oem` 目录，板端永远读不到那份副本 → 旧 post 恢复是**无效修复**。
  已构建镜像实证 `output/image/oem.img` 内 freetype 命中 0。
- **修复**：`b684dc30e` 新增 V020 专属 pre-OEM 包装脚本
  `luckfox-buildroot-v020-oem-pre.sh`，在 `build_mkimg oem` **之前**把
  `libfreetype.so.6.17.0` / `libiconv.so.2.6.1` 装回 OEM 打包目录并建 SONAME 链接。

### 缺陷 B（本提交 b8485375f 修复）：门控关闭 rkipc 连带关掉模块装载

- **事实（实板只读 ADB）**：板上没有 `/dev/video*`，也没有 `/dev/media*`；
  `lsmod` 里没有 `video_rkcif`、`video_rkisp`、相机 sensor、`mpp_vcodec`、
  `rockit`。
- **事实（代码）**：原厂链路里这些模块由 `RkLunch.sh` 的 `post_chk` 装载：
  `project/app/rkipc/rkipc/src/rv1106_ipc/RkLunch.sh:60-65`
  ```sh
  default_ko_dir=/ko
  if [ -f "/oem/usr/ko/insmod_ko.sh" ]; then default_ko_dir=/oem/usr/ko; fi
  if [ -f "$default_ko_dir/insmod_ko.sh" ]; then
      cd $default_ko_dir && sh insmod_ko.sh && cd -
  fi
  ```
  `/oem/usr/ko/insmod_ko.sh` 装载 `video_rkcif.ko`、`video_rkisp.ko`、各 sensor、
  `mpp_vcodec.ko`、`rockit.ko` 等（`sysdrv/drv_ko/insmod_ko.sh:41-85`）。
- **事实（代码）**：上一轮门控（`82c3c5a44`）在关闭分支直接 `return 0`，
  **不**执行 `RkLunch.sh`，于是 `insmod_ko.sh` 一次都没跑。
- **推断（与实板现象一致）**：这些模块是 **dw-rec 本地录像与 rkipc 出流共用**的
  依赖，不是 rkipc 专属。所以"关闭 rkipc 自启"把与 rkipc 无关的 dw-rec 也一起
  关停了 —— 这就是板上无 video/media 节点的直接原因。
- **修复**：本提交 `b8485375f`。

## 2. 启动顺序与竞态分析（代码事实）

### 2.1 rcS 枚举与字典序

`output/out/rootfs_uclibc_rv1106/etc/init.d/rcS` 用 `for i in /etc/init.d/S??*`
顺序执行。相关脚本字典序与相对位置：

```
S10udev(S+两位数字,先于) → S20linkmount → S20pstore → S20urandom → S21appinit
  → S25backlight → S30dbus → S35iptables → S35wifibt → S40bluetoothd …
```

`S20linkmount`(start) 依次 `mount_part rootfs IGNORE ubifs` /
`mount_part oem /oem ubifs` / `mount_part userdata /userdata ubifs`。因此跑到
`S21appinit` 时 `/oem` 与 `/userdata` 都已挂载，门控无需轮询等待。

### 2.2 为什么“打开”分支不能预先装载（重复装载 = 拆 sensor）

`insmod_ko.sh` 末尾的 `__rmmod_camera_sensor()`（`sysdrv/drv_ko/insmod_ko.sh:15-23`）
遍历 sensor 列表，把 `lsmod` 中 refcount==0 的模块 `rmmod`，且**同一趟不再重装**。

| 若在打开分支先自己 insmod_ko.sh 再交给 RkLunch.sh | 后果 |
|---|---|
| 第 1 遍（门控）：装载 sensor + video_rkcif/rkisp + …；末尾 rmmod 掉刚装且 refcount==0 的 sensor |
| 第 2 遍（RkLunch post_chk）：再装一遍；末尾再 rmmod refcount==0 的 sensor；此时 rkipc 尚未起，sensor 仍会被拆 |

两遍装载在任何时点都可能把 sensor 拆掉不补回，是会留下"无 sensor"残局的真实风险。
因此“避免重复装载”落实为：**模块装载在任一分支都只发生一次**。

### 2.3 S35wifibt 竞态（本改动不新引入）

- `insmod_ko.sh:90` 末行 `$(pwd)/insmod_wifi.sh &` 后台装载 WiFi（`insmod_ko.sh`
  开头已 `cd $_DIR`，故 `$(pwd)` = `/oem/usr/ko`）。
- 原厂也是后台：`RkLunch.sh:166` 为 `post_chk &`，即 RkLunch 在 S21 立刻返回，
  模块装载与 WiFi 装载都在后台与 S25/S30/S35 并发。S35wifibt 历来靠自身守卫
  `lsmod | grep -q '^aic8800_fdrv '`（`overlay-luckfox-buildroot-init/etc/init.d/S35wifibt:30`）
  处理"WiFi 已装就跳过、未装就自己装"的窗口。
- 本改动“关闭”分支**同步**跑 `insmod_ko.sh`，相机模块在返回 S21 前已就位；WiFi 仍
  是后台，与原厂一致。故不新引入竞态，也不改 `S35wifibt`。

## 3. 修复内容（b8485375f）

仅动 V020 专属文件，共享脚本与其他板型一字未改：

1. `project/cfg/BoardConfig_IPC/overlay/overlay-luckfox-buildroot-config/etc/init.d/S21appinit`
   - 新增 `KO_DIR=/oem/usr/ko` 与 `load_media_modules()`：缺 `insmod_ko.sh` 或执行
     失败都打印 `ERROR …` 到 stderr 并 `return 1`。
   - `start)` 改为：`rkipc_enabled` 为真 → 走原厂 `sh /oem/usr/bin/RkLunch.sh`（只一次）；
     为假 → 打印关闭提示后 `load_media_modules` 并以其退出码返回。**不再裸 `return 0`**。
2. `project/cfg/BoardConfig_IPC/luckfox-buildroot-ble-fix-post.sh`
   - 构建期断言新增两条：覆盖件须含 `insmod_ko.sh` 引用、须含 `KO_DIR=/oem/usr/ko`。
3. `project/cfg/BoardConfig_IPC/BoardConfig-SPI_NAND-Buildroot-RV1106_DW-TLY-V020-IPC.mk`
   - 仅补注释，说明门控语义。

未改：`project/build.sh`、`rv1106_ipc/RkLunch.sh`、`S35wifibt`、共享 Buildroot
defconfig、V014/Luckfox Pico Ultra 及任何其他 BoardConfig/overlay。

## 4. 验证（夹具级，全部在本 worktree 源码上）

### 4.1 语法与空白

```
$ sh -n  project/cfg/BoardConfig_IPC/overlay/overlay-luckfox-buildroot-config/etc/init.d/S21appinit   # rc=0
$ bash -n project/cfg/BoardConfig_IPC/luckfox-buildroot-ble-fix-post.sh                                # rc=0
$ git diff --check                                                                                     # 干净
```

### 4.2 门控夹具（`/tmp/dw012-v020-camera-20261001/gate_test.sh`，12/12 PASS）

桩拦截 `RkLunch.sh`（写 `RkLunch` 到 calls.log）、`RkLunch-stop.sh`、`insmod_ko.sh`
（写 `insmod_ko`），统计各分支调用次数：

| 场景 | 期望 | 实测 |
|---|---|---|
| 无标志 | RkLunch=0, insmod_ko=1, rc=0 | 一致 |
| 标志=目录 | RkLunch=0, insmod_ko=1, rc=0 | 一致 |
| 标志=指向常规文件的符号链接 | RkLunch=0, insmod_ko=1, rc=0 | 一致 |
| 标志=悬空链接 | RkLunch=0, insmod_ko=1, rc=0 | 一致 |
| 标志=FIFO | RkLunch=0, insmod_ko=1, rc=0 | 一致 |
| 标志=普通文件 | RkLunch=1, insmod_ko=0, rc=0 | 一致（**不重复装载**） |
| `stop` | 调 RkLunch-stop.sh，RkLunch=0, insmod_ko=0 | 一致 |
| `restart` 且标志在位 | 先 stop 再 start，RkLunch=1, insmod_ko=0 | 一致 |
| 非法参数 | rc=1 | 一致 |
| 缺 `insmod_ko.sh`（关闭分支） | rc≠0 且打印 `ERROR camera module loader missing` | 一致 |
| `insmod_ko.sh` 执行失败（关闭分支） | rc≠0 且打印 `ERROR camera module load failed` | 一致 |

关键点：普通文件标志那行证明**打开路径不重复装载**（insmod_ko=0，装载全权交给
一次性的 RkLunch.sh）；关闭路径即使不启 rkipc 也保证装载一次。

### 4.3 post 夹具（`/tmp/dw012-v020-camera-20261001/post_test.sh`，10/10 PASS）

| 场景 | 结果 |
|---|---|
| V020 正常覆盖件 | rc=0，打印新断言信息，门控装入 rootfs |
| 覆盖件缺 `insmod_ko.sh` 引用 | rc=1，`ERROR … lacks camera module loader` |
| 覆盖件缺 `.rkipc-enable` | rc=1，`ERROR … lacks /userdata/.rkipc-enable` |
| 产物存在 `S21appinit.disabled` 残留 | rc=1，`ERROR stale … matches rcS S??* glob` |
| V014(Luckfox Pico Ultra) DTS 路径 | rc=0，保留 S91smb，不安装 V020 门控 |

## 4.4 最终镜像构建与包内静态核验（本切片最终产物）

构建源码提交：`b260e110e52dcdbf7cc1c7d962da211574f25fb6`（本证据文件尚未提交前；
构建时工作树唯一脏文件为构建副产物 `project/app/wifi_app/wifi/librkwifibt.so`，
非源码改动）。

```
$ PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin ./build.sh allsave
  退出码 0（后台运行并以 /tmp/dw012-v020-camera-final-allsave.exit 记录实际退出码；
  末行 "Running build_allsave succeeded."）
  日志：/tmp/dw012-v020-camera-final-allsave.log
```

日志内 V020 专属标记（均在 rootfs/oem 成像与打包之前）：

```
:2710 luckfox-buildroot-v020-oem-pre: restored libfreetype.so.6 -> libfreetype.so.6.17.0 into oem package dir
:2719 luckfox-buildroot-v020-oem-pre: restored libiconv.so.2 -> libiconv.so.2.6.1 into oem package dir
:2899 luckfox-buildroot-ble-fix-post: V020 SMB/NMB autostart disabled
:2900 luckfox-buildroot-ble-fix-post: V020 rkipc autostart gated by /userdata/.rkipc-enable (S21appinit kept, camera modules loaded when gated off)
```

两层解包（`rkImageMaker -unpack update.img <dir>` → `afptool -unpack firmware.img <dir>`）：

- 包内 `Image/rootfs.img`、`Image/oem.img` 与 `output/image/*` **逐字节一致**
  （sha256 相同，见下表）。
- 用自建 UBIFS 解析器（`/tmp/dw012-v020-camera-20261001/ubifs_extract.c` +
  内核 `lib/lzo/lzo1x_decompress_safe.c`，LZO 解压）直接读包内卷 0：

  | 校验 | 结果 |
  |---|---|
  | 包内 `/etc/init.d/S21appinit`（inum 2087，2 个 data 块，5218 B）vs 源码覆盖件 | **IDENTICAL**（逐字节） |
  | 包内 `S21appinit` 含 `KO_DIR=/oem/usr/ko`、`insmod_ko.sh`、`load_media_modules`、`.rkipc-enable`、`RkLunch.sh` | 全部命中 |
  | 包内 rootfs `/etc/init.d/`：`S91smb` | **不存在** |
  | 包内 rootfs `/etc/init.d/`：`S21appinit.disabled` 或任何 `*appinit*` 残留 | **不存在**（只有 `S21appinit`） |
  | 包内 `oem.img` `/usr/lib/libfreetype.so.6.17.0` vs 打包源 | **IDENTICAL**（296648 B） |
  | 包内 `oem.img` `/usr/lib/libiconv.so.2.6.1` vs 打包源 | **IDENTICAL**（251180 B） |
  | 包内 `oem.img` `libfreetype.so`/`.so.6`、`libiconv.so`/`.so.2` 链接（size 21 / 17） | 与打包源一致 |
  | 包内 `oem.img` `/usr/ko/insmod_ko.sh` vs 源码 | **IDENTICAL**（1734 B） |

- 无 CPUFreq 回归：构建内核 `sysdrv/source/objs_kernel/.config` 为
  `# CONFIG_CPU_FREQ is not set`；包内 rootfs 无 cpufreq 相关启动项。
- 无 SMB/NMB：包内 rootfs 无 `S91smb`（沿用 `ebf61369f` 的 V020 关闭行为）。

### 4.5 产物哈希（本切片候选）

| 产物（`IMAGE/IPC_SPI_NAND_TLY_V020_20261001.1026_RELEASE_TEST/IMAGES/`） | 大小 (B) | SHA-256 |
|---|---|---|
| `update.img` | 81,537,610 | `c8961d02640dc1a5ec1ab22c4c34c99acb0c415d5bebfd8499cfc4ce7ff3aeef` |
| `rootfs.img` | 59,899,904 | `55f1cd03dd2e1e784b79e2f9aed1b2109c825b24752b5c5337d43eab6f236710` |
| `oem.img` | 14,548,992 | `660dc13fa3e8fae37b778f2096b3bf4d033a514244b962589c63ec410fda6225` |
| `boot.img` | 3,866,112 | `5969c1fc3c5bc8b338129969cb1b36cbcc30f546b4bff75b0ada0f12700d562b` |

`IMAGE/…/IMAGES/*` 与 `output/image/*` 逐一 sha256 一致。**未烧录**。

## 5. 限制 / 未验证（不得写成实机通过）

- **实板验证全部缺失**：修复后镜像从未烧录。相机模块是否真的装载成功、
  `/dev/video*` 与 `/dev/media*` 是否真的出现、dw-rec 是否恢复本地录像、
  rkipc 默认是否仍不出流、置位开关重启后是否自启 —— 全部待 V020 NAND 验证板确认。
- 本缺陷 B 的根因链路中，"module 装载缺失导致 dw-rec 失效"是**推断**，由实板现象
  （无 video/media 节点、lsmod 无相关模块）与代码链路共同支撑，尚未在板端用
  "装载前后对比 /dev 节点出现"的实验直接证明。
- 本镜像不得称"可烧录候选"或"已获硬件签核"；仅供用户在 V020 NAND 验证板自行烧录。
  旧的 `20260930.2054`（门控失效）与 `20260930.2112`（缺 freetype + 缺模块装载）
  均**不可**作最终候选。

## 6. 更正既有错误证据

- `aidlc-docs/CURRENT.md` 第 7.2 节原写 "`rkipc` 的 `libfreetype.so.6`/`libiconv.so.2`
  依赖在 `oem/usr/lib/` 有闭包" —— **错误**（指的是被独立分区盖住的 rootfs 内嵌副本）。
  已在同处加更正说明。
- `aidlc-docs/evidence/2026-09-30-v020-rkipc-autostart-gate-rework.md` 第 3.3 节夹具
  描述与第 3.4 节"依赖闭包"两处同样把 rootfs 内嵌 `oem/usr/lib` 与生成 `oem.img`
  的 `${RK_PROJECT_PACKAGE_OEM_DIR}/usr/lib` 混为一谈，已在两处加更正说明。

## 7. 提交

- `b8485375f` `fix(dw-012): V020 门控关闭 rkipc 时仍装载相机/媒体模块`
  - 改动：`S21appinit`（覆盖件）、`luckfox-buildroot-ble-fix-post.sh`、V020 BoardConfig 注释。
- 前序 `b684dc30e`（freetype 移入 OEM 打包目录）保持原样，未 amend、未改写。
- 本证据文件与 `aidlc-docs/CURRENT.md` 更正为紧随其后的文档提交。
