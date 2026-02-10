# Redis luckyus-isales-market - Summary Statistics

**Report Period:** 2026-02-10 08:06 UTC to 14:06 UTC (6 hours)
**Instance:** `rediss://master.luckyus-isales-market.vyllrs.use1.cache.amazonaws.com:6379`
**Region:** us-east-1

---

## Memory Usage Statistics

| Metric | Value |
|--------|-------|
| **Minimum** | 54.78% (1.27 GB) |
| **Maximum** | 75.61% (1.75 GB) |
| **Current** | 55.07% (1.28 GB) |
| **Alert Threshold** | 70% |
| **Peak Time** | 2026-02-10T11:51:00Z |
| **Recovery Time** | 2026-02-10T13:01:00Z |
| **Time Above Threshold** | ~70 minutes |
| **Max Memory Capacity** | 2.32 GB |

### Memory Phases
| Phase | Start Time | End Time | Duration | Avg Memory % |
|-------|------------|----------|----------|--------------|
| Pre-event baseline | 08:06 | 08:36 | 30 min | 54.78% |
| First spike (small) | 08:41 | 11:36 | ~3 hrs | 57.5% |
| Major spike | 11:41 | 11:51 | 10 min | 68-75% |
| Above threshold | 11:46 | 12:56 | 70 min | 70-75% |
| Recovery | 12:56 | 14:06 | 70 min | 55-59% |

---

## Key Count Statistics

| Metric | Value |
|--------|-------|
| **Minimum Keys** | 5,761,447 |
| **Maximum Keys** | 6,326,183 |
| **Current Keys** | 5,761,447 |
| **Keys Added (peak)** | +473,156 keys |
| **Keys Expired Since Peak** | -564,736 keys |

### Key TTL Breakdown (Current)
| Category | Count | Percentage |
|----------|-------|------------|
| Keys with TTL | 3,226,667 | 56.01% |
| Keys without TTL | 2,534,780 | 43.99% |
| **Total** | **5,761,447** | 100% |

---

## Connected Clients Statistics

| Metric | Value |
|--------|-------|
| **Baseline** | 26-27 |
| **Maximum** | 134 |
| **Current** | 89 |
| **Peak Increase** | +108 clients (+415%) |
| **Peak Time** | 2026-02-10T11:46:00Z |

---

## Commands Per Second Statistics

| Metric | Value |
|--------|-------|
| **Baseline Avg** | 7-11 cmd/sec |
| **Maximum** | 8,199.59 cmd/sec |
| **Current** | 163.56 cmd/sec |
| **Peak Increase** | 800x baseline |
| **Peak Time** | 2026-02-10T11:51:00Z |

---

## Event Correlation Timeline

| Time (UTC) | Event | Memory % | Keys | Clients | Cmd/sec |
|------------|-------|----------|------|---------|---------|
| 08:06 | Baseline | 54.78% | 5.85M | 26 | 7.69 |
| 08:41 | First write wave starts | 58.22% | 6.10M | 41 | 2,688 |
| 11:36 | Build-up phase | 57.33% | 6.00M | 58 | 265 |
| 11:41 | Major spike begins | 59.04% | 6.02M | 92 | 2,034 |
| **11:46** | **Alert triggered** | **68.48%** | **6.20M** | **134** | **7,974** |
| **11:51** | **Peak reached** | **75.61%** | **6.33M** | 103 | **8,200** |
| 12:16 | Crosses below threshold | 70.75% | 6.20M | 103 | 144 |
| 12:56 | Alert clears | 58.72% | 5.85M | 101 | 146 |
| 14:06 | Current | 55.07% | 5.76M | 89 | 164 |

---

## Key Insights for Visualization

### Recommended Chart Types

1. **Time Series Line Chart (Multi-axis)**
   - Left Y-axis: Memory % (0-100)
   - Right Y-axis: Commands/sec (0-10000)
   - X-axis: Time
   - Add horizontal line at 70% threshold

2. **Stacked Area Chart**
   - Keys with TTL vs Keys without TTL
   - Shows composition over time

3. **Dual Line Chart**
   - Connected Clients (left axis)
   - Commands/sec (right axis)
   - Shows correlation between load sources

4. **Heatmap or Event Timeline**
   - Color-coded by severity
   - Mark alert trigger and recovery points

### Key Correlations to Highlight

1. **Client spike → Command spike → Memory spike** (15-20 minute cascade)
2. **Keys with TTL increasing → Memory increase** (direct correlation)
3. **Natural TTL expiration → Memory recovery** (self-healing pattern)

---

*Generated: 2026-02-10T14:15:00Z*
*Data Source: Prometheus via Grafana MCP*
