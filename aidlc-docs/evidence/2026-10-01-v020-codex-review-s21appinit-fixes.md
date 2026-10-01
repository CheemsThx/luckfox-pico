# DW-012 / V020 —— Codex 复审：S21appinit 门控两处行为缺口修正与替代候选

- 日期：2026-10-01
- 分支：`codex/dw-012-v020-nand-validation`
- 源修复提交：`278545e14 fix(dw-012): V020 rkipc 门控保留 RkLunch 退出码并核对核心媒体模块`
- 被取代提交基线：`099cf7d3a`（记录 20261001.1026 候选）；被复审源码 `b8485375f`
- 状态：**候选已构建、包内静态核验通过；仍未烧录、未实板验证**

## 1. 复审发现（Codex，2026-10-01）

Codex 复审 `b8485375f` 的 S21appinit 源码，指出两处“行为与声明不符”的缺口。二者均经本次实读源码确认为真：

### 缺口 1 —— 打开分支无条件 `return 0` 吞掉 RkLunch 退出码
`b8485375f` 的 `start()` 启用分支：

```sh
sh /oem/usr/bin/RkLunch.sh
return 0
```

RkLunch.sh 的 `post_chk` 确实是 `post_chk &` 后台执行（`RkLunch.sh:166`），但脚本**同步段**仍可能失败：`rcS()` 逐个 `$i start` `/oem/usr/etc/init.d/S??*`（`RkLunch.sh:3-24`）、sensor 高度分支可提前 `return`（`:141,147`）。这些状态被无条件 `return 0` 静默吞掉。

### 缺口 2 —— “模块装载失败返回非零”是假保证
关闭分支原本以 `insmod_ko.sh` 的退出码判定成功。但：
- `insmod_ko.sh` 无 `set -e`；
- `__insmod()` 对缺失 `.ko` 仅是 `[ -f "$1" ]` 静默跳过（`sysdrv/drv_ko/insmod_ko.sh:8-13`）；
- 脚本**末行** `$(pwd)/insmod_wifi.sh &`（`:90`）把最后一条命令放后台——后台 job 启动成功，使**整条脚本退出码为 0**，即便 `video_rkcif/video_rkisp/mpp_vcodec/rockit` 一个都没装上。

这正是 20260930.2112 候选镜像“板端无 `/dev/video*`、无 `/dev/media*`、lsmod 缺 video_rkcif/rkisp/mpp/rockit”的机制。

### 复审附注 —— 未证的 V014 声明
pre-OEM 包装脚本原注释断言“V014 等板型不装 rkipc”，未取证。
**经查**：`grep -rn 'rkipc' project/cfg/BoardConfig_IPC/*V014*` 无结果；`BoardConfig-...Ultra-IPC.mk`（即 V014）无任何 rkipc 引用。该断言现无法从仓库证明（rkipc 应用由 `project/app/` 统一构建，非板级开关）。
处理：**按 Codex 要求收窄措辞**，改为“共享脚本对所有板型（含 V014）的删除行为一概不变；本包装只在 V020 这一步补回”，不改变任何 V014 行为。

## 2. 修正内容（提交 278545e14）

文件：`project/cfg/BoardConfig_IPC/overlay/overlay-luckfox-buildroot-config/etc/init.d/S21appinit`

- **缺陷 1**：`start()` 启用分支改为 `sh /oem/usr/bin/RkLunch.sh; return $?`，如实回传退出码。
- **缺陷 2**：装载后新增核对：

```sh
CORE_MEDIA_MODULES="video_rkcif video_rkisp mpp_vcodec rockit"
media_modules_present() {           # lsmod 第一列精确匹配
    for m in $CORE_MEDIA_MODULES; do
        lsmod | awk '{print $1}' | grep -qx "$m" || { 报错并点名; return 1; }
    done
}
load_media_modules() { ...; media_modules_present || return 1; ... }
```

核心集合的取舍依据（避免误报）：
- **不含 `rga3`**：V020 编译产物 `output/out/oem/usr/ko/` 根本无 `rga3.ko`（该 SDK 未编出），纳入必备集必误报。
- **绝不含 sensor**：`insmod_ko.sh` 末尾 `__rmmod_camera_sensor()`（`:15-23,67`）会主动 rmmod `refcount==0` 的 sensor；本板 sensor 未探到，缺席是**正常态**。

文件：`project/cfg/BoardConfig_IPC/luckfox-buildroot-ble-fix-post.sh`
- V020 断言块新增两条：覆盖件须含 `sh /oem/usr/bin/RkLunch.sh` 直调、须含 `CORE_MEDIA_MODULES=`，把“吞退出码/去掉模块核对”两类回归钉在构建期。

文件：`project/cfg/BoardConfig_IPC/luckfox-buildroot-v020-oem-pre.sh`
- 仅改注释（第 7-10 行区），收窄 V014 措辞；无行为变更。

### 不动项
`project/build.sh`、`rv1106_ipc/RkLunch.sh`、`S35wifibt`、共享 `luckfox-buildroot-oem-pre.sh`、V014 及其他板型**一律未改**。rkipc 仍默认关闭；启用路径仍单次装载。

## 3. 验证证据（脚本/夹具级；非实板）

夹具位于 `/tmp/dw012-codex-review/`（临时，不入库）：
- `run-tests.sh`：门控夹具。真实脚本经 `sed` 重写 `/oem`、`/userdata` 前缀进 stub 目录，`lsmod`/`insmod_ko.sh`/`RkLunch.sh` 用桩拦截。
- `run-post-tests.sh`：post 断言块夹具（`gate_src` 用 `realpath($0)` 定位，故把块放到能看见真实 overlay 的目录执行）。

| 夹具 | 结果 | 关键断言 |
| --- | --- | --- |
| 门控 `run-tests.sh` | **19/19 PASS** | 见下 |
| post `run-post-tests.sh` | **5/5 PASS** | 见下 |

门控夹具分组：
- A（关闭分支判定，5 例）：无标志 / 标志=目录 / 符号链接 / 悬空链接 → 跑 `insmod_ko` 一次、不跑 RkLunch；普通文件 → 只跑一次 RkLunch、不自行 insmod_ko（**单次装载**）。
- B（缺陷 2 修复，7 例）：`insmod_ko` 退出 0 但核心模块缺失 → 非零并点名（B1）；缺 `rockit` → 非零点名（B2）；loader 非零 / 缺 loader → 非零（B3/B4）；核心齐+无关模块在 → rc0（B5）；**仅核心 4 模块、无任何 sensor → rc0 不误报**（B6）；`video_rkcif_v2` 不得充当 `video_rkcif`（B7，`grep -x`）。
- C（缺陷 1 修复，3 例）：RkLunch rc0 → rc0（C1）；**RkLunch rc5 → rc5**（C2）；打开分支不做模块核对（C3）。
- D（3 例）：stop 只调 RkLunch-stop；restart 关闭态先 stop 再 insmod_ko；restart 打开态 stop+RkLunch；非法参数 exit 1。

**判别性验证**（证明夹具非空转）：同一套夹具跑 `b8485375f` 旧代码得 **14/19**，失败项恰好是 B1、B2、B7（缺陷 2）与 C2（`rc5 → 0`，缺陷 1）。

post 夹具：V020 正常覆盖件 rc0 并安装（P1）；缺 `CORE_MEDIA_MODULES`、缺 RkLunch.sh 直调、存在 `S21appinit.disabled` 残留均 rc1（P2/P3/P5）；非 V020 dts 整块跳过 rc0 不安装（P4）。

其他：`sh -n`、`bash -n`、`git diff --check` 均通过。

## 4. 构建与包内核验（本轮，20261001.1051）

### 4.1 构建事实
- 源码提交：`278545e14`（工作树除本证据文件外干净；开工时 `librkwifibt.so` 脏为上一轮构建副产物，已 `git checkout HEAD --` 还原，构建后再次变脏，再次仅还原此文件）。
- BoardConfig：`BoardConfig-SPI_NAND-Buildroot-RV1106_DW-TLY-V020-IPC.mk`（`.BoardConfig.mk` 软链指向它）
- DTS：`rv1106g-dw-tly-v020.dts`（boot.img FIT 内 DTB 实测 `model = "DW-TLY-V020 W"`、`compatible` 含 `rockchip,rv1106g3`）
- 命令：`./build.sh allsave`，日志 `/tmp/dw012-codex-review/build-allsave.log`
- **实际退出码：0**（后台运行，末行 `Running build_allsave succeeded.`，并以 `EXIT_CODE=0` 落盘，非仅“启动即判成功”）
- 产物目录：`IMAGE/IPC_SPI_NAND_TLY_V020_20261001.1051_RELEASE_TEST/`

### 4.2 产物 SHA-256

| 产物 | 大小 (B) | SHA-256 |
| --- | --- | --- |
| `update.img`（**最终候选**） | 81,537,610 | `b81f558d1141ad96d5f17aeebee64da4d62c9ec19a3911392d948ef7df444e9a` |
| `rootfs.img` | 59,899,904 | `9a6de18e0f732922b2610cb9cf00293ad344d4497904dc857ba5fff3da8bbf6a` |
| `oem.img` | 14,548,992 | `c31ae647b4bf3156a25b5d360c325b9f61e323b120cceec91c23f0258a29719a` |
| `boot.img` | 3,866,112 | `977e1657104afa0c55dac51978a942c63a84b6e0912983dbe86c37a236053ca9` |
| `env.img` | 262,144 | `d6e2c00c3e74a26b4ac347ec91b01b204b083cbc09d3e860a6711db92d4571d1` |
| `idblock.img` | 188,416 | `1b1624b4cd727783ca00088112d8c6f1f4af7f5de6cb0228e068f942611c5a24` |
| `uboot.img` | 262,144 | `254a224d4ebd403feaefa66ef183e41422711f24847f36e20bdd99c1e7895762` |
| `userdata.img` | 1,966,080 | `fcaa6525a5e26fafc4c30d6332ab451646f27cd1f47d1df34581de53a3ace6ce` |

### 4.3 两层解包一致性
`./build.sh unpackimg`（rkImageMaker ver 2.2 + afptool）解出分区，逐字节等于构建产物：
`oem.img`/`rootfs.img`/`boot.img` **SHA-256 全部 MATCH**（见上表），证明核验的是**这份** update.img 本身。

### 4.4 包内 UBIFS 逐字节核验
用自建 UBIFS 解析器（`/tmp/dw012-v020-camera-20261001/ubifs_extract`，`load_ubi2` + 内核 `lzo1x_decompress_safe` 解 LZO，直接读卷 0）读 `IMAGE/.../oem.img`、`rootfs.img`：

| 核验项 | 结果 |
| --- | --- |
| OEM UBIFS `libfreetype.so.6.17.0` | **IDENTICAL** 于 `output/out/app_out/lib/libfreetype.so.6.17.0`（296,648 B） |
| OEM UBIFS `libiconv.so.2.6.1` | **IDENTICAL** 于源（251,180 B） |
| OEM UBIFS SONAME 链接 | `libfreetype.so.6`、`libfreetype.so`、`libiconv.so.2`、`libiconv.so` 均在 |
| OEM UBIFS 核心模块 | `video_rkcif.ko`、`video_rkisp.ko`、`mpp_vcodec.ko`、`rockit.ko`、`insmod_ko.sh`、`rkipc` 均在 |
| **rootfs UBIFS /etc/init.d/S21appinit** | **IDENTICAL** 于本次复审的仓库覆盖件（7,722 B） |
| rootfs `S91smb` | **不存在**（SMB/NMB 关闭，无回归） |
| rootfs `S21cpufreq` | **不存在**（CPU DVFS 已按规则移除，无回归） |
| rootfs `S21appinit.disabled` | **无残留** |
| rootfs `S20linkmount`/`S35wifibt`/`S50usbdevice` | 均在 |

即：rootfs 里的 S21appinit 就是本次含“保留 RkLunch 退出码 + 核心模块核对”的版本，OEM 分区里 rkipc 的 freetype/iconv 依赖与相机/媒体模块都在。

## 5. 仍未做的事 / 未决

- **未烧录、未实板验证**。相机/媒体模块在真机是否真加载、`/dev/video*`、`/dev/media*` 是否出现、dw-rec 是否恢复录像、rkipc 启用路径是否正常，**均待 V020 NAND 验证板烧录后确认**。
- `20261001.1026` 候选镜像被本提交构建出的替代候选**取代（superseded）**。
- 用户手头 V020 板移用 V014 样品芯片，无 V015 量产板；本候选不得称为已获硬件签核。

## 6. 跟踪文件清理

`project/app/wifi_app/wifi/librkwifibt.so` 由构建（wifibt 应用编译）作为副作用改写（HEAD 版本 281544 B → 构建版本 281904 B），非人工改动；已在本次开工时 `git checkout HEAD --` 还原；构建后若再变脏，仅还原此文件。

## 7. AI-DLC 映射

| 项 | 内容 |
| --- | --- |
| 需求 | DW-012 / V020 NAND：rkipc 门控须保留 RkLunch 状态；关闭分支须保证核心媒体模块真的在 |
| 代码事实 | `S21appinit`（本提交）、`insmod_ko.sh:8-13/90`、`RkLunch.sh:3-24/141/147/166`、`output/out/oem/usr/ko/` 模块清单 |
| 验证级别 | 源码 + 夹具级（判别性已证）；**未实板** |
| 阻塞 | 无 V020 验证板烧录授权；无 V015 量产板 |
