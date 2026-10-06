//+------------------------------------------------------------------+
//|                                                     TrendMA.mqh  |
//|  模块1：趋势模块（双均线多空状态过滤）                             |
//|  示例模块 —— 把你自己的趋势判断逻辑替换进 TrendState() 即可        |
//|                                                                  |
//|  设计约定：                                                       |
//|  · 模块内不定义 input，参数由主指标通过 struct 传入（防参数爆炸）   |
//|  · 模块自管句柄的创建与释放，主指标只管 Create/调用/整体释放        |
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
//| 趋势模块类                                                        |
//+------------------------------------------------------------------+
class CTrendModule
  {
private:
   TrendSettings      m_cfg;
   int                m_hFast;
   int                m_hSlow;

public:
                     CTrendModule(void) : m_hFast(INVALID_HANDLE), m_hSlow(INVALID_HANDLE) {}
                    ~CTrendModule(void) { Release(); }

   //--- 初始化：创建内部指标句柄
   bool               Create(const string symbol,const ENUM_TIMEFRAMES tf,const TrendSettings &cfg)
     {
      m_cfg   = cfg;
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

   //--- 核心逻辑：返回 +1(多头) / -1(空头) / 0(数据未就绪)
   //    index = 主指标OnCalculate中正在计算的bar（非序列索引）
   int                TrendState(const int index,const int rates_total)
     {
      double fast[2], slow[2];
      int start = rates_total - 1 - index;   // index 距最新bar的年龄
      if(start < 0)
         return(0);
      //--- CopyBuffer 固定按"旧->新"排列：fast[0]=index-1, fast[1]=index
      if(CopyBuffer(m_hFast, 0, start, 2, fast) < 2)
         return(0);
      if(CopyBuffer(m_hSlow, 0, start, 2, slow) < 2)
         return(0);
      //--- 扩展点：可在此加入均线斜率、ATR过滤、多周期共振等你的逻辑
      if(fast[1] > slow[1])
         return(1);
      if(fast[1] < slow[1])
         return(-1);
      return(0);
     }
  };

#endif // __TREND_MA_MQH__
