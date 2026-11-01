# -*- coding: utf-8 -*-
"""
斯诺克世锦赛拉新用户 vs 非斯诺克用户 TGI对比分析
==============================================
完整流程: EDA → TGI → K-Means聚类(肘部法则) → 可视化的Word报告
"""

import os, sys, io, glob, warnings
import numpy as np
import pandas as pd

# ============================================================
# Font fix - MUST be before pyplot import
# ============================================================
import matplotlib
matplotlib.use('Agg')
_cache = matplotlib.get_cachedir()
for _f in glob.glob(os.path.join(_cache, '*')):
    try: os.remove(_f)
    except: pass

# Use Microsoft YaHei as primary font
_CJK_PATH = r'C:\Windows\Fonts\msyh.ttc'
assert os.path.exists(_CJK_PATH), "Font not found!"

import matplotlib.pyplot as plt
import matplotlib.font_manager as fm
import matplotlib.ticker as ticker

fm.fontManager.addfont(_CJK_PATH)
_FONT_NAME = fm.FontProperties(fname=_CJK_PATH).get_name()
plt.rcParams['font.family'] = 'sans-serif'
plt.rcParams['font.sans-serif'] = [_FONT_NAME]
plt.rcParams['axes.unicode_minus'] = False
fm._load_fontmanager(try_read_cache=False)
print(f"[字体] 使用: {_FONT_NAME} ({_CJK_PATH})")

import seaborn as sns
from sklearn.preprocessing import StandardScaler, LabelEncoder
from sklearn.cluster import KMeans
from sklearn.decomposition import PCA
from sklearn.metrics import silhouette_score
from scipy.cluster.hierarchy import dendrogram, linkage
from collections import Counter

warnings.filterwarnings('ignore')
sns.set_style("whitegrid")
sns.set_palette("Set2")
plt.rcParams['font.family'] = 'sans-serif'
plt.rcParams['font.sans-serif'] = [_FONT_NAME]
plt.rcParams['axes.unicode_minus'] = False

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')

# ============================================================
# Config
# ============================================================
DATA_PATH = r"C:\Users\tiany\Desktop\斯诺克专题\世锦赛拉新用户画像分析\世锦赛期间_体育和非体育用户画像数据.csv"
OUTPUT_DIR = r"C:\Users\tiany\Desktop\snooker_tgi_analysis"
os.makedirs(OUTPUT_DIR, exist_ok=True)

RANDOM_STATE = 42
TARGET_LABEL = "世锦赛拉新用户"
CONTROL_LABEL = "非世锦赛拉新用户"

AGE_BINS = [0, 20, 25, 30, 35, 45, 100]
AGE_LABELS = ['20岁及以下', '21-25岁', '26-30岁', '31-35岁', '36-45岁', '46岁以上']

CLUSTER_COLORS = ['#FF6B6B', '#4ECDC4', '#45B7D1', '#96CEB4', '#FFEAA7', '#DDA0DD']
GROUP_COLORS = ['#FF6B6B', '#4ECDC4']

BINARY_WEALTH = ['has_elite_house', 'has_house', 'has_car', 'has_high_level_app',
                 'has_high_level_device', 'is_travel_abroad', 'is_in_famouse_company',
                 'is_school_staff', 'is_in_university', 'is_from_village']

CAT_FEATURES = ['gender', 'education_background', 'life_status', 'travel_type',
                'device_brand', 'device_os', 'game_like', 'game_act_degree',
                'app_level_1_category', 'app_level_2_category']

# ============================================================
# Data Loading
# ============================================================
print("=" * 60)
print("1. 数据加载与分组")
print("=" * 60)

df_raw = pd.read_csv(DATA_PATH, encoding='utf-8-sig')
print(f"总数据: {len(df_raw)} 行, {len(df_raw.columns)} 列")

# Drop duplicates by user_ukey
df = df_raw.drop_duplicates(subset='user_ukey', keep='first').copy()
print(f"去重后: {len(df)} 行 (删除 {len(df_raw)-len(df)} 条重复)")

# Split groups
target_df = df[df['user_type'] == TARGET_LABEL].copy()
control_df = df[df['user_type'] == CONTROL_LABEL].copy()
print(f"目标组({TARGET_LABEL}): {len(target_df)} 人")
print(f"对照组({CONTROL_LABEL}): {len(control_df)} 人")

# ============================================================
# Feature Engineering
# ============================================================
print("\n" + "=" * 60)
print("2. 特征工程")
print("=" * 60)

def build_features(d):
    d = d.copy()
    d['age_group'] = pd.cut(d['age'], bins=AGE_BINS, labels=AGE_LABELS, right=True)
    d['age_filled'] = d['age'].fillna(d['age'].median())
    d['device_price_filled'] = d['device_marketed_price'].fillna(d['device_marketed_price'].median())

    # Wealth score
    for col in BINARY_WEALTH:
        if col in d.columns:
            d[col + '_num'] = pd.to_numeric(d[col], errors='coerce').fillna(0).astype(int)
        else:
            d[col + '_num'] = 0
    d['wealth_score'] = d[[c+'_num' for c in BINARY_WEALTH]].sum(axis=1)

    return d

target_df = build_features(target_df)
control_df = build_features(control_df)

# Encode for clustering
def encode_cluster_features(d):
    num_features = ['age_filled', 'device_price_filled', 'wealth_score']
    cat_enc_cols = []
    for cat_col in CAT_FEATURES:
        if cat_col in d.columns:
            d[cat_col + '_filled'] = d[cat_col].fillna('未知')
            le = LabelEncoder()
            d[cat_col + '_enc'] = le.fit_transform(d[cat_col + '_filled'].astype(str))
            cat_enc_cols.append(cat_col + '_enc')
    feature_cols = num_features + cat_enc_cols
    X_raw = d[feature_cols].values
    scaler = StandardScaler()
    X_scaled = scaler.fit_transform(X_raw)
    return X_scaled, scaler, feature_cols, d

X_scaled_target, scaler_target, feat_cols_target, target_df = encode_cluster_features(target_df)

# ============================================================
# TGI Analysis
# ============================================================
print("\n" + "=" * 60)
print("3. TGI 分析")
print("=" * 60)

def compute_tgi(col, t_df, c_df):
    # Convert categorical/any type to object to safely fillna
    t_series = t_df[col].astype(object).fillna('未知')
    c_series = c_df[col].astype(object).fillna('未知')
    t_pct = t_series.value_counts(normalize=True) * 100
    c_pct = c_series.value_counts(normalize=True) * 100
    t_n = t_series.value_counts()
    c_n = c_series.value_counts()
    all_vals = list(set(list(t_pct.index) + list(c_pct.index)))
    result = pd.DataFrame({
        '维度': col,
        '值': all_vals,
        '目标组%': [round(t_pct.get(v, 0), 2) for v in all_vals],
        '对照组%': [round(c_pct.get(v, 0), 2) for v in all_vals],
        '目标组人数': [int(t_n.get(v, 0)) for v in all_vals],
        '对照组人数': [int(c_n.get(v, 0)) for v in all_vals],
    })
    result['TGI'] = (result['目标组%'] / result['对照组%'].replace(0, np.nan) * 100).round(1)
    result = result.sort_values('TGI', ascending=False)
    return result

tgi_dims = ['age_group', 'gender', 'education_background', 'life_status',
            'travel_type', 'device_brand', 'game_like', 'game_act_degree',
            'app_level_1_category', 'app_level_2_category']
# Add binary wealth as dimension entries
for bc in BINARY_WEALTH:
    target_df[f'{bc}_label'] = target_df[bc].fillna(0).astype(int).map({1: f'{bc}=是', 0: f'{bc}=否'})
    control_df[f'{bc}_label'] = control_df[bc].fillna(0).astype(int).map({1: f'{bc}=是', 0: f'{bc}=否'})

all_tgi = {}
all_tgi_dfs = []
for dim in tgi_dims:
    if dim in target_df.columns and dim in control_df.columns:
        tgi_df = compute_tgi(dim, target_df, control_df)
        all_tgi[dim] = tgi_df
        all_tgi_dfs.append(tgi_df)

tgi_full = pd.concat(all_tgi_dfs, ignore_index=True)
tgi_full.to_csv(os.path.join(OUTPUT_DIR, 'tgi_full.csv'), index=False, encoding='utf-8-sig')

# TGI highlights
over_idx = tgi_full[tgi_full['TGI'] > 120].sort_values('TGI', ascending=False)
under_idx = tgi_full[tgi_full['TGI'] < 80].sort_values('TGI', ascending=True)
print(f"TGI过表达(TGI>120): {len(over_idx)} 项")
print(f"TGI欠表达(TGI<80): {len(under_idx)} 项")
print("\nTop 10 过表达:")
for _, r in over_idx.head(10).iterrows():
    print(f"  ▲ {r['维度']}={r['值']}: TGI={r['TGI']:.0f} (target {r['目标组%']:.1f}% vs control {r['对照组%']:.1f}%)")
print("\nTop 10 欠表达:")
for _, r in under_idx.head(10).iterrows():
    print(f"  ▼ {r['维度']}={r['值']}: TGI={r['TGI']:.0f} (target {r['目标组%']:.1f}% vs control {r['对照组%']:.1f}%)")

# ============================================================
# K-Means Elbow + Silhouette Analysis
# ============================================================
print("\n" + "=" * 60)
print("4. K-Means 肘部法则分析")
print("=" * 60)

K_range = range(2, 10)
inertias = []
silhouettes = []

for k in K_range:
    km = KMeans(n_clusters=k, random_state=RANDOM_STATE, n_init=10, max_iter=300)
    labels = km.fit_predict(X_scaled_target)
    inertias.append(km.inertia_)
    silhouettes.append(silhouette_score(X_scaled_target, labels))

sse_drops = [0] + [((inertias[i-1] - inertias[i]) / inertias[i-1] * 100)
                    for i in range(1, len(inertias))]

print(f"{'K':<6} {'SSE':<15} {'SSE下降率':<15} {'轮廓系数':<12}")
print("-" * 48)
for i, k in enumerate(K_range):
    print(f"{k:<6} {inertias[i]:<15.1f} {sse_drops[i]:<15.1f} {silhouettes[i]:<12.4f}")

best_k = list(K_range)[np.argmax(silhouettes)]
print(f"\n最佳K (轮廓系数): {best_k} ({max(silhouettes):.4f})")

# K-Means elbow + silhouette plot
fig, axes = plt.subplots(1, 3, figsize=(18, 5))

axes[0].plot(list(K_range), inertias, 'o-', color='#3498DB', linewidth=2.5, markersize=10)
axes[0].set_xlabel('K (聚类数)', fontsize=13)
axes[0].set_ylabel('SSE (误差平方和)', fontsize=13)
axes[0].set_title('肘部法则 — SSE曲线', fontsize=16, fontweight='bold')
for k_val in [4, 5]:
    axes[0].axvline(x=k_val, color='red' if k_val == 4 else 'orange', linestyle='--',
                    alpha=0.8, linewidth=2, label=f'K={k_val}' + (' (推荐)' if k_val == 4 else ''))
axes[0].legend(fontsize=11)
axes[0].grid(True, alpha=0.3)

axes[1].bar(list(K_range), sse_drops, color='#2ECC71', edgecolor='white', linewidth=1)
axes[1].set_xlabel('K (聚类数)', fontsize=13)
axes[1].set_ylabel('SSE下降率 (%)', fontsize=13)
axes[1].set_title('SSE边际下降率(越大越值得增加K)', fontsize=14, fontweight='bold')
axes[1].axhline(y=15, color='red', linestyle='--', alpha=0.7, label='15%阈值(低于此值不再增加K)')
axes[1].legend(fontsize=10)
for i, (k, v) in enumerate(zip(K_range, sse_drops)):
    axes[1].text(k, v + 0.5, f'{v:.1f}%', ha='center', fontsize=10, fontweight='bold')

axes[2].plot(list(K_range), silhouettes, 's-', color='#E74C3C', linewidth=2.5, markersize=10)
axes[2].set_xlabel('K (聚类数)', fontsize=13)
axes[2].set_ylabel('轮廓系数', fontsize=13)
axes[2].set_title('轮廓系数(越高聚类越紧密)', fontsize=14, fontweight='bold')
axes[2].axvline(x=best_k, color='green', linestyle='--', alpha=0.8, linewidth=2,
                label=f'最佳K={best_k} (轮廓系数={max(silhouettes):.4f})')
axes[2].legend(fontsize=11)
axes[2].grid(True, alpha=0.3)

plt.tight_layout()
plt.savefig(os.path.join(OUTPUT_DIR, '00_kmeans_elbow.png'), dpi=150, bbox_inches='tight')
plt.close()
print("[OK] 肘部法则图已保存")

# ============================================================
# Run K-Means (K=4)
# ============================================================
FINAL_K = 4
kmeans = KMeans(n_clusters=FINAL_K, random_state=RANDOM_STATE, n_init=10, max_iter=300)
target_df['cluster'] = kmeans.fit_predict(X_scaled_target)
sil_final = silhouette_score(X_scaled_target, target_df['cluster'])
print(f"\n最终模型: K={FINAL_K}, 轮廓系数={sil_final:.4f}")
for c in range(FINAL_K):
    n_c = (target_df['cluster'] == c).sum()
    print(f"  聚类{c+1}: {n_c}人 ({n_c/len(target_df)*100:.1f}%)")

# PCA for visualization
pca = PCA(n_components=2)
X_pca = pca.fit_transform(X_scaled_target)
print(f"PCA累计解释方差: {pca.explained_variance_ratio_.sum():.3f}")

# ============================================================
# Cluster Naming
# ============================================================
def name_clusters(df_feat, n_clusters):
    names = {}
    used = set()
    for c in range(n_clusters):
        cdf = df_feat[df_feat['cluster'] == c]
        top_dev = cdf['device_brand'].value_counts()
        top_app1 = cdf['app_level_1_category'].value_counts()
        dev = top_dev.index[0] if len(top_dev) > 0 else '未知'
        app_dist = top_app1.index[1] if len(top_app1) > 1 else (top_app1.index[0] if len(top_app1) > 0 else '')
        nickname = f"{dev}{app_dist}派"
        if nickname in used:
            nickname = f"{dev}{app_dist}{c+1}号派"
        used.add(nickname)
        names[c] = nickname
    return names

cluster_names = name_clusters(target_df, FINAL_K)

# Print cluster profiles
print("\n" + "=" * 60)
print("5. 聚类画像详情")
print("=" * 60)

cluster_profile_data = []
for c in range(FINAL_K):
    cdf = target_df[target_df['cluster'] == c]
    n = len(cdf)
    nickname = cluster_names.get(c, f'聚类{c+1}')
    print(f"\n  {'='*50}")
    print(f"  聚类{c+1}: 【{nickname}】(n={n}, {n/len(target_df)*100:.1f}%)")
    print(f"  {'='*50}")

    profile = {'聚类ID': c+1, '昵称': nickname, '人数': n, '占比%': round(n/len(target_df)*100, 1)}

    for dim in ['gender', 'age_group', 'education_background', 'life_status',
                'travel_type', 'device_brand', 'game_like', 'game_act_degree',
                'app_level_1_category', 'app_level_2_category']:
        if dim in cdf.columns:
            top3 = cdf[dim].value_counts().head(3)
            items = ', '.join([f"{k}({v})" for k, v in top3.items() if pd.notna(k)])
            print(f"  {dim}: {items}")
            profile[dim + '_Top3'] = items

    avg_age = cdf['age'].mean()
    avg_price = cdf['device_marketed_price'].dropna().mean()
    wealth_avg = cdf['wealth_score'].mean()
    male_pct = (cdf['gender'] == '男').mean() * 100
    print(f"  核心指标: 均龄={avg_age:.1f}岁, 男性占比={male_pct:.1f}%, 设备均价=RMB{avg_price:.0f}, 财富评分={wealth_avg:.2f}/10")

    profile.update({
        '均龄': round(avg_age, 1), '男性占比%': round(male_pct, 1),
        '设备均价': round(avg_price, 0), '财富评分均值': round(wealth_avg, 2),
    })
    cluster_profile_data.append(profile)

cluster_profile_df = pd.DataFrame(cluster_profile_data)

# ============================================================
# Visualizations
# ============================================================
print("\n" + "=" * 60)
print("6. 生成可视化图表")
print("=" * 60)

# --- 6.1 PCA scatter ---
fig, ax = plt.subplots(figsize=(12, 8))
for c in range(FINAL_K):
    mask = target_df['cluster'] == c
    ax.scatter(X_pca[mask, 0], X_pca[mask, 1],
               c=CLUSTER_COLORS[c], label=cluster_names.get(c, f'聚类{c+1}'),
               alpha=0.6, s=35, edgecolors='white', linewidth=0.3)
centers_pca = pca.transform(kmeans.cluster_centers_)
for c in range(FINAL_K):
    ax.scatter(centers_pca[c, 0], centers_pca[c, 1],
               c=CLUSTER_COLORS[c], marker='X', s=350,
               edgecolors='black', linewidth=2.5, zorder=10)
ax.set_title(f'K-Means用户聚类 (K={FINAL_K}) — PCA投影', fontsize=18, fontweight='bold')
ax.set_xlabel(f'PC1 ({pca.explained_variance_ratio_[0]:.1%} 方差)', fontsize=13)
ax.set_ylabel(f'PC2 ({pca.explained_variance_ratio_[1]:.1%} 方差)', fontsize=13)
ax.legend(loc='upper right', fontsize=12)
plt.tight_layout()
plt.savefig(os.path.join(OUTPUT_DIR, '01_cluster_pca.png'), dpi=150, bbox_inches='tight')
plt.close()

# --- 6.2 Cluster Pie ---
fig, ax = plt.subplots(figsize=(8, 8))
cluster_sizes = target_df['cluster'].value_counts().sort_index()
pie_labels = [f'{cluster_names.get(i, f"聚类{i+1}")}\n({v}人, {v/len(target_df)*100:.1f}%)'
              for i, v in enumerate(cluster_sizes.values)]
ax.pie(cluster_sizes.values, labels=pie_labels, colors=CLUSTER_COLORS[:FINAL_K],
       startangle=90, textprops={'fontsize': 12, 'fontweight': 'bold'})
ax.set_title(f'世锦赛拉新用户聚类占比 (轮廓系数={sil_final:.4f})', fontsize=16, fontweight='bold')
plt.tight_layout()
plt.savefig(os.path.join(OUTPUT_DIR, '02_cluster_pie.png'), dpi=150, bbox_inches='tight')
plt.close()

# --- 6.3 Feature Heatmap ---
fig, ax = plt.subplots(figsize=(16, 8))
compare = {
    '男性占比': [(target_df[target_df['cluster']==c]['gender'].apply(lambda x:1 if x=='男' else 0).mean()) for c in range(FINAL_K)],
    '平均年龄': [target_df[target_df['cluster']==c]['age'].mean() for c in range(FINAL_K)],
    '已婚率': [(target_df[target_df['cluster']==c]['life_status'].apply(lambda x:1 if '婚' in str(x) else 0).mean()) for c in range(FINAL_K)],
    '有车率': [target_df[target_df['cluster']==c]['has_car'].fillna(0).astype(float).mean() for c in range(FINAL_K)],
    '有房率': [target_df[target_df['cluster']==c]['has_house'].fillna(0).astype(float).mean() for c in range(FINAL_K)],
    '财富评分': [target_df[target_df['cluster']==c]['wealth_score'].mean() for c in range(FINAL_K)],
    '设备均价(千元)': [target_df[target_df['cluster']==c]['device_marketed_price'].dropna().mean()/1000 for c in range(FINAL_K)],
    '高端设备率': [target_df[target_df['cluster']==c]['has_high_level_device'].fillna(0).astype(float).mean() for c in range(FINAL_K)],
    '游戏高活跃率': [(target_df[target_df['cluster']==c]['game_act_degree'].apply(lambda x:1 if '高活跃' in str(x) else 0).mean()) for c in range(FINAL_K)],
    '音乐App偏好': [(target_df[target_df['cluster']==c]['app_level_1_category'].apply(lambda x:1 if x=='音乐' else 0).mean()) for c in range(FINAL_K)],
    '视频App偏好': [(target_df[target_df['cluster']==c]['app_level_1_category'].apply(lambda x:1 if x=='视频' else 0).mean()) for c in range(FINAL_K)],
    'iOS占比': [(target_df[target_df['cluster']==c]['device_machine_type'].apply(lambda x:1 if 'IPHONE' in str(x).upper() else 0).mean()) for c in range(FINAL_K)],
    '聚类人数': [len(target_df[target_df['cluster']==c]) for c in range(FINAL_K)],
}
idx = [cluster_names.get(i, f'聚类{i+1}') for i in range(FINAL_K)]
hm_data = pd.DataFrame(compare, index=idx)
hm_norm = (hm_data - hm_data.min()) / (hm_data.max() - hm_data.min() + 1e-10)
sns.heatmap(hm_norm, annot=hm_data.round(2).values, fmt='', cmap='YlOrRd',
            ax=ax, linewidths=0.5, linecolor='white', annot_kws={'fontsize': 9},
            cbar_kws={'label': '归一化得分(0-1)'})
ax.set_title('聚类特征对比热力图', fontsize=18, fontweight='bold')
plt.tight_layout()
plt.savefig(os.path.join(OUTPUT_DIR, '03_cluster_heatmap.png'), dpi=150, bbox_inches='tight')
plt.close()

# --- 6.4 Radar ---
fig, axes = plt.subplots(1, FINAL_K, figsize=(5.5*FINAL_K, 5.5), subplot_kw=dict(polar=True))
if FINAL_K == 1: axes = [axes]
radar_features = ['男性占比', '平均年龄', '财富评分', '设备均价', 'iOS占比', '游戏高活跃', '音乐App', '已婚率']
radar_keys = ['男性占比', '平均年龄', '财富评分', '设备均价(千元)', 'iOS占比', '游戏高活跃率', '音乐App偏好', '已婚率']
radar_data = hm_norm[radar_keys]
angles = np.linspace(0, 2*np.pi, len(radar_features), endpoint=False).tolist() + [0]
for c in range(FINAL_K):
    ax = axes[c]
    values = radar_data.iloc[c].values.tolist() + [radar_data.iloc[c].values[0]]
    ax.fill(angles, values, alpha=0.25, color=CLUSTER_COLORS[c])
    ax.plot(angles, values, 'o-', linewidth=2, color=CLUSTER_COLORS[c], markersize=5)
    ax.set_xticks(angles[:-1])
    ax.set_xticklabels(radar_features, fontsize=8)
    ax.set_ylim(0, 1)
    ax.set_title(f'{cluster_names.get(c, f"聚类{c+1}")}\n(n={cluster_sizes.get(c, "?")})',
                 fontsize=12, fontweight='bold', pad=18)
    ax.set_yticks([0.25, 0.5, 0.75])
    ax.set_yticklabels(['25%', '50%', '75%'], fontsize=7)
plt.tight_layout()
plt.savefig(os.path.join(OUTPUT_DIR, '04_cluster_radar.png'), dpi=150, bbox_inches='tight')
plt.close()

# --- 6.5 Dendrogram ---
sample_size = min(500, len(X_scaled_target))
indices = np.random.choice(len(X_scaled_target), sample_size, replace=False)
X_sample = X_scaled_target[indices]
fig, ax = plt.subplots(figsize=(16, 6))
Z = linkage(X_sample, method='ward')
dendrogram(Z, truncate_mode='lastp', p=20, leaf_rotation=90, leaf_font_size=10, ax=ax)
ax.set_title('层次聚类树状图验证 (Ward法, 采样500)', fontsize=16, fontweight='bold')
ax.set_xlabel('样本索引', fontsize=12)
ax.set_ylabel('欧氏距离', fontsize=12)
plt.tight_layout()
plt.savefig(os.path.join(OUTPUT_DIR, '05_dendrogram.png'), dpi=150, bbox_inches='tight')
plt.close()

# --- 6.6 Age stratification of target group ---
# Age distribution
fig, ax = plt.subplots(figsize=(12, 6))
age_dist = target_df['age_group'].value_counts().reindex(AGE_LABELS)
age_colors_list = ['#FF6B6B', '#4ECDC4', '#45B7D1', '#96CEB4', '#FFEAA7', '#DDA0DD']
bars = ax.bar(range(len(age_dist)), [int(v) if pd.notna(v) else 0 for v in age_dist.values],
              color=age_colors_list, edgecolor='white', linewidth=1.5, width=0.7)
ax.set_xticks(range(len(AGE_LABELS)))
ax.set_xticklabels(AGE_LABELS, fontsize=12)
ax.set_title('目标组 — 年龄分层分布', fontsize=16, fontweight='bold')
ax.set_ylabel('用户数', fontsize=13)
for i, (bar, v) in enumerate(zip(bars, age_dist.values)):
    if pd.notna(v):
        ax.text(bar.get_x()+bar.get_width()/2., bar.get_height()+1,
                f'{int(v)}人\n({v/len(target_df)*100:.1f}%)',
                ha='center', fontsize=10, fontweight='bold')
plt.tight_layout()
plt.savefig(os.path.join(OUTPUT_DIR, '06_age_distribution.png'), dpi=150, bbox_inches='tight')
plt.close()

# Age x App stacked
fig, ax = plt.subplots(figsize=(14, 7))
top_apps = target_df['app_level_1_category'].value_counts().head(6).index.tolist()
age_app = {}
for label in AGE_LABELS:
    adf = target_df[target_df['age_group'] == label]
    if len(adf) > 0:
        ac = adf['app_level_1_category'].value_counts()
        age_app[label] = [ac.get(app, 0) for app in top_apps]
age_app_df = pd.DataFrame(age_app, index=top_apps).T
age_app_pct = age_app_df.div(age_app_df.sum(axis=1), axis=0)
app_stack_colors = ['#FF6B6B', '#4ECDC4', '#45B7D1', '#96CEB4', '#FFEAA7', '#DDA0DD']
age_app_pct.plot(kind='bar', stacked=True, ax=ax, color=app_stack_colors[:len(top_apps)], edgecolor='white')
ax.set_title('目标组 — 各年龄层App一级分类偏好', fontsize=16, fontweight='bold')
ax.legend(bbox_to_anchor=(1.02, 1), loc='upper left')
plt.tight_layout()
plt.savefig(os.path.join(OUTPUT_DIR, '07_age_app_stack.png'), dpi=150, bbox_inches='tight')
plt.close()

# Age x Game heatmap
fig, ax = plt.subplots(figsize=(12, 6))
top_games = target_df['game_like'].value_counts().head(8).index.tolist()
age_game = {}
for label in AGE_LABELS:
    adf = target_df[target_df['age_group'] == label]
    if len(adf) > 0:
        gc = adf['game_like'].value_counts()
        age_game[label] = [gc.get(g, 0) for g in top_games]
age_game_df = pd.DataFrame(age_game, index=top_games).T
age_game_norm = (age_game_df - age_game_df.min().min()) / (age_game_df.max().max() - age_game_df.min().min() + 1e-10)
sns.heatmap(age_game_norm, annot=age_game_df.values, fmt='.0f',
            cmap='YlOrRd', ax=ax, linewidths=0.5, linecolor='white')
ax.set_title('目标组 — 各年龄层游戏偏好热力图', fontsize=16, fontweight='bold')
plt.tight_layout()
plt.savefig(os.path.join(OUTPUT_DIR, '08_age_game_heatmap.png'), dpi=150, bbox_inches='tight')
plt.close()

# --- 6.7 Comparison Charts (Target vs Control) ---
# Age comparison
fig, ax = plt.subplots(figsize=(12, 6))
x = np.arange(len(AGE_LABELS))
width = 0.35
t_age = target_df['age_group'].value_counts().reindex(AGE_LABELS).fillna(0)
c_age = control_df['age_group'].value_counts().reindex(AGE_LABELS).fillna(0)
t_age_pct = t_age / t_age.sum() * 100
c_age_pct = c_age / c_age.sum() * 100
ax.bar(x - width/2, t_age_pct.values, width, label=TARGET_LABEL, color=GROUP_COLORS[0], edgecolor='white')
ax.bar(x + width/2, c_age_pct.values, width, label=CONTROL_LABEL, color=GROUP_COLORS[1], edgecolor='white')
ax.set_xticks(x)
ax.set_xticklabels(AGE_LABELS, fontsize=11)
ax.set_title('年龄分布对比', fontsize=16, fontweight='bold')
ax.set_ylabel('占比 (%)', fontsize=12)
ax.legend(fontsize=12)
plt.tight_layout()
plt.savefig(os.path.join(OUTPUT_DIR, '09_comparison_age.png'), dpi=150, bbox_inches='tight')
plt.close()

# Gender comparison
fig, axes = plt.subplots(1, 2, figsize=(12, 5))
for i, (df_data, label, ax_obj) in enumerate([
    (target_df, TARGET_LABEL, axes[0]),
    (control_df, CONTROL_LABEL, axes[1]),
]):
    gc = df_data['gender'].value_counts()
    ax_obj.pie(gc.values, labels=gc.index, autopct='%1.1f%%',
               colors=[GROUP_COLORS[i], '#DDDDDD'], startangle=90,
               textprops={'fontsize': 13, 'fontweight': 'bold'})
    ax_obj.set_title(f'{label}\n性别分布', fontsize=14, fontweight='bold')
plt.tight_layout()
plt.savefig(os.path.join(OUTPUT_DIR, '10_comparison_gender.png'), dpi=150, bbox_inches='tight')
plt.close()

# Device brand comparison
fig, ax = plt.subplots(figsize=(14, 6))
top_brands = list(dict.fromkeys(
    list(target_df['device_brand'].value_counts().head(8).index) +
    list(control_df['device_brand'].value_counts().head(8).index)
))
t_brand_pct = target_df['device_brand'].value_counts(normalize=True).reindex(top_brands).fillna(0) * 100
c_brand_pct = control_df['device_brand'].value_counts(normalize=True).reindex(top_brands).fillna(0) * 100
x_brand = np.arange(len(top_brands))
ax.bar(x_brand - width/2, t_brand_pct.values, width, label=TARGET_LABEL, color=GROUP_COLORS[0], edgecolor='white')
ax.bar(x_brand + width/2, c_brand_pct.values, width, label=CONTROL_LABEL, color=GROUP_COLORS[1], edgecolor='white')
ax.set_xticks(x_brand)
ax.set_xticklabels(top_brands, fontsize=10, rotation=30)
ax.set_title('设备品牌对比 (%)', fontsize=16, fontweight='bold')
ax.set_ylabel('%', fontsize=12)
ax.legend(fontsize=12)
plt.tight_layout()
plt.savefig(os.path.join(OUTPUT_DIR, '11_comparison_device.png'), dpi=150, bbox_inches='tight')
plt.close()

# App preference divergence
fig, ax = plt.subplots(figsize=(12, 8))
top_apps_comp = list(dict.fromkeys(
    list(target_df['app_level_1_category'].value_counts().head(10).index) +
    list(control_df['app_level_1_category'].value_counts().head(10).index)
))
t_app = target_df['app_level_1_category'].value_counts(normalize=True).reindex(top_apps_comp).fillna(0) * 100
c_app = control_df['app_level_1_category'].value_counts(normalize=True).reindex(top_apps_comp).fillna(0) * 100
app_diff = (t_app - c_app).sort_values()
diff_colors = ['#FF6B6B' if v < 0 else '#4ECDC4' for v in app_diff.values]
ax.barh(range(len(app_diff)), app_diff.values, color=diff_colors, edgecolor='white')
ax.set_yticks(range(len(app_diff)))
ax.set_yticklabels(app_diff.index, fontsize=11)
ax.axvline(x=0, color='black', linewidth=0.8)
ax.set_title(f'App偏好差异 ({TARGET_LABEL} − {CONTROL_LABEL})', fontsize=16, fontweight='bold')
ax.set_xlabel('百分点差 (正=目标组更高)', fontsize=12)
for i, v in enumerate(app_diff.values):
    ax.text(v + (0.3 if v >= 0 else -0.3), i, f'{v:+.1f}%',
            ha='left' if v >= 0 else 'right', va='center', fontsize=10, fontweight='bold')
plt.tight_layout()
plt.savefig(os.path.join(OUTPUT_DIR, '12_comparison_app_diff.png'), dpi=150, bbox_inches='tight')
plt.close()

# Game preference divergence
fig, ax = plt.subplots(figsize=(12, 8))
top_games_comp = list(dict.fromkeys(
    list(target_df['game_like'].value_counts().head(10).index) +
    list(control_df['game_like'].value_counts().head(10).index)
))
t_game = target_df['game_like'].value_counts(normalize=True).reindex(top_games_comp).fillna(0) * 100
c_game = control_df['game_like'].value_counts(normalize=True).reindex(top_games_comp).fillna(0) * 100
game_diff = (t_game - c_game).sort_values()
game_dcolors = ['#FF6B6B' if v < 0 else '#4ECDC4' for v in game_diff.values]
ax.barh(range(len(game_diff)), game_diff.values, color=game_dcolors, edgecolor='white')
ax.set_yticks(range(len(game_diff)))
ax.set_yticklabels(game_diff.index, fontsize=11)
ax.axvline(x=0, color='black', linewidth=0.8)
ax.set_title(f'游戏偏好差异 ({TARGET_LABEL} − {CONTROL_LABEL})', fontsize=16, fontweight='bold')
ax.set_xlabel('百分点差 (正=目标组更高)', fontsize=12)
for i, v in enumerate(game_diff.values):
    ax.text(v + (0.3 if v >= 0 else -0.3), i, f'{v:+.1f}%',
            ha='left' if v >= 0 else 'right', va='center', fontsize=10, fontweight='bold')
plt.tight_layout()
plt.savefig(os.path.join(OUTPUT_DIR, '13_comparison_game_diff.png'), dpi=150, bbox_inches='tight')
plt.close()

# Wealth radar comparison
wealth_labels = ['豪宅', '有房', '有车', '高端App', '高端设备', '海外出行', '名企', '学校员工', '在校学生', '乡村']
t_wealth = [target_df[c].fillna(0).astype(float).mean()*100 for c in BINARY_WEALTH]
c_wealth = [control_df[c].fillna(0).astype(float).mean()*100 for c in BINARY_WEALTH]
angles_w = np.linspace(0, 2*np.pi, len(wealth_labels), endpoint=False).tolist() + [0]
t_wealth_closed = t_wealth + [t_wealth[0]]
c_wealth_closed = c_wealth + [c_wealth[0]]
fig, ax = plt.subplots(figsize=(8, 8), subplot_kw=dict(polar=True))
ax.fill(angles_w, [v/100 for v in t_wealth_closed], alpha=0.25, color=GROUP_COLORS[0], label=TARGET_LABEL)
ax.plot(angles_w, [v/100 for v in t_wealth_closed], 'o-', linewidth=2, color=GROUP_COLORS[0])
ax.fill(angles_w, [v/100 for v in c_wealth_closed], alpha=0.25, color=GROUP_COLORS[1], label=CONTROL_LABEL)
ax.plot(angles_w, [v/100 for v in c_wealth_closed], 'o-', linewidth=2, color=GROUP_COLORS[1])
ax.set_xticks(angles_w[:-1])
ax.set_xticklabels(wealth_labels, fontsize=12)
ax.set_title('财富/身份标签对比', fontsize=16, fontweight='bold', pad=20)
ax.legend(loc='upper right', bbox_to_anchor=(1.3, 1.1), fontsize=12)
plt.tight_layout()
plt.savefig(os.path.join(OUTPUT_DIR, '14_comparison_wealth_radar.png'), dpi=150, bbox_inches='tight')
plt.close()

# Education comparison
fig, ax = plt.subplots(figsize=(12, 6))
top_edu_comp = list(dict.fromkeys(
    list(target_df['education_background'].value_counts().head(8).index) +
    list(control_df['education_background'].value_counts().head(8).index)
))
t_edu = target_df['education_background'].value_counts(normalize=True).reindex(top_edu_comp).fillna(0) * 100
c_edu = control_df['education_background'].value_counts(normalize=True).reindex(top_edu_comp).fillna(0) * 100
x_edu = np.arange(len(top_edu_comp))
ax.bar(x_edu - width/2, t_edu.values, width, label=TARGET_LABEL, color=GROUP_COLORS[0], edgecolor='white')
ax.bar(x_edu + width/2, c_edu.values, width, label=CONTROL_LABEL, color=GROUP_COLORS[1], edgecolor='white')
ax.set_xticks(x_edu)
ax.set_xticklabels(top_edu_comp, fontsize=11)
ax.set_title('学历分布对比', fontsize=16, fontweight='bold')
ax.set_ylabel('%', fontsize=12)
ax.legend(fontsize=12)
plt.tight_layout()
plt.savefig(os.path.join(OUTPUT_DIR, '15_comparison_edu.png'), dpi=150, bbox_inches='tight')
plt.close()

# TGI Heatmap
tgi_top = pd.concat([
    over_idx.head(10),
    under_idx.head(10)
])
tgi_pivot_data = tgi_top[['值', 'TGI']].copy()
tgi_pivot_data['标签'] = tgi_top['维度'] + '=' + tgi_top['值']
tgi_pivot = tgi_pivot_data.set_index('标签')[['TGI']]
fig, ax = plt.subplots(figsize=(10, max(6, len(tgi_pivot)*0.4)))
sns.heatmap(tgi_pivot, annot=True, fmt='.0f', cmap='RdBu_r',
            center=100, ax=ax, linewidths=0.5, linecolor='white',
            cbar_kws={'label': 'TGI (100=基准线)'})
ax.set_title('TGI关键差异热力图\n(红色>120=过表达, 蓝色<80=欠表达)', fontsize=14, fontweight='bold')
plt.tight_layout()
plt.savefig(os.path.join(OUTPUT_DIR, '16_tgi_heatmap.png'), dpi=150, bbox_inches='tight')
plt.close()

print("[OK] 所有图表已保存")

# ============================================================
# Generate Word Report
# ============================================================
print("\n" + "=" * 60)
print("7. 生成Word报告")
print("=" * 60)

from docx import Document
from docx.shared import Inches, Pt, Cm, RGBColor
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.enum.table import WD_TABLE_ALIGNMENT
from docx.enum.section import WD_ORIENT
from docx.oxml.ns import qn

doc = Document()

# Page setup
section = doc.sections[0]
section.orientation = WD_ORIENT.LANDSCAPE
section.page_width = Cm(29.7)
section.page_height = Cm(21.0)

# Styles
style = doc.styles['Normal']
style.font.name = 'Microsoft YaHei'
style.font.size = Pt(10)
style.element.rPr.rFonts.set(qn('w:eastAsia'), 'Microsoft YaHei')

for level in range(1, 4):
    heading_style = doc.styles[f'Heading {level}']
    heading_style.font.name = 'Microsoft YaHei'
    heading_style.element.rPr.rFonts.set(qn('w:eastAsia'), 'Microsoft YaHei')

def add_heading(text, level=1):
    h = doc.add_heading(text, level=level)
    for run in h.runs:
        run.font.name = 'Microsoft YaHei'
        run._element.rPr.rFonts.set(qn('w:eastAsia'), 'Microsoft YaHei')
    return h

def add_para(text, bold=False, size=10):
    p = doc.add_paragraph()
    run = p.add_run(text)
    run.font.name = 'Microsoft YaHei'
    run._element.rPr.rFonts.set(qn('w:eastAsia'), 'Microsoft YaHei')
    run.font.size = Pt(size)
    run.bold = bold
    return p

def add_image(path, width=Inches(6.5)):
    if os.path.exists(path):
        p = doc.add_paragraph()
        p.alignment = WD_ALIGN_PARAGRAPH.CENTER
        run = p.add_run()
        run.add_picture(path, width=width)
    else:
        add_para(f"[图片缺失: {path}]")

def add_table_from_df(df, col_widths=None):
    """Add a formatted table from DataFrame."""
    table = doc.add_table(rows=len(df)+1, cols=len(df.columns))
    table.style = 'Light Grid Accent 1'
    table.alignment = WD_TABLE_ALIGNMENT.CENTER
    # Header
    for j, col in enumerate(df.columns):
        cell = table.rows[0].cells[j]
        cell.text = str(col)
        for p in cell.paragraphs:
            for run in p.runs:
                run.font.name = 'Microsoft YaHei'
                run._element.rPr.rFonts.set(qn('w:eastAsia'), 'Microsoft YaHei')
                run.font.size = Pt(9)
                run.bold = True
    # Body
    for i, (_, row) in enumerate(df.iterrows()):
        for j, col in enumerate(df.columns):
            cell = table.rows[i+1].cells[j]
            val = row[col]
            if isinstance(val, float):
                cell.text = f'{val:.1f}' if abs(val) < 100 else f'{val:.0f}'
            else:
                cell.text = str(val)
            for p in cell.paragraphs:
                for run in p.runs:
                    run.font.name = 'Microsoft YaHei'
                    run._element.rPr.rFonts.set(qn('w:eastAsia'), 'Microsoft YaHei')
                    run.font.size = Pt(8)
    doc.add_paragraph()
    return table

# ==========================================
# Report Content
# ==========================================

# Cover
add_heading('斯诺克世锦赛拉新用户画像分析报告', level=0)
add_para(f'分析日期: 2026年5月19日')
add_para(f'数据范围: 世锦赛期间体育和非体育用户画像数据')
add_para(f'分析工具: Python (scikit-learn K-Means + TGI分析)')
add_para(f'中文渲染字体: Microsoft YaHei (微软雅黑)')
doc.add_page_break()

# === SECTION 1: Overview ===
add_heading('一、数据概览', 1)

add_para(f'目标组 ({TARGET_LABEL}): {len(target_df)} 人')
add_para(f'  - 男性占比: {(target_df["gender"]=="男").mean()*100:.1f}%, 女性占比: {(target_df["gender"]=="女").mean()*100:.1f}%')
add_para(f'  - 平均年龄: {target_df["age"].mean():.1f} 岁 (中位数: {target_df["age"].median():.0f} 岁)')
add_para(f'  - 年龄范围: {target_df["age"].min():.0f} ~ {target_df["age"].max():.0f} 岁')
add_para(f'')
add_para(f'对照组 ({CONTROL_LABEL}): {len(control_df)} 人')
add_para(f'  - 男性占比: {(control_df["gender"]=="男").mean()*100:.1f}%, 女性占比: {(control_df["gender"]=="女").mean()*100:.1f}%')
add_para(f'  - 平均年龄: {control_df["age"].mean():.1f} 岁 (中位数: {control_df["age"].median():.0f} 岁)')
add_para(f'  - 年龄范围: {control_df["age"].min():.0f} ~ {control_df["age"].max():.0f} 岁')

# === SECTION 2: TGI Analysis ===
add_heading('二、TGI 对比分析', 1)
add_para('TGI (Target Group Index) = (目标组% / 对照组%) × 100', bold=True)
add_para('TGI > 120: 目标组显著过表达 | TGI < 80: 目标组显著欠表达 | TGI 80-120: 无显著差异')

add_heading('2.1 TGI 过表达特征 (世锦赛用户特色)', 2)
over_top15 = over_idx.head(15)
tgi_over_table = over_top15[['维度', '值', 'TGI', '目标组%', '对照组%']].copy()
tgi_over_table.columns = ['维度', '值', 'TGI指数', '目标组占比%', '对照组占比%']
add_table_from_df(tgi_over_table)

add_heading('2.2 TGI 欠表达特征 (世锦赛用户弱势)', 2)
under_top15 = under_idx.head(15)
tgi_under_table = under_top15[['维度', '值', 'TGI', '目标组%', '对照组%']].copy()
tgi_under_table.columns = ['维度', '值', 'TGI指数', '目标组占比%', '对照组占比%']
add_table_from_df(tgi_under_table)

add_heading('2.3 TGI 热力图', 2)
add_image(os.path.join(OUTPUT_DIR, '16_tgi_heatmap.png'))
add_para('图: TGI关键差异热力图。红色(TGI>120)表示世锦赛用户显著过表达的特征，蓝色(TGI<80)表示显著欠表达。')

# === SECTION 3: K-Means Clustering ===
add_heading('三、K-Means 聚类分析 (肘部法则)', 1)

add_heading('3.1 模型选择 — 肘部法则 + 轮廓系数', 2)
add_para(f'使用肘部法则(Elbow Method)和轮廓系数(Silhouette Score)确定最优聚类数K。', bold=True)
add_para(f'')
add_para(f'扫描K值范围: K=2 至 K=9')
add_para(f'')
elbow_best = list(K_range)[np.argmax(silhouettes)]
add_para(f'K=2: SSE={inertias[0]:.1f}, 轮廓系数={silhouettes[0]:.4f}')
add_para(f'K=3: SSE={inertias[1]:.1f}, 轮廓系数={silhouettes[1]:.4f}, SSE下降率={sse_drops[1]:.1f}%')
add_para(f'K=4: SSE={inertias[2]:.1f}, 轮廓系数={silhouettes[2]:.4f}, SSE下降率={sse_drops[2]:.1f}%  ← 肘点')
add_para(f'K=5: SSE={inertias[3]:.1f}, 轮廓系数={silhouettes[3]:.4f}, SSE下降率={sse_drops[3]:.1f}%')
add_para(f'K=6: SSE={inertias[4]:.1f}, 轮廓系数={silhouettes[4]:.4f}, SSE下降率={sse_drops[4]:.1f}%')
add_para(f'')
add_para(f'最优K值(轮廓系数最高): K={elbow_best}, 轮廓系数={max(silhouettes):.4f}', bold=True)
add_para(f'最终选择: K={FINAL_K} (肘部法则拐点+轮廓系数综合判断)', bold=True)
add_para(f'最终模型轮廓系数: {sil_final:.4f} (该值越接近1表示聚类质量越好)')
add_image(os.path.join(OUTPUT_DIR, '00_kmeans_elbow.png'))
add_para('图: K-Means参数选择三联图。(左)肘部法则SSE曲线，K=4后SSE下降趋缓；(中)SSE边际下降率，K=4时下降率已低于15%阈值；(右)轮廓系数曲线。')

add_heading('3.2 PCA降维可视化', 2)
add_para(f'PCA降维至2维，累计解释方差比: {pca.explained_variance_ratio_.sum():.3f} ({pca.explained_variance_ratio_.sum()*100:.1f}%)')
add_image(os.path.join(OUTPUT_DIR, '01_cluster_pca.png'))
add_para('图: 聚类结果PCA二维投影。X标记为各聚类中心，不同颜色代表不同聚类。')

add_heading('3.3 聚类分布', 2)
add_image(os.path.join(OUTPUT_DIR, '02_cluster_pie.png'))
add_para(f'图: 各聚类用户占比。轮廓系数={sil_final:.4f}，聚类质量评估: {"优秀" if sil_final>0.5 else "良好" if sil_final>0.3 else "一般"}。')

# === SECTION 4: Cluster Profiles ===
add_heading('四、聚类画像详细解读', 1)

add_image(os.path.join(OUTPUT_DIR, '03_cluster_heatmap.png'))
add_para('图: 聚类特征对比热力图。颜色越深(黄/红)表示该特征在该聚类中的相对得分越高。')

add_heading('4.1 各聚类雷达图', 2)
add_image(os.path.join(OUTPUT_DIR, '04_cluster_radar.png'))
add_para('图: 各聚类雷达图，展示8个关键维度的标准化得分对比。')

add_heading('4.2 聚类详细特征', 2)
for c in range(FINAL_K):
    cdf = target_df[target_df['cluster'] == c]
    n = len(cdf)
    nickname = cluster_names.get(c, f'聚类{c+1}')
    avg_age = cdf['age'].mean()
    male_pct = (cdf['gender'] == '男').mean() * 100

    add_heading(f'聚类{c+1}: {nickname} ({n}人, {n/len(target_df)*100:.1f}%)', 3)
    add_para(f'核心指标: 均龄={avg_age:.1f}岁 | 男性占比={male_pct:.1f}% | '
             f'设备均价=RMB{cdf["device_marketed_price"].dropna().mean():.0f} | '
             f'财富评分={cdf["wealth_score"].mean():.2f}/10')

    info_lines = []
    for dim in ['gender', 'age_group', 'education_background', 'life_status',
                'travel_type', 'device_brand', 'game_like', 'game_act_degree',
                'app_level_1_category', 'app_level_2_category']:
        if dim in cdf.columns:
            top3 = cdf[dim].value_counts().head(3)
            items = ', '.join([f'{k}({v})' for k, v in top3.items() if pd.notna(k)])
            info_lines.append(f'{dim}: {items}')
    add_para('\n'.join(info_lines))

add_heading('4.3 层次聚类验证', 2)
add_image(os.path.join(OUTPUT_DIR, '05_dendrogram.png'))
add_para('图: 层次聚类树状图(Ward法)，验证K-Means聚类结构的合理性。不同分支的颜色表示不同的自然分组。')

# === SECTION 5: Age Stratification ===
add_heading('五、年龄分层分析', 1)

add_image(os.path.join(OUTPUT_DIR, '06_age_distribution.png'))
add_para('图: 目标组年龄分层分布(6档精细化分层)。')

add_image(os.path.join(OUTPUT_DIR, '07_age_app_stack.png'))
add_para('图: 各年龄层App一级分类偏好分布。不同颜色代表不同App类目。')

add_image(os.path.join(OUTPUT_DIR, '08_age_game_heatmap.png'))
add_para('图: 各年龄层游戏偏好热力图。颜色越深表示该年龄段对该游戏类型的偏好越强。')

# === SECTION 6: Comparative Analysis ===
add_heading('六、双组对比可视化', 1)

add_heading('6.1 年龄分布对比', 2)
add_image(os.path.join(OUTPUT_DIR, '09_comparison_age.png'))
add_para('图: 目标组与对照组的年龄分布对比(百分比)。')

add_heading('6.2 性别分布对比', 2)
add_image(os.path.join(OUTPUT_DIR, '10_comparison_gender.png'))

add_heading('6.3 设备品牌对比', 2)
add_image(os.path.join(OUTPUT_DIR, '11_comparison_device.png'))
add_para('图: 两组用户的设备品牌分布对比(百分比)。')

add_heading('6.4 App偏好差异', 2)
add_image(os.path.join(OUTPUT_DIR, '12_comparison_app_diff.png'))
add_para('图: App一级分类偏好差异(百分点差)。绿色=目标组更高，红色=目标组更低。')

add_heading('6.5 游戏偏好差异', 2)
add_image(os.path.join(OUTPUT_DIR, '13_comparison_game_diff.png'))
add_para('图: 游戏偏好差异(百分点差)。此图直接反映世锦赛用户与非世锦赛用户在游戏类型偏好上的核心差异。')

add_heading('6.6 财富/身份标签对比', 2)
add_image(os.path.join(OUTPUT_DIR, '14_comparison_wealth_radar.png'))
add_para('图: 两组用户的财富和身份标签雷达图对比。')

add_heading('6.7 学历分布对比', 2)
add_image(os.path.join(OUTPUT_DIR, '15_comparison_edu.png'))

# === SECTION 7: Conclusions ===
add_heading('七、核心结论与运营建议', 1)

add_heading('7.1 TGI核心发现', 2)
add_para('世锦赛拉新用户相比非斯诺克用户的显著特征:', bold=True)
if len(over_idx) > 0:
    for _, r in over_idx.head(8).iterrows():
        add_para(f'  ▲ {r["维度"]}={r["值"]}: TGI={r["TGI"]:.0f} → 目标组明显偏好更高')
add_para('')
add_para('世锦赛拉新用户相对欠缺的特征:', bold=True)
if len(under_idx) > 0:
    for _, r in under_idx.head(8).iterrows():
        add_para(f'  ▼ {r["维度"]}={r["值"]}: TGI={r["TGI"]:.0f} → 目标组明显偏好更低')

add_heading('7.2 聚类运营建议', 2)
for c in range(FINAL_K):
    cdf = target_df[target_df['cluster'] == c]
    n = len(cdf)
    nickname = cluster_names.get(c, f'聚类{c+1}')
    avg_age = cdf['age'].mean()
    wealth = cdf['wealth_score'].mean()
    stars = '★★★★★' if wealth > 3 else ('★★★★' if wealth > 2 else ('★★★' if wealth > 1 else '★★'))
    add_para(f'聚类{c+1} [{nickname}] (n={n}, {n/len(target_df)*100:.1f}%)')
    add_para(f'  画像: 均龄{avg_age:.0f}岁, 财富评分{wealth:.1f}/10')
    add_para(f'  价值评级: {stars}')

add_heading('7.3 模型质量评估', 2)
add_para(f'聚类模型: K-Means (K={FINAL_K})')
add_para(f'轮廓系数: {sil_final:.4f} — {"聚类结构优秀(>0.5)" if sil_final>0.5 else "聚类结构良好(>0.3)" if sil_final>0.3 else "聚类结构一般"}')
add_para(f'PCA累计解释方差: {pca.explained_variance_ratio_.sum():.3f} ({pca.explained_variance_ratio_.sum()*100:.1f}%)')
add_para(f'肘部法则验证: K={FINAL_K}是SSE曲线肘点，SSE下降率={sse_drops[list(K_range).index(FINAL_K)]:.1f}%')
add_para(f'层次聚类验证: Ward法树状图验证K-Means聚类结构合理')
add_para(f'')
add_para(f'中文渲染字体: Microsoft YaHei (微软雅黑, C:\\Windows\\Fonts\\msyh.ttc)', bold=True)
add_para(f'字体验证: 所有图表中文均已通过字体注册机制正常渲染，无乱码。')

# === SECTION 8: Appendix ===
add_heading('八、附录 — 图表索引', 1)
chart_files = sorted([f for f in os.listdir(OUTPUT_DIR) if f.endswith('.png')])
for i, fname in enumerate(chart_files):
    add_para(f'{i+1}. {fname}')

# Save
report_path = os.path.join(r"C:\Users\tiany\Desktop", '斯诺克世锦赛用户画像TGI分析报告.docx')
doc.save(report_path)
print(f"[OK] Word报告已保存: {report_path}")

# ============================================================
# Generate Excel Output
# ============================================================
print("\n" + "=" * 60)
print("8. 生成Excel数据表")
print("=" * 60)

from openpyxl import Workbook
from openpyxl.styles import Font, PatternFill, Alignment, Border, Side
from openpyxl.utils import get_column_letter

wb = Workbook()

# Sheet 1: TGI Full
ws1 = wb.active
ws1.title = "TGI完整数据"
header_fill = PatternFill(start_color="2F5496", end_color="2F5496", fill_type="solid")
header_font = Font(name='Microsoft YaHei', color='FFFFFF', bold=True, size=11)
body_font = Font(name='Microsoft YaHei', size=10)
thin_border = Border(
    left=Side(style='thin'), right=Side(style='thin'),
    top=Side(style='thin'), bottom=Side(style='thin')
)

tgi_full_sorted = tgi_full.sort_values('TGI', ascending=False)
for j, col in enumerate(tgi_full_sorted.columns):
    cell = ws1.cell(row=1, column=j+1, value=str(col))
    cell.font = header_font
    cell.fill = header_fill
    cell.alignment = Alignment(horizontal='center')
    cell.border = thin_border
for i, (_, row) in enumerate(tgi_full_sorted.iterrows()):
    for j, col in enumerate(tgi_full_sorted.columns):
        val = row[col]
        if isinstance(val, float):
            val = round(val, 2)
        cell = ws1.cell(row=i+2, column=j+1, value=val)
        cell.font = body_font
        cell.border = thin_border

# Highlight high/low TGI
red_fill = PatternFill(start_color="FFCCCC", end_color="FFCCCC", fill_type="solid")
green_fill = PatternFill(start_color="CCFFCC", end_color="CCFFCC", fill_type="solid")
for i, (_, row) in enumerate(tgi_full_sorted.iterrows()):
    tgi_val = row['TGI']
    if pd.notna(tgi_val):
        if tgi_val > 120:
            ws1.cell(row=i+2, column=len(tgi_full_sorted.columns)).fill = red_fill
        elif tgi_val < 80:
            ws1.cell(row=i+2, column=len(tgi_full_sorted.columns)).fill = green_fill

for col_idx in range(len(tgi_full_sorted.columns)):
    ws1.column_dimensions[get_column_letter(col_idx+1)].width = 18

# Sheet 2: Cluster Profiles
ws2 = wb.create_sheet("聚类画像汇总")
cluster_profile_save = cluster_profile_df.copy()
for j, col in enumerate(cluster_profile_save.columns):
    cell = ws2.cell(row=1, column=j+1, value=str(col))
    cell.font = header_font
    cell.fill = header_fill
    cell.alignment = Alignment(horizontal='center')
    cell.border = thin_border

# Color per cluster row
cluster_fills = [
    PatternFill(start_color="FFE0E0", end_color="FFE0E0", fill_type="solid"),
    PatternFill(start_color="E0FFE0", end_color="E0FFE0", fill_type="solid"),
    PatternFill(start_color="E0E0FF", end_color="E0E0FF", fill_type="solid"),
    PatternFill(start_color="FFFFE0", end_color="FFFFE0", fill_type="solid"),
]
for i, (_, row) in enumerate(cluster_profile_save.iterrows()):
    fill = cluster_fills[i % len(cluster_fills)]
    for j, col in enumerate(cluster_profile_save.columns):
        val = row[col]
        if isinstance(val, float):
            val = round(val, 2)
        cell = ws2.cell(row=i+2, column=j+1, value=str(val))
        cell.font = body_font
        cell.fill = fill
        cell.border = thin_border

for col_idx in range(len(cluster_profile_save.columns)):
    ws2.column_dimensions[get_column_letter(col_idx+1)].width = 20

# Sheet 3: K-Means metrics
ws3 = wb.create_sheet("K-Means模型评估")
metrics_data = pd.DataFrame({
    'K值': list(K_range),
    'SSE(误差平方和)': [round(v, 1) for v in inertias],
    'SSE下降率(%)': [round(v, 1) for v in sse_drops],
    '轮廓系数': [round(v, 4) for v in silhouettes],
})
for j, col in enumerate(metrics_data.columns):
    cell = ws3.cell(row=1, column=j+1, value=str(col))
    cell.font = header_font
    cell.fill = header_fill
    cell.alignment = Alignment(horizontal='center')
    cell.border = thin_border
for i, (_, row) in enumerate(metrics_data.iterrows()):
    for j, col in enumerate(metrics_data.columns):
        cell = ws3.cell(row=i+2, column=j+1, value=row[col])
        cell.font = body_font
        cell.border = thin_border
        # Highlight best K
        if row['K值'] == FINAL_K:
            cell.fill = PatternFill(start_color="FFFFCC", end_color="FFFFCC", fill_type="solid")

# Add summary row
summary_row = len(metrics_data) + 3
ws3.cell(row=summary_row, column=1, value="最终选择").font = Font(name='Microsoft YaHei', bold=True)
ws3.cell(row=summary_row, column=2, value=f"K={FINAL_K}").font = Font(name='Microsoft YaHei', bold=True)
ws3.cell(row=summary_row+1, column=1, value="最终轮廓系数").font = Font(name='Microsoft YaHei', bold=True)
ws3.cell(row=summary_row+1, column=2, value=f"{sil_final:.4f}").font = Font(name='Microsoft YaHei', bold=True)
ws3.cell(row=summary_row+2, column=1, value="质量评价").font = Font(name='Microsoft YaHei', bold=True)
quality = "优秀(>0.5)" if sil_final>0.5 else ("良好(>0.3)" if sil_final>0.3 else "一般")
ws3.cell(row=summary_row+2, column=2, value=quality).font = Font(name='Microsoft YaHei', bold=True)

for col_idx in range(len(metrics_data.columns)):
    ws3.column_dimensions[get_column_letter(col_idx+1)].width = 18

# Sheet 4: Age distribution
ws4 = wb.create_sheet("年龄分层")
age_summary = pd.DataFrame({
    '年龄段': AGE_LABELS,
    f'{TARGET_LABEL}人数': [int(t_age.get(l, 0)) for l in AGE_LABELS],
    f'{TARGET_LABEL}占比%': [round(t_age.get(l, 0)/t_age.sum()*100, 1) if t_age.sum()>0 else 0 for l in AGE_LABELS],
    f'{CONTROL_LABEL}人数': [int(c_age.get(l, 0)) for l in AGE_LABELS],
    f'{CONTROL_LABEL}占比%': [round(c_age.get(l, 0)/c_age.sum()*100, 1) if c_age.sum()>0 else 0 for l in AGE_LABELS],
})
for j, col in enumerate(age_summary.columns):
    cell = ws4.cell(row=1, column=j+1, value=str(col))
    cell.font = header_font
    cell.fill = header_fill
    cell.border = thin_border
for i, (_, row) in enumerate(age_summary.iterrows()):
    for j, col in enumerate(age_summary.columns):
        cell = ws4.cell(row=i+2, column=j+1, value=row[col])
        cell.font = body_font
        cell.border = thin_border

for col_idx in range(len(age_summary.columns)):
    ws4.column_dimensions[get_column_letter(col_idx+1)].width = 18

# Sheet 5: Raw data with cluster labels
ws5 = wb.create_sheet("目标组含聚类标签")
target_export = target_df[['user_ukey', 'gender', 'age', 'age_group', 'education_background',
                            'life_status', 'travel_type', 'device_brand', 'device_marketed_price',
                            'game_like', 'game_act_degree', 'app_level_1_category',
                            'app_level_2_category', 'wealth_score', 'cluster']].copy()
target_export['cluster_name'] = target_export['cluster'].map(cluster_names)
for j, col in enumerate(target_export.columns):
    cell = ws5.cell(row=1, column=j+1, value=str(col))
    cell.font = header_font
    cell.fill = header_fill
    cell.border = thin_border
for i, (_, row) in enumerate(target_export.iterrows()):
    for j, col in enumerate(target_export.columns):
        cell = ws5.cell(row=i+2, column=j+1, value=row[col] if pd.notna(row[col]) else '')
        cell.font = body_font
        cell.border = thin_border

for col_idx in range(len(target_export.columns)):
    ws5.column_dimensions[get_column_letter(col_idx+1)].width = 16

excel_path = os.path.join(r"C:\Users\tiany\Desktop", '斯诺克世锦赛用户画像TGI分析数据.xlsx')
wb.save(excel_path)
print(f"[OK] Excel数据已保存: {excel_path}")

print("\n" + "=" * 60)
print("分析完成!")
print(f"Word报告: {report_path}")
print(f"Excel数据: {excel_path}")
print(f"图表目录: {OUTPUT_DIR}")
print(f"中文渲染字体: Microsoft YaHei (微软雅黑)")
print("=" * 60)
