//+------------------------------------------------------------------+
//|                                                  RsiFilter.mqh   |
//|  模块：RSI 方向过滤器（可选，供动量类信号做顺势确认）              |
//|                                                                  |
//|  口径说明（取自参考策略 MACD_Color_EA）：                          |
//|    · 做多放行条件：RSI >= Level（默认 50）                         |
//|    · 做空放行条件：RSI <  Level                                    |
//|  即"信号方向必须已被 RSI 站队确认"，属于顺势过滤，会明显减少信号量。|
//|                                                                  |
//|  设计约定同其他模块：                                              |
//|  · 不定义 input，参数由主指标通过 struct 传入                      |
//|  · 模块自管句柄的创建与释放                                        |
//|  · 增量取数：仿 MacdTrend，只在新增bar时补拷                        |
//+------------------------------------------------------------------+
#ifndef __RSI_FILTER_MQH__
#define __RSI_FILTER_MQH__

//--- 模块配置体
struct RsiSettings
  {
   int                Period;   // RSI 周期
   double             Level;    // 多空分界（默认 50.0）
  };

//+------------------------------------------------------------------+
//| RSI 过滤模块类                                                     |
//+------------------------------------------------------------------+
class CRsiFilter
  {
private:
   RsiSettings        m_cfg;
   int                m_h;      // RSI 句柄
   double             m_rsi[];  // RSI 序列（与主循环同序：索引 0 = 最老）

public:
                     CRsiFilter(void) : m_h(INVALID_HANDLE) {}
                    ~CRsiFilter(void) { Release(); }

   //--- 初始化：创建 RSI 句柄
   bool               Create(const string symbol,const ENUM_TIMEFRAMES tf,const RsiSettings &cfg)
     {
      m_cfg = cfg;
      if(cfg.Period < 2)
        {
         Print(__FUNCTION__, ": RSI 周期非法");
         return(false);
        }
      m_h = iRSI(symbol, tf, cfg.Period, PRICE_CLOSE);
      if(m_h == INVALID_HANDLE)
        {
         Print(__FUNCTION__, ": 创建 RSI 句柄失败, err=", GetLastError());
         return(false);
        }
      return(true);
     }

   //--- 释放句柄
   void               Release(void)
     {
      if(m_h != INVALID_HANDLE)
        {
         IndicatorRelease(m_h);
         m_h = INVALID_HANDLE;
        }
     }

   //--- 增量取数（未就绪返回 false，调用方等待下个Tick即可）
   bool               Prepare(const int rates_total,const int prev_calculated)
     {
      if(m_h == INVALID_HANDLE || rates_total <= m_cfg.Period + 1)
         return(false);

      if(ArraySize(m_rsi) != rates_total)
         ArrayResize(m_rsi, rates_total);

      //--- 句柄历史未算够时等待
      if(BarsCalculated(m_h) < rates_total)
         return(false);

      int to_copy;
      if(prev_calculated <= 0 || prev_calculated > rates_total)
         to_copy = rates_total;                                 // 首次/历史被截断：整体重取
      else
        {
         to_copy = rates_total - prev_calculated;
         if(prev_calculated > 0)
            to_copy++;
        }
      if(to_copy <= 0)
         return(true);

      if(CopyBuffer(m_h, 0, 0, to_copy, m_rsi) <= 0)
         return(false);

      return(true);
     }

   //--- 方向状态：+1 RSI>=Level（放行做多）/ -1 RSI<Level（放行做空）/ 0 未就绪
   int                State(const int index)
     {
      if(index < m_cfg.Period + 1 || index >= ArraySize(m_rsi))
         return(0);
      if(m_rsi[index] >= m_cfg.Level)
         return(1);
      return(-1);
     }

   //--- 只读访问（供主指标核对/扩展）
   double             RsiAt(const int index)
     {
      return(index >= 0 && index < ArraySize(m_rsi)) ? m_rsi[index] : 0.0;
     }
  };

#endif // __RSI_FILTER_MQH__
