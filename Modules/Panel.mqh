//+------------------------------------------------------------------+
//|                                                     Panel.mqh    |
//|  模块10：图表快捷面板（一键开关各模块）                            |
//|                                                                  |
//|  背景：MQL5 指标的 input 参数在运行时不可修改，改参数必须重新初始化。  |
//|  本面板不改 input，只维护「运行时覆盖」数组 g_runOn[]：              |
//|    · 打开/关闭立即生效（不清空 input、不重载指标）                   |
//|    · 重启终端 / 切换周期 / 改任一参数后，状态回到 input 的默认值      |
//|    · 面板状态不写入 .set 预设                                      |
//|                                                                  |
//|  UI：右上角一组 OBJ_BUTTON + 一块 OBJ_RECTANGLE_LABEL 背板          |
//|    · 开 = 深绿底白字；关 = 深灰底浅灰字                             |
//|    · 点击由主指标 OnChartEvent(CHARTEVENT_OBJECT_CLICK) 处理       |
//|                                                                  |
//|  对象名：MSPN_<ChartID>_BG / MSPN_<ChartID>_B_<模块ID>             |
//+------------------------------------------------------------------+
#ifndef __PANEL_MQH__
#define __PANEL_MQH__

//--- 面板配置体
struct PanelSettings
  {
   bool   Enabled;        // 面板总开关
   int    X;              // 距右上角距离（像素，越大越靠左）
   int    Y;              // 距顶部距离（像素）
   int    BtnW;           // 按钮宽
   int    BtnH;           // 按钮高
   int    Cols;           // 列数
   int    FontSize;       // 字号
  };

//+------------------------------------------------------------------+
//| 快捷面板模块                                                      |
//+------------------------------------------------------------------+
class CPanelModule
  {
private:
   PanelSettings  m_cfg;
   string         m_prefix;      // MSPN_<ChartID>_
   string         m_bg;          // 背板对象名
   int            m_ids[];       // 按钮 -> 模块ID
   string         m_labels[];    // 按钮文字
   bool           m_created;
   int            m_rows;

   //--- 按钮对象名
   string             BtnName(const int id) const
     {
      return(m_prefix + "B_" + IntegerToString(id));
     }

   void               StyleButton(const int id,const bool on)
     {
      string name = BtnName(id);
      if(ObjectFind(0, name) < 0)
         return;
      //--- 开：深绿底 + 白字；关：深灰底 + 浅灰字
      ObjectSetInteger(0, name, OBJPROP_BGCOLOR,     on ? (color)C'0,90,40'    : (color)C'55,55,55');
      ObjectSetInteger(0, name, OBJPROP_COLOR,       on ? clrWhite            : (color)C'175,175,175');
      ObjectSetInteger(0, name, OBJPROP_BORDER_COLOR,on ? (color)C'0,150,70'   : (color)C'85,85,85');
      ObjectSetInteger(0, name, OBJPROP_STATE,       false);   // 不用按下态，靠颜色表达
     }

public:
                     CPanelModule(void) : m_prefix("MSPN_"), m_bg(""), m_created(false), m_rows(0) {}
                    ~CPanelModule(void) { Release(); }

   bool               Enabled(void) const { return(m_cfg.Enabled && m_created); }

   //--- 命中测试：返回按钮对应的模块ID，非本面板返回 -1
   int                HitTest(const string obj_name)
     {
      if(!m_created)
         return(-1);
      int n = ArraySize(m_ids);
      for(int i = 0; i < n; i++)
         if(obj_name == BtnName(m_ids[i]))
            return(m_ids[i]);
      return(-1);
     }

   //--- 重建按钮颜色（调用方在状态变化后调用）
   void               Refresh(const bool &states[])
     {
      if(!m_created)
         return;
      int n = ArraySize(m_ids);
      for(int i = 0; i < n; i++)
        {
         int id = m_ids[i];
         if(id >= 0 && id < ArraySize(states))
            StyleButton(id, states[id]);
        }
     }

   //--- 初始化：创建背板与按钮
   bool               Create(const PanelSettings &cfg,const int &ids[],const string &labels[])
     {
      m_cfg = cfg;
      if(!m_cfg.Enabled)
         return(true);

      m_prefix = "MSPN_" + IntegerToString((int)ChartID()) + "_";
      m_bg     = m_prefix + "BG";

      //--- 清理同族但非本实例的遗留（模板套用到其他图表后 ChartID 不匹配）
      int stale = 0;
      for(int i = ObjectsTotal(0, 0, -1) - 1; i >= 0; i--)
        {
         string nm = ObjectName(0, i, 0, -1);
         if(StringFind(nm, "MSPN_") != 0)
            continue;
         if(StringFind(nm, m_prefix) == 0)
            continue;
         if(ObjectDelete(0, nm))
            stale++;
        }
      if(stale > 0)
         PrintFormat("Panel: cleaned %d stale object(s)", stale);

      int n = ArraySize(ids);
      if(n <= 0)
         return(true);

      int cols = (m_cfg.Cols > 0) ? m_cfg.Cols : 1;
      int rows = (n + cols - 1) / cols;

      ArrayResize(m_ids, n);
      ArrayResize(m_labels, n);
      for(int i = 0; i < n; i++)
        {
         m_ids[i]    = ids[i];
         m_labels[i] = labels[i];
        }

      int gap  = 4;
      int pad  = 6;
      int btnW = (m_cfg.BtnW > 20) ? m_cfg.BtnW : 78;
      int btnH = (m_cfg.BtnH > 12) ? m_cfg.BtnH : 22;
      int fs   = (m_cfg.FontSize > 5) ? m_cfg.FontSize : 9;

      int panelW = cols * (btnW + gap) - gap + pad * 2;
      int panelH = rows * (btnH + gap) - gap + pad * 2;

      //--- 背板（先建，保证在按钮下层）
      if(ObjectFind(0, m_bg) >= 0)
         ObjectDelete(0, m_bg);
      if(!ObjectCreate(0, m_bg, OBJ_RECTANGLE_LABEL, 0, 0, 0))
        {
         Print(__FUNCTION__, ": 创建面板背板失败, err=", GetLastError());
         return(false);
        }
      ObjectSetInteger(0, m_bg, OBJPROP_CORNER,     CORNER_RIGHT_UPPER);
      ObjectSetInteger(0, m_bg, OBJPROP_XDISTANCE,  m_cfg.X);
      ObjectSetInteger(0, m_bg, OBJPROP_YDISTANCE,  m_cfg.Y);
      ObjectSetInteger(0, m_bg, OBJPROP_XSIZE,      panelW);
      ObjectSetInteger(0, m_bg, OBJPROP_YSIZE,      panelH);
      ObjectSetInteger(0, m_bg, OBJPROP_BGCOLOR,    (color)C'28,28,28');
      ObjectSetInteger(0, m_bg, OBJPROP_BORDER_TYPE, BORDER_FLAT);
      ObjectSetInteger(0, m_bg, OBJPROP_COLOR,      (color)C'70,70,70');
      ObjectSetInteger(0, m_bg, OBJPROP_BACK,       false);
      ObjectSetInteger(0, m_bg, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, m_bg, OBJPROP_HIDDEN,     true);

      //--- 按钮：右上角锚点 => 列索引越大越靠左
      for(int i = 0; i < n; i++)
        {
         int id = m_ids[i];
         string name = BtnName(id);
         if(ObjectFind(0, name) >= 0)
            ObjectDelete(0, name);
         if(!ObjectCreate(0, name, OBJ_BUTTON, 0, 0, 0))
           {
            Print(__FUNCTION__, ": 创建按钮失败 id=", id, " err=", GetLastError());
            continue;
           }
         int row = i / cols;
         int col = i % cols;
         int x   = m_cfg.X + pad + (cols - 1 - col) * (btnW + gap);
         int y   = m_cfg.Y + pad + row * (btnH + gap);

         ObjectSetInteger(0, name, OBJPROP_CORNER,      CORNER_RIGHT_UPPER);
         ObjectSetInteger(0, name, OBJPROP_XDISTANCE,   x);
         ObjectSetInteger(0, name, OBJPROP_YDISTANCE,   y);
         ObjectSetInteger(0, name, OBJPROP_XSIZE,       btnW);
         ObjectSetInteger(0, name, OBJPROP_YSIZE,       btnH);
         ObjectSetInteger(0, name, OBJPROP_FONTSIZE,    fs);
         ObjectSetString (0, name, OBJPROP_FONT,        "Microsoft YaHei");
         ObjectSetString (0, name, OBJPROP_TEXT,        m_labels[i]);
         ObjectSetInteger(0, name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
         ObjectSetInteger(0, name, OBJPROP_BACK,        false);
         ObjectSetInteger(0, name, OBJPROP_SELECTABLE,  false);
         ObjectSetInteger(0, name, OBJPROP_HIDDEN,      true);
         StyleButton(id, true);                 // 初始一律按「开」上色，随后由 Refresh 校正
        }

      m_rows    = rows;
      m_created = true;
      return(true);
     }

   //--- 释放：删除背板与全部按钮
   void               Release(void)
     {
      if(StringLen(m_prefix) > 1)
        {
         ObjectsDeleteAll(0, m_prefix);
        }
      m_created = false;
      ArrayResize(m_ids, 0);
      ArrayResize(m_labels, 0);
     }
  };

#endif // __PANEL_MQH__
//+------------------------------------------------------------------+
