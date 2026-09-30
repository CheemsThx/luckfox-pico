# V020 CPU 动态调频/调压撤销（纠正 75a002c9 的"限频"方案）

日期：2026-09-30
工作项：DW-012 / V020 CPU DVFS 撤销（S2 Comprehensive）
提交：见本文件所在提交（简体中文标题 "board: V020 撤销 CPU 动态调频/调压"）
范围：只改 V020 板级 dtsi + V020 内核配置 fragment。未改通用 `rv1106.dtsi`/defconfig、
驱动、应用、其它板；未烧写、未 ADB、未 `allsave`、未 push。

## 0. 仓库与起点

| 项 | 值 |
|---|---|
| SDK 工作区 | `/home/henry/rv1106/luckfox-pico-v020-main-axiarz`（git worktree） |
| 分支 | `codex/dw-012-v020-nand-validation` |
| 起点提交 | `75a002c90d082655c9e02c5fa154cdbf46796975`（干净，核对通过） |
| 改动文件 | `sysdrv/source/kernel/arch/arm/boot/dts/rv1106-dw-tly-v020-ipc.dtsi`、`sysdrv/source/kernel/arch/arm/configs/rv1106-v020.config` |
| 板级顶层 DTS | `rv1106g-dw-tly-v020.dts`（本次未改） |
| 内核配置基座 | `luckfox_rv1106_linux_defconfig` + 板级 fragment `rv1106-bt.config rv1106-v020.config` |

## 1. 需求纠正（为什么不是"继续限频"）

用户明确：V020 的 CPU 电源由硬件设定死，**不需要** CPU 电压/调频功能。

前一提交 `75a002c9` 的分析（固定 0.9V 轨无法满足共用 OPP 表里 >0.9V 的高压档，
运行期 `-EINVAL` 刷屏）**仍然成立**，但它的修法是"保留 ≤1.296GHz 的档并在 0.9V
轨上继续动态调频"，这仍保留了 DVFS 通路，不符合"不需要调频"的要求。本次改为
**整体撤销** CPU 动态调频/调压：不再让 cpufreq/cpufreq-dt 改 CPU 时钟，也不再
向任何 regulator 请求 CPU 电压。`75a002c9` 的 OPP 限频改动被本提交推翻（用后续
提交纠正，未重写历史）。旧证据 `2026-09-30-v020-cpu-dvfs-fixed-0v9.md` 的根因
分析仍可参考，其"修复"结论已被本文件取代。

## 2. 硬件事实（沿用旧证据，未变）

- VDD_0V9 由 U9(RY3430) + R26=10k(VDD_0V9→FB) / R27=20k(FB→GND) 固定分压
  ⇒ 0.9V；网表上没有 CPU 侧 PWM/I2C 到 U9 的控制路径。
- 该轨同时接 CPU_DVDD(pin115)、DVDD_1..7、PMU_DVDD0V9、OSC_PLL_DVDD，
  不能随 CPU 频率抬高。

## 3. 撤销项与代码级依据

### 3.1 板级 DTS（`rv1106-dw-tly-v020-ipc.dtsi`）

- `&cpu0`：`/delete-property/ operating-points-v2;` 与 `/delete-property/ cpu-supply;`。
- 删除本板 `vdd_arm` 虚拟 `regulator-fixed` 节点。
- `/delete-node/ &cpu0_opp_table;`：删除共用 `rv1106.dtsi` 针对本板引入的 OPP 表
  实例（表内 `nvmem-cells=<&cpu_leakage>`、`rockchip,pvtpll-*`、`rockchip,low-temp-*`
  等对本板无意义）。

两处绑定删除后，`drivers/cpufreq/rockchip-cpufreq.c` 的探测必然失败：

- `rockchip_cpufreq_cluster_init()`（:540）在 :563/:565 检查 `cpu-supply`/`cpu0-supply`，
  两者都无 → 返回 `-ENOENT`；:570 检查 `operating-points-v2`，无 → `dev_warn("OPP-v2
  not supported")` 并返回 `-ENOENT`。
- `rockchip_cpufreq_driver_init()`（:953）在此错误上 :972 `pr_err("Failed to initialize
  dvfs info cpuN")` 并 `goto release_cluster_info`，**跳过** :1007 的
  `platform_device_register_data(NULL, "cpufreq-dt", ...)` ⇒ cpufreq-dt 根本不注册。

即便假设 cpufreq-dt 被注册，第二道闸也会拦住：`cpufreq-dt.c:274-279`
`dev_pm_opp_get_opp_count()<=0` → `"OPP table can't be empty"` → 返回 `-ENODEV`。

### 3.2 内核配置（`rv1106-v020.config` fragment）

新增（叠加在 `luckfox_rv1106_linux_defconfig` 之上）：

```
# CONFIG_CPU_FREQ is not set
# CONFIG_CPUFREQ_DT is not set
# CONFIG_ARM_ROCKCHIP_CPUFREQ is not set
```

- fragment 由 `scripts/kconfig/Makefile` 的 `%.config` 规则经
  `scripts/kconfig/merge_config.sh -m .config` 合并后 `olddefconfig`（本板
  `RK_KERNEL_DEFCONFIG_FRAGMENT="rv1106-bt.config rv1106-v020.config"`）。
- `CPU_FREQ=n` 使依赖它的 `CPUFREQ_DT`/`ARM_ROCKCHIP_CPUFREQ`/各 governor/
  `CPU_FREQ_THERMAL` 一并置 n（`CPU_FREQ_THERMAL` 在
  `drivers/thermal/Kconfig` 的 `if CPU_THERMAL` 内且 `depends on CPU_FREQ`，
  `default y`）⇒ `drivers/cpufreq/` 与 `drivers/thermal/cpufreq_cooling.o` 不再编译/链接。
- 全树仅有 `arch/arm/Kconfig` 的 `ARCH_SA1100` `select CPU_FREQ`（本板不选），
  没有其它 select 会把 CPU_FREQ 重新拉回 y。

## 4. 热保护：为什么关 cpufreq 不危险（刻意保留）

`ROCKCHIP_THERMAL`（及 `THERMAL`）**不依赖** `CPU_FREQ`，保持 =y。SoC 的两条热
关断通路都在，且都不经过 cpufreq：

1. **硬件 tshut**：`rv1106.dtsi` 的 `tsadc@ff3c8000`
   `rockchip,hw-tshut-temp=120000`(120℃)、`rockchip,hw-tshut-mode=0:CRU`，
   超温由 tsadc 硬件经 CRU 直接复位 SoC。
2. **软件 critical trip**：`soc-thermal` 的 `soc-crit`，`temperature=115000`(115℃)、
   `type="critical"`。`drivers/thermal/thermal_core.c:handle_critical_trips()` 对
   `THERMAL_TRIP_CRITICAL` 直接 `orderly_poweroff(true)` 并挂 backup
   `thermal_emergency_poweroff()`，与 cpufreq cooling 无关。

`CONFIG_CPU_THERMAL` 只决定"能否把 CPU 当 cooling device"，没有 cpufreq policy 时
本来就注册不了 cooling device，保留 =y 无副作用，未改。

## 5. 频率：未指定新的运行频率

撤销 cpufreq 后内核不再调用 `clk_set_rate(ARMCLK)` 换档。ARMCLK 保持 bootloader
默认：U-Boot `arch/arm/include/asm/arch-rockchip/cru_rv1106.h` `APLL_HZ = 1104MHz`
（`clk_rv1106.c:rv1106_clk_init()` 把 APLL 设为 APLL_HZ）。这与通用 `rv1106.dtsi`
cru 节点 `assigned-clock-rates` 里 `ARMCLK=1104MHz`（由 clk 框架
`drivers/clk/clk.c:5262 of_clk_set_defaults()` 在 provider 注册时应用）一致，
因此本轮**没有引入任何新的频率**，CPU 停在 1.104GHz（共用 OPP 表里该档额定
850mV ≤ 0.9V，处于固定轨能力内）。

## 6. 验证（本会话实做）

工作目录 `/home/henry/rv1106/luckfox-pico-v020-main-axiarz`。

### 6.1 独立 DTS 语法/绑定核对（改动后、构建前）

```
cpp -nostdinc -I include -I arch/arm/boot/dts -undef -D__DTS__ -x assembler-with-cpp \
    arch/arm/boot/dts/rv1106g-dw-tly-v020.dts -o /tmp/v020.nodvfs.pre.dts   # exit 0
dtc -I dts -O dtb -o /tmp/v020.nodvfs.dtb /tmp/v020.nodvfs.pre.dts           # exit 0（仅既有 warning）
dtc -I dtb -O dts .../v020.nodvfs.dtb                                        # 反编译
```

反编译核对（工作目录 `sysdrv/source/kernel`）：

- `cpu@0` 仅剩 `device_type/compatible/reg/clocks`，**无** `operating-points-v2`、
  **无** `cpu-supply`；
- `operating-points`/`opp-microvolt`/`cpu0-opp-table`/`vdd-arm`/`cpu-supply`
  在整份 DTB 中计数为 **0**；
- `tsadc@ff3c8000` 仍在，`rockchip,hw-tshut-temp=0x1d4c0`(120000)、
  `rockchip,hw-tshut-mode=0x0`(CRU)；
- `soc-crit` 仍在，`temperature=0x1c138`(115000)、`type="critical"`。

### 6.2 真实内核构建

```
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin ./build.sh kernel
# 完整日志 /tmp/v020-dw012-kernel.log；EXIT=0（"Running build_kernel succeeded."）
```

### 6.3 构建后 `.config`（`sysdrv/source/objs_kernel/.config`）

```
445:# CONFIG_CPU_FREQ is not set
   CONFIG_CPUFREQ_DT            —— 不存在（自动置 n）
   CONFIG_ARM_ROCKCHIP_CPUFREQ  —— 不存在（自动置 n）
2123:CONFIG_THERMAL=y
2136:CONFIG_CPU_THERMAL=y
2140:CONFIG_ROCKCHIP_THERMAL=y
   CONFIG_CPU_FREQ_THERMAL      —— 不存在（自动置 n）
```

### 6.4 链接层核对（证明 cpufreq 未进 vmlinux）

```
grep -c cpufreq sysdrv/source/objs_kernel/System.map        # 0
ar t sysdrv/source/objs_kernel/drivers/thermal/built-in.a   # 无 cpufreq_cooling.o
grep rockchip_thermal_probe System.map                      # 存在
grep thermal_zone_device_register System.map                # 存在
```

（`drivers/cpufreq/*.o` 旧文件仍在磁盘，属未清理的增量构建残留；`System.map` 计数
为 0 且 `built-in.a` 不含它们，证明未被链接。`rockchip_pvtpll_calibrate_opp`/
`_set_opp_voltage` 仍在 vmlinux，是 VPU/NPU 等 devfreq 走的共用 OPP/rockchip_opp_select
代码，CPU 侧已无消费者调用。）

### 6.5 交付 DTB

```
dtc -I dtb -O dts sysdrv/out/bin/board_uclibc_rv1106/rv1106g-dw-tly-v020.dtb
```

结果同 6.1：`cpu@0` 无 OPP 绑定/cpu-supply，OPP 表与 vdd-arm 计数 0，
tsadc/soc-crit 计数 3（保留）。

### 6.6 洁净度

```
git diff --check     # exit 0
git status --short   # 仅上述 2 个源码文件（+ 本证据文件）
```

## 7. 限制 / 待验证

- **未**整包 `update.img`/`boot.img`、未烧写、未真机 ADB。本切片止于源码 + 内核
  构建 + DTB 反编译 + 链接符号核对。实机行为（CPU 固定 1.104GHz、无 cpufreq/
  regulator 报错、thermal 正常）留待 Codex 另下构建/上板切片。
- 交付镜像哈希：本切片只构建到 `sysdrv/out/bin/board_uclibc_rv1106/`（`Image`/
  `rv1106g-dw-tly-v020.dtb`/`resource.img`），未做整包 FIT，故无 update.img 哈希。
- CPU 固定频率 1.104GHz 来自 bootloader/通用 dtsi 默认，若实测该档在 0.9V 下不稳，
  需回到通用 `rv1106.dtsi` 的 cru `assigned-clock-rates`（超出本切片允许范围）。
- 未触碰通用 `rv1106.dtsi`、defconfig、V014/V015、驱动、应用、其它板。
