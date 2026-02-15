# Operational Guide / 运维指南
## UC-OP-02: Store Performance Anomaly Detection / 门店绩效异常检测

---

## 1. System Overview / 系统概述

The Store Performance Anomaly Detection system monitors 10 Luckin Coffee USA stores daily using Statistical Process Control (SPC). It extracts data from 6 source databases, computes Z-scores and Western Electric rule violations, generates composite health scores, and triggers tiered alerts.

门店绩效异常检测系统使用统计过程控制(SPC)方法每日监控10家瑞幸咖啡美国门店。系统从6个源数据库提取数据，计算Z分数和西部电气规则违规，生成综合健康评分，并触发分级告警。

### Architecture / 架构

```
┌──────────────────────────────────────────────────┐
│               Source Databases (6)                │
├──────────┬──────────┬──────────┬────────┬────────┤
│  opshop  │salesorder│production│quality │empeff  │
│ (stores) │(revenue) │ (ops)    │(checks)│(staff) │
└────┬─────┴────┬─────┴────┬─────┴───┬────┴───┬────┘
     │          │          │         │        │
     └──────────┴──────────┴────┬────┴────────┘
                                │
                    ┌───────────▼───────────┐
                    │  Python Orchestrator   │
                    │  run_pipeline.py       │
                    │  (12 steps, daily)     │
                    └───────────┬───────────┘
                                │
                    ┌───────────▼───────────┐
                    │  Analytics Tables (5)  │
                    │  test schema @ dbatest │
                    ├───────────────────────┤
                    │ store_kpi_daily        │
                    │ store_anomaly_scores   │
                    │ store_health_scores    │
                    │ store_anomaly_alerts   │
                    │ store_anomaly_pipeline │
                    └───────────┬───────────┘
                                │
                    ┌───────────▼───────────┐
                    │  Grafana Dashboards    │
                    │  http://10.238.3.43    │
                    └───────────────────────┘
```

### Data Flow / 数据流

| Step | Source | Target | Description |
|------|--------|--------|-------------|
| 1 | opshop | memory | Load store master list |
| 2 | salesorder | store_kpi_daily | Revenue, orders, AOV |
| 3 | opproduction | store_kpi_daily | Production count, time |
| 4 | opempefficiency | store_kpi_daily | Scheduled hours, headcount |
| 5 | opqualitycontrol | store_kpi_daily | Inspection scores |
| 6 | store_kpi_daily | store_kpi_daily | Derived metrics |
| 7 | store_kpi_daily | store_anomaly_scores | Z-scores, control limits |
| 8 | store_anomaly_scores | store_anomaly_scores | WE rules evaluation |
| 9 | store_kpi_daily | store_health_scores | Composite health scores |
| 10 | scores + health | store_anomaly_alerts | Alert generation |
| 11 | — | pipeline_log | Execution logging |
| 12 | all tables | — | Verification |

---

## 2. Prerequisites / 前提条件

### Software
- Python 3.8+ with pip
- PyMySQL 1.1.0
- python-dotenv 1.0.1

### Database Access
Credentials required for 6 MySQL servers:

| Server | Schema | Access Level |
|--------|--------|-------------|
| aws-luckyus-opshop-rw | luckyus_opshop | READ |
| aws-luckyus-salesorder-rw | luckyus_sales_order | READ |
| aws-luckyus-opproduction-rw | luckyus_opproduction | READ |
| aws-luckyus-opqualitycontrol-rw | luckyus_opqualitycontrol | READ |
| aws-luckyus-opempefficiency-rw | luckyus_opempefficiency | READ |
| aws-luckyus-dbatest-rw | test | READ/WRITE |

### Infrastructure
- MySQL EVENT scheduler enabled on dbatest (for automated daily runs)
- Grafana instance at http://10.238.3.43:3000 (for dashboards)
- Network access from orchestrator host to all 6 database servers

---

## 3. Installation / 安装

```bash
# 1. Navigate to orchestrator directory
cd /app/UC-OP-02-store-anomaly/orchestrator

# 2. Create environment file from template
cp .env.example .env

# 3. Edit .env with actual database credentials
vi .env

# 4. Install Python dependencies
pip install -r requirements.txt

# 5. Create analytics tables (run DDL on dbatest)
# Execute sql/02_create_analytics_schema.sql on aws-luckyus-dbatest-rw

# 6. Run initial backfill
python run_pipeline.py --backfill-from 2025-07-01 --backfill-to 2026-02-15

# 7. Import Grafana dashboard
# Upload dashboards/store_anomaly_dashboard.json to Grafana
```

---

## 4. Running the Pipeline / 运行管道

### Daily Run (Default)
```bash
# Process today's data (with 3-day lookback for late-arriving records)
python run_pipeline.py
```

### Specific Date
```bash
# Process a specific date
python run_pipeline.py --date 2026-01-15
```

### Backfill Date Range
```bash
# Backfill historical data
python run_pipeline.py --backfill-from 2025-07-01 --backfill-to 2026-01-31
```

### Automated Scheduling
The stored procedure `test.sp_refresh_store_anomaly` runs via MySQL EVENT:
- **Schedule**: Daily at 12:00 UTC (07:00 EST)
- **Runs after**: UC-SC-01 forecast pipeline (06:00 EST)

Alternatively, use cron:
```bash
# crontab entry (07:00 EST = 12:00 UTC)
0 12 * * * cd /app/UC-OP-02-store-anomaly/orchestrator && python run_pipeline.py >> /var/log/uc-op-02.log 2>&1
```

---

## 5. Monitoring / 监控

### Pipeline Execution Log
```sql
-- Check latest pipeline run
SELECT run_id, run_date, step_name, status, rows_affected,
       duration_seconds, error_message
FROM test.store_anomaly_pipeline_log
WHERE run_date = CURDATE()
ORDER BY step_number;

-- Check for failed steps
SELECT * FROM test.store_anomaly_pipeline_log
WHERE status = 'FAILED'
AND run_date >= DATE_SUB(CURDATE(), INTERVAL 7 DAY);
```

### Health Score Dashboard
- **Grafana**: http://10.238.3.43:3000 → "AI Analytics" folder → "Store Anomaly Detection"
- **Dashboard UID**: `uc-op-02-store-anomaly`

### Active Alerts
```sql
-- Current unacknowledged alerts
SELECT store_name, alert_date, severity, metric_name,
       description_en, recommended_action
FROM test.store_anomaly_alerts
WHERE acknowledged = FALSE
ORDER BY
  FIELD(severity, 'CRITICAL', 'WARNING', 'INFO'),
  alert_date DESC;
```

---

## 6. Troubleshooting / 故障排除

### Common Issues

| Issue | Cause | Solution |
|-------|-------|----------|
| Connection timeout | Network/firewall | Check VPC security groups, verify host reachable |
| Empty results for a store | Store opened recently | Need 28+ days of data for SPC; store will be skipped |
| All Z-scores = NULL | Zero standard deviation | Store has constant values (rare); check data quality |
| Missing quality scores | Sparse inspection data | Expected — only 120 records total; quality dimension weighted lower |
| Pipeline step FAILED | SQL error or timeout | Check error_message in pipeline_log; re-run specific date |
| Health score NULL | Missing dimensions | System redistributes weights among available dimensions |

### Debugging Commands
```bash
# Run with debug logging
LOG_LEVEL=DEBUG python run_pipeline.py --date 2026-01-15

# Test database connectivity
python -c "
import pymysql
from dotenv import load_dotenv
import os
load_dotenv()
conn = pymysql.connect(
    host=os.getenv('SALESORDER_HOST'),
    port=int(os.getenv('SALESORDER_PORT', 3306)),
    user=os.getenv('SALESORDER_USER'),
    password=os.getenv('SALESORDER_PASS'),
    database=os.getenv('SALESORDER_DB')
)
print('Connected successfully')
conn.close()
"
```

### Data Freshness Check
```sql
-- Check when each store last had data
SELECT store_id, store_name,
       MAX(metric_date) as latest_date,
       DATEDIFF(CURDATE(), MAX(metric_date)) as days_stale
FROM test.store_kpi_daily
GROUP BY store_id, store_name
ORDER BY latest_date;
```

---

## 7. Maintenance / 维护

### Log Rotation
```sql
-- Purge pipeline logs older than 90 days
DELETE FROM test.store_anomaly_pipeline_log
WHERE run_date < DATE_SUB(CURDATE(), INTERVAL 90 DAY);
```

### Adding New Stores
1. Add the new store's `dept_id` to `ACTIVE_STORES` dict in `run_pipeline.py`
2. Wait 28 days for SPC baseline to build
3. Store will automatically appear in health grid and alert system

### Adjusting SPC Parameters
Edit constants in `run_pipeline.py`:
```python
ROLLING_WINDOW = 28   # Days for rolling statistics (increase for stability)
SIGMA_WARNING = 2     # σ threshold for WARNING alerts
SIGMA_CRITICAL = 3    # σ threshold for CRITICAL alerts
DOW_WEEKS = 8         # Weeks for day-of-week comparison
```

### Rebuilding Historical Scores
```sql
-- Clear and rebuild for a specific store
DELETE FROM test.store_anomaly_scores WHERE store_id = 1127;
DELETE FROM test.store_health_scores WHERE store_id = 1127;
DELETE FROM test.store_anomaly_alerts WHERE store_id = 1127;

-- Then run backfill:
-- python run_pipeline.py --backfill-from 2025-07-01 --backfill-to 2026-02-15
```

### Acknowledging Alerts
```sql
-- Acknowledge a specific alert
UPDATE test.store_anomaly_alerts
SET acknowledged = TRUE,
    acknowledged_by = 'manager_name',
    acknowledged_at = NOW()
WHERE id = <alert_id>;

-- Bulk acknowledge old INFO alerts
UPDATE test.store_anomaly_alerts
SET acknowledged = TRUE, acknowledged_by = 'system_cleanup', acknowledged_at = NOW()
WHERE severity = 'INFO' AND alert_date < DATE_SUB(CURDATE(), INTERVAL 30 DAY)
AND acknowledged = FALSE;
```

---

## 8. Alert Response Protocol / 告警响应协议

### Severity Levels

| Severity | Meaning | Response Time | Action Required |
|----------|---------|--------------|-----------------|
| **CRITICAL** | Z-score beyond 3σ, or WE Rule 1 violation | **Same day** | Investigate immediately. Identify root cause. Escalate to regional manager. |
| **WARNING** | Z-score beyond 2σ, or WE Rules 2-4 | **48 hours** | Review metrics trend. Check for operational issues. Schedule follow-up. |
| **INFO** | Sustained decline trend, WE Rule 5 | **Weekly review** | Monitor during regular dashboard review. Note in weekly report. |

### Investigation Checklist
When a CRITICAL or WARNING alert fires:

1. **Verify data quality** — Is the metric data correct? Check for data gaps or ETL issues.
2. **Check operational factors** — Equipment downtime? Staffing changes? Menu changes?
3. **Review external factors** — Weather events? Local construction? Competitor activity?
4. **Compare with portfolio** — Is this store-specific or affecting multiple locations?
5. **Check cannibalization** — Did a new store open nearby recently?
6. **Document findings** — Record root cause and action taken.
7. **Acknowledge alert** — Mark as acknowledged in the system with notes.

### Escalation Path
```
INFO alerts → Store Manager (weekly review)
WARNING alerts → District Manager (48-hour review)
CRITICAL alerts → Regional VP + Operations Director (same-day action)
```

---

## 9. Database Server Reference / 数据库服务器参考

| Server Name | Schema | Purpose | Data Volume |
|-------------|--------|---------|-------------|
| aws-luckyus-opshop-rw | luckyus_opshop | Store master data | ~20 stores |
| aws-luckyus-salesorder-rw | luckyus_sales_order | Orders & revenue | 520K+ orders |
| aws-luckyus-opproduction-rw | luckyus_opproduction | Production records | 500K+ records |
| aws-luckyus-opqualitycontrol-rw | luckyus_opqualitycontrol | Quality inspections | ~120 records |
| aws-luckyus-opempefficiency-rw | luckyus_opempefficiency | Staffing & scheduling | ~16K records |
| aws-luckyus-dbatest-rw | test | Analytics output | 5 tables |

---

## 10. Related Systems / 相关系统

| System | Schedule | Relationship |
|--------|----------|-------------|
| UC-SC-01 Forecast Accuracy | 06:00 EST daily | Runs before UC-OP-02; shares dbatest server |
| Grafana | Always on | Visualization layer at http://10.238.3.43:3000 |
| MCP DB Gateway | Always on | Used for ad-hoc queries during development |

---

## 11. Contact / 联系方式

- **System Owner**: Data & Analytics Team
- **Grafana Dashboard**: http://10.238.3.43:3000/d/uc-op-02-store-anomaly
- **Source Code**: `/app/UC-OP-02-store-anomaly/`
- **Related**: UC-SC-01 at `/app/UC-SC-01-forecast-accuracy/`
