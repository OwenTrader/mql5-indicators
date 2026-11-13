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
   double             m_tmp[];  // 拷贝中转（非指标缓冲区禁止直接部分拷贝，见 MacdTrend 文件头）

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
   //    ★ 铁律：CopyBuffer 对「非指标缓冲区」做部分拷贝，会把目标数组压成
   //      「拷贝数量」那么大、且数据落在起始处。必须经中转数组，再按
   //      off = rates_total - copied 对齐回填（与 MacdTrend 同口径）。
   bool               Prepare(const int rates_total,const int prev_calculated)
     {
      if(m_h == INVALID_HANDLE || rates_total <= m_cfg.Period + 1)
         return(false);

      //--- 缓冲区尺寸变化 => 内容失效，强制整体重取
      int prev = prev_calculated;
      if(ArraySize(m_rsi) != rates_total)
        {
         ArrayResize(m_rsi, rates_total);
         prev = 0;
        }

      //--- 不使用 BarsCalculated 硬性拒绝：终端历史尚在加载时它会长期小于
      //    rates_total，硬拒绝会让信号永久空转（同 MacdTrend 的修复口径）
      int need;
      if(prev <= 0 || prev > rates_total)
         need = rates_total;
      else
        {
         need = rates_total - prev + 1;
         if(need < 1)
            need = 1;
        }

      ArrayFree(m_tmp);
      int copied = CopyBuffer(m_h, 0, 0, need, m_tmp);
      if(copied <= 0)
         return(false);

      int off = rates_total - copied;
      if(off < 0)
         return(false);
      for(int k = 0; k < copied; k++)
         m_rsi[off + k] = m_tmp[k];

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
