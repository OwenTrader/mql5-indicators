//+------------------------------------------------------------------+
//|                                                   OscSignal.mqh  |
//|  模块5：震荡触发模块（Stochastic 超买超卖区穿越触发）              |
//|  示例模块 —— 把你自己的入场触发逻辑替换进 Signal() 即可            |
//|                                                                  |
//|  性能说明（v1.29 重构）：                                          |
//|  旧实现在 Signal() 内逐 bar 调 CopyBuffer(…,3,…)，全历史首算时      |
//|  10 万根bar ≈ 20 万次 API 调用，加载明显卡顿，且数据未就绪时静默    |
//|  返回 0（表现为「历史信号凭空消失」）。现改为 Prepare() 批量增量    |
//|  预取到内部数组，Signal() 只查表，与 MacdTrend 同口径。             |
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
   double             m_k[];      // %K 序列（索引 0 = 最老，与主循环同序）
   double             m_d[];      // %D 序列（暂未参与判定，留作扩展）
   double             m_tmpK[];   // 拷贝中转（非指标缓冲区禁止直接部分拷贝）
   double             m_tmpD[];
   int                m_validFrom;// 首个有效图表索引

public:
                     COscModule(void) : m_hStoch(INVALID_HANDLE), m_validFrom(0) {}
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

   //--- 批量增量预取（返回 false = 本轮数据不足，调用方等下一轮）
   bool               Prepare(const int rates_total,const int prev_calculated)
     {
      if(m_hStoch == INVALID_HANDLE)
         return(false);
      if(rates_total <= m_cfg.KPeriod + m_cfg.DPeriod + m_cfg.Slowing + 2)
         return(false);

      int prev = prev_calculated;
      if(ArraySize(m_k) != rates_total)
        {
         ArrayResize(m_k, rates_total);
         ArrayResize(m_d, rates_total);
         prev = 0;                       // 尺寸变化 => 内容失效，整体重取
        }

      int need;
      if(prev <= 0 || prev > rates_total)
         need = rates_total;
      else
        {
         need = rates_total - prev + 1;
         if(need < 1)
            need = 1;
        }

      ArrayFree(m_tmpK);
      ArrayFree(m_tmpD);
      int ck = CopyBuffer(m_hStoch, MAIN_LINE,   0, need, m_tmpK);
      if(ck <= 0)
         return(false);
      int cd = CopyBuffer(m_hStoch, SIGNAL_LINE, 0, need, m_tmpD);
      if(cd <= 0)
         return(false);

      int copied = MathMin(ck, cd);
      int off    = rates_total - copied;
      if(off < 0)
         return(false);
      for(int k = 0; k < copied; k++)
        {
         m_k[off + k] = m_tmpK[k];
         m_d[off + k] = m_tmpD[k];
        }

      m_validFrom = off;
      return(true);
     }

   //--- 核心逻辑：返回 +1(买入触发) / -1(卖出触发) / 0(无信号)
   //    只查已预取的数组，无任何 API 调用
   int                Signal(const int index)
     {
      if(index < 1 || index >= ArraySize(m_k) || index <= m_validFrom)
         return(0);
      //--- K线自下而上穿越超卖区 -> 买入触发
      if(m_k[index - 1] <= m_cfg.BuyLevel && m_k[index] > m_cfg.BuyLevel)
         return(1);
      //--- K线自上而下穿越超买区 -> 卖出触发
      if(m_k[index - 1] >= m_cfg.SellLevel && m_k[index] < m_cfg.SellLevel)
         return(-1);
      //--- 扩展点：可在此加入 K>D 确认、背离检测、多模块投票等逻辑
      return(0);
     }

   //--- 只读访问（供核对/扩展）
   double             KAt(const int index) { return(index >= 0 && index < ArraySize(m_k)) ? m_k[index] : 0.0; }
   double             DAt(const int index) { return(index >= 0 && index < ArraySize(m_d)) ? m_d[index] : 0.0; }
  };

#endif // __OSC_SIGNAL_MQH__
