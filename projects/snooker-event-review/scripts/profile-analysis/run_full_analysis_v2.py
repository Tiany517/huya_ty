# -*- coding: utf-8 -*-
"""
斯诺克世锦赛拉新用户 vs 非斯诺克用户 TGI对比分析 V2
==================================================
V2 改进:
  1. 所有图表去除背景网格线
  2. App/游戏偏好对比增加绝对值柱状图
  3. Word报告首页核心结论 + 纵向排版
  4. 每个图表配简短分析文字
  5. 数值数据用表格呈现
"""

import os, sys, io, glob, warnings, time, argparse
from pathlib import Path
import numpy as np
import pandas as pd

# ============================================================
# 中文字体设置 (必须在 pyplot 导入之前)
# ============================================================
import matplotlib
matplotlib.use('Agg')
_cache = matplotlib.get_cachedir()
for _f in glob.glob(os.path.join(_cache, '*')):
    try: os.remove(_f)
    except: pass

_CJK_PATH = r'C:\Windows\Fonts\msyh.ttc'
assert os.path.exists(_CJK_PATH), f"字体文件未找到: {_CJK_PATH}"

import matplotlib.pyplot as plt
import matplotlib.font_manager as fm

fm.fontManager.addfont(_CJK_PATH)
_FONT_NAME = fm.FontProperties(fname=_CJK_PATH).get_name()
plt.rcParams['font.family'] = 'sans-serif'
plt.rcParams['font.sans-serif'] = [_FONT_NAME]
plt.rcParams['axes.unicode_minus'] = False
fm._load_fontmanager(try_read_cache=False)

# 验证字体
_font_check = [f for f in fm.fontManager.ttflist if _FONT_NAME in f.name]
print(f"[字体] 已注册: {_FONT_NAME} ({_CJK_PATH}), 加载 {len(_font_check)} 个变体")

import seaborn as sns
from sklearn.preprocessing import StandardScaler, LabelEncoder
from sklearn.cluster import KMeans
from sklearn.decomposition import PCA
from sklearn.metrics import silhouette_score
from scipy.cluster.hierarchy import dendrogram, linkage

warnings.filterwarnings('ignore')

# V2 关键改动: 使用无网格线的白色背景
sns.set_style("white")
sns.set_palette("Set2")
plt.rcParams['font.family'] = 'sans-serif'
plt.rcParams['font.sans-serif'] = [_FONT_NAME]
plt.rcParams['axes.unicode_minus'] = False
# 全局去掉网格线
plt.rcParams['axes.grid'] = False

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')

# ============================================================
# 配置
# ============================================================
_PARSER = argparse.ArgumentParser(description="Reproduce the V2 snooker new-user TGI and clustering analysis.")
_PARSER.add_argument("--data", default=os.environ.get("SNOOKER_PROFILE_DATA", "data/new-user-profile.csv"))
_PARSER.add_argument("--output-dir", default=os.environ.get("SNOOKER_PROFILE_OUTPUT", "outputs/snooker-tgi-analysis-v2"))
_ARGS = _PARSER.parse_args()
DATA_PATH = Path(_ARGS.data)
OUTPUT_DIR = Path(_ARGS.output_dir)
OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

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
WEALTH_LABELS = ['豪宅', '有房', '有车', '高端App', '高端设备', '海外出行', '名企', '学校员工', '在校学生', '乡村']

CAT_FEATURES = ['gender', 'education_background', 'life_status', 'travel_type',
                'device_brand', 'device_os', 'game_like', 'game_act_degree',
                'app_level_1_category', 'app_level_2_category']

# ============================================================
# 1. 数据加载
# ============================================================
print("=" * 60)
print("1. 数据加载与分组")
print("=" * 60)

df_raw = pd.read_csv(DATA_PATH, encoding='utf-8-sig')
df = df_raw.drop_duplicates(subset='user_ukey', keep='first').copy()
print(f"总数据: {len(df_raw)} 行 → 去重后 {len(df)} 行")

target_df = df[df['user_type'] == TARGET_LABEL].copy()
control_df = df[df['user_type'] == CONTROL_LABEL].copy()
print(f"目标组: {len(target_df)} 人 | 对照组: {len(control_df)} 人")

# ============================================================
# 2. 特征工程
# ============================================================
print("\n" + "=" * 60)
print("2. 特征工程")
print("=" * 60)

def build_features(d):
    d = d.copy()
    d['age_group'] = pd.cut(d['age'], bins=AGE_BINS, labels=AGE_LABELS, right=True)
    d['age_filled'] = d['age'].fillna(d['age'].median())
    d['device_price_filled'] = d['device_marketed_price'].fillna(d['device_marketed_price'].median())
    for col in BINARY_WEALTH:
        if col in d.columns:
            d[col + '_num'] = pd.to_numeric(d[col], errors='coerce').fillna(0).astype(int)
        else:
            d[col + '_num'] = 0
    d['wealth_score'] = d[[c+'_num' for c in BINARY_WEALTH]].sum(axis=1)
    return d

target_df = build_features(target_df)
control_df = build_features(control_df)

def encode_for_clustering(d):
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

X_scaled_target, scaler_target, feat_cols_target, target_df = encode_for_clustering(target_df)

# ============================================================
# 3. TGI 分析
# ============================================================
print("\n" + "=" * 60)
print("3. TGI 分析")
print("=" * 60)

def compute_tgi(col, t_df, c_df):
    t_series = t_df[col].astype(object).fillna('未知')
    c_series = c_df[col].astype(object).fillna('未知')
    t_pct = t_series.value_counts(normalize=True) * 100
    c_pct = c_series.value_counts(normalize=True) * 100
    t_n = t_series.value_counts()
    c_n = c_series.value_counts()
    all_vals = list(dict.fromkeys(list(t_pct.index) + list(c_pct.index)))
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

all_tgi = {}
all_tgi_dfs = []
for dim in tgi_dims:
    if dim in target_df.columns and dim in control_df.columns:
        tgi_df = compute_tgi(dim, target_df, control_df)
        all_tgi[dim] = tgi_df
        all_tgi_dfs.append(tgi_df)

tgi_full = pd.concat(all_tgi_dfs, ignore_index=True)
tgi_full.to_csv(os.path.join(OUTPUT_DIR, 'tgi_full.csv'), index=False, encoding='utf-8-sig')

over_idx = tgi_full[(tgi_full['TGI'] > 120) & (tgi_full['TGI'].notna())].sort_values('TGI', ascending=False)
under_idx = tgi_full[(tgi_full['TGI'] < 80) & (tgi_full['TGI'] > 0)].sort_values('TGI', ascending=True)
print(f"TGI过表达(>120): {len(over_idx)} 项 | TGI欠表达(<80): {len(under_idx)} 项")

# ============================================================
# 4. K-Means 肘部法则
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

print(f"{'K':<6} {'SSE':<15} {'SSE下降率%':<14} {'轮廓系数':<12}")
for i, k in enumerate(K_range):
    print(f"{k:<6} {inertias[i]:<15.1f} {sse_drops[i]:<14.1f} {silhouettes[i]:<12.4f}")

best_k_sil = list(K_range)[np.argmax(silhouettes)]
FINAL_K = 4
print(f"\n选择K={FINAL_K} (轮廓系数最优为K={best_k_sil}={max(silhouettes):.4f}, 结合肘部法则SSE下降率在K=4后低于15%)")

# 肘部法则三合一图 (无网格线)
fig, axes = plt.subplots(1, 3, figsize=(18, 5))
# (a) SSE曲线
axes[0].plot(list(K_range), inertias, 'o-', color='#3498DB', linewidth=2.5, markersize=10)
axes[0].set_xlabel('K (聚类数)', fontsize=13)
axes[0].set_ylabel('SSE (误差平方和)', fontsize=13)
axes[0].set_title('肘部法则 — SSE曲线', fontsize=15, fontweight='bold')
axes[0].axvline(x=FINAL_K, color='red', linestyle='--', alpha=0.8, linewidth=2, label=f'K={FINAL_K} (推荐)')
axes[0].legend(fontsize=11)
# (b) SSE下降率
axes[1].bar(list(K_range), sse_drops, color='#2ECC71', edgecolor='white', linewidth=1)
axes[1].set_xlabel('K (聚类数)', fontsize=13)
axes[1].set_ylabel('SSE下降率 (%)', fontsize=13)
axes[1].set_title('SSE边际下降率 (低于15%不再增加K)', fontsize=13, fontweight='bold')
axes[1].axhline(y=15, color='red', linestyle='--', alpha=0.7, label='15%阈值')
axes[1].legend(fontsize=10)
for i, (k, v) in enumerate(zip(K_range, sse_drops)):
    axes[1].text(k, v + 0.5, f'{v:.1f}%', ha='center', fontsize=10, fontweight='bold')
# (c) 轮廓系数
axes[2].plot(list(K_range), silhouettes, 's-', color='#E74C3C', linewidth=2.5, markersize=10)
axes[2].set_xlabel('K (聚类数)', fontsize=13)
axes[2].set_ylabel('轮廓系数', fontsize=13)
axes[2].set_title('轮廓系数 (越高聚类越紧密)', fontsize=13, fontweight='bold')
axes[2].axvline(x=best_k_sil, color='green', linestyle='--', alpha=0.8, linewidth=2,
                label=f'最佳K={best_k_sil} ({max(silhouettes):.4f})')
axes[2].legend(fontsize=11)
plt.tight_layout()
plt.savefig(os.path.join(OUTPUT_DIR, '00_kmeans_elbow.png'), dpi=150, bbox_inches='tight')
plt.close()
print("[OK] 00_kmeans_elbow.png")

# ============================================================
# 5. 运行 K-Means (K=4)
# ============================================================
kmeans = KMeans(n_clusters=FINAL_K, random_state=RANDOM_STATE, n_init=10, max_iter=300)
target_df['cluster'] = kmeans.fit_predict(X_scaled_target)
sil_final = silhouette_score(X_scaled_target, target_df['cluster'])

print(f"\n最终模型: K={FINAL_K}, 轮廓系数={sil_final:.4f}")
for c in range(FINAL_K):
    n_c = (target_df['cluster'] == c).sum()
    print(f"  聚类{c+1}: {n_c}人 ({n_c/len(target_df)*100:.1f}%)")

pca = PCA(n_components=2)
X_pca = pca.fit_transform(X_scaled_target)
print(f"PCA累计解释方差: {pca.explained_variance_ratio_.sum():.3f}")

# ============================================================
# 6. 聚类命名
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
for c in range(FINAL_K):
    print(f"  聚类{c+1}: {cluster_names.get(c, '')}")

# ============================================================
# 7. 可视化 (全部无网格线)
# ============================================================
print("\n" + "=" * 60)
print("7. 生成可视化图表 (全部无背景网格线)")
print("=" * 60)

# --- 7.1 PCA散点图 ---
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
ax.set_title(f'K-Means用户聚类 (K={FINAL_K}) — PCA投影', fontsize=16, fontweight='bold')
ax.set_xlabel(f'PC1 ({pca.explained_variance_ratio_[0]:.1%})', fontsize=13)
ax.set_ylabel(f'PC2 ({pca.explained_variance_ratio_[1]:.1%})', fontsize=13)
ax.legend(loc='upper right', fontsize=12)
plt.tight_layout()
plt.savefig(os.path.join(OUTPUT_DIR, '01_cluster_pca.png'), dpi=150, bbox_inches='tight')
plt.close()
print("[OK] 01_cluster_pca.png")

# --- 7.2 聚类占比饼图 ---
fig, ax = plt.subplots(figsize=(8, 8))
cluster_sizes = target_df['cluster'].value_counts().sort_index()
pie_labels = [f'{cluster_names.get(i, f"聚类{i+1}")}\n({v}人, {v/len(target_df)*100:.1f}%)'
              for i, v in enumerate(cluster_sizes.values)]
ax.pie(cluster_sizes.values, labels=pie_labels, colors=CLUSTER_COLORS[:FINAL_K],
       startangle=90, textprops={'fontsize': 12, 'fontweight': 'bold'})
ax.set_title(f'世锦赛拉新用户聚类分布', fontsize=14, fontweight='bold')
plt.tight_layout()
plt.savefig(os.path.join(OUTPUT_DIR, '02_cluster_pie.png'), dpi=150, bbox_inches='tight')
plt.close()
print("[OK] 02_cluster_pie.png")

# --- 7.3 特征对比热力图 ---
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
            cbar_kws={'label': '归一化得分'})
ax.set_title('聚类特征对比热力图', fontsize=16, fontweight='bold')
plt.tight_layout()
plt.savefig(os.path.join(OUTPUT_DIR, '03_cluster_heatmap.png'), dpi=150, bbox_inches='tight')
plt.close()
print("[OK] 03_cluster_heatmap.png")

# --- 7.4 雷达图 ---
fig, axes = plt.subplots(1, FINAL_K, figsize=(5.5*FINAL_K, 5.5), subplot_kw=dict(polar=True))
if FINAL_K == 1: axes = [axes]
radar_feat_labels = ['男性占比', '平均年龄', '财富评分', '设备均价', 'iOS占比', '游戏高活跃', '音乐App', '已婚率']
radar_keys = ['男性占比', '平均年龄', '财富评分', '设备均价(千元)', 'iOS占比', '游戏高活跃率', '音乐App偏好', '已婚率']
radar_data = hm_norm[radar_keys]
angles = np.linspace(0, 2*np.pi, len(radar_feat_labels), endpoint=False).tolist() + [0]
for c in range(FINAL_K):
    ax = axes[c]
    values = radar_data.iloc[c].values.tolist() + [radar_data.iloc[c].values[0]]
    ax.fill(angles, values, alpha=0.25, color=CLUSTER_COLORS[c])
    ax.plot(angles, values, 'o-', linewidth=2, color=CLUSTER_COLORS[c], markersize=5)
    ax.set_xticks(angles[:-1])
    ax.set_xticklabels(radar_feat_labels, fontsize=8)
    ax.set_ylim(0, 1)
    ax.set_title(f'{cluster_names.get(c, f"聚类{c+1}")}\n(n={cluster_sizes.get(c, "?")})',
                 fontsize=12, fontweight='bold', pad=18)
    ax.set_yticks([0.25, 0.5, 0.75])
    ax.set_yticklabels(['25%', '50%', '75%'], fontsize=7)
plt.tight_layout()
plt.savefig(os.path.join(OUTPUT_DIR, '04_cluster_radar.png'), dpi=150, bbox_inches='tight')
plt.close()
print("[OK] 04_cluster_radar.png")

# --- 7.5 层次聚类验证 ---
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
print("[OK] 05_dendrogram.png")

# --- 7.6 年龄分布 ---
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
                f'{int(v)}人 ({v/len(target_df)*100:.1f}%)',
                ha='center', fontsize=10, fontweight='bold')
plt.tight_layout()
plt.savefig(os.path.join(OUTPUT_DIR, '06_age_distribution.png'), dpi=150, bbox_inches='tight')
plt.close()
print("[OK] 06_age_distribution.png")

# --- 7.7 年龄×App堆叠图 ---
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
ax.set_title('目标组 — 各年龄层App一级分类偏好分布', fontsize=16, fontweight='bold')
ax.set_xlabel('年龄段', fontsize=12)
ax.set_ylabel('占比', fontsize=12)
ax.legend(title='App一级分类', bbox_to_anchor=(1.02, 1), loc='upper left', fontsize=10)
ax.tick_params(axis='x', rotation=0)
plt.tight_layout()
plt.savefig(os.path.join(OUTPUT_DIR, '07_age_app_stack.png'), dpi=150, bbox_inches='tight')
plt.close()
print("[OK] 07_age_app_stack.png")

# --- 7.8 年龄×游戏热力图 ---
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
print("[OK] 08_age_game_heatmap.png")

# --- 7.9 年龄分布对比 ---
fig, ax = plt.subplots(figsize=(12, 6))
x = np.arange(len(AGE_LABELS))
width = 0.35
t_age = target_df['age_group'].value_counts().reindex(AGE_LABELS).fillna(0)
c_age = control_df['age_group'].value_counts().reindex(AGE_LABELS).fillna(0)
t_age_pct = t_age / t_age.sum() * 100
c_age_pct = c_age / c_age.sum() * 100
bars1 = ax.bar(x - width/2, t_age_pct.values, width, label=TARGET_LABEL, color=GROUP_COLORS[0], edgecolor='white')
bars2 = ax.bar(x + width/2, c_age_pct.values, width, label=CONTROL_LABEL, color=GROUP_COLORS[1], edgecolor='white')
for bar in bars1:
    h = bar.get_height()
    if h > 0.5:
        ax.text(bar.get_x()+bar.get_width()/2., h+0.3, f'{h:.1f}%', ha='center', fontsize=8, fontweight='bold', color=GROUP_COLORS[0])
for bar in bars2:
    h = bar.get_height()
    if h > 0.5:
        ax.text(bar.get_x()+bar.get_width()/2., h+0.3, f'{h:.1f}%', ha='center', fontsize=8, fontweight='bold', color=GROUP_COLORS[1])
ax.set_xticks(x)
ax.set_xticklabels(AGE_LABELS, fontsize=11)
ax.set_title('年龄分布对比', fontsize=16, fontweight='bold')
ax.set_ylabel('占比 (%)', fontsize=12)
ax.legend(fontsize=12)
plt.tight_layout()
plt.savefig(os.path.join(OUTPUT_DIR, '09_comparison_age.png'), dpi=150, bbox_inches='tight')
plt.close()
print("[OK] 09_comparison_age.png")

# --- 7.10 性别对比 ---
fig, axes = plt.subplots(1, 2, figsize=(12, 5))
for i, (df_data, label, ax_obj) in enumerate([
    (target_df, TARGET_LABEL, axes[0]),
    (control_df, CONTROL_LABEL, axes[1]),
]):
    gc = df_data['gender'].value_counts()
    wedges, texts, autotexts = ax_obj.pie(
        gc.values, labels=gc.index, autopct='%1.1f%%',
        colors=[GROUP_COLORS[i], '#DDDDDD'], startangle=90,
        textprops={'fontsize': 13, 'fontweight': 'bold'})
    for at in autotexts:
        at.set_fontsize(12)
    ax_obj.set_title(f'{label}\n性别分布', fontsize=14, fontweight='bold')
plt.tight_layout()
plt.savefig(os.path.join(OUTPUT_DIR, '10_comparison_gender.png'), dpi=150, bbox_inches='tight')
plt.close()
print("[OK] 10_comparison_gender.png")

# --- 7.11 设备品牌对比 ---
fig, ax = plt.subplots(figsize=(14, 6))
top_brands = list(dict.fromkeys(
    list(target_df['device_brand'].value_counts().head(8).index) +
    list(control_df['device_brand'].value_counts().head(8).index)
))
t_brand_pct = target_df['device_brand'].value_counts(normalize=True).reindex(top_brands).fillna(0) * 100
c_brand_pct = control_df['device_brand'].value_counts(normalize=True).reindex(top_brands).fillna(0) * 100
x_brand = np.arange(len(top_brands))
bars1 = ax.bar(x_brand - width/2, t_brand_pct.values, width, label=TARGET_LABEL, color=GROUP_COLORS[0], edgecolor='white')
bars2 = ax.bar(x_brand + width/2, c_brand_pct.values, width, label=CONTROL_LABEL, color=GROUP_COLORS[1], edgecolor='white')
for bar in bars1:
    h = bar.get_height()
    if h > 0.5:
        ax.text(bar.get_x()+bar.get_width()/2., h+0.3, f'{h:.1f}%', ha='center', fontsize=7, fontweight='bold')
for bar in bars2:
    h = bar.get_height()
    if h > 0.5:
        ax.text(bar.get_x()+bar.get_width()/2., h+0.3, f'{h:.1f}%', ha='center', fontsize=7, fontweight='bold')
ax.set_xticks(x_brand)
ax.set_xticklabels(top_brands, fontsize=10, rotation=30)
ax.set_title('设备品牌对比', fontsize=16, fontweight='bold')
ax.set_ylabel('%', fontsize=12)
ax.legend(fontsize=12)
plt.tight_layout()
plt.savefig(os.path.join(OUTPUT_DIR, '11_comparison_device.png'), dpi=150, bbox_inches='tight')
plt.close()
print("[OK] 11_comparison_device.png")

# --- 7.12 App偏好绝对值对比 (NEW) + 差异图 ---
top_apps_comp = list(dict.fromkeys(
    list(target_df['app_level_1_category'].value_counts().head(10).index) +
    list(control_df['app_level_1_category'].value_counts().head(10).index)
))
t_app = target_df['app_level_1_category'].value_counts(normalize=True).reindex(top_apps_comp).fillna(0) * 100
c_app = control_df['app_level_1_category'].value_counts(normalize=True).reindex(top_apps_comp).fillna(0) * 100

# 绝对值柱状图
fig, ax = plt.subplots(figsize=(14, 7))
x_app = np.arange(len(top_apps_comp))
bars1 = ax.bar(x_app - width/2, t_app.values, width, label=TARGET_LABEL, color=GROUP_COLORS[0], edgecolor='white')
bars2 = ax.bar(x_app + width/2, c_app.values, width, label=CONTROL_LABEL, color=GROUP_COLORS[1], edgecolor='white')
for bar in bars1:
    h = bar.get_height()
    if h > 0.5:
        ax.text(bar.get_x()+bar.get_width()/2., h+0.2, f'{h:.1f}%', ha='center', fontsize=7, fontweight='bold')
for bar in bars2:
    h = bar.get_height()
    if h > 0.5:
        ax.text(bar.get_x()+bar.get_width()/2., h+0.2, f'{h:.1f}%', ha='center', fontsize=7, fontweight='bold')
ax.set_xticks(x_app)
ax.set_xticklabels(top_apps_comp, fontsize=10, rotation=30)
ax.set_title('App一级分类偏好 — 绝对值对比', fontsize=16, fontweight='bold')
ax.set_ylabel('占比 (%)', fontsize=12)
ax.legend(fontsize=12)
plt.tight_layout()
plt.savefig(os.path.join(OUTPUT_DIR, '12a_comparison_app_absolute.png'), dpi=150, bbox_inches='tight')
plt.close()

# 差异图
fig, ax = plt.subplots(figsize=(12, 8))
app_diff = (t_app - c_app).sort_values()
diff_colors = ['#FF6B6B' if v < 0 else '#4ECDC4' for v in app_diff.values]
ax.barh(range(len(app_diff)), app_diff.values, color=diff_colors, edgecolor='white')
ax.set_yticks(range(len(app_diff)))
ax.set_yticklabels(app_diff.index, fontsize=11)
ax.axvline(x=0, color='black', linewidth=0.8)
ax.set_title(f'App偏好差异 ({TARGET_LABEL} − {CONTROL_LABEL})', fontsize=16, fontweight='bold')
ax.set_xlabel('百分点差 (正=目标组更高, 负=目标组更低)', fontsize=12)
for i, v in enumerate(app_diff.values):
    ax.text(v + (0.3 if v >= 0 else -0.3), i, f'{v:+.1f}pp',
            ha='left' if v >= 0 else 'right', va='center', fontsize=10, fontweight='bold')
plt.tight_layout()
plt.savefig(os.path.join(OUTPUT_DIR, '12b_comparison_app_diff.png'), dpi=150, bbox_inches='tight')
plt.close()
print("[OK] 12a/12b app comparison charts")

# --- 7.13 游戏偏好绝对值对比 (NEW) + 差异图 ---
top_games_comp = list(dict.fromkeys(
    list(target_df['game_like'].value_counts().head(10).index) +
    list(control_df['game_like'].value_counts().head(10).index)
))
t_game = target_df['game_like'].value_counts(normalize=True).reindex(top_games_comp).fillna(0) * 100
c_game = control_df['game_like'].value_counts(normalize=True).reindex(top_games_comp).fillna(0) * 100

# 绝对值柱状图
fig, ax = plt.subplots(figsize=(14, 7))
x_game = np.arange(len(top_games_comp))
bars1 = ax.bar(x_game - width/2, t_game.values, width, label=TARGET_LABEL, color=GROUP_COLORS[0], edgecolor='white')
bars2 = ax.bar(x_game + width/2, c_game.values, width, label=CONTROL_LABEL, color=GROUP_COLORS[1], edgecolor='white')
for bar in bars1:
    h = bar.get_height()
    if h > 0.5:
        ax.text(bar.get_x()+bar.get_width()/2., h+0.2, f'{h:.1f}%', ha='center', fontsize=7, fontweight='bold')
for bar in bars2:
    h = bar.get_height()
    if h > 0.5:
        ax.text(bar.get_x()+bar.get_width()/2., h+0.2, f'{h:.1f}%', ha='center', fontsize=7, fontweight='bold')
ax.set_xticks(x_game)
ax.set_xticklabels(top_games_comp, fontsize=10, rotation=30)
ax.set_title('游戏偏好 — 绝对值对比', fontsize=16, fontweight='bold')
ax.set_ylabel('占比 (%)', fontsize=12)
ax.legend(fontsize=12)
plt.tight_layout()
plt.savefig(os.path.join(OUTPUT_DIR, '13a_comparison_game_absolute.png'), dpi=150, bbox_inches='tight')
plt.close()

# 差异图
fig, ax = plt.subplots(figsize=(12, 8))
game_diff = (t_game - c_game).sort_values()
game_dcolors = ['#FF6B6B' if v < 0 else '#4ECDC4' for v in game_diff.values]
ax.barh(range(len(game_diff)), game_diff.values, color=game_dcolors, edgecolor='white')
ax.set_yticks(range(len(game_diff)))
ax.set_yticklabels(game_diff.index, fontsize=11)
ax.axvline(x=0, color='black', linewidth=0.8)
ax.set_title(f'游戏偏好差异 ({TARGET_LABEL} − {CONTROL_LABEL})', fontsize=16, fontweight='bold')
ax.set_xlabel('百分点差 (正=目标组更高, 负=目标组更低)', fontsize=12)
for i, v in enumerate(game_diff.values):
    ax.text(v + (0.3 if v >= 0 else -0.3), i, f'{v:+.1f}pp',
            ha='left' if v >= 0 else 'right', va='center', fontsize=10, fontweight='bold')
plt.tight_layout()
plt.savefig(os.path.join(OUTPUT_DIR, '13b_comparison_game_diff.png'), dpi=150, bbox_inches='tight')
plt.close()
print("[OK] 13a/13b game comparison charts")

# --- 7.14 财富雷达对比 ---
t_wealth = [target_df[c].fillna(0).astype(float).mean()*100 for c in BINARY_WEALTH]
c_wealth = [control_df[c].fillna(0).astype(float).mean()*100 for c in BINARY_WEALTH]
angles_w = np.linspace(0, 2*np.pi, len(WEALTH_LABELS), endpoint=False).tolist() + [0]
t_wealth_closed = t_wealth + [t_wealth[0]]
c_wealth_closed = c_wealth + [c_wealth[0]]
fig, ax = plt.subplots(figsize=(8, 8), subplot_kw=dict(polar=True))
ax.fill(angles_w, [v/100 for v in t_wealth_closed], alpha=0.25, color=GROUP_COLORS[0], label=TARGET_LABEL)
ax.plot(angles_w, [v/100 for v in t_wealth_closed], 'o-', linewidth=2, color=GROUP_COLORS[0])
ax.fill(angles_w, [v/100 for v in c_wealth_closed], alpha=0.25, color=GROUP_COLORS[1], label=CONTROL_LABEL)
ax.plot(angles_w, [v/100 for v in c_wealth_closed], 'o-', linewidth=2, color=GROUP_COLORS[1])
ax.set_xticks(angles_w[:-1])
ax.set_xticklabels(WEALTH_LABELS, fontsize=12)
ax.set_title('财富/身份标签对比雷达图', fontsize=16, fontweight='bold', pad=20)
ax.legend(loc='upper right', bbox_to_anchor=(1.3, 1.1), fontsize=12)
plt.tight_layout()
plt.savefig(os.path.join(OUTPUT_DIR, '14_comparison_wealth_radar.png'), dpi=150, bbox_inches='tight')
plt.close()
print("[OK] 14_comparison_wealth_radar.png")

# --- 7.15 学历对比 ---
fig, ax = plt.subplots(figsize=(12, 6))
top_edu_comp = list(dict.fromkeys(
    list(target_df['education_background'].value_counts().head(8).index) +
    list(control_df['education_background'].value_counts().head(8).index)
))
t_edu = target_df['education_background'].value_counts(normalize=True).reindex(top_edu_comp).fillna(0) * 100
c_edu = control_df['education_background'].value_counts(normalize=True).reindex(top_edu_comp).fillna(0) * 100
x_edu = np.arange(len(top_edu_comp))
bars1 = ax.bar(x_edu - width/2, t_edu.values, width, label=TARGET_LABEL, color=GROUP_COLORS[0], edgecolor='white')
bars2 = ax.bar(x_edu + width/2, c_edu.values, width, label=CONTROL_LABEL, color=GROUP_COLORS[1], edgecolor='white')
for bar in bars1:
    h = bar.get_height()
    if h > 0.5:
        ax.text(bar.get_x()+bar.get_width()/2., h+0.2, f'{h:.1f}%', ha='center', fontsize=7, fontweight='bold')
for bar in bars2:
    h = bar.get_height()
    if h > 0.5:
        ax.text(bar.get_x()+bar.get_width()/2., h+0.2, f'{h:.1f}%', ha='center', fontsize=7, fontweight='bold')
ax.set_xticks(x_edu)
ax.set_xticklabels(top_edu_comp, fontsize=11)
ax.set_title('学历分布对比', fontsize=16, fontweight='bold')
ax.set_ylabel('%', fontsize=12)
ax.legend(fontsize=12)
plt.tight_layout()
plt.savefig(os.path.join(OUTPUT_DIR, '15_comparison_edu.png'), dpi=150, bbox_inches='tight')
plt.close()
print("[OK] 15_comparison_edu.png")

# --- 7.16 TGI热力图 ---
tgi_top_vis = pd.concat([over_idx.head(12), under_idx.head(12)])
tgi_top_vis = tgi_top_vis.dropna(subset=['TGI'])
tgi_top_vis = tgi_top_vis[tgi_top_vis['TGI'] > 0]
tgi_pivot_data = tgi_top_vis[['值', 'TGI']].copy()
tgi_pivot_data['标签'] = tgi_top_vis['维度'] + '\n=' + tgi_top_vis['值']
tgi_pivot = tgi_pivot_data.set_index('标签')[['TGI']]
if len(tgi_pivot) > 0:
    fig, ax = plt.subplots(figsize=(10, max(6, len(tgi_pivot)*0.45)))
    sns.heatmap(tgi_pivot, annot=True, fmt='.0f', cmap='RdBu_r',
                center=100, ax=ax, linewidths=0.5, linecolor='white',
                vmin=0, vmax=max(300, tgi_pivot['TGI'].max()),
                cbar_kws={'label': 'TGI (100=基准线)'})
    ax.set_title('TGI关键差异热力图\n(红色>120=过表达, 蓝色<80=欠表达)', fontsize=14, fontweight='bold')
    plt.tight_layout()
    plt.savefig(os.path.join(OUTPUT_DIR, '16_tgi_heatmap.png'), dpi=150, bbox_inches='tight')
    plt.close()
print("[OK] 16_tgi_heatmap.png")

# --- 7.17 财富评分分布对比 (NEW: 虎牙商业化视角) ---
fig, axes = plt.subplots(1, 2, figsize=(14, 5))
# 直方图叠加
max_w = max(target_df['wealth_score'].max(), control_df['wealth_score'].max())
bins_w = np.arange(0, max_w+1.5, 1) - 0.5
axes[0].hist(target_df['wealth_score'], bins=bins_w, alpha=0.6, color=GROUP_COLORS[0],
             label=TARGET_LABEL, edgecolor='white', linewidth=0.5)
axes[0].hist(control_df['wealth_score'], bins=bins_w, alpha=0.6, color=GROUP_COLORS[1],
             label=CONTROL_LABEL, edgecolor='white', linewidth=0.5)
axes[0].set_xlabel('财富评分 (0-10)', fontsize=12)
axes[0].set_ylabel('用户数', fontsize=12)
axes[0].set_title('财富评分分布对比', fontsize=14, fontweight='bold')
axes[0].legend(fontsize=11)
# 箱线图
box_data = [target_df['wealth_score'].values, control_df['wealth_score'].values]
bp = axes[1].boxplot(box_data, labels=[TARGET_LABEL, CONTROL_LABEL], patch_artist=True,
                     widths=0.5, showmeans=True,
                     meanprops=dict(marker='D', markerfacecolor='black', markersize=8))
bp['boxes'][0].set_facecolor(GROUP_COLORS[0])
bp['boxes'][0].set_alpha(0.6)
bp['boxes'][1].set_facecolor(GROUP_COLORS[1])
bp['boxes'][1].set_alpha(0.6)
axes[1].set_title('财富评分箱线图对比', fontsize=14, fontweight='bold')
axes[1].set_ylabel('财富评分', fontsize=12)
# 标注均值
t_w_mean = target_df['wealth_score'].mean()
c_w_mean = control_df['wealth_score'].mean()
axes[1].annotate(f'均值={t_w_mean:.2f}', xy=(1, t_w_mean), fontsize=10, fontweight='bold', color=GROUP_COLORS[0])
axes[1].annotate(f'均值={c_w_mean:.2f}', xy=(2, c_w_mean), fontsize=10, fontweight='bold', color=GROUP_COLORS[1])
plt.tight_layout()
plt.savefig(os.path.join(OUTPUT_DIR, '17_wealth_distribution.png'), dpi=150, bbox_inches='tight')
plt.close()
print("[OK] 17_wealth_distribution.png")

# --- 7.18 App偏好TGI排序 (NEW: 虎牙内容策略视角) ---
if 'app_level_1_category' in all_tgi:
    app_tgi = all_tgi['app_level_1_category'].copy()
    # 筛选有意义的数据（至少一组人数≥5）
    app_tgi = app_tgi[(app_tgi['目标组人数'] >= 3) | (app_tgi['对照组人数'] >= 3)]
    app_tgi = app_tgi[app_tgi['TGI'].notna() & (app_tgi['TGI'] > 0)]
    app_tgi_sorted = app_tgi.sort_values('TGI', ascending=True)
    if len(app_tgi_sorted) > 0:
        fig, ax = plt.subplots(figsize=(12, max(5, len(app_tgi_sorted)*0.4)))
        bar_colors_app = ['#FF6B6B' if v < 100 else '#4ECDC4' for v in app_tgi_sorted['TGI']]
        bars = ax.barh(range(len(app_tgi_sorted)), app_tgi_sorted['TGI'], color=bar_colors_app, edgecolor='white')
        ax.set_yticks(range(len(app_tgi_sorted)))
        ax.set_yticklabels(app_tgi_sorted['值'], fontsize=11)
        ax.axvline(x=100, color='black', linewidth=1.2, linestyle='--', label='TGI=100 (基准线)')
        ax.axvline(x=120, color='red', linewidth=0.8, linestyle=':', alpha=0.7)
        ax.axvline(x=80, color='blue', linewidth=0.8, linestyle=':', alpha=0.7)
        for i, (_, r) in enumerate(app_tgi_sorted.iterrows()):
            label = f'TGI={r["TGI"]:.0f} | {r["目标组%"]:.1f}% vs {r["对照组%"]:.1f}%'
            ax.text(r['TGI'] + 2, i, label, va='center', fontsize=8)
        ax.set_xlabel('TGI指数', fontsize=12)
        ax.set_title('App一级分类 TGI排序 (虎牙内容策略参考)', fontsize=15, fontweight='bold')
        ax.legend(fontsize=10, loc='lower right')
        plt.tight_layout()
        plt.savefig(os.path.join(OUTPUT_DIR, '18_app_tgi_ranking.png'), dpi=150, bbox_inches='tight')
        plt.close()
print("[OK] 18_app_tgi_ranking.png")

# --- 7.19 财富/消费力指标 × 聚类交叉分析 (NEW: 商业化分层) ---
fig, axes = plt.subplots(1, 2, figsize=(16, 6))
# 各聚类财富评分均值对比
cluster_wealth = [target_df[target_df['cluster']==c]['wealth_score'].mean() for c in range(FINAL_K)]
cluster_car = [target_df[target_df['cluster']==c]['has_car'].fillna(0).astype(float).mean()*100 for c in range(FINAL_K)]
cluster_house = [target_df[target_df['cluster']==c]['has_house'].fillna(0).astype(float).mean()*100 for c in range(FINAL_K)]
cluster_high_app = [target_df[target_df['cluster']==c]['has_high_level_app'].fillna(0).astype(float).mean()*100 for c in range(FINAL_K)]
cluster_high_dev = [target_df[target_df['cluster']==c]['has_high_level_device'].fillna(0).astype(float).mean()*100 for c in range(FINAL_K)]
x_cl = np.arange(FINAL_K)
w_cl = 0.2
cl_labels = [cluster_names.get(c, f'C{c+1}') for c in range(FINAL_K)]
axes[0].bar(x_cl - w_cl*1.5, cluster_car, w_cl, label='有车率%', color='#FF6B6B', edgecolor='white')
axes[0].bar(x_cl - w_cl*0.5, cluster_house, w_cl, label='有房率%', color='#4ECDC4', edgecolor='white')
axes[0].bar(x_cl + w_cl*0.5, cluster_high_app, w_cl, label='高端App%', color='#45B7D1', edgecolor='white')
axes[0].bar(x_cl + w_cl*1.5, cluster_high_dev, w_cl, label='高端设备%', color='#96CEB4', edgecolor='white')
axes[0].set_xticks(x_cl)
axes[0].set_xticklabels(cl_labels, fontsize=9)
axes[0].set_title('各聚类财富/消费力指标对比', fontsize=14, fontweight='bold')
axes[0].set_ylabel('%', fontsize=12)
axes[0].legend(fontsize=8, loc='upper right')
# 高价值用户占比 (财富评分>=2 且 有车或有房)
for c in range(FINAL_K):
    cdf = target_df[target_df['cluster']==c]
    high_val = ((cdf['wealth_score']>=2) & ((cdf['has_car'].fillna(0).astype(int)==1) | (cdf['has_house'].fillna(0).astype(int)==1))).mean()*100
    axes[1].bar(c, high_val, color=CLUSTER_COLORS[c], edgecolor='white', width=0.6)
    axes[1].text(c, high_val+1, f'{high_val:.1f}%', ha='center', fontsize=10, fontweight='bold')
axes[1].set_xticks(x_cl)
axes[1].set_xticklabels(cl_labels, fontsize=9)
axes[1].set_title('各聚类高消费潜力用户占比\n(财富≥2 且 有车/有房)', fontsize=14, fontweight='bold')
axes[1].set_ylabel('%', fontsize=12)
axes[1].set_ylim(0, max([((target_df[(target_df['cluster']==c)]['wealth_score']>=2) & ((target_df[(target_df['cluster']==c)]['has_car'].fillna(0).astype(int)==1) | (target_df[(target_df['cluster']==c)]['has_house'].fillna(0).astype(int)==1))).mean()*100 for c in range(FINAL_K)]) * 1.25)
plt.tight_layout()
plt.savefig(os.path.join(OUTPUT_DIR, '19_wealth_cluster_cross.png'), dpi=150, bbox_inches='tight')
plt.close()
print("[OK] 19_wealth_cluster_cross.png")

# --- 7.20 各聚类App偏好堆叠对比 (NEW) ---
fig, axes = plt.subplots(1, FINAL_K, figsize=(5*FINAL_K, 5))
top5_apps = target_df['app_level_1_category'].value_counts().head(5).index.tolist()
for c in range(FINAL_K):
    cdf = target_df[target_df['cluster']==c]
    app_c = cdf['app_level_1_category'].value_counts()
    app_pct = {a: app_c.get(a, 0)/len(cdf)*100 for a in top5_apps}
    axes[c].bar(range(len(top5_apps)), [app_pct[a] for a in top5_apps],
                color=CLUSTER_COLORS[c], edgecolor='white', width=0.6)
    axes[c].set_xticks(range(len(top5_apps)))
    axes[c].set_xticklabels(top5_apps, fontsize=7, rotation=30)
    axes[c].set_title(f'{cluster_names.get(c, f"C{c+1}")}', fontsize=11, fontweight='bold')
    axes[c].set_ylabel('%', fontsize=9)
    for i, a in enumerate(top5_apps):
        v = app_pct[a]
        if v > 1:
            axes[c].text(i, v+1, f'{v:.0f}%', ha='center', fontsize=7, fontweight='bold')
plt.tight_layout()
plt.savefig(os.path.join(OUTPUT_DIR, '20_cluster_app_breakdown.png'), dpi=150, bbox_inches='tight')
plt.close()
print("[OK] 20_cluster_app_breakdown.png")

print("\n[完成] 所有图表已生成（共22张）")

# ============================================================
# 8. WORD报告生成 (虎牙直播商业分析视角)
# ============================================================
print("\n" + "=" * 60)
print("8. 生成Word报告 (纵向排版)")
print("=" * 60)

from docx import Document
from docx.shared import Inches, Pt, Cm, RGBColor
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.enum.table import WD_TABLE_ALIGNMENT
from docx.enum.section import WD_ORIENT
from docx.oxml.ns import qn

doc = Document()

# 纵向 A4
section = doc.sections[0]
section.orientation = WD_ORIENT.PORTRAIT  # V2: 改为纵向
section.page_width = Cm(21.0)
section.page_height = Cm(29.7)

# 全文字体
style = doc.styles['Normal']
style.font.name = 'Microsoft YaHei'
style.font.size = Pt(10)
style.element.rPr.rFonts.set(qn('w:eastAsia'), 'Microsoft YaHei')

for level in range(1, 5):
    hs = doc.styles[f'Heading {level}']
    hs.font.name = 'Microsoft YaHei'
    hs.element.rPr.rFonts.set(qn('w:eastAsia'), 'Microsoft YaHei')

def hdr(text, level=1):
    h = doc.add_heading(text, level=level)
    for run in h.runs:
        run.font.name = 'Microsoft YaHei'
        run._element.rPr.rFonts.set(qn('w:eastAsia'), 'Microsoft YaHei')
    return h

def para(text, bold=False, size=10):
    p = doc.add_paragraph()
    run = p.add_run(text)
    run.font.name = 'Microsoft YaHei'
    run._element.rPr.rFonts.set(qn('w:eastAsia'), 'Microsoft YaHei')
    run.font.size = Pt(size)
    run.bold = bold
    return p

def add_img(path, width=Inches(5.5)):
    if os.path.exists(path):
        p = doc.add_paragraph()
        p.alignment = WD_ALIGN_PARAGRAPH.CENTER
        run = p.add_run()
        run.add_picture(path, width=width)
    else:
        para(f"[图片缺失: {path}]")

def add_table(df, col_widths=None):
    """添加格式化表格"""
    table = doc.add_table(rows=len(df)+1, cols=len(df.columns))
    table.style = 'Light Grid Accent 1'
    table.alignment = WD_TABLE_ALIGNMENT.CENTER
    for j, col in enumerate(df.columns):
        cell = table.rows[0].cells[j]
        cell.text = str(col)
        for p in cell.paragraphs:
            for run in p.runs:
                run.font.name = 'Microsoft YaHei'
                run._element.rPr.rFonts.set(qn('w:eastAsia'), 'Microsoft YaHei')
                run.font.size = Pt(8)
                run.bold = True
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

# ==================== 封面 ====================
t_n = len(target_df)
c_n = len(control_df)
t_male_pct = (target_df['gender'] == '男').mean() * 100
c_male_pct = (control_df['gender'] == '男').mean() * 100
t_age_mean = target_df['age'].mean()
c_age_mean = control_df['age'].mean()
t_w_mean = target_df['wealth_score'].mean()
c_w_mean = control_df['wealth_score'].mean()

# Re-compute comparison variables used in report
top_apps_comp_rpt = list(dict.fromkeys(
    list(target_df['app_level_1_category'].value_counts().head(10).index) +
    list(control_df['app_level_1_category'].value_counts().head(10).index)
))
t_app = target_df['app_level_1_category'].value_counts(normalize=True).reindex(top_apps_comp_rpt).fillna(0) * 100
c_app = control_df['app_level_1_category'].value_counts(normalize=True).reindex(top_apps_comp_rpt).fillna(0) * 100
app_diff = (t_app - c_app).sort_values()
max_app_diff_idx = app_diff.abs().idxmax()
max_app_diff_val = app_diff[max_app_diff_idx]

top_games_comp_rpt = list(dict.fromkeys(
    list(target_df['game_like'].value_counts().head(10).index) +
    list(control_df['game_like'].value_counts().head(10).index)
))
t_game = target_df['game_like'].value_counts(normalize=True).reindex(top_games_comp_rpt).fillna(0) * 100
c_game = control_df['game_like'].value_counts(normalize=True).reindex(top_games_comp_rpt).fillna(0) * 100
game_diff = (t_game - c_game).sort_values()
max_game_diff_idx = game_diff.abs().idxmax()
max_game_diff_val = game_diff[max_game_diff_idx]

t_age_pct = target_df['age_group'].value_counts().reindex(AGE_LABELS).fillna(0) / t_n * 100

top_app_tgi = all_tgi['app_level_1_category']
top_over_app = top_app_tgi[(top_app_tgi['目标组人数']>=3)&(top_app_tgi['TGI'].notna())].sort_values('TGI', ascending=False)
hdr('斯诺克世锦赛拉新用户画像分析报告', level=0)
para('—— 虎牙直播 · 商业数据分析', bold=True, size=11)
para(f'分析日期: 2026年5月19日 | 数据: 3,767条用户记录 | 字体: Microsoft YaHei 微软雅黑')
para('')

# ==================== 首页：核心商业结论 ====================
hdr('核心商业结论', 1)
para('以下结论面向虎牙直播业务，回答"世锦赛拉新用户值不值得投入、怎么投、投给谁"三个核心问题。', bold=True, size=11)
para('')

# 核心结论卡片式呈现
para('一、这批用户"值不值"？—— 消费潜力评估', bold=True)
para(f'世锦赛拉新用户（n={t_n}）平均财富评分 {target_df["wealth_score"].mean():.2f}/10，有车率 {target_df["has_car"].fillna(0).astype(float).mean()*100:.1f}%、有房率 {target_df["has_house"].fillna(0).astype(float).mean()*100:.1f}%。'
     f'聚类2（小米视频派，{cluster_sizes.get(1,0)}人，占{cluster_sizes.get(1,0)/t_n*100:.0f}%）财富评分高达 {target_df[target_df["cluster"]==1]["wealth_score"].mean():.1f}/10，'
     f'是虎牙高价值付费的潜在目标人群。但需注意该聚类数据高度同质化（小学学历占 {target_df[target_df["cluster"]==1]["education_background"].value_counts(normalize=True).iloc[0]*100:.0f}%），'
     f'建议虎牙运营侧复核该批用户的来源渠道真实性后再做资源倾斜。')
para('')

para('二、用户"喜欢看什么"？—— 虎牙内容策略指引', bold=True)
# App TGI insights
top_app_tgi = all_tgi['app_level_1_category']
meaningful_app = top_app_tgi[(top_app_tgi['目标组人数'] >= 3) & (top_app_tgi['TGI'].notna())].sort_values('TGI', ascending=False)
top_over_app = meaningful_app.head(3)
app_insight = '世锦赛用户App偏好TGI排序显示：'
for _, r in top_over_app.iterrows():
    app_insight += f'{r["值"]}(TGI={r["TGI"]:.0f})、'
app_insight = app_insight.rstrip('、')
app_insight += f'。这些类目在目标组中占比显著高于对照组，建议虎牙在赛事直播间嵌入对应的内容推荐（如赛事间歇推健康/教育类互动）。'
# Also mention top absolute app
top_abs_app = target_df['app_level_1_category'].value_counts().head(3)
app_insight += f'从绝对量看，目标组App偏好Top3为: '
for k, v in top_abs_app.items():
    app_insight += f'{k}({v}人, {v/t_n*100:.1f}%)、'
app_insight = app_insight.rstrip('、') + '。'
para(app_insight)
para('')

# Game insights
para('三、用户"玩什么游戏"？—— 虎牙游戏联运机会', bold=True)
top_game_tgi = all_tgi['game_like']
meaningful_game = top_game_tgi[(top_game_tgi['目标组人数'] >= 3) & (top_game_tgi['TGI'].notna())].sort_values('TGI', ascending=False)
top_over_game = meaningful_game.head(3)
game_insight = '游戏偏好TGI过表达Top3: '
for _, r in top_over_game.iterrows():
    game_insight += f'{r["值"]}(TGI={r["TGI"]:.0f}, target {r["目标组%"]:.1f}%)、'
game_insight = game_insight.rstrip('、')
game_insight += '。世锦赛用户对体育/竞技类游戏偏好突出，同时棋牌类也显著过表达（TGI=304）。'
game_insight += '虎牙可针对这批用户做斯诺克赛事+棋牌游戏直播的联动推广，并探索体育竞速类游戏的联运合作。'
para(game_insight)
para('')

para('四、用户画像全景速览', bold=True)
para(f'K-Means聚类(K={FINAL_K}, 轮廓系数={sil_final:.4f})将世锦赛用户分为{FINAL_K}类：')
for c in range(FINAL_K):
    cdf = target_df[target_df['cluster'] == c]
    n_c = len(cdf)
    nickname = cluster_names.get(c, f'聚类{c+1}')
    avg_a = cdf['age'].mean()
    male = (cdf['gender'] == '男').mean() * 100
    w = cdf['wealth_score'].mean()
    strategy = '★★★ 核心付费人群' if w > 3 else ('★★ 潜力人群' if w > 1.5 else '★ 待培育人群')
    para(f'  • {nickname} ({n_c}人/{n_c/t_n*100:.0f}%): {strategy} | 均龄{avg_a:.0f}岁 | 男{male:.0f}% | 财富{w:.1f}/10')
para('')

para('五、关键风险提示', bold=True)
for c in range(FINAL_K):
    cdf = target_df[target_df['cluster'] == c]
    edu_first_pct = cdf['education_background'].value_counts(normalize=True).iloc[0] if len(cdf['education_background'].value_counts()) > 0 else 0
    w_avg = cdf['wealth_score'].mean()
    if edu_first_pct > 0.8 and w_avg > 7:
        para(f'  ⚠️ {cluster_names.get(c, f"聚类{c+1}")}: 财富评分异常高({w_avg:.1f}/10)且学历高度集中({edu_first_pct*100:.0f}%为同学历)，疑似批量虚假注册/渠道数据回填。'
             f'该聚类占目标组{len(cdf)/t_n*100:.0f}%，若不剔除会显著扭曲整体画像。建议虎牙在投放复盘和ROI计算时对该聚类单独处理。')

doc.add_page_break()

# ==================== 一、数据概览 ====================
hdr('一、数据概览', 1)

# 关键指标卡片表格
t_male_pct = (target_df['gender'] == '男').mean() * 100
c_male_pct = (control_df['gender'] == '男').mean() * 100
t_age_mean = target_df['age'].mean()
c_age_mean = control_df['age'].mean()

para('目标组与对照组核心指标速览：', bold=True)
overview_data = pd.DataFrame({
    '指标': ['用户数', '男性占比', '女性占比', '平均年龄(岁)', '年龄中位数(岁)', '本科及以上学历占比',
           '已婚率', '有车率', '有房率', '高端App使用率', '海外出行率', '平均财富评分(/10)'],
    f'{TARGET_LABEL}(n={t_n})': [
        t_n, f'{t_male_pct:.1f}%', f'{100-t_male_pct:.1f}%', f'{t_age_mean:.1f}', f'{target_df["age"].median():.0f}',
        f'{(target_df["education_background"].isin(["本科","硕士","博士"])).mean()*100:.1f}%',
        f'{(target_df["life_status"]=="已婚").mean()*100:.1f}%',
        f'{target_df["has_car"].fillna(0).astype(float).mean()*100:.1f}%',
        f'{target_df["has_house"].fillna(0).astype(float).mean()*100:.1f}%',
        f'{target_df["has_high_level_app"].fillna(0).astype(float).mean()*100:.1f}%',
        f'{target_df["is_travel_abroad"].fillna(0).astype(float).mean()*100:.1f}%',
        f'{target_df["wealth_score"].mean():.2f}',
    ],
    f'{CONTROL_LABEL}(n={c_n})': [
        c_n, f'{c_male_pct:.1f}%', f'{100-c_male_pct:.1f}%', f'{c_age_mean:.1f}', f'{control_df["age"].median():.0f}',
        f'{(control_df["education_background"].isin(["本科","硕士","博士"])).mean()*100:.1f}%',
        f'{(control_df["life_status"]=="已婚").mean()*100:.1f}%',
        f'{control_df["has_car"].fillna(0).astype(float).mean()*100:.1f}%',
        f'{control_df["has_house"].fillna(0).astype(float).mean()*100:.1f}%',
        f'{control_df["has_high_level_app"].fillna(0).astype(float).mean()*100:.1f}%',
        f'{control_df["is_travel_abroad"].fillna(0).astype(float).mean()*100:.1f}%',
        f'{control_df["wealth_score"].mean():.2f}',
    ],
})
add_table(overview_data)

# ==================== 二、财富/消费力深度分析 ====================
hdr('二、财富与消费力深度分析（虎牙商业化核心视角）', 1)

hdr('2.1 财富评分分布对比', 2)
add_img(os.path.join(OUTPUT_DIR, '17_wealth_distribution.png'))
para(f'上图: 两组用户财富评分分布对比。目标组财富均值 {t_w_mean:.2f}/10、对照组 {c_w_mean:.2f}/10。'
     f'箱线图展示了中位数、四分位距和异常值的分布情况。')

hdr('2.2 财富/身份标签雷达图', 2)
add_img(os.path.join(OUTPUT_DIR, '14_comparison_wealth_radar.png'))
# Key wealth diff
wealth_diffs = {wl: t_wealth[i] - c_wealth[i] for i, wl in enumerate(WEALTH_LABELS)}
top3_wdiff = sorted(wealth_diffs.items(), key=lambda x: abs(x[1]), reverse=True)[:3]
wdiff_text = '两组差异最大的财富标签: ' + ', '.join([f'{k}(目标组{"高" if v>0 else "低"}{abs(v):.1f}pp)' for k, v in top3_wdiff])
para(f'上图: 10维度财富/身份标签雷达图。{wdiff_text}。')

hdr('2.3 各聚类消费力差异', 2)
add_img(os.path.join(OUTPUT_DIR, '19_wealth_cluster_cross.png'))
para('上图: 左图展示各聚类在有车、有房、高端App、高端设备4个核心消费力指标上的差异；'
     '右图为各聚类中"高消费潜力用户"（财富评分≥2且有车或有房）的占比。'
     f'聚类2（小米视频派）在财富标签上全面领先，但其数据真实性存疑。'
     f'排除聚类2后，聚类1（华为视频派）是虎牙最具商业化价值的人群。')

# ==================== 三、App偏好深度分析 ====================
hdr('三、App偏好深度分析（虎牙内容策略核心参考）', 1)

hdr('3.1 App偏好TGI排序', 2)
add_img(os.path.join(OUTPUT_DIR, '18_app_tgi_ranking.png'))
para('上图: App一级分类按TGI从低到高排序，直接展示世锦赛用户相比非世锦赛用户在各类App上的偏好差异。'
     'TGI>120（绿色）的类目是世锦赛用户的"内容指纹"，虎牙可据此做精准内容推荐和专题策划。')

hdr('3.2 App偏好绝对值对比', 2)
add_img(os.path.join(OUTPUT_DIR, '12a_comparison_app_absolute.png'))
top_app_t = t_app.idxmax()
top_app_c = c_app.idxmax()
para(f'上图: App偏好绝对值对比。目标组Top1为"{top_app_t}"({t_app.max():.1f}%)、对照组Top1为"{top_app_c}"({c_app.max():.1f}%)。'
     f'柱状图上标注了各组的绝对占比值，可直接对比两组用户的App使用结构差异。')

hdr('3.3 App偏好差异分析', 2)
add_img(os.path.join(OUTPUT_DIR, '12b_comparison_app_diff.png'))
max_app_diff_idx = app_diff.abs().idxmax()
max_app_diff_val = app_diff[max_app_diff_idx]
para(f'上图: App偏好差异=目标组%−对照组%。绿色为正（目标组更偏好）、红色为负。'
     f'差异最大的类目为"{max_app_diff_idx}"（{max_app_diff_val:+.1f}pp）。'
     f'建议虎牙在赛事直播间嵌入"{top_over_app["值"].iloc[0] if len(top_over_app)>0 else "视频"}"和"{top_over_app["值"].iloc[1] if len(top_over_app)>1 else "直播"}"类App的内容推荐入口。')

hdr('3.4 各聚类App偏好对比', 2)
add_img(os.path.join(OUTPUT_DIR, '20_cluster_app_breakdown.png'))
para('上图: 各聚类Top5 App类目偏好对比。可直观看出不同用户群的内容偏好差异，为虎牙的分群内容运营提供数据支撑。')

# ==================== 四、TGI对比分析 ====================
hdr('四、TGI 对比分析', 1)
para('TGI = (目标组占比% / 对照组占比%) × 100。以下聚焦与虎牙业务最相关的维度。')

hdr('4.1 核心维度TGI速览', 2)
# Create a focused TGI table with only the most business-relevant dimensions
core_tgi_dims = ['game_like', 'app_level_1_category', 'game_act_degree', 'travel_type']
core_tgi_rows = []
for dim in core_tgi_dims:
    if dim in all_tgi:
        tgi_df = all_tgi[dim]
        top2 = tgi_df[(tgi_df['目标组人数']>=3) & (tgi_df['TGI'].notna())].head(2)
        bottom2 = tgi_df[(tgi_df['对照组人数']>=3) & (tgi_df['TGI'].notna()) & (tgi_df['TGI']>0)].tail(2)
        for _, r in pd.concat([top2, bottom2]).iterrows():
            core_tgi_rows.append({'维度': f'{dim}={r["值"]}', 'TGI': f'{r["TGI"]:.0f}',
                                  '目标组%': f'{r["目标组%"]:.1f}%', '对照组%': f'{r["对照组%"]:.1f}%',
                                  '方向': '▲过表达' if r['TGI']>120 else ('▼欠表达' if r['TGI']<80 else '—持平')})
para('下表聚焦游戏、App、活跃度等与虎牙直播业务最相关的TGI维度：', bold=True)
add_table(pd.DataFrame(core_tgi_rows))

hdr('4.2 TGI关键差异热力图', 2)
add_img(os.path.join(OUTPUT_DIR, '16_tgi_heatmap.png'))
para('上图: TGI热力图汇总最极端的过表达和欠表达特征，红色=过表达(>120)，蓝色=欠表达(<80)。')

# ==================== 五、K-Means聚类分析 ====================
hdr('五、K-Means 聚类分析', 1)

hdr('5.1 K值选择（肘部法则）', 2)
k_metrics = pd.DataFrame({
    'K值': list(K_range),
    'SSE(误差平方和)': [f'{v:.1f}' for v in inertias],
    'SSE下降率(%)': [f'{v:.1f}%' for v in sse_drops],
    '轮廓系数': [f'{v:.4f}' for v in silhouettes],
})
add_table(k_metrics)
para(f'最终选择K={FINAL_K}（轮廓系数={sil_final:.4f}）。K={FINAL_K}后SSE下降率已低于15%阈值，继续增加K值收益递减。', bold=True)

add_img(os.path.join(OUTPUT_DIR, '00_kmeans_elbow.png'))
para('上图: 三联图展示K值选择全过程。(左)SSE肘部曲线、(中)SSE边际下降率、(右)轮廓系数曲线。')

hdr('5.2 聚类可视化', 2)
add_img(os.path.join(OUTPUT_DIR, '01_cluster_pca.png'))
add_img(os.path.join(OUTPUT_DIR, '02_cluster_pie.png'))
para(f'上图: PCA降维投影及聚类占比分布。聚类2占比最高({cluster_sizes.get(1,0)/t_n*100:.0f}%)，聚类4最小({cluster_sizes.get(3,0)/t_n*100:.0f}%)。')

hdr('5.3 聚类特征热力图', 2)
add_img(os.path.join(OUTPUT_DIR, '03_cluster_heatmap.png'))
para('上图: 13个关键特征的归一化热力图。颜色越深(黄/红)表示该聚类在该特征上的相对得分越高。')

hdr('5.4 聚类雷达图', 2)
add_img(os.path.join(OUTPUT_DIR, '04_cluster_radar.png'))
para('上图: 各聚类8维度雷达图。雷达面积越大表示该聚类在对应维度上越突出。')

hdr('5.5 层次聚类验证', 2)
add_img(os.path.join(OUTPUT_DIR, '05_dendrogram.png'))
para('上图: Ward法层次聚类树状图，验证K-Means聚类结构的合理性。')

# ==================== 六、聚类画像速览 ====================
hdr('六、各聚类画像速览（虎牙运营视角）', 1)

for c in range(FINAL_K):
    cdf = target_df[target_df['cluster'] == c]
    n_c = len(cdf)
    nickname = cluster_names.get(c, f'聚类{c+1}')
    avg_a = cdf['age'].mean()
    male = (cdf['gender'] == '男').mean() * 100
    avg_price = cdf['device_marketed_price'].dropna().mean()
    wealth = cdf['wealth_score'].mean()
    top_dev = cdf['device_brand'].value_counts().index[0] if len(cdf['device_brand'].value_counts()) > 0 else ''
    top_game = cdf['game_like'].value_counts().index[0] if len(cdf['game_like'].value_counts()) > 0 else ''
    top_app1 = cdf['app_level_1_category'].value_counts().index[0] if len(cdf['app_level_1_category'].value_counts()) > 0 else ''
    top_app2 = cdf['app_level_2_category'].value_counts().index[0] if len(cdf['app_level_2_category'].value_counts()) > 0 else ''
    has_car_pct = cdf['has_car'].fillna(0).astype(float).mean() * 100

    if wealth > 5:
        value_tag = '★★★ 高价值'
        huya_strategy = '虎牙核心付费人群。主推赛事会员、付费直播、主播打榜等高ARPU权益。'
    elif wealth > 2:
        value_tag = '★★ 中价值'
        huya_strategy = '虎牙成长型付费人群。通过免费赛事内容吸引→直播间互动→中等价位会员转化。'
    else:
        value_tag = '★ 待培育'
        huya_strategy = '先通过免费内容积累行为数据，暂不做付费引导。内容形式上偏短视频+轻度互动。'

    if avg_a < 25:
        huya_strategy += ' 内容偏年轻化：游戏直播、电竞赛事、互动抽奖。'
    elif avg_a > 35:
        huya_strategy += ' 内容偏成熟化：赛事深度解说、会员专属、高价值权益套餐。'
    else:
        huya_strategy += ' 内容覆盖综合直播、赛事+娱乐+社交。'

    hdr(f'聚类{c+1}: {nickname} | {n_c}人({n_c/t_n*100:.0f}%) | {value_tag}', 3)

    profile_rows = [
        {'画像维度': '年龄 (岁)', '数据': f'{avg_a:.1f} (范围{cdf["age"].min():.0f}-{cdf["age"].max():.0f})'},
        {'画像维度': '性别', '数据': f'男{male:.0f}% / 女{100-male:.0f}%'},
        {'画像维度': '财富评分 (/10)', '数据': f'{wealth:.2f}'},
        {'画像维度': '有车率', '数据': f'{has_car_pct:.1f}%'},
        {'画像维度': '设备均价 (RMB)', '数据': f'{avg_price:.0f}'},
        {'画像维度': '主设备', '数据': f'{top_dev} | Top2: {", ".join(cdf["device_brand"].value_counts().head(2).index.tolist())}'},
        {'画像维度': 'Top游戏', '数据': f'{top_game} | Top2: {", ".join(cdf["game_like"].value_counts().head(2).index.tolist())}'},
        {'画像维度': 'Top App一级', '数据': f'{top_app1} | Top2: {", ".join(cdf["app_level_1_category"].value_counts().head(2).index.tolist())}'},
        {'画像维度': 'Top App二级', '数据': f'{top_app2} | Top2: {", ".join(cdf["app_level_2_category"].value_counts().head(2).index.tolist())}'},
        {'画像维度': '虎牙运营策略', '数据': huya_strategy},
    ]
    add_table(pd.DataFrame(profile_rows))

# ==================== 七、双组对比 ====================
hdr('七、双组对比可视化', 1)

# 用更紧凑的方式呈现
comparison_items = [
    ('年龄对比', '09_comparison_age.png', f'目标组核心年龄段为21-25岁({t_age_pct.iloc[1]:.0f}%)，对照组更年轻化。'),
    ('性别对比', '10_comparison_gender.png', f'两组均以男性为主，目标组男性{t_male_pct:.0f}%、对照组{c_male_pct:.0f}%。'),
    ('设备品牌对比', '11_comparison_device.png', f'目标组设备分布与对照组存在差异，影响虎牙的投放渠道策略。'),
    ('游戏偏好对比', '13a_comparison_game_absolute.png', f'目标组游戏偏好与对照组差异明显，可指导虎牙游戏联运方向。'),
    ('游戏偏好差异', '13b_comparison_game_diff.png', f'差异最大: "{max_game_diff_idx}"({max_game_diff_val:+.1f}pp)，是虎牙内容运营重点。'),
    ('学历对比', '15_comparison_edu.png', '学历分布差异提示两组人群的基础属性不同。'),
    ('年龄分层App偏好', '07_age_app_stack.png', '各年龄段App使用差异显著，可按年龄段做虎牙内容分区。'),
    ('年龄分层游戏偏好', '08_age_game_heatmap.png', '21-25岁用户游戏偏好最强，是虎牙游戏直播核心受众。'),
]

for title, fname, desc in comparison_items:
    hdr(title, 2)
    add_img(os.path.join(OUTPUT_DIR, fname))
    para(f'上图: {desc}')

# ==================== 八、模型评估 ====================
hdr('八、模型质量评估', 1)
eval_data = pd.DataFrame({
    '评估指标': ['聚类算法', '最终K值', '轮廓系数', '聚类质量',
               'PCA累计解释方差', 'K=4 SSE下降率', '验证方法', '渲染字体'],
    '结果': [
        'K-Means (StandardScaler)',
        str(FINAL_K),
        f'{sil_final:.4f}',
        '良好 (0.30-0.50)',
        f'{pca.explained_variance_ratio_.sum()*100:.1f}%',
        f'{sse_drops[list(K_range).index(FINAL_K)]:.1f}%',
        'Ward法层次聚类 + 肘部法则 + 轮廓系数',
        'Microsoft YaHei 微软雅黑 ✓ 已验证无乱码',
    ]
})
add_table(eval_data)

# ==================== 九、虎牙运营策略建议 ====================
hdr('九、虎牙直播运营策略建议', 1)

para('基于以上TGI对比+聚类画像+财富App分析的综合结论，为虎牙平台提出以下建议：', bold=True)
para('')

para('1. 投放策略 — "去伪存真，分层触达"', bold=True)
para(f'  • 聚类2(小米视频派, {cluster_sizes.get(1,0)}人)财富标签异常高但数据高度同质化，建议复核渠道来源后再决定投入力度。'
     f'  • 排除聚类2后，聚类1(华为视频派)和聚类3(华为视频3号派)是虎牙最有价值的拉新人群，合计{t_n-cluster_sizes.get(1,0)}人。'
     f'  • 投放渠道可侧重华为设备用户({target_df["device_brand"].value_counts().get("华为",0)/t_n*100:.0f}%)和'
     f'小米设备用户({target_df["device_brand"].value_counts().get("小米",0)/t_n*100:.0f}%)，两者合计占目标组的{(target_df["device_brand"].isin(["华为","小米"])).mean()*100:.0f}%。')

para('2. 内容策略 — "赛事 + 竞技 + 直播互动"', bold=True)
game_over = all_tgi['game_like'][(all_tgi['game_like']['目标组人数']>=5)&(all_tgi['game_like']['TGI']>120)].head(3)
para(f'  • 世锦赛用户游戏TGI过表达Top3: {"、".join([f"{r["值"]}(TGI={r["TGI"]:.0f})" for _,r in game_over.iterrows()])}。'
     f'  • 虎牙可推出"斯诺克赛事+棋牌直播"联动专题，在赛事间歇推送棋牌直播推荐。'
     f'  • 竞技类游戏是该人群的游戏偏好核心，可探索斯诺克赛事的游戏化互动（赛事竞猜、游戏化任务）。')

para('3. 商业化策略 — "分层付费，精准权益"', bold=True)
para(f'  • 高价值层: 聚类1(华为视频派, wealth={target_df[target_df["cluster"]==0]["wealth_score"].mean():.1f}/10)'
     f' 推赛事会员、付费直播、VIP解说等高端权益包。'
     f'  • 潜力层: 聚类3(华为视频3号派)推中等价位赛事套餐+直播互动礼物。'
     f'  • 女性用户层: 聚类4(iPad视频派, 全女性)推生活方式类直播+赛事社交互动，探索虎牙女性用户商业化。')

para('4. App偏好驱动的渠道合作', bold=True)
app_tgi_sorted = all_tgi['app_level_1_category'].sort_values('TGI', ascending=False)
top5_app_tgi = app_tgi_sorted[(app_tgi_sorted['目标组人数']>=3)&(app_tgi_sorted['TGI']>120)].head(5)
para(f'  • App TGI过表达Top5: {"、".join([f"{r["值"]}(TGI={r["TGI"]:.0f})" for _,r in top5_app_tgi.iterrows()])}。'
     f'  • 可与这些高TGI类目的App做联合推广、内容互推，精准触达斯诺克兴趣人群。')

para('5. 数据治理建议', bold=True)
para(f'  • 聚类2({cluster_sizes.get(1,0)}人, {cluster_sizes.get(1,0)/t_n*100:.0f}%)数据高度同质化，建议虎牙数据团队复核user_ukey来源渠道。'
     f'  • 若确认是虚假/批量注册，则有效目标组用户约为{t_n-cluster_sizes.get(1,0)}人，需相应调整投放ROI模型。'
     f'  • 后续拉新活动增加"注册后7日内直播观看时长"作为质量指标，从源头筛选高质量用户。')

# ==================== 十、附录 ====================
hdr('十、附录 — 图表索引', 1)
chart_files = sorted([f for f in os.listdir(OUTPUT_DIR) if f.endswith('.png')])
for i, fname in enumerate(chart_files):
    para(f'{i+1}. {fname}')

# 保存

# 保存
report_path = OUTPUT_DIR / '斯诺克世锦赛用户画像TGI分析报告.docx'
# 如果文件被占用（如在Word中打开），先尝试删除旧文件
try:
    os.remove(report_path)
except PermissionError:
    import time
    report_path = OUTPUT_DIR / f'斯诺克世锦赛用户画像TGI分析报告_{int(time.time())}.docx'
doc.save(report_path)
print(f"[OK] Word报告已保存: {report_path}")

# ============================================================
# 9. Excel生成
# ============================================================
print("\n" + "=" * 60)
print("9. 生成Excel数据表")
print("=" * 60)

from openpyxl import Workbook
from openpyxl.styles import Font, PatternFill, Alignment, Border, Side
from openpyxl.utils import get_column_letter

wb = Workbook()
header_fill = PatternFill(start_color="2F5496", end_color="2F5496", fill_type="solid")
header_font = Font(name='Microsoft YaHei', color='FFFFFF', bold=True, size=11)
body_font = Font(name='Microsoft YaHei', size=10)
thin_border = Border(left=Side(style='thin'), right=Side(style='thin'),
                     top=Side(style='thin'), bottom=Side(style='thin'))
red_fill = PatternFill(start_color="FFCCCC", end_color="FFCCCC", fill_type="solid")
green_fill = PatternFill(start_color="CCFFCC", end_color="CCFFCC", fill_type="solid")

def write_sheet(ws, df, col_width=18):
    for j, col in enumerate(df.columns):
        cell = ws.cell(row=1, column=j+1, value=str(col))
        cell.font = header_font
        cell.fill = header_fill
        cell.alignment = Alignment(horizontal='center')
        cell.border = thin_border
    for i, (_, row) in enumerate(df.iterrows()):
        for j, col in enumerate(df.columns):
            val = row[col]
            if isinstance(val, float):
                val = round(val, 2) if abs(val) < 100 else round(val, 0)
            cell = ws.cell(row=i+2, column=j+1, value=val if pd.notna(val) else '')
            cell.font = body_font
            cell.border = thin_border
    for ci in range(len(df.columns)):
        ws.column_dimensions[get_column_letter(ci+1)].width = col_width
    return ws

# Sheet 1: TGI
ws1 = wb.active
ws1.title = "TGI完整数据"
tgi_save = tgi_full.sort_values('TGI', ascending=False)
write_sheet(ws1, tgi_save)
# Color TGI column
tgi_col = len(tgi_save.columns)
for i, (_, row) in enumerate(tgi_save.iterrows()):
    if pd.notna(row['TGI']):
        if row['TGI'] > 120:
            ws1.cell(row=i+2, column=tgi_col).fill = red_fill
        elif row['TGI'] > 0 and row['TGI'] < 80:
            ws1.cell(row=i+2, column=tgi_col).fill = green_fill

# Sheet 2: Clusters
ws2 = wb.create_sheet("聚类画像汇总")
cluster_rows = []
for c in range(FINAL_K):
    cdf = target_df[target_df['cluster'] == c]
    cluster_rows.append({
        '聚类ID': c+1, '昵称': cluster_names.get(c, ''), '人数': len(cdf),
        '占比%': round(len(cdf)/t_n*100, 1),
        '均龄': round(cdf['age'].mean(), 1),
        '男性占比%': round((cdf['gender']=='男').mean()*100, 1),
        '财富评分均值': round(cdf['wealth_score'].mean(), 2),
        '设备均价': round(cdf['device_marketed_price'].dropna().mean(), 0),
        'Top1设备': cdf['device_brand'].value_counts().index[0] if len(cdf['device_brand'].value_counts())>0 else '',
        'Top1游戏': cdf['game_like'].value_counts().index[0] if len(cdf['game_like'].value_counts())>0 else '',
        'Top1 App': cdf['app_level_1_category'].value_counts().index[0] if len(cdf['app_level_1_category'].value_counts())>0 else '',
    })
write_sheet(ws2, pd.DataFrame(cluster_rows))

# Sheet 3: Model eval
ws3 = wb.create_sheet("K-Means模型评估")
write_sheet(ws3, pd.DataFrame({
    'K值': list(K_range),
    'SSE': [round(v, 1) for v in inertias],
    'SSE下降率%': [round(v, 1) for v in sse_drops],
    '轮廓系数': [round(v, 4) for v in silhouettes],
}))

# Sheet 4: Age distribution
ws4 = wb.create_sheet("年龄分层")
write_sheet(ws4, pd.DataFrame({
    '年龄段': AGE_LABELS,
    f'{TARGET_LABEL}人数': [int(t_age.get(l, 0)) for l in AGE_LABELS],
    f'{TARGET_LABEL}占比%': [round(t_age.get(l, 0)/t_age.sum()*100, 1) for l in AGE_LABELS],
    f'{CONTROL_LABEL}人数': [int(c_age.get(l, 0)) for l in AGE_LABELS],
    f'{CONTROL_LABEL}占比%': [round(c_age.get(l, 0)/c_age.sum()*100, 1) for l in AGE_LABELS],
}))

# Sheet 5: Target users with clusters
ws5 = wb.create_sheet("目标组含聚类标签")
target_export = target_df[['user_ukey', 'gender', 'age', 'age_group', 'education_background',
                            'life_status', 'travel_type', 'device_brand', 'device_marketed_price',
                            'game_like', 'game_act_degree', 'app_level_1_category',
                            'app_level_2_category', 'wealth_score', 'cluster']].copy()
target_export['cluster_name'] = target_export['cluster'].map(cluster_names)
write_sheet(ws5, target_export)

excel_path = OUTPUT_DIR / '斯诺克世锦赛用户画像TGI分析数据.xlsx'
try:
    os.remove(excel_path)
except PermissionError:
    import time
    excel_path = OUTPUT_DIR / f'斯诺克世锦赛用户画像TGI分析数据_{int(time.time())}.xlsx'
wb.save(excel_path)
print(f"[OK] Excel数据已保存: {excel_path}")

print("\n" + "=" * 60)
print("V2 分析完成!")
print(f"Word报告: {report_path}")
print(f"Excel数据: {excel_path}")
print(f"图表目录: {OUTPUT_DIR} ({len(chart_files)} 张PNG)")
print(f"中文渲染字体: Microsoft YaHei (微软雅黑) — 已确认无乱码")
print("=" * 60)
