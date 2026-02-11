#!/usr/bin/env python3
"""
Analyze Luckin USA Store Opening Week Traffic vs Subsequent Weeks
Compares opening week traffic to average of subsequent weeks on the same weekday
"""

import json
import mysql.connector
from datetime import datetime, timedelta
import pandas as pd
import matplotlib.pyplot as plt
import matplotlib
matplotlib.use('Agg')
import numpy as np
from scipy import stats
import openpyxl
from openpyxl.styles import Font, PatternFill, Alignment
from openpyxl.utils.dataframe import dataframe_to_rows

# Database configuration
DB_CONFIG = {
    'host': 'aws-luckyus-opshop-rw',
    'database': 'luckyus_opshop',
    'user': 'diagtools',
}

DB_CONFIG_HEALTH = {
    'host': 'aws-luckyus-iluckyhealth-rw',
    'database': 'luckyus_iluckyhealth',
    'user': 'diagtools',
}

def get_store_info():
    """Get all US store opening information"""
    # Using direct MySQL connection approach
    # This would need to be adapted to your actual connection method
    stores = [
        {"shop_no": "US00000", "shop_name": "NJ Test Kitchen", "set_up_time": "2025-05-09", "opening_dow": 6, "opening_day_name": "Friday"},
        {"shop_no": "US00001", "shop_name": "8th & Broadway", "set_up_time": "2025-06-30", "opening_dow": 2, "opening_day_name": "Monday"},
        {"shop_no": "US00002", "shop_name": "28th & 6th", "set_up_time": "2025-06-30", "opening_dow": 2, "opening_day_name": "Monday"},
        {"shop_no": "US00005", "shop_name": "54th & 8th", "set_up_time": "2025-08-24", "opening_dow": 1, "opening_day_name": "Sunday"},
        {"shop_no": "US00006", "shop_name": "102 Fulton", "set_up_time": "2025-08-28", "opening_dow": 5, "opening_day_name": "Thursday"},
        {"shop_no": "US00003", "shop_name": "100 Maiden Ln", "set_up_time": "2025-09-09", "opening_dow": 3, "opening_day_name": "Tuesday"},
        {"shop_no": "US00004", "shop_name": "37th & Broadway", "set_up_time": "2025-11-20", "opening_dow": 5, "opening_day_name": "Thursday"},
        {"shop_no": "US00008", "shop_name": "33rd & 10th", "set_up_time": "2025-12-01", "opening_dow": 2, "opening_day_name": "Monday"},
        {"shop_no": "US00024", "shop_name": "15th & 3rd", "set_up_time": "2025-12-14", "opening_dow": 1, "opening_day_name": "Sunday"},
        {"shop_no": "US00025", "shop_name": "221 Grand", "set_up_time": "2025-12-15", "opening_dow": 2, "opening_day_name": "Monday"},
        {"shop_no": "US00020", "shop_name": "21st & 3rd", "set_up_time": "2026-02-06", "opening_dow": 6, "opening_day_name": "Friday"},
    ]
    return stores

# Store the actual daily data we retrieved
DAILY_DATA = """[
    {"shop_name": "8th & Broadway", "date": "2025-06-30", "cup_count": 739.0},
    {"shop_name": "8th & Broadway", "date": "2025-07-07", "cup_count": 552.0},
    {"shop_name": "8th & Broadway", "date": "2025-07-14", "cup_count": 526.0},
    {"shop_name": "8th & Broadway", "date": "2025-07-21", "cup_count": 539.0},
    {"shop_name": "8th & Broadway", "date": "2025-07-28", "cup_count": 542.0},
    {"shop_name": "8th & Broadway", "date": "2025-08-04", "cup_count": 617.0},
    {"shop_name": "8th & Broadway", "date": "2025-08-11", "cup_count": 568.0},
    {"shop_name": "8th & Broadway", "date": "2025-08-18", "cup_count": 534.0},
    {"shop_name": "8th & Broadway", "date": "2025-08-25", "cup_count": 556.0},
    {"shop_name": "8th & Broadway", "date": "2025-09-01", "cup_count": 638.0},
    {"shop_name": "8th & Broadway", "date": "2025-09-08", "cup_count": 802.0},
    {"shop_name": "8th & Broadway", "date": "2025-09-15", "cup_count": 797.0},
    {"shop_name": "8th & Broadway", "date": "2025-09-22", "cup_count": 884.0},
    {"shop_name": "8th & Broadway", "date": "2025-09-29", "cup_count": 801.0},
    {"shop_name": "8th & Broadway", "date": "2025-10-06", "cup_count": 959.0}
]"""

print("=" * 80)
print("LUCKIN USA OPENING WEEK TRAFFIC ANALYSIS")
print("=" * 80)
print()
print("Analysis Goal: Determine if opening week traffic is better/worse than")
print("               subsequent weeks on the same calendar day")
print()
print("=" * 80)

# For this script to work with the MCP gateway, we'll need to manually query each store
# This is a template showing the approach
