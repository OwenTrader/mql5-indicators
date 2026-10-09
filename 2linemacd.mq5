//+------------------------------------------------------------------+
//|                                          DoubleLineMACD.mq5       |
//|                                    Copyright 2025, MetaQuotes    |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025"
#property version   "1.00"
#property indicator_separate_window
#property indicator_buffers 3
#property indicator_plots   3

//--- 柱状图（Histogram：DIF - DEA）
#property indicator_label1  "Histogram"
#property indicator_type1   DRAW_HISTOGRAM
#property indicator_color1  clrSilver
#property indicator_style1  STYLE_SOLID
#property indicator_width1  2

//--- MACD 主线（DIF）
#property indicator_label2  "MACD"
#property indicator_type2   DRAW_LINE
#property indicator_color2  clrDodgerBlue
#property indicator_style2  STYLE_SOLID
#property indicator_width2  1

//--- 信号线（DEA）
#property indicator_label3  "Signal"
#property indicator_type3   DRAW_LINE
#property indicator_color3  clrRed
#property indicator_style3  STYLE_SOLID
#property indicator_width3  1

//--- 输入参数
input int                InpFastEMA     = 12;              // 快速EMA周期
input int                InpSlowEMA     = 26;              // 慢速EMA周期
input int                InpSignalSMA   = 9;               // 信号线周期
input ENUM_APPLIED_PRICE InpAppliedPrice = PRICE_CLOSE;    // 应用价格

//--- 指标缓冲区
double    HistogramBuffer[];   // 柱状图 = MACD主线 - 信号线
double    MacdBuffer[];        // MACD主线（DIF）
double    SignalBuffer[];      // 信号线（DEA）

int       ExtMacdHandle;

//+------------------------------------------------------------------+
//| 自定义指标初始化函数                                               |
//+------------------------------------------------------------------+
int OnInit()
  {
   //--- 绑定指标缓冲区
   SetIndexBuffer(0, HistogramBuffer, INDICATOR_DATA);
   SetIndexBuffer(1, MacdBuffer,      INDICATOR_DATA);
   SetIndexBuffer(2, SignalBuffer,    INDICATOR_DATA);

   //--- 创建 iMACD 指标句柄
   ExtMacdHandle = iMACD(_Symbol, PERIOD_CURRENT,
                         InpFastEMA, InpSlowEMA, InpSignalSMA, InpAppliedPrice);
   if(ExtMacdHandle == INVALID_HANDLE)
     {
      Print("创建 iMACD 句柄失败，错误码: ", GetLastError());
      return(INIT_FAILED);
     }

   //--- 设置指标显示名称
   IndicatorSetString(INDICATOR_SHORTNAME,
                      StringFormat("MACD(%d,%d,%d)", InpFastEMA, InpSlowEMA, InpSignalSMA));

   //--- 设置指标小数位数
   IndicatorSetInteger(INDICATOR_DIGITS, _Digits + 2);

   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| 自定义指标迭代函数                                                 |
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
   //--- 检查指标句柄有效性
   if(ExtMacdHandle == INVALID_HANDLE)
      return(0);

   //--- 确定需要复制的数据量
   int calculated = BarsCalculated(ExtMacdHandle);
   if(calculated <= 0)
     {
      Print("BarsCalculated 返回错误: ", calculated, " 错误码: ", GetLastError());
      return(0);
     }

   int copyBars;
   if(prev_calculated == 0 || calculated != rates_total || rates_total > prev_calculated + 1)
      copyBars = (calculated > rates_total) ? rates_total : calculated;
   else
      copyBars = rates_total - prev_calculated + 1;

   //--- 从 iMACD 缓冲区 0 复制主 MACD 线（DIF）
   if(CopyBuffer(ExtMacdHandle, 0, 0, copyBars, MacdBuffer) < 0)
     {
      Print("复制 MACD 主线数据失败，错误码: ", GetLastError());
      return(0);
     }

   //--- 从 iMACD 缓冲区 1 复制信号线（DEA）
   if(CopyBuffer(ExtMacdHandle, 1, 0, copyBars, SignalBuffer) < 0)
     {
      Print("复制信号线数据失败，错误码: ", GetLastError());
      return(0);
     }

   //--- 计算柱状图 = MACD主线 - 信号线
   for(int i = 0; i < copyBars; i++)
      HistogramBuffer[i] = MacdBuffer[i] - SignalBuffer[i];

   //--- 返回已计算的柱数
   return(rates_total);
  }

//+------------------------------------------------------------------+
//| 自定义指标反初始化函数                                             |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   if(ExtMacdHandle != INVALID_HANDLE)
      IndicatorRelease(ExtMacdHandle);
  }
//+------------------------------------------------------------------+