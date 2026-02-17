#!/usr/bin/env python3
"""
UC-PR-01 Phase 3: BCG/Kasavana-Smith Menu Engineering Matrix Visualization

Generates a professional scatter-plot of the Menu Engineering Matrix with:
- X-axis: Sales Mix % (popularity)
- Y-axis: Contribution Margin % (profitability)
- Quadrant coloring: Star (green), Plow Horse (blue), Puzzle (orange), Dog (red)
- Bubble size proportional to total contribution margin dollars
- Threshold lines at weighted average CM% and popularity threshold (1/N × 70%)
- Product labels for key items
"""

import csv
import os
import matplotlib
matplotlib.use('Agg')  # Non-interactive backend
import matplotlib.pyplot as plt
import matplotlib.patches as mpatches
from matplotlib.ticker import FuncFormatter
import numpy as np

# ── Configuration ──────────────────────────────────────────────────────────────
DATA_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "data")
INPUT_CSV = os.path.join(DATA_DIR, "cost_model_output.csv")
OUTPUT_DIR = os.path.join(DATA_DIR, "charts")

COLORS = {
    "Star": "#2ecc71",        # Green
    "Plow Horse": "#3498db",  # Blue
    "Puzzle": "#f39c12",      # Orange
    "Dog": "#e74c3c",         # Red
}

QUADRANT_BG = {
    "Star": "#2ecc7115",
    "Plow Horse": "#3498db15",
    "Puzzle": "#f39c1215",
    "Dog": "#e74c3c15",
}

# Short labels for readability
SHORT_NAMES = {
    "Iced Coconut Latte": "Iced Coconut",
    "Drip Coffee": "Drip Coffee",
    "Iced Kyoto Matcha Latte": "Kyoto Matcha Iced",
    "Latte (Hot)": "Latte Hot",
    "Iced Velvet Latte": "Velvet Iced",
    "Iced Latte": "Iced Latte",
    "Cold Brew": "Cold Brew",
    "Coconut Latte (Hot)": "Coconut Hot",
    "Iced Kyoto Matcha Coconut Latte": "Matcha Coco Iced",
    "Kyoto Matcha Latte (Hot)": "Matcha Hot",
    "Iced Caramel Popcorn Latte": "Caramel Popcorn",
    "Sausage Egg Cheese Croissant": "Sausage Croissant",
    "Cappuccino (Hot)": "Cappuccino",
    "Velvet Latte (Hot)": "Velvet Hot",
    "Americano (Hot)": "Americano Hot",
    "Iced Americano": "Iced Americano",
    "Pineapple Cold Brew": "Pineapple CB",
    "Vital Kale": "Vital Kale",
    "Spanish Latte (Hot)": "Spanish Hot",
    "Toffee Hazelnut Latte (Hot)": "Toffee Hazelnut",
    "Mango Coconut Sunrise": "Mango Sunrise",
    "Kyoto Matcha Coconut Latte (Hot)": "Matcha Coco Hot",
    "Iced Toffee Hazelnut Latte": "Toffee Iced",
    "Iced Matcha Latte": "Matcha Iced",
    "Iced Matcha Coconut Latte": "Matcha Coco Iced",
    "Blood Orange Cold Brew": "Blood Orange CB",
    "Raspberry Cold Brew": "Raspberry CB",
    "Pistachio Matcha Coconut Latte (Hot)": "Pistachio Matcha",
    "Pistachio Oat Latte (Hot)": "Pistachio Oat Hot",
    "Iced Pistachio Oat Latte": "Pistachio Oat Iced",
    "Kyoto Matcha Smoothie": "Matcha Smoothie",
    "Iced Creme Brulee Latte": "Creme Brulee Iced",
    "Caramel Popcorn Latte (Hot)": "Caramel Pop Hot",
    "Creme Brulee Latte (Hot)": "Creme Brulee Hot",
    "Iced Spanish Latte": "Spanish Iced",
    "Iced Pistachio Matcha Coconut Latte": "Pistachio Matcha Iced",
    "Iced Coconut Velvet Latte": "Coco Velvet Iced",
    "Iced Pumpkin Spice Latte": "Pumpkin Iced",
    "Pumpkin Spice Latte (Hot)": "Pumpkin Hot",
    "Iced Flat White": "Flat White Iced",
    "Iced Latte (Flat White variant)": "Flat White v2",
}


def load_data():
    """Load cost model output CSV."""
    items = []
    with open(INPUT_CSV, "r") as f:
        reader = csv.DictReader(f)
        for row in reader:
            items.append({
                "spu": row["spu_code"],
                "name": row["product_name"],
                "category": row["category"],
                "cm_pct": float(row["cm_pct"]),
                "sales_mix_pct": float(row["sales_mix_pct"]),
                "total_cm": float(row["total_cm"]),
                "total_revenue": float(row["total_revenue"]),
                "classification": row["classification"],
                "qty_sold": int(row["qty_sold"]),
                "cm_dollar": float(row["cm_dollar"]),
                "cogs": float(row["cogs"]),
                "discount_depth": float(row["discount_depth"]),
            })
    return items


def compute_thresholds(items):
    """Compute the BCG threshold lines."""
    n = len(items)
    popularity_threshold = (1.0 / n) * 70.0  # 70% rule: 1/N × 70
    # Revenue-weighted CM% — matches cost_model.py classification threshold
    total_revenue = sum(i["total_revenue"] for i in items)
    total_cm = sum(i["total_cm"] for i in items)
    weighted_cm = (total_cm / total_revenue) * 100.0 if total_revenue else 0
    return popularity_threshold, weighted_cm


def short_name(name):
    """Get short display name."""
    return SHORT_NAMES.get(name, name[:18])


def create_main_matrix(items, pop_thresh, cm_thresh):
    """Create the primary BCG Matrix scatter plot."""
    fig, ax = plt.subplots(figsize=(20, 14))

    # ── Quadrant background fills ──────────────────────────────────────────
    x_max = max(i["sales_mix_pct"] for i in items) * 1.15
    y_min = min(i["cm_pct"] for i in items) - 5
    y_max = max(i["cm_pct"] for i in items) + 5

    # Star quadrant (high popularity, high margin)
    ax.axhspan(cm_thresh, y_max, xmin=pop_thresh / x_max, xmax=1.0,
               alpha=0.06, color="#2ecc71", zorder=0)
    # Plow Horse quadrant (high popularity, low margin)
    ax.axhspan(y_min, cm_thresh, xmin=pop_thresh / x_max, xmax=1.0,
               alpha=0.06, color="#3498db", zorder=0)
    # Puzzle quadrant (low popularity, high margin)
    ax.axhspan(cm_thresh, y_max, xmin=0, xmax=pop_thresh / x_max,
               alpha=0.06, color="#f39c12", zorder=0)
    # Dog quadrant (low popularity, low margin)
    ax.axhspan(y_min, cm_thresh, xmin=0, xmax=pop_thresh / x_max,
               alpha=0.06, color="#e74c3c", zorder=0)

    # ── Threshold lines ────────────────────────────────────────────────────
    ax.axhline(y=cm_thresh, color="#555555", linewidth=1.5, linestyle="--",
               alpha=0.7, zorder=2)
    ax.axvline(x=pop_thresh, color="#555555", linewidth=1.5, linestyle="--",
               alpha=0.7, zorder=2)

    # Threshold labels
    ax.text(x_max * 0.98, cm_thresh + 1.2,
            f"CM% Threshold: {cm_thresh:.1f}%",
            ha="right", va="bottom", fontsize=9, color="#555555",
            fontstyle="italic", zorder=5)
    ax.text(pop_thresh + 0.08, y_max - 2,
            f"Popularity Threshold: {pop_thresh:.2f}%",
            ha="left", va="top", fontsize=9, color="#555555",
            fontstyle="italic", rotation=90, zorder=5)

    # ── Quadrant labels ────────────────────────────────────────────────────
    label_props = dict(fontsize=16, fontweight="bold", alpha=0.25, zorder=1)
    mid_pop_high = (pop_thresh + x_max) / 2
    mid_pop_low = pop_thresh / 2
    mid_cm_high = (cm_thresh + y_max) / 2
    mid_cm_low = (y_min + cm_thresh) / 2

    ax.text(mid_pop_high, mid_cm_high, "STAR", ha="center", va="center",
            color="#27ae60", **label_props)
    ax.text(mid_pop_high, mid_cm_low, "PLOW HORSE", ha="center", va="center",
            color="#2980b9", **label_props)
    ax.text(mid_pop_low, mid_cm_high, "PUZZLE", ha="center", va="center",
            color="#e67e22", **label_props)
    ax.text(mid_pop_low, mid_cm_low, "DOG", ha="center", va="center",
            color="#c0392b", **label_props)

    # ── Plot items as bubbles ──────────────────────────────────────────────
    # Bubble size proportional to total_cm (capped for visual clarity)
    max_cm = max(abs(i["total_cm"]) for i in items)

    for item in items:
        color = COLORS[item["classification"]]
        # Scale bubble size: sqrt for area perception, range 80-2000
        size = max(80, min(2000, (abs(item["total_cm"]) / max_cm) * 2000))

        ax.scatter(
            item["sales_mix_pct"], item["cm_pct"],
            s=size, c=color, alpha=0.65, edgecolors="white",
            linewidth=1.2, zorder=4
        )

    # ── Label top items and interesting outliers ───────────────────────────
    # Label: all Stars, all Plow Horses, and notable Puzzles/Dogs
    label_items = [i for i in items if
                   i["classification"] in ("Star", "Plow Horse") or
                   i["sales_mix_pct"] > 0.8 or
                   i["cm_pct"] > 75 or
                   i["cm_pct"] < 15 or
                   i["total_cm"] > 8000]

    # Track label positions to avoid overlap
    placed = []

    for item in sorted(label_items, key=lambda x: -x["total_cm"]):
        x = item["sales_mix_pct"]
        y = item["cm_pct"]
        label = short_name(item["name"])

        # Determine offset direction based on position
        x_offset = 0.15
        y_offset = 2.0

        # Try to avoid overlaps with previously placed labels
        for px, py in placed:
            if abs(x - px) < 0.6 and abs(y - py) < 5:
                y_offset = -y_offset if y_offset > 0 else y_offset - 2

        ax.annotate(
            label,
            xy=(x, y),
            xytext=(x + x_offset, y + y_offset),
            fontsize=7.5,
            color="#333333",
            fontweight="medium",
            arrowprops=dict(arrowstyle="-", color="#aaaaaa", lw=0.5),
            zorder=6,
            bbox=dict(boxstyle="round,pad=0.15", facecolor="white",
                      edgecolor="#cccccc", alpha=0.85)
        )
        placed.append((x, y))

    # ── Axes formatting ────────────────────────────────────────────────────
    ax.set_xlabel("Sales Mix % (Popularity)", fontsize=13, fontweight="bold",
                  labelpad=10)
    ax.set_ylabel("Contribution Margin % (Profitability)", fontsize=13,
                  fontweight="bold", labelpad=10)
    ax.set_title(
        "Luckin Coffee USA — Menu Engineering Matrix (BCG/Kasavana-Smith)\n"
        f"58 SKUs | Weighted Avg CM: {cm_thresh:.1f}% | "
        f"Popularity Threshold: {pop_thresh:.2f}%",
        fontsize=15, fontweight="bold", pad=20
    )

    ax.set_xlim(-0.3, x_max)
    ax.set_ylim(y_min, y_max)
    ax.xaxis.set_major_formatter(FuncFormatter(lambda x, _: f"{x:.1f}%"))
    ax.yaxis.set_major_formatter(FuncFormatter(lambda y, _: f"{y:.0f}%"))
    ax.grid(True, alpha=0.2, linestyle="-", linewidth=0.5)
    ax.set_axisbelow(True)

    # ── Legend ─────────────────────────────────────────────────────────────
    counts = {}
    for i in items:
        c = i["classification"]
        counts[c] = counts.get(c, 0) + 1

    legend_handles = [
        mpatches.Patch(color=COLORS["Star"], label=f"Star ({counts.get('Star', 0)})"),
        mpatches.Patch(color=COLORS["Plow Horse"],
                       label=f"Plow Horse ({counts.get('Plow Horse', 0)})"),
        mpatches.Patch(color=COLORS["Puzzle"],
                       label=f"Puzzle ({counts.get('Puzzle', 0)})"),
        mpatches.Patch(color=COLORS["Dog"], label=f"Dog ({counts.get('Dog', 0)})"),
    ]
    ax.legend(handles=legend_handles, loc="upper right", fontsize=10,
              framealpha=0.9, edgecolor="#cccccc", title="Classification",
              title_fontsize=11)

    # ── Annotation: bubble size explanation ─────────────────────────────────
    ax.text(0.02, 0.02,
            "Bubble size = Total Contribution Margin $\n"
            "Data period: Recent sales data | Cost model: Hybrid (qty × est. unit price)",
            transform=ax.transAxes, fontsize=8, color="#888888",
            va="bottom", ha="left",
            bbox=dict(boxstyle="round,pad=0.3", facecolor="white",
                      edgecolor="#dddddd", alpha=0.8))

    plt.tight_layout()
    return fig


def create_category_breakdown(items, pop_thresh, cm_thresh):
    """Create a 2x2 grid with per-category views."""
    categories = {
        "beverage_hot": "Hot Beverages",
        "beverage_iced": "Iced Beverages",
        "food": "Food Items",
    }

    fig, axes = plt.subplots(2, 2, figsize=(18, 14))
    axes = axes.flatten()

    for idx, (cat_key, cat_label) in enumerate(categories.items()):
        ax = axes[idx]
        cat_items = [i for i in items if i["category"] == cat_key]

        if not cat_items:
            ax.text(0.5, 0.5, "No data", ha="center", va="center", fontsize=14)
            ax.set_title(cat_label)
            continue

        # Threshold lines
        ax.axhline(y=cm_thresh, color="#555555", linewidth=1, linestyle="--", alpha=0.5)
        ax.axvline(x=pop_thresh, color="#555555", linewidth=1, linestyle="--", alpha=0.5)

        max_cm = max(abs(i["total_cm"]) for i in cat_items) if cat_items else 1

        for item in cat_items:
            color = COLORS[item["classification"]]
            size = max(60, min(1200, (abs(item["total_cm"]) / max_cm) * 1200))
            ax.scatter(item["sales_mix_pct"], item["cm_pct"],
                       s=size, c=color, alpha=0.65, edgecolors="white",
                       linewidth=1, zorder=3)

            # Label all items in category view
            label = short_name(item["name"])
            ax.annotate(label, xy=(item["sales_mix_pct"], item["cm_pct"]),
                        xytext=(5, 5), textcoords="offset points",
                        fontsize=6.5, color="#333333",
                        bbox=dict(boxstyle="round,pad=0.1", facecolor="white",
                                  edgecolor="#dddddd", alpha=0.8),
                        zorder=5)

        cat_count = len(cat_items)
        cat_revenue = sum(i["total_revenue"] for i in cat_items)
        cat_cm = sum(i["total_cm"] for i in cat_items)
        avg_cm = cat_cm / cat_revenue * 100 if cat_revenue > 0 else 0

        ax.set_title(f"{cat_label} ({cat_count} items, ${cat_revenue:,.0f} rev, "
                     f"{avg_cm:.1f}% avg CM)", fontsize=11, fontweight="bold")
        ax.set_xlabel("Sales Mix %", fontsize=9)
        ax.set_ylabel("CM %", fontsize=9)
        ax.xaxis.set_major_formatter(FuncFormatter(lambda x, _: f"{x:.1f}%"))
        ax.yaxis.set_major_formatter(FuncFormatter(lambda y, _: f"{y:.0f}%"))
        ax.grid(True, alpha=0.15)
        ax.set_axisbelow(True)

    # Use 4th panel for summary statistics
    ax = axes[3]
    ax.axis("off")

    # Summary stats table
    stats = []
    for cls in ["Star", "Plow Horse", "Puzzle", "Dog"]:
        cls_items = [i for i in items if i["classification"] == cls]
        if cls_items:
            cnt = len(cls_items)
            rev = sum(i["total_revenue"] for i in cls_items)
            cm = sum(i["total_cm"] for i in cls_items)
            qty = sum(i["qty_sold"] for i in cls_items)
            avg_cm_pct = cm / rev * 100 if rev > 0 else 0
            stats.append([cls, cnt, f"${rev:,.0f}", f"${cm:,.0f}",
                          f"{avg_cm_pct:.1f}%", f"{qty:,}"])

    total_rev = sum(i["total_revenue"] for i in items)
    total_cm = sum(i["total_cm"] for i in items)
    total_qty = sum(i["qty_sold"] for i in items)
    stats.append(["TOTAL", len(items), f"${total_rev:,.0f}", f"${total_cm:,.0f}",
                  f"{total_cm / total_rev * 100:.1f}%", f"{total_qty:,}"])

    table = ax.table(
        cellText=stats,
        colLabels=["Quadrant", "Count", "Revenue", "Total CM$", "Avg CM%", "Units"],
        cellLoc="center",
        loc="center",
        colWidths=[0.15, 0.08, 0.18, 0.18, 0.12, 0.15]
    )
    table.auto_set_font_size(False)
    table.set_fontsize(10)
    table.scale(1.0, 1.8)

    # Style header row
    for col in range(6):
        cell = table[0, col]
        cell.set_facecolor("#34495e")
        cell.set_text_props(color="white", fontweight="bold")

    # Style quadrant rows
    row_colors = {0: "#2ecc71", 1: "#3498db", 2: "#f39c12", 3: "#e74c3c", 4: "#ecf0f1"}
    for row in range(5):
        for col in range(6):
            cell = table[row + 1, col]
            cell.set_facecolor(row_colors.get(row, "white"))
            cell.set_alpha(0.2 if row < 4 else 0.4)
            if row == 4:
                cell.set_text_props(fontweight="bold")

    ax.set_title("Classification Summary", fontsize=12, fontweight="bold", pad=20)

    fig.suptitle("Luckin Coffee USA — Menu Engineering by Category",
                 fontsize=15, fontweight="bold", y=1.01)
    plt.tight_layout()
    return fig


def create_margin_vs_discount(items):
    """Scatter plot of CM% vs Discount Depth — shows pricing power."""
    fig, ax = plt.subplots(figsize=(16, 10))

    for item in items:
        color = COLORS[item["classification"]]
        size = max(40, min(800, item["qty_sold"] / 100))
        ax.scatter(item["discount_depth"], item["cm_pct"],
                   s=size, c=color, alpha=0.6, edgecolors="white",
                   linewidth=0.8, zorder=3)

    # Label interesting outliers
    for item in items:
        if (item["cm_pct"] > 78 or item["cm_pct"] < 10 or
                item["discount_depth"] > 54 or
                item["qty_sold"] > 20000):
            ax.annotate(
                short_name(item["name"]),
                xy=(item["discount_depth"], item["cm_pct"]),
                xytext=(5, 5), textcoords="offset points",
                fontsize=7, color="#333333",
                bbox=dict(boxstyle="round,pad=0.1", facecolor="white",
                          edgecolor="#dddddd", alpha=0.85),
                zorder=5
            )

    # Trend line
    x_vals = [i["discount_depth"] for i in items]
    y_vals = [i["cm_pct"] for i in items]
    z = np.polyfit(x_vals, y_vals, 1)
    p = np.poly1d(z)
    x_range = np.linspace(min(x_vals) - 2, max(x_vals) + 2, 100)
    ax.plot(x_range, p(x_range), "--", color="#888888", alpha=0.5, linewidth=1.5,
            label=f"Trend (slope: {z[0]:.2f})")

    ax.set_xlabel("Discount Depth % (List Price → Paid Price)", fontsize=12,
                  fontweight="bold", labelpad=10)
    ax.set_ylabel("Contribution Margin %", fontsize=12, fontweight="bold",
                  labelpad=10)
    ax.set_title("Margin Erosion Analysis: CM% vs Discount Depth\n"
                 "Bubble size = Units Sold",
                 fontsize=14, fontweight="bold", pad=15)

    ax.xaxis.set_major_formatter(FuncFormatter(lambda x, _: f"{x:.0f}%"))
    ax.yaxis.set_major_formatter(FuncFormatter(lambda y, _: f"{y:.0f}%"))
    ax.grid(True, alpha=0.2)
    ax.set_axisbelow(True)

    legend_handles = [
        mpatches.Patch(color=COLORS[c], label=c) for c in COLORS
    ]
    ax.legend(handles=legend_handles, loc="upper right", fontsize=9,
              framealpha=0.9, title="Classification", title_fontsize=10)

    plt.tight_layout()
    return fig


def create_top_bottom_bar(items):
    """Horizontal bar chart — top 10 and bottom 10 by CM$."""
    fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(18, 10))

    sorted_items = sorted(items, key=lambda x: x["total_cm"], reverse=True)

    # Top 10
    top10 = sorted_items[:10]
    names = [short_name(i["name"]) for i in top10]
    values = [i["total_cm"] for i in top10]
    colors = [COLORS[i["classification"]] for i in top10]

    y_pos = range(len(top10))
    bars = ax1.barh(y_pos, values, color=colors, alpha=0.8, edgecolor="white")
    ax1.set_yticks(y_pos)
    ax1.set_yticklabels(names, fontsize=10)
    ax1.invert_yaxis()
    ax1.set_xlabel("Total Contribution Margin ($)", fontsize=11, fontweight="bold")
    ax1.set_title("Top 10 by Total CM$", fontsize=13, fontweight="bold")
    ax1.xaxis.set_major_formatter(FuncFormatter(lambda x, _: f"${x:,.0f}"))

    for bar, item in zip(bars, top10):
        ax1.text(bar.get_width() + 500, bar.get_y() + bar.get_height() / 2,
                 f"${item['total_cm']:,.0f}  ({item['cm_pct']:.0f}% CM)",
                 va="center", fontsize=8, color="#555555")

    # Bottom 10
    bottom10 = sorted_items[-10:]
    names_b = [short_name(i["name"]) for i in bottom10]
    values_b = [i["total_cm"] for i in bottom10]
    colors_b = [COLORS[i["classification"]] for i in bottom10]

    y_pos_b = range(len(bottom10))
    bars_b = ax2.barh(y_pos_b, values_b, color=colors_b, alpha=0.8, edgecolor="white")
    ax2.set_yticks(y_pos_b)
    ax2.set_yticklabels(names_b, fontsize=10)
    ax2.invert_yaxis()
    ax2.set_xlabel("Total Contribution Margin ($)", fontsize=11, fontweight="bold")
    ax2.set_title("Bottom 10 by Total CM$", fontsize=13, fontweight="bold")
    ax2.xaxis.set_major_formatter(FuncFormatter(lambda x, _: f"${x:,.0f}"))

    for bar, item in zip(bars_b, bottom10):
        offset = max(bar.get_width(), 0) + 200
        ax2.text(offset, bar.get_y() + bar.get_height() / 2,
                 f"${item['total_cm']:,.0f}  ({item['cm_pct']:.0f}% CM)",
                 va="center", fontsize=8, color="#555555")

    fig.suptitle("Luckin Coffee USA — Contribution Margin Ranking",
                 fontsize=14, fontweight="bold", y=1.01)
    plt.tight_layout()
    return fig


def create_cogs_waterfall(items):
    """COGS composition chart — avg COGS per unit by category."""
    fig, ax = plt.subplots(figsize=(16, 8))

    # Sort by COGS descending
    sorted_items = sorted(items, key=lambda x: x["cogs"], reverse=True)[:20]

    names = [short_name(i["name"]) for i in sorted_items]
    cogs_vals = [i["cogs"] for i in sorted_items]
    cm_vals = [max(0, i["cm_dollar"]) for i in sorted_items]
    colors = [COLORS[i["classification"]] for i in sorted_items]

    x = range(len(sorted_items))
    width = 0.35

    bars1 = ax.bar([i - width / 2 for i in x], cogs_vals, width, label="COGS/unit",
                   color="#e74c3c", alpha=0.7, edgecolor="white")
    bars2 = ax.bar([i + width / 2 for i in x], cm_vals, width, label="CM$/unit",
                   color="#2ecc71", alpha=0.7, edgecolor="white")

    ax.set_xticks(x)
    ax.set_xticklabels(names, rotation=45, ha="right", fontsize=8)
    ax.set_ylabel("$ per Unit", fontsize=11, fontweight="bold")
    ax.set_title("Top 20 Items by COGS — Unit Economics Breakdown\n"
                 "COGS vs Contribution Margin per Unit",
                 fontsize=13, fontweight="bold", pad=15)
    ax.yaxis.set_major_formatter(FuncFormatter(lambda y, _: f"${y:.2f}"))
    ax.legend(fontsize=10, loc="upper right")
    ax.grid(True, alpha=0.15, axis="y")
    ax.set_axisbelow(True)

    plt.tight_layout()
    return fig


def main():
    os.makedirs(OUTPUT_DIR, exist_ok=True)

    print("Loading data...")
    items = load_data()
    pop_thresh, cm_thresh = compute_thresholds(items)
    print(f"  Items: {len(items)}")
    print(f"  Popularity threshold: {pop_thresh:.2f}%")
    print(f"  CM% threshold: {cm_thresh:.1f}%")

    counts = {}
    for i in items:
        c = i["classification"]
        counts[c] = counts.get(c, 0) + 1
    print(f"  Stars: {counts.get('Star', 0)}, Plow Horses: {counts.get('Plow Horse', 0)}, "
          f"Puzzles: {counts.get('Puzzle', 0)}, Dogs: {counts.get('Dog', 0)}")

    # Chart 1: Main BCG Matrix
    print("\n[1/5] Generating main BCG Matrix scatter plot...")
    fig1 = create_main_matrix(items, pop_thresh, cm_thresh)
    path1 = os.path.join(OUTPUT_DIR, "01_bcg_matrix.png")
    fig1.savefig(path1, dpi=150, bbox_inches="tight", facecolor="white")
    plt.close(fig1)
    print(f"  Saved: {path1}")

    # Chart 2: Category breakdown
    print("[2/5] Generating category breakdown...")
    fig2 = create_category_breakdown(items, pop_thresh, cm_thresh)
    path2 = os.path.join(OUTPUT_DIR, "02_category_breakdown.png")
    fig2.savefig(path2, dpi=150, bbox_inches="tight", facecolor="white")
    plt.close(fig2)
    print(f"  Saved: {path2}")

    # Chart 3: Margin vs Discount
    print("[3/5] Generating margin erosion analysis...")
    fig3 = create_margin_vs_discount(items)
    path3 = os.path.join(OUTPUT_DIR, "03_margin_vs_discount.png")
    fig3.savefig(path3, dpi=150, bbox_inches="tight", facecolor="white")
    plt.close(fig3)
    print(f"  Saved: {path3}")

    # Chart 4: Top/Bottom bar chart
    print("[4/5] Generating CM$ ranking bars...")
    fig4 = create_top_bottom_bar(items)
    path4 = os.path.join(OUTPUT_DIR, "04_cm_ranking.png")
    fig4.savefig(path4, dpi=150, bbox_inches="tight", facecolor="white")
    plt.close(fig4)
    print(f"  Saved: {path4}")

    # Chart 5: COGS waterfall
    print("[5/5] Generating COGS unit economics...")
    fig5 = create_cogs_waterfall(items)
    path5 = os.path.join(OUTPUT_DIR, "05_cogs_unit_economics.png")
    fig5.savefig(path5, dpi=150, bbox_inches="tight", facecolor="white")
    plt.close(fig5)
    print(f"  Saved: {path5}")

    print(f"\n✓ All 5 charts saved to {OUTPUT_DIR}/")
    print("\nChart index:")
    print("  01_bcg_matrix.png          — Primary Menu Engineering Matrix (scatter)")
    print("  02_category_breakdown.png  — Per-category views + summary table")
    print("  03_margin_vs_discount.png  — Margin erosion vs discount depth")
    print("  04_cm_ranking.png          — Top 10 / Bottom 10 by total CM$")
    print("  05_cogs_unit_economics.png — COGS vs CM per unit (top 20)")


if __name__ == "__main__":
    main()
