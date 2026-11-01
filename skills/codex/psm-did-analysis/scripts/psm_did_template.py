# -*- coding: utf-8 -*-
"""
=============================================================================
  PSM+DID 因果推断分析 — 通用模板脚本 (v4 核心骨架)
=============================================================================
  此模板为 psm-did-analysis skill 的 bundled scripts。
  使用时需根据实际数据替换 CONFIG 区域的配置。

  分析流程（3模块）：
    模块A：全量样本 PSM+DID
    模块B：子人群 PSM+DID（可选，通过 SUBGROUP_CONFIG 控制）
    模块C：LTV补充分析（pay_rate + ARPPU + 稀释效应诊断）

  依赖：
    pip install pandas numpy matplotlib scikit-learn scipy python-docx openpyxl
=============================================================================
"""

import pandas as pd
import numpy as np
import warnings, os, sys
from datetime import datetime

if sys.platform == 'win32':
    try:
        sys.stdout = open(sys.stdout.fileno(), mode='w', encoding='utf-8', buffering=1)
        sys.stderr = open(sys.stderr.fileno(), mode='w', encoding='utf-8', buffering=1)
    except Exception:
        pass
warnings.filterwarnings('ignore')

import matplotlib.pyplot as plt
import matplotlib
matplotlib.rcParams['font.sans-serif'] = ['Microsoft YaHei', 'SimHei']
matplotlib.rcParams['axes.unicode_minus'] = False
plt.rcParams['figure.dpi'] = 150

# ★ 图表字体统一：微软雅黑 12pt（与Word报告保持一致）
plt.rcParams['font.size'] = 12
plt.rcParams['axes.titlesize'] = 14      # 图表标题稍大
plt.rcParams['axes.labelsize'] = 12
plt.rcParams['xtick.labelsize'] = 11
plt.rcParams['ytick.labelsize'] = 11
plt.rcParams['legend.fontsize'] = 11
plt.rcParams['figure.titlesize'] = 14

from sklearn.linear_model import LogisticRegression
from sklearn.preprocessing import StandardScaler
from sklearn.neighbors import KDTree
from scipy.stats import ttest_ind, mannwhitneyu, gaussian_kde

from docx import Document
from docx.shared import Inches, Pt, Cm
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.oxml.ns import qn

import openpyxl
from openpyxl.styles import Font, Alignment, PatternFill, Border, Side
from openpyxl.utils import get_column_letter


# ============================================================
#  CONFIG — 替换为你的数据和路径
# ============================================================
BASE_DIR = r'C:\Users\tiany\Desktop\YOUR_PROJECT'   # 项目根目录
DATA_CSV = os.path.join(BASE_DIR, 'your_data.csv')   # 数据文件

# ★ 关键列名配置（根据实际数据调整）
TREATMENT_COL = 'is_treat'      # 处理变量：1=实验组, 0=对照组
USER_COL = 'user_id'            # 用户ID列

# ★ 匹配特征（PSM协变量）— 填写 before_* 列的列名
MATCH_FEATURES = [
    'before_watch_duration',
    'before_active_days',
    'before_consume_amount',
    # ... 根据实际数据补充
]

# ★ 结果变量（DID指标）— 填写 after_* 列的列名
# 格式: {after_col: before_col} 的映射字典
OUTCOME_MAPPING = {
    'after_watch_duration': 'before_watch_duration',
    'after_active_days':    'before_active_days',
    'after_consume_amount': 'before_consume_amount',
    # ... 根据实际数据补充
}

# ★ 结果变量中文标签
OUTCOME_LABELS = {
    'after_watch_duration': ('观看时长(分钟)', '分钟'),
    'after_active_days':    ('活跃天数',      '天'),
    'after_consume_amount': ('付费金额(元)',   '元'),
    # ... 根据实际数据补充
}

# ★ LT/LTV 维度分类（用于报告归类）
LT_OUTCOMES = {'after_watch_duration', 'after_active_days'}   # 活跃指标
LTV_OUTCOMES = {'after_consume_amount'}                      # 消费指标

# ★ 子人群配置（可选 — 不需要子人群分析时设为 None）
SUBGROUP_CONFIG = {
    'enabled': False,               # True = 启用子人群分析
    'filter_col': None,             # 筛选列名，如 'is_interest_dota2'
    'filter_value': 1,              # 筛选值
    'label': '子人群',              # 报告中的标签
    'exclude_from_features': None,  # 从匹配特征中排除的列，如 'is_interest_dota2'
}

# ★ LTV消费指标列名（用于 pay_rate + ARPPU 补充分析）
LTV_AMOUNT_COL = 'after_consume_amount'      # after期消费金额列
LTV_AMOUNT_BEFORE = 'before_consume_amount'  # before期消费金额列

# ★ 匹配参数
CALIPER = 0.05           # 卡钳阈值
SEED = 42
MAX_CTRL_SAMPLE = 1_500_000

# ★ 显著性阈值
ALPHA_STRICT = 0.01   # ***
ALPHA_STANDARD = 0.05  # **
ALPHA_LOOSE = 0.10     # *

# ★ 输出目录
OUT_DIR = BASE_DIR


# ============================================================
#  工具函数
# ============================================================

def safe_fillna(df, cols):
    """
    彻底填充 NaN 和 Inf。

    为什么不用 df.fillna(0)：
    - 全列填0会扭曲均值和方差，影响后续 Logit 回归的系数估计
    - 中位数填充保留了变量的中心趋势，对偏态分布更稳健
    - NaN 会导致 sklearn 的 StandardScaler 和 LogisticRegression 崩溃
    - Inf 来自除以零等边界运算，同样需要处理
    """
    df = df.copy()
    for col in cols:
        if col not in df.columns:
            continue
        df[col] = pd.to_numeric(df[col], errors='coerce')
        med = df[col].median()
        if pd.isna(med) or np.isinf(med):
            med = 0.0
        df[col] = df[col].fillna(med)
        df[col] = df[col].replace([np.inf, -np.inf], med)
        df[col] = df[col].fillna(0.0)
    return df


def calc_smd(data, feat, treat_col):
    """计算标准化均值差异 (Standardized Mean Difference)

    为什么用 SMD 而非 p 值：
    - 在大样本中，即使差异微不足道，p值也可能显著
    - SMD 是效应量指标，衡量差异的实际大小，不受样本量影响
    - |SMD| < 0.1 是经验性阈值（基于 Rubin 2001 的推荐）
    """
    t = data[data[treat_col] == 1][feat].astype(float)
    c = data[data[treat_col] == 0][feat].astype(float)
    mean_diff = t.mean() - c.mean()
    pool_var = (t.var(ddof=0) + c.var(ddof=0)) / 2
    return abs(mean_diff / np.sqrt(pool_var)) if pool_var > 1e-10 else 0.0


def sig_mark(p_val, did_effect):
    """
    显著性标记 — 同时考虑方向和强度。

    为什么区分方向：
    - 正向显著和负向显著的业务含义完全不同
    - 报告中的视觉标记（颜色、箭头）需要区分
    """
    if p_val < 0.01: stars = '***'
    elif p_val < 0.05: stars = '**'
    elif p_val < 0.1: stars = '*'
    else: stars = ''

    if p_val < 0.05 and did_effect > 0:
        return f'正向显著{stars}↑', stars + '↑'
    elif p_val < 0.05 and did_effect < 0:
        return f'负向显著{stars}↓', stars + '↓'
    elif 0.05 <= p_val < 0.1:
        return f'边缘显著{stars}?', stars + '?'
    else:
        return '不显著', ''


# ============================================================
#  可视化函数（图表字体统一：微软雅黑 12pt，通过 rcParams 全局设置）
# ============================================================

def plot_ps_distribution(matched_df, treat_col, title_suffix='', save_path=None):
    """
    倾向得分分布图（匹配后）。

    展示实验组和对照组在匹配后的倾向得分分布重叠情况。
    两组曲线越重合，说明匹配质量越高。

    字体要求：微软雅黑 12pt（通过全局 rcParams 控制）
    """
    fig, axes = plt.subplots(1, 2, figsize=(14, 5))

    # 左图：匹配前的倾向得分分布（从 matched_df 的原始数据推算）
    treat_ps = matched_df[matched_df[treat_col] == 1]['propensity_score']
    ctrl_ps = matched_df[matched_df[treat_col] == 0]['propensity_score']

    # 右图：匹配后的分布（两组都应该在 matched_df 里）
    axes[0].hist(treat_ps, bins=40, alpha=0.6, label='实验组(Treatment)',
                 color='#2196F3', edgecolor='white')
    axes[0].hist(ctrl_ps, bins=40, alpha=0.6, label='对照组(Control)',
                 color='#FF9800', edgecolor='white')
    axes[0].set_xlabel('倾向得分 (Propensity Score)')
    axes[0].set_ylabel('用户数量')
    axes[0].set_title(f'倾向得分分布（匹配后）\n{title_suffix}')
    axes[0].legend(loc='upper right')
    axes[0].grid(alpha=0.3)

    # 右图：PS分布的KDE平滑曲线
    try:
        kde_t = gaussian_kde(treat_ps)
        kde_c = gaussian_kde(ctrl_ps)
        xs = np.linspace(0, 1, 200)
        axes[1].plot(xs, kde_t(xs), color='#2196F3', linewidth=2, label='实验组')
        axes[1].plot(xs, kde_c(xs), color='#FF9800', linewidth=2, label='对照组')
        axes[1].fill_between(xs, kde_t(xs), alpha=0.15, color='#2196F3')
        axes[1].fill_between(xs, kde_c(xs), alpha=0.15, color='#FF9800')
    except Exception:
        axes[1].text(0.5, 0.5, 'KDE无法计算\n（样本量不足）',
                    ha='center', va='center', transform=axes[1].transAxes)
    axes[1].set_xlabel('倾向得分 (Propensity Score)')
    axes[1].set_title(f'倾向得分密度分布（匹配后）\n{title_suffix}')
    axes[1].legend(loc='upper right')
    axes[1].grid(alpha=0.3)

    plt.tight_layout()
    if save_path:
        plt.savefig(save_path, dpi=150, bbox_inches='tight', facecolor='white')
        print(f"  PS分布图已保存: {save_path}")
    plt.close()
    return save_path


def plot_love(balance_df, title_suffix='', save_path=None):
    """
    Love Plot — 匹配前后 SMD 对比图。

    纵轴为特征名（倒序排列），横轴为 |SMD|。
    两条虚线分别标注 0.1（通过线）和 0.2（显著不均衡线）。
    圆圈=匹配前 SMD，三角=匹配后 SMD。

    字体要求：微软雅黑 12pt（通过全局 rcParams 控制）
    """
    features = balance_df['feature'].tolist()[::-1]  # 倒序
    smd_before = balance_df['smd_before'].tolist()[::-1]
    smd_after = balance_df['smd_after'].tolist()[::-1]

    fig, ax = plt.subplots(figsize=(10, max(6, len(features) * 0.4)))

    y_pos = range(len(features))

    # 匹配前：空心圆圈
    ax.scatter(smd_before, y_pos, marker='o', s=80, color='#E53935',
               edgecolors='#E53935', linewidths=1.5, alpha=0.7, label='匹配前 (Before)',
               zorder=3)

    # 匹配后：实心三角
    ax.scatter(smd_after, y_pos, marker='^', s=80, color='#43A047',
               edgecolors='#2E7D32', linewidths=1.5, alpha=0.9, label='匹配后 (After)',
               zorder=4)

    # 连接线（展示每个特征从匹配前到匹配后的变化）
    for i in range(len(features)):
        ax.plot([smd_before[i], smd_after[i]], [y_pos[i], y_pos[i]],
                color='#9E9E9E', linewidth=0.8, alpha=0.5, zorder=1)

    # 阈值线
    ax.axvline(x=0.1, color='#FF9800', linestyle='--', linewidth=1.5, alpha=0.8,
               label='SMD = 0.1（通过线）')
    ax.axvline(x=0.2, color='#E53935', linestyle=':', linewidth=1, alpha=0.5,
               label='SMD = 0.2（显著不均衡）')

    ax.set_yticks(list(y_pos))
    ax.set_yticklabels(features)
    ax.set_xlabel('|SMD| 标准化均值差异')
    ax.set_title(f'平衡性检验 — Love Plot\n{title_suffix}')
    ax.legend(loc='lower right', framealpha=0.9)
    ax.grid(axis='x', alpha=0.3)

    plt.tight_layout()
    if save_path:
        plt.savefig(save_path, dpi=150, bbox_inches='tight', facecolor='white')
        print(f"  Love Plot已保存: {save_path}")
    plt.close()
    return save_path


def plot_did_bars(did_df, title_suffix='', save_path=None):
    """
    DID效应柱状图。

    展示各指标的DID净效应值，用颜色区分显著/不显著：
    绿色=正向显著，红色=负向显著，灰色=不显著。
    柱顶标注显著性星号。

    字体要求：微软雅黑 12pt（通过全局 rcParams 控制）
    """
    # 只取非LTV补充指标（pay_rate和ARPPU单独展示）
    main = did_df[~did_df['outcome'].str.startswith('ltv_', na=False)].copy()
    if main.empty:
        return None

    labels = main['label'].tolist()
    effects = main['did_effect'].tolist()
    sigs = main['significant'].tolist()
    marks = main['sig_mark'].tolist()

    colors = []
    for did, sig in zip(effects, sigs):
        if sig and did > 0:
            colors.append('#43A047')      # 正向显著 = 绿色
        elif sig and did < 0:
            colors.append('#E53935')      # 负向显著 = 红色
        else:
            colors.append('#BDBDBD')      # 不显著 = 灰色

    fig, ax = plt.subplots(figsize=(10, max(5, len(labels) * 0.5)))

    bars = ax.barh(range(len(labels)), effects, color=colors, edgecolor='white', height=0.6)

    # 标注显著性
    for i, (bar, mark) in enumerate(zip(bars, marks)):
        if mark:
            ax.text(bar.get_width() + (max(effects) * 0.02 if bar.get_width() >= 0 else min(effects) * 0.02),
                    bar.get_y() + bar.get_height() / 2,
                    mark.replace('*', '').replace('↑', ' ↑').replace('↓', ' ↓'),
                    va='center', fontsize=10)

    ax.set_yticks(range(len(labels)))
    ax.set_yticklabels(labels)
    ax.axvline(x=0, color='black', linewidth=0.8)
    ax.set_xlabel('DID 净效应')
    ax.set_title(f'DID 双重差分因果效应\n{title_suffix}')
    ax.grid(axis='x', alpha=0.3)
    ax.invert_yaxis()

    plt.tight_layout()
    if save_path:
        plt.savefig(save_path, dpi=150, bbox_inches='tight', facecolor='white')
        print(f"  DID柱状图已保存: {save_path}")
    plt.close()
    return save_path


# ============================================================
#  核心流水线
# ============================================================

def run_psm_pipeline(df, label_suffix='', match_features=None):
    """
    完整的 PSM+DID 流水线。

    参数:
      df: 已清洗的数据框
      label_suffix: 文件/报告标记（如 '_full' 或 '_subgroup'）
      match_features: 匹配特征列表（默认使用全局 MATCH_FEATURES）

    返回:
      dict: matched_df, balance_df, did_df, psm_plot, did_plot 等
    """
    if match_features is None:
        match_features = MATCH_FEATURES

    print(f"\n{'='*70}")
    print(f"  PSM+DID Pipeline: {label_suffix}")
    print(f"{'='*70}")

    results = {}
    results['label_suffix'] = label_suffix
    results['match_features'] = match_features

    # ---- Step 1: 拆分处理组/对照组 ----
    print(f"\n--- Step 2: PSM Matching [{label_suffix}] ---")
    treat = df[df[TREATMENT_COL] == 1].copy().reset_index(drop=True)
    control = df[df[TREATMENT_COL] == 0].copy().reset_index(drop=True)
    orig_n_treat = len(treat)
    orig_n_ctrl = len(control)
    print(f"  Treated: {orig_n_treat:,} | Control: {orig_n_ctrl:,}")

    # 对照组降采样（大样本时加速匹配）
    if len(control) > MAX_CTRL_SAMPLE:
        control = control.sample(n=MAX_CTRL_SAMPLE, random_state=SEED)
        print(f"  Control downsampled to: {MAX_CTRL_SAMPLE:,} (seed={SEED})")

    combined = pd.concat([treat, control], ignore_index=True)

    # ---- Step 2: 特征标准化 + 倾向得分 ----
    feature_data = combined[match_features].copy().astype(float)
    feature_data = safe_fillna(feature_data, match_features)[match_features]

    scaler = StandardScaler()
    X = scaler.fit_transform(feature_data)
    X = np.nan_to_num(X, nan=0.0, posinf=0.0, neginf=0.0)
    y = combined[TREATMENT_COL].values.astype(int)

    ps_model = LogisticRegression(random_state=SEED, max_iter=1000)
    ps_model.fit(X, y)
    combined['propensity_score'] = ps_model.predict_proba(X)[:, 1]

    treat_df = combined[combined[TREATMENT_COL] == 1].copy()
    control_df = combined[combined[TREATMENT_COL] == 0].copy()

    # KDTree 1:1 最近邻匹配
    tree = KDTree(control_df['propensity_score'].values.reshape(-1, 1))
    dists, indices = tree.query(treat_df['propensity_score'].values.reshape(-1, 1), k=1)
    valid_mask = dists.flatten() <= CALIPER
    matched_treat = treat_df[valid_mask].copy()
    matched_ctrl = control_df.iloc[indices[valid_mask].flatten()].copy()
    matched_df = pd.concat([matched_treat, matched_ctrl], ignore_index=True)

    match_rate = len(matched_treat) / orig_n_treat * 100 if orig_n_treat > 0 else 0
    print(f"  Matched: {len(matched_treat):,}/{orig_n_treat:,} ({match_rate:.1f}%)")

    # ---- Step 3: SMD 平衡性检验 ----
    print(f"\n--- Step 3: Balance Check (SMD) [{label_suffix}] ---")
    smd_records = []
    for feat in match_features:
        sb = calc_smd(df, feat, TREATMENT_COL)
        sa = calc_smd(matched_df, feat, TREATMENT_COL)
        smd_records.append({'feature': feat, 'smd_before': round(sb, 4), 'smd_after': round(sa, 4)})
    balance_df = pd.DataFrame(smd_records)
    n_pass = (balance_df['smd_after'] < 0.1).sum()
    mx_smd = balance_df['smd_after'].max()
    print(f"  Passed: {n_pass}/{len(match_features)} | Max |SMD|: {mx_smd:.4f}")

    results['matched_df'] = matched_df
    results['n_matched_treat'] = len(matched_treat)
    results['n_matched_ctrl'] = len(matched_ctrl)
    results['orig_n_treat'] = orig_n_treat
    results['orig_n_ctrl'] = min(orig_n_ctrl, MAX_CTRL_SAMPLE)
    results['balance_df'] = balance_df
    results['smd_pass_rate'] = f"{n_pass}/{len(match_features)}"
    results['max_smd'] = mx_smd

    # ---- Step 4: DID 分析 ----
    print(f"\n--- Step 4: DID Estimation [{label_suffix}] ---")

    did_ready = matched_df.copy()
    # NaN 兜底：after 缺失时用 before 值填充（保守假设：无变化）
    for after_col, before_col in OUTCOME_MAPPING.items():
        mask_nan = did_ready[after_col].isna()
        did_ready.loc[mask_nan, after_col] = did_ready.loc[mask_nan, before_col]

    treat_did = did_ready[did_ready[TREATMENT_COL] == 1]
    control_did = did_ready[did_ready[TREATMENT_COL] == 0]

    did_records = []
    for after_col, before_col in OUTCOME_MAPPING.items():
        # 提取四组数据
        tv = treat_did[after_col].astype(float).values
        cv = control_did[after_col].astype(float).values
        tb = treat_did[before_col].astype(float).values
        cb = control_did[before_col].astype(float).values

        # 清理
        tv, cv = tv[np.isfinite(tv)], cv[np.isfinite(cv)]
        tb, cb = tb[np.isfinite(tb)], cb[np.isfinite(cb)]

        ta, ca = tv.mean(), cv.mean()
        tb_m, cb_m = tb.mean(), cb.mean()
        did_effect = (ta - tb_m) - (ca - cb_m)
        lift_pct = (did_effect / tb_m * 100) if abs(tb_m) > 1e-10 else 0.0

        # 标准差 + CV
        ta_std, ca_std = tv.std(), cv.std()
        cv_t = (ta_std / ta * 100) if abs(ta) > 1e-10 else float('inf')
        cv_c = (ca_std / ca * 100) if abs(ca) > 1e-10 else float('inf')

        # t 检验
        if len(tv) >= 2 and len(cv) >= 2:
            _, p_val = ttest_ind(tv, cv)
            if np.isnan(p_val) or np.isinf(p_val): p_val = 1.0
        else:
            p_val = 1.0

        sig_text, sig_mk = sig_mark(p_val, did_effect)
        p_display = f'{p_val:.2e}'

        # 中位数DID + M-W U
        med_ta, med_ca = np.median(tv), np.median(cv)
        med_tb, med_cb = np.median(tb), np.median(cb)
        med_did = (med_ta - med_tb) - (med_ca - med_cb)
        med_lift = (med_did / med_tb * 100) if abs(med_tb) > 1e-10 else 0.0

        try:
            _, med_p = mannwhitneyu(tv, cv, alternative='two-sided')
            if np.isnan(med_p) or np.isinf(med_p): med_p = 1.0
        except Exception:
            med_p = 1.0

        med_sig_text, med_sig_mk = sig_mark(med_p, med_did)

        label, unit = OUTCOME_LABELS.get(after_col, (after_col, ''))

        did_records.append({
            'outcome': after_col, 'label': label, 'unit': unit,
            'treat_before': round(tb_m, 2), 'treat_after': round(ta, 2),
            'ctrl_before': round(cb_m, 2), 'ctrl_after': round(ca, 2),
            'did_effect': round(did_effect, 2), 'lift_pct': f"{lift_pct:+.1f}%",
            'p_value_raw': p_val, 'p_value_display': p_display,
            'significant': p_val < ALPHA_STANDARD,
            'sig_mark': sig_mk, 'sig_text': sig_text,
            'treat_before_std': round(tb.std(), 2), 'treat_after_std': round(ta_std, 2),
            'ctrl_before_std': round(cb.std(), 2), 'ctrl_after_std': round(ca_std, 2),
            'med_treat_before': round(med_tb, 2), 'med_treat_after': round(med_ta, 2),
            'med_ctrl_before': round(med_cb, 2), 'med_ctrl_after': round(med_ca, 2),
            'med_did_effect': round(med_did, 2), 'med_lift_pct': f"{med_lift:+.1f}%",
            'med_p_value': med_p, 'med_p_display': f'{med_p:.2e}',
            'med_significant': med_p < ALPHA_STANDARD,
            'med_sig_mark': med_sig_mk, 'med_sig_text': med_sig_text,
        })

    # ---- LTV 补充分析 (pay_rate + ARPPU) ----
    # 详细逻辑见 references/ltv-methodology.md
    ltv_results = _run_ltv_supplement(treat_did, control_did, did_records, label_suffix)

    results['did_df'] = pd.DataFrame(did_records)

    # ---- 生成图表（PS分布图、Love Plot、DID柱状图）----
    ts = datetime.now().strftime('%Y%m%d_%H%M%S')
    sfx = label_suffix.replace(' ', '_') if label_suffix else 'full'

    ps_path = os.path.join(OUT_DIR, f'ps_distribution_{sfx}_{ts}.png')
    love_path = os.path.join(OUT_DIR, f'love_plot_{sfx}_{ts}.png')
    did_path = os.path.join(OUT_DIR, f'did_bars_{sfx}_{ts}.png')

    plot_ps_distribution(matched_df, TREATMENT_COL,
                         title_suffix=label_suffix, save_path=ps_path)
    plot_love(balance_df,
              title_suffix=label_suffix, save_path=love_path)
    plot_did_bars(results['did_df'],
                  title_suffix=label_suffix, save_path=did_path)

    results['psm_plot'] = ps_path
    results['love_plot'] = love_path
    results['did_plot'] = did_path

    return results


def _run_ltv_supplement(treat_did, control_did, did_records, label_suffix):
    """
    LTV 补充分析。

    当原始消费金额 CV 过高（>500%）导致 DID 不显著时，
    自动拆解为 pay_rate（广度）和 ARPPU（深度）两个指标。

    为什么需要这一步：
    原始 consume_amount 的 CV 通常 >1000%，t 检验基本无效。
    pay_rate 作为二分类变量（0/1）CV≈0%，是最可靠的 LTV 信号。
    ARPPU 排除零值后 CV 中等（50-200%），但仍需警惕稀释效应。

    完整方法论：references/ltv-methodology.md
    """
    pay_col = LTV_AMOUNT_COL
    pay_before = LTV_AMOUNT_BEFORE

    # -- pay_rate --
    tr_pay = (treat_did[pay_col] > 0).mean() * 100
    ct_pay = (control_did[pay_col] > 0).mean() * 100
    tr_pay_bf = (treat_did[pay_before] > 0).mean() * 100
    ct_pay_bf = (control_did[pay_before] > 0).mean() * 100
    pay_did = (tr_pay - tr_pay_bf) - (ct_pay - ct_pay_bf)
    pay_lift = (pay_did / tr_pay_bf * 100) if abs(tr_pay_bf) > 1e-10 else 0.0

    tv_pay = (treat_did[pay_col] > 0).astype(float).values
    cv_pay = (control_did[pay_col] > 0).astype(float).values
    tv_pay, cv_pay = tv_pay[np.isfinite(tv_pay)], cv_pay[np.isfinite(cv_pay)]
    _, pay_p = ttest_ind(tv_pay, cv_pay) if len(tv_pay)>=2 and len(cv_pay)>=2 else (0, 1.0)
    if np.isnan(pay_p) or np.isinf(pay_p): pay_p = 1.0
    pay_stxt, pay_smk = sig_mark(pay_p, pay_did)

    # -- ARPPU --
    tpa = treat_did[treat_did[pay_col] > 0][pay_col].astype(float)
    cpa = control_did[control_did[pay_col] > 0][pay_col].astype(float)
    tpb = treat_did[treat_did[pay_before] > 0][pay_before].astype(float)
    cpb = control_did[control_did[pay_before] > 0][pay_before].astype(float)

    arppu_did = (tpa.mean() - tpb.mean()) - (cpa.mean() - cpb.mean())
    arppu_lift = (arppu_did / tpb.mean() * 100) if abs(tpb.mean()) > 1e-10 else 0.0

    tpa_v, cpa_v = tpa.values[np.isfinite(tpa.values)], cpa.values[np.isfinite(cpa.values)]
    _, arppu_p = ttest_ind(tpa_v, cpa_v) if len(tpa_v)>=2 and len(cpa_v)>=2 else (0, 1.0)
    if np.isnan(arppu_p) or np.isinf(arppu_p): arppu_p = 1.0
    arppu_stxt, arppu_smk = sig_mark(arppu_p, arppu_did)

    # 中位数ARPPU
    med_arppu_did = (tpa.median() - tpb.median()) - (cpa.median() - cpb.median())
    try:
        _, med_arppu_p = mannwhitneyu(tpa_v, cpa_v, alternative='two-sided')
        if np.isnan(med_arppu_p) or np.isinf(med_arppu_p): med_arppu_p = 1.0
    except: med_arppu_p = 1.0
    med_arppu_stxt, _ = sig_mark(med_arppu_p, med_arppu_did)

    # 稀释效应诊断
    n_treat_paid = len(tpa)
    n_ctrl_paid = len(cpa)
    dilution_ratio = n_treat_paid / max(n_ctrl_paid, 1)
    arppu_conflict = ((arppu_did > 0) != (med_arppu_did > 0)) and (arppu_p < ALPHA_STANDARD or med_arppu_p < ALPHA_STANDARD)

    # 追加到 did_records
    did_records.extend([
        {
            'outcome': 'ltv_pay_rate', 'label': '付费转化率', 'unit': '%',
            'treat_before': round(tr_pay_bf, 4), 'treat_after': round(tr_pay, 4),
            'ctrl_before': round(ct_pay_bf, 4), 'ctrl_after': round(ct_pay, 4),
            'did_effect': round(pay_did, 4), 'lift_pct': f"{pay_lift:+.2f}%",
            'p_value_raw': pay_p, 'p_value_display': f'{pay_p:.2e}',
            'significant': pay_p < ALPHA_STANDARD,
            'sig_mark': pay_smk, 'sig_text': pay_stxt,
            'treat_before_std': 0, 'treat_after_std': 0,
            'ctrl_before_std': 0, 'ctrl_after_std': 0,
            'med_treat_before': 0, 'med_treat_after': 0,
            'med_ctrl_before': 0, 'med_ctrl_after': 0,
            'med_did_effect': 0, 'med_lift_pct': '0%',
            'med_p_value': 1.0, 'med_p_display': '1.0',
            'med_significant': False, 'med_sig_mark': '', 'med_sig_text': '—',
        },
        {
            'outcome': 'ltv_arppu', 'label': 'ARPPU', 'unit': '元',
            'treat_before': round(tpb.mean(), 2), 'treat_after': round(tpa.mean(), 2),
            'ctrl_before': round(cpb.mean(), 2), 'ctrl_after': round(cpa.mean(), 2),
            'did_effect': round(arppu_did, 2), 'lift_pct': f"{arppu_lift:+.2f}%",
            'p_value_raw': arppu_p, 'p_value_display': f'{arppu_p:.2e}',
            'significant': arppu_p < ALPHA_STANDARD,
            'sig_mark': arppu_smk, 'sig_text': arppu_stxt,
            'treat_before_std': round(tpb.std(), 2), 'treat_after_std': round(tpa.std(), 2),
            'ctrl_before_std': round(cpb.std(), 2), 'ctrl_after_std': round(cpa.std(), 2),
            'med_treat_before': round(tpb.median(), 2), 'med_treat_after': round(tpa.median(), 2),
            'med_ctrl_before': round(cpb.median(), 2), 'med_ctrl_after': round(cpa.median(), 2),
            'med_did_effect': round(med_arppu_did, 2), 'med_lift_pct': f"{med_arppu_did/tpb.median()*100:+.2f}%" if abs(tpb.median())>1e-10 else '0%',
            'med_p_value': med_arppu_p, 'med_p_display': f'{med_arppu_p:.2e}',
            'med_significant': med_arppu_p < ALPHA_STANDARD,
            'med_sig_mark': '', 'med_sig_text': med_arppu_stxt,
        },
    ])

    return {
        'pay_rate': {'did': pay_did, 'p': pay_p, 'sig': pay_stxt},
        'arppu': {'did': arppu_did, 'p': arppu_p, 'sig': arppu_stxt, 'med_did': med_arppu_did, 'med_sig': med_arppu_stxt},
        'dilution_ratio': dilution_ratio, 'conflict': arppu_conflict,
        'n_treat_paid': n_treat_paid, 'n_ctrl_paid': n_ctrl_paid,
    }


# ============================================================
#  主流程
# ============================================================

if __name__ == '__main__':
    print("=" * 70)
    print("  PSM+DID Causal Inference Analysis")
    print(f"  Started: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print("=" * 70)

    # 加载数据
    print(f"\n--- Step 1: Data Loading ---")
    df = pd.read_csv(DATA_CSV)
    print(f"  Loaded: {len(df):,} rows, {len(df.columns)} cols")

    # 清洗所有数值列
    all_num_cols = MATCH_FEATURES + list(OUTCOME_MAPPING.keys())
    df = safe_fillna(df, all_num_cols)

    # ---- 模块A: 全量样本 ----
    full_results = run_psm_pipeline(df, label_suffix='full')

    # ---- 模块B: 子人群（可选） ----
    subgroup_results = None
    if SUBGROUP_CONFIG.get('enabled'):
        filt_col = SUBGROUP_CONFIG['filter_col']
        filt_val = SUBGROUP_CONFIG['filter_value']
        subgroup_df = df[df[filt_col] == filt_val].copy()

        sub_features = [f for f in MATCH_FEATURES
                       if f != SUBGROUP_CONFIG.get('exclude_from_features')]
        subgroup_results = run_psm_pipeline(
            subgroup_df,
            label_suffix=SUBGROUP_CONFIG['label'],
            match_features=sub_features
        )

    # ---- 报告生成 ----
    # Word 报告：调用 docx skill 的生成逻辑
    # Excel 报告：合并单元格、均值+中位数双区、微软雅黑
    # CSV 导出：utf-8-sig 编码、仅展示列

    print(f"\n{'='*70}")
    print(f"  ✅ Analysis Complete: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print(f"{'='*70}")
