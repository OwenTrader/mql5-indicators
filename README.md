# MySystem 交易系统骨架 · 使用说明

一套「主指标 + .mqh 模块库」的 MQL5 工程模板。
源码层面拆分，产品层面聚合：**编译后只有一个 .ex5，图上只挂一个指标。**

```
mql5_skeleton/
├── MySystem.mq5        ← 主指标：参数汇总、信号合成、绘图（编译这个文件）
├── Modules/
│   ├── MacdTrend.mqh   ← 模块1：趋势模块（标准三线 MACD：DIF/DEA/柱）
│   ├── OscSignal.mqh   ← 模块2：震荡触发模块（Stoch超买超卖穿越）
│   ├── Countdown.mqh   ← 模块3：K线倒计时模块（剩余时间+实时价格）
│   ├── GridLines.mqh   ← 模块4：网格线模块（整数位/四分位/中位/八分位+标签+预警）
│   └── BigCandles.mqh  ← 模块5：K线着色模块（大实体/大影线6色分类+ATR自适应）
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
| 系统设置 | InpMode | MODE_FILTER=震荡触发+趋势过滤（默认）；MODE_ANY=任一触发（测试用）；MODE_MACD=MACD三线金叉/死叉直接触发 |
| 系统设置 | InpOnlyClosed | true=只在K线收盘后出信号（**防重绘**，回测/实盘建议保持true） |
| 模块1 趋势(MACD三线) | Fast/Slow/Signal/Price/HistMult | 快线EMA、慢线EMA、信号线DEA(EMA平滑)、应用价格、柱放大倍数(默认2) |
| 模块2 震荡 | K/D/Slowing/阈值 | Stochastic参数与超买超卖阈值 |
| 模块3 倒计时 | Enabled/FontSize/Color/X/Y/ShowPrice/Separator | 是否启用、字体、偏移、实时价格开关、分隔符（由 timer.mq5 提炼） |
| 模块4 网格线 | Enabled/AutoDetect/Interval/NumLines/各类型线型/预警 | 网格间隔自动检测、每类线颜色线型、触及预警（由 line.mq5 提炼，对象前缀 MSGL_） |
| 模块5 K线着色 | Enabled/六色/ATR或各周期点数阈值/影线/预警 | 6色K线分类、ATR自适应阈值（由 candle.mq5 提炼，plot0=DRAW_COLOR_CANDLES） |

调好一组参数后：图表右键 → 指标列表 → 保存为 **.set 预设文件**，之后一键切换。

---

## 三、如何接入你自己的逻辑（三个扩展点）

### 1) 替换模块内部逻辑（最常用）
打开对应 .mqh，找到标注 `扩展点` 的位置重写判断即可：
- 趋势类逻辑 → `Modules/MacdTrend.mqh`：`TrendState()` 返回 +1 多 / -1 空 / 0 未定（看柱的正负）；
  `CrossSignal()` 返回 +1 金叉 / -1 死叉 / 0 无（看 DIF 与 DEA 的穿越）
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

## 六、模块1：三线 MACD 口径说明（重要）

本模块**不使用** MT5 内置 `iMACD`，三条线全部自算，与 MT5 默认 MACD 有本质区别：

| | MT5 内置 MACD（`iMACD` / `Examples\MACD.mq5`） | 本模块（标准三线） |
|---|---|---|
| DIF | `EMA(fast) − EMA(slow)` | 同 |
| 信号线 | **`SMA(DIF, signal)`** | **`EMA(DIF, signal)` = DEA** |
| 柱 | 无标准柱，绘图把 **DIF 本身**画成柱 | **`(DIF − DEA) × 倍数`** |
| 金叉 | DIF 上穿 `SMA(DIF,9)` | DIF 上穿 DEA（柱由负转正） |

> 因信号线平滑口径不同（**EMA vs SMA**），两者的金叉/死叉在**时点与价位上都不同**，
> 不要把本模块的信号与 MT5 自带 MACD 指标窗口的交叉点对照，会不一致。

---

## 七、信号逻辑速览

- **MODE_FILTER**（默认）：MACD 多头（DIF > DEA）且 K线上穿超卖区 → 买；反之 → 卖
- **MODE_MACD**：MACD 三线金叉（DIF 上穿 DEA）→ 买；死叉（DIF 下穿 DEA）→ 卖
- **MODE_ANY**：仅看 Stoch 触发（测试用）
- 信号画在触发bar上：绿色↑ = Buy，红色↓ = Sell

> 示例规则仅演示架构，请替换成你自己的系统逻辑后再评估使用。
> 模块1 原为双均线（`Modules/TrendMA.mqh`，已不再引用，可保留作参考或删除）。
