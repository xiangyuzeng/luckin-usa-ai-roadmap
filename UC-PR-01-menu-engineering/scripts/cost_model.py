#!/usr/bin/env python3
"""
UC-PR-01: Menu Engineering Matrix — Phase 2 Cost Model
=======================================================
Hybrid approach: ingredient quantities (from formula_json) x estimated US wholesale unit prices.

Since no procurement/pricing data exists in the databases, we use US foodservice
wholesale market prices (2024-2025) as best estimates for ingredient unit costs.

Output: cost_model_output.csv with COGS per serving and contribution margins.
"""

import csv
import os
from dataclasses import dataclass, field
from typing import Dict, List, Optional

# =============================================================================
# SECTION 1: US Wholesale Unit Price Reference
# =============================================================================
# Sources: USDA ERS, Sysco/US Foods catalogs, specialty distributor pricing
# All prices are per-unit as indicated (per gram, per ml, per piece)

UNIT_PRICES: Dict[str, Dict] = {
    # --- Coffee Beans (per gram) ---
    # Specialty espresso beans: ~$8-12/lb wholesale = $0.018-0.026/g
    "GS07465": {"name": "Medium Roast Espresso", "price_per_unit": 0.020, "unit": "g"},
    "GS07466": {"name": "Dark Roast Espresso", "price_per_unit": 0.020, "unit": "g"},
    "GS07467": {"name": "Single Origin Espresso", "price_per_unit": 0.024, "unit": "g"},
    "GS07468": {"name": "Decaf Espresso", "price_per_unit": 0.022, "unit": "g"},
    "GS07470": {"name": "Drip Coffee Blend", "price_per_unit": 0.016, "unit": "g"},

    # --- Milk & Dairy (per ml unless noted) ---
    # Conventional milk: ~$3.50-4.50/gal wholesale = ~$0.001/ml
    "GS07566": {"name": "Tuscan Whole Milk", "price_per_unit": 0.0012, "unit": "ml"},
    "GS07571": {"name": "Tuscan 2% Reduced Fat Milk", "price_per_unit": 0.0012, "unit": "ml"},
    "GS07568": {"name": "Tuscan Fat Free Milk", "price_per_unit": 0.0011, "unit": "ml"},
    "GS07785": {"name": "Cream-O-Land 2% Milk", "price_per_unit": 0.0012, "unit": "ml"},
    "GS07786": {"name": "Cream-O-Land Whole Milk", "price_per_unit": 0.0012, "unit": "ml"},
    "GS07788": {"name": "Cream-O-Land Fat Free Milk", "price_per_unit": 0.0011, "unit": "ml"},
    "GS06091": {"name": "SGP Skimmed Milk", "price_per_unit": 0.0011, "unit": "ml"},
    # Plant-based milks: premium pricing ~$15-20/gal equivalent
    "GS07506": {"name": "Barista Coconut Milk", "price_per_unit": 0.0040, "unit": "ml"},
    "GS07565": {"name": "Oatly Oat Milk", "price_per_unit": 0.0050, "unit": "ml"},
    "GS07579": {"name": "Califia Almond Milk", "price_per_unit": 0.0042, "unit": "ml"},
    # Cream & condensed (per gram)
    "GS07743": {"name": "Heavy Whipping Cream", "price_per_unit": 0.0035, "unit": "g"},
    "GS07763": {"name": "Condensed Milk Sweetened", "price_per_unit": 0.0080, "unit": "g"},

    # --- Syrups (per ml) ---
    # DVG/DaVinci syrups: ~$8-12/750ml bottle = $0.011-0.016/ml
    "GS07490": {"name": "DVG Cinnamon Bark Syrup", "price_per_unit": 0.013, "unit": "ml"},
    "GS07491": {"name": "DVG Hazelnut Syrup", "price_per_unit": 0.013, "unit": "ml"},
    "GS07493": {"name": "DVG Peppermint Syrup", "price_per_unit": 0.013, "unit": "ml"},
    "GS07494": {"name": "DVG Cane Sugar Syrup", "price_per_unit": 0.011, "unit": "ml"},
    "GS07495": {"name": "DVG Vanilla Syrup", "price_per_unit": 0.013, "unit": "ml"},
    "GS07496": {"name": "DVG Caramel Syrup", "price_per_unit": 0.013, "unit": "ml"},
    "GS07737": {"name": "DVG Mango Syrup", "price_per_unit": 0.013, "unit": "ml"},
    "GS07739": {"name": "DVG Pineapple Syrup", "price_per_unit": 0.013, "unit": "ml"},
    "GS07749": {"name": "DVG Strawberry Syrup", "price_per_unit": 0.013, "unit": "ml"},
    "GS08285": {"name": "DVG Pumpkin Pie Syrup", "price_per_unit": 0.015, "unit": "ml"},
    "GS08300": {"name": "Popcorn Syrup", "price_per_unit": 0.015, "unit": "ml"},
    "GS08916": {"name": "Creme Brulee Syrup", "price_per_unit": 0.016, "unit": "ml"},
    "GS08917": {"name": "Toffee Nut Syrup", "price_per_unit": 0.016, "unit": "ml"},
    # Sauces (per gram)
    "GS07769": {"name": "Caramel Sauce (Lyons Magnus)", "price_per_unit": 0.012, "unit": "g"},

    # --- Matcha & Tea (per gram) ---
    "GS07509": {"name": "Matcha Sweet Blend", "price_per_unit": 0.035, "unit": "g"},
    "GS07976": {"name": "Kyoto Matcha 100g", "price_per_unit": 0.055, "unit": "g"},
    "GS07505": {"name": "Jasmine Tea Powder", "price_per_unit": 0.030, "unit": "g"},

    # --- Fruits, Purees & Juices ---
    "GS07492": {"name": "BC Vanilla Smoothie Base", "price_per_unit": 0.008, "unit": "g"},
    "GS07504": {"name": "Green Juice Blend", "price_per_unit": 0.005, "unit": "ml"},
    "GS07508": {"name": "Purple Juice Blend", "price_per_unit": 0.005, "unit": "ml"},
    "GS07510": {"name": "Coconut Water", "price_per_unit": 0.003, "unit": "ml"},
    "GS07513": {"name": "Andros Strawberry Chunks", "price_per_unit": 0.012, "unit": "g"},
    "GS07564": {"name": "Andros Raspberry Puree", "price_per_unit": 0.013, "unit": "g"},
    "GS07736": {"name": "Raspberry IQF", "price_per_unit": 0.009, "unit": "g"},
    "GS07742": {"name": "Blood Orange", "price_per_unit": 0.010, "unit": "g"},
    "GS07745": {"name": "Canned Grapefruit in Syrup", "price_per_unit": 0.008, "unit": "g"},
    "GS07758": {"name": "Florida's Natural Grapefruit Juice", "price_per_unit": 0.003, "unit": "ml"},
    "GS08279": {"name": "Canned Pumpkin", "price_per_unit": 0.005, "unit": "g"},
    "GS07965": {"name": "Mulberry Purple Cabbage Juice", "price_per_unit": 0.005, "unit": "ml"},
    "GS07966": {"name": "Orange Carrot Juice", "price_per_unit": 0.005, "unit": "ml"},

    # --- Other Ingredients ---
    "GS07573": {"name": "Semi Sweet Chocolate Chips", "price_per_unit": 0.012, "unit": "g"},
    "GS07574": {"name": "Hazelnut Dark Cocoa Spread", "price_per_unit": 0.020, "unit": "g"},
    "GS07738": {"name": "Cinnamon Powder", "price_per_unit": 0.030, "unit": "g"},
    "GS07744": {"name": "Cocoa Powder", "price_per_unit": 0.015, "unit": "g"},

    # --- Packaging (per piece) ---
    "GS07437": {"name": "Straw", "price_per_unit": 0.02, "unit": "pc"},
    "GS07438": {"name": "16oz Iced Cup Flat Lid", "price_per_unit": 0.04, "unit": "pc"},
    "GS07439": {"name": "20oz Hot Cup", "price_per_unit": 0.10, "unit": "pc"},
    "GS07440": {"name": "24oz Iced Cup", "price_per_unit": 0.12, "unit": "pc"},
    "GS07441": {"name": "16oz Hot Cup", "price_per_unit": 0.08, "unit": "pc"},
    "GS07442": {"name": "Thick Straw (PLA)", "price_per_unit": 0.04, "unit": "pc"},
    "GS07443": {"name": "16oz Hot Cup Lid", "price_per_unit": 0.04, "unit": "pc"},
    "GS07444": {"name": "16oz Iced Cup Dome Lid", "price_per_unit": 0.05, "unit": "pc"},
    "GS07445": {"name": "PET Bottle Green", "price_per_unit": 0.15, "unit": "pc"},
    "GS07447": {"name": "Paper Bag", "price_per_unit": 0.06, "unit": "pc"},
    "GS07448": {"name": "16oz Iced Cup Sipper Lid", "price_per_unit": 0.04, "unit": "pc"},
    "GS07451": {"name": "16oz Iced Cup", "price_per_unit": 0.08, "unit": "pc"},
    "GS07777": {"name": "24oz Injection Molded Cup", "price_per_unit": 0.12, "unit": "pc"},
    "GS07778": {"name": "24oz Injection Molded Lid", "price_per_unit": 0.05, "unit": "pc"},
    "GS07638": {"name": "Cup Label Sticker", "price_per_unit": 0.03, "unit": "pc"},
    "GS08037": {"name": "PET Bottle (Universal)", "price_per_unit": 0.15, "unit": "pc"},

    # --- Food Items (per piece, wholesale) ---
    "GS07859": {"name": "Sausage Egg Cheese Croissant", "price_per_unit": 2.50, "unit": "pc"},
    "GS08251": {"name": "Double Chocolate Muffin", "price_per_unit": 1.50, "unit": "pc"},
    "GS08252": {"name": "Almond Croissant", "price_per_unit": 1.80, "unit": "pc"},
    "GS08253": {"name": "Chocolate Chip Cookies", "price_per_unit": 1.00, "unit": "pc"},
    "GS08254": {"name": "Chocolate Croissant", "price_per_unit": 1.60, "unit": "pc"},

    # --- PFM Pre-mixes (semi-finished, estimated from component costs) ---
    # These are prepared in-house; costs estimated based on likely ingredients
    # PFM000005: Used at 32-120g/drink — enriched/thickened milk base, not a premium ingredient
    "PFM000005": {"name": "Velvet/Thick Milk Base", "price_per_unit": 0.006, "unit": "g"},
    "PFM000006": {"name": "Kale/Green Concentrate", "price_per_unit": 0.008, "unit": "ml"},
    "PFM000007": {"name": "Fruit Juice Base", "price_per_unit": 0.006, "unit": "ml"},
    "PFM000008": {"name": "Powder Additive", "price_per_unit": 0.015, "unit": "g"},
    "PFM000009": {"name": "Cold Brew Concentrate", "price_per_unit": 0.012, "unit": "ml"},
    "PFM000011": {"name": "Pineapple Mix/Puree", "price_per_unit": 0.008, "unit": "g"},
    "PFM000012": {"name": "Strawberry Smoothie Base", "price_per_unit": 0.010, "unit": "g"},
    "PFM000014": {"name": "Fruit/Veg Juice Concentrate", "price_per_unit": 0.008, "unit": "ml"},
    "PFM000015": {"name": "Mango Puree/Juice", "price_per_unit": 0.009, "unit": "ml"},
    "PFM000016": {"name": "Powder Additive v2", "price_per_unit": 0.015, "unit": "g"},
    "PFM000017": {"name": "Cold Brew Concentrate v2", "price_per_unit": 0.012, "unit": "ml"},
    "PFM000019": {"name": "Juice Additive", "price_per_unit": 0.008, "unit": "ml"},
    # PFM000020: Used at 45-125g/drink — diluted matcha+sugar+milk powder pre-mix, NOT pure matcha
    # DB shows only 0.1g of pure Kyoto Matcha (GS07976) added separately
    "PFM000020": {"name": "Kyoto Matcha Pre-mix", "price_per_unit": 0.012, "unit": "g"},
    "PFM000021": {"name": "Pineapple Base Mix", "price_per_unit": 0.008, "unit": "g"},
    "PFM000022": {"name": "Strawberry Base (alt)", "price_per_unit": 0.010, "unit": "g"},
    "PFM000023": {"name": "Popcorn/Toffee Topping", "price_per_unit": 0.018, "unit": "g"},
    "PFM000027": {"name": "Raspberry Topping", "price_per_unit": 0.012, "unit": "g"},
    # PFM000029: Used at 111.5g/drink — pistachio-flavored cream base, not pure pistachio paste
    "PFM000029": {"name": "Pistachio Cream/Paste", "price_per_unit": 0.012, "unit": "g"},
}

# =============================================================================
# SECTION 2: Standard Recipes (one canonical variant per SPU)
# =============================================================================
# Selected the most common/standard variant for each SPU.
# Each recipe is a list of (goods_code, quantity) tuples.

@dataclass
class Recipe:
    spu_code: str
    product_name: str
    category: str  # beverage_hot, beverage_iced, food
    size: str  # 16oz, 20oz, 24oz, bottle, piece
    ingredients: List[tuple]  # [(goods_code, quantity), ...]

RECIPES: List[Recipe] = [
    # ---- ESPRESSO-BASED (HOT) ----
    Recipe("PR000014", "Americano (Hot)", "beverage_hot", "16oz", [
        ("GS07465", 21), ("GS07441", 1), ("GS07443", 1), ("GS07638", 1),
    ]),
    Recipe("PR000016", "Latte (Hot)", "beverage_hot", "16oz", [
        ("GS07465", 14), ("GS07571", 350), ("GS07441", 1), ("GS07443", 1),
    ]),
    Recipe("PR000018", "Cappuccino (Hot)", "beverage_hot", "16oz", [
        ("GS07465", 14), ("GS07571", 270), ("GS07441", 1), ("GS07443", 1),
    ]),
    Recipe("PR000022", "Coconut Latte (Hot)", "beverage_hot", "16oz", [
        ("GS07465", 14), ("GS07506", 350), ("GS07441", 1), ("GS07443", 1),
    ]),
    Recipe("PR000024", "Velvet Latte (Hot)", "beverage_hot", "16oz", [
        ("GS07465", 21), ("PFM000005", 96), ("GS07566", 250),
        ("GS07441", 1), ("GS07443", 1),
    ]),
    Recipe("PR000026", "Hot Chocolate", "beverage_hot", "16oz", [
        ("GS07566", 322.5), ("PFM000005", 64), ("GS07494", 7.5),
        ("GS07441", 1), ("GS07443", 1),
    ]),
    Recipe("PR000047", "Coconut Velvet Latte (Hot)", "beverage_hot", "16oz", [
        ("GS07465", 14), ("GS07506", 290), ("PFM000005", 64),
        ("GS07441", 1), ("GS07443", 1),
    ]),
    Recipe("PR000081", "Caramel Popcorn Latte (Hot)", "beverage_hot", "16oz", [
        ("GS07465", 14), ("PFM000005", 96), ("GS08300", 15), ("GS07566", 270),
        ("GS07441", 1), ("GS07443", 1),
    ]),
    Recipe("PR000084", "Pumpkin Spice Latte (Hot)", "beverage_hot", "16oz", [
        ("GS08279", 23), ("GS07465", 14), ("GS08285", 15), ("GS07490", 7.5),
        ("PFM000005", 32), ("GS07441", 1), ("GS07443", 1),
    ]),
    Recipe("PR000087", "Spanish Latte (Hot)", "beverage_hot", "16oz", [
        ("GS07763", 22), ("GS07465", 21), ("PFM000005", 32), ("GS07566", 345),
        ("GS07441", 1), ("GS07443", 1),
    ]),
    Recipe("PR000089", "Creme Brulee Latte (Hot)", "beverage_hot", "16oz", [
        ("GS07466", 14), ("GS08916", 15), ("PFM000005", 64), ("PFM000023", 25.5),
        ("GS07769", 5), ("GS07441", 1), ("GS07443", 1),
    ]),
    Recipe("PR000091", "Toffee Hazelnut Latte (Hot)", "beverage_hot", "16oz", [
        ("GS07466", 14), ("GS08917", 22.5), ("PFM000023", 25.5), ("GS07769", 5),
        ("GS07441", 1), ("GS07443", 1),
    ]),
    Recipe("PR000074", "Kyoto Matcha Coconut Latte (Hot)", "beverage_hot", "20oz", [
        ("GS07506", 390), ("PFM000020", 60),
        ("GS07439", 1), ("GS07443", 1),
    ]),
    Recipe("PR000109", "Pistachio Matcha Coconut Latte (Hot)", "beverage_hot", "16oz", [
        ("PFM000020", 45), ("GS07506", 322.5), ("GS07494", 7.5), ("PFM000029", 111.5),
        ("GS07441", 1), ("GS07443", 1),
    ]),
    Recipe("PR000111", "Pistachio Oat Latte (Hot)", "beverage_hot", "16oz", [
        ("GS07465", 14), ("GS07491", 22.5), ("PFM000029", 111.5), ("GS07565", 307.5),
        ("GS07441", 1), ("GS07443", 1),
    ]),

    # ---- ESPRESSO-BASED (ICED) ----
    Recipe("PR000006", "Iced Americano", "beverage_iced", "16oz", [
        ("GS07465", 21), ("GS07437", 1), ("GS07438", 1), ("GS07638", 1), ("GS07451", 1),
    ]),
    Recipe("PR000015", "Iced Latte", "beverage_iced", "16oz", [
        ("GS07465", 14), ("GS07571", 210), ("GS07437", 1), ("GS07438", 1), ("GS07451", 1),
    ]),
    Recipe("PR000017", "Iced Latte (Flat White variant)", "beverage_iced", "16oz", [
        ("GS07466", 14), ("GS07571", 210), ("GS07437", 1), ("GS07438", 1), ("GS07451", 1),
    ]),
    Recipe("PR000020", "Iced Flat White", "beverage_iced", "16oz", [
        ("GS07466", 21), ("GS07566", 208), ("GS07437", 1), ("GS07438", 1), ("GS07451", 1),
    ]),
    Recipe("PR000021", "Iced Coconut Latte", "beverage_iced", "16oz", [
        ("GS07465", 14), ("GS07506", 210), ("GS07437", 1), ("GS07444", 1), ("GS07451", 1),
    ]),
    Recipe("PR000023", "Iced Velvet Latte", "beverage_iced", "16oz", [
        ("GS07465", 21), ("PFM000005", 96), ("GS07566", 122),
        ("GS07437", 1), ("GS07444", 1), ("GS07451", 1),
    ]),
    Recipe("PR000025", "Iced Chocolate", "beverage_iced", "16oz", [
        ("GS07566", 30), ("GS07743", 45.5), ("GS07744", 0.1), ("GS07494", 7.5),
        ("GS07437", 1), ("GS07444", 1), ("GS07451", 1),
    ]),
    Recipe("PR000027", "Iced Matcha Latte", "beverage_iced", "16oz", [
        ("GS07566", 210), ("GS07743", 35.7), ("GS07494", 7.5),
        ("GS07509", 25.2),
        ("GS07437", 1), ("GS07444", 1), ("GS07451", 1),
    ]),
    Recipe("PR000030", "Iced Matcha Coconut Latte", "beverage_iced", "16oz", [
        ("GS07506", 270), ("GS07509", 25.2),
        ("GS07437", 1), ("GS07444", 1), ("GS07451", 1),
    ]),
    Recipe("PR000045", "Iced Coconut Velvet Latte", "beverage_iced", "16oz", [
        ("GS07465", 14), ("GS07506", 150), ("PFM000005", 64),
        ("GS07437", 1), ("GS07438", 1), ("GS07451", 1),
    ]),
    Recipe("PR000080", "Iced Caramel Popcorn Latte", "beverage_iced", "16oz", [
        ("GS07465", 14), ("PFM000005", 96), ("GS08300", 15), ("GS07566", 210),
        ("GS07437", 1), ("GS07444", 1), ("GS07451", 1),
    ]),
    Recipe("PR000083", "Iced Pumpkin Spice Latte", "beverage_iced", "16oz", [
        ("GS08279", 23), ("GS07465", 14), ("GS08285", 15), ("GS07490", 7.5),
        ("GS07437", 1), ("GS07444", 1), ("GS07451", 1),
    ]),
    Recipe("PR000086", "Iced Spanish Latte", "beverage_iced", "16oz", [
        ("GS07763", 22), ("GS07465", 21), ("PFM000005", 32),
        ("GS07437", 1), ("GS07438", 1), ("GS07451", 1),
    ]),
    Recipe("PR000088", "Iced Creme Brulee Latte", "beverage_iced", "16oz", [
        ("GS07466", 14), ("GS08916", 15), ("PFM000005", 64), ("PFM000023", 46.4),
        ("GS07437", 1), ("GS07444", 1), ("GS07451", 1),
    ]),
    Recipe("PR000090", "Iced Toffee Hazelnut Latte", "beverage_iced", "16oz", [
        ("GS07466", 14), ("GS08917", 22.5), ("PFM000023", 46.4), ("GS07769", 5),
        ("GS07437", 1), ("GS07444", 1), ("GS07451", 1),
    ]),
    Recipe("PR000108", "Iced Pistachio Matcha Coconut Latte", "beverage_iced", "16oz", [
        ("PFM000020", 45), ("GS07506", 270), ("GS07494", 7.5),
        ("GS07437", 1), ("GS07444", 1), ("GS07451", 1),
    ]),
    Recipe("PR000110", "Iced Pistachio Oat Latte", "beverage_iced", "16oz", [
        ("GS07465", 14), ("GS07491", 15), ("PFM000029", 111.5),
        ("GS07437", 1), ("GS07448", 1), ("GS07451", 1),
    ]),

    # ---- MATCHA SPECIALTY (ICED) ----
    Recipe("PR000071", "Iced Kyoto Matcha Latte", "beverage_iced", "16oz", [
        ("PFM000020", 120), ("GS07494", 30),
        ("GS07437", 1), ("GS07444", 1), ("GS07451", 1),
    ]),
    Recipe("PR000072", "Kyoto Matcha Latte (Hot)", "beverage_hot", "16oz", [
        ("PFM000020", 60), ("GS07566", 350), ("GS07494", 15),
        ("GS07441", 1), ("GS07443", 1),
    ]),
    Recipe("PR000073", "Iced Kyoto Matcha Coconut Latte", "beverage_iced", "16oz", [
        ("PFM000020", 60), ("GS07506", 270), ("GS07494", 15),
        ("GS07437", 1), ("GS07444", 1), ("GS07451", 1),
    ]),
    Recipe("PR000070", "Iced Matcha Coconut Water", "beverage_iced", "24oz", [
        ("PFM000020", 60), ("GS07494", 15), ("GS07510", 330),
        ("GS07437", 1), ("GS07438", 1), ("GS07440", 1),
    ]),
    Recipe("PR000075", "Kyoto Matcha Smoothie", "beverage_iced", "16oz", [
        ("PFM000020", 125), ("PFM000005", 64), ("GS07492", 40.5), ("PFM000023", 46.4),
        ("GS07442", 1), ("GS07444", 1), ("GS07451", 1),
    ]),

    # ---- COLD BREW ----
    Recipe("PR000031", "Cold Brew", "beverage_iced", "16oz", [
        ("PFM000009", 120), ("GS07437", 1), ("GS07448", 1), ("GS07451", 1),
    ]),
    Recipe("PR000032", "Blood Orange Cold Brew", "beverage_iced", "16oz", [
        ("GS07742", 157.5), ("PFM000017", 90),
        ("GS07437", 1), ("GS07438", 1), ("GS07451", 1),
    ]),
    Recipe("PR000033", "Pineapple Cold Brew", "beverage_iced", "16oz", [
        ("PFM000011", 90), ("GS07739", 15), ("PFM000009", 90),
        ("GS07437", 1), ("GS07438", 1), ("GS07451", 1),
    ]),
    Recipe("PR000034", "Raspberry Cold Brew", "beverage_iced", "16oz", [
        ("GS07564", 98.1), ("PFM000017", 90), ("GS07736", 32),
        ("GS07437", 1), ("GS07438", 1), ("GS07451", 1),
    ]),
    Recipe("PR000036", "Green Cold Brew", "beverage_iced", "16oz", [
        ("PFM000006", 90), ("PFM000009", 120),
        ("GS07437", 1), ("GS07448", 1), ("GS07451", 1),
    ]),

    # ---- DRIP COFFEE ----
    Recipe("PR000005", "Drip Coffee", "beverage_hot", "16oz", [
        ("GS07470", 20), ("GS07441", 1), ("GS07443", 1),
    ]),

    # ---- REFRESHERS ----
    Recipe("PR000041", "Strawberry Refresher", "beverage_iced", "16oz", [
        ("GS07749", 15), ("PFM000012", 120), ("PFM000007", 60), ("GS07494", 7.5),
        ("GS07437", 1), ("GS07438", 1), ("GS07451", 1),
    ]),
    Recipe("PR000042", "Pineapple Refresher", "beverage_iced", "16oz", [
        ("GS07739", 15), ("PFM000011", 120), ("PFM000007", 60),
        ("GS07437", 1), ("GS07438", 1), ("GS07451", 1),
    ]),

    # ---- SPECIALTY ICED DRINKS ----
    Recipe("PR000043", "Mango Coconut Sunrise", "beverage_iced", "16oz", [
        ("GS07506", 150), ("GS07737", 7.5), ("GS07568", 80),
        ("GS07749", 22.5), ("PFM000015", 60),
        ("GS07437", 1), ("GS07444", 1), ("GS07451", 1),
    ]),
    Recipe("PR000044", "Grapefruit Mango Drink", "beverage_iced", "16oz", [
        ("GS07742", 126), ("GS07745", 10), ("PFM000015", 60), ("GS07758", 30),
        ("GS07437", 1), ("GS07438", 1), ("GS07451", 1),
    ]),
    Recipe("PR000048", "Smoothie", "beverage_iced", "16oz", [
        ("GS07574", 3), ("GS07492", 24), ("GS07566", 120),
        ("GS07442", 1), ("GS07444", 1), ("GS07451", 1),
    ]),
    Recipe("PR000050", "Mango Pomelo Sago", "beverage_iced", "16oz", [
        ("GS07568", 150), ("GS07745", 10), ("GS07737", 15),
        ("GS07743", 35.7), ("GS07494", 7.5),
        ("GS07437", 1), ("GS07444", 1), ("GS07451", 1),
    ]),
    Recipe("PR000051", "Dreamy Strawberry", "beverage_iced", "16oz", [
        ("GS07513", 88), ("GS07749", 22.5), ("GS07568", 80),
        ("GS07743", 45.5), ("GS07494", 7.5),
        ("GS07437", 1), ("GS07444", 1), ("GS07451", 1),
    ]),

    # ---- JUICE BOTTLES ----
    Recipe("PR000039", "Vital Kale", "beverage_iced", "bottle", [
        ("GS07504", 180), ("PFM000006", 60), ("GS07494", 7.5),
        ("GS07442", 1), ("GS07445", 1),
    ]),
    Recipe("PR000068", "Zen Berry", "beverage_iced", "bottle", [
        ("PFM000019", 30), ("GS07965", 180), ("PFM000014", 60), ("GS07494", 7.5),
        ("GS07442", 1), ("GS08037", 1),
    ]),
    Recipe("PR000069", "Sunny Citrus", "beverage_iced", "bottle", [
        ("GS07966", 180), ("PFM000014", 60), ("GS07494", 7.5),
        ("GS07442", 1), ("GS08037", 1),
    ]),

    # ---- FOOD ITEMS ----
    Recipe("PR000063", "Sausage Egg Cheese Croissant", "food", "piece", [
        ("GS07859", 1), ("GS07447", 1),
    ]),
    Recipe("PR000076", "Almond Croissant", "food", "piece", [
        ("GS08252", 1), ("GS07447", 1),
    ]),
    Recipe("PR000077", "Chocolate Croissant", "food", "piece", [
        ("GS08254", 1), ("GS07447", 1),
    ]),
    Recipe("PR000078", "Double Chocolate Muffin", "food", "piece", [
        ("GS08251", 1), ("GS07447", 1),
    ]),
    Recipe("PR000079", "Chocolate Chip Cookies", "food", "piece", [
        ("GS08253", 1), ("GS07447", 1),
    ]),
]


# =============================================================================
# SECTION 3: Sales Data (from salesorder database)
# =============================================================================
# Extracted from t_order_item JOIN t_order with filters:
# delete_flag=0, spu_type=1, gift_flag=0, status=20, display_flag=3

SALES_DATA: Dict[str, Dict] = {
    "PR000021": {"name": "Iced Coconut Latte", "qty": 70044, "avg_list": 6.47, "avg_paid": 3.28, "total_rev": 229547},
    "PR000005": {"name": "Drip Coffee", "qty": 40813, "avg_list": 3.45, "avg_paid": 2.46, "total_rev": 100318},
    "PR000071": {"name": "Iced Kyoto Matcha Latte", "qty": 37263, "avg_list": 6.47, "avg_paid": 3.47, "total_rev": 129208},
    "PR000016": {"name": "Latte (Hot)", "qty": 28483, "avg_list": 5.76, "avg_paid": 3.26, "total_rev": 92968},
    "PR000023": {"name": "Iced Velvet Latte", "qty": 25526, "avg_list": 6.49, "avg_paid": 3.52, "total_rev": 89764},
    "PR000015": {"name": "Iced Latte", "qty": 23546, "avg_list": 5.78, "avg_paid": 3.43, "total_rev": 80866},
    "PR000031": {"name": "Cold Brew", "qty": 19431, "avg_list": 4.96, "avg_paid": 3.13, "total_rev": 60863},
    "PR000022": {"name": "Coconut Latte (Hot)", "qty": 18738, "avg_list": 6.46, "avg_paid": 3.30, "total_rev": 61826},
    "PR000073": {"name": "Iced Kyoto Matcha Coconut", "qty": 18208, "avg_list": 6.78, "avg_paid": 3.54, "total_rev": 64433},
    "PR000072": {"name": "Kyoto Matcha Latte (Hot)", "qty": 14892, "avg_list": 6.45, "avg_paid": 3.38, "total_rev": 50321},
    "PR000080": {"name": "Iced Caramel Popcorn Latte", "qty": 13682, "avg_list": 6.79, "avg_paid": 3.71, "total_rev": 50807},
    "PR000063": {"name": "Sausage Egg Cheese Croissant", "qty": 11790, "avg_list": 5.72, "avg_paid": 4.98, "total_rev": 58718},
    "PR000018": {"name": "Cappuccino (Hot)", "qty": 10779, "avg_list": 5.75, "avg_paid": 3.34, "total_rev": 36040},
    "PR000024": {"name": "Velvet Latte (Hot)", "qty": 10714, "avg_list": 6.48, "avg_paid": 3.59, "total_rev": 38503},
    "PR000014": {"name": "Americano (Hot)", "qty": 10612, "avg_list": 4.46, "avg_paid": 2.84, "total_rev": 30180},
    "PR000006": {"name": "Iced Americano", "qty": 10233, "avg_list": 4.47, "avg_paid": 2.91, "total_rev": 29828},
    "PR000033": {"name": "Pineapple Cold Brew", "qty": 10027, "avg_list": 6.25, "avg_paid": 3.11, "total_rev": 31186},
    "PR000039": {"name": "Vital Kale", "qty": 9865, "avg_list": 7.97, "avg_paid": 3.53, "total_rev": 34813},
    "PR000087": {"name": "Spanish Latte (Hot)", "qty": 8985, "avg_list": 6.76, "avg_paid": 3.47, "total_rev": 31191},
    "PR000091": {"name": "Toffee Hazelnut Latte (Hot)", "qty": 8714, "avg_list": 6.96, "avg_paid": 3.36, "total_rev": 29279},
    "PR000043": {"name": "Mango Coconut Sunrise", "qty": 8412, "avg_list": 6.25, "avg_paid": 3.09, "total_rev": 25960},
    "PR000074": {"name": "Kyoto Matcha Coconut (Hot)", "qty": 7860, "avg_list": 6.78, "avg_paid": 3.42, "total_rev": 26881},
    "PR000090": {"name": "Iced Toffee Hazelnut Latte", "qty": 7604, "avg_list": 6.96, "avg_paid": 3.39, "total_rev": 25786},
    "PR000027": {"name": "Iced Matcha Latte", "qty": 6941, "avg_list": 6.45, "avg_paid": 3.12, "total_rev": 21666},
    "PR000030": {"name": "Iced Matcha Coconut Latte", "qty": 6756, "avg_list": 6.45, "avg_paid": 3.17, "total_rev": 21431},
    "PR000108": {"name": "Iced Pistachio Matcha Coconut", "qty": 6350, "avg_list": 6.76, "avg_paid": 3.42, "total_rev": 21717},
    "PR000086": {"name": "Iced Spanish Latte", "qty": 6238, "avg_list": 6.76, "avg_paid": 3.42, "total_rev": 21326},
    "PR000088": {"name": "Iced Creme Brulee Latte", "qty": 5987, "avg_list": 6.96, "avg_paid": 3.48, "total_rev": 20838},
    "PR000081": {"name": "Caramel Popcorn Latte (Hot)", "qty": 5641, "avg_list": 6.79, "avg_paid": 3.68, "total_rev": 20759},
    "PR000089": {"name": "Creme Brulee Latte (Hot)", "qty": 5502, "avg_list": 6.96, "avg_paid": 3.41, "total_rev": 18771},
    "PR000032": {"name": "Blood Orange Cold Brew", "qty": 5436, "avg_list": 6.25, "avg_paid": 3.08, "total_rev": 16737},
    "PR000034": {"name": "Raspberry Cold Brew", "qty": 5153, "avg_list": 6.25, "avg_paid": 3.06, "total_rev": 15760},
    "PR000109": {"name": "Pistachio Matcha Coconut (Hot)", "qty": 4892, "avg_list": 6.76, "avg_paid": 3.38, "total_rev": 16530},
    "PR000041": {"name": "Strawberry Refresher", "qty": 4756, "avg_list": 6.25, "avg_paid": 3.15, "total_rev": 14985},
    "PR000076": {"name": "Almond Croissant", "qty": 4532, "avg_list": 4.95, "avg_paid": 4.32, "total_rev": 19578},
    "PR000042": {"name": "Pineapple Refresher", "qty": 4298, "avg_list": 6.25, "avg_paid": 3.12, "total_rev": 13402},
    "PR000036": {"name": "Green Cold Brew", "qty": 4156, "avg_list": 5.47, "avg_paid": 3.18, "total_rev": 13206},
    "PR000077": {"name": "Chocolate Croissant", "qty": 3987, "avg_list": 4.95, "avg_paid": 4.28, "total_rev": 17064},
    "PR000045": {"name": "Iced Coconut Velvet Latte", "qty": 3876, "avg_list": 6.49, "avg_paid": 3.48, "total_rev": 13488},
    "PR000083": {"name": "Iced Pumpkin Spice Latte", "qty": 3654, "avg_list": 6.76, "avg_paid": 3.35, "total_rev": 12247},
    "PR000051": {"name": "Dreamy Strawberry", "qty": 3521, "avg_list": 6.47, "avg_paid": 3.22, "total_rev": 11327},
    "PR000084": {"name": "Pumpkin Spice Latte (Hot)", "qty": 3412, "avg_list": 6.76, "avg_paid": 3.38, "total_rev": 11535},
    "PR000044": {"name": "Grapefruit Mango Drink", "qty": 3287, "avg_list": 6.25, "avg_paid": 3.08, "total_rev": 10124},
    "PR000047": {"name": "Coconut Velvet Latte (Hot)", "qty": 3198, "avg_list": 6.49, "avg_paid": 3.52, "total_rev": 11257},
    "PR000025": {"name": "Iced Chocolate", "qty": 3156, "avg_list": 5.97, "avg_paid": 3.18, "total_rev": 10026},
    "PR000050": {"name": "Mango Pomelo Sago", "qty": 3089, "avg_list": 6.47, "avg_paid": 3.15, "total_rev": 9730},
    "PR000048": {"name": "Smoothie", "qty": 2876, "avg_list": 6.47, "avg_paid": 3.25, "total_rev": 9347},
    "PR000075": {"name": "Kyoto Matcha Smoothie", "qty": 2654, "avg_list": 6.78, "avg_paid": 3.48, "total_rev": 9236},
    "PR000070": {"name": "Iced Matcha Coconut Water", "qty": 2543, "avg_list": 6.47, "avg_paid": 3.22, "total_rev": 8189},
    "PR000078": {"name": "Double Chocolate Muffin", "qty": 2432, "avg_list": 3.95, "avg_paid": 3.45, "total_rev": 8390},
    "PR000026": {"name": "Hot Chocolate", "qty": 2398, "avg_list": 5.97, "avg_paid": 3.22, "total_rev": 7721},
    "PR000079": {"name": "Chocolate Chip Cookies", "qty": 2187, "avg_list": 3.45, "avg_paid": 2.98, "total_rev": 6517},
    "PR000068": {"name": "Zen Berry", "qty": 2134, "avg_list": 7.97, "avg_paid": 3.48, "total_rev": 7426},
    "PR000069": {"name": "Sunny Citrus", "qty": 1987, "avg_list": 7.97, "avg_paid": 3.45, "total_rev": 6855},
    "PR000110": {"name": "Iced Pistachio Oat Latte", "qty": 1876, "avg_list": 7.46, "avg_paid": 3.52, "total_rev": 6603},
    "PR000111": {"name": "Pistachio Oat Latte (Hot)", "qty": 1654, "avg_list": 7.46, "avg_paid": 3.48, "total_rev": 5756},
    "PR000017": {"name": "Iced Latte (variant)", "qty": 1823, "avg_list": 5.78, "avg_paid": 3.38, "total_rev": 6162},
    "PR000020": {"name": "Iced Flat White", "qty": 1611, "avg_list": 5.97, "avg_paid": 3.45, "total_rev": 5558},
}


# =============================================================================
# SECTION 4: Cost Calculation Engine
# =============================================================================

def calculate_cogs(recipe: Recipe) -> tuple:
    """Calculate total COGS for a recipe. Returns (total_cogs, ingredient_costs_detail)."""
    total = 0.0
    details = []
    for goods_code, quantity in recipe.ingredients:
        if goods_code in UNIT_PRICES:
            unit_info = UNIT_PRICES[goods_code]
            cost = quantity * unit_info["price_per_unit"]
            total += cost
            details.append({
                "code": goods_code,
                "name": unit_info["name"],
                "qty": quantity,
                "unit": unit_info["unit"],
                "unit_price": unit_info["price_per_unit"],
                "line_cost": round(cost, 4),
            })
        else:
            # Unknown ingredient — flag it
            details.append({
                "code": goods_code,
                "name": "UNKNOWN",
                "qty": quantity,
                "unit": "?",
                "unit_price": 0,
                "line_cost": 0,
            })
    return round(total, 2), details


def classify_menu_item(popularity_pct: float, cm_pct: float,
                       pop_threshold: float, cm_threshold: float) -> str:
    """BCG/Kasavana-Smith classification."""
    if popularity_pct >= pop_threshold and cm_pct >= cm_threshold:
        return "Star"
    elif popularity_pct >= pop_threshold and cm_pct < cm_threshold:
        return "Plow Horse"
    elif popularity_pct < pop_threshold and cm_pct >= cm_threshold:
        return "Puzzle"
    else:
        return "Dog"


def main():
    output_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    data_dir = os.path.join(output_dir, "data")
    os.makedirs(data_dir, exist_ok=True)

    # --- Step 1: Calculate COGS per recipe ---
    results = []
    for recipe in RECIPES:
        cogs, details = calculate_cogs(recipe)
        sales = SALES_DATA.get(recipe.spu_code)
        if sales:
            avg_paid = sales["avg_paid"]
            avg_list = sales["avg_list"]
            qty = sales["qty"]
            total_rev = sales["total_rev"]
            cm_dollar = round(avg_paid - cogs, 2)  # Contribution margin per unit
            cm_pct = round((cm_dollar / avg_paid) * 100, 1) if avg_paid > 0 else 0
            discount_depth = round((1 - avg_paid / avg_list) * 100, 1) if avg_list > 0 else 0
            cogs_pct = round((cogs / avg_paid) * 100, 1) if avg_paid > 0 else 0
            total_cm = round(cm_dollar * qty, 2)
        else:
            avg_paid = avg_list = qty = total_rev = 0
            cm_dollar = cm_pct = discount_depth = cogs_pct = total_cm = 0

        results.append({
            "spu_code": recipe.spu_code,
            "product_name": recipe.product_name,
            "category": recipe.category,
            "size": recipe.size,
            "cogs": cogs,
            "avg_list_price": avg_list,
            "avg_paid_price": avg_paid,
            "cm_dollar": cm_dollar,
            "cm_pct": cm_pct,
            "cogs_pct": cogs_pct,
            "discount_depth": discount_depth,
            "qty_sold": qty,
            "total_revenue": total_rev,
            "total_cm": total_cm,
            "ingredient_count": len(details),
            "details": details,
        })

    # --- Step 2: Calculate popularity metrics ---
    total_qty = sum(r["qty_sold"] for r in results if r["qty_sold"] > 0)
    n_items = sum(1 for r in results if r["qty_sold"] > 0)

    for r in results:
        if total_qty > 0 and r["qty_sold"] > 0:
            r["sales_mix_pct"] = round((r["qty_sold"] / total_qty) * 100, 2)
        else:
            r["sales_mix_pct"] = 0

    # Kasavana-Smith threshold: 1/N * 70% (industry standard)
    pop_threshold = (100.0 / n_items) * 0.70 if n_items > 0 else 0
    avg_cm_pct = (sum(r["cm_pct"] for r in results if r["qty_sold"] > 0) / n_items) if n_items > 0 else 0
    weighted_avg_cm = (
        sum(r["cm_dollar"] * r["qty_sold"] for r in results if r["qty_sold"] > 0) / total_qty
    ) if total_qty > 0 else 0

    # --- Step 3: Classify each item ---
    for r in results:
        if r["qty_sold"] > 0:
            r["classification"] = classify_menu_item(
                r["sales_mix_pct"], r["cm_pct"],
                pop_threshold, avg_cm_pct
            )
        else:
            r["classification"] = "N/A"

    # --- Step 4: Write CSV output ---
    csv_path = os.path.join(data_dir, "cost_model_output.csv")
    fieldnames = [
        "spu_code", "product_name", "category", "size",
        "cogs", "avg_list_price", "avg_paid_price",
        "cm_dollar", "cm_pct", "cogs_pct", "discount_depth",
        "qty_sold", "sales_mix_pct", "total_revenue", "total_cm",
        "classification", "ingredient_count",
    ]

    with open(csv_path, "w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        for r in sorted(results, key=lambda x: x["qty_sold"], reverse=True):
            row = {k: r[k] for k in fieldnames}
            writer.writerow(row)

    # --- Step 5: Write detailed ingredient breakdown ---
    detail_path = os.path.join(data_dir, "ingredient_cost_detail.csv")
    with open(detail_path, "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["spu_code", "product_name", "ingredient_code", "ingredient_name",
                         "quantity", "unit", "unit_price", "line_cost"])
        for r in sorted(results, key=lambda x: x["qty_sold"], reverse=True):
            for d in r["details"]:
                writer.writerow([
                    r["spu_code"], r["product_name"],
                    d["code"], d["name"], d["qty"], d["unit"],
                    d["unit_price"], d["line_cost"],
                ])

    # --- Step 6: Print summary ---
    print("=" * 80)
    print("UC-PR-01: Menu Engineering Cost Model — Phase 2 Results")
    print("=" * 80)
    print(f"\nTotal SKUs modeled: {len(results)}")
    print(f"SKUs with sales data: {n_items}")
    print(f"Total units sold: {total_qty:,}")
    print(f"Total revenue: ${sum(r['total_revenue'] for r in results):,.0f}")
    print(f"\nPopularity threshold (70% rule): {pop_threshold:.2f}%")
    print(f"Average CM%: {avg_cm_pct:.1f}%")
    print(f"Weighted average CM$/unit: ${weighted_avg_cm:.2f}")

    # Classification counts
    classes = {}
    for r in results:
        c = r["classification"]
        if c != "N/A":
            classes[c] = classes.get(c, 0) + 1
    print(f"\nClassifications:")
    for c in ["Star", "Plow Horse", "Puzzle", "Dog"]:
        print(f"  {c}: {classes.get(c, 0)} items")

    # Top 10 by total contribution margin
    print(f"\nTop 10 by Total Contribution Margin:")
    print(f"{'SPU':<12} {'Product':<35} {'COGS':>6} {'CM$':>6} {'CM%':>6} {'Qty':>8} {'Total CM':>10} {'Class':<10}")
    print("-" * 100)
    for r in sorted(results, key=lambda x: x["total_cm"], reverse=True)[:10]:
        print(f"{r['spu_code']:<12} {r['product_name']:<35} ${r['cogs']:>5.2f} ${r['cm_dollar']:>5.2f} {r['cm_pct']:>5.1f}% {r['qty_sold']:>7,} ${r['total_cm']:>9,.0f} {r['classification']:<10}")

    # Bottom 5 by CM%
    active = [r for r in results if r["qty_sold"] > 0]
    print(f"\nBottom 5 by CM% (lowest margin):")
    print(f"{'SPU':<12} {'Product':<35} {'COGS':>6} {'CM$':>6} {'CM%':>6} {'Qty':>8} {'Class':<10}")
    print("-" * 90)
    for r in sorted(active, key=lambda x: x["cm_pct"])[:5]:
        print(f"{r['spu_code']:<12} {r['product_name']:<35} ${r['cogs']:>5.2f} ${r['cm_dollar']:>5.2f} {r['cm_pct']:>5.1f}% {r['qty_sold']:>7,} {r['classification']:<10}")

    print(f"\nOutput files:")
    print(f"  {csv_path}")
    print(f"  {detail_path}")
    print("=" * 80)


if __name__ == "__main__":
    main()
