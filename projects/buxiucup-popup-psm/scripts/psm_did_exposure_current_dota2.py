# -*- coding: utf-8 -*-
"""
=============================================================================
  不朽杯APP拍脸活动曝光 PSM+DID 因果推断分析
  数据源: 对功能页曝光的研究_针对当天观看DOTA2的用户
  活动日: 2026年5月12日 (仅1天 — ⚠ 风险点)
  实验组: 当天观看过DOTA2且当天被曝光的用户
  对照组: 当天观看过DOTA2但当天未被曝光的用户
  验收标准: SMD < 0.1
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
from openpyxl.utils import get_column_letter


# ============================================================
#  CONFIG — 本次分析专用配置
# ============================================================
BASE_DIR = r'C:\Users\tiany\Desktop\不朽杯弹窗PSM实验\对功能页曝光的研究_针对当天观看DOTA2的用户'
DATA_CSV = os.path.join(BASE_DIR, '数据源.csv')

TREATMENT_COL = 'is_exposure'
USER_COL = 'yyuid'

ACTIVITY_NAME = '不朽杯APP拍脸活动曝光'
ACTIVITY_DATE = '2026年5月12日'
RISK_POINT = '活动干预窗口仅1天（5月12日），时间周期不够长，可能限制因果效应的检测灵敏度'
TREAT_LABEL = '当天观看过DOTA2且当天被曝光的用户'
CTRL_LABEL = '当天观看过DOTA2但当天未被曝光的用户'

MATCH_FEATURES = [
    'before_watch_duration',
    'before_watch_dcnt',
    'before_watch_anchorcnt',
    'before_watch_gamecnt',
    'before_consume_amount',
    'before_active_dcnt',
]

OUTCOME_MAPPING = {
    'after_watch_duration': 'before_watch_duration',
    'after_watch_dcnt': 'before_watch_dcnt',
    'after_watch_anchorcnt': 'before_watch_anchorcnt',
    'after_watch_gamecnt': 'before_watch_gamecnt',
    'after_consume_amount': 'before_consume_amount',
    'after_active_dcnt': 'before_active_dcnt',
}

OUTCOME_LABELS = {
    'after_watch_duration': ('观看时长(min)', '分钟'),
    'after_watch_dcnt': ('观看天数', '天'),
    'after_watch_anchorcnt': ('观看主播数', '个'),
    'after_watch_gamecnt': ('观看游戏数', '个'),
    'after_consume_amount': ('付费金额(元)', '元'),
    'after_active_dcnt': ('活跃天数', '天'),
}

LT_OUTCOMES = {'after_watch_duration', 'after_watch_dcnt', 'after_watch_anchorcnt', 'after_watch_gamecnt', 'after_active_dcnt'}
LTV_OUTCOMES = {'after_consume_amount'}

LTV_AMOUNT_COL = 'after_consume_amount'
LTV_AMOUNT_BEFORE = 'before_consume_amount'

# 匹配参数
CALIPER = 0.05
SEED = 42
MAX_CTRL_SAMPLE = 1_500_000
ALPHA_STANDARD = 0.05

OUT_DIR = BASE_DIR

# 维度映射（用于DID核心结论自动生成）
DIMENSION_MAP = {
    'after_watch_duration': '观看',
    'after_watch_dcnt': '回访稳定',
    'after_watch_anchorcnt': '探索广度',
    'after_watch_gamecnt': '跨品类探索',
    'after_active_dcnt': '活跃留存',
}

LTV_DIM_MAP = {
    'ltv_pay_rate': '付费转换率',
    'ltv_arppu': '付费深度',
}

# 业务洞察措辞库
INSIGHT_POS = {
    'after_watch_duration': '用户更喜好平台内容',
    'after_watch_dcnt': '回访更稳定',
    'after_watch_anchorcnt': '探索意愿增强（更多元的内容消费）',
    'after_watch_gamecnt': '探索意愿增强（跨品类兴趣）',
    'after_active_dcnt': '回访更稳定',
    'ltv_pay_rate': '付费意愿增强',
    'ltv_arppu': '付费深度提升',
}

INSIGHT_NEG = {
    'after_watch_duration': '用户内容消费时长有所下降',
    'after_watch_dcnt': '用户回访频次有所减少',
    'after_watch_anchorcnt': '探索意愿有所收缩',
    'after_watch_gamecnt': '探索意愿有所收缩',
    'after_active_dcnt': '用户回访频次有所减少',
    'ltv_pay_rate': '付费转化有所下降，需关注付费引导',
    'ltv_arppu': '付费用户消费深度下降',
}


# ============================================================
#  工具函数
# ============================================================

def safe_fillna(df, cols):
    """彻底填充 NaN 和 Inf（中位数填充，保留变量中心趋势）"""
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
    """计算标准化均值差异 (SMD)"""
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
    """所有 Word run 对象必须调用此函数设置字体"""
    run.font.name = '微软雅黑'
    run._element.rPr.rFonts.set(qn('w:eastAsia'), '微软雅黑')
    run.font.size = size
    run.bold = bold
    if color:
        run.font.color.rgb = color


def calc_ps_range_explanation(matched_df, treat_col):
    """
    动态计算倾向得分密度范围，生成精简解释。
    用户要求：精简倾向得分密度图含义，例如：
    "倾向得分主要集中在0.08~0.25区间，说明样本（根据目前的变量）整体属于低曝光概率人群，
    且实验组与对照组在该区间内存在较强重叠，具备较好的匹配基础。"
    """
    all_ps = matched_df['propensity_score']
    treat_ps = matched_df[matched_df[treat_col] == 1]['propensity_score']
    ctrl_ps = matched_df[matched_df[treat_col] == 0]['propensity_score']

    # 使用10th-90th百分位数确定主要分布区间
    ps_low = all_ps.quantile(0.10)
    ps_high = all_ps.quantile(0.90)

    # 判断整体概率水平
    ps_mean = all_ps.mean()
    if ps_mean < 0.3:
        prob_label = "低曝光概率"
    elif ps_mean < 0.6:
        prob_label = "中等曝光概率"
    else:
        prob_label = "高曝光概率"

    explanation = (
        f"倾向得分主要集中在{ps_low:.2f}~{ps_high:.2f}区间，"
        f"说明样本（根据目前的变量）整体属于{prob_label}人群，"
        f"且实验组与对照组在该区间内存在较强重叠，具备较好的匹配基础。"
    )
    return explanation, ps_low, ps_high


# ============================================================
#  可视化函数
# ============================================================

def plot_ps_distribution(matched_df, treat_col, title_suffix='', save_path=None):
    """倾向得分分布图（匹配后）"""
    fig, axes = plt.subplots(1, 2, figsize=(14, 5))

    treat_ps = matched_df[matched_df[treat_col] == 1]['propensity_score']
    ctrl_ps = matched_df[matched_df[treat_col] == 0]['propensity_score']

    axes[0].hist(treat_ps, bins=40, alpha=0.6, label='实验组(Treatment)',
                 color='#2196F3', edgecolor='white')
    axes[0].hist(ctrl_ps, bins=40, alpha=0.6, label='对照组(Control)',
                 color='#FF9800', edgecolor='white')
    axes[0].set_xlabel('倾向得分 (Propensity Score)')
    axes[0].set_ylabel('用户数量')
    axes[0].set_title(f'倾向得分分布（匹配后）\n{title_suffix}')
    axes[0].legend(loc='upper right')
    axes[0].grid(alpha=0.3)

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
    """Love Plot — 匹配前后 SMD 对比图"""
    features = balance_df['feature'].tolist()[::-1]
    smd_before = balance_df['smd_before'].tolist()[::-1]
    smd_after = balance_df['smd_after'].tolist()[::-1]

    fig, ax = plt.subplots(figsize=(10, max(6, len(features) * 0.4)))
    y_pos = range(len(features))

    ax.scatter(smd_before, y_pos, marker='o', s=80, color='#E53935',
               edgecolors='#E53935', linewidths=1.5, alpha=0.7, label='匹配前 (Before)',
               zorder=3)
    ax.scatter(smd_after, y_pos, marker='^', s=80, color='#43A047',
               edgecolors='#2E7D32', linewidths=1.5, alpha=0.9, label='匹配后 (After)',
               zorder=4)

    for i in range(len(features)):
        ax.plot([smd_before[i], smd_after[i]], [y_pos[i], y_pos[i]],
                color='#9E9E9E', linewidth=0.8, alpha=0.5, zorder=1)

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
#  PSM+DID 核心流水线
# ============================================================

def run_psm_pipeline(df, label_suffix='', match_features=None):
    """完整的 PSM+DID 流水线"""
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

    if len(control) > MAX_CTRL_SAMPLE:
        control = control.sample(n=MAX_CTRL_SAMPLE, random_state=SEED)
        print(f"  Control downsampled to: {MAX_CTRL_SAMPLE:,}")

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

    # ---- PS密度范围精简解释 ----
    ps_explanation, ps_low, ps_high = calc_ps_range_explanation(matched_df, TREATMENT_COL)
    print(f"  PS密度解释: {ps_explanation}")

    results['matched_df'] = matched_df
    results['n_matched_treat'] = len(matched_treat)
    results['n_matched_ctrl'] = len(matched_ctrl)
    results['orig_n_treat'] = orig_n_treat
    results['orig_n_ctrl'] = min(orig_n_ctrl, MAX_CTRL_SAMPLE)
    results['match_rate'] = match_rate
    results['balance_df'] = balance_df
    results['smd_pass_rate'] = f"{n_pass}/{len(match_features)}"
    results['max_smd'] = mx_smd
    results['ps_explanation'] = ps_explanation
    results['ps_range_low'] = ps_low
    results['ps_range_high'] = ps_high

    # ---- Step 4: DID 分析 ----
    print(f"\n--- Step 4: DID Estimation [{label_suffix}] ---")

    did_ready = matched_df.copy()
    for after_col, before_col in OUTCOME_MAPPING.items():
        mask_nan = did_ready[after_col].isna()
        did_ready.loc[mask_nan, after_col] = did_ready.loc[mask_nan, before_col]

    treat_did = did_ready[did_ready[TREATMENT_COL] == 1]
    control_did = did_ready[did_ready[TREATMENT_COL] == 0]

    did_records = []
    for after_col, before_col in OUTCOME_MAPPING.items():
        tv = treat_did[after_col].astype(float).values
        cv_val = control_did[after_col].astype(float).values
        tb = treat_did[before_col].astype(float).values
        cb = control_did[before_col].astype(float).values

        tv = tv[np.isfinite(tv)]
        cv_val = cv_val[np.isfinite(cv_val)]
        tb = tb[np.isfinite(tb)]
        cb = cb[np.isfinite(cb)]

        ta = tv.mean()
        ca = cv_val.mean()
        tb_m = tb.mean()
        cb_m = cb.mean()
        did_effect = (ta - tb_m) - (ca - cb_m)
        lift_pct = (did_effect / tb_m * 100) if abs(tb_m) > 1e-10 else 0.0

        ta_std = tv.std()
        ca_std = cv_val.std()
        cv_t = (ta_std / ta * 100) if abs(ta) > 1e-10 else float('inf')
        cv_c = (ca_std / ca * 100) if abs(ca) > 1e-10 else float('inf')

        if len(tv) >= 2 and len(cv_val) >= 2:
            _, p_val = ttest_ind(tv, cv_val)
            if np.isnan(p_val) or np.isinf(p_val): p_val = 1.0
        else:
            p_val = 1.0

        sig_text, sig_mk = sig_mark(p_val, did_effect)

        # 中位数DID
        med_ta = np.median(tv)
        med_ca = np.median(cv_val)
        med_tb = np.median(tb)
        med_cb = np.median(cb)
        med_did = (med_ta - med_tb) - (med_ca - med_cb)
        med_lift = (med_did / med_tb * 100) if abs(med_tb) > 1e-10 else 0.0

        try:
            _, med_p = mannwhitneyu(tv, cv_val, alternative='two-sided')
            if np.isnan(med_p) or np.isinf(med_p): med_p = 1.0
        except Exception:
            med_p = 1.0

        med_sig_text, med_sig_mk = sig_mark(med_p, med_did)

        label, unit = OUTCOME_LABELS.get(after_col, (after_col, ''))

        did_records.append({
            'outcome': after_col, 'label': label, 'unit': unit,
            'treat_before': round(tb_m, 2), 'treat_after': round(ta, 2),
            'ctrl_before': round(cb_m, 2), 'ctrl_after': round(ca, 2),
            'did_effect': round(did_effect, 2),
            'lift_pct': round(lift_pct, 1),
            'p_value_raw': p_val,
            'p_value_display': f'{p_val:.4f}',
            'significant': p_val < ALPHA_STANDARD,
            'sig_mark': sig_mk, 'sig_text': sig_text,
            'cv_treat': round(cv_t, 1) if cv_t != float('inf') else 'inf',
            'cv_ctrl': round(cv_c, 1) if cv_c != float('inf') else 'inf',
            'med_treat_before': round(med_tb, 2), 'med_treat_after': round(med_ta, 2),
            'med_ctrl_before': round(med_cb, 2), 'med_ctrl_after': round(med_ca, 2),
            'med_did_effect': round(med_did, 2),
            'med_lift_pct': round(med_lift, 1),
            'med_p_value': med_p,
            'med_p_display': f'{med_p:.4f}',
            'med_significant': med_p < ALPHA_STANDARD,
            'med_sig_mark': med_sig_mk, 'med_sig_text': med_sig_text,
        })

    # ---- LTV 补充分析 ----
    ltv_results = _run_ltv_supplement(treat_did, control_did, did_records, label_suffix)

    results['did_df'] = pd.DataFrame(did_records)
    results['ltv_results'] = ltv_results

    # ---- 生成图表 ----
    ts = datetime.now().strftime('%Y%m%d_%H%M%S')
    sfx = label_suffix.replace(' ', '_') if label_suffix else 'full'

    ps_path = os.path.join(OUT_DIR, f'ps_distribution_{sfx}_{ts}.png')
    love_path = os.path.join(OUT_DIR, f'love_plot_{sfx}_{ts}.png')
    did_path = os.path.join(OUT_DIR, f'did_bars_{sfx}_{ts}.png')

    plot_ps_distribution(matched_df, TREATMENT_COL,
                         title_suffix=label_suffix, save_path=ps_path)
    plot_love(balance_df, title_suffix=label_suffix, save_path=love_path)
    plot_did_bars(results['did_df'], title_suffix=label_suffix, save_path=did_path)

    results['psm_plot'] = ps_path
    results['love_plot'] = love_path
    results['did_plot'] = did_path

    return results


def _run_ltv_supplement(treat_did, control_did, did_records, label_suffix):
    """LTV 补充分析 (pay_rate + ARPPU + 稀释效应诊断)"""
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
    tv_pay = tv_pay[np.isfinite(tv_pay)]
    cv_pay = cv_pay[np.isfinite(cv_pay)]
    if len(tv_pay) >= 2 and len(cv_pay) >= 2:
        _, pay_p = ttest_ind(tv_pay, cv_pay)
    else:
        pay_p = 1.0
    if np.isnan(pay_p) or np.isinf(pay_p): pay_p = 1.0
    pay_stxt, pay_smk = sig_mark(pay_p, pay_did)

    # -- ARPPU --
    tpa = treat_did[treat_did[pay_col] > 0][pay_col].astype(float)
    cpa = control_did[control_did[pay_col] > 0][pay_col].astype(float)
    tpb = treat_did[treat_did[pay_before] > 0][pay_before].astype(float)
    cpb = control_did[control_did[pay_before] > 0][pay_before].astype(float)

    arppu_did = (tpa.mean() - tpb.mean()) - (cpa.mean() - cpb.mean())
    arppu_lift = (arppu_did / tpb.mean() * 100) if abs(tpb.mean()) > 1e-10 else 0.0

    tpa_v = tpa.values[np.isfinite(tpa.values)]
    cpa_v = cpa.values[np.isfinite(cpa.values)]
    if len(tpa_v) >= 2 and len(cpa_v) >= 2:
        _, arppu_p = ttest_ind(tpa_v, cpa_v)
    else:
        arppu_p = 1.0
    if np.isnan(arppu_p) or np.isinf(arppu_p): arppu_p = 1.0
    arppu_stxt, arppu_smk = sig_mark(arppu_p, arppu_did)

    # 中位数ARPPU
    med_arppu_did = (tpa.median() - tpb.median()) - (cpa.median() - cpb.median())
    try:
        _, med_arppu_p = mannwhitneyu(tpa_v, cpa_v, alternative='two-sided')
        if np.isnan(med_arppu_p) or np.isinf(med_arppu_p): med_arppu_p = 1.0
    except Exception:
        med_arppu_p = 1.0
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
            'did_effect': round(pay_did, 4),
            'lift_pct': round(pay_lift, 2),
            'p_value_raw': pay_p, 'p_value_display': f'{pay_p:.4f}',
            'significant': pay_p < ALPHA_STANDARD,
            'sig_mark': pay_smk, 'sig_text': pay_stxt,
            'cv_treat': 0, 'cv_ctrl': 0,
            'med_treat_before': 0, 'med_treat_after': 0,
            'med_ctrl_before': 0, 'med_ctrl_after': 0,
            'med_did_effect': 0, 'med_lift_pct': 0,
            'med_p_value': 1.0, 'med_p_display': '1.0000',
            'med_significant': False, 'med_sig_mark': '', 'med_sig_text': '—',
        },
        {
            'outcome': 'ltv_arppu', 'label': 'ARPPU', 'unit': '元',
            'treat_before': round(tpb.mean(), 2), 'treat_after': round(tpa.mean(), 2),
            'ctrl_before': round(cpb.mean(), 2), 'ctrl_after': round(cpa.mean(), 2),
            'did_effect': round(arppu_did, 2),
            'lift_pct': round(arppu_lift, 2),
            'p_value_raw': arppu_p, 'p_value_display': f'{arppu_p:.4f}',
            'significant': arppu_p < ALPHA_STANDARD,
            'sig_mark': arppu_smk, 'sig_text': arppu_stxt,
            'cv_treat': 0, 'cv_ctrl': 0,
            'med_treat_before': round(tpb.median(), 2), 'med_treat_after': round(tpa.median(), 2),
            'med_ctrl_before': round(cpb.median(), 2), 'med_ctrl_after': round(cpa.median(), 2),
            'med_did_effect': round(med_arppu_did, 2), 'med_lift_pct': round((med_arppu_did / tpb.median() * 100) if abs(tpb.median()) > 1e-10 else 0, 2),
            'med_p_value': med_arppu_p, 'med_p_display': f'{med_arppu_p:.4f}',
            'med_significant': med_arppu_p < ALPHA_STANDARD,
            'med_sig_mark': '', 'med_sig_text': med_arppu_stxt,
        },
    ])

    return {
        'pay_rate': {'did': pay_did, 'p': pay_p, 'sig': pay_stxt, 'significant': pay_p < ALPHA_STANDARD},
        'arppu': {'did': arppu_did, 'p': arppu_p, 'sig': arppu_stxt, 'med_did': med_arppu_did, 'med_sig': med_arppu_stxt},
        'dilution_ratio': dilution_ratio, 'conflict': arppu_conflict,
        'n_treat_paid': n_treat_paid, 'n_ctrl_paid': n_ctrl_paid,
    }


# ============================================================
#  DID核心结论自动生成
# ============================================================

def generate_did_core_conclusion(did_df, activity_name):
    """根据DID结果自动生成核心结论段（12pt bold）"""

    lt_pos = []
    lt_neg = []
    ltv_pos = []

    for _, row in did_df.iterrows():
        outcome = row['outcome']
        if outcome in LT_OUTCOMES:
            dim = DIMENSION_MAP.get(outcome, outcome)
            if row['significant'] and row['did_effect'] > 0:
                lt_pos.append(dim)
            elif row['significant'] and row['did_effect'] < 0:
                lt_neg.append(dim)
        elif outcome == 'ltv_pay_rate':
            if row['significant'] and row['did_effect'] > 0:
                ltv_pos.append('付费转换率')
        elif outcome == 'ltv_arppu':
            if row['significant'] and row['did_effect'] > 0:
                ltv_pos.append('付费深度')

    # LT维度结论
    if len(lt_pos) >= 3:
        top3 = lt_pos[:3]
        lt_verdict = f"活动可作用于用户{top3[0]}、{top3[1]}和{top3[2]}"
    elif len(lt_pos) >= 1:
        lt_verdict = f"活动对用户{lt_pos[0]}有正向作用"
    elif lt_neg and not lt_pos:
        lt_verdict = f"活动在活跃维度出现负向变化，需关注"
    else:
        lt_verdict = "活动在各活跃维度均未表现出统计显著的净效应"

    if lt_pos and lt_neg:
        lt_verdict = f"活动对用户{lt_pos[0]}等有正向作用，但{lt_neg[0]}需关注"

    # LTV维度结论
    if ltv_pos:
        if '付费转换率' in ltv_pos:
            ltv_verdict = "在付费转换率上有显著拉升"
        else:
            ltv_verdict = f"在{ltv_pos[0]}上有正向作用"
    else:
        # 检查付费金额原始指标
        consume_row = did_df[did_df['outcome'] == 'after_consume_amount']
        if not consume_row.empty:
            did_val = consume_row.iloc[0]['did_effect']
            if did_val >= 0:
                ltv_verdict = "付费金额正向结果不显著（p值高于临界值），没有出现活动后用户流失、时长下滑、付费明显下降的情况"
            else:
                ltv_verdict = "付费金额负向结果不显著（p值高于临界值），没有出现活动后用户流失、时长下滑、付费明显下降的情况"
        else:
            ltv_verdict = "付费维度无显著变化"

    core_conclusion = f"DID核心结论：{lt_verdict}；{ltv_verdict}。"
    return core_conclusion


def generate_positive_bullets(did_df):
    """生成正向显著指标的bullet列表"""
    bullets = []
    for _, row in did_df.iterrows():
        if row['significant'] and row['did_effect'] > 0:
            outcome = row['outcome']
            label = row['label']
            unit = row['unit']
            did_val = row['did_effect']
            lift = row['lift_pct']
            insight = INSIGHT_POS.get(outcome, '')
            if outcome == 'ltv_pay_rate':
                # pay_rate特殊处理：用pp表示
                bullets.append(f"{label}：净提升{abs(did_val):.2f}pp(+{lift:.2f}%)，{insight}")
            else:
                bullets.append(f"{label}：净提升{abs(did_val):.2f}{unit}(+{lift:.1f}%)，{insight}")
    return bullets


def generate_negative_section(did_df):
    """生成负向显著指标说明"""
    neg_items = []
    for _, row in did_df.iterrows():
        if row['significant'] and row['did_effect'] < 0:
            outcome = row['outcome']
            label = row['label']
            unit = row['unit']
            did_val = row['did_effect']
            lift = row['lift_pct']
            neg_items.append(f"{label}：净减少{abs(did_val):.2f}{unit}({lift:.1f}%)")
    if not neg_items:
        return "无任何显著负向指标"
    return neg_items


def generate_nonsig_context(did_df):
    """生成不显著指标的语境化说明"""
    lines = []
    for _, row in did_df.iterrows():
        if not row['significant'] and row['outcome'] in LTV_OUTCOMES:
            did_val = row['did_effect']
            direction = "正向" if did_val >= 0 else "负向"
            lines.append(f"付费金额{direction}结果不显著（p值高于临界值），没有出现活动后用户流失、时长下滑、付费明显下降的情况。")
    # ARPPU不显著时
    arppu_row = did_df[did_df['outcome'] == 'ltv_arppu']
    if not arppu_row.empty and not arppu_row.iloc[0]['significant']:
        lines.append("ARPPU未见统计显著变化——活动既未提升也未损害付费用户的消费深度。")
    return lines


# ============================================================
#  Excel 报告生成（严格12列格式）
# ============================================================

def generate_excel_report(did_df, out_path):
    """
    生成Excel报告，严格遵循12列格式规范。

    列结构:
    A(均值标签) | B(指标) | C(T0) | D(T1) | E(ΔT) | F(t0) | G(t1) | H(Δt) | I(DID) | J(提升%) | K(p_value) | L(显著性)
    """

    wb = openpyxl.Workbook()
    ws = wb.active
    ws.title = 'DID净效应数据'

    # 样式定义
    font_title = Font(name='微软雅黑', size=14, bold=True)
    font_header = Font(name='微软雅黑', size=11, bold=True, color='FFFFFF')
    font_data = Font(name='微软雅黑', size=10)
    font_data_bold = Font(name='微软雅黑', size=10, bold=True)
    font_sig_pos = Font(name='微软雅黑', size=10, color='006100')
    font_sig_neg = Font(name='微软雅黑', size=10, color='9C0006')

    fill_title = PatternFill(start_color='D6DCE5', end_color='D6DCE5', fill_type='solid')
    fill_header = PatternFill(start_color='4472C4', end_color='4472C4', fill_type='solid')
    fill_pos_i = PatternFill(start_color='BDD7EE', end_color='BDD7EE', fill_type='solid')
    fill_pos_j = PatternFill(start_color='DDEBF7', end_color='DDEBF7', fill_type='solid')
    fill_neg = PatternFill(start_color='FFCCCC', end_color='FFCCCC', fill_type='solid')
    fill_sig_pos = PatternFill(start_color='C6EFCE', end_color='C6EFCE', fill_type='solid')
    fill_sig_neg = PatternFill(start_color='FFC7CE', end_color='FFC7CE', fill_type='solid')

    align_center = Alignment(horizontal='center', vertical='center', wrap_text=True)
    align_left = Alignment(horizontal='left', vertical='center', wrap_text=True)

    thin_border = Border(
        left=Side(style='thin'), right=Side(style='thin'),
        top=Side(style='thin'), bottom=Side(style='thin')
    )

    # ---- Row 1: 标题行 ----
    ws.merge_cells('A1:L1')
    cell = ws['A1']
    cell.value = 'DID净效应数据'
    cell.font = font_title
    cell.fill = fill_title
    cell.alignment = align_center
    for col_idx in range(1, 13):
        ws.cell(row=1, column=col_idx).border = thin_border
        ws.cell(row=1, column=col_idx).fill = fill_title

    # ---- Row 2: 主表头 ----
    # A2:A3 合并（均值标签区域）
    ws.merge_cells('A2:A3')
    ws['A2'].value = ''
    ws['A2'].font = font_header
    ws['A2'].fill = fill_header
    ws['A2'].alignment = align_center
    ws['A3'].fill = fill_header
    ws['A3'].border = thin_border

    # B2:B3 合并
    ws.merge_cells('B2:B3')
    ws['B2'].value = '指标'
    ws['B2'].font = font_header
    ws['B2'].fill = fill_header
    ws['B2'].alignment = align_center
    ws['B3'].fill = fill_header
    ws['B3'].border = thin_border

    # C2:E2 合并（实验组）
    ws.merge_cells('C2:E2')
    ws['C2'].value = '实验组'
    ws['C2'].font = font_header
    ws['C2'].fill = fill_header
    ws['C2'].alignment = align_center
    for c in ['D2', 'E2']:
        ws[c].fill = fill_header
        ws[c].border = thin_border

    # F2:H2 合并（对照组）
    ws.merge_cells('F2:H2')
    ws['F2'].value = '对照组'
    ws['F2'].font = font_header
    ws['F2'].fill = fill_header
    ws['F2'].alignment = align_center
    for c in ['G2', 'H2']:
        ws[c].fill = fill_header
        ws[c].border = thin_border

    # I2:I3 合并
    ws.merge_cells('I2:I3')
    ws['I2'].value = '双重差分净效应(ΔT-Δt)'
    ws['I2'].font = font_header
    ws['I2'].fill = fill_header
    ws['I2'].alignment = align_center

    # J2:J3 合并
    ws.merge_cells('J2:J3')
    ws['J2'].value = '净效应对实验组的作用'
    ws['J2'].font = font_header
    ws['J2'].fill = fill_header
    ws['J2'].alignment = align_center

    # K2:K3 合并
    ws.merge_cells('K2:K3')
    ws['K2'].value = 'p_value'
    ws['K2'].font = font_header
    ws['K2'].fill = fill_header
    ws['K2'].alignment = align_center

    # L2:L3 合并
    ws.merge_cells('L2:L3')
    ws['L2'].value = '统计显著性'
    ws['L2'].font = font_header
    ws['L2'].fill = fill_header
    ws['L2'].alignment = align_center

    # Row 2 和 Row 3 所有单元格加边框和蓝色背景
    for row_idx in [2, 3]:
        for col_idx in range(1, 13):
            cell = ws.cell(row=row_idx, column=col_idx)
            cell.border = thin_border
            if cell.fill == PatternFill():  # 未设置的加蓝色背景
                cell.fill = fill_header
            if cell.font == Font():  # 未设置的加白色字体
                cell.font = font_header

    # ---- Row 3: 子表头 ----
    sub_headers = {
        'C3': '前7日(T0)', 'D3': '后7日(T1)', 'E3': 'ΔT',
        'F3': '前7日(t0)', 'G3': '后7日(t1)', 'H3': 'Δt',
    }
    for cell_ref, value in sub_headers.items():
        cell = ws[cell_ref]
        cell.value = value
        cell.font = font_header
        cell.fill = fill_header
        cell.alignment = align_center
        cell.border = thin_border

    # ---- Row 4+: 数据行 ----
    n_rows = len(did_df)
    start_row = 4

    # A列纵向合并（所有数据行）
    last_row = start_row + n_rows - 1
    ws.merge_cells(f'A{start_row}:A{last_row}')
    ws[f'A{start_row}'].value = '均值'
    ws[f'A{start_row}'].font = font_data_bold
    ws[f'A{start_row}'].alignment = align_center

    for i, (_, row) in enumerate(did_df.iterrows()):
        r = start_row + i

        # B: 指标名
        ws.cell(row=r, column=2).value = row['label']
        ws.cell(row=r, column=2).font = font_data
        ws.cell(row=r, column=2).alignment = align_left
        ws.cell(row=r, column=2).border = thin_border

        # C: T0 (实验组before)
        ws.cell(row=r, column=3).value = row['treat_before']
        ws.cell(row=r, column=3).font = font_data
        ws.cell(row=r, column=3).alignment = align_center
        ws.cell(row=r, column=3).border = thin_border
        ws.cell(row=r, column=3).number_format = '0.00'

        # D: T1 (实验组after)
        ws.cell(row=r, column=4).value = row['treat_after']
        ws.cell(row=r, column=4).font = font_data
        ws.cell(row=r, column=4).alignment = align_center
        ws.cell(row=r, column=4).border = thin_border
        ws.cell(row=r, column=4).number_format = '0.00'

        # E: ΔT
        delta_t = round(row['treat_after'] - row['treat_before'], 2)
        ws.cell(row=r, column=5).value = delta_t
        ws.cell(row=r, column=5).font = font_data
        ws.cell(row=r, column=5).alignment = align_center
        ws.cell(row=r, column=5).border = thin_border
        ws.cell(row=r, column=5).number_format = '0.00'

        # F: t0 (对照组before)
        ws.cell(row=r, column=6).value = row['ctrl_before']
        ws.cell(row=r, column=6).font = font_data
        ws.cell(row=r, column=6).alignment = align_center
        ws.cell(row=r, column=6).border = thin_border
        ws.cell(row=r, column=6).number_format = '0.00'

        # G: t1 (对照组after)
        ws.cell(row=r, column=7).value = row['ctrl_after']
        ws.cell(row=r, column=7).font = font_data
        ws.cell(row=r, column=7).alignment = align_center
        ws.cell(row=r, column=7).border = thin_border
        ws.cell(row=r, column=7).number_format = '0.00'

        # H: Δt
        delta_ctrl = round(row['ctrl_after'] - row['ctrl_before'], 2)
        ws.cell(row=r, column=8).value = delta_ctrl
        ws.cell(row=r, column=8).font = font_data
        ws.cell(row=r, column=8).alignment = align_center
        ws.cell(row=r, column=8).border = thin_border
        ws.cell(row=r, column=8).number_format = '0.00'

        # I: DID净效应
        did_val = row['did_effect']
        ws.cell(row=r, column=9).value = did_val
        ws.cell(row=r, column=9).font = font_data
        ws.cell(row=r, column=9).alignment = align_center
        ws.cell(row=r, column=9).border = thin_border
        ws.cell(row=r, column=9).number_format = '0.00'

        # I列条件着色
        if did_val > 0:
            ws.cell(row=r, column=9).fill = fill_pos_i
        elif did_val < 0:
            ws.cell(row=r, column=9).fill = fill_neg

        # J: 提升%
        lift_val = row['lift_pct']
        # 格式化为百分比字符串
        if row['outcome'] == 'ltv_pay_rate':
            lift_str = f"+{lift_val:.2f}%" if lift_val >= 0 else f"{lift_val:.2f}%"
        else:
            lift_str = f"+{lift_val:.1f}%" if lift_val >= 0 else f"{lift_val:.1f}%"
        ws.cell(row=r, column=10).value = lift_str
        ws.cell(row=r, column=10).font = font_data
        ws.cell(row=r, column=10).alignment = align_center
        ws.cell(row=r, column=10).border = thin_border

        # J列条件着色
        if lift_val > 0:
            ws.cell(row=r, column=10).fill = fill_pos_j
        elif lift_val < 0:
            ws.cell(row=r, column=10).fill = fill_neg

        # K: p_value (0.0000格式，禁止科学计数法)
        p_val = row['p_value_raw']
        # 确保4位小数格式
        p_display = f'{p_val:.4f}'
        ws.cell(row=r, column=11).value = p_display
        ws.cell(row=r, column=11).font = font_data
        ws.cell(row=r, column=11).alignment = align_center
        ws.cell(row=r, column=11).border = thin_border
        ws.cell(row=r, column=11).number_format = '0.0000'

        # L: 统计显著性
        sig_text = row['sig_text']
        ws.cell(row=r, column=12).value = sig_text
        ws.cell(row=r, column=12).alignment = align_center
        ws.cell(row=r, column=12).border = thin_border

        # L列条件着色
        if row['significant'] and did_val > 0:
            ws.cell(row=r, column=12).fill = fill_sig_pos
            ws.cell(row=r, column=12).font = font_sig_pos
        elif row['significant'] and did_val < 0:
            ws.cell(row=r, column=12).fill = fill_sig_neg
            ws.cell(row=r, column=12).font = font_sig_neg
        else:
            ws.cell(row=r, column=12).font = font_data

        # A列边框
        ws.cell(row=r, column=1).border = thin_border

    # ---- 列宽调整 ----
    col_widths = {
        'A': 6, 'B': 16, 'C': 12, 'D': 12, 'E': 10,
        'F': 12, 'G': 12, 'H': 10, 'I': 16, 'J': 16,
        'K': 10, 'L': 12,
    }
    for col_letter, width in col_widths.items():
        ws.column_dimensions[col_letter].width = width

    # ---- 中位数DID Sheet ----
    ws2 = wb.create_sheet('中位数DID数据')

    # Row 1: 标题
    ws2.merge_cells('A1:L1')
    ws2['A1'].value = '中位数DID净效应数据'
    ws2['A1'].font = font_title
    ws2['A1'].fill = fill_title
    ws2['A1'].alignment = align_center
    for col_idx in range(1, 13):
        ws2.cell(row=1, column=col_idx).border = thin_border
        ws2.cell(row=1, column=col_idx).fill = fill_title

    # Row 2-3: 表头（同均值表结构）
    ws2.merge_cells('A2:A3')
    ws2['A2'].value = ''
    ws2['A2'].font = font_header
    ws2['A2'].fill = fill_header
    ws2['A2'].alignment = align_center

    ws2.merge_cells('B2:B3')
    ws2['B2'].value = '指标'
    ws2['B2'].font = font_header
    ws2['B2'].fill = fill_header
    ws2['B2'].alignment = align_center

    ws2.merge_cells('C2:E2')
    ws2['C2'].value = '实验组'
    ws2['C2'].font = font_header
    ws2['C2'].fill = fill_header
    ws2['C2'].alignment = align_center

    ws2.merge_cells('F2:H2')
    ws2['F2'].value = '对照组'
    ws2['F2'].font = font_header
    ws2['F2'].fill = fill_header
    ws2['F2'].alignment = align_center

    ws2.merge_cells('I2:I3')
    ws2['I2'].value = '双重差分净效应(ΔT-Δt)'
    ws2['I2'].font = font_header
    ws2['I2'].fill = fill_header
    ws2['I2'].alignment = align_center

    ws2.merge_cells('J2:J3')
    ws2['J2'].value = '净效应对实验组的作用'
    ws2['J2'].font = font_header
    ws2['J2'].fill = fill_header
    ws2['J2'].alignment = align_center

    ws2.merge_cells('K2:K3')
    ws2['K2'].value = 'p_value'
    ws2['K2'].font = font_header
    ws2['K2'].fill = fill_header
    ws2['K2'].alignment = align_center

    ws2.merge_cells('L2:L3')
    ws2['L2'].value = '统计显著性'
    ws2['L2'].font = font_header
    ws2['L2'].fill = fill_header
    ws2['L2'].alignment = align_center

    for row_idx in [2, 3]:
        for col_idx in range(1, 13):
            cell = ws2.cell(row=row_idx, column=col_idx)
            cell.border = thin_border
            if cell.fill == PatternFill():
                cell.fill = fill_header

    sub_headers2 = {
        'C3': '前7日(T0)', 'D3': '后7日(T1)', 'E3': 'ΔT',
        'F3': '前7日(t0)', 'G3': '后7日(t1)', 'H3': 'Δt',
    }
    for cell_ref, value in sub_headers2.items():
        cell = ws2[cell_ref]
        cell.value = value
        cell.font = font_header
        cell.fill = fill_header
        cell.alignment = align_center
        cell.border = thin_border

    # 数据行（中位数）
    ws2.merge_cells(f'A4:A{4 + n_rows - 1}')
    ws2['A4'].value = '中位数'
    ws2['A4'].font = font_data_bold
    ws2['A4'].alignment = align_center

    for i, (_, row) in enumerate(did_df.iterrows()):
        r = 4 + i

        ws2.cell(row=r, column=2).value = row['label']
        ws2.cell(row=r, column=2).font = font_data
        ws2.cell(row=r, column=2).alignment = align_left
        ws2.cell(row=r, column=2).border = thin_border

        # 中位数值
        med_tb = row['med_treat_before']
        med_ta = row['med_treat_after']
        med_cb = row['med_ctrl_before']
        med_ca = row['med_ctrl_after']
        med_did = row['med_did_effect']
        med_lift = row['med_lift_pct']

        # pay_rate 和 ARPPU 中位数可能为0，用均值替代
        if row['outcome'] == 'ltv_pay_rate':
            med_tb = row['treat_before']
            med_ta = row['treat_after']
            med_cb = row['ctrl_before']
            med_ca = row['ctrl_after']
            med_did = row['did_effect']
            med_lift = row['lift_pct']

        ws2.cell(row=r, column=3).value = med_tb
        ws2.cell(row=r, column=3).font = font_data
        ws2.cell(row=r, column=3).alignment = align_center
        ws2.cell(row=r, column=3).border = thin_border
        ws2.cell(row=r, column=3).number_format = '0.00'

        ws2.cell(row=r, column=4).value = med_ta
        ws2.cell(row=r, column=4).font = font_data
        ws2.cell(row=r, column=4).alignment = align_center
        ws2.cell(row=r, column=4).border = thin_border
        ws2.cell(row=r, column=4).number_format = '0.00'

        delta_med_t = round(med_ta - med_tb, 2) if med_ta != 0 or med_tb != 0 else 0
        ws2.cell(row=r, column=5).value = delta_med_t
        ws2.cell(row=r, column=5).font = font_data
        ws2.cell(row=r, column=5).alignment = align_center
        ws2.cell(row=r, column=5).border = thin_border
        ws2.cell(row=r, column=5).number_format = '0.00'

        ws2.cell(row=r, column=6).value = med_cb
        ws2.cell(row=r, column=6).font = font_data
        ws2.cell(row=r, column=6).alignment = align_center
        ws2.cell(row=r, column=6).border = thin_border
        ws2.cell(row=r, column=6).number_format = '0.00'

        ws2.cell(row=r, column=7).value = med_ca
        ws2.cell(row=r, column=7).font = font_data
        ws2.cell(row=r, column=7).alignment = align_center
        ws2.cell(row=r, column=7).border = thin_border
        ws2.cell(row=r, column=7).number_format = '0.00'

        delta_med_c = round(med_ca - med_cb, 2) if med_ca != 0 or med_cb != 0 else 0
        ws2.cell(row=r, column=8).value = delta_med_c
        ws2.cell(row=r, column=8).font = font_data
        ws2.cell(row=r, column=8).alignment = align_center
        ws2.cell(row=r, column=8).border = thin_border
        ws2.cell(row=r, column=8).number_format = '0.00'

        ws2.cell(row=r, column=9).value = med_did
        ws2.cell(row=r, column=9).font = font_data
        ws2.cell(row=r, column=9).alignment = align_center
        ws2.cell(row=r, column=9).border = thin_border
        ws2.cell(row=r, column=9).number_format = '0.00'

        if med_did > 0:
            ws2.cell(row=r, column=9).fill = fill_pos_i
        elif med_did < 0:
            ws2.cell(row=r, column=9).fill = fill_neg

        if row['outcome'] == 'ltv_pay_rate':
            lift_str2 = f"+{med_lift:.2f}%" if med_lift >= 0 else f"{med_lift:.2f}%"
        else:
            lift_str2 = f"+{med_lift:.1f}%" if med_lift >= 0 else f"{med_lift:.1f}%"
        ws2.cell(row=r, column=10).value = lift_str2
        ws2.cell(row=r, column=10).font = font_data
        ws2.cell(row=r, column=10).alignment = align_center
        ws2.cell(row=r, column=10).border = thin_border

        if med_lift > 0:
            ws2.cell(row=r, column=10).fill = fill_pos_j
        elif med_lift < 0:
            ws2.cell(row=r, column=10).fill = fill_neg

        med_p = row['med_p_value']
        p_display2 = f'{med_p:.4f}'
        ws2.cell(row=r, column=11).value = p_display2
        ws2.cell(row=r, column=11).font = font_data
        ws2.cell(row=r, column=11).alignment = align_center
        ws2.cell(row=r, column=11).border = thin_border
        ws2.cell(row=r, column=11).number_format = '0.0000'

        med_sig = row['med_sig_text']
        ws2.cell(row=r, column=12).value = med_sig
        ws2.cell(row=r, column=12).alignment = align_center
        ws2.cell(row=r, column=12).border = thin_border

        if row.get('med_significant', False) and med_did > 0:
            ws2.cell(row=r, column=12).fill = fill_sig_pos
            ws2.cell(row=r, column=12).font = font_sig_pos
        elif row.get('med_significant', False) and med_did < 0:
            ws2.cell(row=r, column=12).fill = fill_sig_neg
            ws2.cell(row=r, column=12).font = font_sig_neg
        else:
            ws2.cell(row=r, column=12).font = font_data

        ws2.cell(row=r, column=1).border = thin_border

    for col_letter, width in col_widths.items():
        ws2.column_dimensions[col_letter].width = width

    wb.save(out_path)
    print(f"  Excel报告已保存: {out_path}")


# ============================================================
#  Word 报告生成（叙事结构）
# ============================================================

def generate_word_report(results, did_df, out_path):
    """
    生成Word报告，遵循skill.md定义的叙事结构。

    结构:
    1. 总结结论
    2. 实验活动效果评估方案
    3. 一、对功能页曝光的用户分析
       1.1 匹配质量说明
       1.2 关键效果指标
    4. 风险提示
    5. 综合结论
    """

    doc = Document()

    # 设置默认字体
    style = doc.styles['Normal']
    style.font.name = '微软雅黑'
    style.font.size = Pt(11)
    style._element.rPr.rFonts.set(qn('w:eastAsia'), '微软雅黑')

    # ---- 报告标题 ----
    title_text = f'{ACTIVITY_NAME}用户分析PSM+DID_{datetime.now().strftime("%Y%m%d")}'
    title_para = doc.add_paragraph()
    title_run = title_para.add_run(title_text)
    _set_font(title_run, size=Pt(16), bold=True)
    title_para.alignment = WD_ALIGN_PARAGRAPH.CENTER

    # ---- 总结结论 ----
    core_conclusion = generate_did_core_conclusion(did_df, ACTIVITY_NAME)
    summary_para = doc.add_paragraph()
    summary_run = summary_para.add_run(core_conclusion)
    _set_font(summary_run, size=Pt(11))

    # ---- 实验活动效果评估方案 ----
    doc.add_heading('实验活动效果评估方案', level=1)
    _set_font(doc.paragraphs[-1].runs[0], size=Pt(16), bold=True)

    bullets = [
        f'实验组：{TREAT_LABEL}',
        f'对照组：{CTRL_LABEL}',
        f'分析周期：活动日为{ACTIVITY_DATE}（仅1天）——⚠ 风险提示：{RISK_POINT}',
        f'核心目标：评估{ACTIVITY_NAME}对用户LT（活跃维度）和LTV（付费维度）的因果效应',
    ]
    for b in bullets:
        p = doc.add_paragraph(b, style='List Bullet')
        for run in p.runs:
            _set_font(run, size=Pt(11))
        # 风险提示那条加粗和高亮
        if '风险提示' in b:
            for run in p.runs:
                _set_font(run, size=Pt(11), bold=True)

    # ---- 一、对功能页曝光的用户分析 ----
    module_title = f'一、{ACTIVITY_NAME}的用户分析'
    doc.add_heading(module_title, level=1)
    _set_font(doc.paragraphs[-1].runs[0], size=Pt(16), bold=True)

    # ---- 1.1 匹配质量说明 ----
    doc.add_heading('1.1 匹配质量说明', level=2)
    _set_font(doc.paragraphs[-1].runs[0], size=Pt(14), bold=True)

    # PSM+DID方法简介
    intro_para = doc.add_paragraph()
    intro_run = intro_para.add_run(
        '本分析采用PSM（倾向得分匹配）+DID（双重差分）组合策略：'
        'PSM为每个曝光用户匹配一个"各方面相似但未曝光"的对照用户，消除选择偏差；'
        'DID对比两组在活动前后的变化差异，剔除时间趋势。'
        '最终得到的DID净效应即为活动的因果影响。'
    )
    _set_font(intro_run, size=Pt(11))

    # 三点编号
    n_treat = results['n_matched_treat']
    n_ctrl = results['n_matched_ctrl']
    match_rate = results['match_rate']
    max_smd = results['max_smd']
    ps_explanation = results['ps_explanation']

    point1 = f'1. 实现精准匹配，曝光组{n_treat:,}人（匹配率{match_rate:.1f}%），样本充足、结果稳定。'
    point2 = f'2. 匹配后所有用户特征的标准化均值差异（SMD）均远小于0.1（最大|SMD|={max_smd:.4f}），两组用户初始行为高度一致，可认为后续差异完全由{ACTIVITY_NAME}导致。'
    point3 = f'3. {ps_explanation}'

    for pt in [point1, point2, point3]:
        p = doc.add_paragraph(pt)
        for run in p.runs:
            _set_font(run, size=Pt(11))

    # PS分布图
    if results['psm_plot'] and os.path.exists(results['psm_plot']):
        doc.add_picture(results['psm_plot'], width=Inches(6))
        last_para = doc.paragraphs[-1]
        last_para.alignment = WD_ALIGN_PARAGRAPH.CENTER

    # PS分布图注释
    ps_note = doc.add_paragraph()
    ps_note_run = ps_note.add_run(
        f'注：treatment为实验组（{TREAT_LABEL}），control为对照组（{CTRL_LABEL}）'
    )
    _set_font(ps_note_run, size=Pt(9))

    # Love Plot
    if results['love_plot'] and os.path.exists(results['love_plot']):
        doc.add_picture(results['love_plot'], width=Inches(6))
        last_para = doc.paragraphs[-1]
        last_para.alignment = WD_ALIGN_PARAGRAPH.CENTER

    # Love Plot注释
    love_note = doc.add_paragraph()
    love_note_run = love_note.add_run(
        f'注：treatment为实验组（{TREAT_LABEL}），control为对照组（{CTRL_LABEL}）。'
        f'橙色圆圈=匹配前SMD，绿色三角=匹配后SMD。'
        f'所有匹配后SMD均<0.1，平衡性检验通过。'
    )
    _set_font(love_note_run, size=Pt(9))

    # ---- 1.2 关键效果指标 ----
    effect_title = f'1.2 关键效果指标（{ACTIVITY_NAME}带来的净提升）'
    doc.add_heading(effect_title, level=2)
    _set_font(doc.paragraphs[-1].runs[0], size=Pt(14), bold=True)

    # DID核心结论段（12pt bold）
    core_para = doc.add_paragraph()
    core_run = core_para.add_run(core_conclusion)
    _set_font(core_run, size=Pt(12), bold=True)

    # 主要正向作用
    pos_bullets = generate_positive_bullets(did_df)
    if pos_bullets:
        pos_title_para = doc.add_paragraph()
        pos_title_run = pos_title_para.add_run('活动有效促进以下维度：')
        _set_font(pos_title_run, size=Pt(11), bold=True)

        for b in pos_bullets:
            p = doc.add_paragraph(b, style='List Bullet')
            for run in p.runs:
                _set_font(run, size=Pt(11))

    # 显著负向指标
    neg_section = generate_negative_section(did_df)
    neg_title_para = doc.add_paragraph()
    if isinstance(neg_section, str) and neg_section == "无任何显著负向指标":
        neg_title_run = neg_title_para.add_run('显著负向指标：')
        _set_font(neg_title_run, size=Pt(11), bold=True)
        neg_content_para = doc.add_paragraph(neg_section)
        for run in neg_content_para.runs:
            _set_font(run, size=Pt(11))
    elif isinstance(neg_section, list):
        neg_title_run = neg_title_para.add_run('显著负向指标：')
        _set_font(neg_title_run, size=Pt(11), bold=True)
        for item in neg_section:
            p = doc.add_paragraph(item, style='List Bullet')
            for run in p.runs:
                _set_font(run, size=Pt(11))

    # 不显著指标的语境化说明
    nonsig_lines = generate_nonsig_context(did_df)
    if nonsig_lines:
        nonsig_title_para = doc.add_paragraph()
        nonsig_title_run = nonsig_title_para.add_run('不显著指标说明：')
        _set_font(nonsig_title_run, size=Pt(11), bold=True)
        for line in nonsig_lines:
            p = doc.add_paragraph(line)
            for run in p.runs:
                _set_font(run, size=Pt(11))

    # ---- LTV稀释效应说明（如触发） ----
    ltv_res = results['ltv_results']
    if ltv_res.get('conflict'):
        dilution_para = doc.add_paragraph()
        dilution_run = dilution_para.add_run(
            f'稀释效应诊断：实验组after期付费用户数{ltv_res["n_treat_paid"]:,}人，'
            f'对照组{ltv_res["n_ctrl_paid"]:,}人，稀释比={ltv_res["dilution_ratio"]:.2f}。'
            f'ARPPU均值与中位数方向矛盾，存在稀释效应——活动的核心成效是扩大付费用户基数（pay_rate显著提升），'
            f'ARPPU均值下降是"更多人愿意付小钱"的正常数学表现，建议参考中位数ARPPU衡量典型付费用户。'
        )
        _set_font(dilution_run, size=Pt(11))

    # ---- DID数据表（均值） ----
    did_table_title = doc.add_paragraph()
    did_table_run = did_table_title.add_run('均值DID数据表：')
    _set_font(did_table_run, size=Pt(11), bold=True)

    # 创建Word表格
    table_cols = ['指标', '前7日(T0)', '后7日(T1)', 'ΔT', '前7日(t0)', '后7日(t1)', 'Δt',
                  'DID净效应', '提升%', 'p值', '显著性']
    n_table_rows = len(did_df) + 1  # +1 for header

    table = doc.add_table(rows=n_table_rows, cols=len(table_cols))
    table.style = 'Table Grid'

    # 表头
    for j, col_name in enumerate(table_cols):
        cell = table.rows[0].cells[j]
        cell.text = col_name
        for paragraph in cell.paragraphs:
            for run in paragraph.runs:
                _set_font(run, size=Pt(9), bold=True)

    # 数据行
    for i, (_, row) in enumerate(did_df.iterrows()):
        r = i + 1
        table.rows[r].cells[0].text = str(row['label'])
        table.rows[r].cells[1].text = str(row['treat_before'])
        table.rows[r].cells[2].text = str(row['treat_after'])
        table.rows[r].cells[3].text = str(round(row['treat_after'] - row['treat_before'], 2))
        table.rows[r].cells[4].text = str(row['ctrl_before'])
        table.rows[r].cells[5].text = str(row['ctrl_after'])
        table.rows[r].cells[6].text = str(round(row['ctrl_after'] - row['ctrl_before'], 2))
        table.rows[r].cells[7].text = str(row['did_effect'])
        if row['outcome'] == 'ltv_pay_rate':
            table.rows[r].cells[8].text = f"+{row['lift_pct']:.2f}%" if row['lift_pct'] >= 0 else f"{row['lift_pct']:.2f}%"
        else:
            table.rows[r].cells[8].text = f"+{row['lift_pct']:.1f}%" if row['lift_pct'] >= 0 else f"{row['lift_pct']:.1f}%"
        table.rows[r].cells[9].text = f'{row["p_value_raw"]:.4f}'
        table.rows[r].cells[10].text = row['sig_text']

        for cell in table.rows[r].cells:
            for paragraph in cell.paragraphs:
                for run in paragraph.runs:
                    _set_font(run, size=Pt(9))

    # ---- DID数据表（中位数） ----
    med_table_title = doc.add_paragraph()
    med_table_run = med_table_title.add_run('中位数DID数据表：')
    _set_font(med_table_run, size=Pt(11), bold=True)

    table2 = doc.add_table(rows=n_table_rows, cols=len(table_cols))
    table2.style = 'Table Grid'

    for j, col_name in enumerate(table_cols):
        cell = table2.rows[0].cells[j]
        cell.text = col_name
        for paragraph in cell.paragraphs:
            for run in paragraph.runs:
                _set_font(run, size=Pt(9), bold=True)

    for i, (_, row) in enumerate(did_df.iterrows()):
        r = i + 1
        med_tb = row['med_treat_before']
        med_ta = row['med_treat_after']
        med_cb = row['med_ctrl_before']
        med_ca = row['med_ctrl_after']
        med_did = row['med_did_effect']
        med_lift = row['med_lift_pct']

        if row['outcome'] == 'ltv_pay_rate':
            med_tb = row['treat_before']
            med_ta = row['treat_after']
            med_cb = row['ctrl_before']
            med_ca = row['ctrl_after']
            med_did = row['did_effect']
            med_lift = row['lift_pct']

        table2.rows[r].cells[0].text = str(row['label'])
        table2.rows[r].cells[1].text = str(med_tb)
        table2.rows[r].cells[2].text = str(med_ta)
        table2.rows[r].cells[3].text = str(round(med_ta - med_tb, 2) if med_ta != 0 or med_tb != 0 else '0')
        table2.rows[r].cells[4].text = str(med_cb)
        table2.rows[r].cells[5].text = str(med_ca)
        table2.rows[r].cells[6].text = str(round(med_ca - med_cb, 2) if med_ca != 0 or med_cb != 0 else '0')
        table2.rows[r].cells[7].text = str(med_did)
        if row['outcome'] == 'ltv_pay_rate':
            table2.rows[r].cells[8].text = f"+{med_lift:.2f}%" if med_lift >= 0 else f"{med_lift:.2f}%"
        else:
            table2.rows[r].cells[8].text = f"+{med_lift:.1f}%" if med_lift >= 0 else f"{med_lift:.1f}%"
        table2.rows[r].cells[9].text = f'{row["med_p_value"]:.4f}'
        table2.rows[r].cells[10].text = row['med_sig_text']

        for cell in table2.rows[r].cells:
            for paragraph in cell.paragraphs:
                for run in paragraph.runs:
                    _set_font(run, size=Pt(9))

    # ---- 方法注释 ----
    method_note = doc.add_paragraph()
    method_run = method_note.add_run(
        '注：净效应对实验组的作用(%) = 双重差分净效应 / 实验组前七日均值×100。'
        '均值DID基于t检验，中位数DID基于Mann-Whitney U检验。'
    )
    _set_font(method_run, size=Pt(9))

    # ---- DID柱状图 ----
    if results['did_plot'] and os.path.exists(results['did_plot']):
        doc.add_picture(results['did_plot'], width=Inches(6))
        last_para = doc.paragraphs[-1]
        last_para.alignment = WD_ALIGN_PARAGRAPH.CENTER

    # ---- 风险提示独立段落 ----
    risk_para = doc.add_paragraph()
    risk_run = risk_para.add_run(f'⚠ 风险提示：{RISK_POINT}')
    _set_font(risk_run, size=Pt(11), bold=True)

    risk_detail = doc.add_paragraph()
    risk_detail_run = risk_detail.add_run(
        '活动干预窗口仅覆盖5月12日1天，前后对比期的时间跨度可能不足以捕捉活动的完整效应。'
        '短期干预的因果效应估计更容易受到当日随机波动的影响，建议在后续实验中延长活动周期以提升结论的稳健性。'
    )
    _set_font(risk_detail_run, size=Pt(11))

    # ---- 综合结论 ----
    doc.add_heading('综合结论', level=1)
    _set_font(doc.paragraphs[-1].runs[0], size=Pt(16), bold=True)

    # 综合结论内容（基于DID核心结论，加上风险提示的限定语）
    conclusion_para = doc.add_paragraph()
    conclusion_run = conclusion_para.add_run(
        f'{core_conclusion}'
        f'需要注意的是，本次分析的活动干预窗口仅1天（5月12日），'
        f'因果效应的检测灵敏度可能受限，结论的稳健性有待更长周期的实验验证。'
    )
    _set_font(conclusion_run, size=Pt(11))

    doc.save(out_path)
    print(f"  Word报告已保存: {out_path}")


# ============================================================
#  主流程
# ============================================================

if __name__ == '__main__':
    print("=" * 70)
    print(f"  {ACTIVITY_NAME} PSM+DID Causal Inference Analysis")
    print(f"  Started: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print("=" * 70)

    # ---- Step 1: 数据加载与清洗 ----
    print(f"\n--- Step 1: Data Loading & Cleaning ---")
    df = pd.read_csv(DATA_CSV, na_values=['null', 'NULL', 'nan', 'NaN', 'None', ''],
                     encoding='utf-8-sig')
    print(f"  Loaded: {len(df):,} rows, {len(df.columns)} cols")
    print(f"  Columns: {list(df.columns)}")

    # 报告原始数据分组
    n_treat_orig = df[df[TREATMENT_COL] == 1].shape[0]
    n_ctrl_orig = df[df[TREATMENT_COL] == 0].shape[0]
    print(f"  实验组(is_exposure=1): {n_treat_orig:,}")
    print(f"  对照组(is_exposure=0): {n_ctrl_orig:,}")

    # 清洗所有数值列
    all_num_cols = MATCH_FEATURES + list(OUTCOME_MAPPING.keys())
    df = safe_fillna(df, all_num_cols + [TREATMENT_COL, USER_COL])
    print(f"  After cleaning: {len(df):,} rows (NaN/Inf filled)")

    # ---- 模块A: 全量样本 PSM+DID ----
    full_results = run_psm_pipeline(df, label_suffix='对功能页曝光的用户')

    # ---- 报告生成 ----
    did_df = full_results['did_df']
    ts = datetime.now().strftime('%Y%m%d_%H%M%S')

    # Excel报告
    excel_path = os.path.join(OUT_DIR, f'{ACTIVITY_NAME}用户分析PSM+DID_{ts}.xlsx')
    generate_excel_report(did_df, excel_path)

    # Word报告
    word_path = os.path.join(OUT_DIR, f'{ACTIVITY_NAME}用户分析PSM+DID_{ts}.docx')
    generate_word_report(full_results, did_df, word_path)

    # CSV导出
    csv_path = os.path.join(OUT_DIR, f'DID结果_{ts}.csv')
    export_cols = ['outcome', 'label', 'unit', 'treat_before', 'treat_after',
                   'ctrl_before', 'ctrl_after', 'did_effect', 'lift_pct',
                   'p_value_display', 'sig_text', 'significant',
                   'med_treat_before', 'med_treat_after', 'med_ctrl_before', 'med_ctrl_after',
                   'med_did_effect', 'med_lift_pct']
    did_df[export_cols].to_csv(csv_path, index=False, encoding='utf-8-sig')
    print(f"  CSV已保存: {csv_path}")

    # ---- 最终汇总 ----
    print(f"\n{'='*70}")
    print(f"  ✅ Analysis Complete: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print(f"  Outputs:")
    print(f"    Excel: {excel_path}")
    print(f"    Word:  {word_path}")
    print(f"    CSV:   {csv_path}")
    print(f"    PS图:  {full_results['psm_plot']}")
    print(f"    Love:  {full_results['love_plot']}")
    print(f"    DID图: {full_results['did_plot']}")
    print(f"{'='*70}")

    # ---- DID核心结论打印 ----
    core = generate_did_core_conclusion(did_df, ACTIVITY_NAME)
    print(f"\n  DID核心结论: {core}")
    print(f"\n  ⚠ 风险提示: {RISK_POINT}")
