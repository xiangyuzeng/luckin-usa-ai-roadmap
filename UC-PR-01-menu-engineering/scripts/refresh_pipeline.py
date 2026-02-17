#!/usr/bin/env python3
"""UC-PR-01 Phase 7 — Automated Dashboard Refresh Pipeline.

Orchestrates Phases 2-5, recomputes KPIs, and updates dashboard.html
with fresh embedded data via targeted regex replacement.

Usage:
    python scripts/refresh_pipeline.py
    python scripts/refresh_pipeline.py --dry-run
    python scripts/refresh_pipeline.py --skip-scripts --dry-run
"""

import argparse
import csv
import json
import logging
import os
import re
import subprocess
import sys
from datetime import datetime

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
)
log = logging.getLogger("refresh_pipeline")

BASE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA = os.path.join(BASE, "data")
SCRIPTS = os.path.join(BASE, "scripts")
DASHBOARD = os.path.join(DATA, "dashboard.html")

PHASES = [
    ("Phase 2 — Cost Model", "cost_model.py"),
    ("Phase 3 — BCG Matrix", "bcg_matrix_viz.py"),
    ("Phase 4 — Affinity", "affinity_analysis.py"),
    ("Phase 5 — Trends", "trend_analysis.py"),
]


# ── helpers ──────────────────────────────────────────────────────────
def flt(v, d=0.0):
    """Safe float conversion."""
    try:
        return float(v)
    except (ValueError, TypeError):
        return d


def itv(v, d=0):
    """Safe int conversion."""
    try:
        return int(float(v))
    except (ValueError, TypeError):
        return d


def js_num(v):
    """Format number for JS: strip trailing zeros."""
    if isinstance(v, int):
        return str(v)
    s = f"{v:.2f}".rstrip("0").rstrip(".")
    return s


def fmt_money(v):
    """Format dollar value as $X.XXM or $X.XXK."""
    if v >= 1_000_000:
        return f"${v / 1_000_000:.2f}M"
    if v >= 1_000:
        return f"${v / 1_000:.0f}K"
    return f"${v:.0f}"


def fmt_k(v):
    """Format count as XK or X."""
    if v >= 1_000:
        return f"{v / 1_000:.0f}K"
    return f"{v:,.0f}"


def fmt_mo(m):
    """'2025-06' → \"Jun '25\"."""
    parts = m.split("-")
    names = [
        "", "Jan", "Feb", "Mar", "Apr", "May", "Jun",
        "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
    ]
    return f"{names[int(parts[1])]} '{parts[0][2:]}"


def esc(s):
    """Escape string for JS embedding."""
    return s.replace("\\", "\\\\").replace("'", "\\'").replace('"', '\\"')


# ── pipeline orchestration ───────────────────────────────────────────
def run_phases(dry_run=False):
    """Run Phase 2-5 scripts in sequence."""
    for label, script in PHASES:
        path = os.path.join(SCRIPTS, script)
        if not os.path.exists(path):
            log.warning("%s: %s not found, skipping", label, script)
            continue
        if dry_run:
            log.info("[DRY RUN] Would run %s", label)
            continue
        log.info("Running %s ...", label)
        result = subprocess.run(
            [sys.executable, path],
            capture_output=True, text=True, cwd=BASE,
        )
        if result.returncode != 0:
            log.error("%s failed (rc=%d):\n%s", label, result.returncode,
                      result.stderr[-2000:] if result.stderr else "(no stderr)")
            raise RuntimeError(f"{label} failed")
        log.info("%s completed", label)


# ── data loading ─────────────────────────────────────────────────────
def read_csv(name):
    """Read CSV from data/ dir, return list of dicts."""
    path = os.path.join(DATA, name)
    if not os.path.exists(path):
        log.error("Missing %s", path)
        return []
    with open(path, newline="", encoding="utf-8") as f:
        return list(csv.DictReader(f))


def load_data():
    """Load all Phase 2-5 outputs."""
    cost = read_csv("cost_model_output.csv")
    trends = read_csv("trend_summary.csv")
    monthly = read_csv("monthly_sales.csv")
    affinity = read_csv("affinity_pairs.csv")
    log.info("Loaded: %d cost, %d trends, %d monthly, %d affinity rows",
             len(cost), len(trends), len(monthly), len(affinity))
    return cost, trends, monthly, affinity


# ── KPI computation ─────────────────────────────────────────────────
def compute_kpis(cost, trends, monthly, affinity):
    """Compute all dashboard KPIs from raw CSV data."""
    k = {}

    # Revenue / units
    k["rev"] = sum(flt(r["total_revenue"]) for r in cost)
    k["units"] = sum(itv(r["qty_sold"]) for r in cost)

    # Revenue-weighted CM%
    total_cm = sum(flt(r["total_cm"]) for r in cost)
    k["cm_pct"] = (total_cm / k["rev"] * 100) if k["rev"] else 0

    # Average discount depth
    wt_disc = sum(flt(r["discount_depth"]) * flt(r["total_revenue"]) for r in cost)
    k["disc"] = (wt_disc / k["rev"]) if k["rev"] else 0

    # Monthly order totals
    raw_month_totals = {}
    for r in monthly:
        m = r["month"]
        raw_month_totals[m] = raw_month_totals.get(m, 0) + itv(r["qty"])

    # Filter to months with meaningful volume (>1000 orders) to exclude
    # early ramp-up months that distort CMGR
    all_months = sorted(
        m for m, v in raw_month_totals.items() if v >= 1000
    )
    if not all_months:
        all_months = sorted(raw_month_totals.keys())
    k["months"] = all_months

    # Month totals only for significant months
    month_totals = {m: raw_month_totals[m] for m in all_months}
    k["month_totals"] = month_totals

    # CMGR (Compound Monthly Growth Rate)
    if len(all_months) >= 2:
        first_m, last_m = all_months[0], all_months[-1]
        v0 = month_totals.get(first_m, 1)
        vn = month_totals.get(last_m, 1)
        n = len(all_months) - 1
        if v0 > 0 and vn > 0 and n > 0:
            k["cmgr"] = ((vn / v0) ** (1 / n) - 1) * 100
        else:
            k["cmgr"] = 0
    else:
        k["cmgr"] = 0

    # Classification counts & revenue
    cls_map = {"Star": 0, "Plow Horse": 0, "Puzzle": 0, "Dog": 0, "Uncosted": 0}
    cls_rev = {"Star": 0, "Plow Horse": 0, "Puzzle": 0, "Dog": 0, "Uncosted": 0}
    for r in cost:
        c = r.get("classification", "Uncosted")
        if c in cls_map:
            cls_map[c] += 1
            cls_rev[c] += flt(r["total_revenue"])
    # Add Uncosted from trends not in cost
    costed_spus = {r["spu_code"] for r in cost}
    for r in trends:
        if r["spu_code"] not in costed_spus:
            cls_map["Uncosted"] += 1
    k["cls"] = cls_map
    k["n_items"] = sum(cls_map.values())
    k["cls_rev"] = cls_rev

    # Trend directions (ALL items incl Uncosted for doughnut)
    dirs = {"Growing": 0, "Stable": 0, "Declining": 0}
    for r in trends:
        d = r.get("direction", "")
        if d in dirs:
            dirs[d] += 1
    k["dirs"] = dirs
    k["n_analyzed"] = sum(dirs.values())

    # Trend × Classification (excl Uncosted) for stacked bar
    tc = {}
    for d in ["Growing", "Stable", "Declining"]:
        tc[d] = {"Star": 0, "Plow Horse": 0, "Puzzle": 0, "Dog": 0}
    for r in trends:
        c = r.get("classification", "Uncosted")
        d = r.get("direction", "")
        if c != "Uncosted" and d in tc:
            tc[d][c] = tc[d].get(c, 0) + 1
    k["tc"] = tc

    # BCG thresholds
    k["bcg_cm"] = k["cm_pct"]
    costed_count = sum(v for key, v in cls_map.items() if key != "Uncosted")
    k["bcg_pop"] = round(70 / costed_count, 2) if costed_count else 1.21

    # Affinity KPIs — parse from report if available
    report_path = os.path.join(DATA, "phase4_affinity_report.md")
    k["aff_orders"] = 0
    k["aff_multi"] = 0
    k["aff_basket"] = 1.0
    if os.path.exists(report_path):
        with open(report_path, encoding="utf-8") as f:
            rpt = f.read()
        m = re.search(r"([\d,]+)\s+(?:completed )?orders", rpt, re.IGNORECASE)
        if m:
            k["aff_orders"] = int(m.group(1).replace(",", ""))
        m = re.search(r"([\d,]+)\s+(?:multi-item|\()", rpt)
        if m:
            k["aff_multi"] = int(m.group(1).replace(",", ""))
        m = re.search(r"(?:basket|items per order).*?([\d.]+)", rpt, re.IGNORECASE)
        if m:
            k["aff_basket"] = float(m.group(1))
    k["aff_multi_pct"] = (
        k["aff_multi"] / k["aff_orders"] * 100 if k["aff_orders"] else 0
    )

    # Affinity pair stats from CSV
    k["aff_lift"] = sum(1 for r in affinity if flt(r.get("lift", 0)) > 1)
    k["aff_total"] = len(affinity)
    k["aff_cross"] = sum(
        1 for r in affinity
        if r.get("cross_category", "").strip() in ("True", "Y", "N")
        and r.get("cross_category", "").strip() not in ("N",)
    )
    # Recount cross_category properly
    k["aff_cross"] = sum(
        1 for r in affinity
        if r.get("cross_category", "").strip() in ("True", "Y")
    )

    # Top SPUs for share trend (top 10 by avg_qty_share, excl Uncosted)
    ranked = sorted(
        [r for r in trends
         if r.get("classification", "Uncosted") != "Uncosted"
         and flt(r.get("avg_qty_share", 0)) > 0],
        key=lambda r: flt(r["avg_qty_share"]),
        reverse=True,
    )
    k["top_spus"] = [r["spu_code"] for r in ranked[:10]]

    # Share trend months (skip first month if it has too few items)
    k["share_months"] = all_months[1:] if len(all_months) > 1 else all_months

    # Build monthly sales lookup: {spu: [{month, qty, rev}, ...]}
    ms = {}
    for r in monthly:
        spu = r["spu_code"]
        if spu not in ms:
            ms[spu] = []
        ms[spu].append({
            "month": r["month"],
            "qty": itv(r["qty"]),
            "rev": round(flt(r["revenue"]), 2),
        })
    # Sort each SPU's entries by month
    for spu in ms:
        ms[spu].sort(key=lambda x: x["month"])
    k["monthly_sales"] = ms

    # Strategic action lists
    k["watch"] = [
        r for r in trends
        if r.get("classification") == "Star"
        and r.get("direction") == "Declining"
    ]
    k["promote"] = [
        r for r in trends
        if r.get("classification") == "Puzzle"
        and r.get("direction") == "Growing"
    ]
    k["emerging"] = [
        r for r in trends
        if r.get("classification") == "Dog"
        and r.get("direction") == "Growing"
    ]
    k["volatile"] = sorted(
        [r for r in trends if flt(r.get("volatility_cv", 0)) > 80],
        key=lambda r: flt(r["volatility_cv"]),
        reverse=True,
    )[:5]

    return k


# ── JS data builders ────────────────────────────────────────────────
def build_products_js(cost, trends):
    """Build the `const products = [...]` JS array."""
    trend_map = {r["spu_code"]: r for r in trends}
    lines = []
    for r in cost:
        spu = r["spu_code"]
        t = trend_map.get(spu, {})
        lines.append(
            f'  {{spu:"{spu}",name:"{esc(r["product_name"])}",'
            f'cat:"{r["category"]}",cls:"{r["classification"]}",'
            f'cogs:{js_num(flt(r["cogs"]))},avgPaid:{js_num(flt(r["avg_paid_price"]))},'
            f'cm:{js_num(flt(r["cm_dollar"]))},cmPct:{js_num(flt(r["cm_pct"]))},'
            f'disc:{js_num(flt(r["discount_depth"]))},qty:{itv(r["qty_sold"])},'
            f'mix:{js_num(flt(r["sales_mix_pct"]))},rev:{itv(flt(r["total_revenue"]))},'
            f'totalCm:{js_num(flt(r["total_cm"]))}}}'
        )
    return "const products = [\n" + ",\n".join(lines) + "\n];"


def build_trends_js(trends):
    """Build the `const trends = [...]` JS array."""
    lines = []
    for r in trends:
        avg_share = flt(r.get("avg_qty_share", 0))
        trend_pct = flt(r.get("rel_trend_pct", 0))
        r2 = flt(r.get("r_squared", 0))
        mom = flt(r.get("momentum_pct", 0))
        cv = flt(r.get("volatility_cv", 0))
        direction = r.get("direction", "")
        # Handle items with no trend data (too few months)
        if direction and direction != "None":
            lines.append(
                f'  {{spu:"{r["spu_code"]}",name:"{esc(r["product_name"])}",'
                f'cls:"{r.get("classification", "Uncosted")}",'
                f'avgShare:{js_num(avg_share)},trendPct:{js_num(trend_pct)},'
                f'r2:{js_num(r2)},mom:{js_num(mom)},cv:{js_num(cv)},'
                f'dir:"{direction}"}}'
            )
        else:
            lines.append(
                f'  {{spu:"{r["spu_code"]}",name:"{esc(r["product_name"])}",'
                f'cls:"{r.get("classification", "Uncosted")}",'
                f'avgShare:null,trendPct:null,r2:null,mom:null,cv:null,dir:null}}'
            )
    return "const trends = [\n" + ",\n".join(lines) + "\n];"


def build_monthly_js(monthly_sales):
    """Build the `const msRaw = ...` pipe-delimited string."""
    parts = []
    for spu, entries in sorted(monthly_sales.items()):
        for e in entries:
            parts.append(f'{spu},{e["month"]},{e["qty"]},{e["rev"]}')
    raw = "|".join(parts)
    return (
        "const monthlySales = {};\n"
        f"const msRaw = `{raw}`;\n"
        "msRaw.split('|').forEach(r => {\n"
        "  const [spu,m,q,v] = r.split(',');\n"
        "  if(!monthlySales[spu]) monthlySales[spu] = [];\n"
        "  monthlySales[spu].push({month:m, qty:+q, rev:+v});\n"
        "});"
    )


def build_affinity_js(affinity):
    """Build the `const affinityPairs = [...]` JS array."""
    lines = []
    for r in affinity:
        # Truncate names for display
        na = r.get("name_a", r.get("spu_a", ""))[:25]
        nb = r.get("name_b", r.get("spu_b", ""))[:25]
        cross = "Y" if r.get("cross_category", "").strip() in ("True", "Y") else "N"
        lines.append(
            f'  {{a:"{esc(na)}",b:"{esc(nb)}",'
            f'co:{itv(r.get("co_occurrences", 0))},'
            f'lift:{js_num(flt(r.get("lift", 0)))},'
            f'cm:{js_num(flt(r.get("combined_cm_dollar", 0)))},'
            f'cross:"{cross}"}}'
        )
    return "const affinityPairs = [\n" + ",\n".join(lines) + "\n];"


# ── HTML patching ────────────────────────────────────────────────────
def patch_html(html, kpis, cost, trends, monthly_sales, affinity):
    """Replace embedded data and KPI values in dashboard HTML."""

    # ── 1. Overview KPI cards (lines ~89-92) ──
    html = re.sub(
        r'(<h3>Total Revenue</h3><div class="kpi">)\$[^<]+(</div><div class="kpi-sub">)[\d,]+ units sold',
        lambda m: (
            f'{m.group(1)}{fmt_money(kpis["rev"])}{m.group(2)}'
            f'{kpis["units"]:,} units sold'
        ),
        html
    )
    html = re.sub(
        r'(<h3>Avg CM%</h3><div class="kpi">)[\d.]+%',
        lambda m: f'{m.group(1)}{kpis["cm_pct"]:.1f}%',
        html
    )
    html = re.sub(
        r'(<h3>Avg Discount</h3><div class="kpi">)[\d.]+%',
        lambda m: f'{m.group(1)}{kpis["disc"]:.1f}%',
        html
    )
    # CMGR
    sign = "+" if kpis["cmgr"] >= 0 else ""
    first_mo = fmt_mo(kpis["months"][0]) if kpis["months"] else "?"
    last_mo = fmt_mo(kpis["months"][-1]) if kpis["months"] else "?"
    html = re.sub(
        r'(<h3>Order Growth</h3><div class="kpi"[^>]*>)[^<]+(</div><div class="kpi-sub">)CMGR[^<]+',
        lambda m: (
            f'{m.group(1)}{sign}{kpis["cmgr"]:.1f}%{m.group(2)}'
            f'CMGR {first_mo} — {last_mo}'
        ),
        html
    )

    # ── 2. Trend direction summary title ──
    html = re.sub(
        r'Trend Direction Summary \(\d+ Analyzed SPUs\)',
        f'Trend Direction Summary ({kpis["n_analyzed"]} Analyzed SPUs)',
        html
    )

    # ── 3. Affinity KPI cards ──
    html = re.sub(
        r'(<h3>Orders Analyzed</h3><div class="kpi">)[^<]+(</div><div class="kpi-sub">)[\d,]+ multi-item \([\d.]+%\)',
        lambda m: (
            f'{m.group(1)}{fmt_k(kpis["aff_orders"])}{m.group(2)}'
            f'{kpis["aff_multi"]:,} multi-item ({kpis["aff_multi_pct"]:.1f}%)'
        ),
        html
    )
    html = re.sub(
        r'(<h3>Avg Basket Size</h3><div class="kpi">)[\d.]+',
        lambda m: f'{m.group(1)}{kpis["aff_basket"]:.2f}',
        html
    )
    html = re.sub(
        r'(<h3>Pairs with Lift >1</h3><div class="kpi">)\d+(</div><div class="kpi-sub">)of \d+ unique pairs',
        lambda m: (
            f'{m.group(1)}{kpis["aff_lift"]}{m.group(2)}'
            f'of {kpis["aff_total"]} unique pairs'
        ),
        html
    )
    html = re.sub(
        r'(<h3>Cross-Category Pairs</h3><div class="kpi">)\d+',
        lambda m: f'{m.group(1)}{kpis["aff_cross"]}',
        html
    )

    # ── 4. Explorer filter button counts ──
    cls = kpis["cls"]
    html = re.sub(
        r'(data-cls="all"[^>]*>)All \(\d+\)',
        lambda m: f'{m.group(1)}All ({kpis["n_items"]})',
        html
    )
    html = re.sub(
        r'(data-cls="Star"[^>]*>.*?)Stars \(\d+\)',
        lambda m: f'{m.group(1)}Stars ({cls["Star"]})',
        html
    )
    html = re.sub(
        r'(data-cls="Plow Horse"[^>]*>.*?)Plow \(\d+\)',
        lambda m: f'{m.group(1)}Plow ({cls["Plow Horse"]})',
        html
    )
    html = re.sub(
        r'(data-cls="Puzzle"[^>]*>.*?)Puzzles \(\d+\)',
        lambda m: f'{m.group(1)}Puzzles ({cls["Puzzle"]})',
        html
    )
    html = re.sub(
        r'(data-cls="Dog"[^>]*>.*?)Dogs \(\d+\)',
        lambda m: f'{m.group(1)}Dogs ({cls["Dog"]})',
        html
    )
    html = re.sub(
        r'(data-cls="Uncosted"[^>]*>.*?)Uncosted \(\d+\)',
        lambda m: f'{m.group(1)}Uncosted ({cls["Uncosted"]})',
        html
    )

    # ── 5. Replace JS data blocks ──
    # products array
    products_js = build_products_js(cost, trends)
    html = re.sub(
        r'const products = \[.*?\];',
        products_js,
        html,
        flags=re.DOTALL,
    )

    # trends array
    trends_js = build_trends_js(
        sorted(
            [r for r in trends],  # all trends
            key=lambda r: flt(r.get("avg_qty_share", 0)),
            reverse=True,
        )
    )
    html = re.sub(
        r'const trends = \[.*?\];',
        trends_js,
        html,
        flags=re.DOTALL,
    )

    # monthly sales
    monthly_js = build_monthly_js(kpis["monthly_sales"])
    html = re.sub(
        r'const monthlySales = \{\};.*?monthlySales\[spu\]\.push\(\{month:m, qty:\+q, rev:\+v\}\);\n\}\);',
        monthly_js,
        html,
        flags=re.DOTALL,
    )

    # affinity pairs
    affinity_js = build_affinity_js(affinity)
    html = re.sub(
        r'const affinityPairs = \[.*?\];',
        affinity_js,
        html,
        flags=re.DOTALL,
    )

    # ── 6. Update chart config values ──
    # Classification distribution doughnut
    cls_counts_js = json.dumps(cls)
    html = re.sub(
        r"const clsCounts = \{[^}]+\};",
        f"const clsCounts = {cls_counts_js};",
        html,
    )

    # Trend direction doughnut labels+data
    dirs = kpis["dirs"]
    html = re.sub(
        r"labels:\['Growing \(\d+\)','Stable \(\d+\)','Declining \(\d+\)'\],datasets:\[\{data:\[\d+,\d+,\d+\]",
        f"labels:['Growing ({dirs['Growing']})','Stable ({dirs['Stable']})','Declining ({dirs['Declining']})'],"
        f"datasets:[{{data:[{dirs['Growing']},{dirs['Stable']},{dirs['Declining']}]",
        html,
    )

    # Trend x Classification stacked bar
    tc = kpis["tc"]
    for direction in ["Growing", "Stable", "Declining"]:
        vals = tc[direction]
        old_pat = f"label:'{direction}',data:\\[\\d+,\\d+,\\d+,\\d+\\]"
        new_val = (
            f"label:'{direction}',"
            f"data:[{vals['Star']},{vals['Plow Horse']},{vals['Puzzle']},{vals['Dog']}]"
        )
        html = re.sub(old_pat, new_val, html)

    # Monthly orders: months array and totals
    months_js = ",".join(f"'{m}'" for m in kpis["months"])
    html = re.sub(
        r"(// Monthly orders\n\s+)const months = \[[^\]]+\];",
        f"\\1const months = [{months_js}];",
        html,
    )

    # BCG annotation lines (CM% avg and pop threshold)
    html = re.sub(
        r"yMin:[\d.]+,yMax:[\d.]+,borderColor:'#666',borderDash:\[5,5\],borderWidth:1,label:\{content:'CM% avg = [\d.]+%'",
        f"yMin:{js_num(kpis['bcg_cm'])},yMax:{js_num(kpis['bcg_cm'])},"
        f"borderColor:'#666',borderDash:[5,5],borderWidth:1,"
        f"label:{{content:'CM% avg = {kpis['bcg_cm']:.1f}%'",
        html,
    )
    html = re.sub(
        r"xMin:[\d.]+,xMax:[\d.]+,borderColor:'#666',borderDash:\[5,5\],borderWidth:1,label:\{content:'Pop\. threshold = [\d.]+%'",
        f"xMin:{js_num(kpis['bcg_pop'])},xMax:{js_num(kpis['bcg_pop'])},"
        f"borderColor:'#666',borderDash:[5,5],borderWidth:1,"
        f"label:{{content:'Pop. threshold = {kpis['bcg_pop']:.2f}%'",
        html,
    )

    # Share trend: months and top SPUs
    share_months_js = ",".join(f"'{m}'" for m in kpis["share_months"])
    html = re.sub(
        r"(function drawShareTrend\(\) \{\n\s+)const months = \[[^\]]+\];",
        f"\\1const months = [{share_months_js}];",
        html,
    )
    top_spus_js = ",".join(f"'{s}'" for s in kpis["top_spus"])
    html = re.sub(
        r"const topSpus = \[[^\]]+\];",
        f"const topSpus = [{top_spus_js}];",
        html,
    )

    # ── 7. Update strategic actions ──
    html = _patch_action_list(html, "watchItems", kpis["watch"], _watch_detail)
    html = _patch_action_list(html, "promoItems", kpis["promote"], _promo_detail)
    html = _patch_action_list(html, "emergingItems", kpis["emerging"], _emerging_detail)
    html = _patch_action_list(html, "volatileItems", kpis["volatile"], _volatile_detail)

    return html


def _patch_action_list(html, var_name, items, detail_fn):
    """Replace a strategic action list JS array."""
    if not items:
        return html
    entries = []
    for r in items[:6]:
        name = esc(r.get("product_name", ""))
        detail = esc(detail_fn(r))
        entries.append(f"    {{name:'{name}',detail:'{detail}'}}")
    block = f"const {var_name} = [\n" + ",\n".join(entries) + "\n  ];"
    pattern = rf"const {var_name} = \[.*?\];"
    html = re.sub(pattern, block, html, flags=re.DOTALL)
    return html


def _watch_detail(r):
    trend = flt(r.get("rel_trend_pct", 0))
    return f'Share declining at {trend:.1f}%/month — monitor closely'


def _promo_detail(r):
    trend = flt(r.get("rel_trend_pct", 0))
    cm = flt(r.get("cm_pct", 0))
    return f'+{trend:.1f}%/mo share growth, {cm:.1f}% CM — promote to Star via app featuring'


def _emerging_detail(r):
    trend = flt(r.get("rel_trend_pct", 0))
    cm = flt(r.get("cm_pct", 0))
    mom = flt(r.get("momentum_pct", 0))
    return f'+{trend:.1f}%/mo share growth, {cm:.1f}% CM — gaining momentum ({mom:+.0f}%), monitor'


def _volatile_detail(r):
    cv = flt(r.get("volatility_cv", 0))
    return f'CV {cv:.0f}% — high volatility, investigate seasonality patterns'


# ── main ─────────────────────────────────────────────────────────────
def main():
    parser = argparse.ArgumentParser(description="UC-PR-01 Dashboard Refresh Pipeline")
    parser.add_argument("--dry-run", action="store_true",
                        help="Show what would happen without writing files")
    parser.add_argument("--skip-scripts", action="store_true",
                        help="Skip running Phase 2-5 scripts (use existing CSVs)")
    args = parser.parse_args()

    log.info("=== UC-PR-01 Dashboard Refresh Pipeline ===")
    log.info("Base: %s", BASE)

    # Step 1: Run upstream scripts
    if not args.skip_scripts:
        run_phases(dry_run=args.dry_run)
    else:
        log.info("Skipping Phase 2-5 scripts (--skip-scripts)")

    # Step 2: Load data
    cost, trends, monthly, affinity = load_data()
    if not cost:
        log.error("No cost data — cannot proceed")
        sys.exit(1)

    # Step 3: Compute KPIs
    kpis = compute_kpis(cost, trends, monthly, affinity)
    log.info("KPIs: rev=%s, units=%s, CM%%=%.1f%%, disc=%.1f%%, CMGR=%+.1f%%",
             fmt_money(kpis["rev"]), f'{kpis["units"]:,}',
             kpis["cm_pct"], kpis["disc"], kpis["cmgr"])
    log.info("Classification: %s", kpis["cls"])
    log.info("Trends: %s", kpis["dirs"])

    # Step 4: Patch dashboard HTML
    if not os.path.exists(DASHBOARD):
        log.error("Dashboard not found: %s", DASHBOARD)
        sys.exit(1)

    with open(DASHBOARD, encoding="utf-8") as f:
        html = f.read()

    html_new = patch_html(html, kpis, cost, trends, kpis["monthly_sales"], affinity)

    if args.dry_run:
        changed = html_new != html
        log.info("[DRY RUN] Dashboard would %s",
                 "be updated" if changed else "remain unchanged")
        # Show diff stats
        old_lines = html.splitlines()
        new_lines = html_new.splitlines()
        log.info("[DRY RUN] Lines: %d → %d", len(old_lines), len(new_lines))
    else:
        # Backup
        backup = DASHBOARD + f".bak.{datetime.now().strftime('%Y%m%d_%H%M%S')}"
        with open(backup, "w", encoding="utf-8") as f:
            f.write(html)
        log.info("Backup: %s", backup)

        # Write
        with open(DASHBOARD, "w", encoding="utf-8") as f:
            f.write(html_new)
        log.info("Dashboard updated: %s", DASHBOARD)

    log.info("=== Pipeline complete ===")


if __name__ == "__main__":
    main()
