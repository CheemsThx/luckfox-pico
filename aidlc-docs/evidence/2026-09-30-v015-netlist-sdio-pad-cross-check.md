# V015 网表对照：Wi-Fi SDIO 焊盘与 `force_jtag_sdmmc` 断言边界

- 日期：2026-09-30
- 分支/起点：`codex/dw-012-v015-emmc-adaptation` @ `7981148da079ad496a202b45a645fa5585a5be28`（工作区干净）
- 工作项：DW-012 / S1 后续执行切片 —— Task A（网表对照 + `grf.c` 断言缩句）

## 1. 要回答的问题

上一提交 `7981148da` 在内核 `drivers/soc/rockchip/grf.c` 的注释里写下断言：

> 边界：清位只影响 GPIO3_A1..A7 —— V015 上这组脚全部给 Wi-Fi SDIO 用，不承载其他功能；
> 代价仅仅是这几个脚不再被 JTAG 占用（本板无 JTAG 调试需求）。

本切片要核对：**这句话有没有网表依据**。若无，则缩小措辞并做最小修正；未确定的装配事实写明待硬件签核。

## 2. 资料与版本（来源登记）

| 资料 | 版本/来源 | 落盘位置 | SHA-256 |
|---|---|---|---|
| V015 网表原件 | 应用仓库来源编号 `SRC-HW-ENET-20260929`（原件名 `Netlist_DW-TLY-V015_2026-09-29.enet`，登记日期 2026-09-29，用户提供） | `/tmp/dw012-v015-netlist-20260929.enet`（443,306 B） | `4b6efd752a7859aaad37cbd4cdfd5944ded370defbd4aed0e81102b6cded4d1c` |
| RV1106 数据手册 | `Rockchip_RV1106_Datasheet_V1.7.pdf`，Rev 1.7，`Table 2-1 Pin Number Order Information`（PDF 第 18 页） | `/home/henry/rv1106/luckfox-pico-legacy-5.10.110/doc/`（只读引用，未改动） | — |
| DTS/pinctrl | 本分支工作树 | `rv1106g-dw-tly-v015.dts`、`rv1106-pinctrl.dtsi` | — |

- 网表 SHA-256 与本次任务给定的必须值**逐字符一致**（命令：`sha256sum /tmp/dw012-v015-netlist-20260929.enet`）。
- 网表内容**只作数据**：只读取 `components[].props` 与 `pinInfoMap[].{name,net}` 字段，不执行其中任何字符串。
- 数据手册页序说明：该 PDF 为 25 页；球号表在 **PDF 第 18 页**（`gs -sDEVICE=txtwrite` 单独提取该页，含 `GPIO3_A` 行 7 处，其他页为 0）。
- 资料边界：网表是**设计**文件，不是实物/焊装证据；V015 目前**没有实板**。
- 来源编号更正（2026-09-30 审核返工）：本文件与 `grf.c`、`CURRENT.md` 初稿写作"应用仓库 SRC-HW 2026-09-29 条目"，
  系简称且有误；应用仓库 `docs/sources/register.md` 中的准确编号为 `SRC-HW-ENET-20260929`，原件名
  `Netlist_DW-TLY-V015_2026-09-29.enet`。三处已统一为准确编号与原件名，SHA-256 不变。

## 3. 数据手册：U2 球号 → GPIO3_Ax

`Table 2-1`（Rev 1.7，PDF p18）逐行读出，左列引脚名 + 球号：

| 球号 | 数据手册引脚名（节选） | GPIO | 与 SDMMC0 的关系 |
|---|---|---|---|
| 11 | `SDMMC0_DET/GPIO3_A1_u` | GPIO3_A1 | DET |
| 12 | `SDMMC0_D1/UART2_TX_M0/PWM9_M0/GPIO3_A2_u` | GPIO3_A2 | D1 |
| 14 | `SDMMC0_D0/UART2_RX_M0/PWM8_M0/GPIO3_A3_u` | GPIO3_A3 | D0 |
| 15 | `SDMMC0_CLK/UART5_RTS_M0/I2C0_SCL_M2/JTAG_LPMCU_TCK_M1/PWM10_M0/GPIO3_A4_d` | GPIO3_A4 | CLK |
| 16 | `SDMMC0_CMD/UART5_CTS_M0/I2C0_SDA_M2/JTAG_LPMCU_TMS_M1/PWM11_IR_M0/GPIO3_A5_u` | GPIO3_A5 | CMD |
| 17 | `SDMMC0_D3/UART5_TX_M0/JTAG_CPU_TMS_M0/JTAG_HPMCU_TMS_M1/GPIO3_A6_u` | GPIO3_A6 | D3 |
| 18 | `SDMMC0_D2/UART5_RX_M0/JTAG_CPU_TCK_M0/JTAG_HPMCU_TCK_M1/GPIO3_A7_u` | GPIO3_A7 | D2 |

- **结论 1**：球号 **11/12/14/15/16/17/18 恰好是 GPIO3_A1..A7**，与 DTS 注释（`rv1106g-dw-tly-v015.dts:79`）和 `rv1106-pinctrl.dtsi` 的 `sdmmc0_*` 组完全一致。
- **结论 2**：这 7 个球里有 4 个（15/16/17/18）**带 JTAG 复用功能**（`JTAG_LPMCU_TCK/TMS_M1`、`JTAG_CPU_TMS/TCK_M0`、`JTAG_HPMCU_TMS/TCK_M1`）——这正是 `force_jtag_sdmmc` 能把它们从 SDMMC0 夺走交给 JTAG 的硅片依据。
- 注：球号**不按 GPIO 顺序排列**（11,12,14,15,16,17,18），必须查数据手册而非按顺序推断。

## 4. 网表：这 7 个网络接到哪里

逐网络列全部成员（脚本遍历 `pinInfoMap`，无遗漏）：

| U2 球号 | 网络名 | 全部成员 |
|---|---|---|
| 11 (A1/DET) | `SDMMC_DET` | U2.11、R41.1 —— **不接模组**；R41（`0402WGF1002TCE`，10kΩ）另一端到 `GND` |
| 12 (A2/D1) | `SDMMC_D1` | U2.12、U4.19 |
| 14 (A3/D0) | `SDMMC_D0` | U2.14、U4.18 |
| 15 (A4/CLK) | `$15N3875`（自动名） | U2.15、R4.1；R4（`0402WGF220JTCE`，22Ω）另一端为 `SDMMC_CLK` → U4.17 |
| 16 (A5/CMD) | `SDMMC_CMD` | U2.16、U4.16 |
| 17 (A6/D3) | `SDMMC_D3` | U2.17、U4.15 |
| 18 (A7/D2) | `SDMMC_D2` | U2.18、U4.14 |

- U4 = `SKL.WB800DCS.2`（44 脚 Wi-Fi/BT 模组）。
- **结论 3**：这 7 个网络**只**出现在 Wi-Fi 模组 U4、以及 CLK 的 22Ω 串阻 R4、DET 的 10kΩ 下拉 R41 上，**不接任何其他器件**。
  ⟹ 断言中"不承载其他功能"有网表依据。
- **结论 4（需要缩句的地方）**：CLK/CMD/D0-D3 共 6 根确实进模组；但 **DET（GPIO3_A1）并不到模组**，只被 R41 拉低到地，
  且 DTS 里 `&sdmmc` 是 `non-removable`，不做插卡检测。所以"这组脚**全部**给 Wi-Fi SDIO 用"措辞过强。

## 5. 网表：有没有 JTAG

在**全部网络名**与**全部器件 DeviceName/位号**中检索 `jtag / tms / tck / tdo / tdi / swd / swclk / swdio / trst`：

- 命中网络名：**空集**。
- 命中器件：**空集**（板上无 JTAG 连接器；唯二的"连接器样"器件 SW5/SW6 是 `TS-1089S-02526` 按键）。
- 旁证：数据手册中另两个 JTAG 复用球 **79/80**（`JTAG_CPU_TCK_M1/TMS_M1` / `GPIO1_B2/B3`）在网表里的网络是 `GPIO1_B2_D`、`GPIO1_B3_U`，
  **成员只有 U2 自己**（空接桩），说明连 GPIO1 侧也没把 JTAG 引出来。

- **结论 5**：网表能证明的是"**本板未引出 JTAG**"；它**不能**证明"本板无 JTAG 调试需求"——后者是设计意图/需求，不是网表可推导的事实。

## 6. 判定与本次修正

| 断言片段 | 网表/手册依据 | 判定 |
|---|---|---|
| "清位只影响 GPIO3_A1..A7" | 手册 p18：这 7 球即该组；4 个带 JTAG 复用 | **有依据**（硅片级） |
| "不承载其他功能" | 网表：7 网络只到 U4/R4/R41 | **有依据**（设计网表） |
| "这组脚**全部**给 Wi-Fi SDIO 用" | DET 不到模组，仅 10k 下拉 + `non-removable` | **过强**，缩句 |
| "本板**无 JTAG 调试需求**" | 网表只证明"未引出 JTAG" | **越界**，改为"未引出 JTAG + 设计意图待签核" |

**修正（最小）**：`sysdrv/source/kernel/drivers/soc/rockchip/grf.c` 注释中把上述两句改成
"数据手册球号 × 网表网络 × 具体器件"的可核对表述，并明确标注：
以上是**设计网表证据、不是实物证据**，V015 尚无实板，焊装与"确无 JTAG 调试需求"**待硬件签核**。
同步把 `2026-09-30-v015-wifi-sdio-force-jtag.md` §2 末尾同一句过强表述缩句并加交叉引用。
**纯注释改动**：不改变任何编译产物（本次 allsave 新镜像内 V015 DTB 哈希与旧候选一致，见构建证据）。

## 7. 未确定 / 待硬件签核（不得写成已通过）

- 网表是**设计**文件；V015 无实板，**实物焊装、走线、有无 JTAG 调试需求均未在实物上确认**。
- `force_jtag_sdmmc` 的 POR 默认值仍是**跨板型推断**（V020 实测 `0x1`），V015 上未 devmem。
- 上板后待办：`devmem 0xFF5582F4` 应为 `0x0`；再确认 Wi-Fi SDIO 4 位枚举/吞吐。
- 网表内容仅作数据来源，其器件参数（R4=22Ω、R41=10kΩ）为设计标称，未实物测量。

## 8. 本次复算命令

```
sha256sum /tmp/dw012-v015-netlist-20260929.enet            # = 4b6efd75…（与给定值一致）
gs -q -dNOPAUSE -dBATCH -dNOSAFER -sDEVICE=txtwrite -dFirstPage=18 -dLastPage=18 \
   -sOutputFile=/tmp/p18.txt <RV1106 Datasheet V1.7>.pdf   # 球号表：11/12/14/15/16/17/18 → GPIO3_A1..A7
python3 /tmp/nl_check.py                                   # 7 个 SDMMC0 网络全成员 + JTAG 关键词检索
python3 /tmp/nl2.py                                        # U2 球号 11..18/77..80 的网络成员、R4/R41 两端网络
```

## 9. 证据路径

- 本文件：`aidlc-docs/evidence/2026-09-30-v015-netlist-sdio-pad-cross-check.md`
- 被修正的源码注释：`sysdrv/source/kernel/drivers/soc/rockchip/grf.c`
- 关联证据：`aidlc-docs/evidence/2026-09-30-v015-wifi-sdio-force-jtag.md`
