# Redis luckyus-isales-market Visualization Data

**Alert Date:** February 10, 2026
**Instance:** `rediss://master.luckyus-isales-market.vyllrs.use1.cache.amazonaws.com:6379`
**Region:** us-east-1
**Data Source:** Prometheus via Grafana MCP

---

## Quick Summary

| Metric | Before | Peak | After |
|--------|--------|------|-------|
| Memory % | 54.78% | **75.61%** | 55.07% |
| Keys | 5.85M | **6.33M** | 5.76M |
| Clients | 26 | **134** | 89 |
| Cmd/sec | 7-11 | **8,200** | 164 |

**Root Cause:** Burst write operation added ~473K keys in ~10 minutes
**Resolution:** Self-healed via TTL expiration (no intervention needed)

---

## Files Included

### CSV Files (Excel/Tableau/Power BI ready)

| File | Description | Columns |
|------|-------------|---------|
| `01-memory-usage-percent.csv` | Memory utilization % | timestamp_unix, timestamp_iso, memory_usage_percent |
| `02-key-count.csv` | Redis key statistics | timestamp, total_keys, keys_with_ttl, keys_without_ttl, ttl_percentage |
| `03-connected-clients.csv` | Client connections | timestamp, connected_clients |
| `04-commands-per-second.csv` | Throughput | timestamp, commands_per_second |
| `05-memory-bytes.csv` | Raw memory in bytes | timestamp, memory_used_bytes, memory_used_gb, memory_max_bytes |
| `08-combined-timeseries.csv` | All metrics combined | All columns + above_threshold flag |

### JSON Files (JavaScript/D3/Chart.js ready)

| File | Description |
|------|-------------|
| `06-combined-all-metrics.json` | Complete dataset with metadata and event markers |

### Documentation

| File | Description |
|------|-------------|
| `07-summary-statistics.md` | Statistical analysis and chart recommendations |
| `README.md` | This file |

---

## Visualization Recommendations

### 1. Memory Timeline with Alert Threshold
```
Chart Type: Line chart with area fill
X-axis: Time (08:06 - 14:06 UTC)
Y-axis: Memory % (0-100)
Features:
  - Horizontal line at 70% (alert threshold)
  - Shaded region where above_threshold=1
  - Peak annotation at 75.61%
```

### 2. Multi-Metric Correlation
```
Chart Type: Multi-axis line chart
Left Y-axis: Memory % + Clients
Right Y-axis: Commands/sec (log scale recommended)
Insight: Shows cascade effect (clients → commands → memory)
```

### 3. Key Composition Stacked Area
```
Chart Type: Stacked area
Data: keys_with_ttl + keys_without_ttl = keys_total
Insight: Shows that burst added keys WITH TTL (good practice)
```

### 4. Recovery Rate Analysis
```
Chart Type: Line with trend
Data: Memory % from 11:51 (peak) to 14:06 (current)
Insight: Linear recovery rate of ~0.4%/min after peak
```

---

## Data Quality Notes

- **Sample Interval:** 5 minutes (300 seconds)
- **Data Points:** 73 per metric
- **Missing Data:** None
- **Timezone:** All timestamps in UTC
- **Precision:** 2 decimal places for percentages

---

## Usage Examples

### Python (Pandas)
```python
import pandas as pd

# Load combined data
df = pd.read_csv('08-combined-timeseries.csv')
df['timestamp_iso'] = pd.to_datetime(df['timestamp_iso'])
df.set_index('timestamp_iso', inplace=True)

# Plot memory with threshold
import matplotlib.pyplot as plt
fig, ax = plt.subplots(figsize=(12, 6))
ax.plot(df.index, df['memory_percent'], label='Memory %')
ax.axhline(y=70, color='r', linestyle='--', label='Alert Threshold')
ax.fill_between(df.index, df['memory_percent'], 70,
                where=df['memory_percent'] > 70, alpha=0.3, color='red')
plt.legend()
plt.show()
```

### JavaScript (Chart.js)
```javascript
fetch('06-combined-all-metrics.json')
  .then(response => response.json())
  .then(data => {
    const labels = data.time_series.map(d => d.timestamp);
    const memoryData = data.time_series.map(d => d.memory_percent);

    new Chart(ctx, {
      type: 'line',
      data: {
        labels: labels,
        datasets: [{
          label: 'Memory %',
          data: memoryData,
          borderColor: 'rgb(75, 192, 192)'
        }]
      },
      options: {
        plugins: {
          annotation: {
            annotations: {
              threshold: {
                type: 'line',
                yMin: 70, yMax: 70,
                borderColor: 'red',
                borderDash: [5, 5]
              }
            }
          }
        }
      }
    });
  });
```

---

*Generated: 2026-02-10T14:15:00Z*
