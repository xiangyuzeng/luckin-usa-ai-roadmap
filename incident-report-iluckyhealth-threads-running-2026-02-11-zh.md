# RDS 活跃线程告警 - 故障报告
**集群名称：** aws-luckyus-iluckyhealth-rw (MySQL RDS)
**告警时间：** 2026-02-11 (持续时间：调查前已自动恢复)
**严重程度：** 高
**状态：** 已解决 (调查时告警已清除)

---

## 概要

RDS 集群 `aws-luckyus-iluckyhealth-rw` 触发活跃线程持续高于 24 的告警(持续2分钟)。调查发现**大型采集表上的超慢分析查询**导致线程堆积。告警在 DBA 介入前已自动恢复,但根因分析发现了需要立即优化的关键性能问题。

---

## 根因分析

### 主要原因:未优化的分析查询导致慢查询堆积

**关键发现:**

1. **极端查询时长 - 最长96分钟**
   - `t_collect_shop_make_inter` 表的 GROUP BY 查询: **5,787 秒 (96分钟)**
   - 每次执行扫描: **20,722,827 行**
   - 缺少支持聚合查询的索引

2. **高频慢查询**
   - `t_collect_shop_make_inter` 上的时间分桶查询: **执行 7,625 次**
   - 平均时长: **每次查询 118 秒**
   - 总扫描行数: **381,753,314 行**
   - 这些查询很可能重叠执行,导致线程累积

3. **大表无优化**
   - `t_collect_order_tenant_inter`: 3670万行 (8.8 GB)
   - `t_collect_shop_make_inter`: 2750万行 (6.7 GB)
   - `t_collect_order_inter`: 1230万行 (2.6 GB)
   - 总查询负载: **2040万次执行,扫描 386 亿行**

### 次要因素:
- ✅ 未检测到锁竞争
- ✅ 无元数据锁阻塞 DML
- ✅ InnoDB 状态无死锁
- ✅ 连接分布正常 (调查时共9个连接)

---

## 受影响组件

### 数据表
- `t_collect_shop_make_inter` (2750万行) - **主要影响**
- `t_collect_order_inter` (1230万行)
- `t_collect_order_tenant_inter` (3670万行)
- `t_collect_payment_inter` (660万行)
- `t_collect_shop_inter` (680万行)

### 查询模式
1. **无索引支持的分析型 GROUP BY 聚合**
2. **带日期分桶的时间范围查询** (UNIX_TIMESTAMP 计算)
3. **带排序的 DISTINCTROW 查询** (metric_name 列)
4. **当天聚合查询** 使用 `DATE(insert_time) = CURDATE()`

### 用户/应用
- **用户:** `iluckyhealth_o` (应用查询)
- **数据库:** `luckyus_iluckyhealth`

---

## 已采取行动

### 立即行动 (调查期间)
1. ✅ 确认告警已自动恢复 (Threads_running: 2, Threads_connected: 9)
2. ✅ 无活跃长查询需要终止
3. ✅ 收集 performance schema 诊断数据
4. ✅ 分析查询模式和表统计信息

### 无需操作
- 无需 KILL 命令 (无运行超过60秒的查询)
- 无需紧急参数调优

---

## 后续行动 (关键 - 需要执行)

### 1. **紧急:索引优化 (P0)**

**目标: `t_collect_shop_make_inter` (2750万行)**
```sql
-- 针对 GROUP BY metric_name 查询
CREATE INDEX idx_metric_name_inserttime ON t_collect_shop_make_inter(metric_name, metric_name_comment, insert_time);

-- 针对时间范围 + 指标过滤
CREATE INDEX idx_inserttime_metricname_value ON t_collect_shop_make_inter(insert_time, metric_name, metric_value);
```

**目标: `t_collect_order_inter` (1230万行)**
```sql
-- 针对使用 CURDATE() 的当日聚合
CREATE INDEX idx_inserttime_metricname ON t_collect_order_inter(insert_time, metric_name, metric_value);

-- 针对渠道/类型分析查询
CREATE INDEX idx_metric_inserttime ON t_collect_order_inter(metric_name, insert_time);
```

**目标: `t_collect_payment_inter` (660万行)**
```sql
CREATE INDEX idx_metric_inserttime ON t_collect_payment_inter(metric_name, insert_time);
```

### 2. **查询重写建议 (P0)**

**替换:**
```sql
-- 错误: 全表扫描使用 DATE() 函数
WHERE DATE(insert_time) = CURDATE()
```

**改为:**
```sql
-- 正确: 索引友好的范围扫描
WHERE insert_time >= CURDATE() AND insert_time < CURDATE() + INTERVAL 1 DAY
```

**对于时间分桶,考虑预计算物化聚合:**
```sql
-- 不要对2700万行进行实时 UNIX_TIMESTAMP() 计算
-- 通过定时任务创建小时/每日汇总表
```

### 3. **应用层优化 (P1)**

- **实现查询结果缓存** 用于重复的指标查询
- **添加分页/限制** 到分析查询 (避免无界 GROUP BY)
- **在非高峰时段调度重型分析**
- **考虑只读副本** 用于报表查询

### 4. **表分区策略 (P1)**

对于时间序列数据表:
```sql
-- 按月/周分区以改进查询修剪
ALTER TABLE t_collect_shop_make_inter
PARTITION BY RANGE (TO_DAYS(insert_time)) (
    PARTITION p202601 VALUES LESS THAN (TO_DAYS('2026-02-01')),
    PARTITION p202602 VALUES LESS THAN (TO_DAYS('2026-03-01')),
    ...
);
```

### 5. **监控增强 (P2)**

- 添加慢查询日志分析 (>5秒的查询)
- 设置告警用于:
  - 查询扫描 >100万行
  - 单个查询时长 >60秒
  - `Threads_running` 飙升并附带查询详情

### 6. **数据生命周期管理 (P2)**

- 实施 `t_collect_*` 表超过90天数据的归档
- 当前增长率: 每表约2700万行 = 6.7GB
- 预测: 无归档情况下每年超过3亿行

---

## 性能影响评估

| 指标 | 告警期间 | 当前状态 |
|------|---------|---------|
| 运行线程数 | >24 (告警阈值) | 2 |
| 连接线程数 | 未知 (估计>50) | 9 |
| 最长查询 | 5,787 秒 | 0 秒 |
| 总扫描行数 | 386 亿 | 极少 |

---

## 经验教训

1. **OLTP 数据库上无索引的分析查询会导致严重性能下降**
2. **WHERE 子句中使用日期函数会阻止索引使用** (DATE(insert_time) vs. insert_time 范围)
3. **大表聚合需要覆盖索引** (metric_name + insert_time)
4. **监控应包含查询级指标**,不仅仅是连接/线程计数

---

## 后续步骤与负责人

| 行动 | 负责人 | 截止日期 | 状态 |
|------|-------|---------|------|
| 在 t_collect_shop_make_inter 创建索引 | DBA 团队 | 2026-02-12 | 🔴 待办 |
| 重写 CURDATE() 查询 | 应用团队 (iLuckyHealth) | 2026-02-13 | 🔴 待办 |
| 实现查询缓存 | 应用团队 | 2026-02-15 | 🔴 待办 |
| 评估分区策略 | DBA 团队 | 2026-02-18 | 🔴 待办 |
| 设置增强监控 | DevOps 团队 | 2026-02-20 | 🔴 待办 |

---

## 附录:查询示例

### 前3个最慢查询

**1. 门店制作指标聚合 (5787秒)**
```sql
SELECT DISTINCTROW metric_name, metric_name_comment,
       COUNT(*) AS record_count,
       MIN(insert_time) AS earliest,
       MAX(insert_time) AS latest
FROM luckyus_iluckyhealth.t_collect_shop_make_inter
GROUP BY metric_name, metric_name_comment
ORDER BY metric_name;
-- 扫描行数: 20,722,827
-- 返回行数: 184
```

**2. 时间分桶查询 (平均118秒, 执行7625次)**
```sql
SELECT (UNIX_TIMESTAMP(insert_time) DIV ? * ?) DIV (? * ?) * (? * ?) AS ?,
       SUM(metric_count) AS ?
FROM t_collect_shop_make_inter
WHERE insert_time BETWEEN FROM_UNIXTIME(?) AND FROM_UNIXTIME(?)
  AND metric_name = ? AND metric_value = ?
GROUP BY ?
ORDER BY UNIX_TIMESTAMP(insert_time) DIV ? * ?;
-- 总扫描行数: 381,753,314 (所有执行的总和)
```

**3. 当日聚合 (平均78秒, 130次执行)**
```sql
SELECT SUM(metric_count) AS ?
FROM luckyus_iluckyhealth.t_collect_order_inter
WHERE metric_name = ? AND metric_value = ?
  AND DATE(insert_time) = CURDATE();
-- 总扫描行数: 26,770,369 (所有执行的总和)
```

---

**报告生成时间:** 2026-02-11
**调查人员:** DBA 团队 (自动化 MCP 诊断)
**严重程度分类:** 高 (已自动恢复,但根因仍存在)
