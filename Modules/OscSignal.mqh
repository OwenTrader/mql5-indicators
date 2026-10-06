//+------------------------------------------------------------------+
//|                                                   OscSignal.mqh  |
//|  模块2：震荡触发模块（Stochastic 超买超卖区穿越触发）              |
//|  示例模块 —— 把你自己的入场触发逻辑替换进 Signal() 即可            |
//+------------------------------------------------------------------+
#ifndef __OSC_SIGNAL_MQH__
#define __OSC_SIGNAL_MQH__

//--- 模块配置体
struct OscSettings
  {
   int      KPeriod;      // %K 周期
   int      DPeriod;      // %D 周期
   int      Slowing;      // 平滑
   double   BuyLevel;     // 超卖阈值
   double   SellLevel;    // 超买阈值
  };

//+------------------------------------------------------------------+
//| 震荡触发模块类                                                    |
//+------------------------------------------------------------------+
class COscModule
  {
private:
   OscSettings        m_cfg;
   int                m_hStoch;

public:
                     COscModule(void) : m_hStoch(INVALID_HANDLE) {}
                    ~COscModule(void) { Release(); }

   //--- 初始化
   bool               Create(const string symbol,const ENUM_TIMEFRAMES tf,const OscSettings &cfg)
     {
      m_cfg    = cfg;
      m_hStoch = iStochastic(symbol, tf, cfg.KPeriod, cfg.DPeriod, cfg.Slowing, MODE_SMA, STO_LOWHIGH);
      if(m_hStoch == INVALID_HANDLE)
        {
         Print(__FUNCTION__, ": 创建Stochastic句柄失败, err=", GetLastError());
         return(false);
        }
      return(true);
     }

   //--- 释放句柄
   void               Release(void)
     {
      if(m_hStoch != INVALID_HANDLE) { IndicatorRelease(m_hStoch); m_hStoch = INVALID_HANDLE; }
     }

   //--- 核心逻辑：返回 +1(买入触发) / -1(卖出触发) / 0(无信号)
   int                Signal(const int index,const int rates_total)
     {
      double k[3], d[3];
      int start = rates_total - 1 - index;
      if(start < 2)                                          // 历史不足
         return(0);
      //--- 取 index-2, index-1, index 三根bar（旧->新排列）
      if(CopyBuffer(m_hStoch, MAIN_LINE,   start, 3, k) < 3)
         return(0);
      if(CopyBuffer(m_hStoch, SIGNAL_LINE, start, 3, d) < 3)
         return(0);
      //--- K线自下而上穿越超卖区 -> 买入触发
      if(k[1] <= m_cfg.BuyLevel && k[2] > m_cfg.BuyLevel)
         return(1);
      //--- K线自上而下穿越超买区 -> 卖出触发
      if(k[1] >= m_cfg.SellLevel && k[2] < m_cfg.SellLevel)
         return(-1);
      //--- 扩展点：可在此加入 K>D 确认、背离检测、多模块投票等逻辑
      return(0);
     }
  };

#endif // __OSC_SIGNAL_MQH__
