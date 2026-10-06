//+------------------------------------------------------------------+
//|                                       CandleCountdownWithPrice.mq5 |
//|                                      交易员 & MQL5编程大师出品     |
//+------------------------------------------------------------------+
#property indicator_chart_window
#property indicator_plots 0 // 纯图形对象指标，不绘制缓冲区线条

//--- 输入参数
input int      InpFontSize     = 14;         // 字体大小
input color    InpColor        = clrYellow;  // 字体颜色
input string   InpFontName     = "Consolas"; // 字体名称(建议用等宽字体如Consolas，跳动更平稳)
input int      InpXOffset      = 10;         // X轴偏移量 (像素)
input int      InpYOffset      = 15;         // Y轴偏移量 (像素，越大越往下)
input bool     InpShowPrice    = true;       // 开关：是否显示实时价格
input string   InpSeparator    = "  |  ";    // 倒计时与价格的分隔符

//--- 全局变量
string labelName = "CandleCountdownLabel_OBJ";

//+------------------------------------------------------------------+
//| Custom indicator initialization function                         |
//+------------------------------------------------------------------+
int OnInit()
  {
   // 创建标签对象
   if(!ObjectCreate(0, labelName, OBJ_LABEL, 0, 0, 0))
     {
      Print("创建标签对象失败! 错误代码: ", GetLastError());
      return(INIT_FAILED);
     }

   // 设置标签基本属性
   ObjectSetInteger(0, labelName, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, labelName, OBJPROP_ANCHOR, ANCHOR_LEFT_LOWER); 
   ObjectSetInteger(0, labelName, OBJPROP_FONTSIZE, InpFontSize);
   ObjectSetString(0, labelName, OBJPROP_FONT, InpFontName);
   ObjectSetInteger(0, labelName, OBJPROP_COLOR, InpColor);
   ObjectSetInteger(0, labelName, OBJPROP_BACK, false);
   ObjectSetInteger(0, labelName, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, labelName, OBJPROP_HIDDEN, true);

   // 设置定时器，每秒触发一次 (用于倒计时跳动)
   EventSetTimer(1);

   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Custom indicator deinitialization function                       |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   // 删除标签对象
   ObjectDelete(0, labelName);
   // 关闭定时器
   EventKillTimer();
   // 刷新图表
   ChartRedraw(0);
  }

//+------------------------------------------------------------------+
//| Custom indicator iteration function                              |
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
   // 有Tick更新时也计算一次，确保价格和位置是最新的
   UpdateCountdown();
   return(rates_total);
  }

//+------------------------------------------------------------------+
//| Timer function                                                   |
//+------------------------------------------------------------------+
void OnTimer()
  {
   // 每秒更新倒计时
   UpdateCountdown();
   ChartRedraw(0);
  }

//+------------------------------------------------------------------+
//| 更新倒计时及实时价格显示                                          |
//+------------------------------------------------------------------+
void UpdateCountdown()
  {
   // 获取当前服务器时间和最新K线开盘时间
   datetime currentTime = TimeCurrent();
   datetime lastBarTime = iTime(_Symbol, _Period, 0);

   if(lastBarTime == 0) return; // 数据未准备好则退出

   // 获取当前时间周期的秒数
   int periodSecs = PeriodSeconds(_Period);
   
   // 计算K线结束时间 (开盘时间 + 周期秒数)
   datetime barEndTime = lastBarTime + periodSecs;
   
   // 计算剩余秒数
   int remainingSecs = (int)(barEndTime - currentTime);
   if(remainingSecs < 0) remainingSecs = 0;

   // 格式化剩余时间
   string timeStr;
   int hours = remainingSecs / 3600;
   int mins = (remainingSecs % 3600) / 60;
   int secs = remainingSecs % 60;

   if(periodSecs >= 3600) // 1小时及以上，显示 时:分:秒
     {
      timeStr = StringFormat("%02d:%02d:%02d", hours, mins, secs);
     }
   else if(periodSecs >= 60) // 1分钟到59分钟，显示 分:秒
     {
      timeStr = StringFormat("%02d:%02d", mins, secs);
     }
   else // 秒图等
     {
      timeStr = StringFormat("%02d", secs);
     }

   // 组装最终显示的文本
   string displayText = timeStr;

   // 如果开启了显示实时价格
   if(InpShowPrice)
     {
      // 获取实时买价。如果需要卖价可改为 SYMBOL_ASK
      double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      
      // 关键：处理浮点数精度问题
      // 使用 _Digits 获取当前品种的小数位数(如欧美5位，黄金2位，JP指数3位等)
      // 这样无论什么品种，都能完美显示正确的位数
      string priceStr = DoubleToString(currentPrice, _Digits);
      
      // 拼接： 倒计时 + 分隔符 + 价格
      displayText = timeStr + InpSeparator + priceStr;
     }

   // --- 坐标转换部分 ---
   long chartID = 0;
   int subWindow = 0;
   datetime time1 = lastBarTime;
   double price1 = iHigh(_Symbol, _Period, 0);

   int x, y;
   if(ChartTimePriceToXY(chartID, subWindow, time1, price1, x, y))
     {
      // 锚点设为 ANCHOR_LEFT_LOWER，所以Y轴减去偏移量为向上移动
      ObjectSetInteger(0, labelName, OBJPROP_XDISTANCE, x + InpXOffset);
      ObjectSetInteger(0, labelName, OBJPROP_YDISTANCE, y - InpYOffset);
     }

   // 更新显示文本
   ObjectSetString(0, labelName, OBJPROP_TEXT, displayText);
  }
//+------------------------------------------------------------------+
