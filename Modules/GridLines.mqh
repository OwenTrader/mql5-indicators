//+------------------------------------------------------------------+
//|                                                   GridLines.mqh  |
//|  模块1：网格线模块（整数位/四分位/中位/八分位水平线 + 价格标签）    |
//|  由 line.mq5 (GridLines_Opt) 提炼而来，接入主指标 MySystem          |
//|                                                                  |
//|  自动间隔（v1.33）：按「价格展示位数」定档                          |
//|    展示位数 = 整数位位数 + 小数位位数                               |
//|    通用：间隔点数 = 10^(展示位数 - 3)  ->  6位=1000点 / 7位=10000点 |
//|    黄金(含XAU/GOLD) 与 股指(US30/USTEC/US500/GER/UK100/JP225…)：     |
//|           10^(展示位数 - 2) -> 6位=10000点 / 7位=100000点（宽10倍） |
//|    该间隔再被八分位线等分成 8 份（每份 = 间隔/8）                    |
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
   //    返回 true = 确实发生了变化（调用方据此决定是否重绘）
   bool               UpdateObjectProperties(const string symbol,const ENUM_TIMEFRAMES tf,const string name)
     {
      bool changed = false;

      if(StringFind(name, "LABEL_") > 0)
        {
         double   price      = ObjectGetDouble(0, name, OBJPROP_PRICE);
         datetime label_time = GetLabelTime(symbol, tf);
         datetime cur_time   = (datetime)ObjectGetInteger(0, name, OBJPROP_TIME, 0);
         if(cur_time != label_time)
           {
            ObjectMove(0, name, 0, label_time, price);
            changed = true;
           }
        }

      //--- 仅当本次会话的参数相比对象建立时发生过变化，才重写样式
      if(m_styleDirty)
        {
         ApplyProperties(symbol, name);
         changed = true;
        }
      return(changed);
     }

   //--- 创建新对象（创建后立即套用当前样式）
   bool               CreateObject(const string symbol,const ENUM_TIMEFRAMES tf,const string name)
     {
      bool   is_label = (StringFind(name, "LABEL_") > 0);
      double price    = PriceFromName(name, is_label);

      bool ok;
      if(is_label)
         ok = ObjectCreate(0, name, OBJ_TEXT, 0, GetLabelTime(symbol, tf), price);
      else
         ok = ObjectCreate(0, name, OBJ_HLINE, 0, 0, price);

      if(ok)
         ApplyProperties(symbol, name);
      return(ok);
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
   //    返回 true = 对象集合或标签位置发生变化
   bool               SyncGrid(const string symbol,const ENUM_TIMEFRAMES tf)
     {
      m_lastUpdate = TimeCurrent();

      //--- 自动档位可能因 OnInit 时报价未就绪而算错/为 0：此处兜底重算
      if(m_intervalPts <= 0)
         DetectInterval(symbol);

      int    digits     = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
      double point      = SymbolInfoDouble(symbol, SYMBOL_POINT);
      double base_price = SymbolInfoDouble(symbol, SYMBOL_BID);
      double grid_size  = m_intervalPts * point;

      if(point <= 0.0 || grid_size <= 0.0 || base_price <= 0.0)
         return(false);                    // 报价未就绪：本轮跳过，等下一个周期

      double base_level = MathFloor(base_price / grid_size) * grid_size;
      bool   changed    = false;

      //--- 1. 生成所需对象名称列表
      //    每档最多 8 条线（INT 1 + QTR 2 + MID 1 + EIG 4）+ 8 个标签，
      //    预留 *16 可避免同步过程中反复 ArrayResize
      string required_names[];
      int est_count = (m_cfg.NumLines * 2 + 2) * 16 + 16;
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
            changed = UpdateObjectProperties(symbol, tf, name) || changed;
         else
           {
            ObjectDelete(0, name);
            changed = true;
           }
        }

      //--- 3. 创建缺失的对象（需求列表中未清空的）
      for(int k = 0; k < req_count; k++)
        {
         if(required_names[k] != "")
            changed = CreateObject(symbol, tf, required_names[k]) || changed;
        }

      //--- 4. 预警检查
      CheckAlerts(symbol, digits, base_price, grid_size, base_level);

      //--- 5. 本轮已覆盖全部在列对象（含新创建），样式与配置一致
      m_styleDirty = false;

      return(changed);
     }

   //--- 黄金族判定：品种名【包含】XAU（任意位置、不区分大小写）
   //    GOLD 作为等价别名一并纳入（同一价格台阶，避免别名品种掉回通用档变密 10 倍）
   bool               IsGoldSymbol(const string symbol)
     {
      string s = symbol;
      StringToUpper(s);
      return(StringFind(s, "XAU") >= 0 || StringFind(s, "GOLD") >= 0);
     }

   //--- 股指族判定：品种名【包含】任一常见别名（含经纪商后缀，如 US30.cash / GER40.pro）
   bool               IsIndexSymbol(const string symbol)
     {
      string s = symbol;
      StringToUpper(s);

      string keys[] =
        {
         //--- 道指
         "US30", "DJ30", "WS30", "DOW", "USA30",
         //--- 纳指
         "USTEC", "USTECH", "US100", "NAS100", "NASDAQ",
         //--- 标普
         "US500", "USA500", "SP500", "SPX",
         //--- 德指
         "GER30", "GER40", "DE30", "DE40", "DAX",
         //--- 富时
         "UK100", "FTSE",
         //--- 日经
         "JP225", "JPN225", "NIKKEI"
        };

      int n = ArraySize(keys);
      for(int i = 0; i < n; i++)
         if(StringFind(s, keys[i]) >= 0)
            return(true);
      return(false);
     }

   //--- 自动档位：按「价格展示位数」定档
   //    展示位数 = 整数部分位数 + 小数位位数（1.12345 = 6 位；4999.00 = 6 位；4000.000 = 7 位）
   //    通用：间隔点数 = 10^(展示位数 - 3)   ->  5位=100 / 6位=1000 / 7位=10000
   //    黄金（含 XAU/GOLD）与股指（US30/USTEC/US500/GER/UK100/JP225 等）：指数 +1
   //          -> 6位=10000 / 7位=100000（比通用档宽 10 倍）
   //    该间隔再被「八分位」线等分成 8 份（1/8、2/8…7/8 各有线型），即每份 = 间隔/8。
   void               DetectInterval(const string symbol)
     {
      int    digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
      double point  = SymbolInfoDouble(symbol, SYMBOL_POINT);
      if(point <= 0.0)
         point = MathPow(0.1, (double)digits);     // 兜底：由小数位反推 point

      double refPrice = SymbolInfoDouble(symbol, SYMBOL_BID);
      if(point <= 0.0 || refPrice <= 0.0)
        {
         m_intervalPts = 0;                        // 报价未就绪：留给 SyncGrid 下次重算
         return;
        }

      int intDigits = (int)MathFloor(MathLog(refPrice) / MathLog(10.0)) + 1;   // 整数部分位数
      if(intDigits < 1)
         intDigits = 1;
      int totalDigits = intDigits + digits;                                    // 展示位数

      bool isGold  = IsGoldSymbol(symbol);
      bool isIndex = (!isGold) && IsIndexSymbol(symbol);
      int  expo    = totalDigits - 3 + ((isGold || isIndex) ? 1 : 0);          // 金银/股指档位宽 10 倍

      double pts = MathPow(10.0, (double)expo);
      if(pts < 1.0)
         pts = 1.0;
      if(pts > 1e9)
         pts = 1e9;
      m_intervalPts = (int)MathRound(pts);

      double gridPrice = m_intervalPts * point;
      string tag = isGold ? " [黄金档]" : (isIndex ? " [股指档]" : " [通用档]");
      Print("网格自动定档(", symbol, ")：价格 ", DoubleToString(refPrice, digits),
            " = ", totalDigits, " 位(", intDigits, " 整数 + ", digits, " 小数)", tag,
            " -> 间隔 ", m_intervalPts, " 点 = ", DoubleToString(gridPrice, digits),
            "，八等分每份 ", DoubleToString(gridPrice / 8.0, digits + 1));
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

      //--- 对象名前缀带图表ID：模板/同一模板复制到多图表时不互相覆盖
      m_prefix = "MSGL_" + IntegerToString((int)ChartID()) + "_";

      if(!m_cfg.Enabled)
         return(true);

      m_stateInt.last_time  = 0;
      m_stateInt.last_price = 0;
      m_stateMid.last_time  = 0;
      m_stateMid.last_price = 0;
      m_lastUpdate          = 0;

      if(m_cfg.AutoDetect)
         DetectInterval(symbol);
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
      //--- 前缀为空时 ObjectsDeleteAll(0,"") 会删光整张图表的对象，必须拦住
      if(StringLen(m_prefix) > 1)
         ObjectsDeleteAll(0, m_prefix);
     }

   //--- 刷新：内部节流，距上次同步不足间隔秒数则跳过
   //    由主指标 OnCalculate / OnTimer 调用（定时器周期为1秒）
   //    返回 true = 本轮确实改动了对象（调用方据此决定是否重绘）
   bool               Update(const string symbol,const ENUM_TIMEFRAMES tf)
     {
      if(!m_cfg.Enabled)
         return(false);
      if(TimeCurrent() - m_lastUpdate < m_cfg.UpdateSeconds)
         return(false);
      return(SyncGrid(symbol, tf));
     }
  };

#endif // __GRIDLINES_MQH__
