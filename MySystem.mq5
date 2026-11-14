//+------------------------------------------------------------------+
//|                                                   MySystem.mq5   |
//|  交易系统主指标（骨架）：聚合各逻辑模块，输出综合信号               |
//|                                                                  |
//|  架构：源码拆分(.mqh) / 产品聚合(单个.ex5)                         |
//|   · 各逻辑模块放在 Modules\ 下的 .mqh 文件，独立维护              |
//|   · 本文件编译后是一个完整指标，图上只需挂这一个                   |
//|   · 新增模块三步：写 .mqh -> include -> OnCalculate 里调用        |
//|                                                                  |
//|  扩展方式B：调用独立子指标（无需手动挂到图表）                     |
//|   int h = iCustom(_Symbol, _Period, "MyFolder\\MySubInd",         |
//|                   参数1, 参数2, ...);                             |
//|   double v[];                                                     |
//|   CopyBuffer(h, 0, start, 2, v);  // v[0]=index-1, v[1]=index     |
//|   注意：子指标须位于 MQL5\Indicators\ 下且已编译                   |
//+------------------------------------------------------------------+
#property copyright   "MyTradingSystem"
#property version     "1.44"
#property description "模块化交易系统骨架：主指标聚合器"
#property description "默认开启：网格线 + 价格折线(高/低) + K线倒计时 + 双均线(13/30 EMA，含画线)"
#property description "默认关闭：MACD二线交叉 / 震荡触发 / MACD动量 / K线着色 / 形态识别"
#property indicator_chart_window
#property indicator_buffers 17
#property indicator_plots   9

#property indicator_label1  "Candles"
#property indicator_type1   DRAW_COLOR_CANDLES
#property indicator_color1  clrLime,clrRed,clrDeepSkyBlue,clrMagenta,clrDarkGreen,clrMaroon

#property indicator_label2  "Buy"
#property indicator_type2   DRAW_ARROW
#property indicator_color2  clrLime
#property indicator_width2  2

#property indicator_label3  "Sell"
#property indicator_type3   DRAW_ARROW
#property indicator_color3  clrOrangeRed
#property indicator_width3  2

//--- 模块2：价格折线（默认类型；OnInit 里会按开关改写为 DRAW_NONE）
#property indicator_label4  "High Line"
#property indicator_type4   DRAW_LINE
#property indicator_color4  clrDodgerBlue
#property indicator_width4  1

#property indicator_label5  "Low Line"
#property indicator_type5   DRAW_LINE
#property indicator_color5  clrOrangeRed
#property indicator_width5  1

#property indicator_label6  "Open Line"
#property indicator_type6   DRAW_LINE
#property indicator_color6  clrGold
#property indicator_width6  1

//--- 模块8：形态识别（默认类型；关闭时 OnInit 里会改写为 DRAW_NONE）
#property indicator_label7  "Pattern"
#property indicator_type7   DRAW_COLOR_CANDLES
#property indicator_color7  clrLime,clrRed,clrGray,clrYellow

//--- 模块7：双均线（关闭时 OnInit 里改写为 DRAW_NONE）
#property indicator_label8  "MA Fast"
#property indicator_type8   DRAW_LINE
#property indicator_color8  clrDodgerBlue
#property indicator_width8  2

#property indicator_label9  "MA Slow"
#property indicator_type9   DRAW_LINE
#property indicator_color9  clrOrangeRed
#property indicator_width9  2

#include "Modules\MacdTrend.mqh"
#include "Modules\OscSignal.mqh"
#include "Modules\RsiFilter.mqh"
#include "Modules\Countdown.mqh"
#include "Modules\GridLines.mqh"
#include "Modules\BigCandles.mqh"
#include "Modules\TrendMA.mqh"    // 模块7：双均线趋势（默认开启，13/30 EMA 方向过滤）
#include "Modules\PriceLines.mqh" // 模块2：价格折线（高/低/开，三条折线可独立开关）
#include "Modules\PatternSig.mqh" // 模块8：形态识别（涨-回调-涨 / 跌-反弹-跌）

//--- 信号组合模式
enum ENUM_SIGNAL_MODE
  {
   MODE_FILTER   = 0,   // 震荡触发 + MACD方向过滤
   MODE_ANY      = 1,   // 仅震荡触发(测试用)
   MODE_MACD     = 2,   // ★MACD二线交叉(DIF上穿/下穿DEA) —— 默认
   MODE_MOMENTUM = 3    // MACD柱动量耗尽确认(加速→减速→反向穿越)
  };

//=== 参数：分组收纳，只在这里暴露可调项 ==============================
//    顺序 = 使用频率：默认开启的三个显示模块（网格线/价格折线/倒计时）排最前，
//    其后系统设置，最后是默认关闭的信号与着色模块
input group "══════ 模块1：网格线 ══════"
input bool            InpGridEnabled     = true;              // 启用网格线
input bool            InpGridAutoDetect  = true;              // 自动检测品种网格间隔
input int             InpGridIntervalPts = 1000;              // 网格间隔点数(手动模式)
input int             InpGridNumLines    = 5;                 // 每侧线条数量
input int             InpGridUpdateSecs  = 5;                 // 更新间隔秒数
input bool            InpGridShowInt     = true;              // 显示整数位线条
input color           InpGridIntColor    = clrDarkOrange;     // 整数位颜色
input ENUM_LINE_STYLE InpGridIntStyle    = STYLE_SOLID;       // 整数位线型
input int             InpGridIntWidth    = 2;                 // 整数位线宽
input int             InpGridIntFontSize = 18;                // 整数位标签字号
input bool            InpGridAlertInt    = false;             // 整数位预警
input bool            InpGridShowQtr     = true;              // 显示四分之一位线条
input color           InpGridQtrColor    = clrFireBrick;      // 四分之一位颜色
input ENUM_LINE_STYLE InpGridQtrStyle    = STYLE_DOT;         // 四分之一位线型
input int             InpGridQtrWidth    = 1;                 // 四分之一位线宽
input int             InpGridQtrFontSize = 12;                // 四分之一位标签字号
input bool            InpGridShowMid     = true;              // 显示中位线条
input color           InpGridMidColor    = clrViolet;         // 中位线颜色
input ENUM_LINE_STYLE InpGridMidStyle    = STYLE_SOLID;       // 中位线线型
input int             InpGridMidWidth    = 1;                 // 中位线线宽
input int             InpGridMidFontSize = 16;                // 中位线标签字号
input bool            InpGridAlertMid    = false;             // 中位线预警
input bool            InpGridShowEig     = false;             // 显示八分位线条(默认关)
input color           InpGridEigColor    = clrTeal;           // 八分位颜色
input ENUM_LINE_STYLE InpGridEigStyle    = STYLE_DASH;        // 八分位线型
input int             InpGridEigWidth    = 1;                 // 八分位线宽
input int             InpGridEigFontSize = 10;                // 八分位标签字号
input bool            InpGridShowLabels  = true;              // 显示价格标签
input color           InpGridLabelColor  = clrWhite;          // 标签颜色
input string          InpGridLabelFont   = "Consolas";        // 标签字体

input group "══════ 模块2：价格折线(最高/最低/开盘，可独立开关) ══════"
input bool            InpPLEnabled   = true;         // 启用价格折线模块
input bool            InpPLShowHigh  = true;         // 绘制最高价折线
input color           InpPLHighColor = clrDodgerBlue; // 最高价线颜色
input ENUM_LINE_STYLE InpPLHighStyle = STYLE_SOLID;  // 最高价线型
input int             InpPLHighWidth = 1;            // 最高价线宽
input bool            InpPLShowLow   = true;         // 绘制最低价折线
input color           InpPLLowColor  = clrOrangeRed; // 最低价线颜色
input ENUM_LINE_STYLE InpPLLowStyle  = STYLE_SOLID;  // 最低价线型
input int             InpPLLowWidth  = 1;            // 最低价线宽
input bool            InpPLShowOpen  = false;        // 绘制开盘价折线
input color           InpPLOpenColor = clrGold;      // 开盘价线颜色
input ENUM_LINE_STYLE InpPLOpenStyle = STYLE_DOT;    // 开盘价线型
input int             InpPLOpenWidth = 1;            // 开盘价线宽

input group "══════ 模块3：倒计时 ══════"
input bool   InpCdEnabled   = true;        // 启用倒计时显示
input int    InpCdFontSize  = 14;          // 字体大小
input color  InpCdColor     = clrYellow;   // 字体颜色
input string InpCdFontName  = "Consolas";  // 字体名称(建议等宽)
input int    InpCdXOffset   = 10;          // X轴偏移量(像素)
input int    InpCdYOffset   = 15;          // Y轴偏移量(像素，越大越往下)
input bool   InpCdShowPrice = true;        // 显示实时价格
input string InpCdSeparator = "  |  ";     // 倒计时与价格的分隔符

input group "══════ 系统设置 ══════"
input ENUM_SIGNAL_MODE InpMode       = MODE_MACD;   // 信号组合模式(需先启用对应模块；默认MACD)
input bool             InpOnlyClosed = true;        // 仅收盘bar出信号(防重绘)

input group "══════ 模块4：MACD 二线交叉(默认关闭，同 iMACD 口径) ══════"
input bool               InpMacdEnabled  = false;        // 启用 MACD 模块
input int                InpMacdFast     = 12;          // 快线EMA周期
input int                InpMacdSlow     = 26;          // 慢线EMA周期
input int                InpMacdSignal   = 9;           // 信号线DEA周期(SMA平滑，同iMACD)
input ENUM_APPLIED_PRICE InpMacdPrice    = PRICE_CLOSE; // 应用价格
input double             InpMacdHistMult = 1.0;         // 柱放大倍数(1.0=与2linemacd柱值一致)

input group "══════ 模块4b：MACD动量确认(仅 MODE_MOMENTUM 生效) ══════"
input int    InpMacdRunLen    = 6;     // 加速段最少连续柱数
input int    InpMacdDecelMin  = 1;     // 减速段最少连续柱数
input int    InpMacdLookback  = 50;    // 结构最大回看柱数
input bool   InpMacdUseRSI    = false; // 叠加RSI方向过滤(顺势确认，会明显减少信号)
input int    InpMacdRSIPeriod = 14;    // RSI周期(仅上面开关开启时生效)
input double InpMacdRSILevel  = 50.0;  // RSI多空分界

input group "══════ 模块5：震荡(Stoch)(默认关闭) ══════"
input bool   InpOscEnabled   = false;  // 启用震荡模块
input int    InpOscK         = 14;    // %K 周期
input int    InpOscD         = 3;     // %D 周期
input int    InpOscSlowing   = 3;     // 平滑
input double InpOscBuyLevel  = 25.0;  // 超卖阈值
input double InpOscSellLevel = 75.0;  // 超买阈值

input group "══════ 模块6：K线着色(默认关闭) ══════"
input bool   InpCandleEnabled  = false;              // 启用K线着色
input bool   InpCdlHideNormal  = true;               // 不绘制普通K线(仅高亮特殊K线)
input color  InpCdlBullBody    = clrLime;            // 大实体阳线颜色
input color  InpCdlBearBody    = clrRed;             // 大实体阴线颜色
input color  InpCdlShadowBull  = clrDeepSkyBlue;     // 大下影线K线颜色(偏多)
input color  InpCdlShadowBear  = clrMagenta;         // 大上影线K线颜色(偏空)
input color  InpCdlNormalBull  = clrDarkGreen;       // 普通阳线颜色
input color  InpCdlNormalBear  = clrMaroon;          // 普通阴线颜色
input bool   InpCdlUseATR      = true;               // 使用ATR自适应实体阈值(默认开)
input double InpCdlATRMult     = 1.5;                // ATR倍数
input int    InpCdlATRPeriod   = 14;                 // ATR周期
input int    InpCdlM1Body      = 36;                 // M1最小实体点数
input int    InpCdlM5Body      = 60;                 // M5最小实体点数
input int    InpCdlM15Body     = 80;                 // M15最小实体点数
input int    InpCdlM30Body     = 100;                // M30最小实体点数
input int    InpCdlH1Body      = 200;                // H1最小实体点数
input int    InpCdlH4Body      = 350;                // H4最小实体点数
input int    InpCdlD1Body      = 800;                // D1最小实体点数
input bool   InpCdlShowShadow  = false;              // 显示大影线K线
input int    InpCdlM30Shadow   = 200;                // M30最小单边影线点数
input int    InpCdlH1Shadow    = 300;                // H1最小单边影线点数
input int    InpCdlH4Shadow    = 400;                // H4最小单边影线点数
input int    InpCdlD1Shadow    = 600;                // D1最小单边影线点数
input bool   InpCdlFilterRatio = true;               // 过滤实体过大的影线K线
input double InpCdlMaxRatio    = 62.0;               // 最大实体/影线比例(%)
input bool   InpCdlAlerts      = false;              // 开启预警
input bool   InpCdlAlertBody   = true;               // 大实体K线预警
input bool   InpCdlAlertShadow = true;               // 大影线K线预警
input bool   InpCdlDebug       = false;              // 显示调试信息

//=== 可选模块：参数组按约定统一排在设置页最底部，默认关闭、不参与信号 ===
input group "══════ 模块7：双均线趋势(默认开启，方向过滤) ══════"
input bool               InpMaEnabled = true;           // 启用双均线模块
input int                InpMaFast    = 13;             // 快线周期(默认13 EMA)
input int                InpMaSlow    = 30;             // 慢线周期(默认30 EMA)
input ENUM_MA_METHOD     InpMaMethod  = MODE_EMA;       // 均线算法
input ENUM_APPLIED_PRICE InpMaPrice   = PRICE_CLOSE;    // 应用价格
input color              InpMaFastColor = clrDodgerBlue;// 快线颜色
input ENUM_LINE_STYLE    InpMaFastStyle = STYLE_SOLID;  // 快线线型
input int                InpMaFastWidth = 2;            // 快线粗细(1-5)
input color              InpMaSlowColor = clrOrangeRed; // 慢线颜色
input ENUM_LINE_STYLE    InpMaSlowStyle = STYLE_SOLID;  // 慢线线型
input int                InpMaSlowWidth = 2;            // 慢线粗细(1-5)

input group "══════ 模块8：形态识别(默认关闭) ══════"
input bool   InpPatEnabled   = false;            // 启用形态识别
input int    InpPatX         = 2;               // 第一段连续根数 x (>=2)
input int    InpPatY         = 2;               // 第二段反向根数 y (上限，1..y 均命中)
input int    InpPatZ         = 2;               // 第三段连续根数 z (>=2)
input int    InpPatMinBody   = 22;              // 小实体忽略阈值(点，小于此值不计数)
input bool   InpPatAllowLonger = false;         // 允许 x/z 段长于设定根数(整段着色)
input bool   InpPatOnlyClosed  = true;          // 仅收盘bar确认(防重绘)
input int    InpPatMaxBars   = 2000;            // 只处理最近N根(0=全部，省内存)
input color  InpPatBullColor = clrLime;         // 主体段阳线颜色(默认绿)
input color  InpPatBearColor = clrRed;          // 主体段阴线颜色(默认红)
input color  InpPatMidColor  = clrGray;         // 回调段/小实体颜色(默认灰)
input color  InpPatOverlapColor = clrYellow;    // 形态重叠部分颜色(默认黄)

//--- 模块实例（全局单例）
CMacdModule      g_macd;
COscModule       g_osc;
CRsiFilter       g_rsi;
CCountdownModule g_cd;
CGridModule      g_grid;
CBigCandleModule g_candle;
CTrendModule     g_ma;      // 模块7：双均线（默认启用 13/30 EMA）
CPriceLineModule g_pl;      // 模块2：价格折线（高/低/开）
CPatternModule   g_pat;     // 模块8：形态识别（涨-回调-涨 / 跌-反弹-跌）

//--- 指标缓冲区
double CandleOpen[];      // 模块6：K线着色 O/H/L/C
double CandleHigh[];
double CandleLow[];
double CandleClose[];
double CandleColor[];     // 模块6：颜色索引(0-5)
double BufBuy[];          // 信号箭头
double BufSell[];

//--- 模块2：价格折线缓冲区（plot 3/4/5）
double PLHigh[];          // 最高价折线
double PLLow[];           // 最低价折线
double PLOpen[];          // 开盘价折线

//--- 模块8：形态识别缓冲区（plot 6）
double PatOpen[];
double PatHigh[];
double PatLow[];
double PatClose[];
double PatColor[];        // 0=主体阳线 / 1=主体阴线 / 2=回调与小实体 / 3=形态重叠

//--- 模块7：双均线绘图缓冲区（plot 7/8）
double MaFastBuf[];
double MaSlowBuf[];

//--- 模块8：重叠统计（非缓冲区，仅覆盖最近 InpPatMaxBars 根窗口）
//    PatHits = 该bar被多少个形态覆盖（>=2 即重叠，画黄色）
//    PatRole = 唯一覆盖时的角色（1=主体段 / 2=回调段或被忽略的小实体）
//    下标为【窗口相对下标】：k - g_patWinStart
int PatHits[];
int PatRole[];
int g_patWinStart = -1;   // 上一轮的窗口首根（-1 = 尚未初始化）

//--- 数据完整性状态位
//    true = 上一次计算时任一数据依赖（MACD/Stoch/RSI/ATR）未就绪，历史区被跳过；
//    下一轮必须从 0 开始全量重算，否则「未就绪期间跳过的历史」会被永久漏算
//    （旧实现只依赖 prev_calculated，正是历史信号/着色丢失的根因）
bool g_needFull = true;

//+------------------------------------------------------------------+
//| 预热bar数：只计入「已启用」的模块所需的最长预热区                   |
//| 单一口径，OnInit 与 OnCalculate 共用（避免两处参数漂移）            |
//+------------------------------------------------------------------+
int WarmupBars(void)
  {
   int bars = 5;
   if(InpMacdEnabled)
      bars = MathMax(bars, InpMacdSlow + InpMacdSignal + 5);
   if(InpMacdEnabled && InpMacdUseRSI)
      bars = MathMax(bars, InpMacdRSIPeriod + 5);
   if(InpMacdEnabled && InpMode == MODE_MOMENTUM)
      bars = MathMax(bars, InpMacdLookback + InpMacdRunLen + InpMacdDecelMin + 5);
   if(InpOscEnabled)
      bars = MathMax(bars, InpOscK + InpOscD + InpOscSlowing + 5);
   if(InpMaEnabled)
      bars = MathMax(bars, InpMaSlow + 5);
   if(InpCandleEnabled && InpCdlUseATR)
      bars = MathMax(bars, InpCdlATRPeriod + 2);
   return(bars);
  }

//+------------------------------------------------------------------+
int OnInit()
  {
   //--- 重初始化（切周期/改参数）后必须从 0 全量重算
   g_needFull = true;

   //--- 模块6：K线着色缓冲区（plot 0 = DRAW_COLOR_CANDLES）
   SetIndexBuffer(0, CandleOpen,  INDICATOR_DATA);
   SetIndexBuffer(1, CandleHigh,  INDICATOR_DATA);
   SetIndexBuffer(2, CandleLow,   INDICATOR_DATA);
   SetIndexBuffer(3, CandleClose, INDICATOR_DATA);
   SetIndexBuffer(4, CandleColor, INDICATOR_COLOR_INDEX);

   //--- 信号箭头缓冲区（plot 1/2）
   SetIndexBuffer(5, BufBuy,  INDICATOR_DATA);
   SetIndexBuffer(6, BufSell, INDICATOR_DATA);

   //--- 模块2：价格折线缓冲区（plot 3/4/5）
   SetIndexBuffer(7, PLHigh, INDICATOR_DATA);
   SetIndexBuffer(8, PLLow,  INDICATOR_DATA);
   SetIndexBuffer(9, PLOpen, INDICATOR_DATA);

   //--- 模块8：形态识别缓冲区（plot 6 = DRAW_COLOR_CANDLES）
   SetIndexBuffer(10, PatOpen,  INDICATOR_DATA);
   SetIndexBuffer(11, PatHigh,  INDICATOR_DATA);
   SetIndexBuffer(12, PatLow,   INDICATOR_DATA);
   SetIndexBuffer(13, PatClose, INDICATOR_DATA);
   SetIndexBuffer(14, PatColor, INDICATOR_COLOR_INDEX);

   //--- 模块7：双均线缓冲区（plot 7/8）
   SetIndexBuffer(15, MaFastBuf, INDICATOR_DATA);
   SetIndexBuffer(16, MaSlowBuf, INDICATOR_DATA);

   //--- K线着色 plot 属性：6 个颜色槽由模块参数驱动
   PlotIndexSetInteger(0, PLOT_COLOR_INDEXES, 6);
   PlotIndexSetInteger(0, PLOT_LINE_COLOR, 0, InpCdlBullBody);
   PlotIndexSetInteger(0, PLOT_LINE_COLOR, 1, InpCdlBearBody);
   PlotIndexSetInteger(0, PLOT_LINE_COLOR, 2, InpCdlShadowBull);
   PlotIndexSetInteger(0, PLOT_LINE_COLOR, 3, InpCdlShadowBear);
   PlotIndexSetInteger(0, PLOT_LINE_COLOR, 4, InpCdlNormalBull);
   PlotIndexSetInteger(0, PLOT_LINE_COLOR, 5, InpCdlNormalBear);
   PlotIndexSetDouble(0, PLOT_EMPTY_VALUE, EMPTY_VALUE);

   PlotIndexSetInteger(1, PLOT_ARROW, 233);              // 上箭头
   PlotIndexSetInteger(2, PLOT_ARROW, 234);              // 下箭头
   PlotIndexSetInteger(1, PLOT_ARROW_SHIFT,  12);        // 箭头离K线下方
   PlotIndexSetInteger(2, PLOT_ARROW_SHIFT, -12);        // 箭头离K线上方
   PlotIndexSetDouble(1, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(2, PLOT_EMPTY_VALUE, EMPTY_VALUE);

   //--- 模块2：价格折线 plot 属性（颜色/线宽/线型）；关闭的线由 Fill() 写 EMPTY_VALUE 隐藏
   //--- 注意：运行时【不要】改写 PLOT_DRAW_TYPE。MT5 会据此重算 plot->buffer 映射，
   //    多缓冲 plot（DRAW_COLOR_CANDLES）改成 DRAW_NONE 时会把后续 plot 的缓冲整体挪位，
   //    表现为「后面的 plot 有值却画不出来、数据窗口空白」。显隐一律由数据（EMPTY）控制。
   PlotIndexSetInteger(3, PLOT_LINE_COLOR, InpPLHighColor);
   PlotIndexSetInteger(3, PLOT_LINE_WIDTH, InpPLHighWidth);
   PlotIndexSetInteger(3, PLOT_LINE_STYLE, InpPLHighStyle);
   PlotIndexSetDouble (3, PLOT_EMPTY_VALUE, EMPTY_VALUE);

   PlotIndexSetInteger(4, PLOT_LINE_COLOR, InpPLLowColor);
   PlotIndexSetInteger(4, PLOT_LINE_WIDTH, InpPLLowWidth);
   PlotIndexSetInteger(4, PLOT_LINE_STYLE, InpPLLowStyle);
   PlotIndexSetDouble (4, PLOT_EMPTY_VALUE, EMPTY_VALUE);

   PlotIndexSetInteger(5, PLOT_LINE_COLOR, InpPLOpenColor);
   PlotIndexSetInteger(5, PLOT_LINE_WIDTH, InpPLOpenWidth);
   PlotIndexSetInteger(5, PLOT_LINE_STYLE, InpPLOpenStyle);
   PlotIndexSetDouble (5, PLOT_EMPTY_VALUE, EMPTY_VALUE);

   //--- 模块8：形态识别 plot 属性（4 个颜色槽：0=主体阳线 / 1=主体阴线 /
   //    2=回调与小实体 / 3=形态重叠）
   PlotIndexSetInteger(6, PLOT_COLOR_INDEXES, 4);
   PlotIndexSetInteger(6, PLOT_LINE_COLOR, 0, InpPatBullColor);
   PlotIndexSetInteger(6, PLOT_LINE_COLOR, 1, InpPatBearColor);
   PlotIndexSetInteger(6, PLOT_LINE_COLOR, 2, InpPatMidColor);
   PlotIndexSetInteger(6, PLOT_LINE_COLOR, 3, InpPatOverlapColor);
   PlotIndexSetDouble (6, PLOT_EMPTY_VALUE, EMPTY_VALUE);

   //--- 模块7：双均线 plot 属性（颜色/线型/粗细）；关闭时缓冲全 EMPTY，不绘制
   PlotIndexSetDouble (7, PLOT_EMPTY_VALUE, EMPTY_VALUE);

   //--- 颜色/线宽兜底：旧图表实例可能把新加的 input 存成 0（黑色 / 宽度 0），
   //    在黑色背景上等于完全隐形。0 视为「未设置」，回落到默认值。
   color cFast = (InpMaFastColor == clrBlack) ? clrDodgerBlue : InpMaFastColor;
   color cSlow = (InpMaSlowColor == clrBlack) ? clrOrangeRed  : InpMaSlowColor;
   int   wFast = InpMaFastWidth; if(wFast < 1) wFast = 1; if(wFast > 5) wFast = 5;
   int   wSlow = InpMaSlowWidth; if(wSlow < 1) wSlow = 1; if(wSlow > 5) wSlow = 5;

   PlotIndexSetInteger(7, PLOT_LINE_COLOR, cFast);
   PlotIndexSetInteger(7, PLOT_LINE_STYLE, InpMaFastStyle);
   PlotIndexSetInteger(7, PLOT_LINE_WIDTH, wFast);

   PlotIndexSetInteger(8, PLOT_LINE_COLOR, cSlow);
   PlotIndexSetInteger(8, PLOT_LINE_STYLE, InpMaSlowStyle);
   PlotIndexSetInteger(8, PLOT_LINE_WIDTH, wSlow);
   PlotIndexSetDouble (8, PLOT_EMPTY_VALUE, EMPTY_VALUE);

   //--- 预热bar数：只计入「已启用」的模块所需的最长预热区（与 OnCalculate 同一函数）
   int minBars = WarmupBars();
   PlotIndexSetInteger(1, PLOT_DRAW_BEGIN, minBars);
   PlotIndexSetInteger(2, PLOT_DRAW_BEGIN, minBars);

   IndicatorSetString(INDICATOR_SHORTNAME, "MySystem v1.44");
   IndicatorSetInteger(INDICATOR_DIGITS, _Digits);

   //--- 装配模块：新增模块时在此加一段配置
   //--- 模块4：MACD（默认启用；关闭时不创建句柄，零开销）
   if(InpMacdEnabled)
     {
      MacdSettings mc;
      mc.FastPeriod     = InpMacdFast;
      mc.SlowPeriod     = InpMacdSlow;
      mc.SignalPeriod   = InpMacdSignal;
      mc.Price          = InpMacdPrice;
      mc.HistMultiplier = InpMacdHistMult;
      if(!g_macd.Create(_Symbol, _Period, mc))
         return(INIT_FAILED);
     }

   //--- 模块4b：RSI 过滤器（可选；依赖 MACD 模块，二者都开启时才创建句柄）
   if(InpMacdEnabled && InpMacdUseRSI)
     {
      RsiSettings rc;
      rc.Period = InpMacdRSIPeriod;
      rc.Level  = InpMacdRSILevel;
      if(!g_rsi.Create(_Symbol, _Period, rc))
         return(INIT_FAILED);
     }

   //--- 模块5：震荡 Stoch（默认启用；关闭时不创建句柄，零开销）
   if(InpOscEnabled)
     {
      OscSettings oc;
      oc.KPeriod   = InpOscK;
      oc.DPeriod   = InpOscD;
      oc.Slowing   = InpOscSlowing;
      oc.BuyLevel  = InpOscBuyLevel;
      oc.SellLevel = InpOscSellLevel;
      if(!g_osc.Create(_Symbol, _Period, oc))
         return(INIT_FAILED);
     }

   CountdownSettings cc;
   cc.Enabled   = InpCdEnabled;
   cc.FontSize  = InpCdFontSize;
   cc.FontColor = InpCdColor;
   cc.FontName  = InpCdFontName;
   cc.XOffset   = InpCdXOffset;
   cc.YOffset   = InpCdYOffset;
   cc.ShowPrice = InpCdShowPrice;
   cc.Separator = InpCdSeparator;
   if(!g_cd.Create(cc))
      return(INIT_FAILED);

   GridSettings gc;
   gc.Enabled         = InpGridEnabled;
   gc.AutoDetect      = InpGridAutoDetect;
   gc.IntervalPoints  = InpGridIntervalPts;
   gc.NumLines        = InpGridNumLines;
   gc.UpdateSeconds   = InpGridUpdateSecs;
   gc.ShowInteger     = InpGridShowInt;
   gc.IntegerColor    = InpGridIntColor;
   gc.IntegerStyle    = InpGridIntStyle;
   gc.IntegerWidth    = InpGridIntWidth;
   gc.IntegerFontSize = InpGridIntFontSize;
   gc.AlertInteger    = InpGridAlertInt;
   gc.ShowQuarter     = InpGridShowQtr;
   gc.QuarterColor    = InpGridQtrColor;
   gc.QuarterStyle    = InpGridQtrStyle;
   gc.QuarterWidth    = InpGridQtrWidth;
   gc.QuarterFontSize = InpGridQtrFontSize;
   gc.ShowMid         = InpGridShowMid;
   gc.MidColor        = InpGridMidColor;
   gc.MidStyle        = InpGridMidStyle;
   gc.MidWidth        = InpGridMidWidth;
   gc.MidFontSize     = InpGridMidFontSize;
   gc.AlertMid        = InpGridAlertMid;
   gc.ShowEighth      = InpGridShowEig;
   gc.EighthColor     = InpGridEigColor;
   gc.EighthStyle     = InpGridEigStyle;
   gc.EighthWidth     = InpGridEigWidth;
   gc.EighthFontSize  = InpGridEigFontSize;
   gc.ShowLabels      = InpGridShowLabels;
   gc.LabelColor      = InpGridLabelColor;
   gc.LabelFont       = InpGridLabelFont;
   if(!g_grid.Create(_Symbol, _Period, gc))
      return(INIT_FAILED);

   CandleSettings bc;
   bc.Enabled              = InpCandleEnabled;
   bc.HideNormalCandles    = InpCdlHideNormal;
   bc.BullBodyColor        = InpCdlBullBody;
   bc.BearBodyColor        = InpCdlBearBody;
   bc.ShadowBullColor      = InpCdlShadowBull;
   bc.ShadowBearColor      = InpCdlShadowBear;
   bc.NormalBullColor      = InpCdlNormalBull;
   bc.NormalBearColor      = InpCdlNormalBear;
   bc.UseATRForBody        = InpCdlUseATR;
   bc.BodyATRMultiplier    = InpCdlATRMult;
   bc.ATRPeriod            = InpCdlATRPeriod;
   bc.M1MinBody            = InpCdlM1Body;
   bc.M5MinBody            = InpCdlM5Body;
   bc.M15MinBody           = InpCdlM15Body;
   bc.M30MinBody           = InpCdlM30Body;
   bc.H1MinBody            = InpCdlH1Body;
   bc.H4MinBody            = InpCdlH4Body;
   bc.D1MinBody            = InpCdlD1Body;
   bc.ShowShadowCandles    = InpCdlShowShadow;
   bc.M30MinShadow         = InpCdlM30Shadow;
   bc.H1MinShadow          = InpCdlH1Shadow;
   bc.H4MinShadow          = InpCdlH4Shadow;
   bc.D1MinShadow          = InpCdlD1Shadow;
   bc.FilterShadowByBodyRatio = InpCdlFilterRatio;
   bc.MaxBodyShadowRatio   = InpCdlMaxRatio;
   bc.EnableAlerts         = InpCdlAlerts;
   bc.AlertOnBigBody       = InpCdlAlertBody;
   bc.AlertOnBigShadow     = InpCdlAlertShadow;
   bc.ShowDebugInfo        = InpCdlDebug;
   if(!g_candle.Create(_Symbol, _Period, bc))
      return(INIT_FAILED);

   //--- 模块7：双均线趋势（默认开启；关闭时不创建句柄，零开销）
   if(InpMaEnabled)
     {
      TrendSettings tc;
      tc.FastPeriod = InpMaFast;
      tc.SlowPeriod = InpMaSlow;
      tc.Method     = InpMaMethod;
      tc.Price      = InpMaPrice;
      if(!g_ma.Create(_Symbol, _Period, tc))
         return(INIT_FAILED);
     }

   //--- 模块2：价格折线（高/低/开；三条线可独立开关）
   PriceLineSettings pls;
   pls.Enabled  = InpPLEnabled;
   pls.ShowHigh = InpPLShowHigh;
   pls.ShowLow  = InpPLShowLow;
   pls.ShowOpen = InpPLShowOpen;
   if(!g_pl.Create(pls))
      return(INIT_FAILED);

   //--- 模块8：形态识别（涨-回调-涨 / 跌-反弹-跌）
   PatternSettings ptc;
   ptc.Enabled       = InpPatEnabled;
   ptc.X             = InpPatX;
   ptc.Y             = InpPatY;
   ptc.Z             = InpPatZ;
   ptc.MinBodyPoints = (double)InpPatMinBody;
   ptc.AllowLonger   = InpPatAllowLonger;
   if(!g_pat.Create(_Symbol, _Period, ptc))
      return(INIT_FAILED);

   //--- 秒级定时器：为倒计时提供稳定的秒级刷新（网格模块内部自行节流）
   //    注：即使定时器在个别环境下不回调，OnCalculate 每 tick 也会刷新外观层，
   //        只是刷新频率取决于行情节奏（活跃品种通常每秒多次）。
   if(!EventSetTimer(1))
      Print("OnInit: EventSetTimer 失败, err=", GetLastError(),
            " —— 倒计时将退化为仅随 tick 刷新");

   //--- 初始化自检（排查显示问题时先看这行）
   PrintFormat("MySystem v%s init: symbol=%s tf=%s MA=%s(%d/%d %s)",
               "1.44", _Symbol, EnumToString(_Period),
               InpMaEnabled ? "ON" : "OFF", InpMaFast, InpMaSlow,
               EnumToString(InpMaMethod));

   //--- 首次绘制网格线
   g_grid.Update(_Symbol, _Period);

   return(INIT_SUCCEEDED);
  }
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   g_macd.Release();
   g_osc.Release();
   g_rsi.Release();
   g_cd.Release();
   g_grid.Release();
   g_candle.Release();
   g_ma.Release();          // 模块7：未启用时句柄为 INVALID_HANDLE，释放无害
   g_pl.Release();          // 模块2：无内部资源，占位调用
   g_pat.Release();         // 模块8：无内部资源，占位调用
   EventKillTimer();
  }
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
  {
   //--- 预热bar数（与 OnInit 共用同一口径）
   int minBars = WarmupBars();

   //--- ★ 外观层：倒计时 / 网格线，必须在最前面无条件执行
   //    历史故障复盘：这两个 Update 原先排在函数末尾，而函数上半部分散布着
   //    "数据未就绪就 return(0)" 的守卫；只要守卫被触发，本 tick 的倒计时与
   //    网格线就整轮不刷新，表现为"倒计时定格不动 / 只画了一次"。
   //    外观层不依赖任何指标数据，因此提到最前，且永不被后续逻辑短路。
   //    返回值 = 对象是否真的发生变化，只有变化时才重绘（省掉每 tick 的 ChartRedraw）
   bool uiChanged = false;
   uiChanged = g_cd.Update(_Symbol, _Period)   || uiChanged;   // 模块3：倒计时 + 实时价格
   uiChanged = g_grid.Update(_Symbol, _Period) || uiChanged;   // 模块1：网格线（模块内部自行节流）

   //--- ★ 数据层：各模块「启用 + 就绪」互相独立，任一缺席只影响依赖它的信号模式
   bool enough = (rates_total >= minBars);

   //--- 数据完整性：上一轮若未就绪，本轮传 0 让各模块整体重取（历史不得被永久跳过）
   int prevForModules = g_needFull ? 0 : prev_calculated;

   bool cdlOk  = g_candle.Prepare(rates_total, prevForModules);              // 模块6：ATR（可选）
   bool macdOk = InpMacdEnabled && enough && g_macd.Calculate(rates_total, prevForModules); // 模块4
   bool oscOk  = InpOscEnabled  && enough && g_osc.Prepare(rates_total, prevForModules);    // 模块5
   bool rsiOk  = true;
   if(InpMacdEnabled && InpMacdUseRSI)                                       // 模块4b：RSI
      rsiOk = g_rsi.Prepare(rates_total, prevForModules);

   bool maOk = true;
   if(InpMaEnabled)                                                          // 模块7：双均线
      maOk = g_ma.Prepare(rates_total, prevForModules);

   //--- 当前信号模式真正依赖哪些模块（依赖项未就绪 => 本轮不出信号，等下一轮补算）
   bool macdReq = InpMacdEnabled && (InpMode == MODE_MACD || InpMode == MODE_FILTER || InpMode == MODE_MOMENTUM);
   bool oscReq  = InpOscEnabled  && (InpMode == MODE_FILTER || InpMode == MODE_ANY);
   bool rsiReq  = InpMacdEnabled && InpMacdUseRSI && InpMode == MODE_MOMENTUM;

   bool depsOk = (!macdReq || macdOk) && (!oscReq || oscOk) && (!rsiReq || rsiOk);
   bool dataOk = depsOk && cdlOk && maOk;

   //--- 计算起点：需要全量重算时从 0 开始（g_needFull 保证历史不被漏算）
   bool full  = (g_needFull || prev_calculated <= 0 || prev_calculated > rates_total);
   int  start = full ? 0 : prev_calculated - 1;

   //--- 缓冲区清空：纯数组写入，代价极低，必须先于任何分类逻辑
   for(int i = start; i < rates_total; i++)
     {
      CandleOpen[i]  = EMPTY_VALUE;
      CandleHigh[i]  = EMPTY_VALUE;
      CandleLow[i]   = EMPTY_VALUE;
      CandleClose[i] = EMPTY_VALUE;
      CandleColor[i] = 0;
      PatOpen[i]  = EMPTY_VALUE;
      PatHigh[i]  = EMPTY_VALUE;
      PatLow[i]   = EMPTY_VALUE;
      PatClose[i] = EMPTY_VALUE;
      PatColor[i] = 0;
      BufBuy[i]   = EMPTY_VALUE;
      BufSell[i]  = EMPTY_VALUE;
      MaFastBuf[i] = EMPTY_VALUE;   // 均线：每根bar重写，未就绪保持空
      MaSlowBuf[i] = EMPTY_VALUE;
     }

   //--- 模块2：价格折线（高/低/开）—— 仅依赖价格序列，无条件刷新
   g_pl.Fill(start, rates_total, open, high, low, PLHigh, PLLow, PLOpen);

   //--- 数据不全：保留 g_needFull，本轮不写分类/信号，下轮从 0 全量补算
   if(!dataOk)
     {
      g_needFull = true;
      if(uiChanged)
         ChartRedraw(0);
      return(rates_total);
     }

   //--- 5-1 K线着色（模块6，默认关闭；开启时覆盖 [start, rates_total)）
   //    独立于 MACD/Stoch 就绪状态：只要 ATR 就绪即写满，避免新bar出现垃圾值
   if(g_candle.Enabled())
      for(int i = start; i < rates_total; i++)
        {
         //--- 分类（内部顺带处理预警，故须在「是否绘制」判定之前调用）
         int cidx = g_candle.ColorIndex(_Symbol, _Period, i, rates_total, prev_calculated,
                                        open, high, low, close);

         //--- 「不绘制普通K线」时，普通阳/阴线保持 EMPTY_VALUE -> 图表原生K线透出，
         //    仅大实体/大影线等特殊K线写入 OHLC 覆盖显示
         if(g_candle.ShouldDraw(cidx))
           {
            CandleOpen[i]  = open[i];
            CandleHigh[i]  = high[i];
            CandleLow[i]   = low[i];
            CandleClose[i] = close[i];
            CandleColor[i] = cidx;
           }
        }

   //--- 模块7：双均线绘制（plot 7/8；关闭时 plot 已为 DRAW_NONE）
   //    数据由 Prepare() 批量预取，这里只做查表搬运，无 API 调用
   if(InpMaEnabled)
     {
      //--- 首次 / 数组重建 / 历史被补齐时，从最早有效bar整段补画；
      //    否则只补增量区间（避免每tick重写全历史）
      int from = start;
      if(g_ma.TakeFullFill())
        {
         int vf = g_ma.ValidFrom();
         from = (vf > 0) ? vf : 0;
        }
      for(int i = from; i < rates_total; i++)
        {
         double vFast = g_ma.FastAt(i);
         double vSlow = g_ma.SlowAt(i);
         if(vFast > 0.0)
            MaFastBuf[i] = vFast;
         if(vSlow > 0.0)
            MaSlowBuf[i] = vSlow;
        }
     }

   //--- 5-2 形态识别（模块8）：两阶段，仅处理最近 InpPatMaxBars 根窗口
   //    ① 统计「每根bar被多少个形态覆盖」——重叠部分（涨的末端同时是跌的开端等）
   //    ② 统一着色：覆盖1次 -> 主体段按方向(阳绿/阴红) / 回调与小实体灰色
   //                  覆盖>=2   -> 黄色（重叠，含义不确定）
   if(g_pat.Enabled())
     {
      //--- 形态层窗口：只处理最近 InpPatMaxBars 根（内存与绘制量受控）
      //    winStart = 窗口首根；计数数组按【窗口大小】分配，用相对下标 k-winStart 访问
      int patWindow = (InpPatMaxBars > 0) ? InpPatMaxBars : rates_total;
      if(patWindow > rates_total)
         patWindow = rates_total;
      if(patWindow < 1)
         patWindow = 1;
      int winStart = rates_total - patWindow;

      //--- 窗口前移：把滑出窗口的旧bar涂回空，否则会残留历史颜色
      if(g_patWinStart >= 0 && winStart > g_patWinStart)
        {
         int to = (winStart < rates_total) ? winStart : rates_total;
         for(int i = g_patWinStart; i < to; i++)
           {
            PatOpen[i]  = EMPTY_VALUE;
            PatHigh[i]  = EMPTY_VALUE;
            PatLow[i]   = EMPTY_VALUE;
            PatClose[i] = EMPTY_VALUE;
            PatColor[i] = 0;
           }
        }

      //--- 计数数组尺寸：窗口扩张保留旧计数（只清尾部），收缩则整体重建
      if(ArraySize(PatHits) < patWindow)
        {
         int oldN = ArraySize(PatHits);
         ArrayResize(PatHits, patWindow);
         ArrayResize(PatRole, patWindow);
         for(int i = oldN; i < patWindow; i++)
           {
            PatHits[i] = 0;
            PatRole[i] = 0;
           }
        }
      else if(ArraySize(PatHits) != patWindow)
        {
         ArrayResize(PatHits, patWindow);
         ArrayResize(PatRole, patWindow);
         ArrayInitialize(PatHits, 0);
         ArrayInitialize(PatRole, 0);
        }
      else if(g_patWinStart >= 0 && winStart != g_patWinStart)
        {
         //--- 窗口平移：整体左移 d 格，尾部补零（d 通常为 1）
         int d = winStart - g_patWinStart;
         if(d > 0 && d < patWindow)
           {
            for(int i = 0; i < patWindow - d; i++)
              {
               PatHits[i] = PatHits[i + d];
               PatRole[i] = PatRole[i + d];
              }
            for(int i = patWindow - d; i < patWindow; i++)
              {
               PatHits[i] = 0;
               PatRole[i] = 0;
              }
           }
         else
           {
            ArrayInitialize(PatHits, 0);
            ArrayInitialize(PatRole, 0);
           }
        }
      g_patWinStart = winStart;

      //--- 计数复位：全量重算则整表清零；否则只清本轮会重新判定的 [start, end)
      if(full || start <= winStart)
         {
         ArrayInitialize(PatHits, 0);
         ArrayInitialize(PatRole, 0);
         }
      else
         {
         for(int i = start; i < rates_total; i++)
           {
            PatHits[i - winStart] = 0;
            PatRole[i - winStart] = 0;
           }
         }

      int paintFrom = rates_total;         // 本轮需要重画的最小下标

      for(int i = MathMax(start, winStart); i < rates_total; i++)
        {
         if(InpPatOnlyClosed && i == rates_total - 1)   // 未收盘bar不确认，防重绘
            continue;

         int segStart = i, midFrom = i, midTo = i - 1;
         if(g_pat.MatchEndingAt(i, open, close, segStart, midFrom, midTo) == 0)
            continue;

         //--- 段可能跨出窗口（历史部分），裁剪到窗口内
         int kFrom = (segStart > winStart) ? segStart : winStart;
         if(kFrom < paintFrom)
            paintFrom = kFrom;

         //--- 计数：每根bar被几个形态覆盖；首次覆盖时记录其在形态中的角色
         for(int k = kFrom; k <= i; k++)
           {
            int idx = k - winStart;
            PatHits[idx]++;
            if(PatHits[idx] == 1)
               PatRole[idx] = (g_pat.IsIgnoredBar(k, open, close) || (k >= midFrom && k <= midTo)) ? 2 : 1;
           }
        }

      //--- 着色（paintFrom 可能早于增量起点，用于把旧颜色升级成黄色重叠）
      if(paintFrom < winStart)
         paintFrom = winStart;
      for(int k = paintFrom; k < rates_total; k++)
        {
         int idx  = k - winStart;
         int hits = PatHits[idx];
         if(hits <= 0)
            continue;

         int cidx;
         if(hits >= 2)
            cidx = 3;                                   // 重叠 -> 黄
         else if(PatRole[idx] == 2)
            cidx = 2;                                   // 回调段 / 小实体 -> 灰
         else
            cidx = g_pat.ColorIndexOf(k, open, close);  // 主体段 -> 阳绿 / 阴红

         if(PatClose[k] == close[k] && PatColor[k] == cidx)
            continue;                                   // 已是该色，不重复落笔

         PatOpen[k]  = open[k];
         PatHigh[k]  = high[k];
         PatLow[k]   = low[k];
         PatClose[k] = close[k];
         PatColor[k] = cidx;
        }
     }

   //--- 5-3 信号层：依赖模块已由 dataOk 保证就绪，循环内按「当前模式」取数
   //--- 历史不足的bar不出信号（K线着色/形态不受此限制）
   for(int i = MathMax(start, minBars); i < rates_total; i++)
     {
      //--- 防重绘：最右一根未收盘bar不出信号
      if(InpOnlyClosed && i == rates_total - 1)
         continue;

      //--- 取数前先判各模块可用性：关闭/未就绪的模块取 0，绝不去读空的内部数组
      int trend = 0, cross = 0, trig = 0;
      if(macdOk)   // 模块4：MACD方向(柱>0 / <0) + 金叉(+1)/死叉(-1)
        {
         trend = g_macd.TrendState(i);
         cross = g_macd.CrossSignal(i);
        }
      if(oscOk)    // 模块5：震荡触发（内部查已预取的K线表，不再逐bar CopyBuffer）
         trig = g_osc.Signal(i);

      //--- 信号合成：改你的交易规则 = 改这里
      bool buy = false, sell = false;
      switch(InpMode)
        {
         case MODE_FILTER:
            // 依赖 模块5(触发) + 模块4(方向)：任一关闭则 trig/trend 恒为0，自然无信号
            buy  = (trig > 0 && trend > 0);   // 多头趋势中超卖触发 -> 买
            sell = (trig < 0 && trend < 0);   // 空头趋势中超买触发 -> 卖
            break;
         case MODE_ANY:
            // 仅依赖 模块5(触发)：模块5关闭则无信号
            buy  = (trig > 0);
            sell = (trig < 0);
            break;
         case MODE_MACD:
            // 仅依赖 模块4：模块4关闭则 cross 恒为0，无信号
            //--- 主信号：2linemacd 两条线的交叉点（DIF 上穿 DEA 买 / 下穿 DEA 卖）
            buy  = (cross > 0);
            sell = (cross < 0);
            break;
         case MODE_MOMENTUM:
           {
            if(!macdOk)   // 依赖 模块4(柱动量)：关闭或未就绪则不出信号
               break;
            // 动量耗尽：加速段 -> 减速段 -> 反向穿越，只在柱的峰/谷处认信号
            int mom = g_macd.MomentumCross(i, InpMacdRunLen, InpMacdDecelMin, InpMacdLookback);
            if(mom > 0)
               buy  = (!InpMacdUseRSI || (rsiOk && g_rsi.State(i) > 0));   // RSI站队多头才买
            else if(mom < 0)
               sell = (!InpMacdUseRSI || (rsiOk && g_rsi.State(i) < 0));   // RSI站队空头才卖
           }
           break;
        }

      //--- 模块7：双均线方向过滤（默认开启）
      //    只有已出现候选信号时才去取均线值，避免全历史逐bar取数（性能）
      if(InpMaEnabled && (buy || sell))
        {
         int maState = g_ma.TrendState(i);
         if(buy  && maState < 0)   // 双均线空头：丢弃做多候选
            buy = false;
         if(sell && maState > 0)   // 双均线多头：丢弃做空候选
            sell = false;
        }

      if(buy)  BufBuy[i]  = low[i];
      if(sell) BufSell[i] = high[i];
     }

   //--- 全量+所有依赖均就绪：清除「需要全量重算」标记
   g_needFull = false;

   //--- 外观对象（倒计时文本/位置、网格线样式）改动后需一次重绘才会立即显现
   //    注：外观层已在函数开头刷新过，这里只负责"把结果画出来"
   if(uiChanged)
      ChartRedraw(0);

   return(rates_total);
  }
//+------------------------------------------------------------------+
//| Timer 事件：每秒刷新外观层（倒计时/网格线）                         |
//| 注：这是"兜底加速器"而非唯一刷新路径——OnCalculate 每 tick 同样会刷新。 |
//|     两者都保留，任何一条通路失效时外观仍能跟上行情。                 |
//+------------------------------------------------------------------+
void OnTimer()
  {
   bool changed = false;
   changed = g_cd.Update(_Symbol, _Period)   || changed;   // 模块3：每秒刷新
   changed = g_grid.Update(_Symbol, _Period) || changed;   // 模块1：内部节流到设定的更新间隔
   if(changed)
      ChartRedraw(0);
  }
//+------------------------------------------------------------------+
