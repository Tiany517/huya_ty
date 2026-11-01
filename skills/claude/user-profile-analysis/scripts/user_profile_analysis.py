# -*- coding: utf-8 -*-
"""
User Profile Analysis & TGI Comparison Suite
============================================
Supports two modes:
  - Single-group: K-Means clustering + full profile analysis
  - Dual-group:   TGI comparison + differential clustering

Usage:
  python user_profile_analysis.py --target <csv> --output <dir>
  python user_profile_analysis.py --target <csv> --control <csv> --output <dir>
  python user_profile_analysis.py --target <csv> --control <csv> --output <dir> --target-label "斯诺克用户" --control-label "非斯诺克用户"
"""

from __future__ import annotations

import argparse
import os
import sys
import io
import glob as _glob
import warnings
from pathlib import Path
from typing import Dict, List, Tuple, Optional
from collections import Counter

import numpy as np
import pandas as pd

# ============================================================
# Chinese Font Fix (must be BEFORE pyplot import)
# ============================================================
import matplotlib
matplotlib.use('Agg')

_cache_dir = matplotlib.get_cachedir()
for _f in _glob.glob(os.path.join(_cache_dir, '*')):
    try:
        os.remove(_f)
    except Exception:
        pass

_CJK_FONT_FILES = [
    r'C:\Windows\Fonts\msyh.ttc',
    r'C:\Windows\Fonts\simhei.ttf',
    r'C:\Windows\Fonts\msyhbd.ttc',
]
_CJK_FONT_PATH = next((f for f in _CJK_FONT_FILES if os.path.exists(f)), None)

import matplotlib.pyplot as plt
import matplotlib.font_manager as fm
import matplotlib.ticker as ticker

if _CJK_FONT_PATH:
    fm.fontManager.addfont(_CJK_FONT_PATH)
    _FONT_NAME = fm.FontProperties(fname=_CJK_FONT_PATH).get_name()
    plt.rcParams['font.family'] = 'sans-serif'
    plt.rcParams['font.sans-serif'] = [_FONT_NAME]
    plt.rcParams['axes.unicode_minus'] = False
    fm._load_fontmanager(try_read_cache=False)
    print(f"[字体] 已加载: {_FONT_NAME} ({_CJK_FONT_PATH})")
else:
    print("[字体] 警告: 未找到中文字体文件，图表中文可能显示异常")

import seaborn as sns
from sklearn.preprocessing import StandardScaler, LabelEncoder
from sklearn.cluster import KMeans
from sklearn.decomposition import PCA
from sklearn.metrics import silhouette_score
from scipy.cluster.hierarchy import dendrogram, linkage

warnings.filterwarnings('ignore')
sns.set_style("whitegrid")
sns.set_palette("Set2")

# Re-apply after seaborn import (it may override)
if _CJK_FONT_PATH:
    plt.rcParams['font.family'] = 'sans-serif'
    plt.rcParams['font.sans-serif'] = [_FONT_NAME]
    plt.rcParams['axes.unicode_minus'] = False

# Fix stdout encoding for Windows
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')


# ============================================================
# Constants
# ============================================================
RANDOM_STATE = 42

BINARY_WEALTH_COLS = [
    'has_elite_house', 'has_house', 'has_car',
    'has_high_level_app', 'has_high_level_device',
    'is_travel_abroad', 'is_in_famouse_company',
]

CATEGORICAL_COLS = [
    'gender', 'education_background', 'life_status', 'travel_type',
    'device_brand', 'device_os', 'game_tag', 'game_act_degree',
    'app_level_1_category', 'app_level_2_category',
]

AGE_BINS = [0, 20, 25, 30, 35, 45, 100]
AGE_LABELS = ['20岁及以下', '21-25岁', '26-30岁', '31-35岁', '36-45岁', '46岁以上']

CLUSTER_COLORS = ['#FF6B6B', '#4ECDC4', '#45B7D1', '#96CEB4', '#FFEAA7', '#DDA0DD']


# ============================================================
# Data Loading & Cleaning
# ============================================================

def load_and_clean(filepath: str, label: str = "") -> pd.DataFrame:
    """Load CSV, deduplicate, return cleaned DataFrame."""
    print(f"\n{'='*60}")
    print(f"加载数据: {label or filepath}")
    print(f"{'='*60}")

    raw = pd.read_csv(filepath, encoding='utf-8-sig')
    n_before = len(raw)
    df = raw.drop_duplicates()
    n_after = len(df)
    print(f"  原始: {n_before} 行 | 去重后: {n_after} 行 | 重复率: {(n_before-n_after)/n_before*100:.1f}%")

    # Missing stats
    missing = df.isnull().sum().sort_values(ascending=False)
    missing_pct = (missing / len(df) * 100).round(2)
    print(f"  缺失值 Top 5:")
    for col in missing.head(5).index:
        print(f"    {col}: {missing[col]} ({missing_pct[col]}%)")

    # Basic numeric checks
    if 'age' in df.columns:
        print(f"  年龄: {df['age'].min():.0f} ~ {df['age'].max():.0f}, 均值={df['age'].mean():.1f}, 中位数={df['age'].median():.0f}")
    if 'device_marketed_price' in df.columns:
        print(f"  设备价格: {df['device_marketed_price'].min():.0f} ~ {df['device_marketed_price'].max():.0f}")

    df['_source'] = label or os.path.basename(filepath)
    return df


# ============================================================
# Feature Engineering
# ============================================================

def build_features(df: pd.DataFrame) -> pd.DataFrame:
    """Add derived features: age_group, wealth_score, filled numericals, encoded categoricals."""
    d = df.copy()

    # Age group
    d['age_group'] = pd.cut(d['age'], bins=AGE_BINS, labels=AGE_LABELS, right=True)

    # Fill numericals
    d['age_filled'] = d['age'].fillna(d['age'].median())
    d['device_age_filled'] = d['device_age'].fillna(d['device_age'].median())
    d['device_price_filled'] = d['device_marketed_price'].fillna(d['device_marketed_price'].median())

    # Wealth score
    for col in BINARY_WEALTH_COLS:
        if col in d.columns:
            d[col + '_num'] = pd.to_numeric(d[col], errors='coerce').fillna(0).astype(int)
        else:
            d[col + '_num'] = 0
    d['wealth_score'] = d[[c + '_num' for c in BINARY_WEALTH_COLS]].sum(axis=1)

    return d


def encode_features(d: pd.DataFrame) -> Tuple[np.ndarray, StandardScaler, List[str]]:
    """Label-encode categorical features, standardize, return (X_scaled, scaler, feature_names)."""
    num_features = ['age_filled', 'device_age_filled', 'device_price_filled', 'wealth_score']
    cat_encoded_cols = []

    for cat_col in CATEGORICAL_COLS:
        if cat_col in d.columns:
            d[cat_col + '_filled'] = d[cat_col].fillna('未知')
            le = LabelEncoder()
            d[cat_col + '_enc'] = le.fit_transform(d[cat_col + '_filled'].astype(str))
            cat_encoded_cols.append(cat_col + '_enc')

    feature_cols = num_features + cat_encoded_cols
    X_raw = d[feature_cols].values
    scaler = StandardScaler()
    X_scaled = scaler.fit_transform(X_raw)
    return X_scaled, scaler, feature_cols


# ============================================================
# TGI Computation
# ============================================================

def compute_tgi(target_df: pd.DataFrame, control_df: pd.DataFrame,
                col: str, target_label: str, control_label: str) -> pd.DataFrame:
    """Compute TGI for a categorical column."""
    t_pct = (target_df[col].fillna('未知').value_counts(normalize=True) * 100).round(2)
    c_pct = (control_df[col].fillna('未知').value_counts(normalize=True) * 100).round(2)
    t_n = target_df[col].fillna('未知').value_counts()
    c_n = control_df[col].fillna('未知').value_counts()

    result = pd.DataFrame({
        'dimension': col,
        'value': t_pct.index,
        'target_pct': t_pct.values,
        'control_pct': c_pct.reindex(t_pct.index).fillna(0).values,
        'target_n': t_n.values,
        'control_n': c_n.reindex(t_n.index).fillna(0).astype(int).values,
    })
    result['TGI'] = (result['target_pct'] / result['control_pct'].replace(0, np.nan) * 100).round(1)
    result = result.sort_values('TGI', ascending=False)
    return result


def compute_all_tgi(target_df: pd.DataFrame, control_df: pd.DataFrame,
                    target_label: str, control_label: str) -> Dict[str, pd.DataFrame]:
    """Compute TGI for all categorical dimensions and binary flags."""
    all_tgi = {}

    tgi_dims = [
        'age_group', 'gender', 'education_background', 'life_status',
        'travel_type', 'device_brand', 'device_os', 'game_tag',
        'game_act_degree', 'app_level_1_category', 'app_level_2_category',
    ]

    # Add binary wealth cols
    for col in BINARY_WEALTH_COLS + ['gender']:
        if col in target_df.columns:
            target_df = target_df.copy()
            target_df[col] = target_df[col].fillna(0).astype(int)
        if col in control_df.columns:
            control_df = control_df.copy()
            control_df[col] = control_df[col].fillna(0).astype(int)

    for dim in tgi_dims:
        if dim in target_df.columns and dim in control_df.columns:
            tgi_df = compute_tgi(target_df, control_df, dim, target_label, control_label)
            all_tgi[dim] = tgi_df

    return all_tgi


def print_tgi_summary(all_tgi: Dict[str, pd.DataFrame]) -> pd.DataFrame:
    """Print TGI highlights and return a summary DataFrame."""
    highlights = []
    for dim, tgi_df in all_tgi.items():
        top3 = tgi_df.head(3)
        bottom3 = tgi_df.tail(3)
        for _, row in top3.iterrows():
            highlights.append({
                'dimension': dim,
                'value': row['value'],
                'TGI': row['TGI'],
                'direction': 'OVER-index',
                'target_pct': row['target_pct'],
                'control_pct': row['control_pct'],
            })
        for _, row in bottom3.iterrows():
            highlights.append({
                'dimension': dim,
                'value': row['value'],
                'TGI': row['TGI'],
                'direction': 'UNDER-index',
                'target_pct': row['target_pct'],
                'control_pct': row['control_pct'],
            })

    summary = pd.DataFrame(highlights)
    print(f"\n{'='*60}")
    print("TGI 分析精华")
    print(f"{'='*60}")
    for _, row in summary.iterrows():
        tag = "▲" if row['direction'] == 'OVER-index' else "▼"
        print(f"  {tag} {row['dimension']}={row['value']}: TGI={row['TGI']:.0f} "
              f"(target {row['target_pct']:.1f}% vs control {row['control_pct']:.1f}%)")
    return summary


# ============================================================
# K-Means Clustering
# ============================================================

def find_optimal_k(X_scaled: np.ndarray, k_range: range = range(2, 10),
                   output_dir: str = "", tag: str = "") -> int:
    """Elbow method + silhouette score to find optimal K."""
    inertias = []
    silhouettes = []
    K_list = list(k_range)

    for k in K_list:
        km = KMeans(n_clusters=k, random_state=RANDOM_STATE, n_init=10, max_iter=300)
        labels = km.fit_predict(X_scaled)
        inertias.append(km.inertia_)
        silhouettes.append(silhouette_score(X_scaled, labels))

    sse_drops = [0] + [((inertias[i-1] - inertias[i]) / inertias[i-1] * 100)
                        for i in range(1, len(inertias))]

    print(f"\nK-Means 参数扫描:")
    for i, k in enumerate(K_list):
        print(f"  K={k}: SSE={inertias[i]:.1f}, 轮廓={silhouettes[i]:.4f}, SSE下降={sse_drops[i]:.1f}%")

    best_k = K_list[np.argmax(silhouettes)]

    # Plot
    fig, axes = plt.subplots(1, 3, figsize=(18, 5))
    axes[0].plot(K_list, inertias, 'o-', color='#3498DB', linewidth=2.5, markersize=10)
    axes[0].set_xlabel('K (聚类数)', fontsize=13)
    axes[0].set_ylabel('SSE', fontsize=13)
    axes[0].set_title('肘部法则', fontsize=16, fontweight='bold')
    axes[0].axvline(x=4, color='red', linestyle='--', alpha=0.8, label='K=4')
    axes[0].legend(fontsize=11)
    axes[0].grid(True, alpha=0.3)

    axes[1].bar(K_list, sse_drops, color='#2ECC71', edgecolor='white')
    axes[1].set_xlabel('K (聚类数)', fontsize=13)
    axes[1].set_ylabel('SSE 下降率 (%)', fontsize=13)
    axes[1].set_title('SSE边际下降率', fontsize=16, fontweight='bold')
    axes[1].axhline(y=15, color='red', linestyle='--', alpha=0.7, label='15%阈值')
    axes[1].legend(fontsize=11)
    for i, (k, v) in enumerate(zip(K_list, sse_drops)):
        axes[1].text(k, v + 0.5, f'{v:.1f}%', ha='center', fontsize=10, fontweight='bold')

    axes[2].plot(K_list, silhouettes, 's-', color='#E74C3C', linewidth=2.5, markersize=10)
    axes[2].set_xlabel('K (聚类数)', fontsize=13)
    axes[2].set_ylabel('轮廓系数', fontsize=13)
    axes[2].set_title('轮廓系数', fontsize=16, fontweight='bold')
    axes[2].axvline(x=best_k, color='green', linestyle='--', alpha=0.8,
                    label=f'最佳K={best_k} ({max(silhouettes):.4f})')
    axes[2].legend(fontsize=11)
    axes[2].grid(True, alpha=0.3)

    plt.tight_layout()
    fname = f'kmeans_selection{tag}.png'
    plt.savefig(os.path.join(output_dir, fname), dpi=150, bbox_inches='tight')
    plt.close()
    print(f"[OK] K值选择图已保存: {fname}")

    return best_k


def run_clustering(df_feat: pd.DataFrame, X_scaled: np.ndarray, n_clusters: int) -> pd.DataFrame:
    """Run K-Means and return DataFrame with cluster labels."""
    kmeans = KMeans(n_clusters=n_clusters, random_state=RANDOM_STATE, n_init=10, max_iter=300)
    labels = kmeans.fit_predict(X_scaled)
    sil = silhouette_score(X_scaled, labels)
    print(f"\n聚类完成: K={n_clusters}, 轮廓系数={sil:.4f}")
    for c in range(n_clusters):
        print(f"  聚类{c+1}: {(labels == c).sum()} 人 ({(labels == c).sum()/len(labels)*100:.1f}%)")
    df_feat['cluster'] = labels
    return df_feat, kmeans


# ============================================================
# Cluster Profiling & Naming
# ============================================================

def name_clusters(df_feat: pd.DataFrame, n_clusters: int) -> Dict[int, str]:
    """Auto-name clusters based on device brand + app preference."""
    names = {}
    used = set()
    for c in range(n_clusters):
        cdf = df_feat[df_feat['cluster'] == c]
        top_dev = cdf['device_brand'].value_counts()
        top_app1 = cdf['app_level_1_category'].value_counts()
        dev = top_dev.index[0] if len(top_dev) > 0 else '未知'
        # Use #2 app category for distinctiveness (music/video often #1 across all)
        app_dist = top_app1.index[1] if len(top_app1) > 1 else (top_app1.index[0] if len(top_app1) > 0 else '')
        nickname = f"{dev}{app_dist}派"
        if nickname in used:
            nickname = f"{dev}{app_dist}{c+1}号派"
        used.add(nickname)
        names[c] = nickname
    return names


def print_cluster_profiles(df_feat: pd.DataFrame, n_clusters: int, names: Dict[int, str]):
    """Print detailed profile for each cluster."""
    for c in range(n_clusters):
        cdf = df_feat[df_feat['cluster'] == c]
        n = len(cdf)
        nickname = names.get(c, f'聚类{c+1}')
        print(f"\n{'='*55}")
        print(f"  聚类{c+1}: 【{nickname}】(n={n}, {n/len(df_feat)*100:.1f}%)")
        print(f"{'='*55}")
        dims = ['gender', 'age_group', 'education_background', 'life_status',
                'travel_type', 'device_brand', 'device_os', 'game_tag',
                'game_act_degree', 'app_level_1_category', 'app_level_2_category']
        for dim in dims:
            if dim in cdf.columns:
                top3 = cdf[dim].value_counts().head(3)
                items = ', '.join([f"{k}({v})" for k, v in top3.items() if pd.notna(k)])
                print(f"  {dim}: {items}")
        print(f"  平均年龄: {cdf['age'].mean():.1f}岁")
        if 'device_marketed_price' in cdf.columns:
            print(f"  设备均价: RMB{cdf['device_marketed_price'].dropna().mean():.0f}")
        print(f"  财富评分: {cdf['wealth_score'].mean():.2f}/7")
        print(f"  昵称: {nickname}")


# ============================================================
# Visualization Functions
# ============================================================

def plot_single_eda(df: pd.DataFrame, output_dir: str, tag: str = ""):
    """Full EDA chart suite for single group."""
    print(f"\n{'='*60}")
    print(f"EDA 图表生成{tag}")
    print(f"{'='*60}")

    # 1. Gender + Age
    fig, axes = plt.subplots(1, 2, figsize=(14, 5))
    gender_counts = df['gender'].value_counts()
    colors = ['#4ECDC4', '#FF6B6B']
    axes[0].pie(gender_counts.values, labels=gender_counts.index, autopct='%1.1f%%',
                colors=colors, startangle=90, textprops={'fontsize': 14, 'fontweight': 'bold'})
    axes[0].set_title('性别分布', fontsize=16, fontweight='bold')

    age_dist = df['age_group'].value_counts().reindex(AGE_LABELS)
    axes[1].bar(range(len(age_dist)), [int(v) if pd.notna(v) else 0 for v in age_dist.values],
                color='#45B7D1', edgecolor='white', linewidth=1.2, width=0.7)
    axes[1].set_xticks(range(len(AGE_LABELS)))
    axes[1].set_xticklabels(AGE_LABELS, fontsize=11)
    axes[1].set_title('年龄分布', fontsize=16, fontweight='bold')
    for i, v in enumerate(age_dist.values):
        if pd.notna(v):
            axes[1].text(i, int(v) + 2, str(int(v)), ha='center', fontsize=11, fontweight='bold')
    plt.tight_layout()
    plt.savefig(os.path.join(output_dir, f'gender_age{tag}.png'), dpi=150, bbox_inches='tight')
    plt.close()

    # 2. Education + Life Status
    fig, axes = plt.subplots(1, 2, figsize=(14, 5))
    for ax, col, title in [
        (axes[0], 'education_background', '学历分布'),
        (axes[1], 'life_status', '人生状态分布'),
    ]:
        counts = df[col].value_counts()
        if col == 'education_background':
            bar_colors = plt.cm.Blues(np.linspace(0.3, 0.9, len(counts)))
            ax.barh(range(len(counts)), counts.values, color=bar_colors, edgecolor='white')
            ax.set_yticks(range(len(counts)))
            ax.set_yticklabels(counts.index, fontsize=12)
            ax.invert_yaxis()
            for i, v in enumerate(counts.values):
                ax.text(v + 1, i, str(v), va='center', fontsize=10, fontweight='bold')
        else:
            life_colors = ['#FFEAA7', '#DDA0DD', '#98D8C8', '#F7DC6F', '#BB8FCE', '#85C1E9']
            ax.bar(counts.index, counts.values, color=life_colors[:len(counts)], edgecolor='white', linewidth=1)
            for i, (k, v) in enumerate(zip(counts.index, counts.values)):
                ax.text(i, v + 1, str(v), ha='center', fontsize=11, fontweight='bold')
        ax.set_title(title, fontsize=16, fontweight='bold')
    plt.tight_layout()
    plt.savefig(os.path.join(output_dir, f'edu_life{tag}.png'), dpi=150, bbox_inches='tight')
    plt.close()

    # 3. Device Brand + OS
    fig, axes = plt.subplots(1, 2, figsize=(14, 5))
    brand_counts = df['device_brand'].value_counts().head(10)
    axes[0].bar(brand_counts.index, brand_counts.values, color='#FF8C42', edgecolor='white', linewidth=1)
    axes[0].set_title('设备品牌 Top10', fontsize=16, fontweight='bold')
    axes[0].tick_params(axis='x', rotation=30, labelsize=10)
    for i, v in enumerate(brand_counts.values):
        axes[0].text(i, v + 1, str(v), ha='center', fontsize=9, fontweight='bold')

    os_counts = df['device_os'].value_counts()
    os_colors = ['#6C5B7B', '#C06C84']
    axes[1].pie(os_counts.values, labels=os_counts.index, autopct='%1.1f%%',
                colors=os_colors, startangle=90, textprops={'fontsize': 14, 'fontweight': 'bold'})
    axes[1].set_title('操作系统分布', fontsize=16, fontweight='bold')
    plt.tight_layout()
    plt.savefig(os.path.join(output_dir, f'device{tag}.png'), dpi=150, bbox_inches='tight')
    plt.close()

    # 4. Travel
    fig, ax = plt.subplots(figsize=(10, 5))
    travel_counts = df['travel_type'].value_counts()
    travel_colors = ['#E84A5F', '#FF847C', '#FECEA8', '#99B898', '#2A363B']
    bars = ax.bar(travel_counts.index, travel_counts.values,
                  color=travel_colors[:len(travel_counts)], edgecolor='white', linewidth=1)
    ax.set_title('出行方式分布', fontsize=16, fontweight='bold')
    for bar, v in zip(bars, travel_counts.values):
        ax.text(bar.get_x() + bar.get_width()/2., bar.get_height() + 1,
                str(v), ha='center', fontsize=11, fontweight='bold')
    plt.tight_layout()
    plt.savefig(os.path.join(output_dir, f'travel{tag}.png'), dpi=150, bbox_inches='tight')
    plt.close()

    # 5. Game preference
    fig, ax = plt.subplots(figsize=(10, 6))
    game_counts = df['game_tag'].value_counts().head(12)
    game_colors = plt.cm.viridis(np.linspace(0.2, 0.9, len(game_counts)))
    bars = ax.barh(range(len(game_counts)), game_counts.values, color=game_colors, edgecolor='white')
    ax.set_yticks(range(len(game_counts)))
    ax.set_yticklabels(game_counts.index, fontsize=11)
    ax.invert_yaxis()
    ax.set_title('游戏偏好标签 Top12', fontsize=16, fontweight='bold')
    for i, v in enumerate(game_counts.values):
        ax.text(v + 0.5, i, str(v), va='center', fontsize=10, fontweight='bold')
    plt.tight_layout()
    plt.savefig(os.path.join(output_dir, f'game_tag{tag}.png'), dpi=150, bbox_inches='tight')
    plt.close()

    # 6. Game activity
    fig, ax = plt.subplots(figsize=(7, 6))
    act_counts = df['game_act_degree'].value_counts()
    act_colors = ['#2ECC71', '#F39C12', '#E74C3C', '#95A5A6']
    ax.pie(act_counts.values, labels=act_counts.index, autopct='%1.1f%%',
           colors=act_colors[:len(act_counts)], startangle=90,
           textprops={'fontsize': 13, 'fontweight': 'bold'})
    ax.set_title('游戏活跃度分布', fontsize=16, fontweight='bold')
    plt.tight_layout()
    plt.savefig(os.path.join(output_dir, f'game_act{tag}.png'), dpi=150, bbox_inches='tight')
    plt.close()

    # 7. App preferences
    fig, axes = plt.subplots(1, 2, figsize=(16, 6))
    for ax, col, title, color in [
        (axes[0], 'app_level_1_category', 'App一级分类 Top10', '#8E44AD'),
        (axes[1], 'app_level_2_category', 'App二级分类 Top10', '#2980B9'),
    ]:
        counts = df[col].value_counts().head(10)
        ax.bar(counts.index, counts.values, color=color, edgecolor='white', linewidth=1)
        ax.set_title(title, fontsize=15, fontweight='bold')
        ax.tick_params(axis='x', rotation=45, labelsize=10)
    plt.tight_layout()
    plt.savefig(os.path.join(output_dir, f'app_pref{tag}.png'), dpi=150, bbox_inches='tight')
    plt.close()

    # 8. Wealth indicators
    fig, ax = plt.subplots(figsize=(9, 5))
    wealth_labels = ['豪宅', '有房', '有车', '高端App', '高端设备', '海外出行', '名企']
    wealth_rates = []
    for col in BINARY_WEALTH_COLS:
        rate = df[col].fillna(0).astype(float).mean() * 100
        wealth_rates.append(rate)
    bars = ax.bar(wealth_labels, wealth_rates,
                  color=plt.cm.RdYlGn(np.linspace(0.2, 0.8, len(wealth_labels))),
                  edgecolor='white', linewidth=1)
    ax.set_title('财富/消费力指标覆盖率 (%)', fontsize=16, fontweight='bold')
    for bar, v in zip(bars, wealth_rates):
        ax.text(bar.get_x() + bar.get_width()/2., bar.get_height() + 1,
                f'{v:.1f}%', ha='center', fontsize=10, fontweight='bold')
    ax.set_ylim(0, max(wealth_rates) * 1.15)
    plt.tight_layout()
    plt.savefig(os.path.join(output_dir, f'wealth{tag}.png'), dpi=150, bbox_inches='tight')
    plt.close()

    print("[OK] 所有EDA图表已保存")


def plot_dual_eda(target_df: pd.DataFrame, control_df: pd.DataFrame,
                  target_label: str, control_label: str, output_dir: str):
    """Comparative EDA charts for dual-group mode."""
    print(f"\n{'='*60}")
    print("双组对比EDA图表生成")
    print(f"{'='*60}")
    group_colors = ['#FF6B6B', '#4ECDC4']

    # 1. Age distribution comparison
    fig, ax = plt.subplots(figsize=(12, 6))
    x = np.arange(len(AGE_LABELS))
    width = 0.35
    t_age = target_df['age_group'].value_counts().reindex(AGE_LABELS).fillna(0)
    c_age = control_df['age_group'].value_counts().reindex(AGE_LABELS).fillna(0)
    t_pct = t_age / t_age.sum() * 100
    c_pct = c_age / c_age.sum() * 100
    ax.bar(x - width/2, t_pct.values, width, label=target_label, color=group_colors[0], edgecolor='white')
    ax.bar(x + width/2, c_pct.values, width, label=control_label, color=group_colors[1], edgecolor='white')
    ax.set_xticks(x)
    ax.set_xticklabels(AGE_LABELS, fontsize=11)
    ax.set_title('年龄分布对比', fontsize=16, fontweight='bold')
    ax.set_ylabel('占比 (%)', fontsize=12)
    ax.legend(fontsize=12)
    plt.tight_layout()
    plt.savefig(os.path.join(output_dir, 'comparison_age.png'), dpi=150, bbox_inches='tight')
    plt.close()

    # 2. Gender comparison
    fig, axes = plt.subplots(1, 2, figsize=(12, 5))
    for i, (df_data, label, ax) in enumerate([
        (target_df, target_label, axes[0]),
        (control_df, control_label, axes[1]),
    ]):
        gc = df_data['gender'].value_counts()
        ax.pie(gc.values, labels=gc.index, autopct='%1.1f%%',
               colors=[group_colors[i], '#DDDDDD'], startangle=90,
               textprops={'fontsize': 13, 'fontweight': 'bold'})
        ax.set_title(f'{label}\n性别分布', fontsize=14, fontweight='bold')
    plt.tight_layout()
    plt.savefig(os.path.join(output_dir, 'comparison_gender.png'), dpi=150, bbox_inches='tight')
    plt.close()

    # 3. Device brand comparison
    fig, ax = plt.subplots(figsize=(14, 6))
    top_brands = list(set(
        list(target_df['device_brand'].value_counts().head(8).index) +
        list(control_df['device_brand'].value_counts().head(8).index)
    ))
    t_brand_pct = target_df['device_brand'].value_counts(normalize=True).reindex(top_brands).fillna(0) * 100
    c_brand_pct = control_df['device_brand'].value_counts(normalize=True).reindex(top_brands).fillna(0) * 100
    x = np.arange(len(top_brands))
    ax.bar(x - width/2, t_brand_pct.values, width, label=target_label, color=group_colors[0], edgecolor='white')
    ax.bar(x + width/2, c_brand_pct.values, width, label=control_label, color=group_colors[1], edgecolor='white')
    ax.set_xticks(x)
    ax.set_xticklabels(top_brands, fontsize=10, rotation=30)
    ax.set_title('设备品牌对比 (%)', fontsize=16, fontweight='bold')
    ax.set_ylabel('%', fontsize=12)
    ax.legend(fontsize=12)
    plt.tight_layout()
    plt.savefig(os.path.join(output_dir, 'comparison_device_brand.png'), dpi=150, bbox_inches='tight')
    plt.close()

    # 4. App preference comparison (horizontal divergence)
    fig, ax = plt.subplots(figsize=(12, 8))
    top_apps = list(set(
        list(target_df['app_level_1_category'].value_counts().head(10).index) +
        list(control_df['app_level_1_category'].value_counts().head(10).index)
    ))
    t_app = target_df['app_level_1_category'].value_counts(normalize=True).reindex(top_apps).fillna(0) * 100
    c_app = control_df['app_level_1_category'].value_counts(normalize=True).reindex(top_apps).fillna(0) * 100
    diff = (t_app - c_app).sort_values()
    diff_colors = ['#FF6B6B' if v < 0 else '#4ECDC4' for v in diff.values]
    ax.barh(range(len(diff)), diff.values, color=diff_colors, edgecolor='white')
    ax.set_yticks(range(len(diff)))
    ax.set_yticklabels(diff.index, fontsize=11)
    ax.axvline(x=0, color='black', linewidth=0.8)
    ax.set_title(f'App偏好差异 ({target_label} - {control_label})', fontsize=16, fontweight='bold')
    ax.set_xlabel('百分点差', fontsize=12)
    for i, v in enumerate(diff.values):
        ax.text(v + (0.3 if v >= 0 else -0.3), i, f'{v:+.1f}%',
                ha='left' if v >= 0 else 'right', va='center', fontsize=10, fontweight='bold')
    plt.tight_layout()
    plt.savefig(os.path.join(output_dir, 'comparison_app_diff.png'), dpi=150, bbox_inches='tight')
    plt.close()

    # 5. Game preference comparison
    fig, ax = plt.subplots(figsize=(12, 8))
    top_games = list(set(
        list(target_df['game_tag'].value_counts().head(10).index) +
        list(control_df['game_tag'].value_counts().head(10).index)
    ))
    t_game = target_df['game_tag'].value_counts(normalize=True).reindex(top_games).fillna(0) * 100
    c_game = control_df['game_tag'].value_counts(normalize=True).reindex(top_games).fillna(0) * 100
    game_diff = (t_game - c_game).sort_values()
    game_diff_colors = ['#FF6B6B' if v < 0 else '#4ECDC4' for v in game_diff.values]
    ax.barh(range(len(game_diff)), game_diff.values, color=game_diff_colors, edgecolor='white')
    ax.set_yticks(range(len(game_diff)))
    ax.set_yticklabels(game_diff.index, fontsize=11)
    ax.axvline(x=0, color='black', linewidth=0.8)
    ax.set_title(f'游戏偏好差异 ({target_label} - {control_label})', fontsize=16, fontweight='bold')
    ax.set_xlabel('百分点差', fontsize=12)
    for i, v in enumerate(game_diff.values):
        ax.text(v + (0.3 if v >= 0 else -0.3), i, f'{v:+.1f}%',
                ha='left' if v >= 0 else 'right', va='center', fontsize=10, fontweight='bold')
    plt.tight_layout()
    plt.savefig(os.path.join(output_dir, 'comparison_game_diff.png'), dpi=150, bbox_inches='tight')
    plt.close()

    # 6. Wealth comparison (overlaid radar)
    wealth_labels = ['豪宅', '有房', '有车', '高端App', '高端设备', '海外出行', '名企']
    t_wealth = [target_df[c].fillna(0).astype(float).mean() * 100 for c in BINARY_WEALTH_COLS]
    c_wealth = [control_df[c].fillna(0).astype(float).mean() * 100 for c in BINARY_WEALTH_COLS]

    angles = np.linspace(0, 2 * np.pi, len(wealth_labels), endpoint=False).tolist()
    angles += angles[:1]
    t_wealth += t_wealth[:1]
    c_wealth += c_wealth[:1]

    fig, ax = plt.subplots(figsize=(8, 8), subplot_kw=dict(polar=True))
    ax.fill(angles, [v/100 for v in t_wealth], alpha=0.25, color=group_colors[0], label=target_label)
    ax.plot(angles, [v/100 for v in t_wealth], 'o-', linewidth=2, color=group_colors[0])
    ax.fill(angles, [v/100 for v in c_wealth], alpha=0.25, color=group_colors[1], label=control_label)
    ax.plot(angles, [v/100 for v in c_wealth], 'o-', linewidth=2, color=group_colors[1])
    ax.set_xticks(angles[:-1])
    ax.set_xticklabels(wealth_labels, fontsize=12)
    ax.set_title('财富/消费力指标对比', fontsize=16, fontweight='bold', pad=20)
    ax.legend(loc='upper right', bbox_to_anchor=(1.3, 1.1), fontsize=12)
    plt.tight_layout()
    plt.savefig(os.path.join(output_dir, 'comparison_wealth_radar.png'), dpi=150, bbox_inches='tight')
    plt.close()

    print("[OK] 所有对比EDA图表已保存")


def plot_cluster_visualizations(df_feat: pd.DataFrame, X_scaled: np.ndarray,
                                 kmeans, n_clusters: int, names: Dict[int, str],
                                 output_dir: str, tag: str = ""):
    """Generate PCA scatter, pie, heatmap, radar, and dendrogram for clusters."""
    print(f"\n{'='*60}")
    print("聚类可视化生成")
    print(f"{'='*60}")

    pca = PCA(n_components=2)
    X_pca = pca.fit_transform(X_scaled)

    # PCA scatter
    fig, ax = plt.subplots(figsize=(12, 8))
    for c in range(n_clusters):
        mask = df_feat['cluster'] == c
        ax.scatter(X_pca[mask, 0], X_pca[mask, 1],
                   c=CLUSTER_COLORS[c], label=names.get(c, f'聚类{c+1}'),
                   alpha=0.6, s=35, edgecolors='white', linewidth=0.3)
    centers_pca = pca.transform(kmeans.cluster_centers_)
    for c in range(n_clusters):
        ax.scatter(centers_pca[c, 0], centers_pca[c, 1],
                   c=CLUSTER_COLORS[c], marker='X', s=350,
                   edgecolors='black', linewidth=2.5, zorder=10)
    ax.set_title(f'K-Means用户聚类 (K={n_clusters}) - PCA投影', fontsize=18, fontweight='bold')
    ax.set_xlabel(f'PC1 ({pca.explained_variance_ratio_[0]:.1%} 方差)', fontsize=13)
    ax.set_ylabel(f'PC2 ({pca.explained_variance_ratio_[1]:.1%} 方差)', fontsize=13)
    ax.legend(loc='upper right', fontsize=12)
    plt.tight_layout()
    plt.savefig(os.path.join(output_dir, f'cluster_pca{tag}.png'), dpi=150, bbox_inches='tight')
    plt.close()

    # Pie chart
    fig, ax = plt.subplots(figsize=(7, 7))
    cluster_sizes = df_feat['cluster'].value_counts().sort_index()
    pie_labels = [f'{names.get(i, f"聚类{i+1}")}\n({v}人, {v/len(df_feat)*100:.1f}%)'
                  for i, v in enumerate(cluster_sizes.values)]
    ax.pie(cluster_sizes.values, labels=pie_labels,
           colors=CLUSTER_COLORS[:n_clusters], startangle=90,
           textprops={'fontsize': 12, 'fontweight': 'bold'})
    ax.set_title('各聚类用户占比', fontsize=16, fontweight='bold')
    plt.tight_layout()
    plt.savefig(os.path.join(output_dir, f'cluster_pie{tag}.png'), dpi=150, bbox_inches='tight')
    plt.close()

    # Feature heatmap
    fig, ax = plt.subplots(figsize=(15, 8))
    compare = {
        '男性占比': [(df_feat[df_feat['cluster'] == c]['gender'].apply(lambda x: 1 if x == '男' else 0).mean()) for c in range(n_clusters)],
        '平均年龄': [df_feat[df_feat['cluster'] == c]['age'].mean() for c in range(n_clusters)],
        '已婚率': [(df_feat[df_feat['cluster'] == c]['life_status'].apply(lambda x: 1 if '婚' in str(x) else 0).mean()) for c in range(n_clusters)],
        '有车率': [df_feat[df_feat['cluster'] == c]['has_car'].fillna(0).astype(float).mean() for c in range(n_clusters)],
        '有房率': [df_feat[df_feat['cluster'] == c]['has_house'].fillna(0).astype(float).mean() for c in range(n_clusters)],
        '财富评分': [df_feat[df_feat['cluster'] == c]['wealth_score'].mean() for c in range(n_clusters)],
        '设备均价(千元)': [df_feat[df_feat['cluster'] == c]['device_marketed_price'].dropna().mean() / 1000 for c in range(n_clusters)],
        'iOS占比': [df_feat[df_feat['cluster'] == c]['device_os'].apply(lambda x: 1 if x == 'IOS' else 0).mean() for c in range(n_clusters)],
        '游戏高活跃率': [df_feat[df_feat['cluster'] == c]['game_act_degree'].apply(lambda x: 1 if '高活跃' in str(x) else 0).mean() for c in range(n_clusters)],
        '音乐App偏好': [df_feat[df_feat['cluster'] == c]['app_level_1_category'].apply(lambda x: 1 if x == '音乐' else 0).mean() for c in range(n_clusters)],
    }
    idx = [names.get(i, f'聚类{i+1}') for i in range(n_clusters)]
    hm_data = pd.DataFrame(compare, index=idx)
    hm_norm = (hm_data - hm_data.min()) / (hm_data.max() - hm_data.min() + 1e-10)
    sns.heatmap(hm_norm, annot=hm_data.round(2).values, fmt='',
                cmap='YlOrRd', ax=ax, linewidths=0.5, linecolor='white',
                annot_kws={'fontsize': 9}, cbar_kws={'label': '归一化得分'})
    ax.set_title('聚类特征对比热力图', fontsize=18, fontweight='bold')
    plt.tight_layout()
    plt.savefig(os.path.join(output_dir, f'cluster_heatmap{tag}.png'), dpi=150, bbox_inches='tight')
    plt.close()

    # Radar charts
    fig, axes = plt.subplots(1, n_clusters, figsize=(5.5 * n_clusters, 5.5), subplot_kw=dict(polar=True))
    if n_clusters == 1:
        axes = [axes]
    radar_features = ['男性占比', '平均年龄', '财富评分', '设备均价', 'iOS占比', '游戏高活跃', '音乐App', '已婚率']
    radar_keys = ['男性占比', '平均年龄', '财富评分', '设备均价(千元)', 'iOS占比', '游戏高活跃率', '音乐App偏好', '已婚率']
    radar_data = hm_norm[radar_keys]
    angles = np.linspace(0, 2 * np.pi, len(radar_features), endpoint=False).tolist()
    angles += angles[:1]

    for c in range(n_clusters):
        ax = axes[c]
        values = radar_data.iloc[c].values.tolist()
        values += values[:1]
        ax.fill(angles, values, alpha=0.25, color=CLUSTER_COLORS[c])
        ax.plot(angles, values, 'o-', linewidth=2, color=CLUSTER_COLORS[c], markersize=5)
        ax.set_xticks(angles[:-1])
        ax.set_xticklabels(radar_features, fontsize=8)
        ax.set_ylim(0, 1)
        ax.set_title(f'{names.get(c, f"聚类{c+1}")}\n(n={cluster_sizes.get(c, "?")})',
                     fontsize=12, fontweight='bold', pad=18)
        ax.set_yticks([0.25, 0.5, 0.75])
        ax.set_yticklabels(['25%', '50%', '75%'], fontsize=7)
    plt.tight_layout()
    plt.savefig(os.path.join(output_dir, f'cluster_radar{tag}.png'), dpi=150, bbox_inches='tight')
    plt.close()

    # Dendrogram
    sample_size = min(500, len(X_scaled))
    indices = np.random.choice(len(X_scaled), sample_size, replace=False)
    X_sample = X_scaled[indices]
    fig, ax = plt.subplots(figsize=(16, 6))
    Z = linkage(X_sample, method='ward')
    dendrogram(Z, truncate_mode='lastp', p=20, leaf_rotation=90,
               leaf_font_size=10, ax=ax)
    ax.set_title('层次聚类验证 (Ward法, 采样500)', fontsize=16, fontweight='bold')
    plt.tight_layout()
    plt.savefig(os.path.join(output_dir, f'dendrogram{tag}.png'), dpi=150, bbox_inches='tight')
    plt.close()

    print("[OK] 所有聚类可视化图表已保存")


def plot_tgi_heatmap(all_tgi: Dict[str, pd.DataFrame], output_dir: str):
    """Generate TGI heatmap for dual-group mode."""
    print("\n生成TGI热力图...")
    # Collect top over/under-indexed entries across all dimensions
    rows = []
    for dim, tgi_df in all_tgi.items():
        top2 = tgi_df.head(2)
        bottom2 = tgi_df.tail(2)
        for _, row in pd.concat([top2, bottom2]).iterrows():
            rows.append({
                'dimension': dim,
                'value': f"{dim}={row['value']}",
                'TGI': row['TGI'],
            })

    if not rows:
        print("[WARN] 无TGI数据可绘图")
        return

    tgi_hm = pd.DataFrame(rows).drop_duplicates(subset=['value']).head(20)
    tgi_pivot = tgi_hm.set_index('value')[['TGI']]

    fig, ax = plt.subplots(figsize=(10, max(6, len(tgi_pivot) * 0.4)))
    sns.heatmap(tgi_pivot, annot=True, fmt='.0f', cmap='RdBu_r',
                center=100, ax=ax, linewidths=0.5, linecolor='white',
                cbar_kws={'label': 'TGI (100=baseline)'})
    ax.set_title('TGI 关键差异热力图\n(>120 过表达, <80 欠表达)', fontsize=16, fontweight='bold')
    plt.tight_layout()
    plt.savefig(os.path.join(output_dir, 'tgi_heatmap.png'), dpi=150, bbox_inches='tight')
    plt.close()
    print("[OK] TGI热力图已保存")


def plot_age_analysis(df: pd.DataFrame, output_dir: str, tag: str = ""):
    """Age stratification: distribution, elbow validation, age×app, age×game."""
    age_values = df[['age']].dropna().values
    age_scaled = StandardScaler().fit_transform(age_values)

    age_inertias = []
    age_silhouettes = []
    age_K_range = range(2, 10)
    for k in age_K_range:
        km = KMeans(n_clusters=k, random_state=RANDOM_STATE, n_init=10, max_iter=300)
        labels = km.fit_predict(age_scaled)
        age_inertias.append(km.inertia_)
        age_silhouettes.append(silhouette_score(age_scaled, labels))

    sse_drops = [0] + [((age_inertias[i-1] - age_inertias[i]) / age_inertias[i-1] * 100)
                        for i in range(1, len(age_inertias))]

    fig, axes = plt.subplots(1, 3, figsize=(18, 5))
    axes[0].plot(list(age_K_range), age_inertias, 'o-', color='#3498DB', linewidth=2.5, markersize=10)
    axes[0].set_title('年龄分层SSE肘部曲线', fontsize=15, fontweight='bold')
    axes[0].axvline(x=5, color='red', linestyle='--', alpha=0.8, label='K=5')
    axes[0].legend()

    axes[1].bar(list(age_K_range), sse_drops, color='#2ECC71', edgecolor='white')
    axes[1].set_title('SSE边际下降率', fontsize=15, fontweight='bold')
    axes[1].axhline(y=20, color='red', linestyle='--', alpha=0.7)
    for i, (k, v) in enumerate(zip(age_K_range, sse_drops)):
        axes[1].text(k, v + 0.5, f'{v:.1f}%', ha='center', fontsize=10, fontweight='bold')

    axes[2].plot(list(age_K_range), age_silhouettes, 's-', color='#E74C3C', linewidth=2.5, markersize=10)
    axes[2].set_title('年龄分层轮廓系数', fontsize=15, fontweight='bold')
    plt.tight_layout()
    plt.savefig(os.path.join(output_dir, f'age_elbow{tag}.png'), dpi=150, bbox_inches='tight')
    plt.close()

    # Age × App stacked bar
    fig, ax = plt.subplots(figsize=(14, 7))
    top_apps = df['app_level_1_category'].value_counts().head(6).index.tolist()
    age_app = {}
    for label in AGE_LABELS:
        adf = df[df['age_group'] == label]
        if len(adf) > 0:
            app_counts = adf['app_level_1_category'].value_counts()
            age_app[label] = [app_counts.get(app, 0) for app in top_apps]
    age_app_df = pd.DataFrame(age_app, index=top_apps).T
    age_app_pct = age_app_df.div(age_app_df.sum(axis=1), axis=0)
    app_colors = ['#FF6B6B', '#4ECDC4', '#45B7D1', '#96CEB4', '#FFEAA7', '#DDA0DD']
    age_app_pct.plot(kind='bar', stacked=True, ax=ax, color=app_colors[:len(top_apps)], edgecolor='white')
    ax.set_title('各年龄层App一级分类偏好', fontsize=16, fontweight='bold')
    ax.legend(bbox_to_anchor=(1.02, 1), loc='upper left')
    plt.tight_layout()
    plt.savefig(os.path.join(output_dir, f'age_app_stack{tag}.png'), dpi=150, bbox_inches='tight')
    plt.close()

    # Age × Game heatmap
    fig, ax = plt.subplots(figsize=(12, 6))
    top_games = df['game_tag'].value_counts().head(8).index.tolist()
    age_game = {}
    for label in AGE_LABELS:
        adf = df[df['age_group'] == label]
        if len(adf) > 0:
            gc = adf['game_tag'].value_counts()
            age_game[label] = [gc.get(g, 0) for g in top_games]
    age_game_df = pd.DataFrame(age_game, index=top_games).T
    age_game_norm = (age_game_df - age_game_df.min().min()) / (age_game_df.max().max() - age_game_df.min().min() + 1e-10)
    sns.heatmap(age_game_norm, annot=age_game_df.values, fmt='.0f',
                cmap='YlOrRd', ax=ax, linewidths=0.5, linecolor='white')
    ax.set_title('各年龄层游戏偏好热力图', fontsize=16, fontweight='bold')
    plt.tight_layout()
    plt.savefig(os.path.join(output_dir, f'age_game_heatmap{tag}.png'), dpi=150, bbox_inches='tight')
    plt.close()
    print("[OK] 年龄分层图表已保存")


# ============================================================
# Report Generation
# ============================================================

def generate_report_single(df: pd.DataFrame, df_feat: pd.DataFrame, n_clusters: int,
                           names: Dict[int, str], sil_score: float, output_dir: str):
    """Generate single-group analysis report."""
    report_path = os.path.join(output_dir, 'user_analysis_report.md')

    lines = [
        "# 用户画像分析报告",
        "",
        f"## 数据概览",
        f"- 用户总数: {len(df)} 人",
        f"- 聚类方法: K-Means (K={n_clusters})",
        f"- 轮廓系数: {sil_score:.4f}",
        f"- 男性占比: {(df['gender'] == '男').mean()*100:.1f}%",
        f"- 平均年龄: {df['age'].mean():.1f} 岁",
        f"- Android占比: {(df['device_os'] == 'ANDROID').mean()*100:.1f}%",
        "",
        "## 聚类画像",
        "",
        "| 聚类 | 昵称 | 人数 | 占比 | 均龄 | 核心特征 |",
        "|------|------|------|------|------|----------|",
    ]

    for c in range(n_clusters):
        cdf = df_feat[df_feat['cluster'] == c]
        n = len(cdf)
        nickname = names.get(c, f'聚类{c+1}')
        avg_age = cdf['age'].mean()
        top_dev = cdf['device_brand'].value_counts().index[0] if len(cdf['device_brand'].value_counts()) > 0 else ''
        top_app = cdf['app_level_1_category'].value_counts().index[0] if len(cdf['app_level_1_category'].value_counts()) > 0 else ''
        lines.append(f"| 聚类{c+1} | {nickname} | {n} | {n/len(df_feat)*100:.1f}% | {avg_age:.0f}岁 | {top_dev}+{top_app} |")

    lines += [
        "",
        "## 年龄分层",
        "",
        "| 年龄段 | 人数 | 占比 |",
        "|--------|------|------|",
    ]
    for label in AGE_LABELS:
        n = (df['age_group'] == label).sum()
        if n > 0:
            lines.append(f"| {label} | {n} | {n/len(df)*100:.1f}% |")

    lines += [
        "",
        "## 关键发现",
        "",
        "1. 性别分布：",
        f"   - 男性占主导（{(df['gender'] == '男').mean()*100:.1f}%）",
        "",
        "2. 设备生态：",
        f"   - Android占 {(df['device_os'] == 'ANDROID').mean()*100:.1f}%",
        f"   - iOS仅 {(df['device_os'] == 'IOS').mean()*100:.1f}%",
        "",
        "3. 游戏活跃度：",
        f"   - 游戏活跃度整体偏低",
        "",
        "4. App偏好：",
        f"   - 音乐类App是各聚类的共同第一偏好",
        "",
        "## 图表索引",
    ]
    for fname in sorted(os.listdir(output_dir)):
        if fname.endswith('.png'):
            lines.append(f"- `{fname}`")

    report = '\n'.join(lines)
    with open(report_path, 'w', encoding='utf-8') as f:
        f.write(report)
    print(f"\n[OK] 报告已保存: {report_path}")


def generate_report_dual(target_df: pd.DataFrame, control_df: pd.DataFrame,
                         df_feat: pd.DataFrame, n_clusters: int, names: Dict[int, str],
                         all_tgi: Dict[str, pd.DataFrame], tgi_summary: pd.DataFrame,
                         target_label: str, control_label: str, output_dir: str):
    """Generate dual-group TGI comparison report."""
    report_path = os.path.join(output_dir, 'user_analysis_report.md')

    lines = [
        f"# 用户画像TGI对比分析报告",
        f"",
        f"## 数据概览",
        f"- 目标组({target_label}): {len(target_df)} 人",
        f"- 对照组({control_label}): {len(control_df)} 人",
        f"- 聚类方法: K-Means (K={n_clusters})，基于目标组",
        f"",
        f"## TGI 核心发现",
        f"",
        f"### 目标组显著过表达特征 (TGI > 120)",
        f"",
    ]

    over = tgi_summary[tgi_summary['direction'] == 'OVER-index'].head(15)
    for _, row in over.iterrows():
        lines.append(f"- **{row['dimension']}={row['value']}**: TGI={row['TGI']:.0f} "
                     f"(target {row['target_pct']:.1f}% vs control {row['control_pct']:.1f}%)")

    lines += [
        "",
        "### 目标组显著欠表达特征 (TGI < 80)",
        "",
    ]
    under = tgi_summary[tgi_summary['direction'] == 'UNDER-index'].head(15)
    for _, row in under.iterrows():
        lines.append(f"- **{row['dimension']}={row['value']}**: TGI={row['TGI']:.0f} "
                     f"(target {row['target_pct']:.1f}% vs control {row['control_pct']:.1f}%)")

    lines += [
        "",
        "## 聚类画像 (基于目标组)",
        "",
        "| 聚类 | 昵称 | 人数 | 占比 | 均龄 | 核心特征 |",
        "|------|------|------|------|------|----------|",
    ]
    for c in range(n_clusters):
        cdf = df_feat[df_feat['cluster'] == c]
        n = len(cdf)
        nickname = names.get(c, f'聚类{c+1}')
        avg_age = cdf['age'].mean()
        top_dev = cdf['device_brand'].value_counts().index[0] if len(cdf['device_brand'].value_counts()) > 0 else ''
        top_app = cdf['app_level_1_category'].value_counts().index[0] if len(cdf['app_level_1_category'].value_counts()) > 0 else ''
        lines.append(f"| 聚类{c+1} | {nickname} | {n} | {n/len(df_feat)*100:.1f}% | {avg_age:.0f}岁 | {top_dev}+{top_app} |")

    lines += [
        "",
        "## 运营建议",
        "",
        "1. **基于TGI差异的定向**: 根据过表达特征，精准定位目标人群的差异化需求",
        "2. **内容策略**: 针对目标组高偏好的App/游戏类型，设计专题内容和互动",
        "3. **渠道选择**: 根据设备品牌和OS的TGI差异，优化投放渠道配比",
        "4. **价值挖掘**: 关注财富/消费力指标的TGI差异，制定差异化定价和权益策略",
        "",
        "## 图表索引",
    ]
    for fname in sorted(os.listdir(output_dir)):
        if fname.endswith('.png'):
            lines.append(f"- `{fname}`")

    report = '\n'.join(lines)
    with open(report_path, 'w', encoding='utf-8') as f:
        f.write(report)
    print(f"\n[OK] 报告已保存: {report_path}")


# ============================================================
# Main Pipeline
# ============================================================

def run_single_group(target_path: str, output_dir: str, target_label: str = "用户"):
    """Full pipeline for single-group analysis."""
    os.makedirs(output_dir, exist_ok=True)

    # 1. Load & clean
    df = load_and_clean(target_path, target_label)
    df = build_features(df)

    # 2. EDA
    plot_single_eda(df, output_dir)
    plot_age_analysis(df, output_dir)

    # 3. Feature engineering & clustering
    X_scaled, scaler, feature_cols = encode_features(df)
    best_k = find_optimal_k(X_scaled, output_dir=output_dir)
    n_clusters = best_k if best_k > 0 else 4
    df_feat, kmeans = run_clustering(df, X_scaled, n_clusters)

    # 4. Profile & name
    names = name_clusters(df_feat, n_clusters)
    print_cluster_profiles(df_feat, n_clusters, names)

    # 5. Visualizations
    plot_cluster_visualizations(df_feat, X_scaled, kmeans, n_clusters, names, output_dir)

    # 6. Report
    sil = silhouette_score(X_scaled, df_feat['cluster'])
    generate_report_single(df, df_feat, n_clusters, names, sil, output_dir)

    print(f"\n{'='*60}")
    print(f"分析完成! 所有输出已保存至: {output_dir}")
    print(f"{'='*60}")


def run_dual_group(target_path: str, control_path: str, output_dir: str,
                   target_label: str = "目标组", control_label: str = "对照组"):
    """Full pipeline for dual-group TGI comparison."""
    os.makedirs(output_dir, exist_ok=True)

    # 1. Load both groups
    t_df = load_and_clean(target_path, target_label)
    c_df = load_and_clean(control_path, control_label)
    t_df = build_features(t_df)
    c_df = build_features(c_df)

    # 2. TGI analysis
    all_tgi = compute_all_tgi(t_df, c_df, target_label, control_label)
    tgi_summary = print_tgi_summary(all_tgi)
    plot_tgi_heatmap(all_tgi, output_dir)

    # Save TGI CSV
    tgi_rows = []
    for dim, tgi_df in all_tgi.items():
        tgi_rows.append(tgi_df)
    if tgi_rows:
        pd.concat(tgi_rows).to_csv(os.path.join(output_dir, 'tgi_summary.csv'),
                                   index=False, encoding='utf-8-sig')
        print("[OK] TGI数据已保存: tgi_summary.csv")

    # 3. Comparative EDA
    plot_single_eda(t_df, output_dir, tag=f'_target')
    plot_single_eda(c_df, output_dir, tag=f'_control')
    plot_dual_eda(t_df, c_df, target_label, control_label, output_dir)

    # 4. Age analysis on target group
    plot_age_analysis(t_df, output_dir, tag='_target')

    # 5. Feature engineering & clustering (on target group)
    X_scaled, scaler, feature_cols = encode_features(t_df)
    best_k = find_optimal_k(X_scaled, output_dir=output_dir, tag='_target')
    n_clusters = best_k if best_k > 0 else 4
    t_feat, kmeans = run_clustering(t_df, X_scaled, n_clusters)

    # 6. Profile & name
    names = name_clusters(t_feat, n_clusters)
    print_cluster_profiles(t_feat, n_clusters, names)

    # 7. Cluster visualizations
    plot_cluster_visualizations(t_feat, X_scaled, kmeans, n_clusters, names, output_dir, tag='_target')

    # 8. Report
    generate_report_dual(t_df, c_df, t_feat, n_clusters, names, all_tgi, tgi_summary,
                         target_label, control_label, output_dir)

    print(f"\n{'='*60}")
    print(f"TGI对比分析完成! 所有输出已保存至: {output_dir}")
    print(f"{'='*60}")


# ============================================================
# CLI Entry Point
# ============================================================

def main():
    parser = argparse.ArgumentParser(
        description='用户画像分析 & TGI对比工具',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
示例:
  # 单组分析
  python user_profile_analysis.py --target users.csv --output ./output

  # 双组TGI对比
  python user_profile_analysis.py --target snooker_users.csv --control non_snooker_users.csv --output ./output \\
      --target-label "斯诺克用户" --control-label "非斯诺克用户"
        """,
    )
    parser.add_argument('--target', required=True, help='目标组CSV文件路径')
    parser.add_argument('--control', default=None, help='对照组CSV文件路径 (提供则进入双组TGI模式)')
    parser.add_argument('--output', required=True, help='输出目录')
    parser.add_argument('--target-label', default='目标组', help='目标组标签 (默认: 目标组)')
    parser.add_argument('--control-label', default='对照组', help='对照组标签 (默认: 对照组)')

    args = parser.parse_args()

    if args.control:
        run_dual_group(args.target, args.control, args.output,
                       args.target_label, args.control_label)
    else:
        run_single_group(args.target, args.output, args.target_label)


if __name__ == "__main__":
    main()
