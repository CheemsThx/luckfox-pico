# DW-SDK-003：pstore / ramoops 重启后内核证据

日期：2026-09-03  
仓库：`CheemsThx/luckfox-pico`，分支 `main_axiarz`  
工作区：`/home/henry/rv1106/luckfox-pico`  
板型：`BoardConfig-SPI_NAND-Buildroot-RV1106_Luckfox_Pico_Ultra-IPC.mk`  
未烧写、未故意 panic、未 `./build.sh` 整包、未改应用仓库。

应用仓库 bolt `aidlc-docs/bolts/DW-SDK-003-pstore-ramoops.md` 本机不存在，按工作项提示执行。

## 交回摘要

| 项 | 值 |
|---|---|
| 是否已上板 | **否** |
| PSTORE 配置 | `CONFIG_PSTORE=y`、`CONFIG_PSTORE_CONSOLE=y`、`CONFIG_PSTORE_RAM=y`；显式关闭 `PSTORE_DEFLATE_COMPRESS`（避免拉 CRYPTO_DEFLATE） |
| 配置文件 | `sysdrv/source/kernel/arch/arm/configs/luckfox_rv1106_linux_defconfig`（未写入 `rv1106-bt.config`） |
| ramoops | `ramoops@d00000`，`reg = <0x00d00000 0x00040000>`（13MB 起，256KB） |
| DTS | `sysdrv/source/kernel/arch/arm/boot/dts/rv1106g-luckfox-pico-ultra-spi-nand.dts` 的 `&reserved_memory` |
| 转存 | 优先 `/mnt/sdcard/dw-pstore/<时间戳>/`，否则 `/userdata/dw-pstore/<时间戳>/`（userdata 约 2.2 MiB 有界） |
| 启动顺序 | overlay `S20pstore`：在 `S20linkmount` 之后、`S21appinit`（RkLunch / dw-rec）之前 |

## 1. 内存图（为何不用 thunder-boot 地址）

本板 Pico Ultra：**256MB DRAM**，物理 `0x00000000–0x10000000`。板级 DTS 无 `memory{}`，由 U-Boot/ATAGS 传入。

`rv1106-thunder-boot.dtsi` 写的是 **128MB** 板 + MCU log：

- `memory { reg = <0x00000000 0x08000000>; }`
- `ramoops@rtos_log`：`reg = <0x7c000 0x3000>`，`record-size`/`console-size` 均为 0，只有 `mcu-log-size`

直接复制会：(1) 只有 12KB 且不能记内核 console；(2) `0x7c000` 落在本板 SPL BSS/栈 `0x001fe000` 与 U-Boot TEXT `0x00200000` 之前，下次启动会被冲掉。

本板已占用 / 启动暂存：

| 区域 | 地址 | 来源 |
|---|---|---|
| SPL TEXT | `0x0` | `CONFIG_SPL_TEXT_BASE` |
| mmc_ecsd | `0x3f000` size `0x1000` | `ultra-ipc.dtsi` reserved-memory |
| SPL BSS/栈 | `0x001fe000` | `rv1106_common.h` |
| U-Boot TEXT | `0x00200000` | `CONFIG_SYS_TEXT_BASE` |
| 内核 TEXT | `0x00208000` | `arch/arm/Makefile` `CONFIG_CPU_RV1106` |
| U-Boot INIT_SP | `0x00400000` | 同上 |
| Image 0–8MB | `kernel_addr_r=0x00008000` | `ENV_MEM_LAYOUT_SETTINGS` |
| zImage 8–12MB | `kernel_addr_c=0x00808000` | 同上 |
| fdt 12–13MB | `fdt_addr_r=0x00c00000` | 同上；本板 dtb ≪ 1MB |
| **ramoops 13–13.25MB** | **`0x00d00000` / 256KB** | **本工作项** |
| ramdisk 14MB+ | `ramdisk_addr_r=0x00e00000` | `CONFIG_SYS_LOAD_ADDR=0x00e00800` |
| DT linux,cma | 10M，`reusable` + `inactive`，无 `@base` | `ultra-ipc.dtsi` |
| bootargs CMA | `rk_dma_heap_cma=66M`，无固定基址 | BoardConfig |

CMA 在 `arm_memblock_init()` 里由 `dma_contiguous_reserve()` 然后 `rk_dma_heap_cma_setup()` 从 **DRAM 高端** 切，与 13MB 空隙相距约 160MB+，不冲突。`drm-logo@0` 的 `reg` 大小为 0，占位。

候选 **不采用** `0x00100000`：它落在 U-Boot 标注的 Image 0–8MB 内，下次解压/加载内核会覆盖。

256KB 划分：`console-size=128KB`（即使 watchdog 硬复位、没有 oops 记录，也能留 printk 尾）；`record-size=32KB`，剩余约 128KB 可放约 4 条 oops/panic。未开 PMSG/FTRACE。未设 `no-map`。

## 2. 应用该读哪些文件

上一轮内核证据在转存目录里，**不要**读 `/root/config.json`，也**不要**依赖应用侧 10/50/20/20 循环 `/dev/kmsg` 日志（那是 U12）。

查找顺序：

1. `/mnt/sdcard/dw-pstore/latest/`（符号链接，指向最近一次时间戳目录）
2. 若无 SD，则 `/userdata/dw-pstore/latest/`

每个时间戳目录内（有则读，没有则跳过）：

| 文件 | 含义 |
|---|---|
| `console-ramoops` 或 `console-ramoops-0` | 上一轮 printk 控制台缓冲（重启/watchdog 最常见） |
| `dmesg-ramoops-0`、`dmesg-ramoops-1`、… | oops / panic 转储，编号越大通常越新 |

userdata 路径总占用约 **2.2 MiB** 上限，超了删最旧时间戳目录。SD 不按此上限裁。

## 3. 未做

- 未烧写、未故意 panic，因此 **未在板上验证** `/sys/fs/pstore` 与转存目录
- 未改 `dongwei-camera-rv1106`
- 未做诊断 tar.gz、DW-SDK-001/002、未提交 `rockiva_video_det`
