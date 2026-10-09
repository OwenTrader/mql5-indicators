//+------------------------------------------------------------------+
//|                                                  BigCandles.mqh  |
//|  模块5：K线着色模块（大实体/大影线/普通K线 6色分类 + ATR自适应）     |
//|  由 candle.mq5 (BigBodyCandles) 提炼而来，接入主指标 MySystem       |
//|                                                                  |
//|  可选：HideNormalCandles=true（默认开）时不绘制普通K线，             |
//|        只高亮特殊K线（大实体/大影线），普通K线交由图表原生绘制，      |
//|        避免指标重复覆盖原生K线。                                    |
//|                                                                  |
//|  设计约定（同 TrendMA / OscSignal）：                              |
//|  · 模块内不定义 input，参数由主指标通过 struct 传入                |
//|  · 模块自管 ATR 句柄的创建与释放                                   |
//|  · 绘图缓冲区(O/H/L/C/Color)归主指标所有，模块只计算颜色索引        |
//|    （DRAW_COLOR_CANDLES 需要主指标声明 plot，模块无法独立绑定）     |
//+------------------------------------------------------------------+
#ifndef __BIGCANDLES_MQH__
#define __BIGCANDLES_MQH__

//--- K线分类（同时是颜色索引，对应主指标 plot0 的 6 个颜色槽）
enum ENUM_CANDLE_TYPE
  {
   CANDLE_BULL_BODY   = 0,   // 大实体阳线
   CANDLE_BEAR_BODY   = 1,   // 大实体阴线
   CANDLE_BULL_SHADOW = 2,   // 大下影线（偏多）
   CANDLE_BEAR_SHADOW = 3,   // 大上影线（偏空）
   CANDLE_NORMAL_BULL = 4,   // 普通阳线
   CANDLE_NORMAL_BEAR = 5    // 普通阴线
  };

//--- 模块配置体
struct CandleSettings
  {
   bool     Enabled;              // 启用K线着色
   bool     HideNormalCandles;    // 不绘制普通K线(仅高亮特殊K线，原生K线透出)
   color    BullBodyColor;        // 大实体阳线
   color    BearBodyColor;        // 大实体阴线
   color    ShadowBullColor;      // 大下影线（偏多）
   color    ShadowBearColor;      // 大上影线（偏空）
   color    NormalBullColor;      // 普通阳线
   color    NormalBearColor;      // 普通阴线
   bool     UseATRForBody;        // 使用ATR自适应实体阈值
   double   BodyATRMultiplier;    // ATR倍数
   int      ATRPeriod;            // ATR周期
   int      M1MinBody;            // M1最小实体点数
   int      M5MinBody;            // M5最小实体点数
   int      M15MinBody;           // M15最小实体点数
   int      M30MinBody;           // M30最小实体点数
   int      H1MinBody;            // H1最小实体点数
   int      H4MinBody;            // H4最小实体点数
   int      D1MinBody;            // D1最小实体点数
   bool     ShowShadowCandles;    // 显示大影线K线
   int      M30MinShadow;         // M30最小单边影线点数
   int      H1MinShadow;          // H1最小单边影线点数
   int      H4MinShadow;          // H4最小单边影线点数
   int      D1MinShadow;          // D1最小单边影线点数
   bool     FilterShadowByBodyRatio; // 过滤实体过大的影线K线
   double   MaxBodyShadowRatio;   // 最大实体/影线比例(%)
   bool     EnableAlerts;         // 开启预警
   bool     AlertOnBigBody;       // 大实体K线预警
   bool     AlertOnBigShadow;     // 大影线K线预警
   bool     ShowDebugInfo;        // 显示调试信息
  };

//+------------------------------------------------------------------+
//| K线着色模块类                                                     |
//+------------------------------------------------------------------+
class CBigCandleModule
  {
private:
   CandleSettings   m_cfg;
   int              m_atr;          // ATR句柄
   double           m_atrBuf[];     // ATR数据（旧->新，与OnCalculate数组同向）
   double           m_point;        // 品种点值
   int              m_minBodyPts;   // 当前周期实体阈值(点)
   int              m_minShadowPts; // 当前周期影线阈值(点)

   //--- 获取最接近的标准时间框架的点数阈值
   int                GetDynamicPoints(const int m1,const int m5,const int m15,const int m30,
                                       const int h1,const int h4,const int d1,
                                       const ENUM_TIMEFRAMES tf) const
     {
      int minutes = PeriodSeconds(tf) / 60;
      if(minutes <= 1)   return(m1);
      if(minutes <= 5)   return(m5);
      if(minutes <= 15)  return(m15);
      if(minutes <= 30)  return(m30);
      if(minutes <= 60)  return(h1);
      if(minutes <= 240) return(h4);
      return(d1);       // W1, MN1
     }

public:
                     CBigCandleModule(void) : m_atr(INVALID_HANDLE), m_point(0),
                                             m_minBodyPts(0), m_minShadowPts(0) {}
                    ~CBigCandleModule(void) { Release(); }

   bool               Enabled(void) const { return(m_cfg.Enabled); }

   //--- 该颜色索引对应的K线是否应当绘制（主指标据此决定是否写入 OHLC 缓冲区）
   //    HideNormalCandles=true 时，普通阳/阴线不写 OHLC -> 终端按 PLOT_EMPTY_VALUE
   //    规则跳过绘制，图上保留原生K线，仅特殊K线以高亮色覆盖。
   bool               ShouldDraw(const int colorIndex) const
     {
      if(!m_cfg.HideNormalCandles)
         return(true);
      return(colorIndex != CANDLE_NORMAL_BULL && colorIndex != CANDLE_NORMAL_BEAR);
     }

   //--- 初始化：点值、周期阈值、ATR句柄
   //    注：图表周期切换会导致指标重新初始化，无需运行中检查周期
   bool               Create(const string symbol,const ENUM_TIMEFRAMES tf,const CandleSettings &cfg)
     {
      m_cfg = cfg;
      if(!m_cfg.Enabled)
         return(true);

      m_point = SymbolInfoDouble(symbol, SYMBOL_POINT);
      if(m_point <= 0)
         return(false);

      m_minBodyPts = GetDynamicPoints(m_cfg.M1MinBody, m_cfg.M5MinBody, m_cfg.M15MinBody,
                                      m_cfg.M30MinBody, m_cfg.H1MinBody, m_cfg.H4MinBody,
                                      m_cfg.D1MinBody, tf);
      m_minShadowPts = GetDynamicPoints(0, 0, 0, m_cfg.M30MinShadow, m_cfg.H1MinShadow,
                                        m_cfg.H4MinShadow, m_cfg.D1MinShadow, tf);

      if(m_cfg.UseATRForBody)
        {
         m_atr = iATR(symbol, tf, m_cfg.ATRPeriod);
         if(m_atr == INVALID_HANDLE)
            return(false);
        }

      if(m_cfg.ShowDebugInfo)
        {
         Print("=== MySystem/BigCandles 模块初始化 ===");
         Print("当前品种: ", symbol, " | 时间框架: ", EnumToString(tf));
         Print("实体阈值: ", m_minBodyPts, " 点 | 影线阈值: ", m_minShadowPts, " 点");
         Print("ATR自适应: ", m_cfg.UseATRForBody ? "开启" : "关闭");
        }

      return(true);
     }

   //--- 释放ATR句柄
   void               Release(void)
     {
      if(m_atr != INVALID_HANDLE)
        {
         IndicatorRelease(m_atr);
         m_atr = INVALID_HANDLE;
        }
     }

   //--- 每轮计算前调用：拷贝ATR数据（返回false=数据未就绪，等待下轮）
   bool               Prepare(const int rates_total)
     {
      if(!m_cfg.Enabled || !m_cfg.UseATRForBody || m_atr == INVALID_HANDLE)
         return(true);

      if(ArraySize(m_atrBuf) < rates_total)
         ArrayResize(m_atrBuf, rates_total);

      //--- 索引0为最老数据，方向与 OnCalculate 的 open/close 一致
      if(CopyBuffer(m_atr, 0, 0, rates_total, m_atrBuf) <= 0)
         return(false);

      return(true);
     }

   //--- 核心：计算第 i 根K线的颜色索引（内部顺带处理预警）
   int                ColorIndex(const string symbol,const ENUM_TIMEFRAMES tf,const int i,
                                 const int rates_total,const int prev_calculated,
                                 const double &open[],const double &high[],
                                 const double &low[],const double &close[])
     {
      double body_size_pts = MathAbs(close[i] - open[i]) / m_point;
      bool   is_bull       = (close[i] > open[i]);

      //--- 默认普通K线
      int result = is_bull ? CANDLE_NORMAL_BULL : CANDLE_NORMAL_BEAR;

      //--- 1. 大实体判断
      bool   is_big_body = false;
      double dynamic_body_thresh_pts = (double)m_minBodyPts;

      if(m_cfg.UseATRForBody && i < ArraySize(m_atrBuf) && m_atrBuf[i] > 0)
         dynamic_body_thresh_pts = (m_atrBuf[i] * m_cfg.BodyATRMultiplier) / m_point;

      if(body_size_pts >= dynamic_body_thresh_pts)
        {
         is_big_body = true;
         result = is_bull ? CANDLE_BULL_BODY : CANDLE_BEAR_BODY;
        }

      //--- 2. 大影线判断（未判定为大实体时）
      if(m_cfg.ShowShadowCandles && !is_big_body)
        {
         double upper_shadow = high[i] - MathMax(open[i], close[i]);
         double lower_shadow = MathMin(open[i], close[i]) - low[i];
         double upper_pts    = upper_shadow / m_point;
         double lower_pts    = lower_shadow / m_point;

         bool is_big_upper = (upper_pts >= m_minShadowPts);
         bool is_big_lower = (lower_pts >= m_minShadowPts);

         //--- 实体/影线比例过滤
         if(m_cfg.FilterShadowByBodyRatio)
           {
            double total_shadow_pts = upper_pts + lower_pts;
            if(total_shadow_pts > 0)
              {
               double ratio = (body_size_pts / total_shadow_pts) * 100.0;
               if(ratio >= m_cfg.MaxBodyShadowRatio)
                 {
                  is_big_upper = false;
                  is_big_lower = false;
                 }
              }
           }

         if(is_big_upper && !is_big_lower)
            result = CANDLE_BEAR_SHADOW;          // 大上影偏空
         else if(is_big_lower && !is_big_upper)
            result = CANDLE_BULL_SHADOW;          // 大下影偏多
         else if(is_big_upper && is_big_lower)
            result = is_bull ? CANDLE_BULL_SHADOW : CANDLE_BEAR_SHADOW;
        }

      //--- 3. 预警（仅对最新完成的K线触发一次）
      if(m_cfg.EnableAlerts && i == rates_total - 2 && i > prev_calculated - 1)
        {
         if((m_cfg.AlertOnBigBody && is_big_body) ||
            (m_cfg.AlertOnBigShadow && (result == CANDLE_BULL_SHADOW || result == CANDLE_BEAR_SHADOW)))
           {
            string type_str = "";
            if(result == CANDLE_BULL_BODY)        type_str = "大实体阳线";
            else if(result == CANDLE_BEAR_BODY)   type_str = "大实体阴线";
            else if(result == CANDLE_BULL_SHADOW) type_str = "大下影线";
            else if(result == CANDLE_BEAR_SHADOW) type_str = "大上影线";
            Alert(symbol, " ", EnumToString(tf), " 出现: ", type_str);
           }
        }

      return(result);
     }
  };

#endif // __BIGCANDLES_MQH__
