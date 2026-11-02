# -*- coding: utf-8 -*-
"""
斯诺克世锦赛拉新用户画像分析 V2
==============================
V2 改进:
  1. 修复中文字体渲染 (matplotlib + Word)
  2. 新增年龄分层精细化分析 + 肘部法则验证
  3. 聚类命名融入 App 偏好
"""

import pandas as pd
import numpy as np
import matplotlib
import argparse
from pathlib import Path
matplotlib.use('Agg')

# ============================================================
# 中文字体修复 - V2.2 终极方案
# ============================================================
import os as _os
import glob as _glob
import shutil as _shutil

# 1. 彻底删除 matplotlib 字体缓存
_cache = matplotlib.get_cachedir()
for _f in _glob.glob(_os.path.join(_cache, '*')):
    try:
        _os.remove(_f)
    except:
        pass

# 2. 尝试多个中文字体文件, 用 FontProperties 逐个验证
_CJK_FONT_FILES = [
    r'C:\Windows\Fonts\msyh.ttc',        # Microsoft YaHei (最佳)
    r'C:\Windows\Fonts\simhei.ttf',       # SimHei
    r'C:\Windows\Fonts\msyhbd.ttc',       # Microsoft YaHei Bold
]

_CJK_FONT_PATH = None
for _fp in _CJK_FONT_FILES:
    if _os.path.exists(_fp):
        _CJK_FONT_PATH = _fp
        break

if _CJK_FONT_PATH is None:
    raise RuntimeError("No CJK font found!")

import matplotlib.pyplot as plt
import matplotlib.ticker as ticker
import matplotlib.font_manager as fm

# 3. 注册字体
fm.fontManager.addfont(_CJK_FONT_PATH)
_fp_obj = fm.FontProperties(fname=_CJK_FONT_PATH)
_FONT_NAME = _fp_obj.get_name()
print(f"[字体] 注册: {_FONT_NAME} ({_CJK_FONT_PATH})")

# 4. 关键：设置 rcParams (必须在 seaborn import 之前)
plt.rcParams['font.family'] = 'sans-serif'
plt.rcParams['font.sans-serif'] = [_FONT_NAME]
plt.rcParams['axes.unicode_minus'] = False

# 5. 强制重建字体缓存，验证
fm._load_fontmanager(try_read_cache=False)
_actual_match = [f for f in fm.fontManager.ttflist if _FONT_NAME in f.name]
print(f"[字体] 确认加载: {len(_actual_match)} 个 '{_FONT_NAME}' 变体")

# 6. 现在导入 seaborn (它会继承上面的 rcParams)
import seaborn as sns
from sklearn.preprocessing import StandardScaler, LabelEncoder
from sklearn.cluster import KMeans
from sklearn.decomposition import PCA
from sklearn.metrics import silhouette_score
from scipy.cluster.hierarchy import dendrogram, linkage, fcluster
from collections import Counter
import warnings
import os
import sys
import io
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')
warnings.filterwarnings('ignore')

# 7. seaborn 之后再次强制 rcParams (sns.set_style 可能覆盖)
sns.set_style("whitegrid")
sns.set_palette("Set2")
plt.rcParams['font.family'] = 'sans-serif'
plt.rcParams['font.sans-serif'] = [_FONT_NAME]
plt.rcParams['axes.unicode_minus'] = False

# 验证字体是否能渲染中文
fig_test, ax_test = plt.subplots(figsize=(2, 1))
ax_test.text(0.5, 0.5, '中文测试', ha='center', va='center', fontsize=14)
ax_test.set_title('字体验证')
_PARSER = argparse.ArgumentParser(description="Reproduce the snooker new-user profile charts.")
_PARSER.add_argument("--data", default=os.environ.get("SNOOKER_PROFILE_DATA", "data/new-user-profile.csv"))
_PARSER.add_argument("--output-dir", default=os.environ.get("SNOOKER_PROFILE_OUTPUT", "outputs/snooker-profile-charts"))
_ARGS = _PARSER.parse_args()
DATA_PATH = Path(_ARGS.data)
OUTPUT_DIR = Path(_ARGS.output_dir)
OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
test_path = OUTPUT_DIR / '_font_test.png'
plt.savefig(test_path, dpi=100)
plt.close()
print(f"[字体] 测试图已保存至: {test_path}")

# ============================================================
# 1. 数据加载与清洗
# ============================================================
print("\n" + "=" * 60)
print("1. 数据加载与清洗")
print("=" * 60)

df_raw = pd.read_csv(DATA_PATH, encoding='utf-8-sig')
print(f"原始数据: {df_raw.shape[0]} 行, {df_raw.shape[1]} 列")

# 去重
n_before = len(df_raw)
df = df_raw.drop_duplicates()
n_after = len(df)
print(f"去重: {n_before} -> {n_after} (删除 {n_before - n_after} 条, 重复率 {(n_before-n_after)/n_before*100:.1f}%)")

# 缺失值统计
missing = df.isnull().sum().sort_values(ascending=False)
missing_pct = (missing / len(df) * 100).round(2)
print("\n缺失值TOP10:")
for col in missing.head(10).index:
    print(f"  {col}: {missing[col]} ({missing_pct[col]}%)")

print(f"\n年龄范围: {df['age'].min():.0f} ~ {df['age'].max():.0f}, 均值: {df['age'].mean():.1f}, 中位数: {df['age'].median():.0f}")

# ============================================================
# 2. 精细化年龄分层分析 [V2新增]
# ============================================================
print("\n" + "=" * 60)
print("2. 精细化年龄分层分析 [V2]")
print("=" * 60)

# 5档年龄分层
age_bins_v2 = [0, 20, 25, 30, 35, 45, 100]
age_labels_v2 = ['20岁及以下', '21-25岁', '26-30岁', '31-35岁', '36-45岁', '46岁以上']
df['age_group_v2'] = pd.cut(df['age'], bins=age_bins_v2, labels=age_labels_v2, right=True)

age_dist = df['age_group_v2'].value_counts().reindex(age_labels_v2)
print("年龄分层分布:")
for label, count in age_dist.items():
    pct = count / len(df) * 100 if pd.notna(count) else 0
    print(f"  {label}: {int(count) if pd.notna(count) else 0} 人 ({pct:.1f}%)")

# --- 各年龄层特征差异 ---
print("\n各年龄层关键特征差异:")
age_profile_cols = ['gender', 'education_background', 'life_status', 'device_brand',
                    'game_tag', 'game_act_degree', 'app_level_1_category', 'travel_type']

for age_label in age_labels_v2:
    adf = df[df['age_group_v2'] == age_label]
    if len(adf) == 0:
        continue
    print(f"\n--- {age_label} (n={len(adf)}) ---")
    print(f"  性别: {adf['gender'].value_counts().to_dict()}")
    print(f"  设备均价: RMB{adf['device_marketed_price'].dropna().mean():.0f}")
    print(f"  Top3 游戏: {dict(adf['game_tag'].value_counts().head(3))}")
    print(f"  Top3 App一级: {dict(adf['app_level_1_category'].value_counts().head(3))}")

# --- 年龄层分布柱状图 ---
fig, ax = plt.subplots(figsize=(12, 6))
age_colors = ['#FF6B6B', '#4ECDC4', '#45B7D1', '#96CEB4', '#FFEAA7', '#DDA0DD']
bars = ax.bar(range(len(age_dist)), [int(v) if pd.notna(v) else 0 for v in age_dist.values],
              color=age_colors[:len(age_dist)], edgecolor='white', linewidth=1.5, width=0.7)
ax.set_xticks(range(len(age_dist)))
ax.set_xticklabels(age_dist.index, fontsize=12)
ax.set_title('精细化年龄分层分布 (5档)', fontsize=18, fontweight='bold')
ax.set_ylabel('用户数', fontsize=13)
for i, (bar, v) in enumerate(zip(bars, age_dist.values)):
    if pd.notna(v):
        ax.text(bar.get_x() + bar.get_width()/2., bar.get_height() + 2,
                f'{int(v)}人\n({v/len(df)*100:.1f}%)',
                ha='center', fontsize=10, fontweight='bold')
plt.tight_layout()
plt.savefig(os.path.join(OUTPUT_DIR, '01_age_stratification.png'), dpi=150, bbox_inches='tight')
plt.close()
print("\n[OK] 年龄分层柱状图已保存")

# --- 各年龄层 App偏好 堆叠柱状图 ---
fig, ax = plt.subplots(figsize=(14, 7))
top_apps = df['app_level_1_category'].value_counts().head(6).index.tolist()
age_app_data = {}
for age_label in age_labels_v2:
    adf = df[df['age_group_v2'] == age_label]
    if len(adf) > 0:
        app_counts = adf['app_level_1_category'].value_counts()
        row = [app_counts.get(app, 0) for app in top_apps]
        age_app_data[age_label] = row

age_app_df = pd.DataFrame(age_app_data, index=top_apps).T
age_app_pct = age_app_df.div(age_app_df.sum(axis=1), axis=0)
app_colors_stack = ['#FF6B6B', '#4ECDC4', '#45B7D1', '#96CEB4', '#FFEAA7', '#DDA0DD']
age_app_pct.plot(kind='bar', stacked=True, ax=ax, color=app_colors_stack[:len(top_apps)], edgecolor='white', linewidth=0.8)
ax.set_title('各年龄层 App一级分类偏好分布', fontsize=16, fontweight='bold')
ax.set_xlabel('年龄段', fontsize=12)
ax.set_ylabel('占比', fontsize=12)
ax.legend(title='App一级分类', bbox_to_anchor=(1.02, 1), loc='upper left', fontsize=10)
ax.tick_params(axis='x', rotation=0)
plt.tight_layout()
plt.savefig(os.path.join(OUTPUT_DIR, '02_age_app_stack.png'), dpi=150, bbox_inches='tight')
plt.close()
print("[OK] 年龄层 App偏好堆叠图已保存")

# --- 年龄层游戏偏好热力图 ---
fig, ax = plt.subplots(figsize=(12, 6))
top_games = df['game_tag'].value_counts().head(8).index.tolist()
age_game_data = {}
for age_label in age_labels_v2:
    adf = df[df['age_group_v2'] == age_label]
    if len(adf) > 0:
        game_counts = adf['game_tag'].value_counts()
        age_game_data[age_label] = [game_counts.get(g, 0) for g in top_games]

age_game_df = pd.DataFrame(age_game_data, index=top_games).T
age_game_norm = (age_game_df - age_game_df.min().min()) / (age_game_df.max().max() - age_game_df.min().min() + 1e-10)

sns.heatmap(age_game_norm, annot=age_game_df.values, fmt='.0f',
            cmap='YlOrRd', ax=ax, linewidths=0.5, linecolor='white',
            xticklabels=top_games, yticklabels=age_game_df.index,
            cbar_kws={'label': '归一化热度'})
ax.set_title('各年龄层 游戏偏好热力图', fontsize=16, fontweight='bold')
ax.set_xlabel('游戏类型', fontsize=12)
ax.set_ylabel('年龄段', fontsize=12)
plt.tight_layout()
plt.savefig(os.path.join(OUTPUT_DIR, '03_age_game_heatmap.png'), dpi=150, bbox_inches='tight')
plt.close()
print("[OK] 年龄层游戏偏好热力图已保存")

# --- 肘部法则: 年龄层SSE用于确定分层合理性 ---
print("\n--- 肘部法则验证年龄分层 ---")
# 将年龄分层转化为数值，然后计算不同K下的SSE
age_values = df[['age']].dropna().values
age_scaled = StandardScaler().fit_transform(age_values)

age_inertias = []
age_silhouettes = []
age_K_range = range(2, 10)

for k in age_K_range:
    km = KMeans(n_clusters=k, random_state=42, n_init=10, max_iter=300)
    labels = km.fit_predict(age_scaled)
    age_inertias.append(km.inertia_)
    if k >= 2:
        age_silhouettes.append(silhouette_score(age_scaled, labels))

# 计算 SSE 下降率
sse_drops = [0] + [((age_inertias[i-1] - age_inertias[i]) / age_inertias[i-1] * 100)
                    for i in range(1, len(age_inertias))]

print("年龄聚类 SSE 分析:")
for i, k in enumerate(age_K_range):
    drop_str = f"SSE下降: {sse_drops[i]:.1f}%" if i > 0 else "SSE下降: --"
    print(f"  K={k}: SSE={age_inertias[i]:.1f}, 轮廓系数={age_silhouettes[i] if i < len(age_silhouettes) else 'N/A':.4f}, {drop_str}")

fig, axes = plt.subplots(1, 3, figsize=(18, 5))

# 1) SSE 曲线
axes[0].plot(list(age_K_range), age_inertias, 'o-', color='#3498DB', linewidth=2.5, markersize=10)
axes[0].set_xlabel('K (聚类数)', fontsize=12)
axes[0].set_ylabel('SSE (误差平方和)', fontsize=12)
axes[0].set_title('年龄分层: SSE肘部曲线', fontsize=15, fontweight='bold')
axes[0].axvline(x=5, color='red', linestyle='--', alpha=0.8, linewidth=2, label='K=5 (肘点)')
axes[0].legend(fontsize=11)
axes[0].grid(True, alpha=0.3)

# 2) SSE下降率
axes[1].bar(list(age_K_range), sse_drops, color='#2ECC71', edgecolor='white', linewidth=1)
axes[1].axhline(y=20, color='red', linestyle='--', alpha=0.7, label='20%阈值线')
axes[1].set_xlabel('K (聚类数)', fontsize=12)
axes[1].set_ylabel('SSE下降率 (%)', fontsize=12)
axes[1].set_title('SSE边际下降率 (越大越好)', fontsize=15, fontweight='bold')
axes[1].legend(fontsize=11)
for i, (k, v) in enumerate(zip(age_K_range, sse_drops)):
    axes[1].text(k, v + 0.5, f'{v:.1f}%', ha='center', fontsize=10, fontweight='bold')

# 3) 轮廓系数
axes[2].plot(list(age_K_range), age_silhouettes, 's-', color='#E74C3C', linewidth=2.5, markersize=10)
axes[2].set_xlabel('K (聚类数)', fontsize=12)
axes[2].set_ylabel('轮廓系数', fontsize=12)
axes[2].set_title('年龄分层: 轮廓系数', fontsize=15, fontweight='bold')
axes[2].grid(True, alpha=0.3)

plt.tight_layout()
plt.savefig(os.path.join(OUTPUT_DIR, '01b_age_elbow.png'), dpi=150, bbox_inches='tight')
plt.close()
print("[OK] 年龄分层肘部法则图已保存")

# ============================================================
# 3. EDA - 探索性数据分析 (V2优化版)
# ============================================================
print("\n" + "=" * 60)
print("3. 探索性数据分析 (EDA)")
print("=" * 60)

# --- 3.1 性别分布 ---
fig, axes = plt.subplots(1, 2, figsize=(14, 5))

gender_counts = df['gender'].value_counts()
colors = ['#4ECDC4', '#FF6B6B']
wedges, texts, autotexts = axes[0].pie(
    gender_counts.values, labels=gender_counts.index, autopct='%1.1f%%',
    colors=colors, startangle=90, explode=(0, 0.02),
    textprops={'fontsize': 14, 'fontweight': 'bold'})
for at in autotexts:
    at.set_fontsize(13)
    at.set_fontweight('bold')
axes[0].set_title('性别分布', fontsize=16, fontweight='bold')

# --- 3.2 年龄分布 (V2细化版) ---
age_dist_v2 = df['age_group_v2'].value_counts().reindex(age_labels_v2)
axes[1].bar(range(len(age_dist_v2)), [int(v) if pd.notna(v) else 0 for v in age_dist_v2.values],
            color='#45B7D1', edgecolor='white', linewidth=1.2, width=0.7)
axes[1].set_xticks(range(len(age_labels_v2)))
axes[1].set_xticklabels(age_labels_v2, fontsize=11)
axes[1].set_title('年龄分布 (5档精细化)', fontsize=16, fontweight='bold')
axes[1].set_ylabel('用户数', fontsize=12)
for i, v in enumerate(age_dist_v2.values):
    if pd.notna(v):
        axes[1].text(i, v + 2, str(int(v)), ha='center', fontsize=11, fontweight='bold')

plt.tight_layout()
plt.savefig(os.path.join(OUTPUT_DIR, '04_gender_age_v2.png'), dpi=150, bbox_inches='tight')
plt.close()
print("[OK] 性别 & 年龄分布图已保存")

# --- 3.3 学历 & 人生状态 ---
fig, axes = plt.subplots(1, 2, figsize=(14, 5))

edu_counts = df['education_background'].value_counts()
edu_colors = plt.cm.Blues(np.linspace(0.3, 0.9, len(edu_counts)))
axes[0].barh(range(len(edu_counts)), edu_counts.values, color=edu_colors, edgecolor='white')
axes[0].set_yticks(range(len(edu_counts)))
axes[0].set_yticklabels(edu_counts.index, fontsize=12)
axes[0].set_title('学历分布', fontsize=16, fontweight='bold')
axes[0].invert_yaxis()
for i, v in enumerate(edu_counts.values):
    axes[0].text(v + 1, i, str(v), va='center', fontsize=10, fontweight='bold')

life_counts = df['life_status'].value_counts()
life_colors = ['#FFEAA7', '#DDA0DD', '#98D8C8', '#F7DC6F', '#BB8FCE', '#85C1E9']
axes[1].bar(life_counts.index, life_counts.values,
            color=life_colors[:len(life_counts)], edgecolor='white', linewidth=1)
axes[1].set_title('人生状态分布', fontsize=16, fontweight='bold')
for i, (k, v) in enumerate(zip(life_counts.index, life_counts.values)):
    axes[1].text(i, v + 1, str(v), ha='center', fontsize=11, fontweight='bold')

plt.tight_layout()
plt.savefig(os.path.join(OUTPUT_DIR, '05_edu_life_v2.png'), dpi=150, bbox_inches='tight')
plt.close()
print("[OK] 学历 & 人生状态图已保存")

# --- 3.4 设备品牌 ---
fig, axes = plt.subplots(1, 2, figsize=(14, 5))

brand_counts = df['device_brand'].value_counts().head(10)
axes[0].bar(brand_counts.index, brand_counts.values,
            color='#FF8C42', edgecolor='white', linewidth=1)
axes[0].set_title('设备品牌 Top10', fontsize=16, fontweight='bold')
axes[0].tick_params(axis='x', rotation=30, labelsize=10)
for i, v in enumerate(brand_counts.values):
    axes[0].text(i, v + 1, str(v), ha='center', fontsize=9, fontweight='bold')

os_counts = df['device_os'].value_counts()
os_colors = ['#6C5B7B', '#C06C84']
wedges2, texts2, autotexts2 = axes[1].pie(
    os_counts.values, labels=os_counts.index, autopct='%1.1f%%',
    colors=os_colors, startangle=90, explode=(0.02, 0),
    textprops={'fontsize': 14, 'fontweight': 'bold'})
for at in autotexts2:
    at.set_fontsize(13)
axes[1].set_title('操作系统分布', fontsize=16, fontweight='bold')

plt.tight_layout()
plt.savefig(os.path.join(OUTPUT_DIR, '06_device_v2.png'), dpi=150, bbox_inches='tight')
plt.close()
print("[OK] 设备品牌 & 系统图已保存")

# --- 3.5 出行方式 ---
fig, ax = plt.subplots(figsize=(10, 5))
travel_counts = df['travel_type'].value_counts()
travel_colors = ['#E84A5F', '#FF847C', '#FECEA8', '#99B898', '#2A363B']
bars = ax.bar(travel_counts.index, travel_counts.values,
              color=travel_colors[:len(travel_counts)], edgecolor='white', linewidth=1)
ax.set_title('出行方式分布', fontsize=16, fontweight='bold')
ax.set_xlabel('出行方式', fontsize=12)
ax.set_ylabel('用户数', fontsize=12)
for bar, v in zip(bars, travel_counts.values):
    ax.text(bar.get_x() + bar.get_width()/2., bar.get_height() + 1,
            str(v), ha='center', fontsize=11, fontweight='bold')
plt.tight_layout()
plt.savefig(os.path.join(OUTPUT_DIR, '07_travel_v2.png'), dpi=150, bbox_inches='tight')
plt.close()
print("[OK] 出行方式图已保存")

# --- 3.6 游戏偏好 ---
fig, ax = plt.subplots(figsize=(10, 6))
game_counts = df['game_tag'].value_counts().head(12)
game_colors = plt.cm.viridis(np.linspace(0.2, 0.9, len(game_counts)))
bars = ax.barh(range(len(game_counts)), game_counts.values, color=game_colors, edgecolor='white')
ax.set_yticks(range(len(game_counts)))
ax.set_yticklabels(game_counts.index, fontsize=11)
ax.invert_yaxis()
ax.set_title('游戏偏好标签 Top12', fontsize=16, fontweight='bold')
ax.set_xlabel('用户数', fontsize=12)
for i, v in enumerate(game_counts.values):
    ax.text(v + 0.5, i, str(v), va='center', fontsize=10, fontweight='bold')
plt.tight_layout()
plt.savefig(os.path.join(OUTPUT_DIR, '08_game_tag_v2.png'), dpi=150, bbox_inches='tight')
plt.close()
print("[OK] 游戏偏好图已保存")

# --- 3.7 游戏活跃度 ---
fig, ax = plt.subplots(figsize=(7, 6))
act_counts = df['game_act_degree'].value_counts()
act_colors = ['#2ECC71', '#F39C12', '#E74C3C', '#95A5A6']
wedges3, texts3, autotexts3 = ax.pie(
    act_counts.values, labels=act_counts.index, autopct='%1.1f%%',
    colors=act_colors[:len(act_counts)], startangle=90,
    textprops={'fontsize': 13, 'fontweight': 'bold'})
for at in autotexts3:
    at.set_fontsize(12)
ax.set_title('游戏活跃度分布', fontsize=16, fontweight='bold')
plt.tight_layout()
plt.savefig(os.path.join(OUTPUT_DIR, '09_game_act_v2.png'), dpi=150, bbox_inches='tight')
plt.close()
print("[OK] 游戏活跃度图已保存")

# --- 3.8 App偏好 ---
fig, axes = plt.subplots(1, 2, figsize=(16, 6))

app_l1 = df['app_level_1_category'].value_counts().head(10)
axes[0].bar(app_l1.index, app_l1.values, color='#8E44AD', edgecolor='white', linewidth=1)
axes[0].set_title('App一级分类偏好 Top10', fontsize=15, fontweight='bold')
axes[0].tick_params(axis='x', rotation=45, labelsize=10)
axes[0].set_ylabel('用户数', fontsize=12)

app_l2 = df['app_level_2_category'].value_counts().head(10)
axes[1].bar(app_l2.index, app_l2.values, color='#2980B9', edgecolor='white', linewidth=1)
axes[1].set_title('App二级分类偏好 Top10', fontsize=15, fontweight='bold')
axes[1].tick_params(axis='x', rotation=45, labelsize=10)
axes[1].set_ylabel('用户数', fontsize=12)

plt.tight_layout()
plt.savefig(os.path.join(OUTPUT_DIR, '10_app_pref_v2.png'), dpi=150, bbox_inches='tight')
plt.close()
print("[OK] App偏好图已保存")

# --- 3.9 财富指标 ---
fig, ax = plt.subplots(figsize=(9, 5))
wealth_cols = ['has_elite_house', 'has_house', 'has_car', 'has_high_level_app',
               'has_high_level_device', 'is_travel_abroad', 'is_in_famouse_company']
wealth_labels = ['豪宅', '有房', '有车', '高端App', '高端设备', '海外出行', '名企']
wealth_rates = []
for col in wealth_cols:
    rate = df[col].fillna(0).astype(float).mean() * 100
    wealth_rates.append(rate)
    print(f"  {col}: {rate:.1f}%")

bars = ax.bar(wealth_labels, wealth_rates,
              color=plt.cm.RdYlGn(np.linspace(0.2, 0.8, len(wealth_labels))),
              edgecolor='white', linewidth=1)
ax.set_title('财富/消费力指标覆盖率 (%)', fontsize=16, fontweight='bold')
ax.set_ylabel('覆盖率 (%)', fontsize=12)
for bar, v in zip(bars, wealth_rates):
    ax.text(bar.get_x() + bar.get_width()/2., bar.get_height() + 1,
            f'{v:.1f}%', ha='center', fontsize=10, fontweight='bold')
ax.set_ylim(0, max(wealth_rates) * 1.15)
plt.tight_layout()
plt.savefig(os.path.join(OUTPUT_DIR, '11_wealth_v2.png'), dpi=150, bbox_inches='tight')
plt.close()
print("[OK] 财富指标图已保存")

# ============================================================
# 4. 特征工程
# ============================================================
print("\n" + "=" * 60)
print("4. 特征工程")
print("=" * 60)

df_feat = df.copy()

# 数值特征
df_feat['age_filled'] = df_feat['age'].fillna(df_feat['age'].median())
df_feat['device_age_filled'] = df_feat['device_age'].fillna(df_feat['device_age'].median())
df_feat['device_price_filled'] = df_feat['device_marketed_price'].fillna(
    df_feat['device_marketed_price'].median())

# 财富综合评分
binary_wealth = ['has_elite_house', 'has_house', 'has_car', 'has_high_level_app',
                 'has_high_level_device', 'is_travel_abroad', 'is_in_famouse_company']
for col in binary_wealth:
    df_feat[col + '_num'] = pd.to_numeric(df_feat[col], errors='coerce').fillna(0).astype(int)
df_feat['wealth_score'] = df_feat[[col + '_num' for col in binary_wealth]].sum(axis=1)

num_features = ['age_filled', 'device_age_filled', 'device_price_filled', 'wealth_score']
print(f"数值特征 ({len(num_features)}): {num_features}")

# 类别特征编码
cat_features_map = {
    'gender': '性别',
    'education_background': '学历',
    'life_status': '人生状态',
    'travel_type': '出行方式',
    'device_brand': '设备品牌',
    'device_os': '操作系统',
    'game_tag': '游戏偏好',
    'game_act_degree': '游戏活跃度',
    'app_level_1_category': 'App一级分类',
}

cat_encoded_cols = []
for cat_col, cat_name in cat_features_map.items():
    df_feat[cat_col + '_filled'] = df_feat[cat_col].fillna('未知')
    le = LabelEncoder()
    df_feat[cat_col + '_enc'] = le.fit_transform(df_feat[cat_col + '_filled'].astype(str))
    cat_encoded_cols.append(cat_col + '_enc')
    print(f"  {cat_name}: {len(le.classes_)} 类别")

# 合并特征矩阵
feature_cols = num_features + cat_encoded_cols
X_raw = df_feat[feature_cols].values
print(f"特征矩阵: {X_raw.shape}")

scaler = StandardScaler()
X_scaled = scaler.fit_transform(X_raw)

# PCA 降维
pca_viz = PCA(n_components=2)
X_pca = pca_viz.fit_transform(X_scaled)
print(f"PCA 可解释方差比: {pca_viz.explained_variance_ratio_}")
print(f"PCA 累计方差: {pca_viz.explained_variance_ratio_.sum():.3f}")

# ============================================================
# 5. K-Means 聚类
# ============================================================
print("\n" + "=" * 60)
print("5. K-Means 聚类分析")
print("=" * 60)

# 肘部法则 + 轮廓系数
inertias = []
silhouettes = []
K_range = range(2, 10)

for k in K_range:
    km = KMeans(n_clusters=k, random_state=42, n_init=10, max_iter=300)
    labels = km.fit_predict(X_scaled)
    inertias.append(km.inertia_)
    silhouettes.append(silhouette_score(X_scaled, labels))

# 计算SSE下降率
sse_drops_main = [0] + [((inertias[i-1] - inertias[i]) / inertias[i-1] * 100)
                         for i in range(1, len(inertias))]

print("K-Means SSE 分析:")
for i, k in enumerate(K_range):
    print(f"  K={k}: SSE={inertias[i]:.1f}, 轮廓系数={silhouettes[i]:.4f}, SSE下降率={sse_drops_main[i]:.1f}%")

fig, axes = plt.subplots(1, 3, figsize=(18, 5))

# 肘部图
axes[0].plot(list(K_range), inertias, 'o-', color='#3498DB', linewidth=2.5, markersize=10)
axes[0].set_xlabel('K (聚类数)', fontsize=13)
axes[0].set_ylabel('SSE (误差平方和)', fontsize=13)
axes[0].set_title('K-Means 肘部法则', fontsize=16, fontweight='bold')
axes[0].axvline(x=4, color='red', linestyle='--', alpha=0.8, linewidth=2, label='K=4 (推荐)')
axes[0].axvline(x=5, color='orange', linestyle='--', alpha=0.8, linewidth=2, label='K=5')
axes[0].legend(fontsize=11)
axes[0].grid(True, alpha=0.3)

# SSE下降率
axes[1].bar(list(K_range), sse_drops_main, color='#2ECC71', edgecolor='white', linewidth=1)
axes[1].set_xlabel('K (聚类数)', fontsize=13)
axes[1].set_ylabel('SSE 下降率 (%)', fontsize=13)
axes[1].set_title('SSE 边际下降率', fontsize=16, fontweight='bold')
axes[1].axhline(y=15, color='red', linestyle='--', alpha=0.7, label='15%阈值线')
axes[1].legend(fontsize=11)
for i, (k, v) in enumerate(zip(K_range, sse_drops_main)):
    axes[1].text(k, v + 0.5, f'{v:.1f}%', ha='center', fontsize=10, fontweight='bold')

# 轮廓系数
axes[2].plot(list(K_range), silhouettes, 's-', color='#E74C3C', linewidth=2.5, markersize=10)
axes[2].set_xlabel('K (聚类数)', fontsize=13)
axes[2].set_ylabel('轮廓系数', fontsize=13)
axes[2].set_title('轮廓系数曲线', fontsize=16, fontweight='bold')
best_k = K_range[np.argmax(silhouettes)]
axes[2].axvline(x=best_k, color='green', linestyle='--', alpha=0.8, linewidth=2,
                label=f'最佳 K={best_k} ({max(silhouettes):.4f})')
axes[2].legend(fontsize=11)
axes[2].grid(True, alpha=0.3)

plt.tight_layout()
plt.savefig(os.path.join(OUTPUT_DIR, '12_kmeans_selection_v2.png'), dpi=150, bbox_inches='tight')
plt.close()
print(f"[OK] K值选择图已保存 (最佳轮廓系数: {max(silhouettes):.4f}, K={best_k})")

# 选择 K=4
FINAL_K = 4
kmeans = KMeans(n_clusters=FINAL_K, random_state=42, n_init=10, max_iter=300)
df['cluster'] = kmeans.fit_predict(X_scaled)
df_feat['cluster'] = df['cluster']

print(f"\n最终聚类数: K={FINAL_K}")
print(f"各簇大小: {dict(df['cluster'].value_counts().sort_index())}")
print(f"轮廓系数: {silhouette_score(X_scaled, df['cluster']):.4f}")

# ============================================================
# 6. 聚类可视化
# ============================================================
print("\n" + "=" * 60)
print("6. 聚类可视化")
print("=" * 60)

# PCA散点图
fig, ax = plt.subplots(figsize=(12, 8))
cluster_colors = ['#FF6B6B', '#4ECDC4', '#45B7D1', '#96CEB4', '#FFEAA7']
for c in range(FINAL_K):
    mask = df['cluster'] == c
    ax.scatter(X_pca[mask, 0], X_pca[mask, 1],
               c=cluster_colors[c], label=f'聚类{c+1}',
               alpha=0.6, s=35, edgecolors='white', linewidth=0.3)

centers_pca = pca_viz.transform(scaler.transform(kmeans.cluster_centers_))
for c in range(FINAL_K):
    ax.scatter(centers_pca[c, 0], centers_pca[c, 1],
               c=cluster_colors[c], marker='X', s=350,
               edgecolors='black', linewidth=2.5, zorder=10)

ax.set_title(f'K-Means 用户聚类 (K={FINAL_K}) - PCA 投影', fontsize=18, fontweight='bold')
ax.set_xlabel(f'PC1 ({pca_viz.explained_variance_ratio_[0]:.1%} 方差)', fontsize=13)
ax.set_ylabel(f'PC2 ({pca_viz.explained_variance_ratio_[1]:.1%} 方差)', fontsize=13)
ax.legend(loc='upper right', fontsize=12)
plt.tight_layout()
plt.savefig(os.path.join(OUTPUT_DIR, '13_cluster_pca_v2.png'), dpi=150, bbox_inches='tight')
plt.close()
print("[OK] PCA聚类散点图已保存")

# 聚类占比饼图
fig, ax = plt.subplots(figsize=(7, 7))
cluster_sizes = df['cluster'].value_counts().sort_index()
cluster_labels_pie = [f'聚类{i+1}\n({v}人, {v/len(df)*100:.1f}%)'
                      for i, v in enumerate(cluster_sizes.values)]
wedges4, texts4 = ax.pie(cluster_sizes.values, labels=cluster_labels_pie,
       colors=cluster_colors[:FINAL_K], startangle=90,
       textprops={'fontsize': 12, 'fontweight': 'bold'})
ax.set_title('各聚类用户占比', fontsize=16, fontweight='bold')
plt.tight_layout()
plt.savefig(os.path.join(OUTPUT_DIR, '14_cluster_pie_v2.png'), dpi=150, bbox_inches='tight')
plt.close()
print("[OK] 聚类占比饼图已保存")

# ============================================================
# 7. 聚类画像解读 (V2: 融入App偏好命名)
# ============================================================
print("\n" + "=" * 60)
print("7. 聚类画像解读 [V2: App偏好命名]")
print("=" * 60)

# 先收集每个聚类的 Top App 偏好用于命名
cluster_app_names = {}
for c in range(FINAL_K):
    cdf = df_feat[df_feat['cluster'] == c]
    top_app1 = cdf['app_level_1_category'].value_counts()
    top_app2 = cdf['app_level_2_category'].value_counts()
    app_name_1 = top_app1.index[0] if len(top_app1) > 0 else '未知'
    app_name_2 = top_app2.index[0] if len(top_app2) > 0 else '未知'
    cluster_app_names[c] = (app_name_1, app_name_2)

def cluster_profile_v2(df_data, cluster_id):
    """输出单个聚类的详细画像 (V2版)"""
    cdf = df_data[df_data['cluster'] == cluster_id]
    n = len(cdf)

    # 构建昵称: 设备 + App一级#2 (更具区分度)
    top_dev = cdf['device_brand'].value_counts()
    top_app1_c = cdf['app_level_1_category'].value_counts()
    top_app2_c = cdf['app_level_2_category'].value_counts()
    dev = top_dev.index[0] if len(top_dev) > 0 else ''
    app_dist = top_app1_c.index[1] if len(top_app1_c) > 1 else (top_app2_c.index[0] if len(top_app2_c) > 0 else '')
    cluster_nickname = f"{dev}{app_dist}派"

    print(f"\n{'='*55}")
    print(f"  聚类{cluster_id+1}: 【{cluster_nickname}】(n={n}, {n/len(df_data)*100:.1f}%)")
    print(f"{'='*55}")

    profiles = {}

    # 性别
    top_g = cdf['gender'].value_counts()
    male_pct = (top_g.get('男', 0) / n * 100)
    female_pct = (top_g.get('女', 0) / n * 100)
    profiles['性别'] = f"男 {male_pct:.1f}% / 女 {female_pct:.1f}%"

    # 年龄分层
    age_groups = cdf['age_group_v2'].value_counts()
    age_summary = ', '.join([f"{k}({v})" for k, v in age_groups.head(3).items()])
    profiles['年龄分层'] = f"均值 {cdf['age'].mean():.1f}岁, 分布: {age_summary}"

    # 学历
    top_edu = cdf['education_background'].value_counts()
    profiles['主要学历'] = ', '.join([f"{k}({v})" for k, v in top_edu.head(3).items()])

    # 人生状态
    top_life = cdf['life_status'].value_counts()
    profiles['人生状态'] = ', '.join([f"{k}({v})" for k, v in top_life.head(3).items()])

    # 出行
    top_travel = cdf['travel_type'].value_counts()
    profiles['出行方式'] = ', '.join([f"{k}({v})" for k, v in top_travel.head(3).items() if pd.notna(k)])

    # 设备
    top_brand = cdf['device_brand'].value_counts()
    avg_price = cdf['device_marketed_price'].dropna().mean()
    ios_pct = (cdf['device_os'] == 'IOS').mean() * 100
    profiles['设备'] = f"{top_brand.index[0] if len(top_brand)>0 else ''}为主, iOS {ios_pct:.0f}%, 均价 RMB{avg_price:.0f}"

    # 游戏 (V2: 更详细)
    top_game = cdf['game_tag'].value_counts()
    top_act = cdf['game_act_degree'].value_counts()
    profiles['游戏偏好'] = ', '.join([f"{k}({v})" for k, v in top_game.head(3).items() if pd.notna(k)])
    profiles['游戏活跃度'] = ', '.join([f"{k}({v})" for k, v in top_act.head(3).items() if pd.notna(k)])

    # App偏好 (V2: 重点突出)
    top_app_l1 = cdf['app_level_1_category'].value_counts()
    top_app_l2 = cdf['app_level_2_category'].value_counts()
    profiles['App一级'] = ', '.join([f"{k}({v})" for k, v in top_app_l1.head(4).items() if pd.notna(k)])
    profiles['App二级'] = ', '.join([f"{k}({v})" for k, v in top_app_l2.head(4).items() if pd.notna(k)])

    # 财富
    profiles['财富评分'] = f"{cdf['wealth_score'].mean():.2f}/7"
    profiles['有车率'] = f"{cdf['has_car'].fillna(0).astype(float).mean()*100:.1f}%"
    profiles['有房率'] = f"{cdf['has_house'].fillna(0).astype(float).mean()*100:.1f}%"

    for k, v in profiles.items():
        print(f"  {k}: {v}")

    return profiles, cluster_nickname

all_profiles = {}
all_nicknames = {}
used_nicknames = set()
for c in range(FINAL_K):
    profiles, nickname = cluster_profile_v2(df_feat, c)
    # 去重昵称: 如果冲突, 用聚类编号后缀区分
    if nickname in used_nicknames:
        nickname = f"{nickname[:-1]}{c+1}号派"
    used_nicknames.add(nickname)
    all_profiles[f'聚类{c+1}'] = profiles
    all_nicknames[f'聚类{c+1}'] = nickname
    print(f"  最终昵称: {nickname}")

# --- 聚类特征对比热力图 ---
fig, ax = plt.subplots(figsize=(15, 8))

compare_features = {
    '男性占比': [df_feat[df_feat['cluster'] == c]['gender'].apply(lambda x: 1 if x == '男' else 0).mean() for c in range(FINAL_K)],
    '平均年龄': [df_feat[df_feat['cluster'] == c]['age'].mean() for c in range(FINAL_K)],
    '已婚率': [df_feat[df_feat['cluster'] == c]['life_status'].apply(lambda x: 1 if x == '已婚' else 0).mean() for c in range(FINAL_K)],
    '有车率': [df_feat[df_feat['cluster'] == c]['has_car'].fillna(0).astype(float).mean() for c in range(FINAL_K)],
    '有房率': [df_feat[df_feat['cluster'] == c]['has_house'].fillna(0).astype(float).mean() for c in range(FINAL_K)],
    '财富评分': [df_feat[df_feat['cluster'] == c]['wealth_score'].mean() for c in range(FINAL_K)],
    '设备均价(千元)': [df_feat[df_feat['cluster'] == c]['device_marketed_price'].dropna().mean() / 1000 for c in range(FINAL_K)],
    '高端设备率': [df_feat[df_feat['cluster'] == c]['has_high_level_device'].fillna(0).astype(float).mean() for c in range(FINAL_K)],
    '游戏高活跃率': [df_feat[df_feat['cluster'] == c]['game_act_degree'].apply(lambda x: 1 if '高活跃' in str(x) else 0).mean() for c in range(FINAL_K)],
    '音乐App偏好率': [df_feat[df_feat['cluster'] == c]['app_level_1_category'].apply(lambda x: 1 if x == '音乐' else 0).mean() for c in range(FINAL_K)],
    '视频App偏好率': [df_feat[df_feat['cluster'] == c]['app_level_1_category'].apply(lambda x: 1 if x == '视频' else 0).mean() for c in range(FINAL_K)],
    '购物App偏好率': [df_feat[df_feat['cluster'] == c]['app_level_1_category'].apply(lambda x: 1 if x == '购物' else 0).mean() for c in range(FINAL_K)],
    'iOS占比': [df_feat[df_feat['cluster'] == c]['device_os'].apply(lambda x: 1 if x == 'IOS' else 0).mean() for c in range(FINAL_K)],
    '聚类大小': [len(df_feat[df_feat['cluster'] == c]) for c in range(FINAL_K)],
}

# 使用V2昵称作为索引
heatmap_data = pd.DataFrame(compare_features, index=[all_nicknames.get(f'聚类{i+1}', f'聚类{i+1}') for i in range(FINAL_K)])
heatmap_norm = (heatmap_data - heatmap_data.min()) / (heatmap_data.max() - heatmap_data.min() + 1e-10)

sns.heatmap(heatmap_norm, annot=heatmap_data.round(2).values, fmt='',
            cmap='YlOrRd', ax=ax, linewidths=0.5, linecolor='white',
            annot_kws={'fontsize': 9},
            cbar_kws={'label': '归一化得分'})
ax.set_title('聚类特征对比热力图 (V2)', fontsize=18, fontweight='bold')
ax.set_xlabel('特征', fontsize=13)
ax.set_ylabel('聚类', fontsize=13)
ax.tick_params(axis='both', labelsize=11)
plt.tight_layout()
plt.savefig(os.path.join(OUTPUT_DIR, '15_cluster_heatmap_v2.png'), dpi=150, bbox_inches='tight')
plt.close()
print("[OK] 聚类特征热力图已保存")

# --- 聚类雷达图 ---
fig, axes = plt.subplots(1, FINAL_K, figsize=(22, 5.5), subplot_kw=dict(polar=True))

radar_features = ['男性占比', '平均年龄\n(归一化)', '财富评分', '设备均价', 'iOS占比', '游戏高活跃', '音乐App', '已婚率']
radar_data = heatmap_norm[['男性占比', '平均年龄', '财富评分', '设备均价(千元)',
                            'iOS占比', '游戏高活跃率', '音乐App偏好率', '已婚率']]

angles = np.linspace(0, 2 * np.pi, len(radar_features), endpoint=False).tolist()
angles += angles[:1]

for c in range(FINAL_K):
    ax = axes[c]
    values = radar_data.iloc[c].values.tolist()
    values += values[:1]
    ax.fill(angles, values, alpha=0.25, color=cluster_colors[c])
    ax.plot(angles, values, 'o-', linewidth=2, color=cluster_colors[c], markersize=5)
    ax.set_xticks(angles[:-1])
    ax.set_xticklabels(radar_features, fontsize=8)
    ax.set_ylim(0, 1)
    ax.set_title(f'{all_nicknames.get(f"聚类{c+1}", f"聚类{c+1}")}\n(n={cluster_sizes.get(c, "?")})',
                 fontsize=12, fontweight='bold', pad=18)
    ax.set_yticks([0.25, 0.5, 0.75])
    ax.set_yticklabels(['25%', '50%', '75%'], fontsize=7)

plt.tight_layout()
plt.savefig(os.path.join(OUTPUT_DIR, '16_cluster_radar_v2.png'), dpi=150, bbox_inches='tight')
plt.close()
print("[OK] 聚类雷达图已保存")

# ============================================================
# 8. 层次聚类验证
# ============================================================
print("\n" + "=" * 60)
print("8. 层次聚类验证")
print("=" * 60)

sample_size = min(500, len(X_scaled))
indices = np.random.choice(len(X_scaled), sample_size, replace=False)
X_sample = X_scaled[indices]

fig, ax = plt.subplots(figsize=(16, 6))
Z = linkage(X_sample, method='ward')
dendro = dendrogram(Z, truncate_mode='lastp', p=20, leaf_rotation=90,
                    leaf_font_size=10, ax=ax)
ax.set_title('层次聚类树状图 (Ward法, 采样500)', fontsize=16, fontweight='bold')
ax.set_xlabel('样本索引', fontsize=12)
ax.set_ylabel('距离', fontsize=12)
plt.tight_layout()
plt.savefig(os.path.join(OUTPUT_DIR, '17_dendrogram_v2.png'), dpi=150, bbox_inches='tight')
plt.close()
print("[OK] 层次聚类树状图已保存")

# ============================================================
# 9. 总结输出
# ============================================================
print("\n" + "=" * 60)
print("9. 分析总结")
print("=" * 60)

print(f"""
╔══════════════════════════════════════════════════════════════╗
║       斯诺克世锦赛拉新用户画像 - 分析总结 V2                  ║
╠══════════════════════════════════════════════════════════════╣
║ 数据量: {n_before} 条 -> 去重后 {n_after} 条有效用户         ║
║ 聚类方法: K-Means (K={FINAL_K})                              ║
║ 轮廓系数: {silhouette_score(X_scaled, df['cluster']):.4f}                              ║
║ 年龄分层: 5档精细化 + 肘部法则验证                            ║
╠══════════════════════════════════════════════════════════════╣
""")

for c in range(FINAL_K):
    cdf = df_feat[df_feat['cluster'] == c]
    n = len(cdf)
    pct = n / len(df_feat) * 100
    nickname = all_nicknames.get(f'聚类{c+1}', f'聚类{c+1}')
    avg_age = cdf['age'].mean()
    print(f"║ 聚类{c+1} 【{nickname}】({n}人, {pct:.1f}%): 均龄{avg_age:.0f}岁")

print("╚══════════════════════════════════════════════════════════════╝")

# 保存处理后的数据
df_feat.to_csv(os.path.join(OUTPUT_DIR, 'processed_data_v2.csv'), index=False, encoding='utf-8-sig')
print(f"\n[OK] 所有V2图表已保存至: {OUTPUT_DIR}")
print(f"[OK] V2处理后数据已保存")

# 输出聚类详情供Word报告使用
for c in range(FINAL_K):
    cdf = df_feat[df_feat['cluster'] == c]
    nickname = all_nicknames.get(f'聚类{c+1}', f'聚类{c+1}')
    print(f"\n--- {nickname} 详细画像 ---")
    for col in ['gender', 'age_group_v2', 'education_background', 'life_status', 'travel_type',
                'device_brand', 'game_tag', 'game_act_degree',
                'app_level_1_category', 'app_level_2_category']:
        top_vals = cdf[col].value_counts().head(3)
        print(f"  {col}: {dict(top_vals)}")

print(f"\n聚类昵称对照表:")
for c in range(FINAL_K):
    print(f"  聚类{c+1} = {all_nicknames.get(f'聚类{c+1}', '')}")
