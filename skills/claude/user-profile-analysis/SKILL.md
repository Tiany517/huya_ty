---
name: user-profile-analysis
description: "端到端用户画像分析系统，支持K-Means聚类和TGI双组对比分析。当用户需要分析用户画像、通过聚类做用户分群、用TGI对比两组用户差异、理解用户人口属性/行为/偏好时使用此技能。触发词：用户画像、user profile、聚类分析、TGI分析、用户分群、用户对比、画像分析、persona analysis、user segmentation。支持单组深度分析和双组TGI对比两种模式。"
license: Proprietary. LICENSE.txt has complete terms
---

# 用户画像分析系统

端到端用户画像分析流水线：数据清洗 → EDA → 特征工程 → K-Means聚类（肘部法则验证）→ TGI对比 → Word报告 + Excel数据。

**业务背景适配**：本技能当前适配虎牙直播平台的商业分析场景。分析结论和运营建议需始终站在虎牙视角：
- 关注用户的消费/付费潜力（财富评分、有车率、有房率、高端设备/App使用率）
- 关注用户的App偏好（为虎牙内容推荐和渠道合作提供数据支撑）
- 关注用户的游戏偏好（为虎牙游戏联运和赛事直播提供策略指引）
- 报告首页必须给出清晰明了的商业结论，回答"值不值得投入、怎么投、投给谁"三个核心问题

## 分析前检查清单

编写任何代码之前，确认以下事项：

1. **Python环境**: 使用用户的venv `C:\Users\tiany\.venv\Scripts\python.exe` (Python 3.14+)。依赖包：pandas, numpy, matplotlib, seaborn, scikit-learn, scipy, python-docx, openpyxl, Pillow。
2. **中文字体**: 用户机器上已确认存在 Microsoft YaHei（微软雅黑）位于 `C:\Windows\Fonts\msyh.ttc`。这是首要字体——必须使用它、验证它已加载、并在报告中注明。
3. **输出位置**: 桌面 (`C:\Users\tiany\Desktop\`)。两份文件：`<项目名>报告.docx` + `<项目名>数据.xlsx`。图表存入桌面 `<项目名>_charts/` 子文件夹。
4. **数据编码**: 中文CSV文件始终使用 `utf-8-sig`。

## 两种分析模式

### 模式一：单组深度分析
一份用户数据CSV → 完整流程：清洗、EDA、年龄分层、K-Means聚类（肘部法则验证）、画像解读、可视化、Word报告。

### 模式二：双组TGI对比（最常用）
一份含`user_type`列的CSV（或两份CSV）→ 拆分为目标组和对照组 → 对比EDA → 全维度TGI指数 → 对目标组做K-Means聚类 → 差异洞察 → Word + Excel报告。

## 完整分析步骤（必须按顺序执行）

### 第一步：数据加载与清洗

```python
df = pd.read_csv(path, encoding='utf-8-sig')
# 按 user_ukey 去重
df = df.drop_duplicates(subset='user_ukey', keep='first')
# 按 user_type 拆分
target_df = df[df['user_type'] == TARGET_LABEL].copy()
control_df = df[df['user_type'] == CONTROL_LABEL].copy()
```

必须报告：总行数、去重数量、目标组/对照组人数、年龄范围/均值/中位数、性别分布、前5缺失列及缺失率。

### 第二步：特征工程

对两组数据添加以下派生特征：

```python
AGE_BINS = [0, 20, 25, 30, 35, 45, 100]
AGE_LABELS = ['20岁及以下', '21-25岁', '26-30岁', '31-35岁', '36-45岁', '46岁以上']
df['age_group'] = pd.cut(df['age'], bins=AGE_BINS, labels=AGE_LABELS, right=True)
df['age_filled'] = df['age'].fillna(df['age'].median())
df['device_price_filled'] = df['device_marketed_price'].fillna(df['device_marketed_price'].median())

# 财富评分：对所有二值标签求和（共10个）
BINARY_WEALTH = ['has_elite_house', 'has_house', 'has_car', 'has_high_level_app',
                 'has_high_level_device', 'is_travel_abroad', 'is_in_famouse_company',
                 'is_school_staff', 'is_in_university', 'is_from_village']
for col in BINARY_WEALTH:
    df[col + '_num'] = pd.to_numeric(df[col], errors='coerce').fillna(0).astype(int)
df['wealth_score'] = df[[c+'_num' for c in BINARY_WEALTH]].sum(axis=1)
```

聚类编码：
```python
CAT_FEATURES = ['gender', 'education_background', 'life_status', 'travel_type',
                'device_brand', 'device_os', 'game_like', 'game_act_degree',
                'app_level_1_category', 'app_level_2_category']
# 对每个分类特征做 LabelEncoder，然后对 [age_filled, device_price_filled, wealth_score] + 编码后的分类特征 做 StandardScaler
```

### 第三步：TGI分析（双组模式）

**公式**: TGI = (目标组占比% / 对照组占比%) × 100

关键注意事项——处理 Pandas 3.x 的分类列：
```python
def compute_tgi(col, t_df, c_df):
    # 必须先用 .astype(object) 转换，Pandas 3.x 的分类列不允许 fillna 加入新类别
    t_series = t_df[col].astype(object).fillna('未知')
    c_series = c_df[col].astype(object).fillna('未知')
    t_pct = t_series.value_counts(normalize=True) * 100
    c_pct = c_series.value_counts(normalize=True) * 100
    # ... 计算 TGI = (t_pct / c_pct) * 100
```

需要计算TGI的维度：
- 人口属性：age_group, gender, education_background, life_status
- 行为特征：travel_type, game_like, game_act_degree
- 设备信息：device_brand
- 内容偏好：app_level_1_category, app_level_2_category
- 二值财富标签：全部10个标签

解读标准：
- **TGI > 120**: 目标组显著过表达（这是目标组的"特色"标签）
- **TGI < 80**: 目标组显著欠表达（该属性在目标组中占比偏低）
- **TGI 80-120**: 无显著差异
- **TGI = 0**: 目标组中该属性为零（过滤掉以保持可读性）

输出：`tgi_full.csv`，按TGI降序排列。

### 第四步：K-Means聚类 + 肘部法则验证

这是最关键的建模步骤。必须生**三联图**：

```
┌─────────────────────────────────────────────────┐
│  面板1: SSE肘部曲线                               │
│  X轴: K (2-9)，Y轴: SSE (inertia)               │
│  红色虚线标注 K=4（推荐值）                        │
│  标注："K=4 (推荐)"                               │
├─────────────────────────────────────────────────┤
│  面板2: SSE边际下降率柱状图                        │
│  X轴: K (2-9)，Y轴: SSE下降率%                    │
│  红色虚线：15%阈值线                              │
│  标注："低于15%后不再新增K"                       │
│  每个柱子上标注下降率数值                          │
├─────────────────────────────────────────────────┤
│  面板3: 轮廓系数曲线                              │
│  X轴: K (2-9)，Y轴: 轮廓系数                      │
│  绿色虚线标注最佳K值                              │
│  标注："最佳K=N (轮廓系数=X.XXXX)"               │
└─────────────────────────────────────────────────┘
```

**K值选择逻辑**:
1. 从轮廓系数峰值出发
2. 结合肘部法则拐点（SSE下降率 < 15%）
3. 优先选择 K=4 或 K=5 以保证可解释性
4. 若轮廓系数单调递增，采用肘部法则的 K=4-5

**模型质量评估指标**:
- 最终轮廓系数及评级：
  - > 0.50: "聚类结构优秀"
  - 0.30-0.50: "聚类结构良好"
  - < 0.30: "聚类结构一般（数据本身同质性较高）"
- PCA累计解释方差比（2个主成分）
- 层次聚类树状图（Ward法，采样500）做可视化验证

### 第五步：聚类可视化（共23张图，全部无背景网格线）

**关键要求：所有图表去除背景网格线。**

```python
sns.set_style("white")  # 不是 "whitegrid"
plt.rcParams['axes.grid'] = False  # 全局关闭网格线
```

**聚类相关（5张）：**
1. `00_kmeans_elbow.png` — K值选择三联图（SSE + 下降率 + 轮廓系数）
2. `01_cluster_pca.png` — PCA二维投影，聚类中心用X标注
3. `02_cluster_pie.png` — 聚类占比饼图
4. `03_cluster_heatmap.png` — 13个特征的热力图（归一化）
5. `04_cluster_radar.png` — 各聚类雷达图（8维度：男性占比、平均年龄、财富评分、设备均价、iOS占比、游戏高活跃、音乐App、已婚率）

**验证（1张）：**
6. `05_dendrogram.png` — 层次聚类树状图（Ward法，采样500）

**年龄分层（3张）：**
7. `06_age_distribution.png` — 年龄分布柱状图（标注人数和占比）
8. `07_age_app_stack.png` — 年龄×App堆叠图
9. `08_age_game_heatmap.png` — 年龄×游戏热力图

**双组对比（8张，含新增的绝对值对比图）：**
10. `09_comparison_age.png` — 年龄分布对比（柱上标绝对占比）
11. `10_comparison_gender.png` — 性别双饼图
12. `11_comparison_device.png` — 设备品牌对比（柱上标绝对占比）
13. `12a_comparison_app_absolute.png` — **NEW** App偏好绝对值对比
14. `12b_comparison_app_diff.png` — App偏好差异分析
15. `13a_comparison_game_absolute.png` — **NEW** 游戏偏好绝对值对比
16. `13b_comparison_game_diff.png` — 游戏偏好差异分析
17. `14_comparison_wealth_radar.png` — 财富/身份标签雷达图
18. `15_comparison_edu.png` — 学历分布对比（柱上标绝对占比）

**TGI可视化（1张）：**
19. `16_tgi_heatmap.png` — TGI关键差异热力图（RdBu_r色系，center=100）

**财富与App深度分析（4张，虎牙商业化核心）：**
20. `17_wealth_distribution.png` — 财富评分分布直方图+箱线图对比：直观展示两组消费力差异
21. `18_app_tgi_ranking.png` — App一级分类TGI排序柱状图：标注每组绝对占比值，直接指导虎牙内容推荐策略
22. `19_wealth_cluster_cross.png` — 各聚类财富/消费力指标交叉分析：左图有车/有房/高端App/高端设备四指标对比，右图高消费潜力用户占比
23. `20_cluster_app_breakdown.png` — 各聚类Top5 App偏好对比：为虎牙分群内容运营提供数据支撑

**V2新增规范**：对于App偏好和游戏偏好，必须先展示绝对值对比柱状图（两组并排，标注各自的绝对占比%），再展示差异图。绝对值图的数据标签必须清晰可见。

### 第六步：聚类自动命名

命名规则: `[设备品牌][App偏好]派`

```python
# 使用第2位App类目（非第一）做区分——第1位往往都是"音乐"
# 若发生命名冲突，追加"N号派"
# 特殊情况：若设备品牌为"IPAD"，使用"iPad"
```

### 第七步：Word报告结构（纵向排版，10章，虎牙商业分析视角）

**报告必须为纵向A4排版，不可横向。**

```python
section.orientation = WD_ORIENT.PORTRAIT
section.page_width = Cm(21.0)
section.page_height = Cm(29.7)
```

**第一章：核心商业结论（放在首页，虎牙商业分析视角）**

**必须包含一段完整的总结段落**，格式要求：
- 一段连续文字覆盖所有核心维度，关键数字用 **加粗** 标注
- 使用 `add_bold_para(parts)` 函数（`parts = [(text, bold), ...]`），每个 run 独立设置 font + eastAsia
- 段落模板如下（以世锦赛分析为例，实际数据从 DataFrame 动态计算）：

> 观看世锦赛超过10分钟的用户共**X.XX万人**（占总样本**XX.X%**），核心特征鲜明：以**男性为主（XX.X%）**，年龄呈现"两极分化"——**46岁以上群体TGI高达XXX**，是最显著的高粘性群体，而**26-35岁人数最多（XX.X%）**；学历上**本科及以上占比达XX.X%**，**博士学历TGI最高（XXX）**；设备偏好中**华为用户最多（X.X万人，XX.X%）且TGI达XXX**，OPPO、荣耀也表现出明显偏好；游戏兴趣方面，**体育类和棋牌中心TGI分别达XXX和XXX**，显示出对竞技性内容的强烈偏好。整体来看，**中年高学历男性、使用华为设备、热爱棋牌竞技游戏**是目标用户的典型画像。

- 段落之后跟 2-3 句补充判断：用户价值判断、聚类速览一句话、运营方向建议
- 关键数字预处理：从 TGI DataFrame 和原始数据中提取，避免硬编码
- 段落行间距 1.5-1.6，字号 11pt，加粗部分必须同时设置 `font.name` 和 `_element.rPr.rFonts.set(qn('w:eastAsia'), ...)`

**第二章：财富/消费力深度分析** — 财富分布直方图+箱线图、财富雷达图、聚类消费力交叉分析（虎牙商业化核心）
**第三章：App偏好深度分析** — App TGI排序图、绝对值对比图、差异图、各聚类App偏好分解（虎牙内容策略核心）
**第四章：TGI对比分析** — 聚焦游戏/App/活跃度等虎牙业务最相关维度，精简TGI速览表 + 热力图
**第五章：K-Means聚类分析** — K值选择过程、PCA投影、聚类分布、热力图、雷达图、层次聚类验证
**第六章：聚类画像速览（虎牙运营视角）** — 每个聚类一页：核心指标+Top偏好+虎牙运营策略建议+价值评级(★★★/★★/★)
**第七章：双组对比可视化** — 紧凑排版，每张图+1句分析，减少文字堆砌
**第八章：模型质量评估** — 聚类算法、K值、轮廓系数、PCA方差、验证方法表格
**第九章：虎牙运营策略建议** — 四大板块：投放策略、内容策略、商业化策略、渠道合作、数据治理建议
**第十章：附录** — 图表索引

**每个图表必须附带**:
1. 图表标题
2. 1-2句简短分析说明（含关键数字）
3. 表格类数据在表格前加一句话概述

### 第八步：Excel数据输出（5个Sheet）

1. **TGI完整数据** — 所有TGI值，按TGI降序。条件着色：TGI>120红色、TGI<80且>0绿色
2. **聚类画像汇总** — 每个聚类一行，含昵称、人数、占比、核心指标
3. **K-Means模型评估** — K=2..9指标表
4. **年龄分层** — 两组各年龄段的绝对值和占比
5. **目标组含聚类标签** — 用户级数据带聚类分配

## 至关重要的中文字体设置

这是用户机器上验证通过的准确字体设置，不可修改或简化：

```python
import matplotlib
matplotlib.use('Agg')

# 关键：删除matplotlib字体缓存，防止旧字体引用导致乱码
import os, glob as _glob
_cache = matplotlib.get_cachedir()
for _f in _glob.glob(os.path.join(_cache, '*')):
    try: os.remove(_f)
    except: pass

# 使用 Microsoft YaHei —— 已在用户机器上验证通过
_CJK_PATH = r'C:\Windows\Fonts\msyh.ttc'
assert os.path.exists(_CJK_PATH), f"字体文件不存在: {_CJK_PATH}"

import matplotlib.pyplot as plt
import matplotlib.font_manager as fm

fm.fontManager.addfont(_CJK_PATH)
_FONT_NAME = fm.FontProperties(fname=_CJK_PATH).get_name()
# _FONT_NAME 的值是 "Microsoft YaHei"

plt.rcParams['font.family'] = 'sans-serif'
plt.rcParams['font.sans-serif'] = [_FONT_NAME]
plt.rcParams['axes.unicode_minus'] = False
fm._load_fontmanager(try_read_cache=False)

# 重点：在 seaborn 导入之后必须重新设置字体参数
import seaborn as sns
sns.set_style("white")  # 注意：使用white而非whitegrid，去除背景网格线
sns.set_palette("Set2")
plt.rcParams['font.family'] = 'sans-serif'
plt.rcParams['font.sans-serif'] = [_FONT_NAME]
plt.rcParams['axes.unicode_minus'] = False
plt.rcParams['axes.grid'] = False  # 全局关闭网格线

# 验证：应输出 "Microsoft YaHei" 及 4 个变体
actual = [f for f in fm.fontManager.ttflist if _FONT_NAME in f.name]
print(f"[字体] 使用: {_FONT_NAME} ({_CJK_PATH}), 已加载 {len(actual)} 个变体")
```

**字体验证清单（提交前确认）：**
1. ✅ `_FONT_NAME` = "Microsoft YaHei"
2. ✅ `len(actual)` ≥ 3（至少3个字体的变体已加载）
3. ✅ 所有图表标题/坐标轴标签使用中文字符（非□□□乱码）
4. ✅ Word文档中明确注明字体名称和路径
5. ✅ 所有图表背景无网格线（灰/白色纯色背景）

## 报告质量检查清单

提交前逐项确认：

- [ ] 23张图表全部生成，中文无乱码
- [ ] 所有图表无背景网格线（sns.set_style("white") + axes.grid = False）
- [ ] K-Means肘部法则：三联图（SSE + 下降率 + 轮廓系数）
- [ ] 模型质量：轮廓系数 + 评级 + PCA方差 + 层次聚类验证
- [ ] App/游戏对比：先绝对值图再差异图，柱上标绝对占比值
- [ ] TGI：完整CSV + 热力图 + Word中过表达/欠表达表格
- [ ] Word报告(.docx)：纵向A4，首页核心结论，9章完整内容
- [ ] Excel(.xlsx)：5个Sheet，TGI有条件着色
- [ ] 聚类命名遵循 [设备品牌][App偏好]派 规则
- [ ] 每个图表配1-2句分析文字
- [ ] 表格数据前有一句话概述
- [ ] 所有文件输出到桌面
- [ ] 字体名称（Microsoft YaHei）和路径在报告中明确注明

## 常见问题与解决方法

| 问题 | 解决方法 |
|------|----------|
| Pandas 3.x 分类列fillna报错 `TypeError: Cannot setitem on a Categorical` | 使用 `.astype(object).fillna('未知')` 替代 `.fillna('未知')` |
| Seaborn导入后中文字体被覆盖 | 在 `sns.set_style()` 之后重新设置 `plt.rcParams['font.sans-serif']` |
| 财富雷达图标签数量与数据列数不匹配 | 确保 `wealth_labels` 列表长度与 `BINARY_WEALTH` 列数一致 |
| TGI出现 inf 或 0 值（极度稀疏的属性） | 筛选 `TGI>0` 且在两组中至少有一组人数≥5 |
| 字体缓存导致旧字体引用 | 在导入 pyplot 之前删除 matplotlib 缓存目录 |
| 聚类命名冲突（两个聚类都叫"华为视频派"） | 追加聚类编号：如"华为视频3号派" |
| Word报告横向排版 | 检查 `WD_ORIENT.PORTRAIT` 和页面尺寸设置为A4纵向 |
| 图表有灰色背景网格线 | 确认使用 `sns.set_style("white")` 且 `plt.rcParams['axes.grid'] = False` |

## 参考脚本

完整的 Python 实现位于 `scripts/` 目录。实际使用时，优先采用本 SKILL.md 中记录的已实战验证的流程，而非旧版脚本。

所有图表参数、报告结构、字体设置均以本文档为准。遇到任何与本skill不一致的情况，以本文档为准。
