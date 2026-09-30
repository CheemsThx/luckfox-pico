# DW-012 / V015：CPU 固定 VDD_0V9 轨——整体撤销动态调频/调压（DTS + 内核配置）

- 日期：2026-09-30（本版为对上一版的返工，见 §0.2）
- 仓库/工作树：`luckfox-pico-v015-main-axiarz`（SDK worktree；按规则不写绝对路径）
- 分支：`codex/dw-012-v015-emmc-adaptation`
- 起点/HEAD：`32bd09ca687be64b00530834f80a7d960c2827b0`（本分支无 upstream 跟踪）
- 本次性质：**写入型**（V015 板级 DTS + V015 配置 fragment + 内核构建 + 静态证据）。
  **未**烧录、**未**访问设备、**未** push、**未** allsave、**未**读/写 `~/.claude/projects/`、
  **未**改通用 dtsi / V020 树 / BoardConfig / 充电参数 / 应用仓库。
- 修改文件（仅两个）：
  1. `sysdrv/source/kernel/arch/arm/boot/dts/rv1106g-dw-tly-v015.dts`
  2. `sysdrv/source/kernel/arch/arm/configs/rv1106-v015.config`
- 产物：`sysdrv/source/objs_kernel/arch/arm/boot/dts/rv1106g-dw-tly-v015.dtb`
  SHA-256 `e3b00deb653ccdcfaf6cd689c1d3b31be9a7612bd6c7307c30739a790b98f99a`

## 0. 工作项与验收

### 0.1 本次要回答的问题

V015 的 CPU 电压轨是否硬件固定、无软件调压路径？若是，能否**与 V020 的做法一致**，在
V015 专属文件内整体撤销动态调频/调压，并用**内核配置层面的开关**收口（而不只是拿掉
DTS 里一个属性），同时保留 thermal / GRF / eMMC / SDIO？

### 0.2 为什么返工（上一版被审核拒绝）

上一版只做了 `&cpu0 { /delete-property/ cpu-supply; }`，并**据此宣称“本板无动态调频”**。
该结论不成立，且机理写错：

- **错误一（完成证据不足）**：删除 `cpu-supply` 只切断“向 regulator 请求电压”这一条边；
  它**不能证明调频不存在**。`.config` 仍是 `CONFIG_CPU_FREQ=y` / `CPUFREQ_DT=y` /
  `ARM_ROCKCHIP_CPUFREQ=y`，DTB 仍带 `operating-points-v2`，cpufreq 子系统照样编进内核、
  照样会去 `clk_set_rate(ARMCLK)` 换档。以“无 cpu-supply ⇒ 必然无调频”作完成证据是错的。
- **错误二（机理写错）**：上一版称“无 `mem-supply` 会让 `rockchip_cpufreq_cluster_init()`
  返回 `-ENOENT`/`-EINVAL`”。核对源码不成立（见 §2.2）：无 `mem-supply` 时该函数**不返回
  错误**，而是走 `else { cluster->regulator_count = 1; }` 分支后 `return 0`。真正会因缺
  `cpu-supply` 直接 `return -ENOENT` 的是同一函数里更早的 `cpu-supply` / `cpu0-supply`
  判定句。上一版把这两处混为一谈，机理错误。

本版按 V020 已定型做法重做，并**以 `.config` 与 `vmlinux` 符号**作为“本板无动态调频”的
完成证据，DTS 改动只是配套。

### 0.3 验收项

① 在 V015 专属 DTS 中删除 `cpu0` 的 `operating-points-v2` 与 `cpu-supply`，删除继承的
`cpu0-opp-table` 与**仅供 CPU 的**伪 `vdd_arm` fixed regulator（先查引用再删）；
② 在 `rv1106-v015.config` 关闭 `CONFIG_CPU_FREQ`；③ 保留 `CONFIG_THERMAL` /
`ROCKCHIP_THERMAL` / `GRF` / eMMC / SDIO；④ 构建通过（退出码 0）；
⑤ 最终 `.config` 出现 `# CONFIG_CPU_FREQ is not set`；⑥ DTB 无 `cpu-supply` /
`operating-points-v2` / `cpu0-opp-table` / `vdd_arm`；⑦ `git diff --check` 干净。

---

## 1. 硬件证据（用户提供的 V015 网表，2026-09-29；**设计证据，非实测**）

- U2 `CPU_DVDD`(pin115) 与 `DVDD`/PMU 等同接 **VDD_0V9**。
- 该轨由 **U57 SY8088IAAC** 经 **L18** 产生；FB 分压 **R316=100k**（VDD_0V9→FB）/
  **R315=200k**（FB→GND）。
- 网表中**不存在**从 SoC 到 U57 的 PWM/I2C 控制路径。

⇒ 由分压比推导该轨约为 0.9V 且不可软件调节。**这是按网表推导，未做上板电压测量；
当前无 V015 量产板。** 下文一律不写“已实测”或“焊死”。

---

## 2. 代码/配置事实（本树可复核）

### 2.1 继承链（改动前）

| 事实 | 出处 |
|---|---|
| `cpu0` 带 `operating-points-v2 = <&cpu0_opp_table>`、`clocks = <&cru ARMCLK>` | `arch/arm/boot/dts/rv1106.dtsi:103-109` |
| OPP 表 408M~1608M，额定 `opp-microvolt` 850000..1000000（408M~1296M=850000/875000**低于** 0.9V；1416M=925000 / 1512M=975000 / 1608M=1000000 高于 0.9V） | `rv1106.dtsi:112-172` |
| 共享板级 dtsi 给 `&cpu0` 挂 `cpu-supply = <&vdd_arm>` | `rv1106-luckfox-pico-ultra-ipc.dtsi:221-223` |
| `vdd_arm` 是 **regulator-fixed**，min 800000 / max 1000000 / init 900000，always-on | `rv1106-luckfox-pico-ultra-ipc.dtsi:160-168` |
| V015 板 DTS 原本**未**覆写 `cpu0`，也未引用 `vdd_arm` | `rv1106g-dw-tly-v015.dts`（改前） |

`rv1106-luckfox-pico-ultra-ipc.dtsi` 被三个板级 dts 引用：`rv1106g-dw-tly-v015.dts`、
`rv1106g-luckfox-pico-ultra.dts`、`rv1106g-luckfox-pico-ultra-spi-nand.dts`。**不能改共享
dtsi**，故所有删除都在 V015 板级 dts 内用 `/delete-node/`、`/delete-property/` 覆写。

### 2.2 `rockchip-cpufreq.c` 里 `cpu-supply` 与 `mem-supply` 的真实作用（纠正上一版机理）

| 位置 | 行为 |
|---|---|
| `rockchip_cpufreq_cluster_init()` 起手 | 有 `cpu-supply` 取 `reg_name="cpu"`，否则有 `cpu0-supply` 取 `"cpu0"`，**都没有则 `return -ENOENT`**（`rockchip-cpufreq.c:552-569`） |
| 同函数后半 | 仅当 `cpu-supply` **与** `mem-supply` **同时存在**才 `regulator_count=2` + `dev_pm_opp_set_regulators`；**否则 `else { cluster->regulator_count = 1; }` 后 `return 0`**（`rockchip-cpufreq.c:615-632`） |

⇒ 上一版“缺 `mem-supply` 导致 `-ENOENT`”的说法错误：缺 `mem-supply` 只让
`regulator_count=1`，**不报错**。真正因缺 `cpu-supply` 而 `-ENOENT` 的是起手那处判定。
两点都指向同一结论：**去掉 `cpu-supply` 后 `rockchip_cpufreq_driver_init()` 放弃注册
cpufreq-dt**，但这只切断调压请求链路，**不构成“无调频”的完整证据**（见 §0.2 错误一）。

### 2.3 cpufreq-dt 侧的对应行为

| 位置 | 行为 |
|---|---|
| `find_supply_name()` | 无 `cpu0-supply`/`cpu-supply` → 返回 `NULL` → 不 `dev_pm_opp_set_regulators()`（`drivers/cpufreq/cpufreq-dt.c:76-107`） |

### 2.4 内核配置依赖（这次真正收口的地方）

| 事实 | 出处 |
|---|---|
| 基座 defconfig 开了 `CONFIG_CPU_FREQ=y` / `CPUFREQ_DT=y` / `ARM_ROCKCHIP_CPUFREQ=y` | `arch/arm/configs/luckfox_rv1106_linux_defconfig:28-32` |
| `ARM_ROCKCHIP_CPUFREQ` **依赖** `CPUFREQ_DT`（`depends on ARCH_ROCKCHIP && CPUFREQ_DT`） | `drivers/cpufreq/Kconfig.arm:161-167` |
| `CPUFREQ_DT` 的 `select CPUFREQ_DT_PLATDEV if !ARM_ROCKCHIP_CPUFREQ` | `drivers/cpufreq/Kconfig:247-251` |
| `CPU_FREQ_THERMAL` 在 `if CPU_THERMAL` 内且 `depends on CPU_FREQ`、`default y` | `drivers/thermal/Kconfig:170-179` |
| `ROCKCHIP_THERMAL` **不依赖** `CPU_FREQ`（`depends on ARCH_ROCKCHIP` 等） | `drivers/thermal/Kconfig:329-337` |

⇒ 关掉 `CONFIG_CPU_FREQ` 后，`CPUFREQ_DT` / `ARM_ROCKCHIP_CPUFREQ` / 各 governor /
`CPU_FREQ_THERMAL` 由 olddefconfig 自动置 n；`THERMAL` / `ROCKCHIP_THERMAL` 不受影响。

### 2.5 运行频率来源

关掉 cpufreq 后内核不再有 cpufreq 侧 `clk_set_rate(ARMCLK)` 换档通路。ARMCLK 的静态
运行值来自通用 `rv1106.dtsi` cru 节点的 `assigned-clock-rates`：

```
cru: clock-controller@ff3a0000 { ... assigned-clock-rates = ..., <1104000000>, ...; }   /* rv1106.dtsi:697-719 */
```

该表在 cru provider 初始化时由 `of_clk_set_defaults()`（`drivers/clk/clk-conf.c`）应用，
故**预期**运行 1.104GHz；须上板确认。本次未改 `assigned-clock-rates`。

---

## 3. 本次改动（仅 V015 专属文件）

### 3.1 `rv1106g-dw-tly-v015.dts`

在 `&fiq_debugger` 之后新增一段（功能性改动仅此一处，另附注释）：

```dts
&cpu0 {
	/delete-property/ operating-points-v2;
	/delete-property/ cpu-supply;
};

/delete-node/ &vdd_arm;
/delete-node/ &cpu0_opp_table;
```

删除依据（先查引用再删）：

- `&vdd_arm` 在**本板编译单元内**只有两处引用——定义
  (`rv1106-luckfox-pico-ultra-ipc.dtsi:160`) 与 `&cpu0` 的 `cpu-supply`(=222)；后者已随
  `cpu0` 覆写一并去掉，删节点不会留下悬空引用。它在 `ultra`/`ultra-spi-nand` 两个**其它
  板**的 dts 里仍被使用，但那些是独立编译单元，不受本板 dts 影响。
- `&cpu0_opp_table` 在 rv1106 系 tree 内只被 `rv1106.dtsi:108`（`cpu0`）引用；该引用已删。
  `decompiled DTB` 复核：全树无其它 `cpu-supply` / `cpu0-supply` 指向 `vdd_arm`。

### 3.2 `rv1106-v015.config`

在保留 `CONFIG_ROCKCHIP_GRF=y` 之后追加：

```
# CONFIG_CPU_FREQ is not set
# CONFIG_CPUFREQ_DT is not set
# CONFIG_ARM_ROCKCHIP_CPUFREQ is not set
```

并附理由注释（热保护保留、频率来源等，与 V020 fragment 同结构）。

---

## 4. 验证（全部为构建/静态验证，**无实板**）

### 4.1 命令与退出码

```
$ ./build.sh kernel
EXIT=0
日志：/tmp/v015-kernelbuild-20260930-cpufreq-off.log（1917 行）
```

关键构建事实（脱敏摘录，未输出 BoardConfig 内容）：

- `switch to DTS: .../rv1106g-dw-tly-v015.dts`
- `switch to kernel defconfig: .../luckfox_rv1106_linux_defconfig`
- `TARGET_ARCH=arm`
- `Running build_kernel succeeded.`
- 唯一 DTC 告警：`rv1106-luckfox-pico-ultra-ipc.dtsi:446 touchscreen I2C bus unit address
  format error, expected "14"`（与本次改动无关，预存）

### 4.2 最终 `.config`（验收项 ⑤）

`sysdrv/source/objs_kernel/.config`：

| 项 | 结果 |
|---|---|
| `CONFIG_CPU_FREQ` | **`# CONFIG_CPU_FREQ is not set`**（第 445 行） |
| `CONFIG_CPUFREQ_DT` / `CONFIG_ARM_ROCKCHIP_CPUFREQ` / 各 governor / `CPU_FREQ_THERMAL` | 文件中**完全不出现**（被 olddefconfig 自动移除，等价于 n） |
| `CONFIG_THERMAL=y` / `CONFIG_ROCKCHIP_THERMAL=y` / `CONFIG_CPU_THERMAL=y` | 保留（2122 / 2139 / 2135 行） |
| `CONFIG_ROCKCHIP_GRF=y` | 保留（4208 行） |
| `CONFIG_MMC=y` / `CONFIG_MMC_DW=y` / `CONFIG_MMC_DW_ROCKCHIP=y` | 保留（3659 / 3675 / 3681 行） |

### 4.3 vmlinux / System.map 符号（“无动态调频”的硬证据）

"无 cpufreq 子系统"这一结论由链接后镜像证明，而不靠“无 cpu-supply”推断：

| 检查 | 结果 |
|---|---|
| `nm vmlinux \| grep -c cpufreq` | **0** |
| `grep -cE "cpufreq_register_driver\|rockchip_cpufreq_driver_init\|cpufreq_dt_platdev_init" System.map` | **0** |
| `ar t drivers/built-in.a \| grep cpufreq` | 无成员 |
| 正向对照 `nm vmlinux \| grep -cE "rockchip_grf_init\|soc_thermal\|rockchip_thermal"` | 15（存在） |
| `vmlinux` / `System.map` / `vmlinux.o` mtime | 2026-09-30 19:40–19:41（本次构建） |

注：`drivers/cpufreq/` 目录下残留若干 **2026-09-29 的旧 `.o`**
（`cpufreq-dt.o`、`rockchip-cpufreq.o` 等）。它们是上一版构建的未清理产物，mtime 早于
本次构建，且**未**进入本次链接的 `drivers/built-in.a` 与 `vmlinux`；旁证是
`drivers/cpufreq/built-in.a` 亦停在 09-29。**这些残留不参与内核**，但读证据时勿据其
mtime 误判本次产物。它们位于 `objs_kernel/`（构建目录，不入 Git）。

### 4.4 构建 DTB 复核（验收项 ⑥）

`dtc -I dtb -O dts` 展开后（`/tmp/v015-final.dts`），全文件 token 计数：

| token | 出现次数 |
|---|---|
| `cpu-supply` | **0** |
| `operating-points-v2` | **0** |
| `cpu0-opp-table` / `cpu0_opp_table` | **0** |
| `vdd_arm` / `vdd-arm` | **0** |

`cpu@0` 节点（修复后）：

```
cpu@0 {
    device_type = "cpu";
    compatible = "arm,cortex-a7";
    reg = <0x00>;
    clocks = <0x02 0x05>;   /* ARMCLK */
    phandle = <0x03>;
};                          /* 无 operating-points-v2、无 cpu-supply */
```

全树**无任何** `cpu-supply` / `cpu0-supply` 指向已删除的 regulator；`aliases` 中无
`vdd-arm` 别名（`vdd_arm` 从未出现在 aliases）。DTB 三份副本 SHA-256 一致
（`objs_kernel` / `sysdrv/out/bin` / `output/out/sysdrv_out` 均为
`e3b00deb653ccdcfaf6cd689c1d3b31be9a7612bd6c7307c30739a790b98f99a`）。

### 4.5 未回归项复核（同一构建 DTB，验收项 ③）

| 项目 | 结果 |
|---|---|
| `mmc@ffa90000`（eMMC） | `status="okay"`, `bus-width=<0x08>`, `non-removable`, `no-sdio`, `no-sd`, `vmmc-supply`/`vqmmc-supply` 同源, `rockchip,default-sample-phase=<0x5a>`, `pinctrl-0` 三项——不变 |
| `mmc@ffaa0000`（Wi-Fi SDIO0） | `status="okay"`, `bus-width=<0x04>`, `non-removable`, `supports-sdio`, `mmc-pwrseq`, `max-frequency=<0x2faf080>`——不变 |
| `soc-thermal` | `polling-delay=0x3e8`、`sustainable-power=0x834`、`soc-crit` 仍在；`aliases` 中 `soc_thermal`/`soc_crit` 指向不变 |
| tsadc | `rockchip,hw-tshut-temp=0x1d4c0`(120℃)、`hw-tshut-mode=0`(CRU) 仍在 |

### 4.6 Git 状态（验收项 ⑦）

```
$ git diff --check      # 退出码 0，无输出
$ git status --short --branch
## codex/dw-012-v015-emmc-adaptation
 M sysdrv/source/kernel/arch/arm/boot/dts/rv1106g-dw-tly-v015.dts
 M sysdrv/source/kernel/arch/arm/configs/rv1106-v015.config
?? aidlc-docs/evidence/2026-09-30-v015-cpu-fixed-rail-no-dvfs.md
```

`allsave` 未运行，无受版本控制的构建产物污染。**未提交、未 push。**

---

## 5. 关键决定与理由

1. **与 V020 做法一致的完整撤销**：V020 在 dtsi 里删 `operating-points-v2`/`cpu-supply`
   与 `cpu0-opp-table`、删 `vdd_arm`，并在 `rv1106-v020.config` 关 `CONFIG_CPU_FREQ`。
   V015 复刻同一组合（因共享 dtsi 被多板引用，删除动作放在 V015 板级 dts 内）。
2. **为何同时删 `operating-points-v2` 而不保留**：OPP 表绑定在 `cpu0` 上就是 cpufreq/OPP
   的“可调压换档”模型入口；本板不做 DVFS，保留它只会让任何残留路径对固定轨发无效
   调压请求。thermal cooling 的实际权衡见 §6.3。
3. **为何必须动 `.config`**：仅 DTS 层面的属性删除**不能**证明 cpufreq 子系统不存在——
   这是上一版被拒的根因。关 `CONFIG_CPU_FREQ` 才能让 `cpufreq` 不编入内核，使“从 cpufreq
   路径调 CPU 时钟 / 向 regulator 请求电压”在内核里无代码可走。**本条只论证到 cpufreq 子系统
   不在内核这一层，不代表“任何路径都无法改 CPU 时钟”**——其它时钟驱动路径（非 cpufreq）是否
   会改 ARMCLK 不在本证据范围内，未作核查。
4. **删除范围限于本板编译单元**：`vdd_arm` / `cpu0_opp_table` 的定义在共享文件里，本次
   一律用板级 `/delete-node/` 覆写，不改共享 dtsi、不影响 `ultra`/`ultra-spi-nand`。

---

## 6. 限制与未决项（**须上板复核，勿当作已通过**）

1. **无 V015 实板**：结论依据网表（设计证据）与源码/构建静态证据，缺实机验证。上板后请：
   - 外部万用表/示波器测 VDD_0V9（U57 输出或 U2 供电脚），核对该轨实际电压；
   - `cat /sys/devices/system/cpu/cpufreq/policy0/...` 应**不存在**（cpufreq 未编入）；
   - `dmesg` 应无 cpufreq 相关注册/报错。
2. **开机频点未实测**：预期 1.104GHz（来自 `rv1106.dtsi` cru 的 `assigned-clock-rates`，
   见 §2.5）。若实测 1.104GHz @ 0.9V 不稳，应在板级 dts 覆写 `&cru` 的
   `assigned-clock-rates` 降频，而不是改通用 dtsi；该决定须实测，不在本次。
3. **thermal cooling 取舍（主动变更）**：本次删掉 `operating-points-v2` 并关
   `CONFIG_CPU_FREQ` 后，**不再有 cpufreq cooling device**，CPU 降温不再经由降频实现。
   温度保护改由：tsadc 硬件 tshut（120℃，CRU 复位）+ `soc-thermal` critical trip
   （115℃，thermal core 直接 orderly_poweroff）。这是**为满足“本板无动态调频”而主动
   接受的设计取舍**，与 V020 一致；其上板行为（尤其重载下的温度曲线）须实测确认。
   `CONFIG_THERMAL` / `ROCKCHIP_THERMAL` / `CONFIG_CPU_THERMAL` 均保留 =y。
4. **构建残留**：`objs_kernel/drivers/cpufreq/*.o` 为 09-29 旧物（见 §4.3 注），本次未清理、
   也未参与链接；如需彻底干净可另行 `make clean`（本次未做，避免超出范围与扰动）。
5. **网表来源版本**：用户提供的 V015 2026-09-29 网表，与既有证据 `SRC-HW-ENET-20260929`
   同源。网表失真/改线风险按既有规则处理。

---

## 7. 未改动确认

- 通用 `rv1106.dtsi`、`rv1106-luckfox-pico-ultra-ipc.dtsi`：**未改**。
- V020 工作树 / `rv1106-dw-tly-v020-ipc.dtsi` / `rv1106-v020.config`：**未触碰**。
- BoardConfig、充电参数、硬件未签核项：**未触碰**。
- 本次**未提交**、**未 push**、**未烧录**、**未访问设备**、**未运行 allsave**。
