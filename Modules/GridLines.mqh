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
   bool             m_styleDirty;    // 配置刚变更 -> 需对已存在对象重套样式
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

   //--- 类型 -> 名称 token
   string             TypeToken(const ENUM_GRIDLINE_TYPE type) const
     {
      switch(type)
        {
         case GRIDLINE_INTEGER: return("INT_");
         case GRIDLINE_QUARTER: return("QTR_");
         case GRIDLINE_MID:     return("MID_");
         case GRIDLINE_EIGHTH:  return("EIG_");
        }
      return("INT_");
     }

   //--- 名称 -> 类型：用 "_XXX_" 全片段精确匹配，避免子串误判
   ENUM_GRIDLINE_TYPE TypeFromName(const string name)
     {
      if(StringFind(name, "_QTR_") > 0)
         return(GRIDLINE_QUARTER);
      if(StringFind(name, "_MID_") > 0)
         return(GRIDLINE_MID);
      if(StringFind(name, "_EIG_") > 0)
         return(GRIDLINE_EIGHTH);
      return(GRIDLINE_INTEGER);
     }

   //--- 品种名前缀匹配（不区分大小写）：命中 symbol 开头即算，
   //    之后可跟经纪商任意后缀（如 XAUUSDm / US30.cash / USTEC.pro）
   bool               MatchPrefix(const string symbol,const string key) const
     {
      string s = symbol; StringToUpper(s);
      string k = key;    StringToUpper(k);
      return(StringFind(s, k) == 0);
     }

   //--- 股指族判定（前缀匹配，含常见别名）：容器按展示位数定档（见 Create）
   bool               IsIndexSymbol(const string symbol) const
     {
      if(MatchPrefix(symbol, "US30")   || MatchPrefix(symbol, "DJ30")   ||
         MatchPrefix(symbol, "WS30")   || MatchPrefix(symbol, "DOW")    ||
         MatchPrefix(symbol, "USA30"))                                       // 道指
         return(true);
      if(MatchPrefix(symbol, "USTEC")  || MatchPrefix(symbol, "USTECH") ||
         MatchPrefix(symbol, "US100")  || MatchPrefix(symbol, "NAS100") ||
         MatchPrefix(symbol, "NASDAQ"))                                      // 纳指
         return(true);
      if(MatchPrefix(symbol, "US500")  || MatchPrefix(symbol, "USA500") ||
         MatchPrefix(symbol, "SP500")  || MatchPrefix(symbol, "SPX"))         // 标普
         return(true);
      if(MatchPrefix(symbol, "GER30")  || MatchPrefix(symbol, "GER40")  ||
         MatchPrefix(symbol, "DE30")   || MatchPrefix(symbol, "DE40")   ||
         MatchPrefix(symbol, "DAX"))                                         // 德指
         return(true);
      if(MatchPrefix(symbol, "UK100")  || MatchPrefix(symbol, "FTSE"))        // 富时
         return(true);
      if(MatchPrefix(symbol, "JP225")  || MatchPrefix(symbol, "JPN225") ||
         MatchPrefix(symbol, "NIKKEI"))                                      // 日经
         return(true);
      return(false);
     }

   //--- 名称 -> 价格
   double             PriceFromName(const string name,const bool is_label) const
     {
      string s = name;
      StringReplace(s, m_prefix + (is_label ? "LABEL_" : "LINE_"), "");
      StringReplace(s, "INT_", "");
      StringReplace(s, "QTR_", "");
      StringReplace(s, "MID_", "");
      StringReplace(s, "EIG_", "");
      return(StringToDouble(s));
     }

   //--- 样式应用：颜色/线型/线宽（线条）或 文本/颜色/字体/字号（标签）
   //    创建时调用，配置变更后也会对已存在对象重套，保证参数改动即时生效
   void               ApplyProperties(const string symbol,const string name)
     {
      bool is_label = (StringFind(name, "LABEL_") > 0);
      ENUM_GRIDLINE_TYPE type = TypeFromName(name);

      if(is_label)
        {
         double price = PriceFromName(name, true);
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
         ObjectSetInteger(0, name, OBJPROP_COLOR, GetColor(type));
         ObjectSetInteger(0, name, OBJPROP_STYLE, GetStyle(type));
         ObjectSetInteger(0, name, OBJPROP_WIDTH, GetWidth(type));
         ObjectSetInteger(0, name, OBJPROP_SELECTABLE, true);
         ObjectSetInteger(0, name, OBJPROP_BACK, true);   // 线条在K线下方
        }
     }

   //--- 加入需求列表（含标签）
   void               AddToRequired(double price,const ENUM_GRIDLINE_TYPE type,
                                    string &arr[],int &count,const int digits)
     {
      price = NormalizeDouble(price, digits);
      string type_str = TypeToken(type);
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

   //--- 刷新已存在对象：标签跟随最新K线移动；配置变更后重套样式
   void               UpdateObjectProperties(const string symbol,const ENUM_TIMEFRAMES tf,const string name)
     {
      if(StringFind(name, "LABEL_") > 0)
        {
         double   price      = ObjectGetDouble(0, name, OBJPROP_PRICE);
         datetime label_time = GetLabelTime(symbol, tf);
         ObjectMove(0, name, 0, label_time, price);
        }

      //--- 仅当本次会话的参数相比对象建立时发生过变化，才重写样式
      if(m_styleDirty)
         ApplyProperties(symbol, name);
     }

   //--- 创建新对象（创建后立即套用当前样式）
   void               CreateObject(const string symbol,const ENUM_TIMEFRAMES tf,const string name)
     {
      bool   is_label = (StringFind(name, "LABEL_") > 0);
      double price    = PriceFromName(name, is_label);

      if(is_label)
         ObjectCreate(0, name, OBJ_TEXT, 0, GetLabelTime(symbol, tf), price);
      else
         ObjectCreate(0, name, OBJ_HLINE, 0, 0, price);

      ApplyProperties(symbol, name);
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
      //    注意：ObjectsTotal 与 ObjectName 必须用同一套 (sub_window, type) 过滤口径，
      //    否则两者索引域不一致会漏掉对象，导致样式刷新/删除失配
      int total_obj = ObjectsTotal(0, 0, -1);
      for(int i = total_obj - 1; i >= 0; i--)
        {
         string name = ObjectName(0, i, 0, -1);
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

      //--- 5. 本轮已覆盖全部在列对象（含新创建），样式与配置一致
      m_styleDirty = false;
     }

public:
                     CGridModule(void) : m_prefix("MSGL_"), m_intervalPts(0), m_lastUpdate(0), m_styleDirty(true) {}
                    ~CGridModule(void) { Release(); }

   bool               Enabled(void) const { return(m_cfg.Enabled); }

   //--- 初始化：品种自动检测 + 网格间隔确定
   bool               Create(const string symbol,const ENUM_TIMEFRAMES tf,const GridSettings &cfg)
     {
      m_cfg = cfg;
      m_styleDirty = true;              // 参数可能已变更：首次同步时对已有对象重套样式
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
         //--- 口径：黄金/白银按「价格步长」识别（与小数位无关，落同一价格台阶）；
         //    股指按「经纪商展示的价格位数」定档（位数每多一位，容器多一个 0）。
         //    m_intervalPts = 网格间隔点数，grid_size = m_intervalPts × SYMBOL_POINT。
         double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
         if(point <= 0.0)
            point = MathPow(0.1, digits);          // 兜底：由小数位反推 point
         double stepPrice = 0.0;
         bool   isIndex   = false;

         //--- 1. 黄金（前缀 XAU / GOLD）：每 10 美元（2位/3位小数通用）
         if(MatchPrefix(symbol, "XAU") || MatchPrefix(symbol, "GOLD"))
            stepPrice = 10.0;
         //--- 2. 白银（前缀 XAG / SILVER）：每 0.5 美元
         else if(MatchPrefix(symbol, "XAG") || MatchPrefix(symbol, "SILVER"))
            stepPrice = 0.5;
         //--- 3. 股指（US30 / USTEC / US500 / GER / UK100 / JP225 等，前缀匹配）
         else if(IsIndexSymbol(symbol))
            isIndex = true;

         if(isIndex)
           {
            //--- 股指容器按「经纪商展示的价格位数」定档：
            //    容器点数 = 10^(展示位数 - 2)          （展示位数 = 整数位位数 + 小数位位数）
            //    等价于  指数点容器 = 10^(整数位位数 - 2) = 指数价位的 1% 左右，与小数位无关
            //    例：US30 =53000.0  (5+1=6位) -> 10^4 = 10000  点 = 1000 指数点
            //        US500=5700.25  (4+2=6位) -> 10^4 = 10000  点 = 100  指数点
            //        USTEC=30000.00 (5+2=7位) -> 10^5 = 100000 点 = 1000 指数点
            double refPrice  = SymbolInfoDouble(symbol, SYMBOL_BID);
            int    intDigits = 1;
            if(refPrice > 0.0)
               intDigits = (int)MathFloor(MathLog(refPrice) / MathLog(10.0)) + 1;   // 整数部分位数
            int    totalDigits = intDigits + digits;                                // 展示位数
            int    idxPts      = (int)MathRound(MathPow(10.0, (double)(totalDigits - 2)));
            if(idxPts < 1)
               idxPts = 1;
            m_intervalPts = idxPts;
            Print("自动识别指数品种(", symbol, ", 展示 ", totalDigits, " 位 = ",
                  intDigits, " 整数位 + ", digits, " 小数位)：网格间隔 ",
                  m_intervalPts, " 点 = ",
                  DoubleToString(m_intervalPts * point, digits), " 指数点");
           }
         else if(stepPrice > 0.0)
           {
            m_intervalPts = (int)MathRound(stepPrice / point);
            if(m_intervalPts < 1)
               m_intervalPts = 1;
            Print("自动识别品种族(", symbol, ", ", digits, "位小数)：网格间隔 ",
                  stepPrice, " 价格单位 = ", m_intervalPts, " 点");
           }
         else
           {
            //--- 通用外汇/其它：100 pips（5/3 位小数 = 1000 点）；其余 100 点
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
   //    注意：不能因为 Enabled=false 就跳过删除，否则「先启用再关闭」会留下
   //    残留线条，而这些残留对象不会再走样式刷新路径
   void               Release(void)
     {
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
