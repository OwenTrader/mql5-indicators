//+------------------------------------------------------------------+
//|                                                   GridLines.mqh  |
//|  模块4：网格线模块（整数位/四分位/中位/八分位水平线 + 价格标签）    |
//|  由 line.mq5 (GridLines_Opt) 提炼而来，接入主指标 MySystem          |
//|                                                                  |
//|  设计约定（同 TrendMA / OscSignal / Countdown）：                  |
//|  · 模块内不定义 input，参数由主指标通过 struct 传入                |
//|  · 模块自管图形对象的创建与删除（前缀 MSGL_，区别于独立版 MGL_）    |
//|  · 定时器归主指标管理，模块 Update() 内部自行节流                  |
//+------------------------------------------------------------------+
#ifndef __GRIDLINES_MQH__
#define __GRIDLINES_MQH__

//--- 网格线类型
enum ENUM_GRIDLINE_TYPE
  {
   GRIDLINE_INTEGER = 0,   // 整数位
   GRIDLINE_QUARTER = 1,   // 四分之一位
   GRIDLINE_MID     = 2,   // 中位线
   GRIDLINE_EIGHTH  = 3    // 八分位
  };

//--- 模块配置体
struct GridSettings
  {
   bool             Enabled;         // 启用网格线
   bool             AutoDetect;      // 自动检测品种设置网格间隔
   int              IntervalPoints;  // 网格间隔点数(手动模式)
   int              NumLines;        // 每侧线条数量
   int              UpdateSeconds;   // 更新间隔秒数
   bool             ShowInteger;     // 显示整数位线条
   color            IntegerColor;
   ENUM_LINE_STYLE  IntegerStyle;
   int              IntegerWidth;
   int              IntegerFontSize;
   bool             AlertInteger;
   bool             ShowQuarter;     // 显示四分之一位线条
   color            QuarterColor;
   ENUM_LINE_STYLE  QuarterStyle;
   int              QuarterWidth;
   int              QuarterFontSize;
   bool             ShowMid;         // 显示中位线
   color            MidColor;
   ENUM_LINE_STYLE  MidStyle;
   int              MidWidth;
   int              MidFontSize;
   bool             AlertMid;
   bool             ShowEighth;      // 显示八分位线条
   color            EighthColor;
   ENUM_LINE_STYLE  EighthStyle;
   int              EighthWidth;
   int              EighthFontSize;
   bool             ShowLabels;      // 显示价格标签
   color            LabelColor;
   string           LabelFont;
  };

//--- 预警冷却状态
struct GridAlertState
  {
   datetime         last_time;
   double           last_price;
  };

//+------------------------------------------------------------------+
//| 网格线模块类                                                      |
//+------------------------------------------------------------------+
class CGridModule
  {
private:
   GridSettings     m_cfg;
   string           m_prefix;        // 对象名前缀
   int              m_intervalPts;   // 实际生效的网格间隔(点)
   datetime         m_lastUpdate;    // 上次同步时间(节流用)
   GridAlertState   m_stateInt;
   GridAlertState   m_stateMid;

   //--- 取标签时间锚点：最新K线向右偏移
   datetime          GetLabelTime(const string symbol,const ENUM_TIMEFRAMES tf) const
     {
      datetime time0 = iTime(symbol, tf, 0);
      if(time0 == 0)
         return(TimeCurrent());
      int shift_bars = (tf >= PERIOD_W1) ? 5 : 2;
      return(time0 + PeriodSeconds(tf) * shift_bars);
     }

   //--- 按类型取样式属性
   color              GetColor(const ENUM_GRIDLINE_TYPE type) const
     {
      switch(type)
        {
         case GRIDLINE_INTEGER: return(m_cfg.IntegerColor);
         case GRIDLINE_QUARTER: return(m_cfg.QuarterColor);
         case GRIDLINE_MID:     return(m_cfg.MidColor);
         case GRIDLINE_EIGHTH:  return(m_cfg.EighthColor);
        }
      return(clrWhite);
     }
   ENUM_LINE_STYLE   GetStyle(const ENUM_GRIDLINE_TYPE type) const
     {
      switch(type)
        {
         case GRIDLINE_INTEGER: return(m_cfg.IntegerStyle);
         case GRIDLINE_QUARTER: return(m_cfg.QuarterStyle);
         case GRIDLINE_MID:     return(m_cfg.MidStyle);
         case GRIDLINE_EIGHTH:  return(m_cfg.EighthStyle);
        }
      return(STYLE_SOLID);
     }
   int                GetWidth(const ENUM_GRIDLINE_TYPE type) const
     {
      switch(type)
        {
         case GRIDLINE_INTEGER: return(m_cfg.IntegerWidth);
         case GRIDLINE_QUARTER: return(m_cfg.QuarterWidth);
         case GRIDLINE_MID:     return(m_cfg.MidWidth);
         case GRIDLINE_EIGHTH:  return(m_cfg.EighthWidth);
        }
      return(1);
     }
   int                GetFontSize(const ENUM_GRIDLINE_TYPE type) const
     {
      switch(type)
        {
         case GRIDLINE_INTEGER: return(m_cfg.IntegerFontSize);
         case GRIDLINE_QUARTER: return(m_cfg.QuarterFontSize);
         case GRIDLINE_MID:     return(m_cfg.MidFontSize);
         case GRIDLINE_EIGHTH:  return(m_cfg.EighthFontSize);
        }
      return(10);
     }

   //--- 加入需求列表（含标签）
   void               AddToRequired(double price,const ENUM_GRIDLINE_TYPE type,
                                    string &arr[],int &count,const int digits)
     {
      price = NormalizeDouble(price, digits);
      string type_str;
      switch(type)
        {
         case GRIDLINE_INTEGER: type_str = "INT_"; break;
         case GRIDLINE_QUARTER: type_str = "QTR_"; break;
         case GRIDLINE_MID:     type_str = "MID_"; break;
         case GRIDLINE_EIGHTH:  type_str = "EIG_"; break;
        }
      string name = m_prefix + "LINE_" + type_str + DoubleToString(price, digits);

      if(count >= ArraySize(arr))
         ArrayResize(arr, count + 100);
      arr[count] = name;
      count++;

      if(m_cfg.ShowLabels)
        {
         string label_name = m_prefix + "LABEL_" + type_str + DoubleToString(price, digits);
         if(count >= ArraySize(arr))
            ArrayResize(arr, count + 100);
         arr[count] = label_name;
         count++;
        }
     }

   //--- 更新现有对象（标签跟随最新K线移动）
   void               UpdateObjectProperties(const string symbol,const ENUM_TIMEFRAMES tf,const string name)
     {
      if(StringFind(name, "LABEL_") > 0)
        {
         double   price      = ObjectGetDouble(0, name, OBJPROP_PRICE);
         datetime label_time = GetLabelTime(symbol, tf);
         ObjectMove(0, name, 0, label_time, price);
        }
     }

   //--- 创建新对象
   void               CreateObject(const string symbol,const ENUM_TIMEFRAMES tf,const string name)
     {
      bool is_label = (StringFind(name, "LABEL_") > 0);
      ENUM_GRIDLINE_TYPE type = GRIDLINE_INTEGER;
      if(StringFind(name, "QTR_") > 0)
         type = GRIDLINE_QUARTER;
      else if(StringFind(name, "MID_") > 0)
         type = GRIDLINE_MID;
      else if(StringFind(name, "EIG_") > 0)
         type = GRIDLINE_EIGHTH;

      string price_str = name;
      StringReplace(price_str, m_prefix + (is_label ? "LABEL_" : "LINE_"), "");
      if(type == GRIDLINE_INTEGER)      StringReplace(price_str, "INT_", "");
      else if(type == GRIDLINE_QUARTER) StringReplace(price_str, "QTR_", "");
      else if(type == GRIDLINE_MID)     StringReplace(price_str, "MID_", "");
      else if(type == GRIDLINE_EIGHTH)  StringReplace(price_str, "EIG_", "");

      double price = StringToDouble(price_str);

      if(is_label)
        {
         ObjectCreate(0, name, OBJ_TEXT, 0, GetLabelTime(symbol, tf), price);
         ObjectSetString(0, name, OBJPROP_TEXT,
                         DoubleToString(price, (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS)));
         ObjectSetInteger(0, name, OBJPROP_COLOR, m_cfg.LabelColor);
         ObjectSetInteger(0, name, OBJPROP_ANCHOR, ANCHOR_LEFT_UPPER);
         ObjectSetInteger(0, name, OBJPROP_FONTSIZE, GetFontSize(type));
         ObjectSetString(0, name, OBJPROP_FONT, m_cfg.LabelFont);
         ObjectSetInteger(0, name, OBJPROP_BACK, false);
        }
      else
        {
         ObjectCreate(0, name, OBJ_HLINE, 0, 0, price);
         ObjectSetInteger(0, name, OBJPROP_COLOR, GetColor(type));
         ObjectSetInteger(0, name, OBJPROP_STYLE, GetStyle(type));
         ObjectSetInteger(0, name, OBJPROP_WIDTH, GetWidth(type));
         ObjectSetInteger(0, name, OBJPROP_SELECTABLE, true);
         ObjectSetInteger(0, name, OBJPROP_BACK, true);   // 线条在K线下方
        }
     }

   //--- 预警检查（含30分钟冷却）
   void               CheckAlerts(const string symbol,const int digits,const double current_price,
                                 const double grid_size,const double base_level)
     {
      datetime now       = TimeCurrent();
      double   tolerance = grid_size * 0.1;   // 10% 容差

      if(m_cfg.AlertInteger)
        {
         double int_level = base_level;       // 最近的下方整数位
         if(current_price - int_level > grid_size / 2)
            int_level += grid_size;

         if(MathAbs(current_price - int_level) < tolerance)
           {
            if((now - m_stateInt.last_time > 1800) ||
               (MathAbs(int_level - m_stateInt.last_price) > tolerance))
              {
               Alert("价格触及整数位网格: ", DoubleToString(int_level, digits), " (", symbol, ")");
               m_stateInt.last_time  = now;
               m_stateInt.last_price = int_level;
              }
           }
        }

      if(m_cfg.AlertMid && m_cfg.ShowMid)
        {
         double mid_level = base_level + grid_size * 0.5;
         if(current_price - mid_level > grid_size / 2)
            mid_level += grid_size;

         if(MathAbs(current_price - mid_level) < tolerance)
           {
            if((now - m_stateMid.last_time > 1800) ||
               (MathAbs(mid_level - m_stateMid.last_price) > tolerance))
              {
               Alert("价格触及中位线网格: ", DoubleToString(mid_level, digits), " (", symbol, ")");
               m_stateMid.last_time  = now;
               m_stateMid.last_price = mid_level;
              }
           }
        }
     }

   //--- 核心同步逻辑：Diff Sync 算法（更新/删除/新增）
   void               SyncGrid(const string symbol,const ENUM_TIMEFRAMES tf)
     {
      m_lastUpdate = TimeCurrent();

      int    digits     = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
      double point      = SymbolInfoDouble(symbol, SYMBOL_POINT);
      double base_price = SymbolInfoDouble(symbol, SYMBOL_BID);
      double grid_size  = m_intervalPts * point;
      double base_level = MathFloor(base_price / grid_size) * grid_size;

      //--- 1. 生成所需对象名称列表
      string required_names[];
      int est_count = (m_cfg.NumLines * 2 + 2) * 8;
      ArrayResize(required_names, est_count);
      int req_count = 0;

      for(int i = -m_cfg.NumLines; i <= m_cfg.NumLines + 1; i++)
        {
         double level = base_level + i * grid_size;

         if(m_cfg.ShowInteger)
            AddToRequired(level, GRIDLINE_INTEGER, required_names, req_count, digits);

         if(m_cfg.ShowQuarter)
           {
            AddToRequired(level + grid_size * 0.25, GRIDLINE_QUARTER, required_names, req_count, digits);
            AddToRequired(level + grid_size * 0.75, GRIDLINE_QUARTER, required_names, req_count, digits);
           }

         if(m_cfg.ShowMid)
            AddToRequired(level + grid_size * 0.50, GRIDLINE_MID, required_names, req_count, digits);

         if(m_cfg.ShowEighth)
           {
            AddToRequired(level + grid_size * 0.125, GRIDLINE_EIGHTH, required_names, req_count, digits);
            AddToRequired(level + grid_size * 0.375, GRIDLINE_EIGHTH, required_names, req_count, digits);
            AddToRequired(level + grid_size * 0.625, GRIDLINE_EIGHTH, required_names, req_count, digits);
            AddToRequired(level + grid_size * 0.875, GRIDLINE_EIGHTH, required_names, req_count, digits);
           }
        }

      ArrayResize(required_names, req_count);

      //--- 2. 遍历已有对象：在需求列表则更新，否则删除
      int total_obj = ObjectsTotal(0, 0, -1);
      for(int i = total_obj - 1; i >= 0; i--)
        {
         string name = ObjectName(0, i);
         if(StringFind(name, m_prefix) != 0)
            continue;                             // 不是本模块的对象

         bool is_needed = false;
         for(int k = 0; k < req_count; k++)
           {
            if(name == required_names[k])
              {
               is_needed = true;
               required_names[k] = "";            // 标记为已处理
               break;
              }
           }

         if(is_needed)
            UpdateObjectProperties(symbol, tf, name);
         else
            ObjectDelete(0, name);
        }

      //--- 3. 创建缺失的对象（需求列表中未清空的）
      for(int k = 0; k < req_count; k++)
        {
         if(required_names[k] != "")
            CreateObject(symbol, tf, required_names[k]);
        }

      //--- 4. 预警检查
      CheckAlerts(symbol, digits, base_price, grid_size, base_level);
     }

public:
                     CGridModule(void) : m_prefix("MSGL_"), m_intervalPts(0), m_lastUpdate(0) {}
                    ~CGridModule(void) { Release(); }

   bool               Enabled(void) const { return(m_cfg.Enabled); }

   //--- 初始化：品种自动检测 + 网格间隔确定
   bool               Create(const string symbol,const ENUM_TIMEFRAMES tf,const GridSettings &cfg)
     {
      m_cfg = cfg;
      if(!m_cfg.Enabled)
         return(true);

      m_stateInt.last_time  = 0;
      m_stateInt.last_price = 0;
      m_stateMid.last_time  = 0;
      m_stateMid.last_price = 0;
      m_lastUpdate          = 0;

      int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);

      if(m_cfg.AutoDetect)
        {
         //--- 1. 优先检测黄金 (XAU / GOLD)
         if(StringFind(symbol, "XAU") != -1 || StringFind(symbol, "GOLD") != -1)
           {
            if(digits == 3)
              {
               m_intervalPts = 100000;   // 3位小数黄金：约10美金
               Print("检测到3位小数黄金品种 (" + symbol + ")，自动设置网格间隔为 ",
                     m_intervalPts, " 点 (约10美金)");
              }
            else if(digits == 2)
              {
               m_intervalPts = 1000;     // 标准黄金
               Print("检测到标准黄金品种 (" + symbol + ")，自动设置网格间隔为 ",
                     m_intervalPts, " 点 (约10美金)");
              }
            else
              {
               m_intervalPts = m_cfg.IntervalPoints;
               Print("检测到黄金但小数位特殊(", digits, ")，使用默认间隔: ", m_intervalPts);
              }
           }
         //--- 2. 日元 (JPY)
         else if(StringFind(symbol, "JPY") != -1)
           {
            m_intervalPts = 1000;
            Print("检测到日元品种，自动设置网格间隔为 ", m_intervalPts);
           }
         //--- 3. 白银 (XAG)
         else if(StringFind(symbol, "XAG") != -1)
           {
            m_intervalPts = 500;
            Print("检测到白银品种，自动设置网格间隔为 ", m_intervalPts);
           }
         //--- 4. 其他品种
         else
           {
            m_intervalPts = (digits == 5 || digits == 3) ? 1000 : 100;
            Print("使用默认网格间隔: ", m_intervalPts);
           }
        }
      else
        {
         m_intervalPts = m_cfg.IntervalPoints;
         Print("使用手动设置的网格间隔: ", m_intervalPts);
        }

      return(true);
     }

   //--- 释放：删除本模块全部对象
   void               Release(void)
     {
      if(!m_cfg.Enabled)
         return;
      ObjectsDeleteAll(0, m_prefix);
     }

   //--- 刷新：内部节流，距上次同步不足间隔秒数则跳过
   //    由主指标 OnCalculate / OnTimer 调用（定时器周期为1秒）
   void               Update(const string symbol,const ENUM_TIMEFRAMES tf)
     {
      if(!m_cfg.Enabled)
         return;
      if(TimeCurrent() - m_lastUpdate < m_cfg.UpdateSeconds)
         return;
      SyncGrid(symbol, tf);
     }
  };

#endif // __GRIDLINES_MQH__
