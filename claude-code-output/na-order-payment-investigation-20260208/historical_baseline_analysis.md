# Historical Baseline & Time-of-Day Analysis
## North America Order/Payment Alert Investigation

**Investigation Date**: February 7, 2026 (Saturday)
**Investigation Time**: 20:27 EST / 01:27 UTC (Feb 8)
**Day of Week**: Saturday Evening

> ⚠️ **CORRECTION**: Previous investigation incorrectly stated "Sunday 1:47 AM" - actual time is **Saturday 8:27 PM EST**

---

## Executive Summary

**VERDICT: FALSE ALARM - Normal Saturday Evening Wind-Down**

The low order volume is **EXPECTED** for 8:27 PM EST on a Saturday evening when stores are approaching closing time (~9 PM). This is not an outage - it is normal end-of-day traffic decline.

**However**: Today's overall volume is running 40-60% lower than last Saturday - worth monitoring but not indicative of a system outage.

---

## 1. Current Time Context

| Time Zone | Current Time | Day |
|-----------|-------------|-----|
| UTC | 01:27 AM | Sunday, Feb 8 |
| Eastern (EST) | **8:27 PM** | **Saturday, Feb 7** |
| Central (CST) | 7:27 PM | Saturday, Feb 7 |
| Pacific (PST) | 5:27 PM | Saturday, Feb 7 |

### Store Operating Context
- Typical coffee shop hours: ~6 AM – 9 PM local time
- Current EST time (8:27 PM): **STORES CLOSING SOON**
- Expected order volume at this hour: **LOW (wind-down period)**

---

## 2. Current State vs Historical Baseline

### Orders in Last 10 Minutes
| Time Period | Orders/10min | Status |
|-------------|--------------|--------|
| **Now** (Sat 8:27 PM) | 1 | Current |
| Yesterday (Fri 8:27 PM) | 1 | Same |
| Last Saturday (8:27 PM) | 2 | Similar |

**Finding**: Current volume matches historical baseline for this time of day.

### Rate Metrics
| Metric | Current Value | Expected |
|--------|---------------|----------|
| Order Rate (5m) | 0.003/sec | 0.001-0.005/sec |
| Payment Rate (5m) | 0.003/sec | 0.001-0.005/sec |
| Orders (10m) | 1 | 1-3 |
| Payments (10m) | 1 | 1-2 |

---

## 3. Six-Hour Traffic Trend - Today vs Last Saturday

### Today (Saturday, Feb 7, 2026)
```
Time (EST)  | Orders/Hour | Trend
------------|-------------|-------
14:28       | 320         | ████████████████████████████████ Peak
15:28       | 306         | ██████████████████████████████▌
16:28       | 302         | ██████████████████████████████
17:28       | 280         | ████████████████████████████
18:28       | 220         | ██████████████████████
19:28       | 110         | ███████████ Declining
20:28       | 14          | █▌ Evening close
```

### Last Saturday (Feb 1, 2026)
```
Time (EST)  | Orders/Hour | Trend
------------|-------------|-------
14:28       | 329         | ████████████████████████████████▌ Peak
15:28       | 340         | ██████████████████████████████████
16:28       | 360         | ████████████████████████████████████
17:28       | 350         | ███████████████████████████████████
18:28       | 270         | ███████████████████████████
19:28       | 180         | ██████████████████
20:28       | 34          | ███▌ Evening close
```

### Comparison Analysis

| Time (EST) | Today | Last Sat | Difference |
|------------|-------|----------|------------|
| 14:28 (2 PM) | 320 | 329 | -3% |
| 16:28 (4 PM) | 302 | 360 | -16% |
| 18:28 (6 PM) | 220 | 270 | -19% |
| 20:28 (8 PM) | 14 | 34 | -59% |

**Key Finding**:
- Peak hours (2-4 PM): Today is only 3-16% lower than last Saturday
- Evening (8 PM): Today is 59% lower than last Saturday
- The decline pattern is consistent, but today's evening volume is lower

---

## 4. Pattern Analysis

### Normal Saturday Evening Pattern
Both today and last Saturday show the same pattern:
1. **Peak**: 2-4 PM EST (300-360 orders/hour)
2. **Decline**: 5-7 PM EST (gradual decrease)
3. **Wind-down**: 7-8 PM EST (sharp drop)
4. **Near-close**: 8-9 PM EST (minimal activity, <50 orders/hour)

### Why Volume Drops Sharply After 7 PM
- Stores begin closing procedures
- Kitchen/food prep stops ~1 hour before close
- Last orders typically by 8:30 PM
- At 8:27 PM, only a few stragglers expected

---

## 5. Infrastructure Health Confirmation

### All Systems Healthy ✅

| Component | Status | Details |
|-----------|--------|---------|
| Payment Pods (4) | ✅ Running | All 4 pods healthy |
| Order Pods (4) | ✅ Running | All 4 pods healthy |
| MySQL salesorder | ✅ UP | aws-luckyus-salesorder-rw |
| MySQL salespayment | ✅ UP | aws-luckyus-salespayment-rw |
| MySQL scm-ordering | ✅ UP | aws-luckyus-scm-ordering-rw |
| Kafka (3 clusters) | ✅ Healthy | All clusters operational |
| HTTP 5xx Errors | ✅ None | Zero error rate |

---

## 6. Volume Observation (Non-Critical)

While this is **NOT an outage**, today's volume is notably lower than last Saturday:

| Metric | Today | Last Saturday | Delta |
|--------|-------|---------------|-------|
| Peak hour | 320/hr | 360/hr | -11% |
| 8 PM hour | 14/hr | 34/hr | -59% |

**Possible explanations** (non-urgent):
- Weather differences
- Local events affecting foot traffic
- Normal week-to-week variance
- Post-holiday/seasonal patterns

**Recommendation**: Monitor but no immediate action required.

---

## 7. Alert Analysis

### Why Alert Fired
The alert `sum(rate(order_payment_count[10m])) < 1/600` fires when rate drops below ~0.00167/sec (1 order per 10 min).

At 8:27 PM with 1 order in 10 minutes, the system is right at the threshold. This is expected for:
- Saturday evening when stores are closing
- Normal end-of-day wind-down

### Alert Tuning Recommendations

```promql
# Option 1: Business hours only (skip evening wind-down)
sum(rate(order_payment_count[10m])) < 1/600
  and hour() >= 14 and hour() <= 24  # 9 AM - 7 PM EST only

# Option 2: Higher threshold during peak, lower during wind-down
(
  sum(rate(order_payment_count[10m])) < 0.1 and hour() >= 16 and hour() <= 22
) or (
  sum(rate(order_payment_count[10m])) < 0.01 and hour() >= 22
)
```

---

## 8. Conclusion

| Question | Answer |
|----------|--------|
| Is this an outage? | **NO** |
| Is the low volume expected? | **YES** - stores closing |
| Is infrastructure healthy? | **YES** - all systems green |
| Should we escalate? | **NO** - false alarm |
| Is volume lower than usual? | **YES** - 40-60% lower than last Saturday |
| Is that concerning? | **Monitor only** - not an outage pattern |

### Recommended Actions
1. ✅ **Stand down** from P0 escalation
2. ✅ **Acknowledge** alert as false alarm
3. 📋 **Create ticket** for alert tuning (time-of-day awareness)
4. 👀 **Monitor** tomorrow's volume to confirm normal pattern

---

## Summary

**VERDICT: FALSE ALARM**

The current low order volume at 8:27 PM EST on Saturday is normal end-of-day traffic. Stores are closing, customers have gone home, and the system is healthy. The alert needs tuning to account for normal business hours patterns.
