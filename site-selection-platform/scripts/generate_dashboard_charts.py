#!/usr/bin/env python3
"""
Luckin Coffee USA - Dashboard Chart Generator
Generates visualization-ready data and optional matplotlib charts
for the site selection scoring model.
"""

import csv
import json
import os

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
DATA_DIR = os.path.join(SCRIPT_DIR, '..', 'data')
DASHBOARD_DIR = os.path.join(SCRIPT_DIR, '..', 'dashboard')


def load_active_stores():
    """Load active store performance data."""
    stores = []
    with open(os.path.join(DATA_DIR, 'active_stores_performance.csv')) as f:
        reader = csv.DictReader(f)
        for row in reader:
            row['avg_daily_cups'] = int(row['avg_daily_cups'])
            row['subway_count'] = int(row['subway_count'])
            row['weekday_pct'] = float(row['weekday_pct'])
            row['latitude'] = float(row['latitude'])
            row['longitude'] = float(row['longitude'])
            stores.append(row)
    return stores


def load_pipeline_locations():
    """Load scored pipeline locations."""
    locations = []
    with open(os.path.join(DATA_DIR, 'pipeline_locations_scored.csv')) as f:
        reader = csv.DictReader(f)
        for row in reader:
            row['rank'] = int(row['rank'])
            row['score_total'] = int(row['score_total'])
            row['projected_daily_cups'] = int(row['projected_daily_cups'])
            row['rent_estimate_monthly'] = int(row['rent_estimate_monthly'])
            row['monthly_profit_estimate'] = int(row['monthly_profit_estimate'])
            locations.append(row)
    return locations


def generate_chart_1_area_type_performance(stores):
    """Chart 1: Area Type vs Average Daily Cups (Bar Chart)"""
    area_data = {}
    for s in stores:
        at = s['area_type']
        if at not in area_data:
            area_data[at] = []
        area_data[at].append(s['avg_daily_cups'])

    chart_data = []
    for at, cups_list in sorted(area_data.items(), key=lambda x: -sum(x[1])/len(x[1])):
        avg = sum(cups_list) / len(cups_list)
        chart_data.append({
            'area_type': at.replace('_', ' ').title(),
            'avg_cups': round(avg),
            'store_count': len(cups_list),
            'stores': [s['store_name'] for s in stores if s['area_type'] == at]
        })

    print("\n=== Chart 1: Area Type vs Daily Cups ===")
    print(f"{'Area Type':<30} {'Avg Cups':>10} {'Stores':>8}")
    print("-" * 50)
    for d in chart_data:
        bar = '#' * (d['avg_cups'] // 10)
        print(f"{d['area_type']:<30} {d['avg_cups']:>10} {d['store_count']:>8}  {bar}")

    return chart_data


def generate_chart_2_score_vs_cups(locations):
    """Chart 2: Model Score vs Projected Cups (Scatter Plot)"""
    chart_data = []
    for loc in locations[:12]:  # Top 12
        chart_data.append({
            'name': loc['store_name'],
            'score': loc['score_total'],
            'projected_cups': loc['projected_daily_cups'],
            'recommendation': loc['recommendation']
        })

    print("\n=== Chart 2: Score vs Projected Cups ===")
    print(f"{'Location':<25} {'Score':>6} {'Cups':>8} {'Recommendation':<25}")
    print("-" * 70)
    for d in chart_data:
        bar = '#' * (d['score'] // 2)
        print(f"{d['name']:<25} {d['score']:>6} {d['projected_cups']:>8} {d['recommendation']:<25} {bar}")

    return chart_data


def generate_chart_3_rent_efficiency(locations):
    """Chart 3: Rent vs Profit (Bubble Chart)"""
    chart_data = []
    for loc in locations:
        if loc['within_budget'] == 'Yes':
            chart_data.append({
                'name': loc['store_name'],
                'rent': loc['rent_estimate_monthly'],
                'profit': loc['monthly_profit_estimate'],
                'cups': loc['projected_daily_cups'],
                'profitable': loc['monthly_profit_estimate'] > 0
            })

    print("\n=== Chart 3: Rent vs Monthly Profit ===")
    print(f"{'Location':<25} {'Rent':>10} {'Profit':>12} {'Status':<15}")
    print("-" * 65)
    for d in sorted(chart_data, key=lambda x: -x['profit']):
        status = "PROFITABLE" if d['profitable'] else "LOSS"
        print(f"{d['name']:<25} ${d['rent']:>8,} ${d['profit']:>10,} {status:<15}")

    return chart_data


def generate_chart_4_scoring_breakdown(locations):
    """Chart 4: Score Breakdown by Factor (Stacked Bar)"""
    chart_data = []
    for loc in locations[:10]:
        chart_data.append({
            'name': loc['store_name'],
            'area_type': int(loc['score_area_type']),
            'subway': int(loc['score_subway_access']),
            'weekend': int(loc['score_weekend_resilience']),
            'cannibalization': int(loc['score_cannibalization']),
            'rent_value': int(loc['score_rent_value']),
            'total': loc['score_total']
        })

    print("\n=== Chart 4: Score Breakdown (Top 10) ===")
    print(f"{'Location':<25} {'Area':>5} {'Sub':>5} {'Wknd':>5} {'Cann':>5} {'Rent':>5} {'TOTAL':>7}")
    print("-" * 63)
    for d in chart_data:
        print(f"{d['name']:<25} {d['area_type']:>5} {d['subway']:>5} {d['weekend']:>5} {d['cannibalization']:>5} {d['rent_value']:>5} {d['total']:>7}")

    return chart_data


def generate_chart_5_breakeven_analysis():
    """Chart 5: Breakeven Analysis at Different Rent Levels"""
    margin = 2.30
    rent_levels = [10000, 12000, 14000, 15000, 16000, 18000, 20000, 22000, 25000]

    chart_data = []
    print("\n=== Chart 5: Breakeven Analysis ===")
    print(f"{'Rent/Month':>12} {'Breakeven Cups/Day':>20} {'Annual Rent':>15}")
    print("-" * 50)
    for rent in rent_levels:
        be_cups = round(rent / (margin * 30))
        budget_marker = " <-- BUDGET" if rent == 20000 else ""
        chart_data.append({
            'rent': rent,
            'breakeven_cups': be_cups,
            'annual_rent': rent * 12
        })
        print(f"${rent:>10,} {be_cups:>18} cups ${rent*12:>12,}{budget_marker}")

    return chart_data


def generate_chart_6_map_data(stores, locations):
    """Chart 6: Map coordinates for all stores (active + pipeline)"""
    map_points = []

    for s in stores:
        map_points.append({
            'name': s['store_name'],
            'lat': s['latitude'],
            'lon': s['longitude'],
            'type': 'active',
            'cups': s['avg_daily_cups'],
            'size': max(5, s['avg_daily_cups'] // 50),
            'color': '#22c55e' if s['avg_daily_cups'] >= 400 else '#f59e0b' if s['avg_daily_cups'] >= 250 else '#ef4444'
        })

    for loc in locations:
        color_map = {
            'Strongly Recommended': '#22c55e',
            'Recommended': '#3b82f6',
            'Recommended with Caution': '#f59e0b',
            'Moderate': '#a855f7',
            'Marginal': '#6b7280',
            'Not Recommended': '#ef4444',
            'Not Recommended (Over Budget)': '#ef4444'
        }
        map_points.append({
            'name': loc['store_name'],
            'lat': float(loc['latitude']),
            'lon': float(loc['longitude']),
            'type': 'pipeline',
            'score': loc['score_total'],
            'size': max(5, loc['score_total'] // 5),
            'color': color_map.get(loc['recommendation'], '#6b7280')
        })

    print(f"\n=== Chart 6: Map Data ===")
    print(f"Total points: {len(map_points)} ({len(stores)} active + {len(locations)} pipeline)")

    return map_points


def generate_summary_kpis(stores, locations):
    """Generate summary KPI data for dashboard header."""
    cups_list = [s['avg_daily_cups'] for s in stores]
    within_budget = [l for l in locations if l['within_budget'] == 'Yes']
    breakeven = [l for l in within_budget if l['projected_daily_cups'] >= 290]

    kpis = {
        'total_active_stores': len(stores),
        'total_pipeline_locations': len(locations),
        'avg_cups_active': round(sum(cups_list) / len(cups_list)),
        'top_performer': max(stores, key=lambda x: x['avg_daily_cups'])['store_name'],
        'top_performer_cups': max(cups_list),
        'locations_within_budget': len(within_budget),
        'locations_above_breakeven': len(breakeven),
        'breakeven_cups_at_20k': 290,
        'budget_monthly': 20000,
        'top_recommendation': locations[0]['store_name'],
        'top_recommendation_score': locations[0]['score_total'],
    }

    print("\n=== Dashboard KPIs ===")
    for k, v in kpis.items():
        print(f"  {k}: {v}")

    return kpis


def main():
    print("=" * 70)
    print("  LUCKIN COFFEE USA - DASHBOARD DATA GENERATOR")
    print("=" * 70)

    stores = load_active_stores()
    locations = load_pipeline_locations()

    # Generate all chart data
    charts = {
        'chart_1_area_type': generate_chart_1_area_type_performance(stores),
        'chart_2_score_vs_cups': generate_chart_2_score_vs_cups(locations),
        'chart_3_rent_efficiency': generate_chart_3_rent_efficiency(locations),
        'chart_4_score_breakdown': generate_chart_4_scoring_breakdown(locations),
        'chart_5_breakeven': generate_chart_5_breakeven_analysis(),
        'chart_6_map': generate_chart_6_map_data(stores, locations),
        'kpis': generate_summary_kpis(stores, locations),
    }

    # Save charts JSON
    output_path = os.path.join(DASHBOARD_DIR, 'chart_data.json')
    with open(output_path, 'w') as f:
        json.dump(charts, f, indent=2)

    print(f"\n{'=' * 70}")
    print(f"  Dashboard data saved to: {output_path}")
    print(f"  Charts generated: {len(charts)}")
    print(f"{'=' * 70}")

    try:
        import matplotlib
        matplotlib.use('Agg')
        import matplotlib.pyplot as plt
        import matplotlib.patches as mpatches

        # Chart 1: Area Type Bar Chart
        fig, ax = plt.subplots(figsize=(12, 6))
        chart1 = charts['chart_1_area_type']
        names = [d['area_type'] for d in chart1]
        cups = [d['avg_cups'] for d in chart1]
        colors = ['#22c55e' if c >= 400 else '#3b82f6' if c >= 300 else '#f59e0b' if c >= 200 else '#ef4444' for c in cups]
        bars = ax.barh(names, cups, color=colors)
        ax.set_xlabel('Average Daily Cups')
        ax.set_title('Luckin Coffee USA: Area Type vs Daily Cup Performance')
        ax.axvline(x=290, color='red', linestyle='--', label='Breakeven (290 cups at $20K rent)')
        ax.legend()
        for bar, cup in zip(bars, cups):
            ax.text(bar.get_width() + 5, bar.get_y() + bar.get_height()/2, f'{cup}', va='center', fontsize=9)
        plt.tight_layout()
        plt.savefig(os.path.join(DASHBOARD_DIR, 'chart_area_type_performance.png'), dpi=150)
        plt.close()

        # Chart 2: Score vs Projected Cups Scatter
        fig, ax = plt.subplots(figsize=(12, 7))
        chart2_data = charts['chart_2_score_vs_cups']
        for d in chart2_data:
            color = '#22c55e' if 'Strongly' in d['recommendation'] else '#3b82f6' if d['recommendation'] == 'Recommended' else '#f59e0b'
            ax.scatter(d['score'], d['projected_cups'], s=150, c=color, edgecolors='black', linewidth=0.5, zorder=5)
            ax.annotate(d['name'], (d['score'], d['projected_cups']), textcoords="offset points",
                       xytext=(5, 5), fontsize=8)
        ax.axhline(y=290, color='red', linestyle='--', alpha=0.7, label='Breakeven (290 cups)')
        ax.set_xlabel('Model Score (0-100)')
        ax.set_ylabel('Projected Daily Cups')
        ax.set_title('Luckin Coffee USA: Model Score vs Projected Cup Sales')
        ax.legend()
        ax.grid(True, alpha=0.3)
        plt.tight_layout()
        plt.savefig(os.path.join(DASHBOARD_DIR, 'chart_score_vs_cups.png'), dpi=150)
        plt.close()

        # Chart 4: Stacked Score Breakdown
        fig, ax = plt.subplots(figsize=(14, 7))
        chart4 = charts['chart_4_score_breakdown']
        names = [d['name'] for d in chart4]
        y_pos = range(len(names))

        area = [d['area_type'] for d in chart4]
        subway = [d['subway'] for d in chart4]
        weekend = [d['weekend'] for d in chart4]
        rent = [d['rent_value'] for d in chart4]
        cannibal = [d['cannibalization'] for d in chart4]

        ax.barh(y_pos, area, color='#3b82f6', label='Area Type (35)')
        ax.barh(y_pos, subway, left=area, color='#22c55e', label='Subway (20)')
        left2 = [a + s for a, s in zip(area, subway)]
        ax.barh(y_pos, weekend, left=left2, color='#f59e0b', label='Weekend (15)')
        left3 = [l + w for l, w in zip(left2, weekend)]
        ax.barh(y_pos, rent, left=left3, color='#8b5cf6', label='Rent Value (15)')

        # Cannibalization penalty (negative bars)
        for i, c in enumerate(cannibal):
            if c < 0:
                total = area[i] + subway[i] + weekend[i] + rent[i]
                ax.barh(i, c, left=total, color='#ef4444')

        ax.set_yticks(y_pos)
        ax.set_yticklabels(names)
        ax.set_xlabel('Score Points')
        ax.set_title('Luckin Coffee USA: Score Breakdown by Factor (Top 10 Locations)')
        ax.legend(loc='lower right')
        cannibal_patch = mpatches.Patch(color='#ef4444', label='Cannibalization (-15)')
        handles, labels = ax.get_legend_handles_labels()
        handles.append(cannibal_patch)
        ax.legend(handles=handles, loc='lower right')
        plt.tight_layout()
        plt.savefig(os.path.join(DASHBOARD_DIR, 'chart_score_breakdown.png'), dpi=150)
        plt.close()

        print("\n  PNG charts saved to dashboard/ folder")

    except ImportError:
        print("\n  Note: matplotlib not installed. Skipping PNG chart generation.")
        print("  Install with: pip install matplotlib")
        print("  JSON data is still available for dashboard tools (Grafana, Tableau, etc.)")


if __name__ == "__main__":
    main()
