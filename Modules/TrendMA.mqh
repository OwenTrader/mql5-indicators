//+------------------------------------------------------------------+
//|                                                     TrendMA.mqh  |
//|  模块7：双均线（方向过滤 + 两条均线绘制）                            |
//|                                                                  |
//|  v1.41 变更：                                                     |
//|   · 新增 Prepare() 批量增量预取 fast/slow 两条序列（原实现每个候选     |
//|     信号都要两次 CopyBuffer，且数值无法用于绘图）                     |
//|   · 新增 FastAt()/SlowAt()，供主指标写入均线绘图缓冲区（plot 7/8）     |
//|   · TrendState() 改为纯查表，不再调用任何 API                        |
//|                                                                  |
//|  设计约定：                                                       |
//|  · 模块内不定义 input，参数由主指标通过 struct 传入（防参数爆炸）     |
//|  · 模块自管句柄的创建与释放，主指标只管 Create/调用/整体释放          |
//|  · 绘图缓冲区归主指标所有，模块只提供数值                            |
//+------------------------------------------------------------------+
#ifndef __TREND_MA_MQH__
#define __TREND_MA_MQH__

//--- 模块配置体
struct TrendSettings
  {
   int                FastPeriod;   // 快线周期
   int                SlowPeriod;   // 慢线周期
   ENUM_MA_METHOD     Method;       // 均线算法
   ENUM_APPLIED_PRICE Price;        // 应用价格
  };

//+------------------------------------------------------------------+
//| 双均线模块类                                                      |
//+------------------------------------------------------------------+
class CTrendModule
  {
private:
   TrendSettings      m_cfg;
   int                m_hFast;
   int                m_hSlow;
   double             m_fast[];     // 快线序列（索引0=最老，与主循环同序）
   double             m_slow[];     // 慢线序列
   double             m_tmpF[];     // 拷贝中转（非指标缓冲区禁止直接部分拷贝）
   double             m_tmpS[];
   int                m_validFrom;  // 【曾】覆盖到的最早有效下标（跨越多轮保留，-1=尚无数据）
   bool               m_resized;    // 本轮是否因数组重建而整体重取
   bool               m_needFullFill;// 有一批更早的bar刚变有效 -> 下一轮需整段补画
   bool               m_logged;     // 首次就绪日志只打一次

   //--- 单条均线的增量取数：返回实际拷贝根数（0=失败）
   int                FillSeries(const int handle,const int rates_total,const int prev_calculated,
                                 double &dst[],double &tmp[])
     {
      if(handle == INVALID_HANDLE)
         return(0);

      int prev = prev_calculated;
      if(ArraySize(dst) != rates_total)
        {
         ArrayResize(dst, rates_total);
         prev = 0;                       // 尺寸变化 => 内容失效，整体重取
         m_resized = true;
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

      ArrayFree(tmp);
      int copied = CopyBuffer(handle, 0, 0, need, tmp);
      if(copied <= 0)
         return(0);

      int off = rates_total - copied;
      if(off < 0)
         return(0);
      for(int k = 0; k < copied; k++)
         dst[off + k] = tmp[k];

      return(copied);
     }

public:
                     CTrendModule(void) : m_hFast(INVALID_HANDLE), m_hSlow(INVALID_HANDLE),
                                          m_validFrom(-1), m_resized(false), m_needFullFill(false), m_logged(false) {}
                    ~CTrendModule(void) { Release(); }

   //--- 初始化：创建内部指标句柄
   bool               Create(const string symbol,const ENUM_TIMEFRAMES tf,const TrendSettings &cfg)
     {
      m_cfg = cfg;
      if(cfg.FastPeriod < 1 || cfg.SlowPeriod < 1)
        {
         Print(__FUNCTION__, ": 均线周期非法");
         return(false);
        }
      if(cfg.FastPeriod >= cfg.SlowPeriod)
         Print(__FUNCTION__, ": 提示 快线周期(", cfg.FastPeriod, ") >= 慢线周期(", cfg.SlowPeriod,
               ")，方向过滤意义有限");

      m_hFast = iMA(symbol, tf, cfg.FastPeriod, 0, cfg.Method, cfg.Price);
      m_hSlow = iMA(symbol, tf, cfg.SlowPeriod, 0, cfg.Method, cfg.Price);
      if(m_hFast == INVALID_HANDLE || m_hSlow == INVALID_HANDLE)
        {
         Print(__FUNCTION__, ": 创建均线句柄失败, err=", GetLastError());
         return(false);
        }
      return(true);
     }

   //--- 释放句柄
   void               Release(void)
     {
      if(m_hFast != INVALID_HANDLE) { IndicatorRelease(m_hFast); m_hFast = INVALID_HANDLE; }
      if(m_hSlow != INVALID_HANDLE) { IndicatorRelease(m_hSlow); m_hSlow = INVALID_HANDLE; }
     }

   bool               Enabled(void) const { return(m_hFast != INVALID_HANDLE && m_hSlow != INVALID_HANDLE); }

   //--- 批量增量预取两条均线（返回 false = 本轮数据不足）
   bool               Prepare(const int rates_total,const int prev_calculated)
     {
      if(m_hFast == INVALID_HANDLE || m_hSlow == INVALID_HANDLE)
         return(false);

      m_resized = false;

      int cf = FillSeries(m_hFast, rates_total, prev_calculated, m_fast, m_tmpF);
      if(cf <= 0)
         return(false);
      int cs = FillSeries(m_hSlow, rates_total, prev_calculated, m_slow, m_tmpS);
      if(cs <= 0)
         return(false);

      //--- ★ 有效区间必须【跨轮累积】：增量轮只拷贝尾部，若每轮都把 validFrom
      //    重置成 rates_total-1，刚收盘的那根（start=rates_total-2）就会被判为
      //    无效而跳过写入，表现为均线每隔一根断一次（甚至整条不出现）。
      int off = rates_total - MathMin(cf, cs);
      if(m_resized || m_validFrom < 0)
        {
         m_validFrom    = off;
         m_needFullFill = true;         // 数组重建/首次：整段重画
        }
      else if(off < m_validFrom)
        {
         m_validFrom    = off;          // 历史被补齐：更早的bar现在有效
         m_needFullFill = true;
        }

      if(!m_logged)
        {
         m_logged = true;
         PrintFormat("TrendMA: first ready fast=%d/%d slow=%d/%d validFrom=%d (rates_total=%d)",
                     m_cfg.FastPeriod, cf, m_cfg.SlowPeriod, cs, m_validFrom, rates_total);
        }
      return(true);
     }

   //--- 曾覆盖到的最早有效下标（-1 = 尚无数据）
   int                ValidFrom(void) const { return(m_validFrom); }

   //--- 取出并清除「需要整段补画」标志（只生效一次）
   bool               TakeFullFill(void)
     {
      bool need = m_needFullFill;
      m_needFullFill = false;
      return(need);
     }

   //--- 方向状态：+1 多头 / -1 空头 / 0 未就绪（纯查表，无 API 调用）
   int                TrendState(const int index)
     {
      if(index < 0 || index < m_validFrom)
         return(0);
      if(index >= ArraySize(m_fast) || index >= ArraySize(m_slow))
         return(0);
      if(m_fast[index] > m_slow[index])
         return(1);
      if(m_fast[index] < m_slow[index])
         return(-1);
      return(0);
     }

   //--- 只读访问（供主指标写绘图缓冲区）：未就绪返回 0
   double             FastAt(const int index)
     {
      return(index >= m_validFrom && index < ArraySize(m_fast)) ? m_fast[index] : 0.0;
     }
   double             SlowAt(const int index)
     {
      return(index >= m_validFrom && index < ArraySize(m_slow)) ? m_slow[index] : 0.0;
     }
  };

#endif // __TREND_MA_MQH__
