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
#property version     "1.22"
#property description "模块化交易系统骨架：主指标聚合器"
#property description "主信号：MACD二线交叉(DIF上穿/下穿DEA，与 iMACD / 2linemacd 同口径) + K线着色 + 网格线 + 倒计时"
#property description "备选：震荡(Stoch)触发 / MACD柱动量耗尽确认 / 双均线过滤(可选，默认关闭)"
#property indicator_chart_window
#property indicator_buffers 7
#property indicator_plots   3

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

#include "Modules\MacdTrend.mqh"
#include "Modules\OscSignal.mqh"
#include "Modules\RsiFilter.mqh"
#include "Modules\Countdown.mqh"
#include "Modules\GridLines.mqh"
#include "Modules\BigCandles.mqh"
#include "Modules\TrendMA.mqh"    // 模块6：双均线趋势（可选，默认关闭；参数组在设置页最底部）

//--- 信号组合模式
enum ENUM_SIGNAL_MODE
  {
   MODE_FILTER   = 0,   // 震荡触发 + MACD方向过滤
   MODE_ANY      = 1,   // 仅震荡触发(测试用)
   MODE_MACD     = 2,   // ★MACD二线交叉(DIF上穿/下穿DEA) —— 默认
   MODE_MOMENTUM = 3    // MACD柱动量耗尽确认(加速→减速→反向穿越)
  };

//=== 参数：分组收纳，只在这里暴露可调项 ==============================
input group "══════ 系统设置 ══════"
input ENUM_SIGNAL_MODE InpMode       = MODE_MACD;   // 信号组合模式(默认=MACD二线交叉)
input bool             InpOnlyClosed = true;        // 仅收盘bar出信号(防重绘)

input group "══════ 模块1：MACD 二线交叉(主信号，同 iMACD 口径) ══════"
input int                InpMacdFast     = 12;          // 快线EMA周期
input int                InpMacdSlow     = 26;          // 慢线EMA周期
input int                InpMacdSignal   = 9;           // 信号线DEA周期(SMA平滑，同iMACD)
input ENUM_APPLIED_PRICE InpMacdPrice    = PRICE_CLOSE; // 应用价格
input double             InpMacdHistMult = 1.0;         // 柱放大倍数(1.0=与2linemacd柱值一致)

input group "══════ 模块1b：MACD动量确认(仅 MODE_MOMENTUM 生效) ══════"
input int    InpMacdRunLen    = 6;     // 加速段最少连续柱数
input int    InpMacdDecelMin  = 1;     // 减速段最少连续柱数
input int    InpMacdLookback  = 50;    // 结构最大回看柱数
input bool   InpMacdUseRSI    = false; // 叠加RSI方向过滤(顺势确认，会明显减少信号)
input int    InpMacdRSIPeriod = 14;    // RSI周期(仅上面开关开启时生效)
input double InpMacdRSILevel  = 50.0;  // RSI多空分界

input group "══════ 模块2：震荡(Stoch) ══════"
input int    InpOscK         = 14;    // %K 周期
input int    InpOscD         = 3;     // %D 周期
input int    InpOscSlowing   = 3;     // 平滑
input double InpOscBuyLevel  = 25.0;  // 超卖阈值
input double InpOscSellLevel = 75.0;  // 超买阈值

input group "══════ 模块3：倒计时 ══════"
input bool   InpCdEnabled   = true;        // 启用倒计时显示
input int    InpCdFontSize  = 14;          // 字体大小
input color  InpCdColor     = clrYellow;   // 字体颜色
input string InpCdFontName  = "Consolas";  // 字体名称(建议等宽)
input int    InpCdXOffset   = 10;          // X轴偏移量(像素)
input int    InpCdYOffset   = 15;          // Y轴偏移量(像素，越大越往下)
input bool   InpCdShowPrice = true;        // 显示实时价格
input string InpCdSeparator = "  |  ";     // 倒计时与价格的分隔符

input group "══════ 模块4：网格线 ══════"
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
input bool            InpGridShowEig     = true;              // 显示八分位线条
input color           InpGridEigColor    = clrTeal;           // 八分位颜色
input ENUM_LINE_STYLE InpGridEigStyle    = STYLE_DASHDOTDOT;  // 八分位线型
input int             InpGridEigWidth    = 1;                 // 八分位线宽
input int             InpGridEigFontSize = 10;                // 八分位标签字号
input bool            InpGridShowLabels  = true;              // 显示价格标签
input color           InpGridLabelColor  = clrWhite;          // 标签颜色
input string          InpGridLabelFont   = "Consolas";        // 标签字体

input group "══════ 模块5：K线着色 ══════"
input bool   InpCandleEnabled  = true;               // 启用K线着色
input bool   InpCdlHideNormal  = true;               // 不绘制普通K线(仅高亮特殊K线)
input color  InpCdlBullBody    = clrLime;            // 大实体阳线颜色
input color  InpCdlBearBody    = clrRed;             // 大实体阴线颜色
input color  InpCdlShadowBull  = clrDeepSkyBlue;     // 大下影线K线颜色(偏多)
input color  InpCdlShadowBear  = clrMagenta;         // 大上影线K线颜色(偏空)
input color  InpCdlNormalBull  = clrDarkGreen;       // 普通阳线颜色
input color  InpCdlNormalBear  = clrMaroon;          // 普通阴线颜色
input bool   InpCdlUseATR      = false;              // 使用ATR自适应实体阈值
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
input group "══════ 模块6：双均线趋势(可选，默认关闭) ══════"
input bool               InpMaEnabled = false;          // 启用双均线模块
input int                InpMaFast    = 20;             // 快线周期
input int                InpMaSlow    = 60;             // 慢线周期
input ENUM_MA_METHOD     InpMaMethod  = MODE_EMA;       // 均线算法
input ENUM_APPLIED_PRICE InpMaPrice   = PRICE_CLOSE;    // 应用价格

//--- 模块实例（全局单例）
CMacdModule      g_macd;
COscModule       g_osc;
CRsiFilter       g_rsi;
CCountdownModule g_cd;
CGridModule      g_grid;
CBigCandleModule g_candle;
CTrendModule     g_ma;      // 模块6：双均线（默认未启用，未启用时不创建句柄）

//--- 指标缓冲区
double CandleOpen[];      // 模块5：K线着色 O/H/L/C
double CandleHigh[];
double CandleLow[];
double CandleClose[];
double CandleColor[];     // 模块5：颜色索引(0-5)
double BufBuy[];          // 信号箭头
double BufSell[];

//+------------------------------------------------------------------+
int OnInit()
  {
   //--- 模块5：K线着色缓冲区（plot 0 = DRAW_COLOR_CANDLES）
   SetIndexBuffer(0, CandleOpen,  INDICATOR_DATA);
   SetIndexBuffer(1, CandleHigh,  INDICATOR_DATA);
   SetIndexBuffer(2, CandleLow,   INDICATOR_DATA);
   SetIndexBuffer(3, CandleClose, INDICATOR_DATA);
   SetIndexBuffer(4, CandleColor, INDICATOR_COLOR_INDEX);

   //--- 信号箭头缓冲区（plot 1/2）
   SetIndexBuffer(5, BufBuy,  INDICATOR_DATA);
   SetIndexBuffer(6, BufSell, INDICATOR_DATA);

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

   int minBars = MathMax(InpMacdSlow + InpMacdSignal, InpOscK + InpOscD + InpOscSlowing) + 5;
   if(InpMaEnabled)
      minBars = MathMax(minBars, InpMaSlow + 5);   // 双均线启用时预留其预热区
   PlotIndexSetInteger(1, PLOT_DRAW_BEGIN, minBars);
   PlotIndexSetInteger(2, PLOT_DRAW_BEGIN, minBars);

   IndicatorSetString(INDICATOR_SHORTNAME, "MySystem v1.22");
   IndicatorSetInteger(INDICATOR_DIGITS, _Digits);

   //--- 装配模块：新增模块时在此加一段配置
   MacdSettings mc;
   mc.FastPeriod     = InpMacdFast;
   mc.SlowPeriod     = InpMacdSlow;
   mc.SignalPeriod   = InpMacdSignal;
   mc.Price          = InpMacdPrice;
   mc.HistMultiplier = InpMacdHistMult;
   if(!g_macd.Create(_Symbol, _Period, mc))
      return(INIT_FAILED);

   //--- 模块1b：RSI 过滤器（可选；仅当开关开启时才创建句柄）
   if(InpMacdUseRSI)
     {
      RsiSettings rc;
      rc.Period = InpMacdRSIPeriod;
      rc.Level  = InpMacdRSILevel;
      if(!g_rsi.Create(_Symbol, _Period, rc))
         return(INIT_FAILED);
     }

   OscSettings oc;
   oc.KPeriod   = InpOscK;
   oc.DPeriod   = InpOscD;
   oc.Slowing   = InpOscSlowing;
   oc.BuyLevel  = InpOscBuyLevel;
   oc.SellLevel = InpOscSellLevel;
   if(!g_osc.Create(_Symbol, _Period, oc))
      return(INIT_FAILED);

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

   //--- 模块6：双均线趋势（可选，默认关闭；关闭时不创建句柄，零开销）
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

   //--- 秒级定时器：为倒计时提供稳定的秒级刷新（网格模块内部自行节流）
   //    注：即使定时器在个别环境下不回调，OnCalculate 每 tick 也会刷新外观层，
   //    只是刷新频率取决于行情节奏（活跃品种通常每秒多次）。
   EventSetTimer(1);

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
   g_ma.Release();          // 模块6：未启用时句柄为 INVALID_HANDLE，释放无害
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
   int minBars = MathMax(InpMacdSlow + InpMacdSignal, InpOscK + InpOscD + InpOscSlowing) + 5;
   if(InpMaEnabled)
      minBars = MathMax(minBars, InpMaSlow + 5);

   //--- ★ 外观层：倒计时 / 网格线，必须在最前面无条件执行
   //    历史故障复盘：这两个 Update 原先排在函数末尾，而函数上半部分散布着
   //    "数据未就绪就 return(0)" 的守卫；只要守卫被触发，本 tick 的倒计时与
   //    网格线就整轮不刷新，表现为"倒计时定格不动 / 只画了一次"。
   //    外观层不依赖任何指标数据，因此提到最前，且永不被后续逻辑短路。
   g_cd.Update(_Symbol, _Period);       // 模块3：倒计时 + 实时价格
   g_grid.Update(_Symbol, _Period);     // 模块4：网格线（模块内部自行节流）

   //--- ★ 数据层：就绪与否只影响"信号层"，不再中断整个 OnCalculate
   bool enough = (rates_total >= minBars);
   g_candle.Prepare(rates_total);                                        // 模块5：ATR（可选，未就绪也不影响着色）
   bool macdOk = enough && g_macd.Calculate(rates_total, prev_calculated); // 模块1：三线 MACD
   bool rsiOk  = (!InpMacdUseRSI || g_rsi.Prepare(rates_total, prev_calculated)); // 模块1b：RSI

   //--- 首次计算：清空信号缓冲区，避免历史区出现乱值
   if(prev_calculated == 0)
     {
      ArrayInitialize(BufBuy,  EMPTY_VALUE);
      ArrayInitialize(BufSell, EMPTY_VALUE);
     }

   //--- 增量计算：K线着色需覆盖全部bar，故首次从0开始
   int start = (prev_calculated > 0 && prev_calculated <= rates_total) ? prev_calculated - 1 : 0;

   //--- 5-1 K线着色：独立于 MACD/Stoch 就绪状态，永远写满 [start, rates_total)
   for(int i = start; i < rates_total; i++)
     {
      //--- 模块5：K线着色（每根bar都要写，否则新bar会出现垃圾值）
      //    先全部置 EMPTY_VALUE = 「不绘制」，再按分类决定是否覆盖真实 OHLC
      CandleOpen[i]  = EMPTY_VALUE;
      CandleHigh[i]  = EMPTY_VALUE;
      CandleLow[i]   = EMPTY_VALUE;
      CandleClose[i] = EMPTY_VALUE;
      CandleColor[i] = 0;
      if(g_candle.Enabled())
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

      //--- 信号缓冲区清空
      BufBuy[i]  = EMPTY_VALUE;
      BufSell[i] = EMPTY_VALUE;

     }

   //--- 5-2 信号层：数据未就绪时仅保留上面的着色结果，本轮不合成信号
   if(!macdOk || !rsiOk)
     {
      ChartRedraw(0);
      return(rates_total);
     }

   //--- 历史不足的bar不出信号（K线着色不受此限制，已在上一步写完）
   for(int i = MathMax(start, minBars); i < rates_total; i++)
     {
      //--- 防重绘：最右一根未收盘bar不出信号
      if(InpOnlyClosed && i == rates_total - 1)
         continue;

      int trend = g_macd.TrendState(i);                 // 模块1：MACD方向(柱>0 / <0)
      int cross = g_macd.CrossSignal(i);                // 模块1：MACD金叉(+1)/死叉(-1)
      int trig  = g_osc.Signal(i, rates_total);         // 模块2：触发

      //--- 信号合成：改你的交易规则 = 改这里
      bool buy = false, sell = false;
      switch(InpMode)
        {
         case MODE_FILTER:
            buy  = (trig > 0 && trend > 0);   // 多头趋势中超卖触发 -> 买
            sell = (trig < 0 && trend < 0);   // 空头趋势中超买触发 -> 卖
            break;
         case MODE_ANY:
            buy  = (trig > 0);
            sell = (trig < 0);
            break;
         case MODE_MACD:
            //--- 主信号：2linemacd 两条线的交叉点（DIF 上穿 DEA 买 / 下穿 DEA 卖）
            buy  = (cross > 0);
            sell = (cross < 0);
            break;
         case MODE_MOMENTUM:
           {
            // 动量耗尽：加速段 -> 减速段 -> 反向穿越，只在柱的峰/谷处认信号
            int mom = g_macd.MomentumCross(i, InpMacdRunLen, InpMacdDecelMin, InpMacdLookback);
            if(mom > 0)
               buy  = (!InpMacdUseRSI || g_rsi.State(i) > 0);   // RSI站队多头才买
            else if(mom < 0)
               sell = (!InpMacdUseRSI || g_rsi.State(i) < 0);   // RSI站队空头才卖
           }
           break;
        }

      //--- 模块6：双均线方向过滤（可选，默认关闭）
      //    只有已出现候选信号时才去取均线值，避免全历史逐bar取数（性能）
      if(InpMaEnabled && (buy || sell))
        {
         int maState = g_ma.TrendState(i, rates_total);
         if(buy  && maState < 0)   // 双均线空头：丢弃做多候选
            buy = false;
         if(sell && maState > 0)   // 双均线多头：丢弃做空候选
            sell = false;
        }

      if(buy)  BufBuy[i]  = low[i];
      if(sell) BufSell[i] = high[i];
     }

   //--- 外观对象（倒计时文本/位置、网格线样式）改动后需一次重绘才会立即显现
   //    注：外观层已在函数开头刷新过，这里只负责"把结果画出来"
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
   g_cd.Update(_Symbol, _Period);      // 模块3：每秒刷新
   g_grid.Update(_Symbol, _Period);    // 模块4：内部节流到设定的更新间隔
   ChartRedraw(0);
  }
//+------------------------------------------------------------------+
