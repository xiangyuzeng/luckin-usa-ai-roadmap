# UC-SC-01: Demand Forecast Accuracy Monitor / 需求预测准确度监控

## Overview / 概述
Production-grade monitoring system for evaluating the accuracy of Luckin Coffee USA's AI-driven demand forecasting system (iReplenishment). Measures predicted vs actual consumption at the daily SKU-store grain across 10 active US stores.

## Key Facts
- **10 active stores**: 1127, 1128, 1140, 1141, 20008, 20010, 20011, 20027, 20031, 20032
- **3 test stores excluded**: 1131, 20007, 20046
- **~88 GS codes** (raw material SKUs) tracked
- **Daily T+1 cadence** with pipeline at 06:00 EST (11:00 UTC)
- **Prediction source**: `vlt_avg_demand` from `luckyus_ireplenishment.t_order_predict_alg_v2`
- **Actual consumption**: Derived from stock change records using `reason_code IN ('025','1001','1002') AND total_adjust_num < 0`
- **Analytics schema**: `test` database on `aws-luckyus-dbatest-rw`
- **Grafana dashboard**: UID `uc-sc-01-forecast-accuracy` (ID 29) in "AI Analytics" folder

## Project Structure / 项目结构

```
UC-SC-01-forecast-accuracy/
├── README.md                          # This file
├── sql/
│   ├── 01_schema_discovery.sql        # Source table documentation & reason code mapping
│   ├── 02_create_analytics_schema.sql # DDL for 4 analytics tables (run on dbatest)
│   ├── 03_accuracy_computation.sql    # ETL: extract predictions & actuals, compute metrics
│   ├── 04_aggregate_metrics.sql       # Multi-dimensional summary aggregation
│   ├── 05_drift_detection.sql         # 5 alert rules (CRITICAL/WARNING/BIAS/COVERAGE/DRIFT)
│   └── 06_daily_refresh.sql           # Stored procedure + MySQL EVENT for scheduling
├── dashboards/
│   ├── ForecastAccuracyDashboard.jsx  # React executive dashboard (Recharts, dark theme)
│   └── forecast_accuracy_dashboard.json # Grafana dashboard export
├── docs/
│   ├── data_dictionary.md             # Comprehensive bilingual data dictionary
│   └── operational_guide.md           # Operations runbook
└── reports/
    └── historical_accuracy_report.md  # 14-day inaugural accuracy analysis
```

## Architecture / 架构

### Data Sources (Cross-Database)
| Server | Schema | Tables | Purpose |
|--------|--------|--------|---------|
| aws-luckyus-ireplenishment-rw | luckyus_ireplenishment | t_order_predict_alg_v2 | ML predictions |
| aws-luckyus-scm-shopstock-rw | luckyus_scm_shopstock | t_shop_goods_stock_change_record | Stock changes (actuals) |
| aws-luckyus-dbatest-rw | test | forecast_accuracy_daily, forecast_accuracy_summary, forecast_alerts, forecast_pipeline_run_log | Analytics output |

### Consumption Formula (Validated)
```sql
SUM(ABS(total_adjust_num))
WHERE reason_code IN ('025', '1001', '1002')
  AND total_adjust_num < 0
-- reason_code 1002 captures ~97% of physical consumption volume
-- reason_code 019 is EXCLUDED (uses theory_total_adjust_num, values 10-40x too low)
```

### Join Keys
```
predictions.shop_dept_id    = actuals.shop_dept_id     -- Store
predictions.goods_code      = actuals.goods_mid        -- Product (GS codes)
predictions.plan_finish_date = DATE(actuals.operated_time) -- Date
```

## Metrics / 指标
| Metric | Formula | Target | Current |
|--------|---------|--------|---------|
| MAPE | AVG(\|pred - actual\| / actual) | < 25% | 37.8% |
| WMAPE | SUM(\|error\|) / SUM(actual) | < 20% | 30.7% |
| RMSE | SQRT(AVG((pred - actual)²)) | Context-dependent | -- |
| MFE/Bias | AVG(pred - actual) | ~ 0 | +9.1% |
| Accuracy Rate | % within ±20% band | > 70% | 42.3% |
| Tracking Signal | Cumulative error / MAD | \|TS\| < 4.0 | -- |

## Deployment / 部署

### Prerequisites
- MySQL 8.0+ on target analytics server
- Access to all 3 source database servers (read-only)
- Grafana instance with MySQL datasource configured

### Setup Steps / 部署步骤

1. **Create analytics tables** (run by DBA on `aws-luckyus-dbatest-rw`):
   ```bash
   mysql -h aws-luckyus-dbatest-rw -u <user> -p test < sql/02_create_analytics_schema.sql
   ```

2. **Initial data load** (run steps 1-3 from `03_accuracy_computation.sql` on respective servers)

3. **Run aggregation** (`04_aggregate_metrics.sql` on dbatest)

4. **Enable alerts** (`05_drift_detection.sql` on dbatest)

5. **Deploy stored procedure & scheduler** (`06_daily_refresh.sql` on dbatest)

6. **Import Grafana dashboard** (via UI or API using `dashboards/forecast_accuracy_dashboard.json`)

### Important Notes / 重要说明
- SQL files target different database servers — check server comments at the top of each file
- The MCP gateway is READ-ONLY for DDL; SQL files must be executed by a DBA
- Analytics tables use `IF NOT EXISTS` for safe re-execution
- The stored procedure is idempotent (DELETE + INSERT pattern)

## Alert Thresholds / 告警阈值
| Type | Condition | Severity |
|------|-----------|----------|
| CRITICAL | 7-day rolling MAPE > 40% (any store) | P1 |
| WARNING | 7-day rolling MAPE > 30% (any store) | P2 |
| BIAS | Same-sign MFE for 14+ consecutive days | P2 |
| COVERAGE | < 90% of store-product-days matched | P2 |
| DRIFT | Week-over-week MAPE change > 50% (category) | P3 |

## Related Documentation / 相关文档
- [Data Dictionary](docs/data_dictionary.md) — Complete source/target schema reference
- [Operational Guide](docs/operational_guide.md) — Day-to-day operations runbook
- [Historical Accuracy Report](reports/historical_accuracy_report.md) — 14-day inaugural analysis
- [Schema Discovery](sql/01_schema_discovery.sql) — Source table documentation

## Change Log / 变更日志
| Date | Version | Change |
|------|---------|--------|
| 2026-02-15 | 1.0.0 | Initial release — 9-phase implementation complete |

---
*UC-SC-01 Forecast Accuracy Monitor — Luckin Coffee USA Supply Chain Intelligence*
