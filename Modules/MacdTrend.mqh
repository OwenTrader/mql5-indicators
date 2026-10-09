//+------------------------------------------------------------------+
//|                                                   MacdTrend.mqh  |
//|  模块1：趋势模块（MACD 二线交叉 —— 与 2linemacd.mq5 完全同口径）   |
//|                                                                  |
//|  ★ 口径说明（改动前务必先读）★                                     |
//|  本模块直接引用 MT5 内置 iMACD 的两条缓冲，不做任何自算：           |
//|    · buffer 0 = DIF = EMA(fast) - EMA(slow)       （走势线）        |
//|    · buffer 1 = DEA = SMA(DIF, signal)            （信号线）        |
//|  即"二线 MACD"：DIF 与 SMA(DIF,9)。                                |
//|  与 2linemacd.mq5 / Examples\MACD.mq5 / MT5 自带 MACD 窗口          |
//|  逐点一致，金叉/死叉的时点完全重合。                                |
//|                                                                  |
//|  与"标准三线 MACD"的区别（不要混用）：                              |
//|    标准三线 = DIF + DEA(EMA(DIF,9)) + 柱(DIF-DEA)×2                 |
//|    因信号线平滑口径不同（EMA vs SMA），两者的金叉/死叉在时点与价位  |
//|    上都不同。本项目按使用者要求统一采用上面的 iMACD 口径。           |
//|                                                                  |
//|  金叉 = DIF 上穿 DEA（DIF-DEA 由 ≤0 变 >0）                        |
//|  死叉 = DIF 下穿 DEA（DIF-DEA 由 ≥0 变 <0）                        |
//|                                                                  |
//|  柱 = (DIF - DEA) × 倍数；默认倍数 1.0，与 2linemacd 的柱值一致。   |
//|  柱状态（4色，供动量确认使用）：                                    |
//|    柱>0 且较前值放大 → 红  (多头动能增强)                           |
//|    柱>0 且较前值缩小 → 粉  (多头动能衰减)                           |
//|    柱<0 且较前值放大 → 绿  (空头动能增强)                           |
//|    柱<0 且较前值缩小 → 浅绿(空头动能衰减)                           |
//|                                                                  |
//|  动量耗尽信号 MomentumCross()：                                    |
//|    加速段(红/绿，连续 runLen 根) → 减速段(粉/浅绿，连续 decelMin 根) |
//|    → 反向穿越。即只在"柱的峰/谷"处才认交叉，过滤掉柱刚出现小凹坑     |
//|    就反向穿越的假信号。                                            |
//|                                                                  |
//|  ★ 取数铁律（曾在此踩坑，勿改）★                                   |
//|  CopyBuffer() 对【非指标缓冲区】做部分拷贝时：                      |
//|    · 接收的动态数组会被改成"拷贝数量"那么大                        |
//|    · 数据落在数组起始处，不是尾部                                  |
//|  官方文档明确要求：非指标缓冲区做部分拷贝必须经【中转数组】，        |
//|  再逐元素写到目标数组的对应位置。本模块用 m_tmpDif/m_tmpDea 遵循。  |
//|  若直接拷进按图表索引对齐的全长数组，增量拷贝(1根)会把数组压成 1 个  |
//|  元素，随后 array[i] (i=rates_total-1) 越界，OnCalculate 会中途中断， |
//|  导致排在后面的着色/倒计时/网格线全部不执行（"只画一次"）。          |
//|                                                                  |
//|  设计约定：                                                       |
//|  · 模块内不定义 input，参数由主指标通过 struct 传入（防参数爆炸）   |
//|  · 模块自管句柄的创建与释放，主指标只管 Create/调用/整体释放        |
//+------------------------------------------------------------------+
#ifndef __MACD_TREND_MQH__
#define __MACD_TREND_MQH__

//--- 模块配置体
struct MacdSettings
  {
   int                FastPeriod;     // 快线 EMA 周期
   int                SlowPeriod;     // 慢线 EMA 周期
   int                SignalPeriod;   // 信号线 DEA 周期（SMA 平滑，同 iMACD）
   ENUM_APPLIED_PRICE Price;          // 应用价格
   double             HistMultiplier; // 柱放大倍数（默认 1.0 = 与 2linemacd 柱值一致）
  };

//--- 柱状态（4色）
enum ENUM_MACD_HIST
  {
   MACD_HIST_RED    = 0,   // 柱>0 且放大：多头动能增强
   MACD_HIST_PINK   = 1,   // 柱>0 且缩小：多头动能衰减
   MACD_HIST_GREEN  = 2,   // 柱<0 且放大：空头动能增强
   MACD_HIST_LGREEN = 3    // 柱<0 且缩小：空头动能衰减
  };

//+------------------------------------------------------------------+
//| 二线 MACD 模块类（iMACD 口径）                                     |
//+------------------------------------------------------------------+
class CMacdModule
  {
private:
   MacdSettings       m_cfg;
   int                m_hMacd;      // iMACD 句柄（buffer0=DIF, buffer1=DEA）
   int                m_begin;      // DIF 首个可信 bar（慢线 EMA 收敛后）
   int                m_firstDea;   // DEA 首个有效 bar（信号线 SMA 预热后）
   int                m_validFrom;  // 首个有效图表索引（小于此值无数据）
   double             m_dif[];      // DIF 序列（按图表索引对齐：0=最老）
   double             m_dea[];      // DEA 序列
   double             m_hist[];     // 柱  = (DIF - DEA) × 倍数
   double             m_tmpDif[];   // DIF 拷贝中转（见文件头"取数铁律"）
   double             m_tmpDea[];   // DEA 拷贝中转

public:
                     CMacdModule(void) : m_hMacd(INVALID_HANDLE),
                                         m_begin(0), m_firstDea(0), m_validFrom(0) {}
                    ~CMacdModule(void) { Release(); }

   //--- 初始化：创建 iMACD 句柄
   bool               Create(const string symbol,const ENUM_TIMEFRAMES tf,const MacdSettings &cfg)
     {
      m_cfg = cfg;
      if(cfg.FastPeriod < 1 || cfg.SlowPeriod < 2 || cfg.SignalPeriod < 1)
        {
         Print(__FUNCTION__, ": MACD 周期参数非法");
         return(false);
        }
      m_hMacd = iMACD(symbol, tf, cfg.FastPeriod, cfg.SlowPeriod, cfg.SignalPeriod, cfg.Price);
      if(m_hMacd == INVALID_HANDLE)
        {
         Print(__FUNCTION__, ": 创建 iMACD 句柄失败, err=", GetLastError());
         return(false);
        }
      //--- 慢线 EMA 需 SlowPeriod 根才收敛；DIF 自其后才可信
      //    信号线是 DIF 的 SMA(signal)，再预热 signal-1 根
      m_begin     = cfg.SlowPeriod - 1;
      m_firstDea  = m_begin + cfg.SignalPeriod - 1;
      m_validFrom = 0;
      return(true);
     }

   //--- 释放句柄
   void               Release(void)
     {
      if(m_hMacd != INVALID_HANDLE) { IndicatorRelease(m_hMacd); m_hMacd = INVALID_HANDLE; }
     }

   //--- 批量计算：DIF / DEA / 柱 三条线（主循环内只查表）
   //    返回 false = 本轮数据不足以计算（只影响信号层，调用方不得据此中断整轮刷新）
   bool               Calculate(const int rates_total,const int prev_calculated)
     {
      if(rates_total <= m_begin + 1)
         return(false);

      //--- 1. 终端为句柄算好了多少根？只作为"可用窗口"依据，不做硬性拒绝
      //    注意：BarsCalculated 可能长期略小于 rates_total（历史还在加载），
      //    旧实现据此 return(false) 会让整轮 OnCalculate 空转，故改为"有多少算多少"
      int ready = BarsCalculated(m_hMacd);
      if(ready <= m_begin + 1)
         return(false);

      int n         = MathMin(ready, rates_total);   // 本次可对齐的最新 n 根
      int validFrom = rates_total - n;               // 图表索引 < validFrom 无有效数据

      //--- 2. 缓冲区按图表索引对齐扩容（0=最老，rates_total-1=最新）
      if(ArraySize(m_dif) != rates_total)
        {
         ArrayResize(m_dif,  rates_total);
         ArrayResize(m_dea,  rates_total);
         ArrayResize(m_hist, rates_total);
        }

      //--- 3. 只取需要的尾部（首轮/历史变动/可用量变化则全量）
      bool full = (prev_calculated <= 0 || prev_calculated > rates_total || validFrom != m_validFrom);
      int  need = full ? n : (rates_total - prev_calculated + 1);
      if(need > n) need = n;
      if(need < 1) need = 1;

      //--- 4. 经中转数组取数（铁律：非指标缓冲区不可直接做部分拷贝）
      ArrayFree(m_tmpDif);
      ArrayFree(m_tmpDea);
      int copied = CopyBuffer(m_hMacd, 0, 0, need, m_tmpDif);   // buffer0 = DIF
      if(copied <= 0)
         return(false);
      if(CopyBuffer(m_hMacd, 1, 0, need, m_tmpDea) <= 0)       // buffer1 = DEA(SMA)
         return(false);

      int off = rates_total - copied;
      if(off < 0)
         return(false);
      for(int k = 0; k < copied; k++)
        {
         m_dif[off + k] = m_tmpDif[k];
         m_dea[off + k] = m_tmpDea[k];
        }

      m_validFrom = validFrom;

      //--- 5. 柱 = (DIF - DEA) × 倍数（默认 1.0，即 2linemacd 的柱值）
      int hStart = MathMax(off, m_firstDea);
      for(int i = hStart; i < rates_total; i++)
         m_hist[i] = (m_dif[i] - m_dea[i]) * m_cfg.HistMultiplier;

      return(true);
     }

   //--- 数据是否就绪
   bool               Ready(const int index)
     {
      return(index >= m_firstDea && index >= m_validFrom && index < ArraySize(m_dif));
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
   //    这就是 2linemacd 副图上两条线的交叉点
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

   //--- 柱状态（4色）：返回 ENUM_MACD_HIST；-1 = 数据未就绪
   //    注意：用 (DIF-DEA) 原始值比较，不走 m_hist，避免放大倍数为 0/负时失真
   int                HistColor(const int index)
     {
      if(index < 1 || !Ready(index) || !Ready(index - 1))
         return(-1);
      double q     = m_dif[index]     - m_dea[index];
      double qPrev = m_dif[index - 1] - m_dea[index - 1];
      if(q > 0.0)
         return((q > qPrev) ? MACD_HIST_RED   : MACD_HIST_PINK);
      if(q < 0.0)
         return((q < qPrev) ? MACD_HIST_GREEN : MACD_HIST_LGREEN);
      return((qPrev > 0.0) ? MACD_HIST_PINK : MACD_HIST_LGREEN);
     }

   //--- 动量耗尽型交叉：加速段 → 减速段 → 反向穿越
   //    index      : 当前 bar（穿越确认 bar）
   //    runLen     : 加速段最少连续柱数
   //    decelMin   : 减速段最少连续柱数
   //    maxLookback: 结构最大回看柱数
   //    返回 +1 金叉买入 / -1 死叉卖出 / 0 不构成信号
   int                MomentumCross(const int index,int runLen,int decelMin,int maxLookback)
     {
      int cross = CrossSignal(index);
      if(cross == 0)
         return(0);

      if(runLen   < 1) runLen   = 1;
      if(decelMin < 1) decelMin = 1;
      if(maxLookback < runLen + decelMin)
         maxLookback = runLen + decelMin;

      //--- 穿越前的柱符号：金叉前为负(绿)，死叉前为正(红)
      int accelColor, decelColor;
      if(cross > 0)
        {
         accelColor = MACD_HIST_GREEN;
         decelColor = MACD_HIST_LGREEN;
        }
      else
        {
         accelColor = MACD_HIST_RED;
         decelColor = MACD_HIST_PINK;
        }

      int limit = index - 1 - maxLookback;    // 回看下界（0 = 序列起点）
      if(limit < 0)
         limit = 0;

      //--- 从穿越前一根起，先数"减速段"，再数紧邻其前的"加速段"
      int j     = index - 1;
      int decel = 0;
      int run   = 0;

      while(j >= limit && HistColor(j) == decelColor)
        {
         decel++;
         j--;
        }
      if(decel < decelMin)
         return(0);

      while(j >= limit && HistColor(j) == accelColor)
        {
         run++;
         j--;
        }
      if(run < runLen)
         return(0);

      return(cross);
     }

   //--- 三条线只读访问（供主指标扩展或核对）
   double             DifAt(const int index)  { return(index >= 0 && index < ArraySize(m_dif))  ? m_dif[index]  : 0.0; }
   double             DeaAt(const int index)  { return(index >= 0 && index < ArraySize(m_dea))  ? m_dea[index]  : 0.0; }
   double             HistAt(const int index) { return(index >= 0 && index < ArraySize(m_hist)) ? m_hist[index] : 0.0; }
  };

#endif // __MACD_TREND_MQH__
