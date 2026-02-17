#!/usr/bin/env python3
"""
UC-PR-01 Phase 5: Time-Series Trend Analysis
=============================================
Analyzes monthly and weekly sales trends for all menu items.
Computes growth rates, momentum scores, market share trends,
and new product launch performance.

Inputs:
  - data/monthly_sales.csv   (spu_code, month, qty, revenue)
  - data/weekly_sales.csv    (spu_code, week, qty, revenue)
  - data/cost_model_output.csv (58 SKUs with BCG classification)

Outputs:
  - data/charts/09_share_trends.png
  - data/charts/10_growth_heatmap.png
  - data/charts/11_launch_curves.png
  - data/charts/12_momentum_scatter.png
  - data/trend_summary.csv
  - data/phase5_trend_report.md
"""

import os
import sys
import pandas as pd
import numpy as np
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import matplotlib.ticker as mticker
from datetime import datetime

# ── Paths ────────────────────────────────────────────────────────────────
BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA_DIR = os.path.join(BASE_DIR, 'data')
CHART_DIR = os.path.join(DATA_DIR, 'charts')
os.makedirs(CHART_DIR, exist_ok=True)

# ── Configuration ────────────────────────────────────────────────────────
# Exclude pre-launch months (Mar-Apr 2025 had <100 orders total)
ANALYSIS_START = '2025-06'   # First full operating month
PARTIAL_MONTH = '2026-02'    # Current partial month (through Feb 16)
TREND_MIN_MONTHS = 3         # Need at least 3 months for trend calculation
TODAY = '2026-02-16'

# ── Supplemental product names (SPUs not in cost_model_output.csv) ────
# Retrieved from t_order_item.spu_name in salesorder DB
EXTRA_NAMES = {
    'PR000001': 'IQA2Test Standard American',
    'PR000002': 'IQA2Test Coconut Latte',
    'PR000003': 'IQA2Test Cake',
    'PR000004': 'IQA2Test Drip Coffee',
    'PR000019': 'Hot Flat White',
    'PR000029': 'Matcha Coconut Latte (Hot)',
    'PR000035': 'Coconut Cold Brew',
    'PR000037': 'Matcha Latte (Hot)',
    'PR000038': 'Matcha Coconut Water',
    'PR000040': 'Zen Berry (Original)',
    'PR000049': 'Matcha Frappe',
    'PR000054': 'IQA2Test Roast Type',
    'PR000055': 'IQA2Test Extraction Type',
    'PR000056': 'IQA2Test Roast Extraction',
    'PR000060': 'IQA2Test Dafu',
    'PR000061': 'Chocolate Chip Brownie',
    'PR000062': 'Chocolate Chip Cookie (GF)',
    'PR000064': 'Banana Yogurt Loaf',
    'PR000065': 'Chewy Marshmallow Bar',
    'PR000066': 'Plain Bagel',
    'PR000101': 'Plain Auli Cake',
    'PR000107': 'IQA2Test Drip Coffee 2',
    'PR000112': 'Iced Tiramisu Latte',
    'PR000113': 'Tiramisu Latte (Hot)',
    'PR000114': 'Tiramisu Cold Brew',
}
# Category for extras (best guess from name)
EXTRA_CATEGORIES = {
    'PR000019': 'beverage_hot', 'PR000029': 'beverage_hot',
    'PR000035': 'beverage_iced', 'PR000037': 'beverage_hot',
    'PR000038': 'beverage_iced', 'PR000040': 'beverage_iced',
    'PR000049': 'beverage_iced',
    'PR000061': 'food', 'PR000062': 'food', 'PR000064': 'food',
    'PR000065': 'food', 'PR000066': 'food', 'PR000101': 'food',
    'PR000112': 'beverage_iced', 'PR000113': 'beverage_hot',
    'PR000114': 'beverage_iced',
}


# ══════════════════════════════════════════════════════════════════════════
# SECTION 1: DATA LOADING
# ══════════════════════════════════════════════════════════════════════════

def load_data():
    """Load all input CSVs."""
    monthly = pd.read_csv(os.path.join(DATA_DIR, 'monthly_sales.csv'))
    weekly = pd.read_csv(os.path.join(DATA_DIR, 'weekly_sales.csv'))
    cost_model = pd.read_csv(os.path.join(DATA_DIR, 'cost_model_output.csv'))

    # Clean up
    monthly['month'] = monthly['month'].astype(str)
    weekly['week'] = weekly['week'].astype(str)

    print(f"Monthly data: {len(monthly)} rows, {monthly['spu_code'].nunique()} SPUs")
    print(f"Weekly data:  {len(weekly)} rows, {weekly['spu_code'].nunique()} SPUs")
    print(f"Cost model:   {len(cost_model)} SKUs with classifications")

    return monthly, weekly, cost_model


def compute_lifecycle(monthly):
    """Derive product lifecycle from monthly sales data."""
    lifecycle = monthly.groupby('spu_code').agg(
        first_month=('month', 'min'),
        last_month=('month', 'max'),
        active_months=('month', 'count'),
        total_qty=('qty', 'sum'),
        total_revenue=('revenue', 'sum')
    ).reset_index()

    # Determine if product is still active (sold in last 2 months)
    recent_months = sorted(monthly['month'].unique())[-2:]
    active_spus = monthly[monthly['month'].isin(recent_months)]['spu_code'].unique()
    lifecycle['is_active'] = lifecycle['spu_code'].isin(active_spus)

    # Launch wave classification
    def classify_launch(first_month):
        if first_month <= '2025-04':
            return 'Pre-launch (Mar-Apr 2025)'
        elif first_month <= '2025-05':
            return 'Core Menu (May 2025)'
        elif first_month <= '2025-07':
            return 'Early Expansion (Jun-Jul 2025)'
        elif first_month <= '2025-09':
            return 'Matcha & Food Wave (Aug-Sep 2025)'
        elif first_month <= '2025-11':
            return 'Seasonal & Specialty (Oct-Nov 2025)'
        elif first_month <= '2026-01':
            return 'Pistachio Launch (Jan 2026)'
        else:
            return 'Newest (Feb 2026)'

    lifecycle['launch_wave'] = lifecycle['first_month'].apply(classify_launch)
    return lifecycle


# ══════════════════════════════════════════════════════════════════════════
# SECTION 2: MARKET SHARE & TREND COMPUTATION
# ══════════════════════════════════════════════════════════════════════════

def compute_monthly_totals(monthly):
    """Compute monthly totals for normalization."""
    totals = monthly.groupby('month').agg(
        total_qty=('qty', 'sum'),
        total_revenue=('revenue', 'sum')
    ).reset_index()
    return totals


def compute_market_share(monthly, totals):
    """Convert raw volumes to market share percentages."""
    merged = monthly.merge(totals, on='month', suffixes=('', '_total'))
    merged['qty_share'] = (merged['qty'] / merged['total_qty'] * 100).round(3)
    merged['rev_share'] = (merged['revenue'] / merged['total_revenue'] * 100).round(3)
    return merged


def compute_trends(share_df, cost_model):
    """Compute trend metrics for each SKU using OLS on market share %."""
    # Filter to analysis period (exclude pre-launch and partial month)
    analysis = share_df[
        (share_df['month'] >= ANALYSIS_START) &
        (share_df['month'] < PARTIAL_MONTH)
    ].copy()

    all_months = sorted(analysis['month'].unique())
    month_to_idx = {m: i for i, m in enumerate(all_months)}
    analysis['month_idx'] = analysis['month'].map(month_to_idx)

    results = []
    for spu in analysis['spu_code'].unique():
        spu_data = analysis[analysis['spu_code'] == spu].sort_values('month')

        if len(spu_data) < TREND_MIN_MONTHS:
            continue

        # OLS regression on qty_share
        x = spu_data['month_idx'].values.astype(float)
        y = spu_data['qty_share'].values.astype(float)

        if len(x) >= 2 and np.std(x) > 0:
            slope, intercept = np.polyfit(x, y, 1)
            y_pred = slope * x + intercept
            ss_res = np.sum((y - y_pred) ** 2)
            ss_tot = np.sum((y - np.mean(y)) ** 2)
            r_squared = 1 - ss_res / ss_tot if ss_tot > 0 else 0
        else:
            slope = 0
            r_squared = 0

        # Average share
        avg_share = np.mean(y)

        # Relative trend: slope as % of average share per month
        rel_trend = (slope / avg_share * 100) if avg_share > 0 else 0

        # Momentum: last 2 months vs prior 2 months (qty share)
        if len(spu_data) >= 4:
            recent = spu_data.tail(2)['qty_share'].mean()
            prior = spu_data.iloc[-4:-2]['qty_share'].mean()
            momentum = ((recent - prior) / prior * 100) if prior > 0 else 0
        elif len(spu_data) >= 3:
            recent = spu_data.tail(1)['qty_share'].mean()
            prior = spu_data.iloc[-3:-1]['qty_share'].mean()
            momentum = ((recent - prior) / prior * 100) if prior > 0 else 0
        else:
            momentum = 0

        # Volatility (coefficient of variation of qty_share)
        cv = (np.std(y) / np.mean(y) * 100) if np.mean(y) > 0 else 0

        # Peak month
        peak_month = spu_data.loc[spu_data['qty_share'].idxmax(), 'month']

        # Month-over-month changes
        mom_changes = spu_data['qty_share'].pct_change().dropna()
        avg_mom = mom_changes.mean() * 100 if len(mom_changes) > 0 else 0

        # Classify trend direction
        if rel_trend > 5:
            direction = 'Growing'
        elif rel_trend < -5:
            direction = 'Declining'
        else:
            direction = 'Stable'

        results.append({
            'spu_code': spu,
            'avg_qty_share': round(avg_share, 3),
            'slope_per_month': round(slope, 4),
            'rel_trend_pct': round(rel_trend, 1),
            'r_squared': round(r_squared, 3),
            'momentum_pct': round(momentum, 1),
            'volatility_cv': round(cv, 1),
            'peak_month': peak_month,
            'avg_mom_pct': round(avg_mom, 1),
            'months_analyzed': len(spu_data),
            'direction': direction,
        })

    trend_df = pd.DataFrame(results)

    # Merge with cost model for names and classifications
    if len(cost_model) > 0:
        trend_df = trend_df.merge(
            cost_model[['spu_code', 'product_name', 'category', 'classification', 'cm_pct', 'total_cm']],
            on='spu_code', how='left'
        )

    # Fill missing names from EXTRA_NAMES lookup
    mask = trend_df['product_name'].isna()
    trend_df.loc[mask, 'product_name'] = trend_df.loc[mask, 'spu_code'].map(EXTRA_NAMES)
    trend_df.loc[mask, 'category'] = trend_df.loc[mask, 'spu_code'].map(EXTRA_CATEGORIES)
    # Still-missing: fall back to spu_code
    trend_df['product_name'] = trend_df['product_name'].fillna(trend_df['spu_code'])
    # Mark extras without cost model data as 'Uncosted'
    trend_df['classification'] = trend_df['classification'].fillna('Uncosted')

    return trend_df


def compute_weekly_momentum(weekly, cost_model):
    """Compute 4-week rolling momentum from weekly data."""
    # Filter to recent period
    recent_weeks = sorted(weekly['week'].unique())
    if len(recent_weeks) < 8:
        return pd.DataFrame()

    # Get total per week for share calculation
    week_totals = weekly.groupby('week')['qty'].sum().reset_index()
    week_totals.columns = ['week', 'week_total']

    wk_merged = weekly.merge(week_totals, on='week')
    wk_merged['qty_share'] = wk_merged['qty'] / wk_merged['week_total'] * 100

    # Last 4 weeks vs prior 4 weeks
    last4 = recent_weeks[-4:]
    prior4 = recent_weeks[-8:-4]

    results = []
    for spu in wk_merged['spu_code'].unique():
        spu_data = wk_merged[wk_merged['spu_code'] == spu]
        recent = spu_data[spu_data['week'].isin(last4)]['qty_share'].mean()
        prior = spu_data[spu_data['week'].isin(prior4)]['qty_share'].mean()

        if prior > 0:
            wk_momentum = (recent - prior) / prior * 100
        else:
            wk_momentum = 100 if recent > 0 else 0

        results.append({
            'spu_code': spu,
            'recent_4wk_share': round(recent, 3) if not np.isnan(recent) else 0,
            'prior_4wk_share': round(prior, 3) if not np.isnan(prior) else 0,
            'weekly_momentum': round(wk_momentum, 1),
        })

    mom_df = pd.DataFrame(results)
    if len(cost_model) > 0:
        mom_df = mom_df.merge(
            cost_model[['spu_code', 'product_name', 'classification']],
            on='spu_code', how='left'
        )
    # Fill missing names from EXTRA_NAMES lookup
    mask = mom_df['product_name'].isna()
    mom_df.loc[mask, 'product_name'] = mom_df.loc[mask, 'spu_code'].map(EXTRA_NAMES)
    mom_df['product_name'] = mom_df['product_name'].fillna(mom_df['spu_code'])
    mom_df['classification'] = mom_df['classification'].fillna('Uncosted')
    return mom_df


# ══════════════════════════════════════════════════════════════════════════
# SECTION 3: VISUALIZATIONS
# ══════════════════════════════════════════════════════════════════════════

COLORS = {
    'Star': '#2ecc71',
    'Plow Horse': '#3498db',
    'Puzzle': '#e67e22',
    'Dog': '#e74c3c',
    'Uncosted': '#95a5a6',
}

def short_name(name, maxlen=20):
    """Truncate product name for chart labels."""
    if pd.isna(name):
        return 'Unknown'
    return name if len(str(name)) <= maxlen else str(name)[:maxlen-1] + '…'


def chart_09_share_trends(share_df, trend_df, cost_model):
    """Market share trends for top 12 SKUs by total volume."""
    fig, axes = plt.subplots(3, 4, figsize=(20, 12))
    fig.suptitle('Market Share Trends — Top 12 SKUs by Volume\n(Normalized for business growth)',
                 fontsize=14, fontweight='bold', y=0.98)

    # Filter to analysis period
    plot_data = share_df[share_df['month'] >= ANALYSIS_START].copy()

    # Top 12 by total qty in analysis period
    top12 = plot_data.groupby('spu_code')['qty'].sum().nlargest(12).index.tolist()

    name_map = cost_model.set_index('spu_code')['product_name'].to_dict()
    class_map = cost_model.set_index('spu_code')['classification'].to_dict()
    trend_map = trend_df.set_index('spu_code') if len(trend_df) > 0 else pd.DataFrame()

    for idx, spu in enumerate(top12):
        ax = axes[idx // 4, idx % 4]
        spu_data = plot_data[plot_data['spu_code'] == spu].sort_values('month')

        color = COLORS.get(class_map.get(spu, ''), '#999999')
        name = short_name(name_map.get(spu, spu), 22)
        cls = class_map.get(spu, '?')

        # Plot market share
        months = spu_data['month'].str[5:7].astype(int)  # Just month number for x-axis
        month_labels = spu_data['month'].str[2:]  # YY-MM

        ax.plot(range(len(spu_data)), spu_data['qty_share'],
                color=color, linewidth=2, marker='o', markersize=4)
        ax.fill_between(range(len(spu_data)), spu_data['qty_share'],
                       alpha=0.15, color=color)

        # Add trend line if available
        if spu in trend_map.index:
            trend_info = trend_map.loc[spu]
            slope = trend_info['slope_per_month']
            direction = trend_info['direction']
            arrow = '↑' if direction == 'Growing' else ('↓' if direction == 'Declining' else '→')

            # OLS trend line
            x_range = np.arange(len(spu_data))
            trend_line = slope * x_range + (spu_data['qty_share'].iloc[0] - slope * 0)
            ax.plot(range(len(spu_data)), trend_line, '--', color='gray', alpha=0.6, linewidth=1)

            ax.set_title(f'{name}\n[{cls}] {arrow} {trend_info["rel_trend_pct"]:+.1f}%/mo',
                        fontsize=9, fontweight='bold')
        else:
            ax.set_title(f'{name}\n[{cls}]', fontsize=9, fontweight='bold')

        ax.set_xticks(range(len(spu_data)))
        ax.set_xticklabels(month_labels, rotation=45, fontsize=7)
        ax.set_ylabel('Share %', fontsize=8)
        ax.yaxis.set_major_formatter(mticker.FormatStrFormatter('%.1f'))
        ax.grid(True, alpha=0.3)

    plt.tight_layout(rect=[0, 0, 1, 0.95])
    path = os.path.join(CHART_DIR, '09_share_trends.png')
    plt.savefig(path, dpi=150, bbox_inches='tight')
    plt.close()
    print(f"  Chart 09 saved: {path}")
    return path


def chart_10_growth_heatmap(share_df, cost_model):
    """Month-over-month growth rate heatmap for top 25 SKUs."""
    fig, ax = plt.subplots(figsize=(16, 12))

    # Filter to analysis period (excluding partial month)
    plot_data = share_df[
        (share_df['month'] >= ANALYSIS_START) &
        (share_df['month'] < PARTIAL_MONTH)
    ].copy()

    months = sorted(plot_data['month'].unique())

    # Top 25 by total qty
    top25 = plot_data.groupby('spu_code')['qty'].sum().nlargest(25).index.tolist()

    name_map = cost_model.set_index('spu_code')['product_name'].to_dict()
    class_map = cost_model.set_index('spu_code')['classification'].to_dict()

    # Build MoM growth matrix
    growth_matrix = []
    labels = []

    for spu in top25:
        spu_data = plot_data[plot_data['spu_code'] == spu].sort_values('month')
        spu_pivot = spu_data.set_index('month')['qty_share']

        row = []
        for i, m in enumerate(months):
            if i == 0:
                row.append(np.nan)  # No prior month for first
            else:
                curr = spu_pivot.get(m, 0)
                prev = spu_pivot.get(months[i-1], 0)
                if prev > 0:
                    row.append((curr - prev) / prev * 100)
                elif curr > 0:
                    row.append(100)  # New launch
                else:
                    row.append(0)

        growth_matrix.append(row)
        cls = class_map.get(spu, '?')
        name = short_name(name_map.get(spu, spu), 25)
        labels.append(f'{name} [{cls}]')

    matrix = np.array(growth_matrix)

    # Clip extreme values for better visualization
    vmax = 80
    matrix_clipped = np.clip(matrix, -vmax, vmax)

    im = ax.imshow(matrix_clipped, cmap='RdYlGn', aspect='auto', vmin=-vmax, vmax=vmax)

    # Labels
    month_labels = [m[2:] for m in months]  # YY-MM
    ax.set_xticks(range(len(months)))
    ax.set_xticklabels(month_labels, rotation=45, fontsize=9)
    ax.set_yticks(range(len(labels)))
    ax.set_yticklabels(labels, fontsize=8)

    # Add text annotations
    for i in range(len(labels)):
        for j in range(len(months)):
            val = matrix[i, j]
            if np.isnan(val):
                text = '—'
                color = 'gray'
            else:
                text = f'{val:+.0f}%' if abs(val) < 1000 else 'NEW'
                color = 'white' if abs(val) > 40 else 'black'
            ax.text(j, i, text, ha='center', va='center', fontsize=6.5, color=color)

    ax.set_title('Month-over-Month Share Growth (%) — Top 25 SKUs\nGreen = gaining share, Red = losing share',
                fontsize=13, fontweight='bold', pad=15)
    ax.set_xlabel('Month', fontsize=11)

    cbar = plt.colorbar(im, ax=ax, shrink=0.8, pad=0.02)
    cbar.set_label('MoM Share Change (%)', fontsize=10)

    plt.tight_layout()
    path = os.path.join(CHART_DIR, '10_growth_heatmap.png')
    plt.savefig(path, dpi=150, bbox_inches='tight')
    plt.close()
    print(f"  Chart 10 saved: {path}")
    return path


def chart_11_launch_curves(monthly, cost_model, lifecycle):
    """New product launch trajectories — months since launch."""
    fig, axes = plt.subplots(1, 2, figsize=(18, 8))

    # Get products launched after core menu (after May 2025)
    launched_after = lifecycle[
        (lifecycle['first_month'] > '2025-05') &
        (lifecycle['is_active']) &
        (lifecycle['total_qty'] > 500)  # Minimum volume threshold
    ].copy()

    name_map = cost_model.set_index('spu_code')['product_name'].to_dict()
    class_map = cost_model.set_index('spu_code')['classification'].to_dict()

    # Panel 1: Raw volume by months since launch
    ax1 = axes[0]
    all_months_sorted = sorted(monthly['month'].unique())
    month_to_num = {m: i for i, m in enumerate(all_months_sorted)}

    for _, row in launched_after.iterrows():
        spu = row['spu_code']
        first_m = row['first_month']

        spu_data = monthly[
            (monthly['spu_code'] == spu) &
            (monthly['month'] >= first_m)
        ].sort_values('month')

        if len(spu_data) < 2:
            continue

        first_idx = month_to_num.get(first_m, 0)
        x = [month_to_num.get(m, 0) - first_idx for m in spu_data['month']]

        name = short_name(name_map.get(spu, spu), 18)
        color = COLORS.get(class_map.get(spu, ''), '#999999')

        ax1.plot(x, spu_data['qty'], marker='o', markersize=3,
                linewidth=1.5, label=name, color=color, alpha=0.8)

    ax1.set_xlabel('Months Since Launch', fontsize=11)
    ax1.set_ylabel('Monthly Units Sold', fontsize=11)
    ax1.set_title('New Product Launch Trajectories\n(Raw Volume by Month Since Launch)',
                  fontsize=12, fontweight='bold')
    ax1.legend(fontsize=7, ncol=2, loc='upper left')
    ax1.grid(True, alpha=0.3)

    # Panel 2: Launch wave comparison (average trajectory per wave)
    ax2 = axes[1]

    wave_colors = {
        'Matcha & Food Wave (Aug-Sep 2025)': '#27ae60',
        'Seasonal & Specialty (Oct-Nov 2025)': '#e67e22',
        'Pistachio Launch (Jan 2026)': '#8e44ad',
    }

    for wave, wcolor in wave_colors.items():
        wave_spus = launched_after[launched_after['launch_wave'] == wave]['spu_code'].tolist()
        if not wave_spus:
            continue

        # Collect normalized trajectories (months since launch)
        trajectories = {}
        for spu in wave_spus:
            first_m = lifecycle[lifecycle['spu_code'] == spu]['first_month'].iloc[0]
            spu_data = monthly[
                (monthly['spu_code'] == spu) &
                (monthly['month'] >= first_m)
            ].sort_values('month')

            first_idx = month_to_num.get(first_m, 0)
            for _, r in spu_data.iterrows():
                m_idx = month_to_num.get(r['month'], 0) - first_idx
                if m_idx not in trajectories:
                    trajectories[m_idx] = []
                trajectories[m_idx].append(r['qty'])

        # Average trajectory
        if trajectories:
            x_vals = sorted(trajectories.keys())
            y_vals = [np.mean(trajectories[x]) for x in x_vals]
            short_wave = wave.split('(')[0].strip()
            ax2.plot(x_vals, y_vals, marker='s', markersize=5,
                    linewidth=2.5, label=f'{short_wave} (n={len(wave_spus)})',
                    color=wcolor)

    ax2.set_xlabel('Months Since Launch', fontsize=11)
    ax2.set_ylabel('Avg Monthly Units per SKU', fontsize=11)
    ax2.set_title('Average Launch Trajectories by Wave\n(How fast do new products ramp?)',
                  fontsize=12, fontweight='bold')
    ax2.legend(fontsize=9)
    ax2.grid(True, alpha=0.3)

    plt.tight_layout()
    path = os.path.join(CHART_DIR, '11_launch_curves.png')
    plt.savefig(path, dpi=150, bbox_inches='tight')
    plt.close()
    print(f"  Chart 11 saved: {path}")
    return path


def chart_12_momentum_scatter(trend_df, weekly_mom):
    """Momentum vs current share scatter — strategic action map."""
    fig, ax = plt.subplots(figsize=(14, 10))

    # Merge trend and weekly momentum
    if len(weekly_mom) == 0:
        print("  Skipping chart 12: insufficient weekly data")
        return None

    plot_df = trend_df.merge(
        weekly_mom[['spu_code', 'weekly_momentum', 'recent_4wk_share']],
        on='spu_code', how='inner'
    )

    if len(plot_df) == 0:
        print("  Skipping chart 12: no merged data")
        return None

    # Plot each classification
    for cls, color in COLORS.items():
        mask = plot_df['classification'] == cls
        subset = plot_df[mask]
        if len(subset) == 0:
            continue

        sizes = np.abs(subset['total_cm'].fillna(100)).clip(lower=100) / 30
        ax.scatter(subset['recent_4wk_share'], subset['weekly_momentum'],
                  s=sizes,
                  c=color, alpha=0.65, edgecolors='white', linewidth=0.5,
                  label=f'{cls} ({len(subset)})', zorder=3)

        # Label notable points
        for _, row in subset.iterrows():
            if (abs(row['weekly_momentum']) > 15 or
                row['recent_4wk_share'] > 3 or
                (row['classification'] == 'Dog' and row['weekly_momentum'] < -20)):
                name = short_name(row.get('product_name', row['spu_code']), 16)
                ax.annotate(name, (row['recent_4wk_share'], row['weekly_momentum']),
                           fontsize=7, alpha=0.8,
                           xytext=(5, 5), textcoords='offset points')

    # Quadrant lines
    ax.axhline(y=0, color='gray', linewidth=1, linestyle='-', alpha=0.5)
    ax.axvline(x=1.21, color='gray', linewidth=1, linestyle='--', alpha=0.5)

    # Quadrant labels
    ax.text(0.02, 0.98, 'DECLINING\nLow Share', transform=ax.transAxes,
           fontsize=9, color='#e74c3c', alpha=0.6, va='top', fontweight='bold')
    ax.text(0.98, 0.98, 'DECLINING\nHigh Share ⚠️', transform=ax.transAxes,
           fontsize=9, color='#e67e22', alpha=0.6, va='top', ha='right', fontweight='bold')
    ax.text(0.02, 0.02, 'GROWING\nLow Share 🌱', transform=ax.transAxes,
           fontsize=9, color='#2ecc71', alpha=0.6, fontweight='bold')
    ax.text(0.98, 0.02, 'GROWING\nHigh Share ✨', transform=ax.transAxes,
           fontsize=9, color='#27ae60', alpha=0.6, ha='right', fontweight='bold')

    ax.set_xlabel('Recent 4-Week Market Share (%)', fontsize=11)
    ax.set_ylabel('4-Week Momentum (% change vs prior 4 weeks)', fontsize=11)
    ax.set_title('Strategic Momentum Map\nBubble size = Total CM$ | Dashed line = popularity threshold (1.21%)',
                fontsize=13, fontweight='bold')
    ax.legend(fontsize=10, loc='upper left')
    ax.grid(True, alpha=0.3)

    plt.tight_layout()
    path = os.path.join(CHART_DIR, '12_momentum_scatter.png')
    plt.savefig(path, dpi=150, bbox_inches='tight')
    plt.close()
    print(f"  Chart 12 saved: {path}")
    return path


# ══════════════════════════════════════════════════════════════════════════
# SECTION 4: REPORT GENERATION
# ══════════════════════════════════════════════════════════════════════════

def save_trend_csv(trend_df):
    """Save trend summary to CSV."""
    path = os.path.join(DATA_DIR, 'trend_summary.csv')
    cols = ['spu_code', 'product_name', 'category', 'classification',
            'avg_qty_share', 'slope_per_month', 'rel_trend_pct', 'r_squared',
            'momentum_pct', 'volatility_cv', 'peak_month', 'direction', 'months_analyzed',
            'cm_pct', 'total_cm']
    out_cols = [c for c in cols if c in trend_df.columns]
    trend_df.sort_values('avg_qty_share', ascending=False).to_csv(path, columns=out_cols, index=False)
    print(f"  Trend summary saved: {path}")
    return path


def generate_report(trend_df, lifecycle, monthly_totals, weekly_mom):
    """Generate Phase 5 markdown report."""

    # Key stats
    total_months = len(monthly_totals[monthly_totals['month'] >= ANALYSIS_START])
    total_spus_analyzed = len(trend_df)
    growing = trend_df[trend_df['direction'] == 'Growing']
    declining = trend_df[trend_df['direction'] == 'Declining']
    stable = trend_df[trend_df['direction'] == 'Stable']

    # Active vs discontinued
    active = lifecycle[lifecycle['is_active']]
    discontinued = lifecycle[~lifecycle['is_active']]

    # Monthly totals for growth stats
    analysis_totals = monthly_totals[
        (monthly_totals['month'] >= ANALYSIS_START) &
        (monthly_totals['month'] < PARTIAL_MONTH)
    ].sort_values('month')

    if len(analysis_totals) >= 2:
        first_month_qty = analysis_totals.iloc[0]['total_qty']
        last_month_qty = analysis_totals.iloc[-1]['total_qty']
        first_month_rev = analysis_totals.iloc[0]['total_revenue']
        last_month_rev = analysis_totals.iloc[-1]['total_revenue']
        n_months = len(analysis_totals) - 1
        qty_cagr = ((last_month_qty / first_month_qty) ** (1/n_months) - 1) * 100 if first_month_qty > 0 else 0
        rev_cagr = ((last_month_rev / first_month_rev) ** (1/n_months) - 1) * 100 if first_month_rev > 0 else 0
    else:
        qty_cagr = rev_cagr = 0

    # Top growing / declining
    top_growing = growing.nlargest(10, 'rel_trend_pct') if len(growing) > 0 else pd.DataFrame()
    top_declining = declining.nsmallest(10, 'rel_trend_pct') if len(declining) > 0 else pd.DataFrame()

    # Most volatile
    most_volatile = trend_df.nlargest(10, 'volatility_cv')

    # Momentum leaders
    if len(weekly_mom) > 0:
        mom_leaders = weekly_mom[weekly_mom['recent_4wk_share'] > 0.3].nlargest(10, 'weekly_momentum')
        mom_laggards = weekly_mom[weekly_mom['recent_4wk_share'] > 0.3].nsmallest(10, 'weekly_momentum')
    else:
        mom_leaders = mom_laggards = pd.DataFrame()

    lines = []
    lines.append("# UC-PR-01: Phase 5 — Time-Series Trend Analysis")
    lines.append("")
    lines.append(f"**Date**: {TODAY}")
    lines.append("**Status**: COMPLETE")
    lines.append("")
    lines.append("---")
    lines.append("")

    # Section 1: Business Overview
    lines.append("## 1. Business Growth Overview")
    lines.append("")
    lines.append("| Metric | Value |")
    lines.append("|--------|-------|")
    lines.append(f"| Analysis period | {ANALYSIS_START} to 2026-01 ({total_months} months) |")
    lines.append(f"| SPUs analyzed (≥3 months data) | {total_spus_analyzed} |")
    lines.append(f"| Active SPUs (sold in last 2 months) | {len(active)} |")
    lines.append(f"| Discontinued SPUs | {len(discontinued)} |")

    if len(analysis_totals) >= 2:
        lines.append(f"| First full month orders ({ANALYSIS_START}) | {int(analysis_totals.iloc[0]['total_qty']):,} |")
        lines.append(f"| Latest full month orders (2026-01) | {int(analysis_totals.iloc[-1]['total_qty']):,} |")
        lines.append(f"| Monthly order CAGR | **{qty_cagr:+.1f}%** |")
        lines.append(f"| Monthly revenue CAGR | **{rev_cagr:+.1f}%** |")
    lines.append("")

    # Section 2: Trend Direction Summary
    lines.append("## 2. Trend Direction Summary")
    lines.append("")
    lines.append("| Direction | Count | % of Analyzed | Description |")
    lines.append("|-----------|-------|--------------|-------------|")
    lines.append(f"| **Growing** (↑) | {len(growing)} | {len(growing)/total_spus_analyzed*100:.0f}% | Share trend > +5%/month |")
    lines.append(f"| **Stable** (→) | {len(stable)} | {len(stable)/total_spus_analyzed*100:.0f}% | Share trend between -5% and +5%/month |")
    lines.append(f"| **Declining** (↓) | {len(declining)} | {len(declining)/total_spus_analyzed*100:.0f}% | Share trend < -5%/month |")
    lines.append("")

    # Cross-tab: direction × classification
    lines.append("### Trend × BCG Classification")
    lines.append("")
    lines.append("| Direction | Star | Plow Horse | Puzzle | Dog | Total |")
    lines.append("|-----------|------|------------|--------|-----|-------|")
    for direction in ['Growing', 'Stable', 'Declining']:
        row = trend_df[trend_df['direction'] == direction]
        counts = row['classification'].value_counts()
        s = counts.get('Star', 0)
        p = counts.get('Plow Horse', 0)
        z = counts.get('Puzzle', 0)
        d = counts.get('Dog', 0)
        lines.append(f"| {direction} | {s} | {p} | {z} | {d} | {len(row)} |")
    lines.append("")

    # Section 3: Top Growing SKUs
    lines.append("## 3. Fastest Growing SKUs (by Market Share Trend)")
    lines.append("")
    if len(top_growing) > 0:
        lines.append("| Rank | Product | Class | Avg Share% | Trend %/mo | R² | Momentum | Peak |")
        lines.append("|------|---------|-------|-----------|-----------|-----|----------|------|")
        for i, (_, row) in enumerate(top_growing.iterrows(), 1):
            name = short_name(row.get('product_name', row['spu_code']), 25)
            cls = row.get('classification', '?')
            lines.append(f"| {i} | {name} | {cls} | {row['avg_qty_share']:.2f} | "
                        f"**{row['rel_trend_pct']:+.1f}%** | {row['r_squared']:.2f} | "
                        f"{row['momentum_pct']:+.0f}% | {row['peak_month']} |")
    lines.append("")

    # Section 4: Fastest Declining SKUs
    lines.append("## 4. Fastest Declining SKUs (by Market Share Trend)")
    lines.append("")
    if len(top_declining) > 0:
        lines.append("| Rank | Product | Class | Avg Share% | Trend %/mo | R² | Momentum | Peak |")
        lines.append("|------|---------|-------|-----------|-----------|-----|----------|------|")
        for i, (_, row) in enumerate(top_declining.iterrows(), 1):
            name = short_name(row.get('product_name', row['spu_code']), 25)
            cls = row.get('classification', '?')
            lines.append(f"| {i} | {name} | {cls} | {row['avg_qty_share']:.2f} | "
                        f"**{row['rel_trend_pct']:+.1f}%** | {row['r_squared']:.2f} | "
                        f"{row['momentum_pct']:+.0f}% | {row['peak_month']} |")
    lines.append("")

    # Section 5: Weekly Momentum
    lines.append("## 5. Weekly Momentum (Last 4 Weeks vs Prior 4 Weeks)")
    lines.append("")
    if len(mom_leaders) > 0:
        lines.append("### 5.1 Momentum Leaders (Gaining)")
        lines.append("")
        lines.append("| Product | Class | Recent 4wk Share | Prior 4wk Share | Momentum |")
        lines.append("|---------|-------|-----------------|----------------|----------|")
        for _, row in mom_leaders.iterrows():
            name = short_name(row.get('product_name', row['spu_code']), 25)
            cls = row.get('classification', '?')
            lines.append(f"| {name} | {cls} | {row['recent_4wk_share']:.2f}% | "
                        f"{row['prior_4wk_share']:.2f}% | **{row['weekly_momentum']:+.1f}%** |")
        lines.append("")

    if len(mom_laggards) > 0:
        lines.append("### 5.2 Momentum Laggards (Losing)")
        lines.append("")
        lines.append("| Product | Class | Recent 4wk Share | Prior 4wk Share | Momentum |")
        lines.append("|---------|-------|-----------------|----------------|----------|")
        for _, row in mom_laggards.iterrows():
            name = short_name(row.get('product_name', row['spu_code']), 25)
            cls = row.get('classification', '?')
            lines.append(f"| {name} | {cls} | {row['recent_4wk_share']:.2f}% | "
                        f"{row['prior_4wk_share']:.2f}% | **{row['weekly_momentum']:+.1f}%** |")
        lines.append("")

    # Section 6: Volatility
    lines.append("## 6. Most Volatile SKUs (Highest CV of Market Share)")
    lines.append("")
    lines.append("| Product | Class | Avg Share% | CV% | Direction | Interpretation |")
    lines.append("|---------|-------|-----------|-----|-----------|----------------|")
    for _, row in most_volatile.iterrows():
        name = short_name(row.get('product_name', row['spu_code']), 25)
        cls = row.get('classification', '?')
        interp = 'Seasonal/promotional' if row['volatility_cv'] > 50 else 'Variable demand'
        lines.append(f"| {name} | {cls} | {row['avg_qty_share']:.2f} | "
                    f"{row['volatility_cv']:.0f}% | {row['direction']} | {interp} |")
    lines.append("")

    # Section 7: Product Lifecycle
    lines.append("## 7. Product Launch Waves")
    lines.append("")
    wave_summary = lifecycle.groupby('launch_wave').agg(
        count=('spu_code', 'count'),
        active=('is_active', 'sum'),
        avg_qty=('total_qty', 'mean')
    ).reset_index()

    lines.append("| Launch Wave | SPUs | Still Active | Avg Total Qty |")
    lines.append("|------------|------|-------------|---------------|")
    for _, row in wave_summary.iterrows():
        lines.append(f"| {row['launch_wave']} | {row['count']} | {int(row['active'])} | {row['avg_qty']:,.0f} |")
    lines.append("")

    # Section 8: Discontinued products
    if len(discontinued) > 0:
        lines.append("## 8. Discontinued Products")
        lines.append("")
        lines.append("| SPU | First Month | Last Month | Total Qty | Total Revenue |")
        lines.append("|-----|------------|------------|-----------|---------------|")
        for _, row in discontinued.sort_values('last_month', ascending=False).iterrows():
            lines.append(f"| {row['spu_code']} | {row['first_month']} | {row['last_month']} | "
                        f"{row['total_qty']:,} | ${row['total_revenue']:,.0f} |")
        lines.append("")

    # Section 9: Strategic Insights
    lines.append("## 9. Key Strategic Insights")
    lines.append("")

    # Find Stars that are declining
    declining_stars = trend_df[(trend_df['direction'] == 'Declining') & (trend_df['classification'] == 'Star')]
    growing_dogs = trend_df[(trend_df['direction'] == 'Growing') & (trend_df['classification'] == 'Dog')]
    growing_puzzles = trend_df[(trend_df['direction'] == 'Growing') & (trend_df['classification'] == 'Puzzle')]

    lines.append("### 9.1 Watch List — Declining Stars")
    if len(declining_stars) > 0:
        for _, row in declining_stars.iterrows():
            name = row.get('product_name', row['spu_code'])
            lines.append(f"- **{name}**: share declining at {row['rel_trend_pct']:+.1f}%/month — investigate root cause")
    else:
        lines.append("- No Stars currently declining — portfolio health is good")
    lines.append("")

    lines.append("### 9.2 Promotion Candidates — Growing Puzzles")
    if len(growing_puzzles) > 0:
        for _, row in growing_puzzles.iterrows():
            name = row.get('product_name', row['spu_code'])
            lines.append(f"- **{name}**: high margin, gaining share ({row['rel_trend_pct']:+.1f}%/mo) — promote to Star status")
    else:
        lines.append("- No Puzzles currently showing growth momentum")
    lines.append("")

    lines.append("### 9.3 Emerging Products — Growing Dogs")
    if len(growing_dogs) > 0:
        for _, row in growing_dogs.iterrows():
            name = row.get('product_name', row['spu_code'])
            lines.append(f"- **{name}**: gaining share ({row['rel_trend_pct']:+.1f}%/mo) — may be too new; monitor before action")
    else:
        lines.append("- No Dogs currently showing growth momentum")
    lines.append("")

    lines.append("### 9.4 Business Growth Context")
    lines.append(f"- Business grew **{qty_cagr:+.1f}% CMGR** in order volume over the analysis period")
    lines.append(f"- Revenue grew **{rev_cagr:+.1f}% CMGR** — faster than volume suggests improving basket value")
    lines.append("- Market share trends normalize for this growth: a product with 'stable' share is actually growing in absolute terms")
    lines.append("- Declining share does NOT mean declining sales — it means the product is growing slower than the business overall")
    lines.append("")

    # Section 10: Visualizations
    lines.append("## 10. Visualization Outputs")
    lines.append("")
    lines.append("| File | Description |")
    lines.append("|------|-------------|")
    lines.append("| `charts/09_share_trends.png` | Market share trends for top 12 SKUs |")
    lines.append("| `charts/10_growth_heatmap.png` | MoM share growth heatmap for top 25 SKUs |")
    lines.append("| `charts/11_launch_curves.png` | New product launch trajectories by wave |")
    lines.append("| `charts/12_momentum_scatter.png` | Strategic momentum map (share vs momentum) |")
    lines.append("| `trend_summary.csv` | Full trend metrics for all analyzed SKUs |")
    lines.append("")
    lines.append("---")
    lines.append("")
    lines.append("*Generated by Claude Code — UC-PR-01 Menu Engineering Matrix*")

    report_path = os.path.join(DATA_DIR, 'phase5_trend_report.md')
    with open(report_path, 'w') as f:
        f.write('\n'.join(lines))
    print(f"  Report saved: {report_path}")
    return report_path


# ══════════════════════════════════════════════════════════════════════════
# SECTION 5: MAIN
# ══════════════════════════════════════════════════════════════════════════

def main():
    print("=" * 60)
    print("UC-PR-01 Phase 5: Time-Series Trend Analysis")
    print("=" * 60)

    # 1. Load data
    print("\n[1/7] Loading data...")
    monthly, weekly, cost_model = load_data()

    # 2. Compute lifecycle
    print("\n[2/7] Computing product lifecycle...")
    lifecycle = compute_lifecycle(monthly)
    print(f"  {len(lifecycle)} SPUs total, {lifecycle['is_active'].sum()} active")
    print(f"  Launch waves: {lifecycle['launch_wave'].value_counts().to_dict()}")

    # 3. Compute monthly totals and market share
    print("\n[3/7] Computing market share trends...")
    monthly_totals = compute_monthly_totals(monthly)
    share_df = compute_market_share(monthly, monthly_totals)
    print(f"  Monthly totals: {len(monthly_totals)} months")

    # 4. Compute trends
    print("\n[4/7] Computing trend metrics...")
    trend_df = compute_trends(share_df, cost_model)
    print(f"  {len(trend_df)} SKUs analyzed (≥{TREND_MIN_MONTHS} months data)")
    if len(trend_df) > 0:
        dir_counts = trend_df['direction'].value_counts()
        print(f"  Directions: {dir_counts.to_dict()}")

    # 5. Compute weekly momentum
    print("\n[5/7] Computing weekly momentum...")
    weekly_mom = compute_weekly_momentum(weekly, cost_model)
    print(f"  {len(weekly_mom)} SKUs with weekly momentum data")

    # 6. Generate charts
    print("\n[6/7] Generating charts...")
    chart_09_share_trends(share_df, trend_df, cost_model)
    chart_10_growth_heatmap(share_df, cost_model)
    chart_11_launch_curves(monthly, cost_model, lifecycle)
    chart_12_momentum_scatter(trend_df, weekly_mom)

    # 7. Save outputs and report
    print("\n[7/7] Saving outputs...")
    save_trend_csv(trend_df)
    generate_report(trend_df, lifecycle, monthly_totals, weekly_mom)

    print("\n" + "=" * 60)
    print("Phase 5 COMPLETE")
    print("=" * 60)


if __name__ == '__main__':
    main()
