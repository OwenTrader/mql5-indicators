# MySystem 交易系统骨架 · 使用说明

一套「主指标 + .mqh 模块库」的 MQL5 工程模板。
源码层面拆分，产品层面聚合：**编译后只有一个 .ex5，图上只挂一个指标。**

```
mql5_skeleton/
├── MySystem.mq5        ← 主指标：参数汇总、信号合成、绘图（编译这个文件）
├── Modules/            ← 顺序 = 设置页分组顺序（默认启用的三个在最前）
│   ├── GridLines.mqh   ← 模块1：网格线（整数位/四分位/中位/八分位+标签+预警）｜默认开
│   ├── PriceLines.mqh  ← 模块2：价格折线（最高/最低/开盘，可独立开关）｜默认开
│   ├── Countdown.mqh   ← 模块3：K线倒计时（剩余时间+实时价格）｜默认开
│   ├── MacdTrend.mqh   ← 模块4：MACD 二线交叉（iMACD 口径，同 2linemacd）｜默认关
│   ├── RsiFilter.mqh   ← 模块4b：RSI 方向过滤（可选，顺势确认）｜默认关
│   ├── OscSignal.mqh   ← 模块5：震荡触发（Stoch 超买超卖穿越）｜默认关
│   ├── BigCandles.mqh  ← 模块6：K线着色（大实体/大影线 6 色 + ATR 自适应）｜默认关
│   ├── TrendMA.mqh     ← 模块7：双均线（13/30 EMA，画线 + 方向过滤）｜默认开
│   └── PatternSig.mqh  ← 模块8：形态识别（涨-回调-涨 / 跌-反弹-跌）｜默认关
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
| 模块1 网格线 | Enabled/AutoDetect/Interval/NumLines/各类型线型/预警 | 网格间隔自动检测、每类线颜色线型、触及预警（由 line.mq5 提炼，对象前缀 MSGL_）；**默认开启：整数位(实线) / 四分位(点线 dot) / 中位(实线)，八分位默认关闭**（v1.39 起，需要时勾选，线型默认 dash）。自动检测见下方说明 |
| 模块2 价格折线 | Enabled/ShowHigh/ShowLow/ShowOpen/各线颜色线型线宽 | 用**最高价/最低价/开盘价**各画一条折线（随价格序列逐bar连线），**三条线可独立开关**（**High/Low 默认开，Open 默认关**）。实现：指标缓冲区 + `DRAW_LINE`（plot3=High / plot4=Low / plot5=Open）；关闭的线在 `OnInit` 里把对应 plot 设为 `DRAW_NONE`，完全不绘制 |
| 模块3 倒计时 | Enabled/FontSize/Color/X/Y/ShowPrice/Separator | 是否启用、字体、偏移、实时价格开关、分隔符（由 timer.mq5 提炼） |
| 模块4 MACD二线 | **Enabled**/Fast/Slow/Signal/Price/HistMult | **独立开关（v1.38 起默认关闭）**；快线EMA、慢线EMA、信号线DEA(SMA平滑，同iMACD)、应用价格、柱放大倍数(默认1=与2linemacd柱值一致)。关闭时不创建句柄（零开销），依赖它的 MODE_MACD / MODE_MOMENTUM / MODE_FILTER 随之失效 |
| 模块4b MACD动量 | RunLen/DecelMin/Lookback | 加速段最少连续柱数(6)、减速段最少连续柱数(1)、结构最大回看柱数(50)；仅 MODE_MOMENTUM 生效 |
| 模块4b RSI过滤 | UseRSI/RSIPeriod/RSILevel | **独立开关**（UseRSI，默认**关**）；是否叠加 RSI 顺势过滤、周期(14)、多空分界(50)。依赖模块4，模块4关闭时本项不生效 |
| 模块5 震荡 | **Enabled**/K/D/Slowing/阈值 | **独立开关（v1.38 起默认关闭）**；Stochastic参数与超买超卖阈值。关闭时不创建句柄（零开销），依赖震荡触发的 MODE_FILTER / MODE_ANY 不再出信号 |
| 模块6 K线着色 | Enabled/**HideNormal**/**UseATR**/六色/ATR倍数与周期/各周期点数阈值(回退)/影线/预警 | **独立开关（v1.29 起默认关闭，InpCandleEnabled=false）**；6色K线分类、ATR自适应阈值（由 candle.mq5 提炼，plot0=DRAW_COLOR_CANDLES）。**HideNormal 默认开启 = 不绘制普通K线**，仅高亮特殊K线，普通K线交由图表原生绘制；**UseATR 默认开启**：大实体阈值 = `ATR × 倍数(默认1.5)`，ATR 未就绪时回退到「各周期最小实体点数」表 |
| 模块7 双均线 | Enabled/Fast/Slow/Method/Price/**颜色/线型/粗细** | **默认开启，13 EMA / 30 EMA**（`MODE_EMA`、`PRICE_CLOSE`）。两个作用：① **画线**——plot7/plot8 输出快线与慢线，颜色/线型/粗细（1-5）可分别调整，关闭时 plot 置 `DRAW_NONE`；② **方向过滤**——任何模式产出的信号必须与双均线方向一致，否则丢弃。数据经 `Prepare()` 批量增量预取，过滤只查表 |
| 模块8 形态识别 | Enabled/X/Y/Z/MinBody/AllowLonger/OnlyClosed/**MaxBars**/四色 | **独立开关（v1.38 起默认关闭）**；命中 `x根阳 + 1..y根阴 + z根阳`（或镜像）后对整段着色，plot6=`DRAW_COLOR_CANDLES`，涨形态绿 / 跌形态红 / 回调灰 / 重叠黄。**x/z 必须 >= 2，y 为上限**。小实体（实体 < `MinBody` 点）**不计数、不打断**。只处理最近 `MaxBars`(默认2000) 根。规则见下方说明 |

调好一组参数后：图表右键 → 指标列表 → 保存为 **.set 预设文件**，之后一键切换。

> **模块6「不绘制普通K线」**（`InpCdlHideNormal`，**默认开启**）：
> 普通阳/阴线不再由本指标绘制，**图表原生K线直接透出**；本指标只覆盖显示**特殊K线**（大实体、大影线）。
> 实现方式是把该类 bar 的 O/H/L/C 缓冲置为 `PLOT_EMPTY_VALUE`（终端对空值**不绘制、也不参与自动缩放**）。
> 好处：消除「指标K线与原生K线两层叠色」的发虚观感，图面更干净，且原生K线外观完全由图表模板控制。
> 关闭该项则退回原行为（6 色全量绘制，含普通K线）。

> **模块6「ATR 自适应实体阈值」**（`InpCdlUseATR`，**默认开启**）：
> 大实体阈值不再固定点数，而是 `阈值点数 = ATR(周期) × ATR倍数 ÷ SYMBOL_POINT`（默认 ATR 周期 14、倍数 1.5），**逐 bar 自适应**，换品种 / 换波动率不用重调参数。
> 预热不足（ATR 未就绪的头部若干 bar）自动回退到「各周期最小实体点数」表（M1 36 / M5 60 / M15 80 / M30 100 / H1 200 / H4 350 / D1 800），所以尾部K线不受影响。
> 影线阈值目前仍按「各周期单边影线点数」表判定（`InpCdlM30Shadow` / `H1` / `H4` 等），不参与 ATR 自适应。
> 关闭该项则完全按点数表判定（旧行为）。

> **网格线样式生效时机**：线条的「颜色/线型/线宽」在对象创建时写入，并在**每次指标重新初始化**（改参数、重编译、重挂指标、重开终端）后的首轮同步中对已存在对象**重套一遍**。
> 之所以需要重套：网格对象会被 .chr 随图表持久化，重启后被 `SyncGrid` 判定为「已存在」而不再重建；
> 若此时只更新标签位置、不重写样式，旧样式会一直留在图上（表现为「改了四分位线设置没反应」）。
> 正常使用无需关心这条，改完参数即生效。

> **网格线分层与默认值（v1.39）**：一个容器 `grid_size` 内部按 1/8 步长排布，共四类线：
> | 类型 | 位置 | 默认开关 | 默认线型 |
> |---|---|---|---|
> | 整数位 INT | 0/8（容器边界） | 开 | 实线 solid，宽 2 |
> | 四分位 QTR | 2/8、6/8 | 开 | **点线 dot** |
> | 中位 MID | 4/8 | 开 | 实线 solid |
> | 八分位 EIG | 1/8、3/8、5/8、7/8 | **关** | **dash**（勾选后生效） |
>
> 每类的颜色/线型/线宽/标签字号都可独立调整。

> **网格线「自动检测品种」口径**（`InpGridAutoDetect`，默认开）：
> 自动检测的结果都是「**网格间隔点数** `m_intervalPts`」，整数位线间距 `grid_size = m_intervalPts × SYMBOL_POINT`，
> 八分位线再把 `grid_size` 等分成 8 块（每块 `grid_size / 8`）。
>
> **口径（v1.33：位数定档 + 黄金/股指宽 10 倍）**：
> 展示位数 = 整数部分位数 + 小数位位数（`1.12345` = 6 位，`53000.0` = 6 位，`4000.000` = 7 位）。
> 通用公式：`间隔点数 = 10^(展示位数 − 3)`；**黄金（名称含 `XAU`/`GOLD`）与常见股指**档位宽 10 倍：`10^(展示位数 − 2)`。
> 股指别名（名称包含即命中，不区分大小写）：`US30`/`DJ30`/`WS30`/`DOW`/`USA30`、`USTEC`/`USTECH`/`US100`/`NAS100`/`NASDAQ`、
> `US500`/`USA500`/`SP500`/`SPX`、`GER30`/`GER40`/`DE30`/`DE40`/`DAX`、`UK100`/`FTSE`、`JP225`/`JPN225`/`NIKKEI`。
>
> | 展示位数 | 通用间隔 | 黄金 / 股指 | 换算示例 |
> |---|---|---|---|
> | 5 位 | 100 点 | — | XAGUSD 30.123（point=0.001）→ 0.1 美元 |
> | **6 位** | **1000 点** | **10000 点** | EURUSD 1.12345 → 0.01000；US500 5700.25 → 100 指数点；**XAUUSD 4999.00 → 100.00 美元** |
> | **7 位** | **10000 点** | **100000 点** | XAUUSD 4000.000 → 100.00 美元；USTEC 30000.00 → 1000 指数点 |
> | 8 位 | 100000 点 | 1000000 点 | 长周期指数 / 加密报价 |
>
> 黄金的 6 位与 7 位报价都落在「**每 100 美元一档**」（10000×0.01 = 100000×0.001 = 100），
> 股指则回到「≈1% 价位」的容器（US30 6 位 point 0.1 → 1000 指数点；US500 6 位 point 0.01 → 100 指数点）。
>
> **注意「点（point）」的口径**：`点 = SYMBOL_POINT`（最小报价单位），**不等于指数点**。
> 需要更宽/更窄的网格时，关掉 `InpGridAutoDetect` 用 `InpGridIntervalPts` 手动指定。
> 报价未就绪（BID=0）时不定档，`SyncGrid` 下个周期自动重算；`OnInit` 只算一次，失败不阻塞加载。
>
> 未识别到品种族时回退到通用规则；`InpGridAutoDetect=false` 时完全按手动 `InpGridIntervalPts`。
> 注：只做「前缀」匹配（不做子串匹配），避免误判；若你的经纪商把前缀放在品种名**之前**（如 `mXAUUSD`），请改用手动模式。

> **模块2「价格折线」**（`InpPLEnabled`，**默认开启**）：
> 用 `high[]` / `low[]` / `open[]` 三条价格序列各连一条折线（plot3/4/5，缓冲区 7/8/9）。
> 三条线由 `InpPLShowHigh` / `InpPLShowLow` / `InpPLShowOpen` **独立开关**（**High/Low 默认开，Open 默认关**）：
> 关闭某条线时，`OnInit` 把该 plot 的 `PLOT_DRAW_TYPE` 设为 `DRAW_NONE`（彻底不绘制，也从数据窗口隐藏），
> 同时模块 `Fill()` 对该缓冲区写 `EMPTY_VALUE` 双保险。
> 该模块只依赖价格序列、不依赖任何指标就绪状态，故在 `OnCalculate` 中**无条件刷新**，与 K 线着色同层。
> 注：是否开启某一开关会触发指标重新初始化（改参数即重算），这是 MQL5 指标绘图属性的正常行为。

> **模块8「形态识别」**（`InpPatEnabled`，**默认开启**）：
> 规则：`x 根连续阳线 + y 根连续阴线 + z 根连续阳线`（涨→回调→涨），或镜像 `x 根阴 + y 根阳 + z 根阴`（跌→反弹→跌）。命中后对**整段**（第一段起点到最后一根）着色，plot6 = `DRAW_COLOR_CANDLES`。
> - **根数口径**：`InpPatX` / `InpPatZ` **必须 >= 2**（首尾两段是形态主体）；`InpPatY` 是**上限**——`1..y` 根反向K线都算命中，默认 2 时 `阳阴阳` 与 `阳阴阴阳阳` 都触发。
> - **小实体忽略**：实体（|close−open|）小于 `InpPatMinBody` 点（默认 22）的K线不计数、也不打断连续性，可出现在段内任意位置（含十字星）。
> - **严格性（只作用于 x/z）**：`InpPatAllowLonger=false`（默认）时 x、z 必须**恰好**等于设定值，`阳阳阳阴阴阳阳` 不算 `阳阳阴阴阳阳`；设为 true 则 x/z 段「至少」设定值，多出的K线一起着色。
> - **防重绘**：`InpPatOnlyClosed=true`（默认）时只在K线收盘后确认，最右未收盘bar不参与判定。
> - **颜色（v1.36）**：按角色分色 —— 主体段按方向（阳=绿 `InpPatBullColor`、阴=红 `InpPatBearColor`），
>   **回调段与小实体/十字星统一灰色**（`InpPatMidColor`，默认 `clrGray`），
>   **重叠部分统一黄色**（`InpPatOverlapColor`，默认 `clrYellow`）。
>   于是「涨-回调-涨」= 绿绿**灰灰**绿绿，「跌-反弹-跌」= 红红**灰灰**红红，形态含义一眼可辨。
> - **重叠判定**：同一根K线被 **≥2 个形态**覆盖即为重叠（涨形态末端与跌形态开端交叠、或连续多个形态首尾相连时中间段会大面积为黄）。
>   实现为两阶段：先统计每根bar的覆盖次数 `PatHits` 与角色 `PatRole`，再统一着色；计数按「新bar收盘时一次」增量维护，不重复累计。
> - **处理窗口（v1.37）**：`InpPatMaxBars`（默认 **2000**）限制形态识别只处理/绘制最近 N 根K线；
>   计数数组按窗口大小分配并以**相对下标**访问，窗口平移时整体左移、滑出窗口的旧K线自动清空（0 = 不限制）。
>   注：MT5 会按 `indicator_buffers` 预分配全历史长度的绘图缓冲区，本项省的是识别侧的计数数组与逐bar判定开销。
> - **去重**：写缓冲区前比对「同色 + 同收盘价」，同一根bar不重复落笔。

> **模块独立性（每个模块都能独立关闭）**：
> **默认开启**：模块1 网格线、模块2 价格折线、模块3 倒计时（纯显示，参数组排最前）、模块7 双均线（13/30 EMA，方向过滤）。
> **默认关闭**：模块4 MACD、模块4b RSI、模块5 震荡、模块6 K线着色、模块8 形态识别。
> 开关变量：模块1 `InpGridEnabled`、模块2 `InpPLEnabled`、模块3 `InpCdEnabled`、模块4 `InpMacdEnabled`、
> 模块4b `InpMacdUseRSI`、模块5 `InpOscEnabled`、模块6 `InpCandleEnabled`、模块7 `InpMaEnabled`、模块8 `InpPatEnabled`。
>
> 关闭后的开销（**这是"关掉还占不占内存"的准确答案**）：
> - **信号类（模块4 / 4b / 5 / 7）**：不创建指标句柄、不计算，内部数组不 `ArrayResize` → **真正零开销**；
>   信号合成中该模块输出恒为 0，只让依赖它的模式失效（关模块5 → MODE_FILTER/MODE_ANY 无信号；关模块4 → MODE_MACD/FILTER/MOMENTUM 无信号）。
> - **着色类（模块6 / 8）**：不判定、不写缓冲区；模块8 的计数数组 `PatHits/PatRole` 也不再分配。
> - **显示类（模块1 / 2 / 3）**：不创建图形对象、不刷新，`Release()` 会清掉已建对象。
> - **关不掉的部分**：MT5 按 `indicator_buffers`（本指标 17 个）为**全部历史**预分配 double 绘图缓冲，
>   约 **136 字节/bar**，与开关无关（100 万根 M1 ≈ 136MB）。想彻底省掉只能把对应 plot 拆成独立子指标。
> - 预热 bar 数 `minBars` 只按「已启用」的模块累加，禁用模块不占预热位。

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

## 六、模块4：MACD 二线交叉口径（重要）

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
- **模块7 双均线**（默认开启 13/30 EMA）：图上绘制快/慢两条线（颜色、线型、粗细可调），同时作为方向过滤 —— 最终信号必须与双均线方向一致，否则丢弃
- 信号画在触发bar上：绿色↑ = Buy，红色↓ = Sell

> **箭头落在哪根 bar**：`InpOnlyClosed=true`（默认）时只在 K 线**收盘后**判定，
> 因此箭头画在「交叉确认的那根已收盘 bar」上，与副图的交叉点逐根对应，且不重绘。
> 设为 false 则盘中实时判定，信号会随未收盘 bar 跳动（重绘）。
>
> 示例规则仅演示架构，请替换成你自己的系统逻辑后再评估使用。
