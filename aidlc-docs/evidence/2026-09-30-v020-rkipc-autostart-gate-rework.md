# V020 rkipc 默认自启门控返工（修复 2054 候选镜像的门控失效与错误证据陈述）

- 工作项：DW-012 / V020 SPI NAND 验证板
- 分支：`codex/dw-012-v020-nand-validation`（本 worktree `/home/henry/rv1106/luckfox-pico-v020-main-axiarz`）
- 起点：`00018c57accc88cc21754123ef8a7b2a3e54e6d2`（"fix(dw-012): V020 恢复 rkipc 所需 freetype 并关闭 rkipc 默认开机启动"）
- 修复提交：`82c3c5a44`（见下方"提交"节）
- 执行日期：2026-09-30
- 边界：**未烧录、未 push、未改设备**；本文件全部为源码与构建期/包内静态证据。

## 1. 缺陷（独立复现）

### 1.1 改名 `.disabled` 关闭不了自启

`output/out/rootfs_uclibc_rv1106/etc/init.d/rcS`（Buildroot 生成，第 7 行起）实际内容为：

```sh
for i in /etc/init.d/S??* ;do
     [ ! -f "$i" ] && continue
     case "$i" in
	*.sh) ... ;;   # source
	*)    $i start ;;  # 执行
     esac
done
```

`S??*` 的匹配语义是：第 1 个字符 `S`、第 2、3 个字符任意两位（`?`）、其余任意（`*`）。
`S21appinit.disabled` 的 `S21` 满足 `S??`，`.disabled` 被 `*` 吸收，**因此仍然匹配该 glob**。
rcS 只跳过目录与悬空链接（`[ ! -f "$i" ] && continue`），`S21appinit.disabled` 是普通文件，
照常被 `$i start` 执行。起点提交把 `S21appinit` 改名为 `S21appinit.disabled`，**并未关闭自启**；
`20260930.2054` 候选镜像因此 rkipc 仍会开机启动。

按 rcS 原文语义复刻的枚举（`/tmp/v020-gate/run-rcS.sh`）作用在真实已构建 rootfs 的
`etc/init.d/` 上：

```
$ /tmp/v020-gate/run-rcS.sh /tmp/v020-gate/init.d.real | grep -i appinit
EXEC   .../init.d/S21appinit.disabled        <= 缺陷复现：.disabled 仍被列为启动项
```

### 1.2 错误的 S20pstore 证据陈述

起点提交正文称"在板端 `touch /etc/init.d/S21appinit.enable`，由 /etc/init.d/S20pstore 在启动时
自动还原入口"。复核：该提交**没有改 S20pstore**；
`project/cfg/BoardConfig_IPC/overlay/overlay-luckfox-buildroot-init/etc/init.d/S20pstore`
（123 行）全文不含 `.enable`、不含 `mv`、不含 `S21`，无任何"还原入口"逻辑。该说法不成立，已删除。

## 2. 修复

### 2.1 决定：保留 `S21appinit` 文件名，在 start 分支加门控

与 V015 分支 `b1998ddfe`（`V015 eMMC：rkipc 默认不自启，改用 /userdata/.rkipc-enable 显式开启`）
同构，但放在 V020 自己的路径下：

- 新增 V020 专属覆盖件
  `project/cfg/BoardConfig_IPC/overlay/overlay-luckfox-buildroot-config/etc/init.d/S21appinit`
  （`chmod 755`，sha256 `cd45ebe1f4b7be30fc723602dd4736ec3796e2328e5892575fcfa109307817ef`）。
  `start)` 判据：`[ -f "$FLAG" ] && [ ! -L "$FLAG" ]`，其中 `FLAG=/userdata/.rkipc-enable`。
  缺省（文件不存在 / 目录 / 符号链接 / 悬空链接 / FIFO）一律 `return 0`，不执行 `RkLunch.sh`。
  保留 `stop)`（`RkLunch-stop.sh`）与 `restart)`。
- `BoardConfig-SPI_NAND-Buildroot-RV1106_DW-TLY-V020-IPC.mk` 的 `RK_POST_OVERLAY` 末尾追加
  `overlay-luckfox-buildroot-config`。`post_overlay`（`build.sh:2510`）按列表顺序 `rsync -a`
  覆盖，末位确保覆盖 `__PACKAGE_OEM`（`build.sh:1465`）生成的那一份 `S21appinit`。
  顺序：`__PACKAGE_OEM` → `__RUN_PRE_BUILD_OEM_SCRIPT` → `__COPY_FILES` →
  `__RUN_POST_BUILD_SCRIPT`（`build.sh:2579`）→ `post_overlay`（`:2580`）→
  `build_mkimg rootfs`（`:2592`）；覆盖发生在 rootfs 成像**之前**。
- V020 专属 post `luckfox-buildroot-ble-fix-post.sh` 移除改名逻辑，改为构建期断言：
  覆盖件存在、含 `RkLunch.sh`、含 `.rkipc-enable`；若产物里存在会被 `S??*` 误匹配的
  `S21appinit.disabled` 残留则**报错退出 1**（把这类缺陷拦在构建期）。
- 共享的 `project/build.sh`、共享 Buildroot defconfig、`rv1106_ipc/RkLunch.sh`、
  其他板型（含 V014 / Luckfox Pico Ultra）**均未改**。

### 2.2 `/userdata` 为 UBI volume 的时序确认（复核自本树）

- `BoardConfig` 存储布局含 `32M(userdata)`，`RK_PARTITION_FS_TYPE_CFG` 中 `userdata@/userdata@ubifs`。
- init.d 字典序：`S20linkmount`(S20l…) < `S20pstore` < `S20urandom` < `S21appinit`。
- 生成的 `output/out/rootfs_uclibc_rv1106/etc/init.d/S20linkmount` 在 `start)` 里依次执行
  `mount_part rootfs IGNORE ubifs` / `mount_part oem /oem ubifs` /
  `mount_part userdata /userdata ubifs`；其 `mount_part` 对 `fstype=ubifs` 走
  `ubiattach → 若 avail_eraseblocks>0 则 ubirsvol 扩满 → mount`（第 83–92 行）。
- 因此执行到 `S21appinit` 时 `/userdata` 已挂载，门控脚本内**不需要**再轮询等待。
- 挂载失败（如首次 `ubiattach` 失败且 `ubiformat` 也失败）时 `mount_part` 走
  `echo mount ... error` 分支并 `return 1`，但 rcS 不把非零退出当致命错误，继续跑后续脚本；
  此时门控拿不到标志文件即按"关闭"处理，与"默认不出流"的设计意图一致。

## 3. 验证

### 3.1 脚本级

- `bash -n`（post）、`sh -n`（覆盖件）、`git diff --check` 全部通过。

### 3.2 门控行为（RkLunch.sh 以桩拦截并计数）

| 开关状态 | 调用 RkLunch.sh | 退出码 |
|---|---|---|
| 无开关（默认） | 否 | 0 |
| 普通文件 | 是 | 0 |
| 目录 | 否 | 0 |
| 指向常规文件的符号链接 | 否 | 0 |
| 悬空符号链接 | 否 | 0 |
| FIFO | 否 | 0 |
| `restart` 且开关在位 | 先 stop 再 start | 0 |
| 非法参数 | 否 | 1 |
| `/userdata` 目录整体缺失 | 否 | 0 |

### 3.3 post 脚本夹具

- V020 DTS 路径：`S91smb` 移除；`libfreetype.so.6.17.0` / `libiconv.so.2.6.1` 就位且
  SONAME 链接（`.so.6`/`.so`、`.so.2`/`.so`）正确；`S21appinit` 为带门控的覆盖件；
  无 `.disabled`；退出 0。
- 负例：人为放入 `S21appinit.disabled` → 报错退出 1；临时移走覆盖件 overlay → 报错退出 1。
- 回归：Ultra(V014) DTS 路径 → `S21appinit` 仍为生成器原样、无门控、未装 freetype、
  未删 `S91smb`（夹具内本无），退出 0。

### 3.4 构建与包内静态核验

构建命令（本 worktree，HEAD=`82c3c5a44`；构建时工作树脏文件仅
`project/app/wifi_app/wifi/librkwifibt.so`，见第 5 节）：

```
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin ./build.sh allsave
```

- 退出码 0；日志 `/tmp/dw012-v020-rkipc-gate-allsave.log`（257877 B）；
  末行 `Running build_allsave succeeded.`。
- 日志内 post 标记（rootfs 成像之前）：
  - `:2838 V020 SMB/NMB autostart disabled`
  - `:2839 V020 restored libfreetype.so.6 -> libfreetype.so.6.17.0`
  - `:2840 V020 restored libiconv.so.2 -> libiconv.so.2.6.1`
  - `:2841 V020 rkipc autostart gated by /userdata/.rkipc-enable (S21appinit kept)`
- **打包源目录**（`mkfs.ubifs` 的 `root:`，日志 `:2877` = `output/out/rootfs_uclibc_rv1106/`）：
  - `etc/init.d/S21appinit` 与源码覆盖件 sha256 **完全一致** `cd45ebe1…0817ef`；
  - `etc/init.d/` 下 **无** `S21appinit.disabled`（计数 0）；
  - 按 rcS 的 `S??*` 语义枚举该目录，appinit 相关只列出 `S21appinit` 一项。
- **包内**（`update.img` 两层解包：`rkImageMaker -unpack` → `afptool -unpack`）：
  - 包内 `Image/rootfs.img` 与 `output/image/rootfs.img` **sha256 逐字节一致**
    `08aca2821bca1f2fa0638b1334731248222766ce0c158e803fb3bd55ed8dfa78`；
  - 直接解析该 UBIFS 卷 0：LEB 数 458，与构建日志 `mkfs.ubifs leb_cnt: 458` 一致；
  - 在卷 0 的 LEB 425、节点（inode 数据节点，`key` 高 40 位 = 2097152，`node_type=1`）
    内检出**该门控脚本正文**：`/bin/sh`、`DW-TLY-V020`、`/userdata/.`+`-enable`、
    `S21appinit`、`for i in`+`S??*`、`RKIPC_ENABLE_FLAG`、`RkLunch`、`touch`、
    `return 1`、`__PACKAGE_OEM`、`overlay`、`RK_POST_OVERLAY`、`dw-tly-v0…`
    （UBIFS 对小文件 data 节点做过自有的重复串压缩，故 `RkLunch.sh`/`rkipc-enable`
    等完整字面量按"片段 + 后向引用距离"编码，未以连续字节出现；片段与结构位置已充分）。
- **依赖闭包**：`readelf -d output/out/app_out/bin/rkipc` 的 NEEDED 含 `libfreetype.so.6`
  与 `libiconv.so.2`；打包源 `oem/usr/lib/` 同时提供
  `libfreetype.so.6.17.0`（+`libfreetype.so.6`/`.so` 链接）与
  `libiconv.so.2.6.1`（+`libiconv.so.2`/`.so` 链接）。

### 3.5 产物哈希

| 产物 | SHA-256 |
|---|---|
| `IMAGE/IPC_SPI_NAND_TLY_V020_20260930.2112_RELEASE_TEST/IMAGES/update.img`（81,406,538 B） | `cb1de8decdc18828f717d9fc29ec88cb4d76f804302df268298423b548350155` |
| 同目录 `rootfs.img`（60,293,120 B） | `08aca2821bca1f2fa0638b1334731248222766ce0c158e803fb3bd55ed8dfa78` |
| 同目录 `boot.img`（3,866,112 B） | `04a067f0de82465a4df53a6ed54e017458639039e7c67dd58915f703e8f86f21` |

`IMAGE/…2112…/IMAGES/update.img` 与 `output/image/update.img` 哈希一致；
`rootfs.img` 与 `output/image/rootfs.img` 及**包内** `Image/rootfs.img` 三者一致。

## 4. 限制 / 未验证（不得写成实机通过）

- **实板验证全部缺失**：`20260930.2112` 镜像从未烧录。rkipc 默认是否真的不出流、
  `touch /userdata/.rkipc-enable` 重启后是否真的自启、手动 `sh /oem/usr/bin/RkLunch.sh`
  是否可用，均**未在真机确认**。
- 本镜像**不得**称为"可烧录候选"或"已获硬件签核"；仅由用户在 V020 NAND 验证板自行烧录验证。
  旧的 `20260930.2054` 镜像门控失效，**不可**作候选。
- 未在上板环境下确认 `/userdata` 在 `S21appinit` 执行时总是已挂载（静态分析见 2.2；
  首次上电 `ubiformat` 路径未实测）。
- UBIFS 卷内文本为片段级检出（UBIFS 自有压缩），未做完整 inode 重组；结论由
  "staging 目录 + 成像顺序 + 包内 rootfs 逐字节一致 + 包内卷结构一致" 共同支撑。

## 5. 构建期工作树副作用

- 构建会重写受版本控制的 `project/app/wifi_app/wifi/librkwifibt.so`（`allsave` 的既有副作用）。
  构建前该文件即已是脏（`00018c57a` 之前遗留），构建后仍在工作树；**未纳入本次提交**。

## 6. 提交

- `82c3c5a44` `fix(dw-012): V020 rkipc 门控改为保留 S21appinit 的文件内开关`
  - 改动：`BoardConfig-SPI_NAND-Buildroot-RV1106_DW-TLY-V020-IPC.mk`、
    `luckfox-buildroot-ble-fix-post.sh`、新增 overlay 覆盖件 `S21appinit`。
- 本证据文件与 `aidlc-docs/CURRENT.md` 更新为紧随其后的文档提交。
