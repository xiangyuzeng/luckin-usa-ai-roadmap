# Data Dictionary / 数据字典

## UC-OP-02: Store Performance Anomaly Detection / 门店绩效异常检测

> Statistical Process Control (SPC) system for detecting performance anomalies
> across Luckin Coffee USA stores. This document catalogs every source table,
> analytics table, metric definition, and SPC term used in the pipeline.
>
> 统计过程控制 (SPC) 系统，用于检测瑞幸咖啡美国门店的绩效异常。
> 本文档记录管道中使用的所有源表、分析表、指标定义和 SPC 术语。

**Version:** 1.0
**Last Updated:** 2026-02-15
**Author:** Data & Analytics Team

---

## Table of Contents / 目录

1. [Source Tables / 源数据表](#source-tables--源数据表)
2. [Analytics Tables / 分析表](#analytics-tables--分析表)
3. [Store Reference / 门店参考](#store-reference--门店参考)
4. [Metric Definitions / 指标定义](#metric-definitions--指标定义)
5. [SPC Terminology / SPC 术语](#spc-terminology--spc-术语)

---

## Source Tables / 源数据表

Six MySQL database servers provide the raw operational data that feeds the
anomaly detection pipeline. All source connections are **read-only**.

六台 MySQL 数据库服务器提供异常检测管道所需的原始运营数据。所有源连接均为**只读**。

| # | Server | Schema | Primary Table | Purpose |
|---|--------|--------|---------------|---------|
| 1 | aws-luckyus-opshop-rw | luckyus_opshop | t_shop_info | Store master data / 门店主数据 |
| 2 | aws-luckyus-salesorder-rw | luckyus_sales_order | t_order | Sales orders / 销售订单 |
| 3 | aws-luckyus-opproduction-rw | luckyus_opproduction | t_production | Production records / 生产记录 |
| 4 | aws-luckyus-opempefficiency-rw | luckyus_opempefficiency | t_emp_scheduling | Employee scheduling / 员工排班 |
| 5 | aws-luckyus-opqualitycontrol-rw | luckyus_opqualitycontrol | t_shopcheck_report | Quality inspections / 质量检查 |
| 6 | aws-luckyus-dbatest-rw | test | (analytics tables) | Analytics output / 分析输出 |

---

### 1. luckyus_opshop.t_shop_info

**Server:** aws-luckyus-opshop-rw
**Purpose:** Store master data -- the single source of truth for store attributes.
门店主数据 -- 门店属性的唯一权威数据源。

| Column | Type | Description EN | Description CN | Notes |
|--------|------|---------------|---------------|-------|
| dept_id | BIGINT | Primary store identifier (PK) | 主要门店标识（主键） | Referenced as `shop_id` in other databases |
| shop_no | VARCHAR(8) | Store number code (e.g. US00001) | 门店编号（如 US00001） | Format: `US#####` |
| shop_name | VARCHAR(128) | Store display name | 门店显示名称 | |
| status | INT | Store operating status | 门店运营状态 | 1=active/营业, 2=preparing/筹备中, 0=closed/关闭 |
| address | VARCHAR(500) | Street address | 街道地址 | Full US postal address |
| location_longitude | DECIMAL(10,6) | GPS longitude (WGS-84) | GPS 经度 | |
| location_latitude | DECIMAL(10,6) | GPS latitude (WGS-84) | GPS 纬度 | |
| set_up_time | DATETIME | Store opening/establishment date | 开业日期 | Used to filter new-store ramp-up periods |
| create_time | DATETIME | Record creation timestamp | 记录创建时间 | |
| update_time | DATETIME | Record last update timestamp | 记录更新时间 | |

**Key relationships / 关键关联:**
- `dept_id` is the universal store identifier across all source systems.
  `dept_id` 是跨所有源系统的通用门店标识符。
- In other databases, this is referenced as `shop_id` (salesorder, production)
  or `dept_id` (empefficiency, qualitycontrol).

---

### 2. luckyus_sales_order.t_order

**Server:** aws-luckyus-salesorder-rw
**Purpose:** Order-level transactional data including revenue and payment amounts.
订单级交易数据，包括收入和支付金额。

| Column | Type | Description EN | Description CN | Notes |
|--------|------|---------------|---------------|-------|
| id | BIGINT | Order ID (snowflake PK) | 订单ID（雪花算法主键） | Globally unique |
| shop_id | BIGINT | Store ID (= dept_id) | 门店ID（= dept_id） | FK to t_shop_info.dept_id |
| shop_name | VARCHAR(100) | Store name (denormalized) | 门店名称（冗余存储） | |
| order_no | VARCHAR(32) | Human-readable order number | 可读订单编号 | |
| total_money | DECIMAL(12,4) | List price total (USD) | 标价总额（美元） | Before any discounts |
| payable_money | DECIMAL(12,4) | Amount due after discounts (USD) | 折后应付金额（美元） | |
| pay_money | DECIMAL(12,4) | Actual paid amount (USD) | 实付金额（美元） | **Primary revenue field**; in dollars NOT cents |
| status | TINYINT | Order lifecycle status | 订单生命周期状态 | 0=created, 10=pending, 20=paid/completed |
| refund_status | SMALLINT | Refund status | 退款状态 | 0=none, >0=refund initiated |
| create_time | DATETIME | Order creation timestamp | 订单创建时间 | |
| pay_time | DATETIME | Payment timestamp | 支付时间 | |
| finish_time | DATETIME | Order completion timestamp | 订单完成时间 | |
| refund_time | DATETIME | Refund timestamp | 退款时间 | NULL if no refund |

**Important notes / 重要说明:**
- `pay_money` is in **US dollars** (typical values: $3.60, $7.97), NOT cents.
  `pay_money` 单位为**美元**（典型值：$3.60, $7.97），非美分。
- Filter `status >= 20` for completed/paid orders only.
  筛选 `status >= 20` 以仅获取已完成/已支付订单。
- Data range: 2025-03-24 to present (~520K total orders across 10 stores).
  数据范围：2025-03-24 至今（10家门店约52万笔订单）。

---

### 3. luckyus_opproduction.t_production

**Server:** aws-luckyus-opproduction-rw
**Purpose:** Per-order production lifecycle tracking; key for computing production
time (speed-of-service). 单笔订单生产全生命周期跟踪；用于计算生产时间（出品速度）。

| Column | Type | Description EN | Description CN | Notes |
|--------|------|---------------|---------------|-------|
| id | BIGINT | Production record PK | 生产记录主键 | |
| order_id | BIGINT | FK to t_order.id | 关联订单ID | |
| dept_id | BIGINT | Store ID (= dept_id) | 门店ID（= dept_id） | |
| shop_name | VARCHAR(128) | Store name (denormalized) | 门店名称（冗余存储） | |
| order_create_time | DATETIME | When the order was placed | 下单时间 | |
| accept_time | DATETIME | When production started | 接单/开始制作时间 | |
| done_time | DATETIME | When production completed | 完成时间 | |
| product_status | TINYINT | Production lifecycle status | 生产状态 | |
| pay_money | DECIMAL(10,2) | Order payment amount (USD) | 订单支付金额（美元） | |
| total_money | DECIMAL(10,2) | Gross order amount (USD) | 订单总金额（美元） | |

**Derived calculation / 衍生计算:**
```
Production Time (seconds) = TIMESTAMPDIFF(SECOND, accept_time, done_time)
```

**Data profile / 数据概况:**
- ~502K records, 10 active stores, data from 2025-03-24.
  约50.2万条记录，10家活跃门店，起始2025-03-24。
- Filter: `accept_time IS NOT NULL AND done_time IS NOT NULL AND done_time > accept_time`

---

### 4. luckyus_opempefficiency.t_emp_scheduling

**Server:** aws-luckyus-opempefficiency-rw
**Purpose:** Employee scheduling records for computing scheduled labor hours per
store per day. 员工排班记录，用于计算门店每日排班工时。

| Column | Type | Description EN | Description CN | Notes |
|--------|------|---------------|---------------|-------|
| id | BIGINT | Scheduling record PK | 排班记录主键 | |
| emp_no | VARCHAR(20) | Employee number | 员工编号 | Unique per employee |
| dept_id | BIGINT | Employee home department | 员工所属部门 | May differ from scheduling_dept_id (cross-store support) |
| scheduling_dept_id | BIGINT | Department where scheduled to work | 实际排班门店 | Use this for store-level aggregation |
| scheduling_date | DATE | Scheduled work date | 排班日期 | |
| effect_hours | FLOAT(7,2) | Effective scheduled hours | 有效排班工时 | |
| work_type | VARCHAR(4) | Work type / shift code | 班次类型代码 | MORNING, AFTERNOON, EVENING, etc. |

**Related table: t_attendance / 关联表：t_attendance**

| Column | Type | Description EN | Description CN | Notes |
|--------|------|---------------|---------------|-------|
| id | BIGINT | Attendance record PK | 考勤记录主键 | |
| emp_no | VARCHAR(20) | Employee number | 员工编号 | |
| dept_id | BIGINT | Store ID | 门店ID | |
| attendance_date | DATE | Actual attendance date | 实际出勤日期 | |
| effect_hours | FLOAT(7,2) | Actual hours worked | 实际工作工时 | |
| work_type | VARCHAR(4) | Work shift type | 班次类型 | |

**Data profile / 数据概况:**
- ~16-17K rows per table, 17-18 stores, from 2025-03-22.
  每表约1.6-1.7万行，17-18家门店，起始2025-03-22。

---

### 5. luckyus_opqualitycontrol.t_shopcheck_report

**Server:** aws-luckyus-opqualitycontrol-rw
**Purpose:** Quality inspection scoring reports per store.
门店质量检查评分报告。

| Column | Type | Description EN | Description CN | Notes |
|--------|------|---------------|---------------|-------|
| id | BIGINT | Report PK | 报告主键 | |
| dept_id | BIGINT | Store ID | 门店ID | |
| shopcheck_data_id | BIGINT | FK to t_shopcheck_data.id | 关联巡检签到ID | |
| check_date | DATE | Inspection date | 巡检日期 | |
| score | SMALLINT | Inspection score | 检查评分 | Typically 0-100 scale |
| score_desc | VARCHAR(10) | Score description | 评分说明 | |
| second_category_name | VARCHAR(2000) | Inspection sub-category name | 巡检项目二级分类 | |
| create_time | DATETIME | Record creation timestamp | 记录创建时间 | |

**Related table: t_shopcheck_data / 关联表：t_shopcheck_data**

| Column | Type | Description EN | Description CN | Notes |
|--------|------|---------------|---------------|-------|
| id | BIGINT | Inspection check-in PK | 巡检签到主键 | |
| dept_id | BIGINT | Store ID | 门店ID | |
| check_date | DATE | Inspection date | 巡检日期 | |
| status | INT | Inspection status | 巡检状态 | 1=completed, 0=incomplete |
| check_duration | INT | Inspection duration (seconds) | 巡检时长（秒） | Drop may indicate rushed checks |
| create_time | DATETIME | Record creation timestamp | 记录创建时间 | |

**Data profile / 数据概况:**
- Only ~120 records across 17 shops -- **sparse data**.
  仅约120条记录覆盖17家门店 -- **数据稀疏**。
- Many store-days will have NULL quality metrics. The anomaly model
  must handle NULLs gracefully for the quality dimension.
  许多门店日将无质量指标数据。异常模型需对质量维度空值进行合理处理。

---

## Analytics Tables / 分析表

All analytics tables reside on `aws-luckyus-dbatest-rw`, schema `test`.
These tables are populated by the Python orchestrator pipeline.

所有分析表位于 `aws-luckyus-dbatest-rw` 服务器，`test` schema。
这些表由 Python 编排器管道填充。

| # | Table | Grain | Purpose |
|---|-------|-------|---------|
| 1 | test.store_kpi_daily | store x day | Core daily KPI fact table / 每店每日KPI事实表 |
| 2 | test.store_anomaly_scores | store x metric x day | SPC computations / SPC统计过程控制计算 |
| 3 | test.store_health_scores | store x day | Composite health scores / 门店综合健康评分 |
| 4 | test.store_anomaly_alerts | store x alert | Alert records / 异常预警记录 |
| 5 | test.store_anomaly_pipeline_log | run x step | Pipeline execution log / 管道执行日志 |

---

### 1. test.store_kpi_daily

**Grain:** One row per (store_id, metric_date).
**Purpose:** Foundational fact table containing revenue, operations, staffing,
and quality KPIs aggregated from multiple source databases.
基础事实表，包含从多个源数据库汇总的收入、运营、人员配置和质量KPI。

| Column | Type | Description EN | Description CN |
|--------|------|---------------|---------------|
| id | BIGINT AUTO_INCREMENT | Primary key | 自增主键 |
| store_id | BIGINT NOT NULL | Store ID (dept_id) | 门店ID |
| store_name | VARCHAR(100) | Store display name | 门店名称 |
| store_no | VARCHAR(20) | Store number (e.g. US00001) | 门店编号 |
| metric_date | DATE NOT NULL | Business date | 业务日期 |
| total_revenue | DECIMAL(12,2) | Daily gross revenue (USD) | 每日总收入（美元） |
| order_count | INT | Number of completed orders | 完成订单数 |
| avg_order_value | DECIMAL(10,2) | Average order value = revenue/orders | 平均订单金额 |
| refund_count | INT DEFAULT 0 | Number of refunded orders | 退款订单数 |
| refund_amount | DECIMAL(12,2) DEFAULT 0 | Total refund amount (USD) | 退款总金额（美元） |
| production_count | INT | Items produced | 生产项目数 |
| avg_production_time_sec | DECIMAL(10,2) | Avg seconds per production | 平均生产时间（秒） |
| scheduled_hours | DECIMAL(8,2) | Total scheduled employee hours | 排班总工时 |
| employee_count | INT | Distinct employees scheduled | 排班员工数 |
| inspection_count | INT DEFAULT 0 | Number of inspections | 检查次数 |
| avg_quality_score | DECIMAL(5,2) | Average inspection score | 平均质量评分 |
| revenue_per_labor_hour | DECIMAL(10,2) | Revenue / scheduled_hours | 每工时收入 |
| orders_per_labor_hour | DECIMAL(10,2) | Orders / scheduled_hours | 每工时订单数 |
| day_of_week | TINYINT | Day of week (0=Mon..6=Sun) | 星期几（0=周一..6=周日） |
| is_weekend | BOOLEAN | Weekend flag (Sat/Sun) | 是否周末 |
| created_at | TIMESTAMP | Row creation timestamp | 记录创建时间 |
| updated_at | TIMESTAMP | Row last update timestamp | 记录更新时间 |

**Indexes / 索引:** `UNIQUE(store_id, metric_date)`, `idx_date`, `idx_store`, `idx_store_no`

---

### 2. test.store_anomaly_scores

**Grain:** One row per (store_id, metric_date, metric_name).
**Purpose:** SPC computations including rolling statistics, Z-scores, control
limits, and Western Electric rule violations.
SPC 计算结果，包括滚动统计、Z 分数、控制限和 Western Electric 规则违反。

| Column | Type | Description EN | Description CN |
|--------|------|---------------|---------------|
| id | BIGINT AUTO_INCREMENT | Primary key | 自增主键 |
| store_id | BIGINT NOT NULL | Store ID | 门店ID |
| store_name | VARCHAR(100) | Store name | 门店名称 |
| metric_date | DATE NOT NULL | Metric date | 指标日期 |
| metric_name | VARCHAR(50) NOT NULL | Metric name (e.g. total_revenue) | 指标名称 |
| metric_value | DECIMAL(14,4) | Current day metric value | 当日指标值 |
| rolling_mean_28d | DECIMAL(14,4) | 28-day rolling mean | 28天滚动均值 |
| rolling_std_28d | DECIMAL(14,4) | 28-day rolling standard deviation | 28天滚动标准差 |
| z_score | DECIMAL(8,4) | Z-score = (value - mean) / std | Z分数 |
| ucl_2sigma | DECIMAL(14,4) | Upper control limit (mean + 2*std) | 上控制限 2sigma |
| ucl_3sigma | DECIMAL(14,4) | Upper control limit (mean + 3*std) | 上控制限 3sigma |
| lcl_2sigma | DECIMAL(14,4) | Lower control limit (mean - 2*std) | 下控制限 2sigma |
| lcl_3sigma | DECIMAL(14,4) | Lower control limit (mean - 3*std) | 下控制限 3sigma |
| same_dow_mean | DECIMAL(14,4) | Same day-of-week mean | 同星期均值 |
| same_dow_std | DECIMAL(14,4) | Same day-of-week standard deviation | 同星期标准差 |
| dow_z_score | DECIMAL(8,4) | Day-of-week adjusted Z-score | 同星期Z分数 |
| we_rule1 | BOOLEAN DEFAULT FALSE | WE Rule 1: single point > 3-sigma | WE规则1: 单点超过3sigma |
| we_rule2 | BOOLEAN DEFAULT FALSE | WE Rule 2: 2 of 3 > 2-sigma (same side) | WE规则2: 3中2超过2sigma |
| we_rule3 | BOOLEAN DEFAULT FALSE | WE Rule 3: 4 of 5 > 1-sigma (same side) | WE规则3: 5中4超过1sigma |
| we_rule4 | BOOLEAN DEFAULT FALSE | WE Rule 4: 8 consecutive same side | WE规则4: 连续8点同侧 |
| we_rule5 | BOOLEAN DEFAULT FALSE | WE Rule 5: 6 consecutive declining | WE规则5: 连续6点递减 |
| anomaly_severity | ENUM('NONE','INFO','WARNING','CRITICAL') | Anomaly severity level | 异常严重度 |
| created_at | TIMESTAMP | Row creation timestamp | 记录创建时间 |

**Indexes / 索引:** `UNIQUE(store_id, metric_date, metric_name)`, `idx_date`, `idx_store`, `idx_severity`

---

### 3. test.store_health_scores

**Grain:** One row per (store_id, metric_date).
**Purpose:** Composite health score combining multiple dimensions with weighted formula.
门店综合健康评分，加权合并多个维度评分。

**Weighting formula / 加权公式:**
```
composite_score = 40% revenue + 20% ops + 15% quality + 15% staffing + 10% customer
```

| Column | Type | Description EN | Description CN |
|--------|------|---------------|---------------|
| id | BIGINT AUTO_INCREMENT | Primary key | 自增主键 |
| store_id | BIGINT NOT NULL | Store ID | 门店ID |
| store_name | VARCHAR(100) | Store name | 门店名称 |
| metric_date | DATE NOT NULL | Score date | 评分日期 |
| revenue_score | DECIMAL(5,2) | Revenue dimension (0-100) | 收入评分（0-100） |
| ops_score | DECIMAL(5,2) | Operations dimension (0-100) | 运营评分（0-100） |
| quality_score | DECIMAL(5,2) | Quality dimension (0-100) | 质量评分（0-100） |
| staffing_score | DECIMAL(5,2) | Staffing dimension (0-100) | 人员评分（0-100） |
| customer_score | DECIMAL(5,2) | Customer dimension (0-100) | 顾客评分（0-100） |
| composite_score | DECIMAL(5,2) | Weighted composite score | 综合评分（加权） |
| health_grade | CHAR(1) | Health grade letter (A/B/C/D/F) | 健康等级 |
| week_over_week_change | DECIMAL(8,4) | WoW composite score change | 周环比变化 |
| trend_direction | ENUM('IMPROVING','STABLE','DECLINING') | Score trend direction | 趋势方向 |
| created_at | TIMESTAMP | Row creation timestamp | 记录创建时间 |

**Grade scale / 等级标准:**

| Grade | Score Range | Interpretation EN | Interpretation CN |
|-------|-------------|-------------------|-------------------|
| A | 90-100 | Excellent performance | 表现优秀 |
| B | 75-89 | Good, minor issues | 良好，有小问题 |
| C | 60-74 | Needs attention | 需要关注 |
| D | 40-59 | Significant issues | 存在重大问题 |
| F | 0-39 | Critical, immediate action | 严重，需立即处理 |

**Indexes / 索引:** `UNIQUE(store_id, metric_date)`, `idx_date`, `idx_store`, `idx_grade`, `idx_composite`

---

### 4. test.store_anomaly_alerts

**Grain:** One row per alert event.
**Purpose:** Alert records generated when SPC rules are violated or health scores
drop below thresholds. Supports bilingual descriptions and acknowledgement workflow.
SPC 规则违反或健康评分低于阈值时生成的预警记录。支持中英文描述和确认流程。

| Column | Type | Description EN | Description CN |
|--------|------|---------------|---------------|
| id | BIGINT AUTO_INCREMENT | Primary key | 自增主键 |
| store_id | BIGINT NOT NULL | Store ID | 门店ID |
| store_name | VARCHAR(100) | Store name | 门店名称 |
| alert_date | DATE NOT NULL | Alert date | 预警日期 |
| alert_type | VARCHAR(50) NOT NULL | Alert type (SPC_RULE, HEALTH_DROP, TREND) | 预警类型 |
| severity | ENUM('INFO','WARNING','CRITICAL') | Alert severity | 严重程度 |
| metric_name | VARCHAR(50) | Triggering metric name | 触发指标名称 |
| current_value | DECIMAL(14,4) | Current metric value | 当前值 |
| expected_value | DECIMAL(14,4) | Expected (mean/baseline) value | 期望值 |
| threshold_value | DECIMAL(14,4) | Threshold value breached | 被突破的阈值 |
| z_score | DECIMAL(8,4) | Z-score at time of alert | 预警时Z分数 |
| consecutive_days | INT DEFAULT 1 | Consecutive days anomaly persisted | 连续异常天数 |
| we_rule_violated | VARCHAR(20) | Western Electric rule violated | 违反的WE规则 |
| description_en | TEXT | Alert description (English) | 英文描述 |
| description_cn | TEXT | Alert description (Chinese) | 中文描述 |
| recommended_action | TEXT | Recommended corrective action | 建议措施 |
| acknowledged | BOOLEAN DEFAULT FALSE | Whether alert was acknowledged | 是否已确认 |
| acknowledged_by | VARCHAR(100) | Username who acknowledged | 确认人 |
| acknowledged_at | TIMESTAMP NULL | Acknowledgement timestamp | 确认时间 |
| created_at | TIMESTAMP | Row creation timestamp | 记录创建时间 |

**Indexes / 索引:** `idx_store`, `idx_alert_date`, `idx_severity`, `idx_store_date`, `idx_ack`

---

### 5. test.store_anomaly_pipeline_log

**Grain:** One row per (run_id, step_number).
**Purpose:** Pipeline execution audit trail tracking every step, status, timing,
row counts, and errors. 管道执行审计日志，跟踪每个步骤的状态、时间、行数和错误。

| Column | Type | Description EN | Description CN |
|--------|------|---------------|---------------|
| id | BIGINT AUTO_INCREMENT | Primary key | 自增主键 |
| run_id | VARCHAR(36) NOT NULL | Pipeline run UUID | 运行ID（UUID） |
| run_date | DATE NOT NULL | Pipeline execution date | 运行日期 |
| step_number | INT NOT NULL | Step sequence number | 步骤序号 |
| step_name | VARCHAR(100) NOT NULL | Pipeline step name | 步骤名称 |
| step_description | VARCHAR(500) | Step description | 步骤描述 |
| status | ENUM('RUNNING','SUCCESS','FAILED','SKIPPED') | Execution status | 运行状态 |
| rows_affected | INT DEFAULT 0 | Rows affected by this step | 影响行数 |
| duration_seconds | DECIMAL(10,3) | Step duration in seconds | 耗时（秒） |
| error_message | TEXT | Error message if FAILED | 错误信息 |
| started_at | TIMESTAMP | Step start timestamp | 开始时间 |
| completed_at | TIMESTAMP NULL | Step completion timestamp | 完成时间 |

**Pipeline steps / 管道步骤:**

| Step# | Step Name | Description EN | Description CN |
|-------|-----------|---------------|---------------|
| 1 | extract_store_master | Load store reference data | 加载门店主数据 |
| 2 | extract_revenue_kpis | Pull daily revenue from salesorder | 提取每日营收 |
| 3 | extract_production_kpis | Pull production metrics | 提取生产指标 |
| 4 | extract_staffing_kpis | Pull scheduling/attendance | 提取排班/出勤 |
| 5 | extract_quality_kpis | Pull inspection scores | 提取质检评分 |
| 6 | compute_derived_metrics | Calculate revenue_per_labor_hour etc. | 计算衍生指标 |
| 7 | compute_spc_scores | Z-scores, control limits, WE rules | 计算SPC评分 |
| 8 | compute_health_scores | Weighted composite health score | 计算综合健康评分 |
| 9 | generate_alerts | Evaluate alert rules, create records | 生成预警记录 |
| 10 | data_quality_check | Verify completeness and freshness | 数据质量检查 |

**Indexes / 索引:** `idx_run_id`, `idx_run_date`, `idx_status`

---

## Store Reference / 门店参考

The 10 monitored Luckin Coffee USA store locations.
受监控的10家瑞幸咖啡美国门店。

| dept_id | shop_no | Store Name | Address | Opened | Status | Notes |
|---------|---------|------------|---------|--------|--------|-------|
| 1131 | US00000 | NJ Test Kitchen | 1 County Rd B9, Secaucus NJ | 2025-05-09 | Active | Test/R&D facility |
| 1127 | US00001 | 8th & Broadway | 755 Broadway, New York NY 10003 | 2025-06-30 | Active | Flagship; 51% revenue decline case study |
| 1128 | US00002 | 28th & 6th | 800 6th Ave, New York NY 10001 | 2025-06-30 | Active | |
| 1140 | US00003 | 100 Maiden Ln | 100 Maiden Ln, New York NY 10038 | 2025-09-09 | Active | Financial District |
| 20011 | US00004 | 37th & Broadway | 1375 Broadway, New York NY 10018 | 2025-11-20 | Active | Potential cannibalization source |
| 1141 | US00005 | 54th & 8th | 901 8th Ave, New York NY 10019 | 2025-08-24 | Active | Midtown West |
| 20010 | US00006 | 102 Fulton | 102 Fulton St, New York NY 10038 | 2025-08-28 | Active | Financial District |
| 20009 | US00007 | 108th & Broadway | 2799 Broadway, New York NY 10025 | -- | status=2 | Not yet open / 尚未开业 |
| 20008 | US00008 | 33rd & 10th | 410 10th Ave, New York NY 10001 | 2025-12-01 | Active | Hell's Kitchen area |
| 20046 | US99998 | Shanghai Test Kitchen | 15 W 38th St, New York NY 10018 | 2025-11-14 | Active | Overseas test facility |

**Active store IDs for SQL filters / 活跃门店ID列表（用于SQL过滤）:**
```sql
dept_id IN (1127, 1128, 1131, 1140, 1141, 20008, 20009, 20010, 20011, 20046)
```

---

## Metric Definitions / 指标定义

All metrics are computed at the **store x day** grain and stored in
`test.store_kpi_daily`. 所有指标按**门店 x 日**粒度计算，存储在 `test.store_kpi_daily`。

### Revenue Metrics / 收入指标

| Metric | Formula | Unit | Source | Description EN | Description CN |
|--------|---------|------|--------|---------------|---------------|
| total_revenue | `SUM(pay_money)` where status >= 20 | USD | t_order | Daily gross revenue from completed orders | 已完成订单每日总收入 |
| order_count | `COUNT(*)` where status >= 20 | count | t_order | Number of completed orders per day | 每日完成订单数 |
| avg_order_value | `total_revenue / order_count` | USD | derived | Average order value (AOV) per day | 日均客单价 |
| refund_count | `COUNT(*)` where refund_status > 0 | count | t_order | Orders with refund initiated | 有退款的订单数 |
| refund_amount | `SUM(pay_money)` for refunded orders | USD | t_order | Total value of refunded orders | 退款总金额 |

### Operations Metrics / 运营指标

| Metric | Formula | Unit | Source | Description EN | Description CN |
|--------|---------|------|--------|---------------|---------------|
| production_count | `COUNT(*)` completed productions | count | t_production | Daily items produced | 每日生产项目数 |
| avg_production_time_sec | `AVG(TIMESTAMPDIFF(SECOND, accept_time, done_time))` | seconds | t_production | Average time from accept to done | 平均生产时间（秒） |

### Staffing Metrics / 人员指标

| Metric | Formula | Unit | Source | Description EN | Description CN |
|--------|---------|------|--------|---------------|---------------|
| scheduled_hours | `SUM(effect_hours)` | hours | t_emp_scheduling | Total scheduled labor hours | 排班总工时 |
| employee_count | `COUNT(DISTINCT emp_no)` | count | t_emp_scheduling | Distinct employees scheduled | 排班员工人数 |

### Quality Metrics / 质量指标

| Metric | Formula | Unit | Source | Description EN | Description CN |
|--------|---------|------|--------|---------------|---------------|
| inspection_count | `COUNT(*)` | count | t_shopcheck_report | Number of inspections on the day | 当日检查次数 |
| avg_quality_score | `AVG(score)` | score (0-100) | t_shopcheck_report | Average inspection score | 平均质量评分 |

### Derived / Efficiency Metrics / 衍生/效率指标

| Metric | Formula | Unit | Source | Description EN | Description CN |
|--------|---------|------|--------|---------------|---------------|
| revenue_per_labor_hour | `total_revenue / scheduled_hours` | USD/hour | derived | Labor productivity by revenue | 每工时收入 |
| orders_per_labor_hour | `order_count / scheduled_hours` | orders/hour | derived | Labor productivity by volume | 每工时订单数 |

---

## SPC Terminology / SPC 术语

### Core Concepts / 核心概念

**Z-Score / Z分数**
A standardized measure of how many standard deviations an observation is from
the rolling mean. 一个标准化度量，表示观测值偏离滚动均值多少个标准差。
```
Z = (X - mu) / sigma

Where:
  X     = observed daily metric value / 观测的每日指标值
  mu    = 28-day rolling mean (excluding current day) / 28天滚动均值（不含当天）
  sigma = 28-day rolling standard deviation / 28天滚动标准差
```

**Rolling Mean / 滚动均值 (mu)**
The average of the metric over the prior 28 calendar days, excluding the
current observation. Provides a stable baseline that adapts to gradual trends.
前28个日历日的指标均值（不含当天观测值）。提供适应渐进趋势的稳定基线。

**Rolling Standard Deviation / 滚动标准差 (sigma)**
The sample standard deviation over the same 28-day window. Defines the expected
range of normal variation. 同一28天窗口的样本标准差。定义正常变异的预期范围。

### Control Limits / 控制限

| Limit | Formula | Meaning EN | Meaning CN |
|-------|---------|-----------|-----------|
| UCL 2-sigma | mean + 2 * std | Upper warning limit | 上警戒限 |
| UCL 3-sigma | mean + 3 * std | Upper action limit | 上行动限 |
| LCL 2-sigma | mean - 2 * std | Lower warning limit | 下警戒限 |
| LCL 3-sigma | mean - 3 * std | Lower action limit | 下行动限 |

### Western Electric Rules / Western Electric 规则

Applied to sequential daily observations on X-bar control charts. Originally
developed by Western Electric Company for manufacturing quality control; adapted
here for retail store performance monitoring.
应用于X-bar控制图的连续每日观测值。最初由Western Electric公司为制造质量控制开发；
此处改用于零售门店绩效监控。

| Rule | Pattern | Interpretation EN | Interpretation CN |
|------|---------|-------------------|-------------------|
| Rule 1 | 1 point beyond 3-sigma | Single extreme outlier | 单点极端异常值 |
| Rule 2 | 2 of 3 consecutive points beyond 2-sigma (same side) | Emerging shift | 正在出现的偏移 |
| Rule 3 | 4 of 5 consecutive points beyond 1-sigma (same side) | Sustained drift | 持续漂移 |
| Rule 4 | 8 consecutive points on same side of center line | Process mean shift | 过程均值偏移 |
| Rule 5 | 6 consecutive points in a declining trend | Continuous deterioration | 持续恶化趋势 |

**8th Avenue validation:** Rule 4 would have flagged the 8th & Broadway (US00001)
sustained revenue decline within 8 business days of the trend starting -- approximately
4-6 weeks before the issue was manually discovered.
**第八大道验证：** 规则4能在趋势开始后8个工作日内标记第八大道 (US00001) 的持续营收下降 --
比人工发现提前约4-6周。

### Anomaly Severity Levels / 异常严重度等级

| Severity | Z-Score Threshold | Response EN | Response CN |
|----------|------------------|-------------|-------------|
| CRITICAL | \|Z\| > 3.0 | Immediate investigation; page on-call ops lead | 立即调查；通知值班运营主管 |
| WARNING | \|Z\| > 2.0 | Next-day review; add to weekly ops meeting | 次日审查；加入周运营会议议程 |
| INFO | \|Z\| > 1.5 | Log for trend analysis; no immediate action | 记录用于趋势分析；无需立即行动 |
| NONE | \|Z\| <= 1.5 | Normal operation | 正常运营 |

### Health Score / 健康评分

A composite 0-100 score combining five dimensions with the following weights.
0-100综合评分，按以下权重合并五个维度。

```
composite_score = (0.40 * revenue_score)
                + (0.20 * ops_score)
                + (0.15 * quality_score)
                + (0.15 * staffing_score)
                + (0.10 * customer_score)
```

Each dimension score is computed by normalizing the store's daily metrics against
its own historical distribution and peer-store benchmarks.
每个维度评分通过将门店日度指标对比其历史分布和同行基准进行标准化计算。

### Health Grade / 健康等级

Letter grades map composite scores to actionable categories.
字母等级将综合评分映射到可操作类别。

| Grade | Range | Status EN | Status CN |
|-------|-------|-----------|-----------|
| A | >= 90 | Excellent -- no action needed | 优秀 -- 无需行动 |
| B | 75-89 | Good -- minor monitoring | 良好 -- 轻度关注 |
| C | 60-74 | Attention -- review within 48h | 需关注 -- 48小时内审查 |
| D | 40-59 | Concern -- investigate this week | 需重视 -- 本周调查 |
| F | < 40 | Critical -- immediate escalation | 严重 -- 立即升级 |

### Trend Direction / 趋势方向

| Direction | Definition | Threshold |
|-----------|-----------|-----------|
| IMPROVING | Week-over-week composite score increase | WoW change > +2.0 |
| STABLE | Composite score within normal fluctuation | WoW change between -2.0 and +2.0 |
| DECLINING | Week-over-week composite score decrease | WoW change < -2.0 |

---

*UC-OP-02 Store Performance Anomaly Detection -- Luckin Coffee USA Operations Intelligence*
*Data Dictionary v1.0 -- 2026-02-15*
