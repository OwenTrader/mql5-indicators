//+------------------------------------------------------------------+
//|                                                   Countdown.mqh  |
//|  模块3：K线倒计时模块（OBJ_LABEL 显示剩余时间 + 可选实时价格）       |
//|  由 timer.mq5 提炼而来，接入主指标 MySystem 统一管理                |
//|                                                                  |
//|  设计约定（同 TrendMA / OscSignal）：                              |
//|  · 模块内不定义 input，参数由主指标通过 struct 传入                |
//|  · 模块自管图形对象的创建与删除，主指标只管 Create/Update/Release   |
//|  · 定时器 EventSetTimer/OnTimer 归主指标管理，模块只提供 Update()  |
//+------------------------------------------------------------------+
#ifndef __COUNTDOWN_MQH__
#define __COUNTDOWN_MQH__

//--- 模块配置体
struct CountdownSettings
  {
   bool     Enabled;      // 是否启用倒计时显示
   int      FontSize;     // 字体大小
   color    FontColor;    // 字体颜色
   string   FontName;     // 字体名称（建议等宽字体）
   int      XOffset;      // X轴偏移量(像素)
   int      YOffset;      // Y轴偏移量(像素，越大越往下)
   bool     ShowPrice;    // 是否显示实时价格
   string   Separator;    // 倒计时与价格的分隔符
  };

//+------------------------------------------------------------------+
//| 倒计时模块类                                                      |
//+------------------------------------------------------------------+
class CCountdownModule
  {
private:
   CountdownSettings  m_cfg;
   string             m_label;
   bool               m_created;

public:
                     CCountdownModule(void) : m_label("MySystem_Countdown"), m_created(false) {}
                    ~CCountdownModule(void) { Release(); }

   //--- 初始化：创建标签对象（未启用则直接返回 true）
   bool               Create(const CountdownSettings &cfg)
     {
      m_cfg = cfg;
      if(!m_cfg.Enabled)
         return(true);

      if(!ObjectCreate(0, m_label, OBJ_LABEL, 0, 0, 0))
        {
         Print(__FUNCTION__, ": 创建倒计时标签失败, err=", GetLastError());
         return(false);
        }

      ObjectSetInteger(0, m_label, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, m_label, OBJPROP_ANCHOR, ANCHOR_LEFT_LOWER);
      ObjectSetInteger(0, m_label, OBJPROP_FONTSIZE, m_cfg.FontSize);
      ObjectSetString(0, m_label, OBJPROP_FONT, m_cfg.FontName);
      ObjectSetInteger(0, m_label, OBJPROP_COLOR, m_cfg.FontColor);
      ObjectSetInteger(0, m_label, OBJPROP_BACK, false);
      ObjectSetInteger(0, m_label, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, m_label, OBJPROP_HIDDEN, true);

      m_created = true;
      return(true);
     }

   //--- 释放：删除标签对象
   void               Release(void)
     {
      if(m_created)
        {
         ObjectDelete(0, m_label);
         m_created = false;
        }
     }

   //--- 核心：刷新倒计时与价格文本（由主指标 OnCalculate/OnTimer 调用）
   void               Update(const string symbol,const ENUM_TIMEFRAMES tf)
     {
      if(!m_created)
         return;

      datetime currentTime = TimeCurrent();
      datetime lastBarTime = iTime(symbol, tf, 0);
      if(lastBarTime == 0)
         return;                                   // 数据未准备好

      int periodSecs  = PeriodSeconds(tf);
      datetime barEnd = lastBarTime + periodSecs;

      int remainingSecs = (int)(barEnd - currentTime);
      if(remainingSecs < 0)
         remainingSecs = 0;

      //--- 按周期自动切换格式
      string timeStr;
      int hours = remainingSecs / 3600;
      int mins  = (remainingSecs % 3600) / 60;
      int secs  = remainingSecs % 60;

      if(periodSecs >= 3600)                       // 1小时及以上：时:分:秒
         timeStr = StringFormat("%02d:%02d:%02d", hours, mins, secs);
      else if(periodSecs >= 60)                    // 1~59分钟：分:秒
         timeStr = StringFormat("%02d:%02d", mins, secs);
      else                                         // 秒图等：秒
         timeStr = StringFormat("%02d", secs);

      string displayText = timeStr;

      if(m_cfg.ShowPrice)
        {
         double currentPrice = SymbolInfoDouble(symbol, SYMBOL_BID);
         int    digits       = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
         string priceStr     = DoubleToString(currentPrice, digits);
         displayText = timeStr + m_cfg.Separator + priceStr;
        }

      //--- 锚定到最新K线高点附近
      long chartID = 0;
      int  subWindow = 0;
      datetime t1 = lastBarTime;
      double  p1 = iHigh(symbol, tf, 0);

      int x, y;
      if(ChartTimePriceToXY(chartID, subWindow, t1, p1, x, y))
        {
         ObjectSetInteger(0, m_label, OBJPROP_XDISTANCE, x + m_cfg.XOffset);
         ObjectSetInteger(0, m_label, OBJPROP_YDISTANCE, y - m_cfg.YOffset);
        }

      ObjectSetString(0, m_label, OBJPROP_TEXT, displayText);
     }
  };

#endif // __COUNTDOWN_MQH__
