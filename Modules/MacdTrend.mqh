//+------------------------------------------------------------------+
//|                                                   MacdTrend.mqh  |
//|  模块1：趋势模块（标准三线 MACD）                                  |
//|                                                                  |
//|  ★ 与 MT5 内置 MACD 的关键区别（不要混用）★                        |
//|  MT5 内置 MACD（iMACD / Examples\MACD.mq5）：                      |
//|    · 绘图 = 【DIF 柱】 + 【SMA(DIF,9) 信号线】，没有标准 MACD 柱    |
//|    · 即"双线"：DIF 与 SMA(DIF,9)                                   |
//|  本模块（标准三线）：                                              |
//|    · DIF = EMA(fast, 价格) - EMA(slow, 价格)                       |
//|    · DEA = EMA(DIF, signal)      ← 信号线用 EMA 平滑，非 SMA        |
//|    · 柱  = (DIF - DEA) × 倍数     ← 标准 MACD 柱                   |
//|  因信号线平滑口径不同（EMA vs SMA），金叉/死叉的时点与价位均不同。  |
//|                                                                  |
//|  金叉 = DIF 上穿 DEA（柱由负转正）                                  |
//|  死叉 = DIF 下穿 DEA（柱由正转负）                                  |
//|                                                                  |
//|  设计约定：                                                       |
//|  · 模块内不定义 input，参数由主指标通过 struct 传入（防参数爆炸）   |
//|  · 模块自管句柄的创建与释放，主指标只管 Create/调用/整体释放        |
//|  · 三条线全部模块内自算，不使用 iMACD，口径可逐行核对               |
//+------------------------------------------------------------------+
#ifndef __MACD_TREND_MQH__
#define __MACD_TREND_MQH__

//--- 模块配置体
struct MacdSettings
  {
   int                FastPeriod;     // 快线 EMA 周期
   int                SlowPeriod;     // 慢线 EMA 周期
   int                SignalPeriod;   // 信号线 DEA 周期（EMA 平滑）
   ENUM_APPLIED_PRICE Price;          // 应用价格
   double             HistMultiplier; // MACD 柱放大倍数（国内惯例 2.0，仅影响柱高度）
  };

//+------------------------------------------------------------------+
//| 三线 MACD 模块类                                                   |
//+------------------------------------------------------------------+
class CMacdModule
  {
private:
   MacdSettings       m_cfg;
   int                m_hFast;      // 快线 EMA 句柄
   int                m_hSlow;      // 慢线 EMA 句柄
   int                m_begin;      // DIF 首个可信 bar（慢线 EMA 收敛后）
   int                m_firstDea;   // DEA 首个有效 bar
   double             m_fast[];     // 快线 EMA 序列
   double             m_slow[];     // 慢线 EMA 序列
   double             m_dif[];      // DIF = fast - slow
   double             m_dea[];      // DEA = EMA(DIF, signal)
   double             m_hist[];     // 柱  = (DIF - DEA) × 倍数

   //--- 全量重算 DEA：前 SignalPeriod 个有效 DIF 用 SMA 播种（经典口径），其后 EMA 递推
   void               RecalcDeaAll(const int rates_total)
     {
      for(int i = 0; i < rates_total; i++)
         m_dea[i] = 0.0;

      int n = m_cfg.SignalPeriod;
      if(m_firstDea >= rates_total || n <= 0)
         return;

      double sum = 0.0;
      for(int i = m_begin; i < m_begin + n; i++)
         sum += m_dif[i];
      m_dea[m_firstDea] = sum / n;

      double k = 2.0 / (1.0 + n);
      for(int i = m_firstDea + 1; i < rates_total; i++)
         m_dea[i] = m_dif[i] * k + m_dea[i - 1] * (1.0 - k);
     }

public:
                     CMacdModule(void) : m_hFast(INVALID_HANDLE), m_hSlow(INVALID_HANDLE),
                                         m_begin(0), m_firstDea(0) {}
                    ~CMacdModule(void) { Release(); }

   //--- 初始化：创建快/慢 EMA 句柄
   bool               Create(const string symbol,const ENUM_TIMEFRAMES tf,const MacdSettings &cfg)
     {
      m_cfg = cfg;
      if(cfg.FastPeriod < 1 || cfg.SlowPeriod < 2 || cfg.SignalPeriod < 1)
        {
         Print(__FUNCTION__, ": MACD 周期参数非法");
         return(false);
        }
      m_hFast = iMA(symbol, tf, cfg.FastPeriod, 0, MODE_EMA, cfg.Price);
      m_hSlow = iMA(symbol, tf, cfg.SlowPeriod, 0, MODE_EMA, cfg.Price);
      if(m_hFast == INVALID_HANDLE || m_hSlow == INVALID_HANDLE)
        {
         Print(__FUNCTION__, ": 创建EMA句柄失败, err=", GetLastError());
         return(false);
        }
      //--- 慢线 EMA 需 SlowPeriod 根才收敛，DIF 自其后才可信
      m_begin    = cfg.SlowPeriod - 1;
      m_firstDea = m_begin + cfg.SignalPeriod - 1;
      return(true);
     }

   //--- 释放句柄
   void               Release(void)
     {
      if(m_hFast != INVALID_HANDLE) { IndicatorRelease(m_hFast); m_hFast = INVALID_HANDLE; }
      if(m_hSlow != INVALID_HANDLE) { IndicatorRelease(m_hSlow); m_hSlow = INVALID_HANDLE; }
     }

   //--- 批量计算：DIF / DEA / 柱 三条线（每根bar一次，主循环内只查表）
   bool               Calculate(const int rates_total,const int prev_calculated)
     {
      if(rates_total <= m_firstDea)
         return(false);

      //--- 缓冲区按需扩容
      if(ArraySize(m_fast) != rates_total)
        {
         ArrayResize(m_fast, rates_total);
         ArrayResize(m_slow, rates_total);
         ArrayResize(m_dif,  rates_total);
         ArrayResize(m_dea,  rates_total);
         ArrayResize(m_hist, rates_total);
        }

      //--- 句柄历史是否已算够（不够则本次不计算，等下一Tick）
      if(BarsCalculated(m_hFast) < rates_total)
         return(false);
      if(BarsCalculated(m_hSlow) < rates_total)
         return(false);

      //--- 取快/慢 EMA（引擎句柄，数值与图表 iMA 一致）
      int to_copy;
      if(prev_calculated > rates_total || prev_calculated < 0)
         to_copy = rates_total;                                  // 历史被截断/异常：整体重取
      else
        {
         to_copy = rates_total - prev_calculated;
         if(prev_calculated > 0)
            to_copy++;
        }
      if(CopyBuffer(m_hFast, 0, 0, to_copy, m_fast) <= 0)
         return(false);
      if(CopyBuffer(m_hSlow, 0, 0, to_copy, m_slow) <= 0)
         return(false);

      //--- DIF = fast - slow
      int start = (prev_calculated > 0 && prev_calculated <= rates_total)
                  ? prev_calculated - 1 : 0;
      for(int i = start; i < rates_total; i++)
         m_dif[i] = m_fast[i] - m_slow[i];

      //--- DEA = EMA(DIF, signal)；起点早于播种点时必须整体重算
      if(prev_calculated <= 0 || start <= m_firstDea)
         RecalcDeaAll(rates_total);
      else
        {
         double k = 2.0 / (1.0 + m_cfg.SignalPeriod);
         for(int i = start; i < rates_total; i++)
            m_dea[i] = m_dif[i] * k + m_dea[i - 1] * (1.0 - k);
        }

      //--- 标准 MACD 柱 = (DIF - DEA) × 倍数
      int hStart = (start > m_firstDea) ? start : m_firstDea;
      for(int i = hStart; i < rates_total; i++)
         m_hist[i] = (m_dif[i] - m_dea[i]) * m_cfg.HistMultiplier;

      return(true);
     }

   //--- 数据是否就绪
   bool               Ready(const int index)
     {
      return(index >= m_firstDea && index < ArraySize(m_dif));
     }

   //--- 方向状态：+1 DIF在DEA上方(柱>0) / -1 DIF在DEA下方(柱<0) / 0 未就绪
   int                TrendState(const int index)
     {
      if(!Ready(index))
         return(0);
      if(m_dif[index] > m_dea[index])
         return(1);
      if(m_dif[index] < m_dea[index])
         return(-1);
      return(0);
     }

   //--- 金叉/死叉：+1 DIF上穿DEA（柱由负转正）/ -1 DIF下穿DEA（柱由正转负）/ 0 无
   int                CrossSignal(const int index)
     {
      if(index < 1 || !Ready(index) || !Ready(index - 1))
         return(0);
      double prev = m_dif[index - 1] - m_dea[index - 1];
      double cur  = m_dif[index]     - m_dea[index];
      if(prev <= 0.0 && cur > 0.0)
         return(1);                       // 金叉
      if(prev >= 0.0 && cur < 0.0)
         return(-1);                      // 死叉
      return(0);
     }

   //--- 三条线只读访问（供主指标扩展或核对）
   double             DifAt(const int index)  { return(index >= 0 && index < ArraySize(m_dif))  ? m_dif[index]  : 0.0; }
   double             DeaAt(const int index)  { return(index >= 0 && index < ArraySize(m_dea))  ? m_dea[index]  : 0.0; }
   double             HistAt(const int index) { return(index >= 0 && index < ArraySize(m_hist)) ? m_hist[index] : 0.0; }
  };

#endif // __MACD_TREND_MQH__
