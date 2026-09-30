# V015 eMMC：rkipc 默认不自启的门控实现

- 日期：2026-09-30
- 分支：`codex/dw-012-v015-emmc-adaptation`
- 功能提交：`b1998ddfec8357e4ed708fab67470830d6e1c1cb`（"V015 eMMC：rkipc 默认不自启，改用 /userdata/.rkipc-enable 显式开启"）
- 工作项：DW-012 / V015 eMMC —— rkipc 默认不自启、可持久显式打开，且不改变其他板型。
- **本产物是静态候选**：V015 无实板、U17 VCCQ/焊球未签核。未烧录、未上电、未实测。

## 1. 需求与起点事实

需求：V015 量产候选默认**不出流**（rkipc 不自启），需要时由现场**显式打开**且
开关能**跨重启保留**；其他板型行为**不得改变**。

起点事实（均在本树逐条复核）：

- `project/build.sh:1477-1505` 的 `__PACKAGE_OEM()` 为**所有**板型生成同一份
  `${RK_PROJECT_PACKAGE_ROOTFS_DIR}/etc/init.d/S21appinit`，其 `start)` 直接
  `sh /oem/usr/bin/RkLunch.sh`。
- `RK_APP_TYPE=RKIPC_RV1106` 映射到 `-DCOMPILE_FOR_RV1106_IPC=ON`
  （`project/app/rkipc/Makefile:47-48`，`rkipc/CMakeLists.txt:50-52`），
  因而安装 `src/rv1106_ipc/RkLunch.sh`（其 `CMakeLists.txt:76`），
  末尾为 `rkipc -a /oem/usr/share/iqfiles &`（`rv1106_ipc/RkLunch.sh:151-155`）。
- 因此在上一候选里，开机必然出流；rkipc 无任何“自身默认关闭”的开关。

## 2. 关键决定

1. **门控放在启动脚本层。** 不改 `build.sh` 的 `__PACKAGE_OEM`，也不改
   `rv1106_ipc/RkLunch.sh` —— 这两处被 V015 之外的其他 `RKIPC_RV1106` 板型共用
   （Ultra / Pi / Zero / Pro_Max 等 `BoardConfig-*` 均为同一 `RK_APP_TYPE`），
   改它们会外溢到其他产品。
2. **覆盖手段用板级 `post_overlay`。** 新增 V015 专属 overlay
   `overlay-dw-tly-v015`，只含一份 `/etc/init.d/S21appinit`，并把该 overlay 放在
   `RK_POST_OVERLAY` **末位**，确保覆盖 `build.sh` 先生成的那一份。
   构建顺序（`build.sh:2578-2609`）：
   `__PACKAGE_ROOTFS` → `__PACKAGE_OEM` → `__RUN_PRE_BUILD_OEM_SCRIPT` →
   `build_mkimg oem` → `__RUN_POST_BUILD_SCRIPT` → `post_overlay` →
   `build_mkimg rootfs`。⇒ 覆盖确实发生在 rootfs 成像**之前**。
3. **持久开关取 `/userdata/.rkipc-enable`。** `/userdata` 是 ext4、可写、
   重新刷机前保留，适合做“现场一次性打开、之后每次开机生效”的开关。
   `S21appinit` 排在 `S20linkmount` 之后，执行到它时 `/userdata` 已挂载，
   故脚本内不做“等待挂载”轮询。
4. **判定只认普通文件。** `[ -f ]` 会跟随符号链接，若只看 `[ -f ]`，
   任何指向常规文件的链接（例如 `/userdata/.rkipc-enable -> /etc/passwd`）
   都会误开 rkipc。已加 `[ ! -L ]` 收紧；目录/FIFO 天然被 `[ -f ]` 排除。
5. **合并后处理脚本。** 原 `dw-tly-v015-disable-smb-post.sh` 只有 SMB 一条；
   现合并进 `dw-tly-v015-post.sh`（保留同一 `rm -f S91smb` 行为），
   避免同板两个后处理脚本。旧文件已 `git rm`。

## 3. 改动清单（功能提交 `b1998ddfe`，4 文件）

| 文件 | 变化 |
|---|---|
| `project/cfg/BoardConfig_IPC/BoardConfig-EMMC-Buildroot-RV1106_DW_TLY_V015-IPC.mk` | `RK_POST_BUILD_SCRIPT` 改为 `dw-tly-v015-post.sh`；`RK_POST_OVERLAY` 末位追加 `overlay-dw-tly-v015` |
| `project/cfg/BoardConfig_IPC/dw-tly-v015-post.sh` | 新增（替代旧 SMB 脚本）：删 `S91smb` + 用覆盖件换 `S21appinit` |
| `project/cfg/BoardConfig_IPC/overlay/overlay-dw-tly-v015/etc/init.d/S21appinit` | 新增：带 `/userdata/.rkipc-enable` 门控的启动脚本 |
| `project/cfg/BoardConfig_IPC/dw-tly-v015-disable-smb-post.sh` | 删除（功能并入上者） |

**未改动**：`project/build.sh`、共享 Buildroot `luckfox_pico_w_defconfig`、
`rv1106_ipc/RkLunch.sh`、`rv1106_ipc/CMakeLists.txt`、其他板型 BoardConfig/DTS。
`git diff --name-only` 在功能提交里只有上表 4 项。

## 4. 验证

### 4.1 构建前脚本级夹具测试（非实板）

`sh -n` 两个脚本通过；`git diff --check` 通过。以夹具模拟 `build.sh` 产出的共享
`S21appinit` 与 `/oem/usr/bin/RkLunch.sh`，按启用路径运行**真实门控脚本**：

| 用例 | 期望 | 实测 |
|---|---|---|
| 开关缺失 | 关闭 | 关闭，未调用 RkLunch.sh |
| 开关为常规文件 | 打开 | 打开，调用 RkLunch.sh |
| 开关为目录 | 关闭 | 关闭 |
| 开关为指向常规文件的符号链接 | 关闭 | **初次误判为打开**，加 `[ ! -L ]` 后关闭 |
| 开关为悬空符号链接 | 关闭 | 关闭 |
| 开关为 FIFO | 关闭 | 关闭 |
| `restart` 且开关为文件 | 先停后起 | `RkLunch-stop.sh` 后 `RkLunch.sh` |
| 非法参数 | 退出码 1 | 退出码 1 |

`dw-tly-v015-post.sh` 夹具端到端：`S91smb` 被删、`S21appinit` 被替换为 755 覆盖件；
缺 overlay 覆盖件 → 退出码 1；缺 `RK_PROJECT_PACKAGE_ROOTFS_DIR` → 退出码 2；
重复执行幂等。

### 4.2 完整构建（提交 `b1998ddfe`，工作区干净）

```
env -i PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin HOME="$HOME" TERM=dumb ./build.sh check
env -i PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin HOME="$HOME" TERM=dumb ./build.sh allsave
```

- `check` 退出码 0，日志 `/tmp/dw012-v015-check-20260930-rkipc.log`。
- `allsave` 退出码 0，日志 `/tmp/dw012-v015-allsave-20260930-rkipc.log`（2,773 行）；
  第 2522 行 `dw-tly-v015-post: rkipc autostart gated by /userdata/.rkipc-enable; SMB/NMB autostart disabled`；
  第 2760/2772/2773 行 `build_updateimg`/`build_save`/`build_allsave succeeded`。
- 产出目录 `IMAGE/IPC_EMMC_BUILDROOT_RV1106_DW_TLY_V015_20260930.2056_RELEASE_TEST/`。

### 4.3 包内静态核验（见 `2026-09-30-v015-allsave-20260930.2056-image.md`）

要点（详见该文件）：双层解包后 7 分区逐个 SHA-256 与候选一致；分区表无越界；
镜像内 `/etc/init.d/S21appinit` 是**带门控的覆盖件**（与源文件同哈希
`446ea1519ea7e3e8ec8e8e7343c4da50786209ce162fe2c05ba31465f4352c89`），
**不是**共享生成器那版；`/etc/init.d/S91smb` 不存在而 `smbd` 二进制仍在；
oem 内 `rkipc`/`RkLunch.sh`/`RkLunch-stop.sh` 在位。

## 5. 与上一候选的差异

`20260930.2056`（`163abefa…`）相对 `20260930.2013`（`90e77d72…`）**只有 rootfs 变**：

| 产物 | 2013 | 2056 |
|---|---|---|
| `update.img` | `90e77d72…` | `163abefa…` |
| `rootfs.img` | `6d5e2b5f…` | `db38fb90…` |
| `boot.img` | `1b33d675…` | `bac6fd9f…`（内容同，仅时间戳） |
| 打包 `fdt` | `e3b00deb…` | `e3b00deb…`（**逐字节相同**） |
| 打包 `kernel` | `c3d6b6c9…` | `c3d6b6c9…`（**逐字节相同**） |
| `oem.img` | `1f3dc9e3…` | `30825e05…` |

⇒ 内核与 DTB 未变（存储配置、CPUFreq-off、force_jtag 修复均保持），
本版唯一实质变化是 rootfs 里 rkipc 的启动门控与 S21appinit 内容。

## 6. 未决 / 待验证（不得写成已通过）

- **实板验证全部缺失**：门控未在真机启动序列里跑过；`/userdata` 在 S21appinit
  执行时刻是否确实已挂载，依赖 `S20linkmount` 的行为，**未实机确认**。
- 手动 `touch /userdata/.rkipc-enable` 后重启能否如预期拉起 rkipc，**未实测**。
- V015 无实板、U17 VCCQ/焊球未签核；本候选不得刷 V020、不得称量产或已签核。

## 7. 复核命令

```
git show --stat b1998ddfe
sh -n project/cfg/BoardConfig_IPC/dw-tly-v015-post.sh
sh -n project/cfg/BoardConfig_IPC/overlay/overlay-dw-tly-v015/etc/init.d/S21appinit
env -i PATH=... HOME="$HOME" TERM=dumb ./build.sh check
env -i PATH=... HOME="$HOME" TERM=dumb ./build.sh allsave
mkdir -p /tmp/u2056 /tmp/fw2056     # rkImageMaker 不会自建输出目录
tools/linux/Linux_Pack_Firmware/rkImageMaker -unpack <update.img> /tmp/u2056
tools/linux/Linux_Pack_Firmware/afptool -unpack /tmp/u2056/firmware.img /tmp/fw2056
debugfs -R "stat /etc/init.d/S21appinit" /tmp/fw2056/Image/rootfs.img
debugfs -R "dump /etc/init.d/S21appinit /tmp/S21_2056.sh" /tmp/fw2056/Image/rootfs.img
sha256sum /tmp/S21_2056.sh project/cfg/BoardConfig_IPC/overlay/overlay-dw-tly-v015/etc/init.d/S21appinit
debugfs -R "stat /etc/init.d/S91smb" /tmp/fw2056/Image/rootfs.img      # File not found
debugfs -R "stat /usr/sbin/smbd"     /tmp/fw2056/Image/rootfs.img      # 仍在
debugfs -R "stat /usr/bin/rkipc"     /tmp/fw2056/Image/oem.img
git checkout -- project/app/wifi_app/wifi/librkwifibt.so
```

## 8. 证据路径

- 本文件：`aidlc-docs/evidence/2026-09-30-v015-rkipc-autostart-gate.md`
- 本次构建与包内核验：`aidlc-docs/evidence/2026-09-30-v015-allsave-20260930.2056-image.md`
- 状态快照：`aidlc-docs/CURRENT.md`
