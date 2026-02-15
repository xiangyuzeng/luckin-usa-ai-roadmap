# UC-SC-01 Operational Guide / 运维指南

## 1. Daily Pipeline Operations / 日常管道运维

### 1.1 Pipeline Schedule / 管道时间表
- Pipeline runs daily at **06:00 EST (11:00 UTC)** via MySQL EVENT `test.evt_daily_forecast_accuracy`
- Processes data for T-1 (yesterday's predictions vs actuals)
- Expected duration: 15-25 minutes
- Pipeline stored procedure: `test.sp_refresh_forecast_accuracy(IN p_calc_date DATE)`

### 1.2 Pipeline Steps / 管道步骤
| Step | Name | Server | Duration | Description EN | Description CN |
|------|------|--------|----------|----------------|----------------|
| 1 | VALIDATE_STAGING | dbatest | ~1s | Verify staging tables have data | 验证暂存表有数据 |
| 2 | IDEMPOTENT_DELETE | dbatest | ~2s | Remove existing rows for calc_date | 删除计算日期的现有行 |
| 3 | COMPUTE_DAILY_ACCURACY | dbatest | ~5min | Join predictions & actuals, compute metrics | 关联预测与实际，计算指标 |
| 4 | RECOMPUTE_AGGREGATES | dbatest | ~8min | Build summary tables (daily/rolling) | 构建汇总表（日/滚动） |
| 5 | DRIFT_DETECTION | dbatest | ~2min | Run alert rules (CRITICAL/WARNING/DRIFT) | 运行告警规则 |
| 6 | CLEANUP_STAGING | dbatest | ~1s | Drop tmp_predictions, tmp_actuals | 删除临时表 |
| 7 | FINALIZE | dbatest | ~1s | Update pipeline run log with status | 更新管道运行日志 |

### 1.3 Manual Execution / 手动执行
```sql
-- Standard daily run (yesterday's data)
CALL test.sp_refresh_forecast_accuracy(CURDATE() - INTERVAL 1 DAY);

-- Specific date backfill
CALL test.sp_refresh_forecast_accuracy('2026-02-10');

-- Check pipeline status
SELECT run_id, data_date, status, error_message,
       TIMESTAMPDIFF(SECOND, run_start_time, run_end_time) AS duration_sec
FROM test.forecast_pipeline_run_log
WHERE pipeline_name = 'forecast_accuracy'
ORDER BY run_start_time DESC LIMIT 10;
```

### 1.4 Pre-Pipeline Data Load / 管道前数据加载
Before running the stored procedure, staging tables must be populated:

```sql
-- Step 1: Extract predictions (run on aws-luckyus-ireplenishment-rw)
-- See sql/03_accuracy_computation.sql Step 1

-- Step 2: Extract actuals (run on aws-luckyus-scm-shopstock-rw)
-- See sql/03_accuracy_computation.sql Step 2
-- KEY: reason_code IN ('025','1001','1002') AND total_adjust_num < 0

-- Step 3: Load staging tables on dbatest
-- See sql/03_accuracy_computation.sql Step 3
```

## 2. Monitoring & Health Checks / 监控与健康检查

### 2.1 Pipeline Health / 管道健康
Check daily via Grafana dashboard (UID: `uc-sc-01-forecast-accuracy`, panel "Pipeline Status"):

| Check | Query | Expected | Action if Failed |
|-------|-------|----------|------------------|
| Last run status | `SELECT status FROM forecast_pipeline_run_log ORDER BY run_start_time DESC LIMIT 1` | 'SUCCESS' | Check error_message, re-run manually |
| Run duration | `TIMESTAMPDIFF(SECOND, run_start_time, run_end_time)` | < 1800s | Investigate slow steps in run_log |
| Data freshness | `SELECT MAX(dt) FROM forecast_accuracy_daily` | Yesterday | Check if pipeline ran; check staging data |
| Row count | `SELECT COUNT(*) FROM forecast_accuracy_daily WHERE dt = CURDATE()-1` | 500-1500 | If 0: pipeline didn't run. If <200: check source data |

### 2.2 Forecast Alert Review / 预测告警审查
```sql
-- Active unacknowledged alerts
SELECT alert_type, severity, entity_type, entity_id,
       metric_value, threshold_value, description, created_at
FROM test.forecast_alerts
WHERE acknowledged = 0
ORDER BY FIELD(severity, 'CRITICAL', 'WARNING', 'INFO'), created_at DESC;

-- Acknowledge an alert
UPDATE test.forecast_alerts
SET acknowledged = 1, acknowledged_by = 'your_name', acknowledged_at = NOW()
WHERE id = <alert_id>;
```

### 2.3 Escalation Matrix / 升级矩阵
| Alert Type | Severity | Response Time | Notification | Owner |
|------------|----------|---------------|--------------|-------|
| CRITICAL | P1 | 30 minutes | Slack + Email | On-call engineer |
| WARNING | P2 | 4 hours | Slack | Data team |
| BIAS | P2 | Next business day | Dashboard | Data scientist |
| COVERAGE | P2 | 4 hours | Slack | Data engineer |
| DRIFT | P3 | Next business day | Dashboard | Data scientist |

## 3. Troubleshooting / 故障排除

### 3.1 Pipeline Failures / 管道故障

**Symptom: Pipeline status = 'FAILED'**
1. Check error message: `SELECT error_message FROM forecast_pipeline_run_log WHERE status = 'FAILED' ORDER BY run_start_time DESC LIMIT 1`
2. Check which step failed: `SELECT step_name, status, error_message FROM forecast_pipeline_run_log WHERE run_id = '<run_id>'`
3. Common causes:
   - VALIDATE_STAGING failed -- Staging tables empty -- Re-run extract steps on source servers
   - COMPUTE_DAILY_ACCURACY failed -- Join key mismatch -- Verify goods_code/goods_mid format
   - RECOMPUTE_AGGREGATES timeout -- Large data volume -- Check if date range is too wide

**Symptom: Pipeline ran but 0 rows inserted**
1. Check staging table counts
2. Verify source data exists for the calc_date
3. Check if all stores were operational
4. Verify reason_code filter: `reason_code IN ('025','1001','1002') AND total_adjust_num < 0`

### 3.2 High MAPE (>40%) / 高MAPE
1. Check if it's a specific store: `SELECT shop_dept_id, AVG(absolute_pct_error) FROM forecast_accuracy_daily WHERE dt = '<date>' GROUP BY shop_dept_id`
2. Check if it's specific products: look for products with very low actual consumption (near zero)
3. Verify the prediction version is latest: `task_version_id` deduplication working correctly
4. Check for data quality issues: late-arriving actuals, missing stock change records

### 3.3 Persistent Bias / 持续偏差
1. If positive bias (over-prediction): prediction model may need recalibration for demand reduction
2. If negative bias (under-prediction): check if new products or promotions are driving demand above forecast
3. Review by category: `SELECT large_class_name, AVG(forecast_error) FROM forecast_accuracy_daily GROUP BY large_class_name`

## 4. Database Servers / 数据库服务器

| Alias | Role | Schema | Access |
|-------|------|--------|--------|
| aws-luckyus-ireplenishment-rw | Predictions source | luckyus_ireplenishment | Read-only |
| aws-luckyus-scm-shopstock-rw | Actuals source | luckyus_scm_shopstock | Read-only |
| aws-luckyus-dbatest-rw | Analytics target | test | Read-write |
| aws-luckyus-ldas01-rw | Grafana datasource | (cross-schema) | Read-only (Grafana) |

## 5. Store Reference / 门店参考

### Active Stores / 活跃门店
| Store ID | Name | Location | Status |
|----------|------|----------|--------|
| 1127 | 221 Grand St | New York, NY | Active |
| 1128 | 8th & Broadway | New York, NY | Active |
| 1140 | 28th & 6th Ave | New York, NY | Active |
| 1141 | 15th & 3rd Ave | New York, NY | Active |
| 20008 | 37th & Broadway | New York, NY | Active |
| 20010 | 21st & 3rd Ave | New York, NY | Active |
| 20011 | Flushing Main St | Queens, NY | Active |
| 20027 | Court & Montague | Brooklyn, NY | Active |
| 20031 | 47th & 6th Ave | New York, NY | Active |
| 20032 | 23rd & 5th Ave | New York, NY | Active |

### Excluded Stores / 排除门店
| Store ID | Name | Reason |
|----------|------|--------|
| 1131 | NJ Test Kitchen | Test environment |
| 20007 | NJ Test Kitchen 2 | Test environment |
| 20046 | Shanghai Test Kitchen | Non-US |

## 6. Key Contacts / 关键联系人

| Role | Responsibility |
|------|----------------|
| Data Engineering | Pipeline operations, ETL issues, staging data |
| Data Science | Model accuracy, bias analysis, algorithm tuning |
| DBA | DDL execution, server access, performance tuning |
| Supply Chain Ops | Business impact assessment, store-level issues |

## 7. Maintenance Tasks / 维护任务

### Weekly
- Review and acknowledge forecast alerts
- Check pipeline run log for any failed runs in the past week
- Review 7-day rolling MAPE trends by store

### Monthly
- Archive old pipeline run logs (>90 days)
- Review alert thresholds -- adjust if baseline accuracy improves
- Generate monthly accuracy report from summary table
- Clean up acknowledged alerts older than 30 days

### Quarterly
- Review consumption formula validity (reason code distribution may shift)
- Assess if new stores need to be added or excluded
- Review Grafana dashboard panels for relevance
- Update data dictionary if schema changes occur

## 8. Grafana Dashboard Reference / Grafana仪表板参考

- **Dashboard UID**: `uc-sc-01-forecast-accuracy`
- **Dashboard ID**: 29
- **Folder**: AI Analytics (UID: `cfd9mzwx2zp4wc`)
- **Datasource**: MySQL-Ldas (UID: `ef5ay9lchfg1sa`, server: `aws-luckyus-ldas01-rw`)
- **Panels**: KPI summary, MAPE trend, store comparison, category breakdown, alert feed, pipeline status

---
*UC-SC-01 Operational Guide -- Luckin Coffee USA Supply Chain Intelligence*
*Last updated: 2026-02-15*
