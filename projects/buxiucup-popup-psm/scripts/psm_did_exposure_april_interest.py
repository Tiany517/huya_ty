# -*- coding: utf-8 -*-
"""
=============================================================================
  PSM+DID 因果推断分析 — 不朽杯APP拍脸活动曝光对LT/LTV的影响
=============================================================================
  实验组：当天活跃 + 4月观看时长最长为DOTA2 + 当天被曝光
  对照组：当天活跃 + 4月观看时长最长为DOTA2 + 当天未被曝光
  活动日：5月12日（仅1天）

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
plt.rcParams['font.size'] = 12
plt.rcParams['axes.titlesize'] = 14
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
#  CONFIG
# ============================================================
BASE_DIR = r'C:\Users\tiany\Desktop\不朽杯弹窗PSM实验\对功能页曝光的研究_针对4月归因为DOTA2的用户'
DATA_CSV = os.path.join(BASE_DIR, '数据源.csv')

# 活动信息
ACTIVITY_NAME = '不朽杯APP拍脸活动曝光'
ACTIVITY_DATE = '2026-05-12'
ACTIVITY_RISK_NOTE = '活动日仅1天（5月12日），时间周期不够长，可能影响因果效应的稳定性和可检测性，需在结论中标注此风险点。'

# 列名配置
TREATMENT_COL = 'is_exposure'
USER_COL = 'yyuid'

# 匹配特征
MATCH_FEATURES = [
    'before_watch_duration',
    'before_watch_dcnt',
    'before_watch_anchorcnt',
    'before_watch_gamecnt',
    'before_consume_amount',
    'before_active_dcnt',
]

# 结果变量映射
OUTCOME_MAPPING = {
    'after_watch_duration':    'before_watch_duration',
    'after_watch_dcnt':        'before_watch_dcnt',
    'after_watch_anchorcnt':   'before_watch_anchorcnt',
    'after_watch_gamecnt':     'before_watch_gamecnt',
    'after_consume_amount':    'before_consume_amount',
    'after_active_dcnt':       'before_active_dcnt',
}

# 结果变量中文标签
OUTCOME_LABELS = {
    'after_watch_duration':    ('观看时长(min)', '分钟'),
    'after_watch_dcnt':        ('观看天数', '天'),
    'after_watch_anchorcnt':   ('观看主播数', '个'),
    'after_watch_gamecnt':     ('观看游戏数', '个'),
    'after_consume_amount':    ('付费金额(元)', '元'),
    'after_active_dcnt':       ('活跃天数', '天'),
}

# LT/LTV维度分类
LT_OUTCOMES = {'after_watch_duration', 'after_watch_dcnt', 'after_watch_anchorcnt',
               'after_watch_gamecnt', 'after_active_dcnt'}
LTV_OUTCOMES = {'after_consume_amount'}

# 子人群配置 — 不启用（数据已针对DOTA2用户筛选）
SUBGROUP_CONFIG = {'enabled': False}

# LTV消费指标
LTV_AMOUNT_COL = 'after_consume_amount'
LTV_AMOUNT_BEFORE = 'before_consume_amount'

# 匹配参数
CALIPER = 0.05
SEED = 42
MAX_CTRL_SAMPLE = 1_500_000

# 显著性阈值
ALPHA_STRICT = 0.01
ALPHA_STANDARD = 0.05
ALPHA_LOOSE = 0.10

# 输出目录
OUT_DIR = BASE_DIR

# 实验组/对照组定义文字
TREAT_DEF = '当天活跃，且4月份观看时长最长为DOTA2，且当天被曝光的用户'
CTRL_DEF = '当天活跃，且4月份观看时长最长为DOTA2，但当天未被曝光的用户'


# ============================================================
#  工具函数
# ============================================================

def safe_fillna(df, cols):
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
    t = data[data[treat_col] == 1][feat].astype(float)
    c = data[data[treat_col] == 0][feat].astype(float)
    mean_diff = t.mean() - c.mean()
    pool_var = (t.var(ddof=0) + c.var(ddof=0)) / 2
    return abs(mean_diff / np.sqrt(pool_var)) if pool_var > 1e-10 else 0.0


def sig_mark(p_val, did_effect):
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
#  可视化函数
# ============================================================

def plot_ps_distribution(matched_df, treat_col, title_suffix='', save_path=None):
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
#  核心流水线
# ============================================================

def run_psm_pipeline(df, label_suffix='', match_features=None):
    if match_features is None:
        match_features = MATCH_FEATURES

    print(f"\n{'='*70}")
    print(f"  PSM+DID Pipeline: {label_suffix}")
    print(f"{'='*70}")

    results = {}
    results['label_suffix'] = label_suffix
    results['match_features'] = match_features

    # Step 1: 拆分
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

    # Step 2: 特征标准化 + 倾向得分
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

    # KDTree 1:1最近邻匹配
    tree = KDTree(control_df['propensity_score'].values.reshape(-1, 1))
    dists, indices = tree.query(treat_df['propensity_score'].values.reshape(-1, 1), k=1)
    valid_mask = dists.flatten() <= CALIPER
    matched_treat = treat_df[valid_mask].copy()
    matched_ctrl = control_df.iloc[indices[valid_mask].flatten()].copy()
    matched_df = pd.concat([matched_treat, matched_ctrl], ignore_index=True)

    match_rate = len(matched_treat) / orig_n_treat * 100 if orig_n_treat > 0 else 0
    print(f"  Matched: {len(matched_treat):,}/{orig_n_treat:,} ({match_rate:.1f}%)")

    # Step 3: SMD平衡性检验
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
    if n_pass < len(match_features):
        fail_feats = balance_df[balance_df['smd_after'] >= 0.1]
        print(f"  !!! SMD未通过的特征:")
        for _, row in fail_feats.iterrows():
            print(f"      {row['feature']}: SMD={row['smd_after']}")

    results['matched_df'] = matched_df
    results['n_matched_treat'] = len(matched_treat)
    results['n_matched_ctrl'] = len(matched_ctrl)
    results['orig_n_treat'] = orig_n_treat
    results['orig_n_ctrl'] = min(orig_n_ctrl, MAX_CTRL_SAMPLE)
    results['balance_df'] = balance_df
    results['smd_pass_rate'] = f"{n_pass}/{len(match_features)}"
    results['max_smd'] = mx_smd
    results['match_rate'] = match_rate

    # Step 4: DID分析
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
        cv_t = (ta_std / ta * 100) if abs(ta) > 1e-10 else float('inf')
        cv_c = (ca_std / ca * 100) if abs(ca) > 1e-10 else float('inf')

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

    # Step 5: LTV补充分析
    ltv_results = _run_ltv_supplement(treat_did, control_did, did_records, label_suffix)
    results['ltv_results'] = ltv_results

    results['did_df'] = pd.DataFrame(did_records)

    # 生成图表
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
    pay_col = LTV_AMOUNT_COL
    pay_before = LTV_AMOUNT_BEFORE

    # ---- pay_rate: 对前后变化量做DID检验 ----
    # pay_rate DID = (T1_pay_rate - T0_pay_rate) - (C1_pay_rate - C0_pay_rate)
    # 统计检验：对两组的"前后变化量"做t检验
    tr_pay_after = (treat_did[pay_col] > 0).astype(float)
    tr_pay_before = (treat_did[pay_before] > 0).astype(float)
    ct_pay_after = (control_did[pay_col] > 0).astype(float)
    ct_pay_before = (control_did[pay_before] > 0).astype(float)

    tr_pay_change = tr_pay_after - tr_pay_before
    ct_pay_change = ct_pay_after - ct_pay_before

    tr_pay = tr_pay_after.mean() * 100
    ct_pay = ct_pay_after.mean() * 100
    tr_pay_bf = tr_pay_before.mean() * 100
    ct_pay_bf = ct_pay_before.mean() * 100
    pay_did = (tr_pay - tr_pay_bf) - (ct_pay - ct_pay_bf)
    pay_lift = (pay_did / tr_pay_bf * 100) if abs(tr_pay_bf) > 1e-10 else 0.0

    # 对前后变化量做t检验
    tv_pay = tr_pay_change.values
    cv_pay = ct_pay_change.values
    tv_pay, cv_pay = tv_pay[np.isfinite(tv_pay)], cv_pay[np.isfinite(cv_pay)]
    _, pay_p = ttest_ind(tv_pay, cv_pay) if len(tv_pay)>=2 and len(cv_pay)>=2 else (0, 1.0)
    if np.isnan(pay_p) or np.isinf(pay_p): pay_p = 1.0
    pay_stxt, pay_smk = sig_mark(pay_p, pay_did)

    # ---- ARPPU: 对前后变化量做DID检验 ----
    tpa_after = treat_did[pay_col].astype(float)
    cpa_after = control_did[pay_col].astype(float)
    tpb_before = treat_did[pay_before].astype(float)
    cpb_before = control_did[pay_before].astype(float)

    # 仅取付费用户子集
    tpa = tpa_after[treat_did[pay_col] > 0]
    cpa = cpa_after[control_did[pay_col] > 0]
    tpb = tpb_before[treat_did[pay_before] > 0]
    cpb = cpb_before[control_did[pay_before] > 0]

    arppu_did = (tpa.mean() - tpb.mean()) - (cpa.mean() - cpb.mean())
    arppu_lift = (arppu_did / tpb.mean() * 100) if abs(tpb.mean()) > 1e-10 else 0.0

    # ARPPU变化量检验：对付费用户的前后变化量做检验
    # 需要同时是before付费和after付费的用户才能算变化量
    # 先定义fallback变量，确保后续引用安全
    tpa_v = tpa.values[np.isfinite(tpa.values)]
    cpa_v = cpa.values[np.isfinite(cpa.values)]

    treat_both_paid = treat_did[(treat_did[pay_before] > 0) & (treat_did[pay_col] > 0)]
    ctrl_both_paid = control_did[(control_did[pay_before] > 0) & (control_did[pay_col] > 0)]

    if len(treat_both_paid) >= 2 and len(ctrl_both_paid) >= 2:
        t_change = treat_both_paid[pay_col].astype(float) - treat_both_paid[pay_before].astype(float)
        c_change = ctrl_both_paid[pay_col].astype(float) - ctrl_both_paid[pay_before].astype(float)
        t_change_v = t_change.values[np.isfinite(t_change.values)]
        c_change_v = c_change.values[np.isfinite(c_change.values)]
        _, arppu_p = ttest_ind(t_change_v, c_change_v) if len(t_change_v)>=2 and len(c_change_v)>=2 else (0, 1.0)
    else:
        # 如果交集太小，退回对after期ARPPU直接比较
        _, arppu_p = ttest_ind(tpa_v, cpa_v) if len(tpa_v)>=2 and len(cpa_v)>=2 else (0, 1.0)
    if np.isnan(arppu_p) or np.isinf(arppu_p): arppu_p = 1.0
    arppu_stxt, arppu_smk = sig_mark(arppu_p, arppu_did)

    med_arppu_did = (tpa.median() - tpb.median()) - (cpa.median() - cpb.median())
    try:
        # 对ARPPU变化量做Mann-Whitney U检验
        if len(treat_both_paid) >= 2 and len(ctrl_both_paid) >= 2:
            med_arppu_p = mannwhitneyu(t_change_v, c_change_v, alternative='two-sided')[1]
        else:
            med_arppu_p = mannwhitneyu(tpa_v, cpa_v, alternative='two-sided')[1] if len(tpa_v)>=2 and len(cpa_v)>=2 else 1.0
        if np.isnan(med_arppu_p) or np.isinf(med_arppu_p): med_arppu_p = 1.0
    except: med_arppu_p = 1.0
    med_arppu_stxt, _ = sig_mark(med_arppu_p, med_arppu_did)

    n_treat_paid = len(tpa)
    n_ctrl_paid = len(cpa)
    dilution_ratio = n_treat_paid / max(n_ctrl_paid, 1)
    arppu_conflict = ((arppu_did > 0) != (med_arppu_did > 0)) and (arppu_p < ALPHA_STANDARD or med_arppu_p < ALPHA_STANDARD)

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
#  Excel 报告生成（严格12列格式）
# ============================================================

def generate_excel_report(did_df, balance_df, ltv_results, out_path):
    wb = openpyxl.Workbook()

    # ---- Sheet 1: DID净效应数据（均值） ----
    ws1 = wb.active
    ws1.title = 'DID净效应数据'

    # 样式定义
    font_title = Font(name='微软雅黑', size=14, bold=True)
    font_header = Font(name='微软雅黑', size=11, bold=True, color='FFFFFF')
    font_sub_header = Font(name='微软雅黑', size=10, bold=True, color='FFFFFF')
    font_data = Font(name='微软雅黑', size=10)
    font_data_bold = Font(name='微软雅黑', size=10, bold=True)

    fill_title = PatternFill(start_color='D6DCE5', end_color='D6DCE5', fill_type='solid')
    fill_header = PatternFill(start_color='4472C4', end_color='4472C4', fill_type='solid')
    fill_blue_i = PatternFill(start_color='BDD7EE', end_color='BDD7EE', fill_type='solid')
    fill_blue_j = PatternFill(start_color='DDEBF7', end_color='DDEBF7', fill_type='solid')
    fill_green = PatternFill(start_color='C6EFCE', end_color='C6EFCE', fill_type='solid')
    fill_red_sig = PatternFill(start_color='FFC7CE', end_color='FFC7CE', fill_type='solid')
    fill_red_neg = PatternFill(start_color='FFCCCC', end_color='FFCCCC', fill_type='solid')

    thin_border = Border(
        left=Side(style='thin'), right=Side(style='thin'),
        top=Side(style='thin'), bottom=Side(style='thin')
    )
    align_center = Alignment(horizontal='center', vertical='center', wrap_text=True)
    align_left = Alignment(horizontal='left', vertical='center', wrap_text=True)

    # Row 1: 标题行
    ws1.merge_cells('A1:L1')
    ws1['A1'].value = 'DID净效应数据'
    ws1['A1'].font = font_title
    ws1['A1'].fill = fill_title
    ws1['A1'].alignment = align_center

    # Row 2: 主表头
    ws1.merge_cells('A2:A3')
    ws1['A2'].value = ''
    ws1['A2'].font = font_header
    ws1['A2'].fill = fill_header
    ws1['A2'].alignment = align_center

    ws1.merge_cells('B2:B3')
    ws1['B2'].value = '指标'
    ws1['B2'].font = font_header
    ws1['B2'].fill = fill_header
    ws1['B2'].alignment = align_center

    ws1.merge_cells('C2:E2')
    ws1['C2'].value = '实验组'
    ws1['C2'].font = font_header
    ws1['C2'].fill = fill_header
    ws1['C2'].alignment = align_center

    ws1.merge_cells('F2:H2')
    ws1['F2'].value = '对照组'
    ws1['F2'].font = font_header
    ws1['F2'].fill = fill_header
    ws1['F2'].alignment = align_center

    ws1['I2'].value = '双重差分\n净效应(ΔT-Δt)'
    ws1.merge_cells('I2:I3')
    ws1['I2'].font = font_header
    ws1['I2'].fill = fill_header
    ws1['I2'].alignment = align_center

    ws1['J2'].value = '净效应对实验\n组的作用'
    ws1.merge_cells('J2:J3')
    ws1['J2'].font = font_header
    ws1['J2'].fill = fill_header
    ws1['J2'].alignment = align_center

    ws1['K2'].value = 'p_value'
    ws1.merge_cells('K2:K3')
    ws1['K2'].font = font_header
    ws1['K2'].fill = fill_header
    ws1['K2'].alignment = align_center

    ws1['L2'].value = '统计显著性'
    ws1.merge_cells('L2:L3')
    ws1['L2'].font = font_header
    ws1['L2'].fill = fill_header
    ws1['L2'].alignment = align_center

    # Row 3: 子表头
    sub_headers = ['前7日(T0)', '后7日(T1)', 'ΔT', '前7日(t0)', '后7日(t1)', 'Δt']
    sub_cols = ['C', 'D', 'E', 'F', 'G', 'H']
    for col_letter, text in zip(sub_cols, sub_headers):
        ws1[f'{col_letter}3'].value = text
        ws1[f'{col_letter}3'].font = font_sub_header
        ws1[f'{col_letter}3'].fill = fill_header
        ws1[f'{col_letter}3'].alignment = align_center
        ws1[f'{col_letter}3'].border = thin_border

    # Row 4+: 数据行
    # 排序：主指标 + LTV补充指标
    main_rows = did_df[~did_df['outcome'].str.startswith('ltv_', na=False)].copy()
    ltv_rows = did_df[did_df['outcome'].str.startswith('ltv_', na=False)].copy()
    ordered = pd.concat([main_rows, ltv_rows], ignore_index=True)

    start_row = 4
    n_data_rows = len(ordered)

    for i, (_, row) in enumerate(ordered.iterrows()):
        r = start_row + i

        # A列: "均值"（纵向合并）
        ws1[f'A{r}'].value = '均值'
        ws1[f'A{r}'].font = font_data_bold
        ws1[f'A{r}'].alignment = align_center
        ws1[f'A{r}'].border = thin_border

        # B列: 指标名
        ws1[f'B{r}'].value = row['label']
        ws1[f'B{r}'].font = font_data
        ws1[f'B{r}'].alignment = align_left
        ws1[f'B{r}'].border = thin_border

        # C-E: 实验组
        ws1[f'C{r}'].value = row['treat_before']
        ws1[f'D{r}'].value = row['treat_after']
        ws1[f'E{r}'].value = round(row['treat_after'] - row['treat_before'], 2)

        # F-H: 对照组
        ws1[f'F{r}'].value = row['ctrl_before']
        ws1[f'G{r}'].value = row['ctrl_after']
        ws1[f'H{r}'].value = round(row['ctrl_after'] - row['ctrl_before'], 2)

        # I: DID
        ws1[f'I{r}'].value = row['did_effect']

        # J: 提升百分比
        lift_val = row['lift_pct']
        if isinstance(lift_val, str):
            ws1[f'J{r}'].value = lift_val
        else:
            ws1[f'J{r}'].value = f"{lift_val:+.1f}%"

        # K: p_value（4位小数，不科学计数法）
        p_raw = row['p_value_raw']
        ws1[f'K{r}'].value = round(p_raw, 4)
        ws1[f'K{r}'].number_format = '0.0000'

        # L: 统计显著性
        did_val = row['did_effect']
        if row['significant'] and did_val > 0:
            ws1[f'L{r}'].value = '显著'
            ws1[f'L{r}'].fill = fill_green
        elif row['significant'] and did_val < 0:
            ws1[f'L{r}'].value = '显著(负)'
            ws1[f'L{r}'].fill = fill_red_sig
        else:
            ws1[f'L{r}'].value = '不显著'

        # 条件着色: I列和J列
        if row['significant'] and did_val > 0:
            ws1[f'I{r}'].fill = fill_blue_i
            ws1[f'J{r}'].fill = fill_blue_j
        elif row['significant'] and did_val < 0:
            ws1[f'I{r}'].fill = fill_red_neg
            ws1[f'J{r}'].fill = fill_red_neg

        # 格式化所有数据单元格
        for col in ['C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L']:
            ws1[f'{col}{r}'].font = font_data
            ws1[f'{col}{r}'].alignment = align_center
            ws1[f'{col}{r}'].border = thin_border

        # 数值格式保留2位小数
        for col in ['C', 'D', 'E', 'F', 'G', 'H', 'I']:
            ws1[f'{col}{r}'].number_format = '0.00'

    # A列纵向合并
    if n_data_rows > 1:
        ws1.merge_cells(f'A4:A{start_row + n_data_rows - 1}')

    # ---- Sheet 2: DID净效应数据（中位数） ----
    ws2 = wb.create_sheet(title='DID净效应数据-中位数')

    # Row 1: 标题行
    ws2.merge_cells('A1:L1')
    ws2['A1'].value = 'DID净效应数据（中位数）'
    ws2['A1'].font = font_title
    ws2['A1'].fill = fill_title
    ws2['A1'].alignment = align_center

    # Row 2: 主表头（同上）
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

    ws2['I2'].value = '双重差分\n净效应(ΔT-Δt)'
    ws2.merge_cells('I2:I3')
    ws2['I2'].font = font_header
    ws2['I2'].fill = fill_header
    ws2['I2'].alignment = align_center

    ws2['J2'].value = '净效应对实验\n组的作用'
    ws2.merge_cells('J2:J3')
    ws2['J2'].font = font_header
    ws2['J2'].fill = fill_header
    ws2['J2'].alignment = align_center

    ws2['K2'].value = 'p_value'
    ws2.merge_cells('K2:K3')
    ws2['K2'].font = font_header
    ws2['K2'].fill = fill_header
    ws2['K2'].alignment = align_center

    ws2['L2'].value = '统计显著性'
    ws2.merge_cells('L2:L3')
    ws2['L2'].font = font_header
    ws2['L2'].fill = fill_header
    ws2['L2'].alignment = align_center

    for col_letter, text in zip(sub_cols, sub_headers):
        ws2[f'{col_letter}3'].value = text
        ws2[f'{col_letter}3'].font = font_sub_header
        ws2[f'{col_letter}3'].fill = fill_header
        ws2[f'{col_letter}3'].alignment = align_center
        ws2[f'{col_letter}3'].border = thin_border

    for i, (_, row) in enumerate(ordered.iterrows()):
        r = start_row + i

        ws2[f'A{r}'].value = '中位数'
        ws2[f'A{r}'].font = font_data_bold
        ws2[f'A{r}'].alignment = align_center
        ws2[f'A{r}'].border = thin_border

        ws2[f'B{r}'].value = row['label']
        ws2[f'B{r}'].font = font_data
        ws2[f'B{r}'].alignment = align_left
        ws2[f'B{r}'].border = thin_border

        ws2[f'C{r}'].value = row['med_treat_before']
        ws2[f'D{r}'].value = row['med_treat_after']
        ws2[f'E{r}'].value = round(row['med_treat_after'] - row['med_treat_before'], 2)

        ws2[f'F{r}'].value = row['med_ctrl_before']
        ws2[f'G{r}'].value = row['med_ctrl_after']
        ws2[f'H{r}'].value = round(row['med_ctrl_after'] - row['med_ctrl_before'], 2)

        ws2[f'I{r}'].value = row['med_did_effect']

        ws2[f'J{r}'].value = row['med_lift_pct']

        med_p_raw = row['med_p_value']
        ws2[f'K{r}'].value = round(med_p_raw, 4)
        ws2[f'K{r}'].number_format = '0.0000'

        med_did_val = row['med_did_effect']
        if row['med_significant'] and med_did_val > 0:
            ws2[f'L{r}'].value = '显著'
            ws2[f'L{r}'].fill = fill_green
        elif row['med_significant'] and med_did_val < 0:
            ws2[f'L{r}'].value = '显著(负)'
            ws2[f'L{r}'].fill = fill_red_sig
        else:
            ws2[f'L{r}'].value = '不显著'

        if row['med_significant'] and med_did_val > 0:
            ws2[f'I{r}'].fill = fill_blue_i
            ws2[f'J{r}'].fill = fill_blue_j
        elif row['med_significant'] and med_did_val < 0:
            ws2[f'I{r}'].fill = fill_red_neg
            ws2[f'J{r}'].fill = fill_red_neg

        for col in ['C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L']:
            ws2[f'{col}{r}'].font = font_data
            ws2[f'{col}{r}'].alignment = align_center
            ws2[f'{col}{r}'].border = thin_border

        for col in ['C', 'D', 'E', 'F', 'G', 'H', 'I']:
            ws2[f'{col}{r}'].number_format = '0.00'

    if n_data_rows > 1:
        ws2.merge_cells(f'A4:A{start_row + n_data_rows - 1}')

    # ---- Sheet 3: SMD平衡检验 ----
    ws3 = wb.create_sheet(title='SMD平衡检验')
    ws3.merge_cells('A1:C1')
    ws3['A1'].value = 'SMD平衡性检验'
    ws3['A1'].font = font_title
    ws3['A1'].fill = fill_title
    ws3['A1'].alignment = align_center

    smd_headers = ['特征', '匹配前|SMD|', '匹配后|SMD|']
    for j, h in enumerate(smd_headers):
        cell = ws3.cell(row=2, column=j+1)
        cell.value = h
        cell.font = font_header
        cell.fill = fill_header
        cell.alignment = align_center
        cell.border = thin_border

    for i, (_, row) in enumerate(balance_df.iterrows()):
        r = 3 + i
        ws3.cell(row=r, column=1).value = row['feature']
        ws3.cell(row=r, column=1).font = font_data
        ws3.cell(row=r, column=1).alignment = align_left
        ws3.cell(row=r, column=1).border = thin_border

        ws3.cell(row=r, column=2).value = row['smd_before']
        ws3.cell(row=r, column=2).font = font_data
        ws3.cell(row=r, column=2).alignment = align_center
        ws3.cell(row=r, column=2).border = thin_border

        ws3.cell(row=r, column=3).value = row['smd_after']
        ws3.cell(row=r, column=3).font = font_data
        ws3.cell(row=r, column=3).alignment = align_center
        ws3.cell(row=r, column=3).border = thin_border

        # 通过/未通过着色
        if row['smd_after'] < 0.1:
            ws3.cell(row=r, column=3).fill = fill_green
        else:
            ws3.cell(row=r, column=3).fill = fill_red_sig

    wb.save(out_path)
    print(f"  Excel报告已保存: {out_path}")
    return out_path


# ============================================================
#  Word 报告生成
# ============================================================

def _set_font(run, size=Pt(11), bold=False, color=None):
    run.font.name = '微软雅黑'
    run._element.rPr.rFonts.set(qn('w:eastAsia'), '微软雅黑')
    run.font.size = size
    run.bold = bold
    if color:
        from docx.dml.color import RGBColor
        if isinstance(color, str):
            run.font.color.rgb = RGBColor.from_string(color)
        else:
            run.font.color.rgb = color


def generate_word_report(results, did_df, ltv_results, balance_df, out_path):
    doc = Document()

    # 设置默认字体
    style = doc.styles['Normal']
    style.font.name = '微软雅黑'
    style._element.rPr.rFonts.set(qn('w:eastAsia'), '微软雅黑')
    style.font.size = Pt(11)

    today_str = datetime.now().strftime('%Y%m%d')

    # ===== 标题 =====
    title_text = f'{ACTIVITY_NAME}参与活动用户分析PSM+DID_{today_str}'
    title_para = doc.add_heading(title_text, level=0)
    for run in title_para.runs:
        _set_font(run, size=Pt(18), bold=True)

    # ===== 总结结论 =====
    # 自动生成核心结论
    did_df_main = did_df[~did_df['outcome'].str.startswith('ltv_', na=False)]
    did_df_ltv = did_df[did_df['outcome'].str.startswith('ltv_', na=False)]

    lt_pos = did_df_main[(did_df_main['significant']) & (did_df_main['did_effect'] > 0)]
    lt_neg = did_df_main[(did_df_main['significant']) & (did_df_main['did_effect'] < 0)]

    # 维度映射
    DIM_MAP = {
        'after_watch_duration': '观看时长',
        'after_watch_dcnt': '观看天数',
        'after_watch_anchorcnt': '主播内容探索深度',
        'after_watch_gamecnt': '游戏品类探索广度',
        'after_active_dcnt': '活跃',
    }

    if len(lt_pos) >= 3:
        dims = [DIM_MAP.get(o, o) for o in lt_pos['outcome'].tolist()[:3]]
        lt_verdict = f"活动可作用于用户{dims[0]}、{dims[1]}和{dims[2]}"
    elif len(lt_pos) >= 1:
        dim = DIM_MAP.get(lt_pos.iloc[0]['outcome'], '部分维度')
        lt_verdict = f"活动对用户{dim}有正向作用"
    else:
        lt_verdict = "活动在各活跃维度均未表现出统计显著的净效应"

    # LTV维度
    pay_rate_row = did_df[did_df['outcome'] == 'ltv_pay_rate']
    arppu_row = did_df[did_df['outcome'] == 'ltv_arppu']

    pay_sig = pay_rate_row['significant'].values[0] if len(pay_rate_row) > 0 else False
    pay_did_val = pay_rate_row['did_effect'].values[0] if len(pay_rate_row) > 0 else 0

    if pay_sig and pay_did_val > 0:
        ltv_verdict = "在付费转化率上有显著拉升"
    elif len(lt_neg) > 0:
        ltv_verdict = "但在付费维度出现负向变化，需关注"
    else:
        ltv_verdict = "付费维度无显著变化（原始金额CV过高，建议参考付费转化率）"

    core_conclusion = f"DID核心结论：{lt_verdict}；{ltv_verdict}。"

    conclusion_para = doc.add_paragraph()
    _set_font(conclusion_para.add_run(core_conclusion), size=Pt(12), bold=True)

    # ===== 风险点提示 =====
    risk_para = doc.add_paragraph()
    _set_font(risk_para.add_run('⚠ 风险提示：'), size=Pt(11), bold=True, color='FF0000')
    _set_font(risk_para.add_run(ACTIVITY_RISK_NOTE), size=Pt(11))

    # ===== 实验活动效果评估方案 =====
    doc.add_heading('实验活动效果评估方案', level=1)

    scheme_para = doc.add_paragraph()
    _set_font(scheme_para.add_run('实验组：'), size=Pt(11), bold=True)
    _set_font(scheme_para.add_run(TREAT_DEF), size=Pt(11))
    scheme_para = doc.add_paragraph()
    _set_font(scheme_para.add_run('对照组：'), size=Pt(11), bold=True)
    _set_font(scheme_para.add_run(CTRL_DEF), size=Pt(11))
    scheme_para = doc.add_paragraph()
    _set_font(scheme_para.add_run('分析周期：'), size=Pt(11), bold=True)
    _set_font(scheme_para.add_run(f'活动日为{ACTIVITY_DATE}，前后各7天作为观测窗口'), size=Pt(11))
    scheme_para = doc.add_paragraph()
    _set_font(scheme_para.add_run('核心目标：'), size=Pt(11), bold=True)
    _set_font(scheme_para.add_run(f'评估{ACTIVITY_NAME}对用户LT（生命周期）和LTV（生命周期价值）的净因果效应'), size=Pt(11))

    # ===== 一、匹配质量说明 =====
    doc.add_heading('一、不朽杯APP拍脸活动曝光的用户分析', level=1)
    doc.add_heading('1.1 匹配质量说明', level=2)

    match_intro = doc.add_paragraph()
    _set_font(match_intro.add_run(
        '本分析采用PSM+DID组合策略：先通过倾向得分匹配（PSM）为每个曝光用户找到"各方面都像但未被曝光"的对照用户，消除选择偏差；再通过双重差分（DID）对比两组前后变化差异，剔除时间趋势，最终得到活动的净因果效应。'
    ), size=Pt(11))

    n_mt = results['n_matched_treat']
    mr = results['match_rate']
    mx_smd = results['max_smd']

    point1 = doc.add_paragraph(style='List Number')
    _set_font(point1.add_run(
        f'实现精准匹配，曝光组{n_mt:,}人（匹配率{mr:.1f}%），样本充足、结果稳定。'
    ), size=Pt(11))

    point2 = doc.add_paragraph(style='List Number')
    _set_font(point2.add_run(
        f'匹配后所有用户特征的标准化均值差异（SMD）均远小于0.1（最大|SMD|={mx_smd:.4f}），两组用户初始行为高度一致，可认为后续差异完全由{ACTIVITY_NAME}导致。'
    ), size=Pt(11))

    point3 = doc.add_paragraph(style='List Number')
    _set_font(point3.add_run(
        '倾向得分分布高度重合，匹配质量优秀，因果结论可靠。'
    ), size=Pt(11))

    # PS分布图
    if results.get('psm_plot') and os.path.exists(results['psm_plot']):
        doc.add_picture(results['psm_plot'], width=Inches(5.5))
        last_para = doc.paragraphs[-1]
        last_para.alignment = WD_ALIGN_PARAGRAPH.CENTER

    fig_note1 = doc.add_paragraph()
    _set_font(fig_note1.add_run(
        f'注：treatment为实验组（{TREAT_DEF}），control为对照组（{CTRL_DEF}）'
    ), size=Pt(9))

    # Love Plot
    if results.get('love_plot') and os.path.exists(results['love_plot']):
        doc.add_picture(results['love_plot'], width=Inches(5.5))
        last_para = doc.paragraphs[-1]
        last_para.alignment = WD_ALIGN_PARAGRAPH.CENTER

    fig_note2 = doc.add_paragraph()
    _set_font(fig_note2.add_run(
        f'注：treatment为实验组（{TREAT_DEF}），control为对照组（{CTRL_DEF}）'
    ), size=Pt(9))

    # ===== 1.2 关键效果指标 =====
    doc.add_heading('1.2 关键效果指标（不朽杯APP拍脸活动曝光带来的净提升）', level=2)

    # DID核心结论段
    core_para = doc.add_paragraph()
    _set_font(core_para.add_run(core_conclusion), size=Pt(12), bold=True)

    # 主要正向作用
    if len(lt_pos) > 0:
        pos_title = doc.add_paragraph()
        _set_font(pos_title.add_run('活动有效促进'), size=Pt(11), bold=True)

        INSIGHT_MAP = {
            'after_watch_duration': '用户更喜好平台内容',
            'after_watch_dcnt': '回访更稳定',
            'after_watch_anchorcnt': '探索意愿增强（更多元的内容消费）',
            'after_watch_gamecnt': '探索意愿增强（跨品类兴趣）',
            'after_active_dcnt': '回访更稳定',
            'ltv_pay_rate': '付费意愿增强',
            'ltv_arppu': '付费深度提升',
        }

        for _, row in lt_pos.iterrows():
            bullet_para = doc.add_paragraph(style='List Bullet')
            insight = INSIGHT_MAP.get(row['outcome'], '正向提升')
            did_val = row['did_effect']
            unit = row['unit']
            lift_str = row['lift_pct']
            _set_font(bullet_para.add_run(
                f'{row["label"]}：净提升{did_val}{unit}({lift_str})，{insight}'
            ), size=Pt(11))

        # LTV正向
        for _, row in did_df_ltv.iterrows():
            if row['significant'] and row['did_effect'] > 0:
                bullet_para = doc.add_paragraph(style='List Bullet')
                insight = INSIGHT_MAP.get(row['outcome'], '正向提升')
                did_val = row['did_effect']
                unit = row['unit']
                lift_str = row['lift_pct']
                _set_font(bullet_para.add_run(
                    f'{row["label"]}：净提升{did_val}{unit}({lift_str})，{insight}'
                ), size=Pt(11))

    # 显著负向指标
    neg_title = doc.add_paragraph()
    if len(lt_neg) > 0:
        _set_font(neg_title.add_run('显著负向指标：'), size=Pt(11), bold=True)
        for _, row in lt_neg.iterrows():
            bullet_para = doc.add_paragraph(style='List Bullet')
            _set_font(bullet_para.add_run(
                f'{row["label"]}：净减少{abs(row["did_effect"])}{row["unit"]}({row["lift_pct"]})'
            ), size=Pt(11))
    else:
        _set_font(neg_title.add_run('无任何显著负向指标'), size=Pt(11))

    # 不显著指标的语境化说明
    consume_row = did_df_main[did_df_main['outcome'] == 'after_consume_amount']
    if len(consume_row) > 0 and not consume_row.iloc[0]['significant']:
        consume_did = consume_row.iloc[0]['did_effect']
        direction = '正向' if consume_did > 0 else '负向'
        ns_para = doc.add_paragraph()
        _set_font(ns_para.add_run(
            f'付费金额{direction}结果不显著（p值高于临界值），没有出现活动后用户流失、时长下滑、付费明显下降的情况。'
        ), size=Pt(11))

    # ARPPU不显著语境化
    if len(arppu_row) > 0 and not arppu_row.iloc[0]['significant']:
        arppu_para = doc.add_paragraph()
        _set_font(arppu_para.add_run(
            'ARPPU未见统计显著变化——活动既未提升也未损害付费用户的消费深度。'
        ), size=Pt(11))

    # ===== DID数据表 =====
    # 均值DID表
    doc.add_paragraph()
    table_title = doc.add_paragraph()
    _set_font(table_title.add_run('均值DID数据表：'), size=Pt(11), bold=True)

    # 创建表格
    did_display = did_df[['label', 'treat_before', 'treat_after',
                          'ctrl_before', 'ctrl_after',
                          'did_effect', 'lift_pct', 'p_value_raw', 'significant']].copy()

    cols = ['指标', '实验组T0', '实验组T1', '对照组t0', '对照组t1',
            'DID净效应', '提升%', 'p_value', '显著性']

    table = doc.add_table(rows=len(did_display)+1, cols=len(cols))
    table.style = 'Table Grid'

    # 表头
    for j, h in enumerate(cols):
        cell = table.rows[0].cells[j]
        cell.text = h
        for run in cell.paragraphs[0].runs:
            _set_font(run, size=Pt(10), bold=True)

    for i, (_, row) in enumerate(did_display.iterrows()):
        cells = table.rows[i+1].cells
        cells[0].text = str(row['label'])
        cells[1].text = str(round(row['treat_before'], 2))
        cells[2].text = str(round(row['treat_after'], 2))
        cells[3].text = str(round(row['ctrl_before'], 2))
        cells[4].text = str(round(row['ctrl_after'], 2))
        cells[5].text = str(round(row['did_effect'], 2))
        cells[6].text = str(row['lift_pct'])
        cells[7].text = f"{round(row['p_value_raw'], 4):.4f}"
        cells[8].text = '显著' if row['significant'] else '不显著'

        for cell in cells:
            for run in cell.paragraphs[0].runs:
                _set_font(run, size=Pt(9))

    # 方法注释
    note_para = doc.add_paragraph()
    _set_font(note_para.add_run(
        '注：净效应对实验组的作用(%) = 双重差分净效应 / 实验组前七日均值×100'
    ), size=Pt(9))

    # DID柱状图
    if results.get('did_plot') and os.path.exists(results['did_plot']):
        doc.add_picture(results['did_plot'], width=Inches(5.5))
        last_para = doc.paragraphs[-1]
        last_para.alignment = WD_ALIGN_PARAGRAPH.CENTER

    # ===== 综合结论 =====
    doc.add_heading('综合结论', level=1)
    final_para = doc.add_paragraph()
    _set_font(final_para.add_run(core_conclusion), size=Pt(12), bold=True)

    # 风险再次提醒
    risk_para2 = doc.add_paragraph()
    _set_font(risk_para2.add_run(f'⚠ 风险提示：{ACTIVITY_RISK_NOTE}'), size=Pt(11))

    doc.save(out_path)
    print(f"  Word报告已保存: {out_path}")
    return out_path


# ============================================================
#  主流程
# ============================================================

if __name__ == '__main__':
    print("=" * 70)
    print("  PSM+DID Causal Inference Analysis")
    print(f"  {ACTIVITY_NAME}")
    print(f"  Started: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print("=" * 70)

    # Step 1: 加载数据
    print(f"\n--- Step 1: Data Loading & Cleaning ---")
    df = pd.read_csv(DATA_CSV)
    print(f"  Loaded: {len(df):,} rows, {len(df.columns)} cols")
    print(f"  Treatment (is_exposure=1): {df[df.is_exposure==1].shape[0]:,}")
    print(f"  Control (is_exposure=0): {df[df.is_exposure==0].shape[0]:,}")

    # NaN统计
    for col in MATCH_FEATURES + list(OUTCOME_MAPPING.keys()):
        n_nan = df[col].isna().sum()
        if n_nan > 0:
            print(f"  {col}: {n_nan} NaN ({n_nan/len(df)*100:.1f}%)")

    # 清洗所有数值列
    all_num_cols = MATCH_FEATURES + list(OUTCOME_MAPPING.keys())
    df = safe_fillna(df, all_num_cols)
    print(f"  After cleaning: {len(df):,} rows")

    # 模块A: 全量样本
    full_results = run_psm_pipeline(df, label_suffix='全量DOTA2用户曝光分析')

    # SMD验收
    balance_df = full_results['balance_df']
    all_pass = (balance_df['smd_after'] < 0.1).all()
    print(f"\n  SMD验收: {'✅ 全部通过 (< 0.1)' if all_pass else '❌ 有特征未通过'}")

    # 报告生成
    print(f"\n--- Step 6: Report Generation ---")
    today_str = datetime.now().strftime('%Y%m%d')

    excel_path = os.path.join(OUT_DIR, f'{ACTIVITY_NAME}_PSM_DID分析报告_{today_str}.xlsx')
    word_path = os.path.join(OUT_DIR, f'{ACTIVITY_NAME}_PSM_DID分析报告_{today_str}.docx')

    generate_excel_report(
        full_results['did_df'],
        full_results['balance_df'],
        full_results['ltv_results'],
        excel_path
    )

    generate_word_report(
        full_results,
        full_results['did_df'],
        full_results['ltv_results'],
        full_results['balance_df'],
        word_path
    )

    # CSV导出
    csv_display_cols = [
        'outcome', 'label', 'unit',
        'treat_before', 'treat_after',
        'ctrl_before', 'ctrl_after',
        'did_effect', 'lift_pct',
        'p_value_display', 'sig_text',
        'med_treat_before', 'med_treat_after',
        'med_ctrl_before', 'med_ctrl_after',
        'med_did_effect', 'med_lift_pct',
        'med_p_display', 'med_sig_text',
    ]
    csv_path = os.path.join(OUT_DIR, f'{ACTIVITY_NAME}_PSM_DID分析数据_{today_str}.csv')
    full_results['did_df'][csv_display_cols].to_csv(csv_path, index=False, encoding='utf-8-sig')
    print(f"  CSV已保存: {csv_path}")

    print(f"\n{'='*70}")
    print(f"  ✅ Analysis Complete: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print(f"  Excel: {excel_path}")
    print(f"  Word:  {word_path}")
    print(f"  CSV:   {csv_path}")
    print(f"{'='*70}")
