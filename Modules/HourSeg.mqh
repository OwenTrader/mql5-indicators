//+------------------------------------------------------------------+
//|                                                    HourSeg.mqh   |
//|  模块9：H1 收盘价水平线段                                          |
//|                                                                  |
//|  规则：                                                           |
//|   · 只在图表周期 < 30 分钟（M1/M2/M5/M15 等）时启用；M30 及以上不画  |
//|   · 每个小时段画一条水平线：                                       |
//|       起点 x = 该小时首根低周期K线的开盘时间（= 对应 H1 的开盘时间）  |
//|       终点 x = 起点 + SpanMinutes 分钟（默认 60 = 1 小时）           |
//|       价格 y = 该小时【之前】那根已完成 H1 的收盘价                  |
//|   · PerBar=true 时改为「每根低周期K线各画一条」：                    |
//|       起点 = 该K线自身开盘时间，长度同上，y = 所属小时的上一根H1收盘价 |
//|                                                                  |
//|  实现约定：                                                       |
//|   · 用图表对象 OBJ_TREND（水平、不向右侧延伸）表示固定长度线段        |
//|     —— 指标缓冲区无法表达「只画一段」，DRAW_LINE 会连成整条线        |
//|   · 对象名 MSHS_<ChartID>_<t0>：同图表多实例互不干扰                 |
//|   · 套用模板会连同对象一起复制，Create 时清理「同族但非本实例」的遗留   |
//|   · 刷新由主指标 OnCalculate / OnTimer 驱动，内部按「最新bar未变则跳过」|
//+------------------------------------------------------------------+
#ifndef __HOURSEG_MQH__
#define __HOURSEG_MQH__

//--- 模块配置体
struct HourSegSettings
  {
   bool             Enabled;        // 启用（且周期 < 30min 才生效）
   int              SpanMinutes;    // 线段长度（分钟），默认 60
   int              MaxLines;       // 最多保留条数（0 = 不限，慎用）
   bool             PerBar;         // true=每根K线各画一条；false=每小时一条
   color            LineColor;      // 线段颜色
   ENUM_LINE_STYLE  LineStyle;      // 线型
   int              LineWidth;      // 线宽(1-5)
  };

//+------------------------------------------------------------------+
//| H1 收盘价水平线段模块                                             |
//+------------------------------------------------------------------+
class CHourSegModule
  {
private:
   HourSegSettings    m_cfg;
   string             m_prefix;      // 对象名前缀（含 ChartID）
   datetime           m_lastBar;     // 上次同步时最新低周期bar的时间
   bool               m_styleDirty;  // 需重套样式（参数变更后）
   bool               m_offCleared;  // 周期不符/关闭时已清场（避免每轮全表扫描）

   //--- 本轮需求列表（复用成员数组，避免每轮分配）
   string             m_reqName[];
   datetime           m_reqT0[];
   double             m_reqPrice[];

   //--- 周期门槛：严格小于 30 分钟
   bool               Eligible(const ENUM_TIMEFRAMES tf) const
     {
      return(PeriodSeconds(tf) < 1800);
     }

   //--- 样式（OBJ_TREND 水平线段：两端同价、不向右延伸）
   void               ApplyStyle(const string name)
     {
      ObjectSetInteger(0, name, OBJPROP_COLOR,      m_cfg.LineColor);
      ObjectSetInteger(0, name, OBJPROP_STYLE,      m_cfg.LineStyle);
      ObjectSetInteger(0, name, OBJPROP_WIDTH,      m_cfg.LineWidth);
      ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT,  false);
      ObjectSetInteger(0, name, OBJPROP_RAY_LEFT,   false);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN,     true);
      ObjectSetInteger(0, name, OBJPROP_BACK,       true);   // 画在K线下方
     }

   //--- 需求条目
   void               AddReq(const string name,const datetime t0,const double price)
     {
      int n = ArraySize(m_reqName);
      if(n >= ArraySize(m_reqT0))
        {
         ArrayResize(m_reqT0, n + 64);
         ArrayResize(m_reqPrice, n + 64);
        }
      ArrayResize(m_reqName, n + 1);
      m_reqName[n]  = name;
      m_reqT0[n]    = t0;
      m_reqPrice[n] = price;
     }

   //--- 创建/更新一条线段；返回 true = 图形有实际变化
   bool               Upsert(const string name,const datetime t0,const datetime t1,const double price)
     {
      bool changed = false;

      if(ObjectFind(0, name) < 0)
        {
         if(!ObjectCreate(0, name, OBJ_TREND, 0, t0, price, t1, price))
            return(false);
         ApplyStyle(name);
         return(true);
        }

      datetime ct0 = (datetime)ObjectGetInteger(0, name, OBJPROP_TIME, 0);
      datetime ct1 = (datetime)ObjectGetInteger(0, name, OBJPROP_TIME, 1);
      double   cp0 = ObjectGetDouble(0, name, OBJPROP_PRICE, 0);
      if(ct0 != t0 || ct1 != t1 || MathAbs(cp0 - price) > _Point * 0.5)
        {
         ObjectMove(0, name, 0, t0, price);
         ObjectMove(0, name, 1, t1, price);
         changed = true;
        }

      if(m_styleDirty)
         ApplyStyle(name);

      return(changed);
     }

   //--- 删除本实例全部对象；返回 true = 删过东西
   bool               DeleteOwn(void)
     {
      bool any = false;
      for(int i = ObjectsTotal(0, 0, -1) - 1; i >= 0; i--)
        {
         string name = ObjectName(0, i, 0, -1);
         if(StringFind(name, m_prefix) != 0)
            continue;
         if(ObjectDelete(0, name))
            any = true;
        }
      return(any);
     }

   //--- 清理「同族但非本实例」的遗留（模板套用到其他图表后 ChartID 不匹配）
   int                CleanupForeign(void)
     {
      int removed = 0;
      for(int i = ObjectsTotal(0, 0, -1) - 1; i >= 0; i--)
        {
         string name = ObjectName(0, i, 0, -1);
         if(StringFind(name, "MSHS_") != 0)
            continue;
         if(StringFind(name, m_prefix) == 0)
            continue;
         if(ObjectDelete(0, name))
            removed++;
        }
      return(removed);
     }

   //--- 构建需求列表（每小时一条 / 每根bar一条）
   bool               BuildRequired(const string symbol,const ENUM_TIMEFRAMES tf)
     {
      ArrayResize(m_reqName, 0);
      int maxN = (m_cfg.MaxLines > 0) ? m_cfg.MaxLines : 100000;

      if(!m_cfg.PerBar)
        {
         //--- 每小时一条：H1 序列，最后一条是当前未完成的小时
         int need = maxN + 1;
         datetime ht[];
         double   hc[];
         int ct = CopyTime(symbol, PERIOD_H1, 0, need, ht);
         int cc = CopyClose(symbol, PERIOD_H1, 0, need, hc);
         if(ct <= 1 || cc <= 1)
            return(false);

         ArraySetAsSeries(ht, true);
         ArraySetAsSeries(hc, true);

         int n = MathMin(maxN, MathMin(ct, cc) - 1);
         for(int k = 0; k < n; k++)
           {
            datetime t0 = ht[k];
            double   y  = hc[k + 1];              // 该小时之前那根已完成 H1 的收盘价
            if(t0 == 0 || y <= 0.0)
               continue;
            AddReq(m_prefix + IntegerToString((long)t0), t0, y);
           }
         return(true);
        }

      //--- 每根低周期K线一条：起点 = 该K线自身开盘时间
      datetime bt[];
      int cb = CopyTime(symbol, tf, 0, maxN, bt);
      if(cb <= 0)
         return(false);
      ArraySetAsSeries(bt, true);

      for(int b = 0; b < cb; b++)
        {
         datetime tb = bt[b];
         if(tb == 0)
            continue;
         int h = iBarShift(symbol, PERIOD_H1, tb, false);
         if(h < 0)
            continue;
         double y = iClose(symbol, PERIOD_H1, h + 1);
         if(y <= 0.0)
            continue;
         AddReq(m_prefix + IntegerToString((long)tb), tb, y);
        }
      return(true);
     }

   //--- 与图表对象做 diff sync
   bool               Sync(const string symbol,const ENUM_TIMEFRAMES tf)
     {
      bool changed = false;

      if(!m_cfg.Enabled || !Eligible(tf))
        {
         if(DeleteOwn())
            changed = true;
         return(changed);
        }

      if(!BuildRequired(symbol, tf))
         return(changed);

      int    req  = ArraySize(m_reqName);
      int    span = (m_cfg.SpanMinutes > 0 ? m_cfg.SpanMinutes : 60) * 60;
      bool   used[];
      ArrayResize(used, req);
      ArrayInitialize(used, false);

      //--- 1. 已有对象：非本族跳过；非本实例删除；不在需求内删除；否则更新
      for(int i = ObjectsTotal(0, 0, -1) - 1; i >= 0; i--)
        {
         string name = ObjectName(0, i, 0, -1);
         if(StringFind(name, "MSHS_") != 0)
            continue;
         if(StringFind(name, m_prefix) != 0)
           {
            ObjectDelete(0, name);                  // 模板/旧实例遗留
            changed = true;
            continue;
           }

         int idx = -1;
         for(int k = 0; k < req; k++)
            if(m_reqName[k] == name) { idx = k; break; }

         if(idx < 0)
           {
            ObjectDelete(0, name);
            changed = true;
            continue;
           }

         used[idx] = true;
         if(Upsert(name, m_reqT0[idx], m_reqT0[idx] + span, m_reqPrice[idx]))
            changed = true;
        }

      //--- 2. 缺失的补建
      for(int k = 0; k < req; k++)
        {
         if(used[k])
            continue;
         if(Upsert(m_reqName[k], m_reqT0[k], m_reqT0[k] + span, m_reqPrice[k]))
            changed = true;
        }

      m_styleDirty = false;
      return(changed);
     }

public:
                     CHourSegModule(void) : m_prefix("MSHS_"), m_lastBar(0),
                                            m_styleDirty(true), m_offCleared(false) {}
                    ~CHourSegModule(void) { Release(); }

   bool               Enabled(void) const { return(m_cfg.Enabled && Eligible(_Period)); }

   //--- 初始化：建前缀 + 清遗留；周期不符或关闭时清空本模块对象
   bool               Create(const string symbol,const ENUM_TIMEFRAMES tf,const HourSegSettings &cfg)
     {
      m_cfg        = cfg;
      m_styleDirty = true;
      m_lastBar    = 0;
      m_offCleared = false;
      m_prefix     = "MSHS_" + IntegerToString((int)ChartID()) + "_";

      int stale = CleanupForeign();
      if(stale > 0)
         PrintFormat("HourSeg: cleaned %d stale object(s), prefix=%s", stale, m_prefix);

      if(!m_cfg.Enabled || !Eligible(tf))
         DeleteOwn();

      return(true);
     }

   //--- 释放：删除本实例全部对象
   void               Release(void)
     {
      if(StringLen(m_prefix) > 1)
         DeleteOwn();
     }

   //--- 刷新：按「最新低周期bar是否变化」节流
   //    返回 true = 本轮改动过图表对象（调用方据此决定是否重绘）
   bool               Update(const string symbol,const ENUM_TIMEFRAMES tf)
     {
      if(!m_cfg.Enabled || !Eligible(tf))
        {
         //--- 周期不符/关闭：只清一次，之后不再每轮扫全表
         if(m_offCleared)
            return(false);
         bool any = DeleteOwn();
         m_offCleared = true;
         m_lastBar    = 0;
         return(any);
        }
      m_offCleared = false;

      datetime cur = iTime(symbol, tf, 0);
      if(cur == m_lastBar && !m_styleDirty && cur != 0)
         return(false);

      m_lastBar = cur;
      return(Sync(symbol, tf));
     }
  };

#endif // __HOURSEG_MQH__
//+------------------------------------------------------------------+
