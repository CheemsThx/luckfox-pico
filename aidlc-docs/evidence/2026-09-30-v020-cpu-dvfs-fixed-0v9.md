# V020 CPU DVFS：固定 0.9V 电源轨与 SDK OPP 表不匹配

日期：2026-09-30
工作项：DW-012 / V020 启动 CPU DVFS 故障切片
范围：只分析 + 只改 V020 板级 dtsi。未烧写、未 ADB、未整包构建、未改通用 `rv1106.dtsi`/驱动/应用。

## 0. 仓库与起点

| 项 | 值 |
|---|---|
| SDK 工作区 | `/home/henry/rv1106/luckfox-pico-v020-main-axiarz`（git worktree） |
| 分支 | `codex/dw-012-v020-nand-validation` |
| 起点提交 | `a36c331c46596403e82c75e0f2c00df9d08115dd` |
| 板级 DTS | `sysdrv/source/kernel/arch/arm/boot/dts/rv1106g-dw-tly-v020.dts` |
| 板级 dtsi（本次唯一改动） | `sysdrv/source/kernel/arch/arm/boot/dts/rv1106-dw-tly-v020-ipc.dtsi` |
| 共用 SoC dtsi | `sysdrv/source/kernel/arch/arm/boot/dts/rv1106.dtsi` |

现场现象（用户口述 + 只读 ADB，本会话未复现）：串口持续打印
`rockchip_pvtpll_set_volt ... (925000 1000000 uV): -22` 与几百次
`_set_opp_voltage ... (1000000 1000000 1000000 mV): -22` / `cpufreq: __target_index ... -22`。
日志里的 mV 标签实际是 uV 数值。

## 1. 硬件事实：V020 CPU 轨固定 0.9V

- 2026-09-29 网表：U9(RY3430) 的 FB 由 R26=10k(VDD_0V9→FB)、R27=20k(FB→GND) 固定分压，
  L3 输出 `VDD_0V9`（Vout = Vref·(1+10k/20k)，Vref=0.6V ⇒ 0.9V）。**没有**从 CPU 侧
  PWM/I2C 到 U9 的控制路径。
- 同一轨还接 RV1106 CPU_DVDD(pin115)、DVDD_1..7、PMU_DVDD0V9、OSC_PLL_DVDD，故该轨
  **不能**随 CPU 频率抬高。
- 板级 dtsi 也按固定轨描述（`rv1106-dw-tly-v020-ipc.dtsi`）：

```dts
vdd_arm: vdd-arm {
	compatible = "regulator-fixed";
	regulator-name = "vdd_arm";
	regulator-min-microvolt = <900000>;
	regulator-max-microvolt = <900000>;
	regulator-always-on;
	regulator-boot-on;
};
...
&cpu0 { cpu-supply = <&vdd_arm>; };
```

对照：共用参考 `rv1106-ipc.dtsi:43-53` 的 `vdd_arm` 是 **pwm-regulator**（724000–1078000，
init 950000）。V020 因硬件无 PWM 路径改成了 fixed，但沿用同一张 OPP 表。

## 2. 共用 OPP 表按“可调 rail”设计

`rv1106.dtsi:112-173` 的 `cpu0-opp-table`（节选）：

| OPP | opp-hz | opp-microvolt = <target min max> | 额定电压档 |
|---|---|---|---|
| opp-408000000 … opp-1200000000 | ≤1.2G | `<850000 850000 1000000>` | 850mV |
| opp-1296000000 | 1.296G | `<875000 850000 1000000>` | 875mV |
| opp-1416000000 | **1.416G** | `<925000 850000 1000000>` | **925mV** |
| opp-1512000000 | 1.512G | `<975000 850000 1000000>` | 975mV |
| opp-1608000000 | 1.608G | `<1000000 850000 1000000>` | 1000mV |

OPP 解析顺序 `target, min, max`（`drivers/opp/of.c:599-606`）。
节点另带：`rockchip,pvtpll-min-rate=<1104000>`（`rv1106.dtsi:120`）、
`rockchip,pvtpll-volt-step=<12500>`（:121）、`rockchip,low-temp=<10000>`（:124）、
`rockchip,low-temp-min-volt=<900000>`（:125）。

## 3. 根因：固定 0.9V 轨无法满足 >0.9V 的 OPP 电压

### 3.1 固定 regulator 的核心语义

- 固定 regulator 描述符：`n_voltages = 1`、`fixed_uV = 900000`（`drivers/regulator/fixed.c:198-201`）。
- `regulator_set_voltage_unlocked()`（`drivers/regulator/core.c:3514`）对“不能改压”的
  regulator 走重叠短路：若 `min_uV <= current(900000) <= max_uV` 则**成功返回**（:3531-3540）；
  否则落到 `!ops->set_voltage && !ops->set_voltage_sel` 的检查 → 返回 **-EINVAL**（:3545）。
- `regulator_set_voltage_triplet(reg, min, target, max)`（`include/linux/regulator/consumer.h:645-653`）
  先试 `set_voltage(target, max)`，失败再试 `set_voltage(min, max)`。

因此对 [900000,900000] 的轨：
- `set_voltage(850000,1000000)` → 900000 落在区间 → **成功**（故 1.2G 及以下不报错）；
- `set_voltage(925000,1000000)` → 925000>900000，短路不成立 → **-EINVAL**；
- `set_voltage(1000000,1000000)` → **-EINVAL**。

这与真机日志（1.416G 的 925000、1.608G 的 1000000 报 -22，而当前 600MHz 正常）逐条吻合。

### 3.2 三处触发点

1. **PVTPLL OPP 校准**（`drivers/soc/rockchip/rockchip_opp_select.c:842-985`）：
   在 boot 期由 `rockchip_cpufreq_adjust_power_scale()` 调用
   （`drivers/cpufreq/rockchip-cpufreq.c:649-662`，入口是 `cpufreq-dt.c:290`）。
   对每个 rate≥`pvtpll-min-rate` 的 OPP 累加 `volt=max(volt,u_volt)` 并
   `rockchip_pvtpll_set_volt(reg, volt, u_volt_max, "vdd")`（:912）。到 1.416G 时
   volt=925000、max=1000000 → `regulator_set_voltage(925000,1000000)` → -EINVAL，
   打印 `rockchip_pvtpll_set_volt ... (925000 1000000 uV): -22` 并 `goto out` **中止校准**。
2. **低温系统监控补偿**（`drivers/soc/rockchip/rockchip_system_monitor.c:862-917`）：
   `rockchip,low-temp=10000`（10℃）+ `rockchip,low-temp-min-volt=900000` 使
   `is_low_temp` 时把每个 OPP 的 `u_volt=u_volt_min=low_temp_volt`,
   `u_volt_max=max(旧max,low_temp_volt)`（:878-895）。1.608G 档因此变成
   **(1000000,1000000,1000000)** → 三元组两次尝试都不含 900000 → -EINVAL，
   打印 `_set_opp_voltage ... (1000000 1000000 1000000 mV): -22`。
   （1.416G 档变 925000 同理。）`max_volt`/`high_temp_max_volt` 缺省 ULONG_MAX、
   `low_temp_min_volt` 取自节点（:634-652），故补偿值确实会被抬到 >0.9V。
3. **运行时换档**：`cpu_opp_helper`→`rockchip_cpufreq_set_volt`（`rockchip-cpufreq.c:422-440`）
   → `_set_opp_voltage`（`drivers/opp/core.c:628-651`）对目标 OPP 调
   `regulator_set_voltage_triplet`。同一 (min,target,max) 失败即 `__target_index` 换档失败。

### 3.3 结论

不是“0.9V 本身错”，而是**共用 OPP 表声明的 1.416/1.512/1.608G 三档额定电压 >0.9V**，
在固定轨上任何一次 set_voltage 都无法满足；且 PVTPLL 校准+低温补偿会把这些电压
写进 OPP 对象，使失败持续复现。必须把这部分 OPP 从板级去掉并让保留档的电压与
固定轨一致。**不允许**把 fixed regulator 伪装成可调，或删掉 `cpu-supply` 掩盖。

## 4. 修复（仅板级 dtsi）

`rv1106-dw-tly-v020-ipc.dtsi` 在 `&cpu0` 之后新增 `&cpu0_opp_table` 覆盖：

- `rockchip,low-temp-min-volt = <900000>`（显式钉住，禁止低温补偿抬压）；
- 删除 `opp-1416000000` / `opp-1512000000` / `opp-1608000000`；
- 保留 ≤1.296G 的 6 档，`opp-microvolt = <900000 900000 900000>`。

保留档判定规则：**只保留额定电压 ≤ 0.9V 的档**。1.296G 额定 875mV ≤ 900mV（唯一
临界档，留 +25mV）；1.416G 起额定 ≥925mV，删除。

修复后各调用点：
- PVTPLL 校准：`volt=max(...,900000)=900000`，`set_volt(900000,900000)` → 900000 落在
  [900000,900000] → 成功；内层 `volt+=12500=912500 > volt_max=900000` 立即 break，
  u_volt 保持 900000，全程无 -EINVAL。
- 低温/常温补偿：三元组恒为 (900000,900000,900000) → 成功。
- 运行时换档：三元组 (900000,900000,900000) → 成功。
- 频点上限：`dev_pm_opp_init_cpufreq_table` 只枚举保留 OPP，ondemand 的 max 由 1.608G 降为 1.296G。

## 5. 验证（本会话实做）

命令与结果（工作目录 `sysdrv/source/kernel`）：

```
cpp -nostdinc -I include -I arch/arm/boot/dts -undef -D__DTS__ \
    -x assembler-with-cpp arch/arm/boot/dts/rv1106g-dw-tly-v020.dts -o /tmp/v020.fixed.pre.dts
# exit 0
dtc -I dts -O dtb -o /tmp/v020.fixed.dtb /tmp/v020.fixed.pre.dts
# exit 0（仅既有 warning：unit_address_vs_reg / i2c_bus_reg 等）
dtc -I dtb -O dts /tmp/v020.fixed.dtb
```

反编译核对（hex）：
- `cpu0-opp-table` 仅剩 opp-408/600/816/1104/1200/1296MHz；三者
  `opp-microvolt = <0xdbba0 0xdbba0 0xdbba0>`（0xdbba0 = 900000）；
  `rockchip,low-temp-min-volt = <0xdbba0>`；`rockchip,pvtpll-min-rate = <0x10d880>`(1104000) 未改。
- `opp-1416000000` / `opp-1512000000` / `opp-1608000000` 计数为 0。
- `cpu@0` 仍有 `cpu-supply = <0x04>`，`0x04` 即 `vdd-arm`
  （`regulator-min/max-microvolt = <0xdbba0>`，fixed，always-on/boot-on）。未被伪装成可调。

`git diff --check`：exit 0。

**未做**：整包 `update.img` 构建、烧写、真机 ADB。本切片只到源码 + DTB 编译/反编译级别；
实机“不再刷 -22”“1.296G 稳定”属待 Codex 另下构建/上板切片验证。

## 6. 限制 / 待验证

- **1.296G@0.9V**：额定 875mV，留 +25mV。这是额定 ≤900mV 的最高档，故取为上限；
  若日后实测该档在 0.9V 下不稳，**下调上限到 1.2G（额定 850mV，留 +50mV）** 即可，
  改法同为删除对应 OPP + 重钉电压。
- 低功耗收益：轨固定，降频不降 CPU 电压；VPU/NPU 另有各自 pvtpll，不受本改动影响。
- 本切片未触碰通用 `rv1106.dtsi`、其它板、驱动、应用；未 push、未烧写、未 ADB。
