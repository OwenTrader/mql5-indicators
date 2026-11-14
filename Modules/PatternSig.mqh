//+------------------------------------------------------------------+
//|                                                  PatternSig.mqh  |
//|  模块8：形态识别（涨-回调-涨 / 跌-反弹-跌）                        |
//|                                                                  |
//|  规则：                                                            |
//|   · 多头形态 = x 根连续阳线 + y 根连续阴线 + z 根连续阳线           |
//|   · 空头形态 = x 根连续阴线 + y 根连续阳线 + z 根连续阴线（镜像）    |
//|   · 实体 < MinBodyPoints 的K线（含十字星）一律「忽略」：既不计数、    |
//|     也不打断连续性，可出现在形态段内任意位置                        |
//|   · 命中后对「整段」（从第一段起点到最后一根）着色，含被忽略的小实体  |
//|                                                                  |
//|  根数口径（v1.30）：                                               |
//|   · x、z 必须 >= 2（首尾两段是形态主体，1 根不构成"段"）           |
//|   · y 是【上限】：1..y 根反向K线都算命中 —— 回调/反弹常常只有 1 根，  |
//|     y 设为 2 时 阳阴阳 与 阳阴阴阳阳 都命中                        |
//|                                                                  |
//|  严格性（只作用于 x / z 两段）：                                    |
//|   · AllowLonger=false（默认）：x、z 必须【恰好】等于设定值，         |
//|     即 阳阳阳阴阴阳阳 不算 阳阳阴阴阳阳（首段 3 根 ≠ 2 根）           |
//|   · AllowLonger=true：x、z 可「至少」设定值，整段一起着色            |
//|                                                                  |
//|  颜色（v1.35）：三段分色，形态含义一眼可辨                             |
//|   · 首段 / 末段（形态主体）：按方向 阳=绿(索引0) / 阴=红(索引1)        |
//|   · 回调段（中段）：统一灰色(索引2)，不区分阴阳                        |
//|   · 小实体 / 十字星：一律灰色(索引2)，无论处在段内哪个位置              |
//|   于是「涨-回调-涨」= 绿 绿 灰 灰 绿 绿；「跌-反弹-跌」= 红 红 灰 灰 红 红|
//|                                                                  |
//|  去重（避免重复绘制）：                                             |
//|   · 判定前先做 O(1) 剪枝：末根被忽略(小实体)则不可能有形态以其收尾，直接跳过|
//|   · 主指标写缓冲区前比对「已绘制值」，同色同价则跳过写，重叠形态不重复落笔|
//|                                                                  |
//|  设计约定（同其他模块）：                                          |
//|  · 模块内不定义 input，参数由主指标通过 struct 传入                 |
//|  · 模块不持有句柄/图形对象，只做「价格序列 -> 是否命中 + 段范围」判定 |
//|  · 缓冲区写入由主指标负责（DRAW_COLOR_CANDLES 的 plot 归主指标）     |
//+------------------------------------------------------------------+
#ifndef __PATTERN_SIG_MQH__
#define __PATTERN_SIG_MQH__

//--- 模块配置体
struct PatternSettings
  {
   bool     Enabled;        // 启用形态识别
   int      X;              // 第一段连续根数（>=2，与末段同向）
   int      Y;              // 第二段反向根数【上限】（1..Y 均命中）
   int      Z;              // 第三段连续根数（>=2，决定形态方向）
   double   MinBodyPoints;  // 小实体忽略阈值（点，小于此值不计数）
   bool     AllowLonger;    // true=x/z 段可长于设定根数
  };

//+------------------------------------------------------------------+
//| 形态识别模块类                                                    |
//+------------------------------------------------------------------+
class CPatternModule
  {
private:
   PatternSettings m_cfg;
   double          m_point;     // 品种点值

   //--- 单根K线的计数方向：+1 阳 / -1 阴 / 0 小实体(忽略)
   int                DirAt(const int i,const double &open[],const double &close[])
     {
      if(m_point <= 0.0)
         return(0);
      double body = MathAbs(close[i] - open[i]) / m_point;
      if(body < m_cfg.MinBodyPoints)
         return(0);
      if(close[i] > open[i])
         return(1);
      if(close[i] < open[i])
         return(-1);
      return(0);
     }

   //--- 从 p 向前数「连续 dir 方向」的计数K线，跳过小实体
   //    结束时 p 停在打断该段的那根计数K线（或 -1 = 序列起点之前）
   //    runFirst / runNewest 输出该段最早 / 最新的一根【计数K线】的索引（-1 = 该段为空）
   //    这两个边界用于把「回调段」单独框出来着色
   int                CountRun(int &p,const int dir,const double &open[],const double &close[],
                               int &runFirst,int &runNewest)
     {
      int cnt = 0;
      runFirst  = -1;
      runNewest = -1;
      while(p >= 0)
        {
         int d = DirAt(p, open, close);
         if(d == 0)                       // 小实体：忽略、不计数、不打断
           {
            p--;
            continue;
           }
         if(d != dir)
            break;
         if(runNewest < 0)
            runNewest = p;                // 首次命中 = 该段最新的一根
         runFirst = p;                    // 持续更新 = 最终为最早的一根
         cnt++;
         p--;
        }
      return(cnt);
     }

   //--- 判定「以 i 结尾、末段方向 = dir」的形态
   //    命中返回 dir，失败返回 0
   //    startBar 输出段起点（含被忽略的小实体）
   //    midFrom / midTo 输出回调段（中段）区间 [midFrom, midTo]，该区间统一画灰色
   int                MatchDir(const int i,const double &open[],const double &close[],
                               int &startBar,int &midFrom,int &midTo,const int dir)
     {
      int p = i;
      int lastFirst = -1, lastNewest = -1;
      int midFirst  = -1, midNewest  = -1;
      int firstFirst= -1, firstNewest= -1;

      int lastCnt = CountRun(p, dir, open, close, lastFirst, lastNewest);   // 末段（z 根）
      if(lastCnt < m_cfg.Z)
         return(0);

      int midCnt = CountRun(p, -dir, open, close, midFirst, midNewest);     // 中段（1..y 根）
      if(midCnt < 1 || midCnt > m_cfg.Y)                                   // y 是上限
         return(0);

      int firstCnt = CountRun(p, dir, open, close, firstFirst, firstNewest); // 首段（x 根）
      if(firstCnt < m_cfg.X)
         return(0);

      //--- 严格模式：x / z 两段必须精确相等（y 已按上限判定，不参与精确比较）
      if(!m_cfg.AllowLonger &&
         (lastCnt != m_cfg.Z || firstCnt != m_cfg.X))
         return(0);

      startBar = firstFirst;
      midFrom  = firstNewest + 1;        // 首段之后（含其间的小实体）开始算回调
      midTo    = lastFirst - 1;          // 末段首根之前结束
      return(dir);
     }

public:
                     CPatternModule(void) : m_point(0.0)
     {
      m_cfg.Enabled       = false;
      m_cfg.X             = 2;
      m_cfg.Y             = 2;
      m_cfg.Z             = 2;
      m_cfg.MinBodyPoints = 22.0;
      m_cfg.AllowLonger   = false;
     }
                    ~CPatternModule(void) {}

   //--- 初始化：仅取点值（阈值以「点」为单位，与周期/品种无关）
   bool               Create(const string symbol,const ENUM_TIMEFRAMES tf,const PatternSettings &cfg)
     {
      m_cfg = cfg;
      if(!m_cfg.Enabled)
         return(true);

      if(m_cfg.X < 2 || m_cfg.Z < 2)
        {
         Print(__FUNCTION__, ": 形态根数非法(X/Z 必须 >= 2，当前 X=", m_cfg.X, " Z=", m_cfg.Z, ")");
         return(false);
        }
      if(m_cfg.Y < 1)
        {
         Print(__FUNCTION__, ": 形态根数非法(Y 必须 >= 1，当前 Y=", m_cfg.Y, ")");
         return(false);
        }

      m_point = SymbolInfoDouble(symbol, SYMBOL_POINT);
      if(m_point <= 0.0)
        {
         Print(__FUNCTION__, ": 取点值失败, err=", GetLastError());
         return(false);
        }
      return(true);
     }

   //--- 释放：无内部资源
   void               Release(void) {}

   bool               Enabled(void) const { return(m_cfg.Enabled); }

   //--- 单根K线是否为「被忽略的小实体」（十字星/实体不足阈值）
   bool               IsIgnoredBar(const int i,const double &open[],const double &close[])
     {
      return(DirAt(i, open, close) == 0);
     }

   //--- 段内单根K线的着色索引：0=阳线色(绿) / 1=阴线色(红)
   //    仅用于形态主体（首/末段）；回调段与小实体由主指标统一置灰
   int                ColorIndexOf(const int i,const double &open[],const double &close[]) const
     {
      if(close[i] < open[i])
         return(1);
      return(0);
     }

   //--- 核心：判定以 i 结尾的形态
   //    返回 +1 = 多头形态(涨-跌-涨) / -1 = 空头形态(跌-涨-跌) / 0 = 未命中
   //    startBar 输出段起点；midFrom/midTo 输出回调段区间（该区间画灰色）
   int                MatchEndingAt(const int i,const double &open[],const double &close[],
                                    int &startBar,int &midFrom,int &midTo)
     {
      startBar = i;
      midFrom  = i;
      midTo    = i - 1;                     // 空区间：默认不产生灰色
      if(!m_cfg.Enabled || i < 1 || m_point <= 0.0)
         return(0);

      //--- O(1) 剪枝：形态必须以一根「计数K线」收尾；末根被忽略(小实体)时
      //    不可能有形态正好结束在这里，直接返回，省掉反向回溯
      if(DirAt(i, open, close) == 0)
         return(0);

      int hit = MatchDir(i, open, close, startBar, midFrom, midTo, 1);
      if(hit != 0)
         return(hit);
      return(MatchDir(i, open, close, startBar, midFrom, midTo, -1));
     }
  };

#endif // __PATTERN_SIG_MQH__
