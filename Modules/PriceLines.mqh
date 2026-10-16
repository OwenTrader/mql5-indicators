//+------------------------------------------------------------------+
//|                                                  PriceLines.mqh  |
//|  模块7：价格折线模块（最高价 / 最低价 / 开盘价 三条折线，可独立开关）|
//|                                                                  |
//|  实现方式：指标缓冲区 + DRAW_LINE（折线）—— 随价格序列逐bar连线。   |
//|   · 每条折线用一个独立 plot（plot3/4/5，缓冲区 7/8/9）             |
//|   · 关闭某条线时，主指标把该 plot 设为 DRAW_NONE（完全不绘制）      |
//|   · 缓冲区写入由本模块 Fill() 统一负责，关闭时写 EMPTY_VALUE 双保险 |
//|                                                                  |
//|  设计约定（同其他模块）：                                          |
//|  · 模块内不定义 input，参数由主指标通过 struct 传入                 |
//|  · 模块不持有图形对象/指标句柄，只负责「源价格 -> 目标缓冲区」搬运   |
//|  · plot 属性（颜色/线宽/线型/DRAW_NONE）由主指标 OnInit 按参数设置  |
//+------------------------------------------------------------------+
#ifndef __PRICE_LINES_MQH__
#define __PRICE_LINES_MQH__

//--- 模块配置体
struct PriceLineSettings
  {
   bool             Enabled;      // 模块总开关
   bool             ShowHigh;     // 绘制最高价折线
   bool             ShowLow;      // 绘制最低价折线
   bool             ShowOpen;     // 绘制开盘价折线
  };

//+------------------------------------------------------------------+
//| 价格折线模块类                                                    |
//+------------------------------------------------------------------+
class CPriceLineModule
  {
private:
   PriceLineSettings m_cfg;

public:
                     CPriceLineModule(void)
     {
      m_cfg.Enabled  = false;
      m_cfg.ShowHigh = false;
      m_cfg.ShowLow  = false;
      m_cfg.ShowOpen = false;
     }
                    ~CPriceLineModule(void) {}

   //--- 初始化：仅保存配置（本模块无需句柄/对象，恒成功）
   bool               Create(const PriceLineSettings &cfg)
     {
      m_cfg = cfg;
      return(true);
     }

   //--- 释放：无内部资源（保留接口以统一调用约定）
   void               Release(void) {}

   //--- 状态查询：总开关 + 单条开关（供主指标决定 plot 是否 DRAW_NONE）
   bool               Enabled(void)  const { return(m_cfg.Enabled);  }
   bool               ShowHigh(void) const { return(m_cfg.Enabled && m_cfg.ShowHigh); }
   bool               ShowLow(void)  const { return(m_cfg.Enabled && m_cfg.ShowLow);  }
   bool               ShowOpen(void) const { return(m_cfg.Enabled && m_cfg.ShowOpen); }

   //--- 逐bar把源价格写入目标缓冲区
   //    开启的线写真实价格；关闭的线写 EMPTY_VALUE（配合 DRAW_NONE 双保险）
   //    start/rates_total 采用主指标 OnCalculate 的同一增量口径
   void               Fill(const int start,const int rates_total,
                           const double &open[],const double &high[],const double &low[],
                           double &bufHigh[],double &bufLow[],double &bufOpen[])
     {
      int from = (start > 0) ? start : 0;
      for(int i = from; i < rates_total; i++)
        {
         bufHigh[i] = ShowHigh() ? high[i] : EMPTY_VALUE;
         bufLow[i]  = ShowLow()  ? low[i]  : EMPTY_VALUE;
         bufOpen[i] = ShowOpen() ? open[i] : EMPTY_VALUE;
        }
     }
  };

#endif // __PRICE_LINES_MQH__
