# MySystem 交易系统骨架 · 使用说明

一套「主指标 + .mqh 模块库」的 MQL5 工程模板。
源码层面拆分，产品层面聚合：**编译后只有一个 .ex5，图上只挂一个指标。**

```
mql5_skeleton/
├── MySystem.mq5        ← 主指标：参数汇总、信号合成、绘图（编译这个文件）
├── Modules/
│   ├── MacdTrend.mqh   ← 模块1：趋势模块（MACD 二线交叉，iMACD 口径，同 2linemacd）
│   ├── RsiFilter.mqh   ← 模块1b：RSI 方向过滤器（可选，顺势确认）
│   ├── OscSignal.mqh   ← 模块2：震荡触发模块（Stoch超买超卖穿越）
│   ├── Countdown.mqh   ← 模块3：K线倒计时模块（剩余时间+实时价格）
│   ├── GridLines.mqh   ← 模块4：网格线模块（整数位/四分位/中位/八分位+标签+预警）
│   ├── BigCandles.mqh  ← 模块5：K线着色模块（大实体/大影线6色分类+ATR自适应；默认不绘制普通K线）
│   └── TrendMA.mqh     ← 模块6：双均线趋势（可选，**默认关闭**；参数组排在设置页最底部）
└── README.md
```

---

## 一、安装（3步）

1. 把整个 `mql5_skeleton` 文件夹复制到 MT5 数据目录下：
   `文件 → 打开数据文件夹 → MQL5 → Indicators\`（可重命名为 MySystem）
2. MetaEditor 打开 `MySystem.mq5`，按 **F7** 编译（0 errors 即成功，.mqh 会被自动打进 .ex5）
3. 回到 MT5，导航器 → 技术指标 → 刷新，把 **MySystem** 拖到图表

> 注意：文件夹/文件名建议保持英文，避免个别版本 MetaEditor 中文路径编译异常。

---

## 二、参数说明

参数按 `input group` 分组收纳，主面板一目了然：

| 分组 | 参数 | 说明 |
|---|---|---|
| 系统设置 | InpMode | **MODE_MACD=MACD二线交叉（默认，主信号）**；MODE_FILTER=Stoch触发+MACD方向过滤；MODE_MOMENTUM=柱动量耗尽确认（加速→减速→反向穿越）；MODE_ANY=仅震荡触发（测试用） |
| 系统设置 | InpOnlyClosed | true=只在K线收盘后出信号（**防重绘**，回测/实盘建议保持true） |
| 模块1 MACD二线 | Fast/Slow/Signal/Price/HistMult | 快线EMA、慢线EMA、信号线DEA(SMA平滑，同iMACD)、应用价格、柱放大倍数(默认1=与2linemacd柱值一致) |
| 模块1b MACD动量 | RunLen/DecelMin/Lookback | 加速段最少连续柱数(6)、减速段最少连续柱数(1)、结构最大回看柱数(50)；仅 MODE_MOMENTUM 生效 |
| 模块1b RSI过滤 | UseRSI/RSIPeriod/RSILevel | 是否叠加 RSI 顺势过滤(默认**关**)、周期(14)、多空分界(50) |
| 模块2 震荡 | K/D/Slowing/阈值 | Stochastic参数与超买超卖阈值 |
| 模块3 倒计时 | Enabled/FontSize/Color/X/Y/ShowPrice/Separator | 是否启用、字体、偏移、实时价格开关、分隔符（由 timer.mq5 提炼） |
| 模块4 网格线 | Enabled/AutoDetect/Interval/NumLines/各类型线型/预警 | 网格间隔自动检测、每类线颜色线型、触及预警（由 line.mq5 提炼，对象前缀 MSGL_）；四类线条默认全开（整数/四分位/中位/**八分位**） |
| 模块5 K线着色 | Enabled/**HideNormal**/六色/ATR或各周期点数阈值/影线/预警 | 6色K线分类、ATR自适应阈值（由 candle.mq5 提炼，plot0=DRAW_COLOR_CANDLES）。**HideNormal 默认开启 = 不绘制普通K线**，仅高亮特殊K线，普通K线交由图表原生绘制 |
| 模块6 双均线 | Enabled/Fast/Slow/Method/Price | **可选模块，默认关闭（InpMaEnabled=false，关闭时不创建句柄、零开销）**；启用后作为方向过滤：任何模式产出的信号都必须与双均线方向一致，否则丢弃。参数组按约定排在设置页**最底部** |

调好一组参数后：图表右键 → 指标列表 → 保存为 **.set 预设文件**，之后一键切换。

> **模块5「不绘制普通K线」**（`InpCdlHideNormal`，**默认开启**）：
> 普通阳/阴线不再由本指标绘制，**图表原生K线直接透出**；本指标只覆盖显示**特殊K线**（大实体、大影线）。
> 实现方式是把该类 bar 的 O/H/L/C 缓冲置为 `PLOT_EMPTY_VALUE`（终端对空值**不绘制、也不参与自动缩放**）。
> 好处：消除「指标K线与原生K线两层叠色」的发虚观感，图面更干净，且原生K线外观完全由图表模板控制。
> 关闭该项则退回原行为（6 色全量绘制，含普通K线）。

> **网格线样式生效时机**：线条的「颜色/线型/线宽」在对象创建时写入，并在**每次指标重新初始化**（改参数、重编译、重挂指标、重开终端）后的首轮同步中对已存在对象**重套一遍**。
> 之所以需要重套：网格对象会被 .chr 随图表持久化，重启后被 `SyncGrid` 判定为「已存在」而不再重建；
> 若此时只更新标签位置、不重写样式，旧样式会一直留在图上（表现为「改了四分位线设置没反应」）。
> 正常使用无需关心这条，改完参数即生效。

---

## 三、如何接入你自己的逻辑（三个扩展点）

### 1) 替换模块内部逻辑（最常用）
打开对应 .mqh，找到标注 `扩展点` 的位置重写判断即可：
- 趋势类逻辑 → `Modules/MacdTrend.mqh`：`TrendState()` 返回 +1 多 / -1 空 / 0 未定（看柱的正负）；
  `CrossSignal()` 返回 +1 金叉 / -1 死叉 / 0 无（看 DIF 与 DEA 的穿越）；
  `HistColor()` 返回柱的 4 色状态；`MomentumCross()` 返回动量耗尽型交叉
- 过滤类逻辑 → `Modules/RsiFilter.mqh` 的 `State()`，返回 +1 放行做多 / -1 放行做空 / 0 未就绪
- 触发类逻辑 → `Modules/OscSignal.mqh` 的 `Signal()`，返回 +1 买 / -1 卖 / 0 无

### 2) 新增一个模块（三步）
1. 复制一份 .mqh 改名（如 `Modules/VolumeFilter.mqh`），照抄类结构
2. 主指标加：`#include "Modules\VolumeFilter.mqh"` + 参数组 + `OnInit` 里 `Create`
3. `OnCalculate` 的信号合成段调用它，参与 buy/sell 判断

### 3) 改信号合成规则
`MySystem.mq5` 的 `OnCalculate` 中标注 `信号合成` 的 switch 段——
你的交易规则（投票、串联过滤、仓位条件……）就写在这里。

---

## 四、需要独立画线的子指标？用 iCustom

如果某个逻辑既要独立显示、又想被主系统调用，把它写成独立指标后：

```mql5
// 主指标内部调用，子指标【不需要】手动挂到图表
int h = iCustom(_Symbol, _Period, "MyFolder\\MySubInd", 参数1, 参数2);
double v[];
CopyBuffer(h, 0, start, 2, v);   // v[0]=index-1, v[1]=index（旧→新）
```

要求：子指标在 `MQL5\Indicators\` 正确目录下且已编译；参数按声明顺序传。

---

## 五、以后升级成 EA

- **方案A（推荐）**：同一套 `.mqh` 模块直接被 EA `#include`，逻辑零改动，EA 自己管理下单
- **方案B**：EA 用 `iCustom` 读本指标的缓冲区：buffer 0 = Buy箭头价、buffer 1 = Sell箭头价，
  读「上一根已收盘bar」的值判断信号即可

---

## 六、模块1：MACD 二线交叉口径（重要）

本模块**直接引用 MT5 内置 `iMACD` 的两条缓冲**，不做任何自算，口径与
`2linemacd.mq5`（= MT5 自带 MACD 窗口）**逐点一致**：

| | 本模块（= `iMACD` = `2linemacd`） |
|---|---|
| DIF | `iMACD` buffer 0 = `EMA(fast) − EMA(slow)` |
| 信号线 DEA | `iMACD` buffer 1 = **`SMA(DIF, signal)`** |
| 柱 | `(DIF − DEA) × 倍数`，倍数默认 **1.0**（与 2linemacd 的柱值一致） |
| 金叉 | DIF 上穿 DEA（`DIF−DEA` 由 ≤0 变 >0） |
| 死叉 | DIF 下穿 DEA（`DIF−DEA` 由 ≥0 变 <0） |

> **与「标准三线 MACD」的区别**：标准三线的信号线是 `EMA(DIF,9)`，本模块（按使用者要求）用 `SMA(DIF,9)`。
> 因信号线平滑口径不同（**SMA vs EMA**），两者的金叉/死叉在**时点与价位上都不同**。
> 本工程信号一律以 iMACD 口径为准；若日后要切回标准三线，只需改 `MacdTrend.mqh` 里取 DEA 的那一步
> （对 DIF 做 EMA 而非取 `iMACD` buffer 1），DIF 不变。

### 6.1 柱状态（4色）与动量耗尽信号

模块把柱按「符号 + 相对前一根增/减」分为 4 态（`HistColor()`，参考 MACD_Color_EA 的彩色柱语义）：

| 柱值 | 相对前值 | 状态 | 含义 |
|---|---|---|---|
| 柱 > 0 | 放大 | 红 | 多头动能增强 |
| 柱 > 0 | 缩小 | 粉 | 多头动能衰减 |
| 柱 < 0 | 放大（更负） | 绿 | 空头动能增强 |
| 柱 < 0 | 缩小（趋零） | 浅绿 | 空头动能衰减 |

`MomentumCross(runLen, decelMin, lookback)` 在此基础上判定动量耗尽型反转：

```
加速段（连续 runLen 根 红/绿） → 减速段（连续 decelMin 根 粉/浅绿） → 反向穿越
```

即**只在柱的峰/谷处才认金叉/死叉**，过滤掉「柱刚出现一个小凹坑就反向穿越」的假信号。

> 修正说明：参考策略 `MACD_Color_EA` 的信号线句柄写作 `iMA(..., SignalEMA, MODE_EMA, PRICE_CLOSE)`，
> 是对**收盘价**做 EMA 而非对 DIF 做 EMA，得到的并不是 DEA，柱的口径随之失真（柱近似恒为负、随价格漂移）。
> 本模块的 DIF/DEA 按上表口径取自 `iMACD`，仅借鉴其「柱变色 + 动能耗尽」的思路。

---

## 七、信号逻辑速览

- **MODE_MACD**（**默认，主信号**）：MACD 二线交叉 —— DIF 上穿 DEA → 买；DIF 下穿 DEA → 卖。
  与 `2linemacd` 副图上的两条线交叉点**逐一重合**。
- **MODE_FILTER**：震荡触发 + MACD方向过滤 —— K线上穿超卖区且 DIF > DEA → 买；K线下穿超买区且 DIF < DEA → 卖
- **MODE_MOMENTUM**：`MomentumCross()` 成立 → 买/卖（默认 加速6根 / 减速1根 / 回看50根）；
  勾选 `InpMacdUseRSI` 时叠加顺势过滤：做多要求 RSI ≥ 50，做空要求 RSI < 50（默认关闭）
- **MODE_ANY**：仅看 Stoch 触发（测试用）
- **模块6 双均线**（默认关闭）：勾选 `InpMaEnabled` 后叠加方向过滤 —— 最终信号必须与双均线方向一致，否则丢弃
- 信号画在触发bar上：绿色↑ = Buy，红色↓ = Sell

> **箭头落在哪根 bar**：`InpOnlyClosed=true`（默认）时只在 K 线**收盘后**判定，
> 因此箭头画在「交叉确认的那根已收盘 bar」上，与副图的交叉点逐根对应，且不重绘。
> 设为 false 则盘中实时判定，信号会随未收盘 bar 跳动（重绘）。
>
> 示例规则仅演示架构，请替换成你自己的系统逻辑后再评估使用。
