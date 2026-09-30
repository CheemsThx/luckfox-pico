# V015 eMMC：Wi-Fi 用户态构建缺口修复（build.sh app 凭据分支）

- 日期：2026-09-30
- 分支：`codex/dw-012-v015-emmc-adaptation`
- 起点提交：`9095c36e7c645c1da8f43f59ae7af86f915dac6a`
- 工作项：DW-012 / V015 eMMC
- 允许范围：仅 `project/build.sh`（本轮只修正脚本注释与本证据措辞，不改功能代码）
- 目标：量产目标 V015 eMMC；V020 NAND 为验证板
- 环境：WSL2（Linux 6.6.87.2-microsoft-standard-WSL2），宿主工具 `bash/gcc/make/tar` 来自 `/usr/bin`，无 WSL 互操作项

## 需求与验收项

1. `RK_ENABLE_WIFI=y` 且两项凭据都提供 → 保持原 `network` 配置生成行为。
2. 两项凭据都未提供 → 生成只有 `ctrl_interface/ap_scan/update_config`、无 `network` 块的基础配置，并**继续** `build_app`。
3. 只提供一项 → 明确报错，不得静默产出半套配置。
4. 不复用旧配置中的凭据。
5. 其它板影响面：仅限于"缺凭据时不再跳过 app 构建"。
6. 只改 `project/build.sh`；先 `bash -n` / `diff --check`；用当前 V015 环境执行 `./build.sh app`；核对退出码、Wi-Fi 用户态文件、配置结构；确认无秘密；如生成 tracked binary 副作用则只恢复该文件。

## 代码事实（映射）

根因链（本任务结论，经源码核实）：

1. `project/build.sh:641`（修复前）：`check_config LF_WIFI_PSK LF_WIFI_SSID || return 0`。当任一凭据未定义时，`check_config`（`project/build.sh:140-152`）返回 1，`build_app` 立即 `return 0`，**不报错、不构建**。
2. `build_app`（`project/build.sh:638`）是唯一调用 `make -C ${SDK_APP_DIR}`（`project/build.sh:665`）的地方。被跳过 ⇒ 整个 `project/app` 不构建。
3. wifi_app 安装链：`project/app/wifi_app/Makefile`
   - 第 113-131 行写入 `install_out/root/{etc,usr/bin,usr/lib}`；rv1106 走 `else` 分支（第 126 行），把 `wpa_supplicant.conf` 装到 `install_out/root/etc`。
   - 第 147 行 `MAROC_COPY_PKG_TO_APP_OUTPUT`（`project/app/Makefile.param:122-135`）把 `install_out` 作为整体目录树复制到 `${RK_APP_OUTPUT}=project/app/out/install_out`。
   - `project/build.sh:1526` `__COPY_FILES $RK_PROJECT_PATH_APP/root $RK_PROJECT_PACKAGE_ROOTFS_DIR`，其中 `RK_PROJECT_PATH_APP=output/out/app_out`（`project/build.sh:71`）=`project/app/out`，因此 `install_out/root/*` 落到 rootfs 根。
4. 被跳过的产物：`usr/bin/{rkwifi_server,wpa_supplicant,wpa_cli,wpa_supplicant_rtk,wpa_supplicant_nl80211_rtk,wpa_cli_rtk,hostapd,hostapd_cli,wifi_start.sh}`、`usr/lib/{librkwifibt.so,libwpa_client.so}`、`etc/wpa_supplicant.conf`。

生效目标身份（**未读取任何凭据值**，仅核对非秘密变量与符号链接）：

- `.BoardConfig.mk -> project/cfg/BoardConfig_IPC/BoardConfig-EMMC-Buildroot-RV1106_DW_TLY_V015-IPC.mk`
- `RK_CHIP=rv1106`、`RK_KERNEL_DTS=rv1106g-dw-tly-v015.dts`、`RK_APP_TYPE=RKIPC_RV1106`、`RK_ENABLE_WIFI=y`、`RK_ENABLE_WIFI_CHIP=AIC8800DC`；**无** `LF_WIFI_SSID/LF_WIFI_PSK`（仅检查存在性）。

## 关键决定

- 用显式 `if [ -z "$LF_WIFI_SSID" ] ...` 判空分支替换 `check_config ... || return 0`。分支判断会读取变量取值，但取值只用于判空，未在日志或证据中展示具体凭据值。
- 两分支各用独立 heredoc 写入同一临时目标 `$WIFI_NEW_CONF`；`cat >` 本身就会截断目标，不会复用旧内容。真正的防止旧凭据残留手段是：无凭据分支写入不含 `network` 块的新基础文件、或凭据分支写入新 `network` 块，随后 `mv` 覆盖目标配置。函数开头 `rm -f $WIFI_NEW_CONF` 仅用于清理上次构建可能残留的临时文件。
- `mv` 移到分支合流处、只在生成成功后执行；失败路径不动目标配置。
- 混合情形 `return 1` 会中断整条 `./build.sh`（`set -e` 未显式开启，但调用点 `eval "${option}"` 失败语义允许硬失败），满足"不得静默打包半套配置"。
- 保留 `touch $WIFI_NEW_CONF`，与原行为一致（非必需）。

## 验证（实际命令与结果）

### 1. 静态检查

```
bash -n project/build.sh        # exit 0
git diff --check                # exit 0
```

### 2. 实环境构建（当前 V015 环境）

```
cd project && ./build.sh app    # 仅本进程干净 PATH：/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
APP_BUILD_EXIT=0
```

日志 `/tmp/dw012-appbuild.log`（1581 行，未向模型输出凭据原文）：

- 第 18 行：`No Wifi SSID and PASSWD, generate a network-less wpa_supplicant.conf`
- 第 19 行：`============Start building app============`（修复前此处会被跳过）
- 第 1564/1576 行：`[INSTALL] install_out` / `[INSTALL] .../project/app/out`

### 3. 产物核对（非命令文本推断）

生成并发布到 `output/out/app_out/root`：

| 路径 | 结果 |
| --- | --- |
| `etc/wpa_supplicant.conf` | 存在，65 B，`-rw-r--r--`，`network` 块 = 0，`ssid`/`psk` 行 = 0，三个基础键 = 3 |
| `usr/bin/wpa_supplicant` | ELF 32-bit LSB, ARM, EABI5 |
| `usr/bin/hostapd` | ELF 32-bit LSB, ARM, EABI5 |
| `usr/bin/rkwifi_server` | ELF 32-bit LSB, ARM, EABI5 |
| 其余 | `wpa_cli`、`wpa_supplicant_rtk`、`wpa_supplicant_nl80211_rtk`、`wpa_cli_rtk`、`wifi_start.sh`、`iperf`、`dnsmasq`、`usr/lib/librkwifibt.so`、`usr/lib/libwpa_client.so` 均已安装 |

`wpa_supplicant.conf` 仅含键名 `ctrl_interface=`、`ap_scan=`、`update_config=`（未输出取值）。

### 4. 秘密扫描

- `project/app/wifi_app/wpa_supplicant.conf`、`output/out/app_out/root/etc/wpa_supplicant.conf`：`ssid`/`psk` 条目计数 = 0，`network` = 0。
- `/tmp/dw012-appbuild.log`：`password|psk=|ssid=` 命中计数 = 0。

### 5. 三分支行为对照（隔离函数体外测试，环境仅 `LF_WIFI_*` + `RK_ENABLE_WIFI=y`，目标配置预置 `STALEMARKER` 旧凭据）

| 分支 | 修改后 exit | 修改后 network 块 | 旧标记残留 | 目标配置保留旧凭据 | 对照 HEAD |
| --- | --- | --- | --- | --- | --- |
| 两项都有 | 0 | 1（含 ssid/psk） | 0 | 否 | 同为 1 块，行为一致 |
| 两项都无 | 0 | **0**，无 ssid/psk | 0 | 否 | HEAD 走 `return 0`，旧标记残留 = 2，目标未更新 |
| 只有一项 | **1**（报 "must be set together"） | 0 | 0 | 否（目标未改） | HEAD 静默跳过 |

正常生成的两条分支均无 `STALEMARKER` 残留 ⇒ **不复用旧凭据**。失败分支（只提供一项）目标配置保持旧文件不变、不清空旧凭据，但其构建停止，失败不会被静默打包。

### 6. tracked binary 副作用与恢复

构建重写了 3 个受版本控制的二进制（这些文件此前因 `build_app` 被跳过而保持旧版）：

```
 project/app/wifi_app/hostapd-2.6/hostapd/hostapd        (Bin 1256692 -> 1255448)
 project/app/wifi_app/hostapd-2.6/hostapd/hostapd_cli    (Bin 51584 -> 51576)
 project/app/wifi_app/wifi/librkwifibt.so                (Bin 281544 -> 281904)
```

按任务要求核对后仅恢复该 3 个文件：

```
git checkout -- project/app/wifi_app/hostapd-2.6/hostapd/hostapd \
                project/app/wifi_app/hostapd-2.6/hostapd/hostapd_cli \
                project/app/wifi_app/wifi/librkwifibt.so
```

最终工作区：

```
## codex/dw-012-v015-emmc-adaptation
 M project/build.sh
```

此处工作区命令行仅按当时状态记录脚本可见的 `M project/build.sh`；提交前预期为一项脚本修改（`project/build.sh`）加本证据新文件（`aidlc-docs/evidence/2026-09-30-v015-wifi-userland-build-gap.md`，提交前为未跟踪状态）。`project/app/wifi_app/wpa_supplicant.conf` 与 `project/app/out/` 均为 `.gitignore` 覆盖的生成物，不入库。

## 影响面（其它板）

- 变更仅在 `build_app` 的 `RK_ENABLE_WIFI=y` 分支内，条件从"缺任一凭据即跳过整个 app 构建"变为"缺凭据仍构建 app，仅不生成凭据 network 块"。
- 对**已配置凭据**的板：生成逻辑与旧版逐字节等价（同 3 键 + 1 个 network 块）。
- 对**未配置凭据**的板：不再跳过 `build_app`（行为改进，符合本次验收项 5）。
- 对**只配置一项**的板：由静默跳过变为显式失败，属刻意收紧，避免打包半套配置。

## 未决 / 待办

- 提交：本轮以工作切片形式暂存并提交 `project/build.sh` 与本证据文件。
- 未做：`full allsave`、push、烧录、设备操作（均未授权）。
- 实机：未烧录验证；本次仅为构建与包内静态验证。
- 若后续以本改动提交，建议同时说明 3 个 tracked binary 会被构建重写这一既有现象（与本次修复无关）。

## 证据路径

- 构建日志：`/tmp/dw012-appbuild.log`（临时，未入库）
- 本文件：`aidlc-docs/evidence/2026-09-30-v015-wifi-userland-build-gap.md`
