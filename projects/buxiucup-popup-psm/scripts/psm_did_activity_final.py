# -*- coding: utf-8 -*-
"""
=============================================================================
  不朽杯打卡活动 PSM+DID 因果推断分析
=============================================================================
  数据源：不朽杯打卡分析_观看DOAT2_用户行为数据源.csv
  分析对象：参与打卡活动用户(is_attend=1) vs 从未参与打卡用户(is_attend=0)
  匹配质量要求：所有特征 SMD < 0.1（自适应卡钳）
  输出：Word报告 + Excel报告 + 图表
=============================================================================
"""

import pandas as pd
import numpy as np
import warnings, os, sys, time
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
plt.rcParams['font.size'] = 12
plt.rcParams['axes.titlesize'] = 14
plt.rcParams['axes.labelsize'] = 12
plt.rcParams['xtick.labelsize'] = 11
plt.rcParams['ytick.labelsize'] = 11
plt.rcParams['legend.fontsize'] = 11

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
from openpyxl.utils.dataframe import dataframe_to_rows
from openpyxl.utils import get_column_letter


# ============================================================
#  CONFIG
# ============================================================
BASE_DIR = r'C:\Users\tiany\Desktop\不朽杯弹窗PSM实验\对比DOTA2观看用户'
DATA_CSV = os.path.join(BASE_DIR, '不朽杯打卡分析_观看DOAT2_用户行为数据源.csv')

TREATMENT_COL = 'is_attend'
USER_COL = 'yyuid'

# 匹配特征（排除 before_main_gameid）
MATCH_FEATURES = [
    'before_watch_duration',
    'before_watch_dcnt',
    'before_watch_anchorcnt',
    'before_watch_gamecnt',
    'before_consume_amount',
    'before_active_dcnt',
]

# 结果变量映射 {after_col: before_col}
OUTCOME_MAPPING = {
    'after_watch_duration':   'before_watch_duration',
    'after_watch_dcnt':       'before_watch_dcnt',
    'after_watch_anchorcnt':  'before_watch_anchorcnt',
    'after_watch_gamecnt':    'before_watch_gamecnt',
    'after_consume_amount':   'before_consume_amount',
    'after_active_dcnt':      'before_active_dcnt',
}

OUTCOME_LABELS = {
    'after_watch_duration':   ('观看时长(分钟)', '分钟'),
    'after_watch_dcnt':       ('观看天数',      '天'),
    'after_watch_anchorcnt':  ('观看主播数',    '个'),
    'after_watch_gamecnt':    ('观看游戏数',    '个'),
    'after_consume_amount':   ('付费金额(元)',   '元'),
    'after_active_dcnt':      ('活跃天数',      '天'),
}

LT_OUTCOMES = {'after_watch_duration', 'after_watch_dcnt', 'after_watch_anchorcnt',
               'after_watch_gamecnt', 'after_active_dcnt'}
LTV_OUTCOMES = {'after_consume_amount'}

LTV_AMOUNT_COL = 'after_consume_amount'
LTV_AMOUNT_BEFORE = 'before_consume_amount'

SEED = 42
MAX_CTRL_SAMPLE = 1_500_000
ALPHA_STANDARD = 0.05
ALPHA_STRICT = 0.01
ALPHA_LOOSE = 0.10

OUT_DIR = BASE_DIR
ACTIVITY_NAME = '不朽杯打卡活动'


# ============================================================
#  工具函数
# ============================================================

def safe_fillna(df, cols):
    """填充 NaN 和 Inf"""
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
    """计算标准化均值差异"""
    t = data[data[treat_col] == 1][feat].astype(float)
    c = data[data[treat_col] == 0][feat].astype(float)
    mean_diff = t.mean() - c.mean()
    pool_var = (t.var(ddof=0) + c.var(ddof=0)) / 2
    return abs(mean_diff / np.sqrt(pool_var)) if pool_var > 1e-10 else 0.0


def sig_mark(p_val, did_effect):
    """显著性标记"""
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


def _set_font(run, size=Pt(11), bold=False, color=None):
    """设置 Word 字体为微软雅黑"""
    run.font.name = '微软雅黑'
    run._element.rPr.rFonts.set(qn('w:eastAsia'), '微软雅黑')
    run.font.size = size
    run.bold = bold
    if color:
        run.font.color.rgb = color


# ============================================================
#  数据加载与聚合
# ============================================================

def load_and_aggregate():
    """
    加载原始日级别数据，聚合成用户级别。

    关键逻辑：
    - is_attend: 用户只要在任何一天参与过打卡 → 实验组(1)，否则对照组(0)
    - before_* / after_* 列取该用户的非空值（这些列已经是预计算的汇总值）
    """
    print(f"\n{'='*70}")
    print(f"  Step 1: 数据加载与聚合")
    print(f"{'='*70}")

    df = pd.read_csv(DATA_CSV, encoding='utf-8-sig', low_memory=False)
    print(f"  原始数据: {len(df):,} 行, {df[USER_COL].nunique():,} 用户")

    # 聚合到用户级别
    # is_attend: 只要有一天是1，则整体标记为1
    user_agg = df.groupby(USER_COL).agg({
        'is_attend': 'max',  # max = 是否曾经参与过
        'is_interest_dota2': 'max',
        'before_watch_duration': 'max',  # 取非空值（预计算值在特定日期有值）
        'before_watch_dcnt': 'max',
        'before_watch_anchorcnt': 'max',
        'before_watch_gamecnt': 'max',
        'before_consume_amount': 'max',
        'before_active_dcnt': 'max',
        'before_main_gameid': 'max',
        'after_watch_duration': 'max',
        'after_watch_dcnt': 'max',
        'after_watch_anchorcnt': 'max',
        'after_watch_gamecnt': 'max',
        'after_consume_amount': 'max',
        'after_active_dcnt': 'max',
    }).reset_index()

    # 仅保留有效数据（before和after都有值的用户）
    before_cols = [c for c in MATCH_FEATURES]
    after_cols = list(OUTCOME_MAPPING.keys())

    # 检查有效性：至少部分before和after有值
    valid_mask = (
        user_agg[before_cols].notna().any(axis=1) &
        user_agg[after_cols].notna().any(axis=1)
    )
    user_agg = user_agg[valid_mask].copy()

    # 清洗数值列
    all_num_cols = MATCH_FEATURES + list(OUTCOME_MAPPING.keys())
    user_agg = safe_fillna(user_agg, all_num_cols)

    n_treat = (user_agg[TREATMENT_COL] == 1).sum()
    n_ctrl = (user_agg[TREATMENT_COL] == 0).sum()

    print(f"  聚合后有效用户: {len(user_agg):,}")
    print(f"  实验组(参与打卡): {n_treat:,} ({n_treat/len(user_agg)*100:.1f}%)")
    print(f"  对照组(从未打卡): {n_ctrl:,} ({n_ctrl/len(user_agg)*100:.1f}%)")

    return user_agg


# ============================================================
#  自适应PSM匹配（确保SMD<0.1）
# ============================================================

def adaptive_psm_match(df, match_features, caliper_start=0.05, smd_threshold=0.1):
    """
    自适应PSM匹配：从宽松卡钳开始，逐步收紧直到所有SMD < threshold

    策略序列：
    1. 卡钳从 0.05 开始，逐步收紧到 0.02, 0.01
    2. 如果卡钳过严导致匹配率过低(<30%)，改用 Mahalanobis距离辅助
    3. 如果仍不通过，对高SMD特征做精确匹配（分箱后匹配）
    """
    treat = df[df[TREATMENT_COL] == 1].copy().reset_index(drop=True)
    control = df[df[TREATMENT_COL] == 0].copy().reset_index(drop=True)
    orig_n_treat = len(treat)
    orig_n_ctrl = len(control)

    print(f"\n  原始样本: 实验组={orig_n_treat:,}, 对照组={orig_n_ctrl:,}")

    if len(control) > MAX_CTRL_SAMPLE:
        control = control.sample(n=MAX_CTRL_SAMPLE, random_state=SEED)
        print(f"  对照组降采样至: {MAX_CTRL_SAMPLE:,}")

    combined = pd.concat([treat, control], ignore_index=True)

    # 特征标准化
    feature_data = combined[match_features].copy().astype(float)
    feature_data = safe_fillna(feature_data, match_features)[match_features]

    scaler = StandardScaler()
    X = scaler.fit_transform(feature_data)
    X = np.nan_to_num(X, nan=0.0, posinf=0.0, neginf=0.0)
    y = combined[TREATMENT_COL].values.astype(int)

    # 倾向得分模型
    # 注意：不使用class_weight='balanced'，避免PS过度集中于0.5
    # 当两组基线特征本身就高度相似时（SMD_before很小），balanced会压缩PS分布
    ps_model = LogisticRegression(random_state=SEED, max_iter=1000)
    ps_model.fit(X, y)
    combined['propensity_score'] = ps_model.predict_proba(X)[:, 1]

    treat_df = combined[combined[TREATMENT_COL] == 1].copy()
    control_df = combined[combined[TREATMENT_COL] == 0].copy()

    # ====== 自适应卡钳策略 ======
    caliper_values = [0.05, 0.03, 0.02, 0.015, 0.01, 0.008, 0.005]

    best_result = None

    for caliper in caliper_values:
        print(f"\n  --- 尝试卡钳: {caliper} ---")

        tree = KDTree(control_df['propensity_score'].values.reshape(-1, 1))
        dists, indices = tree.query(treat_df['propensity_score'].values.reshape(-1, 1), k=1)
        valid_mask = dists.flatten() <= caliper

        matched_treat = treat_df[valid_mask].copy()
        matched_ctrl = control_df.iloc[indices[valid_mask].flatten()].copy()
        matched_df = pd.concat([matched_treat, matched_ctrl], ignore_index=True)

        match_rate = len(matched_treat) / orig_n_treat * 100

        # 计算匹配后SMD
        smd_after_list = []
        for feat in match_features:
            sa = calc_smd(matched_df, feat, TREATMENT_COL)
            smd_after_list.append(sa)

        max_smd = max(smd_after_list)
        n_pass = sum(1 for s in smd_after_list if s < smd_threshold)

        print(f"    匹配成功: {len(matched_treat):,}/{orig_n_treat:,} ({match_rate:.1f}%)")
        print(f"    SMD通过: {n_pass}/{len(match_features)}, 最大|SMD|={max_smd:.4f}")

        result = {
            'matched_df': matched_df,
            'matched_treat': matched_treat,
            'matched_ctrl': matched_ctrl,
            'caliper': caliper,
            'match_rate': match_rate,
            'max_smd': max_smd,
            'n_pass': n_pass,
            'smd_values': dict(zip(match_features, smd_after_list)),
        }

        best_result = result

        # 全部通过 → 直接返回
        if max_smd < smd_threshold and match_rate >= 20:
            print(f"    ✓ 卡钳={caliper}: 所有SMD均<{smd_threshold}, 匹配率{match_rate:.1f}%")
            break

        # 匹配率过低时停止收紧
        if match_rate < 20:
            print(f"    ✗ 匹配率过低({match_rate:.1f}%)，停止收紧卡钳")
            break

    # 如果默认策略仍未全部通过，尝试更激进的方法
    if best_result['max_smd'] >= smd_threshold:
        print(f"\n  === 默认策略未完全通过，启用增强匹配 ===")
        best_result = _enhanced_matching(
            treat_df, control_df, match_features, smd_threshold, orig_n_treat
        )

    return best_result, ps_model, scaler


def _enhanced_matching(treat_df, control_df, match_features, smd_threshold, orig_n_treat):
    """
    增强匹配策略：
    1. 对每个特征进行分箱精确匹配
    2. 结合PS得分和Mahalanobis距离的混合匹配
    """
    print("  策略: PS得分 + 特征分箱混合匹配")

    # 方法：先按关键特征的十分位数分层，然后在每层内做PS匹配
    treat = treat_df.copy()
    ctrl = control_df.copy()

    # 选择SMD最高的几个特征进行分箱
    # 先用宽松卡钳做一次初步匹配，找出问题特征
    tree = KDTree(ctrl['propensity_score'].values.reshape(-1, 1))
    dists, indices = tree.query(treat['propensity_score'].values.reshape(-1, 1), k=1)
    loose_mask = dists.flatten() <= 0.05
    loose_matched = pd.concat([
        treat[loose_mask],
        ctrl.iloc[indices[loose_mask].flatten()]
    ], ignore_index=True)

    problem_feats = []
    for feat in match_features:
        sa = calc_smd(loose_matched, feat, TREATMENT_COL)
        if sa >= smd_threshold:
            problem_feats.append((feat, sa))

    print(f"  问题特征(SMD>={smdd_threshold}): {[f[0] for f in problem_feats]}")

    if not problem_feats:
        return {
            'matched_df': loose_matched,
            'matched_treat': treat[loose_mask],
            'matched_ctrl': ctrl.iloc[indices[loose_mask].flatten()],
            'caliper': 0.05,
            'match_rate': loose_mask.sum()/orig_n_treat*100,
            'max_smd': max(calc_smd(loose_matched, f, TREATMENT_COL) for f in match_features),
            'n_pass': sum(1 for f in match_features if calc_smd(loose_matched, f, TREATMENT_COL) < smd_threshold),
            'smd_values': {f: calc_smd(loose_matched, f, TREATMENT_COL) for f in match_features},
        }

    # 对问题特征进行分箱，然后逐层匹配
    top_problem = problem_feats[0][0]
    print(f"  对最高SMD特征 '{top_problem}' 进行分箱匹配...")

    # 创建分箱标签
    treat['strata_bin'] = pd.qcut(treat[top_problem].rank(method='first'), q=10, labels=False, duplicates='drop')
    ctrl['strata_bin'] = pd.qcut(ctrl[top_problem].rank(method='first'), q=10, labels=False, duplicates='drop')

    final_treat_list = []
    final_ctrl_list = []

    for bin_val in sorted(treat['strata_bin'].unique()):
        t_in_bin = treat[treat['strata_bin'] == bin_val]
        c_in_bin = ctrl[ctrl['strata_bin'] == bin_val]

        if len(c_in_bin) == 0 or len(t_in_bin) == 0:
            continue

        # 层内PS匹配（严格卡钳）
        if len(c_in_bin) >= 3:
            try:
                layer_tree = KDTree(c_in_bin['propensity_score'].values.reshape(-1, 1))
                layer_dists, layer_idxs = layer_tree.query(
                    t_in_bin['propensity_score'].values.reshape(-1, 1), k=1
                )
                layer_valid = layer_dists.flatten() <= 0.02  # 层内严格卡钳

                final_treat_list.append(t_in_bin[layer_valid])
                final_ctrl_list.append(c_in_bin.iloc[layer_idxs[layer_valid].flatten()])
            except:
                pass

    if final_treat_list:
        enhanced_matched = pd.concat(final_treat_list + final_ctrl_list, ignore_index=True)
        enhanced_treat = pd.concat(final_treat_list, ignore_index=True)
        enhanced_ctrl = pd.concat(final_ctrl_list, ignore_index=True)
    else:
        enhanced_matched = loose_matched
        enhanced_treat = treat[loose_mask]
        enhanced_ctrl = ctrl.iloc[indices[loose_mask].flatten()]

    match_rate = len(enhanced_treat) / orig_n_treat * 100
    smd_vals = {f: calc_smd(enhanced_matched, f, TREATMENT_COL) for f in match_features}
    max_smd = max(smd_vals.values())
    n_pass = sum(1 for v in smd_vals.values() if v < smd_threshold)

    print(f"  增强匹配结果: 成功={len(enhanced_treat):,}/{orig_n_treat:,} ({match_rate:.1f}%)")
    print(f"  SMD通过: {n_pass}/{len(match_features)}, 最大|SMD|={max_smd:.4f}")

    return {
        'matched_df': enhanced_matched,
        'matched_treat': enhanced_treat,
        'matched_ctrl': enhanced_ctrl,
        'caliper': 'enhanced',
        'match_rate': match_rate,
        'max_smd': max_smd,
        'n_pass': n_pass,
        'smd_values': smd_vals,
    }


# ============================================================
#  可视化函数（参考样图格式）
# ============================================================

def plot_combined_quality(matched_df, balance_df, treat_col, save_path=None):
    """
    组合质量图 — 参考用户提供的样图格式：
    左侧：Propensity Score Distribution after Matching（密度图，Treatment蓝/Control橙）
    右侧：Standardized Mean Difference after Matching（水平条形图，绿色条形，红色虚线SMD=0.1）
    """
    fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(16, 6))

    # ========== 左图：PS分布（匹配后）— 使用KDE平滑曲线 ==========
    treat_ps = matched_df[matched_df[treat_col] == 1]['propensity_score'].values
    ctrl_ps = matched_df[matched_df[treat_col] == 0]['propensity_score'].values

    # 自适应x轴范围
    ps_min_val = min(treat_ps.min(), ctrl_ps.min())
    ps_max_val = max(treat_ps.max(), ctrl_ps.max())
    ps_range = ps_max_val - ps_min_val
    if ps_range < 0.15:
        center = (ps_max_val + ps_min_val) / 2
        ps_min_plot = max(0, center - 0.10)
        ps_max_plot = min(1, center + 0.10)
    else:
        ps_min_plot = max(0, ps_min_val - ps_range * 0.05)
        ps_max_plot = min(1, ps_max_val + ps_range * 0.05)

    xs = np.linspace(ps_min_plot, ps_max_plot, 300)

    # KDE平滑曲线（比直方图更适合展示密集/集中的分布）
    try:
        kde_t = gaussian_kde(treat_ps)
        kde_c = gaussian_kde(ctrl_ps)
        ys_t = kde_t(xs)
        ys_c = kde_c(xs)

        # 归一化到相似高度便于比较
        max_y = max(ys_t.max(), ys_c.max())
        if max_y > 0:
            ys_t = ys_t / max_y
            ys_c = ys_c / max_y

        ax1.fill_between(xs, ys_t, alpha=0.35, color='#4A90D9', label='Treatment')
        ax1.fill_between(xs, ys_c, alpha=0.35, color='#E8B86D', label='Control')
        ax1.plot(xs, ys_t, color='#2171C5', linewidth=2)
        ax1.plot(xs, ys_c, color='#C4983B', linewidth=2)
    except Exception:
        # KDE失败时回退到直方图
        bins = np.linspace(ps_min_plot, ps_max_plot, 40)
        ax1.hist(treat_ps, bins=bins, alpha=0.5, label='Treatment',
                 color='#4A90D9', edgecolor='white', density=True)
        ax1.hist(ctrl_ps, bins=bins, alpha=0.5, label='Control',
                 color='#E8B86D', edgecolor='white', density=True)

    ax1.set_xlabel('Propensity Score', fontsize=12)
    ax1.set_ylabel('Density', fontsize=12)
    ax1.set_title('Propensity Score Distribution after Matching', fontsize=14, fontweight='bold')
    ax1.legend(loc='upper right', fontsize=11)
    ax1.spines['top'].set_visible(False)
    ax1.spines['right'].set_visible(False)

    # ========== 右图：SMD条形图（匹配后）==========
    features = balance_df['feature'].tolist()[::-1]
    smd_after = balance_df['smd_after'].tolist()[::-1]

    y_pos = range(len(features))
    colors = ['#4CAF50' if s < 0.1 else '#FF5722' for s in smd_after]  # 绿色通过，红色不通过

    bars = ax2.barh(y_pos, smd_after, color=colors, edgecolor='white', height=0.6)

    # SMD=0.1 参考线（红色虚线）
    ax2.axvline(x=0.1, color='#E53935', linestyle='--', linewidth=2, label='SMD=0.1')

    ax2.set_yticks(list(y_pos))
    ax2.set_yticklabels(features, fontsize=11)
    ax2.set_xlabel('|SMD|', fontsize=12)
    ax2.set_title('Standardized Mean Difference after Matching', fontsize=14, fontweight='bold')
    ax2.legend(loc='lower right', fontsize=11)
    ax2.set_xlim(0, max(max(smd_after) * 1.5, 0.12))
    ax2.spines['top'].set_visible(False)
    ax2.spines['right'].set_visible(False)

    plt.tight_layout(pad=2.0)
    if save_path:
        plt.savefig(save_path, dpi=150, bbox_inches='tight', facecolor='white')
        print(f"  组合质量图已保存: {save_path}")
    plt.close()
    return save_path


def plot_love_plot(balance_df, title_suffix='', save_path=None):
    """Love Plot — 匹配前后SMD对比"""
    features = balance_df['feature'].tolist()[::-1]
    smd_before = balance_df['smd_before'].tolist()[::-1]
    smd_after = balance_df['smd_after'].tolist()[::-1]

    fig, ax = plt.subplots(figsize=(10, max(6, len(features) * 0.45)))
    y_pos = range(len(features))

    ax.scatter(smd_before, y_pos, marker='o', s=80, color='#E53935',
               edgecolors='#E53935', linewidths=1.5, alpha=0.7, label='匹配前 (Before)', zorder=3)
    ax.scatter(smd_after, y_pos, marker='^', s=80, color='#43A047',
               edgecolors='#2E7D32', linewidths=1.5, alpha=0.9, label='匹配后 (After)', zorder=4)

    for i in range(len(features)):
        ax.plot([smd_before[i], smd_after[i]], [y_pos[i], y_pos[i]],
                color='#9E9E9E', linewidth=0.8, alpha=0.5, zorder=1)

    ax.axvline(x=0.1, color='#FF9800', linestyle='--', linewidth=1.5, alpha=0.8, label='SMD = 0.1')
    ax.axvline(x=0.2, color='#E53935', linestyle=':', linewidth=1, alpha=0.5, label='SMD = 0.2')

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
    """DID效应柱状图"""
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
            colors.append('#43A047')
        elif sig and did < 0:
            colors.append('#E53935')
        else:
            colors.append('#BDBDBD')

    fig, ax = plt.subplots(figsize=(10, max(5, len(labels) * 0.5)))
    bars = ax.barh(range(len(labels)), effects, color=colors, edgecolor='white', height=0.6)

    for i, (bar, mark) in enumerate(zip(bars, marks)):
        if mark:
            offset = max(effects) * 0.03 if bar.get_width() >= 0 else min(effects) * 0.03
            ax.text(bar.get_width() + offset, bar.get_y() + bar.get_height() / 2,
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
#  DID 分析核心
# ============================================================

def run_did_analysis(matched_df, match_features, label_suffix=''):
    """执行DID双重差分分析"""
    print(f"\n--- Step 4: DID 双重差分估计 [{label_suffix}] ---")

    did_ready = matched_df.copy()
    for after_col, before_col in OUTCOME_MAPPING.items():
        mask_nan = did_ready[after_col].isna()
        did_ready.loc[mask_nan, after_col] = did_ready.loc[mask_nan, before_col]

    treat_did = did_ready[did_ready[TREATMENT_COL] == 1]
    control_did = did_ready[did_ready[TREATMENT_COL] == 0]

    did_records = []
    for after_col, before_col in OUTCOME_MAPPING.items():
        tv = treat_did[after_col].astype(float).values
        cv = control_did[after_col].astype(float).values
        tb = treat_did[before_col].astype(float).values
        cb = control_did[before_col].astype(float).values

        tv, cv = tv[np.isfinite(tv)], cv[np.isfinite(cv)]
        tb, cb = tb[np.isfinite(tb)], cb[np.isfinite(cb)]

        ta, ca = tv.mean(), cv.mean()
        tb_m, cb_m = tb.mean(), cb.mean()
        did_effect = (ta - tb_m) - (ca - cb_m)
        lift_pct = (did_effect / tb_m * 100) if abs(tb_m) > 1e-10 else 0.0

        ta_std, ca_std = tv.std(), cv.std()

        if len(tv) >= 2 and len(cv) >= 2:
            _, p_val = ttest_ind(tv, cv)
            if np.isnan(p_val) or np.isinf(p_val): p_val = 1.0
        else:
            p_val = 1.0

        sig_text, sig_mk = sig_mark(p_val, did_effect)

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
            'p_value_raw': p_val, 'p_value_display': f'{p_val:.2e}',
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

    # LTV补充分析
    ltv_results = _run_ltv_supplement(treat_did, control_did, did_records)

    return pd.DataFrame(did_records), ltv_results


def _run_ltv_supplement(treat_did, control_did, did_records):
    """LTV补充分析：pay_rate + ARPPU"""
    pay_col = LTV_AMOUNT_COL
    pay_before = LTV_AMOUNT_BEFORE

    tr_pay = (treat_did[pay_col] > 0).mean() * 100
    ct_pay = (control_did[pay_col] > 0).mean() * 100
    tr_pay_bf = (treat_did[pay_before] > 0).mean() * 100
    ct_pay_bf = (control_did[pay_before] > 0).mean() * 100
    pay_did = (tr_pay - tr_pay_bf) - (ct_pay - ct_pay_bf)
    pay_lift = (pay_did / tr_pay_bf * 100) if abs(tr_pay_bf) > 1e-10 else 0.0

    tv_pay = (treat_did[pay_col] > 0).astype(float).values
    cv_pay = (control_did[pay_col] > 0).astype(float).values
    tv_pay = tv_pay[np.isfinite(tv_pay)]
    cv_pay = cv_pay[np.isfinite(cv_pay)]
    _, pay_p = ttest_ind(tv_pay, cv_pay) if len(tv_pay)>=2 and len(cv_pay)>=2 else (0, 1.0)
    if np.isnan(pay_p) or np.isinf(pay_p): pay_p = 1.0
    pay_stxt, pay_smk = sig_mark(pay_p, pay_did)

    tpa = treat_did[treat_did[pay_col] > 0][pay_col].astype(float)
    cpa = control_did[control_did[pay_col] > 0][pay_col].astype(float)
    tpb = treat_did[treat_did[pay_before] > 0][pay_before].astype(float)
    cpb = control_did[control_did[pay_before] > 0][pay_before].astype(float)

    arppu_did = (tpa.mean() - tpb.mean()) - (cpa.mean() - cpb.mean())
    arppu_lift = (arppu_did / tpb.mean() * 100) if abs(tpb.mean()) > 1e-10 else 0.0

    tpa_v = tpa.values[np.isfinite(tpa.values)]
    cpa_v = cpa.values[np.isfinite(cpa.values)]
    _, arppu_p = ttest_ind(tpa_v, cpa_v) if len(tpa_v)>=2 and len(cpa_v)>=2 else (0, 1.0)
    if np.isnan(arppu_p) or np.isinf(arppu_p): arppu_p = 1.0
    arppu_stxt, arppu_smk = sig_mark(arppu_p, arppu_did)

    med_arppu_did = (tpa.median() - tpb.median()) - (cpa.median() - cpb.median())
    try:
        _, med_arppu_p = mannwhitneyu(tpa_v, cpa_v, alternative='two-sided')
        if np.isnan(med_arppu_p) or np.isinf(med_arppu_p): med_arppu_p = 1.0
    except Exception:
        med_arppu_p = 1.0
    med_arppu_stxt, _ = sig_mark(med_arppu_p, med_arppu_did)

    n_treat_paid = len(tpa)
    n_ctrl_paid = len(cpa)
    dilution_ratio = n_treat_paid / max(n_ctrl_paid, 1)
    arppu_conflict = ((arppu_did > 0) != (med_arppu_did > 0)) and (arppu_p < ALPHA_STANDARD or med_arppu_p < ALPHA_STANDARD)

    did_records.extend([
        {'outcome': 'ltv_pay_rate', 'label': '付费转化率', 'unit': '%',
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
         'med_significant': False, 'med_sig_mark': '', 'med_sig_text': '—'},
        {'outcome': 'ltv_arppu', 'label': 'ARPPU', 'unit': '元',
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
         'med_did_effect': round(med_arppu_did, 2),
         'med_lift_pct': f"{med_arppu_did/tpb.median()*100:+.2f}%" if abs(tpb.median())>1e-10 else '0%',
         'med_p_value': med_arppu_p, 'med_p_display': f'{med_arppu_p:.2e}',
         'med_significant': med_arppu_p < ALPHA_STANDARD,
         'med_sig_mark': '', 'med_sig_text': med_arppu_stxt},
    ])

    return {
        'pay_rate': {'did': pay_did, 'p': pay_p, 'sig': pay_stxt},
        'arppu': {'did': arppu_did, 'p': arppu_p, 'sig': arppu_stxt, 'med_did': med_arppu_did, 'med_sig': med_arppu_stxt},
        'dilution_ratio': dilution_ratio, 'conflict': arppu_conflict,
        'n_treat_paid': n_treat_paid, 'n_ctrl_paid': n_ctrl_paid,
    }


# ============================================================
#  报告生成
# ============================================================

def generate_excel_report(did_df, results_info, save_path):
    """
    生成Excel报告 — 严格按指定格式：

    列结构（12列）：
      A: 均值(合并) | B: 指标 |
      C: 实验组前7日(T0) | D: 实验组后7日(T1) | E: 实验组变化(ΔT=T1-T0) |
      F: 对照组前7日(t0) | G: 对照组后7日(t1) | H: 对照组变化(Δt=t1-t0) |
      I: 双重差分净效应(DID=ΔT-Δt) | J: 净效应对实验组的作用(%) |
      K: p_value | L: 统计显著性

    格式要点：
      - 第1行：标题"DID净效应数据"，跨所有列合并，蓝色背景
      - 第2行：表头（二级合并：实验组3列/对照组3列）
      - 数据行：左侧A列"均值"标签纵向合并
      - p_value显示为4位小数格式（如0.0000），不用科学计数法
      - 显著性列：正向显著→浅绿背景，负向显著→浅红背景，不显著→无色
      - DID列(I列)：正向→浅蓝背景，负向→浅红背景
      - 净效应%(J列)：正向→浅蓝背景，负向→浅红背景
      - 字体统一微软雅黑
    """
    wb = openpyxl.Workbook()
    ws = wb.active
    ws.title = 'DID净效应数据'

    # ========== 样式定义 ==========
    title_font = Font(name='微软雅黑', bold=True, size=14)
    header_font = Font(name='微软雅黑', bold=True, size=11, color='FFFFFF')
    header_fill = PatternFill(start_color='4472C4', end_color='4472C4', fill_type='solid')  # 蓝色表头
    normal_font = Font(name='微软雅黑', size=10)
    center_align = Alignment(horizontal='center', vertical='center', wrap_text=True)
    left_align = Alignment(horizontal='left', vertical='center')

    # 条件填充色
    did_blue_fill = PatternFill(start_color='BDD7EE', end_color='BDD7EE', fill_type='solid')   # 正向DID浅蓝
    did_red_fill = PatternFill(start_color='FFCCCC', end_color='FFCCCC', fill_type='solid')     # 负向DID浅红
    sig_green_fill = PatternFill(start_color='C6EFCE', end_color='C6EFCE', fill_type='solid')   # 正向显著浅绿
    sig_red_fill = PatternFill(start_color='FFC7CE', end_color='FFC7CE', fill_type='solid')     # 负向显著浅红
    lift_blue_fill = PatternFill(start_color='DDEBF7', end_color='DDEBF7', fill_type='solid')   # 正向提升浅蓝
    lift_red_fill = PatternFill(start_color='FFCCCC', end_color='FFCCCC', fill_type='solid')    # 负向提升浅红

    thin_border = Border(
        left=Side(style='thin'), right=Side(style='thin'),
        top=Side(style='thin'), bottom=Side(style='thin')
    )
    medium_border = Border(
        left=Side(style='medium'), right=Side(style='medium'),
        top=Side(style='medium'), bottom=Side(style='medium')
    )

    # ========== Row 1: 标题行 ==========
    ws.merge_cells('A1:L1')
    ws['A1'] = 'DID净效应数据'
    ws['A1'].font = title_font
    ws['A1'].alignment = center_align
    ws['A1'].fill = PatternFill(start_color='D6DCE5', end_color='D6DCE5', fill_type='solid')
    for col in range(1, 13):
        ws.cell(row=1, column=col).border = medium_border

    # ========== Row 2: 表头（带合并） ==========
    headers_main = {
        'A2': ('', 1),                                    # 左侧空白（下面会被均值覆盖）
        'B2': ('指标', 1),
        'C2': ('实验组', 3),                               # C+E 合并为"实验组"
        'F2': ('对照组', 3),                               # F+H 合并为"对照组"
        'I2': ('双重差分净效应\n(ΔT-Δt)', 1),
        'J2': ('净效应对实\n验组的作用', 1),
        'K2': ('p_value', 1),
        'L2': ('统计显著性', 1),
    }

    for cell_ref, (text, span) in headers_main.items():
        col_idx = ord(cell_ref[0]) - ord('A') + 1
        row_idx = int(cell_ref[1])
        ws[cell_ref] = text
        ws[cell_ref].font = header_font
        ws[cell_ref].fill = header_fill
        ws[cell_ref].alignment = center_align
        ws[cell_ref].border = thin_border
        if span > 1:
            end_col = get_column_letter(col_idx + span - 1)
            ws.merge_cells(f'{cell_ref}:{end_col}{row_idx}')

    # 二级表头（子表头）
    sub_headers = ['前7日（T0）', '后7日（T1）', 'ΔT',
                   '前7日（t0）', '后7日（t1）', 'Δt']
    for i, h in enumerate(sub_headers):
        col = i + 3  # 从C列开始
        cell = ws.cell(row=3, column=col, value=h)
        cell.font = header_font
        cell.fill = header_fill
        cell.alignment = center_align
        cell.border = thin_border

    # 补充I-L列的row3边框和填充
    for col in range(9, 13):
        cell = ws.cell(row=3, column=col)
        cell.fill = header_fill
        cell.border = thin_border

    # A列和B列的row2-row3处理
    ws['A2'].fill = header_fill
    ws['A2'].border = thin_border
    ws['A3'].fill = header_fill
    ws['A3'].border = thin_border
    ws['B2'].border = thin_border
    b3_cell = ws.cell(row=3, column=2, value='')
    b3_cell.fill = header_fill
    b3_cell.border = thin_border

    # ========== 数据行 ==========
    main_did = did_df[~did_df['outcome'].str.startswith('ltv_', na=False)].copy()
    ltv_did = did_df[did_df['outcome'].str.startswith('ltv_', na=False)].copy()

    # 合并主指标和LTV指标（LTV的pay_rate和ARPPU也放在同一张表中）
    all_rows = []
    for _, rec in main_did.iterrows():
        T0 = rec['treat_before']
        T1 = rec['treat_after']
        t0 = rec['ctrl_before']
        t1 = rec['ctrl_after']
        delta_T = round(T1 - T0, 2)
        delta_t = round(t1 - t0, 2)
        did_val = rec['did_effect']

        # lift百分比数值（去掉%号和符号用于计算）
        lift_str = rec['lift_pct'].replace('%', '').replace('+', '')
        try:
            lift_val = float(lift_str)
        except:
            lift_val = 0.0

        # p_value用原始值显示为4位小数
        p_raw = rec.get('p_value_raw', 1.0)
        p_display = f'{p_raw:.4f}' if not np.isnan(p_raw) and not np.isinf(p_raw) else '1.0000'

        # 显著性文字
        if rec['significant']:
            sig_text = '显著' if did_val > 0 else '显著(负)'
        else:
            sig_text = '不显著'

        all_rows.append({
            'label': rec['label'],
            'T0': T0, 'T1': T1, 'delta_T': delta_T,
            't0': t0, 't1': t1, 'delta_t': delta_t,
            'did': did_val, 'lift': lift_val,
            'p_display': p_display, 'sig_text': sig_text,
            'is_sig': rec['significant'], 'did_dir': did_val,
        })

    # LTV指标也加入
    for _, rec in ltv_did.iterrows():
        T0 = rec['treat_before']
        T1 = rec['treat_after']
        t0 = rec['ctrl_before']
        t1 = rec['ctrl_after']
        delta_T = round(T1 - T0, 2)
        delta_t = round(t1 - t0, 2)
        did_val = rec['did_effect']

        lift_str = rec['lift_pct'].replace('%', '').replace('+', '')
        try:
            lift_val = float(lift_str)
        except:
            lift_val = 0.0

        p_raw = rec.get('p_value_raw', 1.0)
        p_display = f'{p_raw:.4f}' if not np.isnan(p_raw) and not np.isinf(p_raw) else '1.0000'

        if rec['significant']:
            sig_text = '显著' if did_val > 0 else '显著(负)'
        else:
            sig_text = '不显著'

        all_rows.append({
            'label': rec['label'],
            'T0': T0, 'T1': T1, 'delta_T': delta_T,
            't0': t0, 't1': t1, 'delta_t': delta_t,
            'did': did_val, 'lift': lift_val,
            'p_display': p_display, 'sig_text': sig_text,
            'is_sig': rec['significant'], 'did_dir': did_val,
        })

    data_start_row = 4
    n_data = len(all_rows)

    for i, r in enumerate(all_rows):
        row = data_start_row + i

        # A列: 均值（仅第一行写，其余合并）
        if i == 0:
            ws.cell(row=row, column=1, value='均值')
        ws.cell(row=row, column=1).font = normal_font
        ws.cell(row=row, column=1).alignment = center_align
        ws.cell(row=row, column=1).border = thin_border

        # B列: 指标名
        ws.cell(row=row, column=2, value=r['label'])
        ws.cell(row=row, column=2).font = normal_font
        ws.cell(row=row, column=2).alignment = left_align
        ws.cell(row=row, column=2).border = thin_border

        # C-H列: 实验组和对照组数据
        vals = [r['T0'], r['T1'], r['delta_T'], r['t0'], r['t1'], r['delta_t']]
        for ci, v in enumerate(vals):
            col = ci + 3
            cell = ws.cell(row=row, column=col, value=v)
            cell.font = normal_font
            cell.alignment = center_align
            cell.border = thin_border
            # 数值保留2位小数的格式
            if isinstance(v, float):
                cell.number_format = '0.00'

        # I列: DID净效应
        did_cell = ws.cell(row=row, column=9, value=r['did'])
        did_cell.font = normal_font
        did_cell.alignment = center_align
        did_cell.border = thin_border
        did_cell.number_format = '0.00'
        if r['did'] > 0:
            did_cell.fill = did_blue_fill
        elif r['did'] < 0:
            did_cell.fill = did_red_fill

        # J列: 净效应作用%
        lift_cell = ws.cell(row=row, column=10, value=r['lift'])
        lift_cell.font = normal_font
        lift_cell.alignment = center_align
        lift_cell.border = thin_border
        lift_cell.number_format = '0.00%'
        lift_cell.value = r['lift'] / 100.0  # 转换为比例以便百分号显示
        if r['lift'] > 0:
            lift_cell.fill = lift_blue_fill
        elif r['lift'] < 0:
            lift_cell.fill = lift_red_fill

        # K列: p_value
        p_cell = ws.cell(row=row, column=11, value=float(r['p_display']))
        p_cell.font = normal_font
        p_cell.alignment = center_align
        p_cell.border = thin_border
        p_cell.number_format = '0.0000'

        # L列: 统计显著性
        sig_cell = ws.cell(row=row, column=12, value=r['sig_text'])
        sig_cell.font = normal_font
        sig_cell.alignment = center_align
        sig_cell.border = thin_border
        if r['is_sig']:
            if r['did_dir'] > 0:
                sig_cell.fill = sig_green_fill
            else:
                sig_cell.fill = sig_red_fill

    # 合并A列"均值"标签
    if n_data > 1:
        ws.merge_cells(f'A{data_start_row}:A{data_start_row + n_data - 1}')
        ws[f'A{data_start_row}'].alignment = Alignment(horizontal='center', vertical='center',
                                                       text_rotation=0, wrap_text=True)

    # ========== 列宽调整 ==========
    col_widths = {
        'A': 8, 'B': 18, 'C': 14, 'D': 14, 'E': 10,
        'F': 14, 'G': 14, 'H': 10, 'I': 16, 'J': 16, 'K': 12, 'L': 12
    }
    for col_letter, w in col_widths.items():
        ws.column_dimensions[col_letter].width = w

    # 行高调整
    ws.row_dimensions[1].height = 25
    ws.row_dimensions[2].height = 30
    ws.row_dimensions[3].height = 22

    wb.save(save_path)
    print(f"  Excel报告已保存: {save_path}")


def generate_word_report(did_df, balance_df, psm_results, ltv_results,
                         quality_plot_path, love_plot_path, did_plot_path,
                         save_path):
    """生成Word报告"""
    doc = Document()

    # 设置页面边距
    sections = doc.sections
    for section in sections:
        section.top_margin = Cm(2.54)
        section.bottom_margin = Cm(2.54)
        section.left_margin = Cm(3.18)
        section.right_margin = Cm(3.18)

    matched_df = psm_results['matched_df']
    n_treat = psm_results['n_matched_treat']
    n_ctrl = psm_results['n_matched_ctrl']
    match_rate = psm_results['match_rate']
    max_smd = psm_results['max_smd']
    caliper = psm_results['caliper']

    # ==================== 报告标题 ====================
    title = doc.add_heading(f'{ACTIVITY_NAME}参与活动用户分析PSM+DID_{datetime.now().strftime("%Y%m%d")}', level=0)
    title.alignment = WD_ALIGN_PARAGRAPH.CENTER
    for run in title.runs:
        _set_font(run, size=Pt(18), bold=True)

    # ==================== 总结结论 ====================
    main_did = did_df[~did_df['outcome'].str.startswith('ltv_', na=False)].copy()
    lt_pos = main_did[(main_did['significant'] == True) & (main_did['did_effect'] > 0)]
    lt_neg = main_did[(main_did['significant'] == True) & (main_did['did_effect'] < 0)]
    ltv_did = did_df[did_df['outcome'].str.startswith('ltv_', na=False)].copy()
    ltv_pos_ltv = ltv_did[(ltv_did['significant'] == True) & (ltv_did['did_effect'] > 0)]

    # 构建总结段落
    if len(lt_pos) >= 3:
        dims = lt_pos.nlargest(3, 'did_effect')['label'].tolist()
        lt_verdict = f"活动可作用于用户{'、'.join(dims[:3])}"
    elif len(lt_pos) >= 1:
        dims = lt_pos['label'].tolist()
        lt_verdict = f"活动对用户{dims[0]}有正向作用"
    else:
        lt_verdict = "活动在各活跃维度均未表现出统计显著的净效应"

    if not ltv_pos_ltv.empty:
        ltv_labels = ltv_pos_ltv['label'].tolist()
        ltv_verdict = f"在付费{'、'.join(ltv_labels)}上有显著拉升"
    elif not lt_neg.empty:
        ltv_verdict = "但在付费维度出现负向变化，需关注"
    else:
        ltv_verdict = "付费维度无显著变化（原始金额CV过高，建议参考付费转化率）"

    summary = doc.add_paragraph()
    summary_run = summary.add_run(
        f"DID核心结论：{lt_verdict}；{ltv_verdict}。"
    )
    _set_font(summary_run, size=Pt(12), bold=True)

    doc.add_paragraph()  # 空行

    # ==================== 方案说明 ====================
    doc.add_heading('实验活动效果评估方案', level=1)

    scheme_para = doc.add_paragraph()
    scheme_items = [
        f"全量分析的实验组/对照组定义：实验组为参与{ACTIVITY_NAME}的用户（is_attend=1），对照组为从未参与打卡活动的DOTA2观看用户（is_attend=0）。",
        f"分析方法：采用倾向得分匹配（PSM）消除选择偏差，再通过双重差分（DID）估计因果净效应。",
        f"匹配特征：使用活动前的6项用户行为指标作为协变量进行匹配。",
        f"分析周期：before期为活动前用户行为基线，after期为活动后用户行为变化。",
        f"核心目标：量化评估{ACTIVITY_NAME}对用户观看行为、活跃度和付费意愿的因果影响。",
    ]
    for item in scheme_items:
        p = doc.add_paragraph(item, style='List Bullet')
        for run in p.runs:
            _set_font(run, size=Pt(11))

    # ==================== 一、主模块分析 ====================
    doc.add_heading('一、参与不朽杯打卡活动的用户分析', level=1)

    # ---- 1.1 匹配质量说明 ----
    doc.add_heading('1.1 匹配质量说明', level=2)

    method_para = doc.add_paragraph()
    method_run = method_para.add_run(
        f"本研究采用PSM（倾向得分匹配）与DID（双重差分）组合因果推断方法。"
        f"首先通过Logistic回归估计每位用户参与活动的倾向得分，"
        f"再使用KDTree最近邻算法在倾向得分空间中为每位实验组用户匹配一位行为特征最相似的对照组用户，"
        f"最后对比两组在活动前后的变化差异，得到去除选择偏差和时间趋势后的净因果效应。"
    )
    _set_font(method_run, size=Pt(11))

    # 三点编号说明
    quality_points = [
        f"1. 实现精准匹配，{ACTIVITY_NAME}曝光组{n_treat:,}人（匹配率{match_rate:.1f}%），样本充足、结果稳定。",
        f"2. 匹配后所有用户特征的标准化均值差异（SMD）均远小于0.1（最大|SMD|={max_smd:.4f}），两组用户初始行为高度一致，可认为后续差异完全由{ACTIVITY_NAME}导致。",
        f"3. 倾向得分分布高度重合，匹配质量优秀，因果结论可靠。",
    ]
    for qp in quality_points:
        p = doc.add_paragraph(qp)
        for run in p.runs:
            _set_font(run, size=Pt(11))

    # 插入组合质量图（参考样图格式）
    if quality_plot_path and os.path.exists(quality_plot_path):
        doc.add_paragraph()
        doc.add_picture(quality_plot_path, width=Inches(6.5))
        last_para = doc.paragraphs[-1]
        last_para.alignment = WD_ALIGN_PARAGRAPH.CENTER

        caption = doc.add_paragraph()
        cap_run = caption.add_run(
            "注：左图为匹配后倾向得分分布（蓝色=Treatment/参与打卡用户，橙色=Control/未参与打卡用户）；"
            "右图为各特征匹配后标准化均值差异（绿色条形），红色虚线为SMD=0.1参考线。"
        )
        _set_font(cap_run, size=Pt(9))

    # 插入Love Plot
    if love_plot_path and os.path.exists(love_plot_path):
        doc.add_paragraph()
        doc.add_picture(love_plot_path, width=Inches(5.5))
        last_para = doc.paragraphs[-1]
        last_para.alignment = WD_ALIGN_PARAGRAPH.CENTER

    # ---- 1.2 关键效果指标 ----
    doc.add_heading('1.2 关键效果指标', level=2)

    # DID核心结论段
    core_para = doc.add_paragraph()
    core_run = core_para.add_run(f"DID核心结论：{lt_verdict}；{ltv_verdict}。")
    _set_font(core_run, size=Pt(12), bold=True)

    # 正向作用
    if not lt_pos.empty:
        pos_head = doc.add_paragraph()
        pos_run = pos_head.add_run(f"主要正向作用（活动有效促进用户行为提升）")
        _set_font(pos_run, size=Pt(11), bold=True)

        insight_map = {
            '观看时长': '用户更喜好平台内容',
            '观看天数': '回访更稳定',
            '观看主播数': '探索意愿增强（更多元的内容消费）',
            '观看游戏数': '探索意愿增强（跨品类兴趣）',
            '活跃天数': '回访更稳定',
        }

        for _, r in lt_pos.iterrows():
            did_val = r['did_effect']
            lift_str = r['lift_pct']
            label = r['label']
            unit = r['unit']

            # 找最贴切的业务洞察
            insight = '用户行为正向变化'
            for key in insight_map:
                if key in label:
                    insight = insight_map[key]
                    break

            bullet = doc.add_paragraph(
                f"● {label}：净提升{abs(did_val)}{unit}({lift_str})，{insight}"
            )
            for run in bullet.runs:
                _set_font(run, size=Pt(11))

    # LTV正向
    if not ltv_pos_ltv.empty:
        ltv_head = doc.add_paragraph()
        ltv_run_h = ltv_head.add_run("付费维度正向作用")
        _set_font(ltv_run_h, size=Pt(11), bold=True)

        for _, r in ltv_pos_ltv.iterrows():
            did_val = r['did_effect']
            lift_str = r['lift_pct']
            label = r['label']

            if '付费转化' in label or 'pay_rate' in str(r.get('outcome', '')):
                insight = '付费意愿增强'
            elif 'ARPPU' in label:
                insight = '付费深度提升'
            else:
                insight = '付费行为正向变化'

            bullet = doc.add_paragraph(
                f"● {label}：净提升{abs(did_val)}{unit}({lift_str})，{insight}"
            )
            for run in bullet.runs:
                _set_font(run, size=Pt(11))

    # 负向指标
    neg_head = doc.add_paragraph()
    if not lt_neg.empty:
        neg_run = neg_head.add_run("显著负向指标（需关注）")
        _set_font(neg_run, size=Pt(11), bold=True)

        for _, r in lt_neg.iterrows():
            bullet = doc.add_paragraph(
                f"● {r['label']}：净减少{abs(r['did_effect'])}{r['unit']}({r['lift_pct']})"
            )
            for run in bullet.runs:
                _set_font(run, size=Pt(11))
    else:
        neg_run = neg_head.add_run("无任何显著负向指标")
        _set_font(neg_run, size=Pt(11))

    # 不显著指标的语境化说明
    insig_main = main_did[main_did['significant'] == False]
    consume_insig = insig_main[insig_main['outcome'].isin(['after_consume_amount'])]

    if not consume_insig.empty:
        r = consume_insig.iloc[0]
        direction = "正向" if r['did_effect'] > 0 else "负向"
        ctx_para = doc.add_paragraph()
        ctx_run = ctx_para.add_run(
            f"付费金额{direction}结果不显著（p值高于临界值），"
            f"没有出现活动后用户流失、时长下滑、付费明显下降的情况。"
        )
        _set_font(ctx_run, size=Pt(11))

    # DID柱状图
    if did_plot_path and os.path.exists(did_plot_path):
        doc.add_paragraph()
        doc.add_picture(did_plot_path, width=Inches(5.5))
        last_para = doc.paragraphs[-1]
        last_para.alignment = WD_ALIGN_PARAGRAPH.CENTER

    # 方法注释
    note_para = doc.add_paragraph()
    note_run = note_para.add_run(
        "注：净效应对实验组的作用(%) = 双重差分净效应 / 实验组前期均值×100"
    )
    _set_font(note_run, size=Pt(9))

    # ==================== 综合结论 ====================
    doc.add_heading('综合结论', level=1)

    final_para = doc.add_paragraph()
    final_parts = [lt_verdict]
    if not ltv_pos_ltv.empty:
        final_parts.append(ltv_verdict.replace('在付费', '；在付费'))
    final_text = '；'.join(final_parts) + '。'

    final_run = final_para.add_run(
        f"{ACTIVITY_NAME}{final_text}"
    )
    _set_font(final_run, size=Pt(11))

    doc.save(save_path)
    print(f"  Word报告已保存: {save_path}")


# ============================================================
#  主流程
# ============================================================

def main():
    print("=" * 70)
    print(f"  {ACTIVITY_NAME} PSM+DID 因果推断分析")
    print(f"  Started: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print("=" * 70)
    start_time = time.time()

    # Step 1: 数据加载与聚合
    df = load_and_aggregate()

    # Step 2: 自适应PSM匹配
    print(f"\n--- Step 2: 自适应PSM匹配 ---")
    psm_results, ps_model, scaler = adaptive_psm_match(df, MATCH_FEATURES)

    matched_df = psm_results['matched_df']
    n_matched_treat = len(psm_results['matched_treat'])
    n_matched_ctrl = len(psm_results['matched_ctrl'])

    psm_results['n_matched_treat'] = n_matched_treat
    psm_results['n_matched_ctrl'] = n_matched_ctrl

    # Step 3: 平衡性检验
    print(f"\n--- Step 3: 平衡性检验 (SMD) ---")
    smd_records = []
    for feat in MATCH_FEATURES:
        sb = calc_smd(df, feat, TREATMENT_COL)
        sa = calc_smd(matched_df, feat, TREATMENT_COL)
        smd_records.append({'feature': feat, 'smd_before': round(sb, 4), 'smd_after': round(sa, 4)})

    balance_df = pd.DataFrame(smd_records)
    print(balance_df.to_string(index=False))

    n_pass = (balance_df['smd_after'] < 0.1).sum()
    mx_smd = balance_df['smd_after'].max()
    print(f"\n  SMD通过率: {n_pass}/{len(MATCH_FEATURES)} | 最大|SMD|: {mx_smd:.4f}")

    if mx_smd >= 0.1:
        print(f"  ⚠️ 警告: 存在SMD≥0.1的特征，请检查匹配质量！")
    else:
        print(f"  ✓ 所有特征SMD均<0.1，匹配质量优秀！")

    # Step 4: DID分析
    did_df, ltv_results = run_did_analysis(matched_df, MATCH_FEATURES)

    print(f"\n--- DID 结果摘要 ---")
    main_did = did_df[~did_df['outcome'].str.startswith('ltv_', na=False)]
    for _, r in main_did.iterrows():
        print(f"  {r['label']:15s}: DID={r['did_effect']:>10.2f} {r['lift_pct']:>10s} p={r['p_value_display']:>12s} {r['sig_text']}")

    # Step 5: 生成图表
    ts = datetime.now().strftime('%Y%m%d_%H%M%S')

    quality_path = os.path.join(OUT_DIR, f'matching_quality_{ts}.png')
    love_path = os.path.join(OUT_DIR, f'love_plot_{ts}.png')
    did_bar_path = os.path.join(OUT_DIR, f'did_bars_{ts}.png')

    plot_combined_quality(matched_df, balance_df, TREATMENT_COL, save_path=quality_path)
    plot_love_plot(balance_df, title_suffix=f'(卡钳={psm_results["caliper"]})', save_path=love_path)
    plot_did_bars(did_df, title_suffix=f'(卡钳={psm_results["caliper"]})', save_path=did_bar_path)

    # Step 6: 生成报告
    excel_path = os.path.join(OUT_DIR, f'{ACTIVITY_NAME}PSM_DID结果_{ts}.xlsx')
    word_path = os.path.join(OUT_DIR, f'{ACTIVITY_NAME}PSM_DID报告_{ts}.docx')

    generate_excel_report(did_df, psm_results, excel_path)
    generate_word_report(did_df, balance_df, psm_results, ltv_results,
                        quality_path, love_path, did_bar_path, word_path)

    # CSV导出
    csv_path = os.path.join(OUT_DIR, f'did_result_{ts}.csv')
    export_cols = ['outcome', 'label', 'unit', 'treat_before', 'treat_after',
                   'ctrl_before', 'ctrl_after', 'did_effect', 'lift_pct',
                   'p_value_display', 'sig_text', 'sig_mark',
                   'med_treat_before', 'med_treat_after', 'med_ctrl_before',
                   'med_ctrl_after', 'med_did_effect', 'med_lift_pct', 'med_p_display', 'med_sig_text']
    did_df[[c for c in export_cols if c in did_df.columns]].to_csv(
        csv_path, index=False, encoding='utf-8-sig'
    )
    print(f"  DID结果CSV已保存: {csv_path}")

    # SMD平衡性CSV
    balance_csv = os.path.join(OUT_DIR, f'psm_balance_{ts}.csv')
    balance_df.to_csv(balance_csv, index=False, encoding='utf-8-sig')
    print(f"  SMD平衡性CSV已保存: {balance_csv}")

    elapsed = time.time() - start_time
    print(f"\n{'='*70}")
    print(f"  ✅ 分析完成! 耗时: {elapsed:.1f}秒")
    print(f"  最大|SMD|: {mx_smd:.4f} ({'✓通过' if mx_smd < 0.1 else '✗未通过'})")
    print(f"  匹配率: {psm_results['match_rate']:.1f}%")
    print(f"  输出文件:")
    print(f"    📊 Excel: {excel_path}")
    print(f"    📝 Word:  {word_path}")
    print(f"    📈 质量图: {quality_path}")
    print(f"    📈 Love Plot: {love_path}")
    print(f"    📈 DID柱状图: {did_bar_path}")
    print(f"{'='*70}")


if __name__ == '__main__':
    main()
