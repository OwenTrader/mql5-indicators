//+------------------------------------------------------------------+
//|                                               DailyLevels.mqh    |
//|  模块11：前一日 / 前一周 OHLC 水平线段                              |
//|                                                                  |
//|  规则：                                                           |
//|   · 日线组：取【上一根已收盘 D1】的 O/H/L/C，画 4 条水平线段，        |
//|     覆盖范围 = 今天（当前 D1 开盘 -> 明日开盘）                      |
//|   · 周线组：取【上一根已收盘 W1】的 O/H/L/C，覆盖本周                |
//|   · 日线 / 周线各自颜色、线型、线宽可独立配置（颜色必须能区分）       |
//|                                                                  |
//|  实现约定：                                                       |
//|   · 用 OBJ_TREND 两端同价 + 关闭左右延伸，表达固定长度线段           |
//|   · 每个周期只维护 8 个固定名对象（D_O/D_H/D_L/D_C、W_*），滚动时     |
//|     只改坐标，不重建对象                                           |
//|   · 对象前缀 MSDL_<ChartID>_，套用模板时清理非本实例遗留             |
//|   · 刷新按「当前 D1 bar 是否变化」节流                              |
//+------------------------------------------------------------------+
#ifndef __DAILYLEVELS_MQH__
#define __DAILYLEVELS_MQH__

//--- 模块配置体
struct DailyLevelsSettings
  {
   bool             Enabled;        // 模块总开关
   bool             ShowDaily;      // 画日线 OHLC
   bool             ShowWeekly;     // 画周线 OHLC
   color            DailyColor;     // 日线颜色
   ENUM_LINE_STYLE  DailyStyle;     // 日线线型
   int              DailyWidth;     // 日线线宽
   color            WeeklyColor;    // 周线颜色
   ENUM_LINE_STYLE  WeeklyStyle;    // 周线线型
   int              WeeklyWidth;    // 周线线宽
  };

//+------------------------------------------------------------------+
//| 前一日 / 前一周 OHLC 水平线段模块                                  |
//+------------------------------------------------------------------+
class CDailyLevelsModule
  {
private:
   DailyLevelsSettings m_cfg;
   string              m_prefix;
   datetime            m_lastD1;      // 上次同步时的当前 D1 时间
   bool                m_styleDirty;

   string             ObjName(const string grp,const string fld) const
     {
      return(m_prefix + grp + "_" + fld);
     }

   void               ApplyStyle(const string name,const color clr,
                                 const ENUM_LINE_STYLE st,const int w)
     {
      ObjectSetInteger(0, name, OBJPROP_COLOR,      clr);
      ObjectSetInteger(0, name, OBJPROP_STYLE,      st);
      ObjectSetInteger(0, name, OBJPROP_WIDTH,      (w < 1) ? 1 : ((w > 5) ? 5 : w));
      ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT,  false);
      ObjectSetInteger(0, name, OBJPROP_RAY_LEFT,   false);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN,     true);
      ObjectSetInteger(0, name, OBJPROP_BACK,       true);
     }

   //--- 创建/更新一条线段；返回 true = 图形有变化
   bool               Upsert(const string name,const datetime t1,const datetime t2,
                             const double price,const color clr,
                             const ENUM_LINE_STYLE st,const int w)
     {
      if(price <= 0.0 || t1 <= 0)
        {
         if(ObjectFind(0, name) >= 0)
           {
            ObjectDelete(0, name);
            return(true);
           }
         return(false);
        }

      if(ObjectFind(0, name) < 0)
        {
         if(!ObjectCreate(0, name, OBJ_TREND, 0, t1, price, t2, price))
            return(false);
         ApplyStyle(name, clr, st, w);
         return(true);
        }

      bool changed = false;
      datetime c1 = (datetime)ObjectGetInteger(0, name, OBJPROP_TIME, 0);
      datetime c2 = (datetime)ObjectGetInteger(0, name, OBJPROP_TIME, 1);
      double   cp = ObjectGetDouble(0, name, OBJPROP_PRICE, 0);
      if(c1 != t1 || c2 != t2 || MathAbs(cp - price) > _Point * 0.5)
        {
         ObjectMove(0, name, 0, t1, price);
         ObjectMove(0, name, 1, t2, price);
         changed = true;
        }
      if(m_styleDirty)
         ApplyStyle(name, clr, st, w);
      return(changed);
     }

   //--- 删除某一组（"D_"/"W_"）
   bool               DeleteGroup(const string grp)
     {
      bool any = false;
      string fields[4] = {"O", "H", "L", "C"};
      for(int i = 0; i < 4; i++)
        {
         string name = ObjName(grp, fields[i]);
         if(ObjectFind(0, name) >= 0)
           {
            ObjectDelete(0, name);
            any = true;
           }
        }
      return(any);
     }

   //--- 删除本实例全部对象
   bool               DeleteOwn(void)
     {
      bool any = false;
      any = DeleteGroup("D_") || any;
      any = DeleteGroup("W_") || any;
      return(any);
     }

   //--- 清理同族但非本实例的遗留（模板套用到其他图表）
   int                CleanupForeign(void)
     {
      int removed = 0;
      for(int i = ObjectsTotal(0, 0, -1) - 1; i >= 0; i--)
        {
         string nm = ObjectName(0, i, 0, -1);
         if(StringFind(nm, "MSDL_") != 0)
            continue;
         if(StringFind(nm, m_prefix) == 0)
            continue;
         if(ObjectDelete(0, nm))
            removed++;
        }
      return(removed);
     }

   //--- 把「D1/W1 时间戳」对齐到当前图表周期上【实际存在的第一根K线】
   //    MT5 的 D1/W1 时间是服务器日界（如 00:00），但第一个成交 bar 可能
   //    从 00:05 / 01:00 才开始（夏令时、经纪商偏移、缺口），直接用它当起点
   //    会让线段从无K线的空白区开始。
   datetime           AlignToFirstBar(const string symbol,const ENUM_TIMEFRAMES tf,
                                      const datetime t) const
     {
      if(t <= 0)
         return(t);

      int k = iBarShift(symbol, tf, t, false);
      if(k < 0)
         return(t);

      datetime tk = iTime(symbol, tf, k);
      if(tk >= t)
         return(tk);                 // 该 bar 正好从 t 开始

      if(k > 0)                      // 取更晚的一根（仍在 t 之后）
        {
         datetime tn = iTime(symbol, tf, k - 1);
         if(tn > 0 && tn >= t)
            return(tn);
        }
      return(t);                     // 找不到更贴合的就退回原时间戳
     }

   //--- 画一组（日线或周线）
   bool               DrawGroup(const string symbol,const ENUM_TIMEFRAMES tf,
                                const string grp,const color clr,
                                const ENUM_LINE_STYLE st,const int w)
     {
      double o = iOpen (symbol, tf, 1);
      double h = iHigh (symbol, tf, 1);
      double l = iLow  (symbol, tf, 1);
      double c = iClose(symbol, tf, 1);
      if(o <= 0.0 || h <= 0.0 || l <= 0.0 || c <= 0.0)
         return(false);

      //--- 覆盖范围 = 当前周期这一根（今天 / 本周）
      //    起点对齐到「当天/当周第一根实际K线」，而不是 D1/W1 的日界时间戳
      datetime tRef = iTime(symbol, tf, 0);
      if(tRef <= 0)
         return(false);
      datetime t1 = AlignToFirstBar(symbol, _Period, tRef);
      datetime t2 = t1 + PeriodSeconds(tf);

      bool changed = false;
      changed = Upsert(ObjName(grp, "O"), t1, t2, o, clr, st, w) || changed;
      changed = Upsert(ObjName(grp, "H"), t1, t2, h, clr, st, w) || changed;
      changed = Upsert(ObjName(grp, "L"), t1, t2, l, clr, st, w) || changed;
      changed = Upsert(ObjName(grp, "C"), t1, t2, c, clr, st, w) || changed;
      return(changed);
     }

public:
                     CDailyLevelsModule(void) : m_prefix("MSDL_"), m_lastD1(0), m_styleDirty(true) {}
                    ~CDailyLevelsModule(void) { Release(); }

   bool               Enabled(void) const { return(m_cfg.Enabled); }

   //--- 初始化
   bool               Create(const string symbol,const ENUM_TIMEFRAMES tf,
                            const DailyLevelsSettings &cfg)
     {
      m_cfg        = cfg;
      m_styleDirty = true;
      m_lastD1     = 0;
      m_prefix     = "MSDL_" + IntegerToString((int)ChartID()) + "_";

      int stale = CleanupForeign();
      if(stale > 0)
         PrintFormat("DailyLevels: cleaned %d stale object(s)", stale);

      if(!m_cfg.Enabled)
         DeleteOwn();

      return(true);
     }

   //--- 释放
   void               Release(void)
     {
      if(StringLen(m_prefix) > 1)
         DeleteOwn();
     }

   //--- 刷新：按「当前 D1 bar 是否变化」节流
   bool               Update(const string symbol,const ENUM_TIMEFRAMES tf)
     {
      if(!m_cfg.Enabled)
        {
         bool any = DeleteOwn();
         m_lastD1 = 0;
         return(any);
        }

      datetime cur = iTime(symbol, PERIOD_D1, 0);
      if(cur == m_lastD1 && !m_styleDirty && cur != 0)
         return(false);
      m_lastD1 = cur;

      bool changed = false;

      if(m_cfg.ShowDaily)
         changed = DrawGroup(symbol, PERIOD_D1, "D_", m_cfg.DailyColor,
                             m_cfg.DailyStyle, m_cfg.DailyWidth) || changed;
      else
         changed = DeleteGroup("D_") || changed;

      if(m_cfg.ShowWeekly)
         changed = DrawGroup(symbol, PERIOD_W1, "W_", m_cfg.WeeklyColor,
                             m_cfg.WeeklyStyle, m_cfg.WeeklyWidth) || changed;
      else
         changed = DeleteGroup("W_") || changed;

      m_styleDirty = false;
      return(changed);
     }
  };

#endif // __DAILYLEVELS_MQH__
//+------------------------------------------------------------------+
