# ElastiCache Notification Action Plan

**Date**: 2026-02-11
**AWS Account**: 257394478466
**Region**: us-east-1
**Requested By**: Manager 于伯伟

---

## Task A: SNS Subscriber Management

### Current Status: BLOCKED - IAM Permission Required

```
Error: User arn:aws:iam::257394478466:user/databasecheck is not authorized to perform:
SNS:Subscribe on resource: arn:aws:sns:us-east-1:257394478466:DBA
```

### Required IAM Permissions

Add the following policy to the `databasecheck` user or use an account with SNS permissions:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "sns:Subscribe",
        "sns:ListSubscriptionsByTopic",
        "sns:Unsubscribe"
      ],
      "Resource": "arn:aws:sns:us-east-1:257394478466:DBA"
    }
  ]
}
```

### Commands to Execute (once permissions granted)

```bash
# Subscribe 翔宇 (Xiangyu)
aws sns subscribe \
  --topic-arn arn:aws:sns:us-east-1:257394478466:DBA \
  --protocol email \
  --notification-endpoint xiangyu.zeng@lkcoffee.com \
  --region us-east-1

# Subscribe 东尧 (Dongyao) - NEED EMAIL ADDRESS
aws sns subscribe \
  --topic-arn arn:aws:sns:us-east-1:257394478466:DBA \
  --protocol email \
  --notification-endpoint <dongyao.xxx@lkcoffee.com> \
  --region us-east-1

# Verify subscriptions
aws sns list-subscriptions-by-topic \
  --topic-arn arn:aws:sns:us-east-1:257394478466:DBA \
  --region us-east-1
```

### Action Required

| Person | Email | Status |
|--------|-------|--------|
| 翔宇 (Xiangyu) | xiangyu.zeng@lkcoffee.com | Ready to add (need IAM permission) |
| 东尧 (Dongyao) | **NEED EMAIL ADDRESS** | Please provide email |

**Note**: Each subscriber must click the AWS confirmation email to activate.

---

## Task B: Notification Frequency Analysis

### DBA SNS Topic - Cluster Inventory

Only **3 clusters** (6 nodes) send notifications to the DBA topic:

| Cluster | Nodes | SNS Topic | Snapshot Window |
|---------|-------|-----------|-----------------|
| luckyus-iopenlinker | -001, -002 | **DBA** | 09:00-10:00 UTC |
| luckyus-iopenlinkeradmin | -001, -002 | **DBA** | 09:00-10:00 UTC |
| luckyus-ilopamanager | -001, -002 | **DBA** | 09:00-10:00 UTC |

**Other clusters** (14 nodes from 7 clusters) use: `Default_CloudWatch_Alarms_Topic_wechat`

### Snapshot Frequency Analysis

| Cluster | Snapshots Found | Frequency | Data Size |
|---------|-----------------|-----------|-----------|
| luckyus-iopenlinker-002 | 3 (Feb 8-10) | **Daily** | 19-21 MB |
| luckyus-iopenlinkeradmin-002 | 3 (Feb 8-10) | **Daily** | 7 MB |
| luckyus-ilopamanager-002 | 3 (Feb 8-10) | **Daily** | 2 MB |

**Actual snapshot timestamps**:
```
luckyus-ilopamanager-002:      Feb 8 09:14, Feb 9 09:13, Feb 10 09:13
luckyus-iopenlinker-002:       Feb 8 09:14, Feb 9 09:13, Feb 10 09:14
luckyus-iopenlinkeradmin-002:  Feb 8 09:14, Feb 9 09:13, Feb 10 09:13
```

### Notification Volume to DBA Topic

| Metric | Value |
|--------|-------|
| **Daily SnapshotComplete notifications** | 3 (one per cluster) |
| **Weekly notifications** | 21 |
| **Monthly notifications** | ~90 |
| **Notification time** | 09:13-09:15 UTC daily |

### Working Hours Impact Analysis

| Time Zone | Snapshot Window (09:00-10:00 UTC) | Impact |
|-----------|-----------------------------------|--------|
| **UTC** | 09:00-10:00 | - |
| **US Eastern (EST/EDT)** | **04:00-05:00 AM** | Very early morning |
| **China (CST)** | **17:00-18:00** | **Working hours!** |

**Conclusion**: Snapshot notifications arrive during **China working hours (5-6 PM)**

---

## Task C: Recommendation & Ready-to-Run Commands

### Recommendation: **KEEP NOTIFICATIONS ACTIVE** (with caveats)

| Factor | Assessment |
|--------|------------|
| Notification volume | Low (3/day to DBA topic) |
| Noise level | **Minimal** - only 3 clusters, not 77 |
| Timing | During China working hours |
| Value | Confirms backups are running |
| Risk of disabling | Might miss backup failures |

### Option 1: Keep Current Configuration (RECOMMENDED)

**Reasoning**:
- Only 3 notifications per day is manageable
- Provides confirmation that backups are completing
- Helps detect backup failures early
- Consider setting up email filtering rules instead

### Option 2: Disable SnapshotComplete Notifications

If the team decides the daily notifications are noise, here are the commands to disable them:

```bash
# ⚠️ DO NOT EXECUTE WITHOUT APPROVAL ⚠️

# Disable notifications for luckyus-iopenlinker
aws elasticache modify-replication-group \
  --replication-group-id luckyus-iopenlinker \
  --notification-topic-status inactive \
  --region us-east-1

# Disable notifications for luckyus-iopenlinkeradmin
aws elasticache modify-replication-group \
  --replication-group-id luckyus-iopenlinkeradmin \
  --notification-topic-status inactive \
  --region us-east-1

# Disable notifications for luckyus-ilopamanager
aws elasticache modify-replication-group \
  --replication-group-id luckyus-ilopamanager \
  --notification-topic-status inactive \
  --region us-east-1
```

**Impact if executed**:
- No more SnapshotComplete emails from these 3 clusters
- No more failure/maintenance notifications either
- Backup process continues unchanged (just no email)

### Option 3: Alternative - Change Snapshot Window (NOT RECOMMENDED)

Moving snapshots to a different time wouldn't reduce notifications, just change when they arrive.

---

## Summary

| Task | Status | Action Required |
|------|--------|-----------------|
| **A: Add SNS Subscribers** | BLOCKED | Need IAM permissions + Dongyao's email |
| **B: Notification Analysis** | COMPLETE | 3 notifications/day, China working hours |
| **C: Suppress Notifications** | PENDING APPROVAL | Commands ready, recommend KEEP active |

### Immediate Actions Needed

1. **Provide Dongyao's email address** (dongyao.xxx@lkcoffee.com)
2. **Grant SNS permissions** to `databasecheck` user (or use different account)
3. **Confirm decision**: Keep notifications active or suppress?

### Questions for Manager 于伯伟

1. Should we disable ALL notifications (including failure/maintenance), or just filter SnapshotComplete at the email level?
2. Are there other clusters that should also notify the DBA topic?
3. What is Dongyao's email address?

---

## Appendix: Full SNS Topic Mapping

### DBA Topic (target of this investigation)
```
Clusters: 3
Daily notifications: 3
luckyus-iopenlinker-001, luckyus-iopenlinker-002
luckyus-iopenlinkeradmin-001, luckyus-iopenlinkeradmin-002
luckyus-ilopamanager-001, luckyus-ilopamanager-002
```

### Default_CloudWatch_Alarms_Topic_wechat (separate topic)
```
Clusters: 7 (14 nodes)
luckyus-auth-001, luckyus-auth-002
luckyus-authservice-001, luckyus-authservice-002
luckyus-cmdb-001, luckyus-cmdb-002
luckyus-ldas-001, luckyus-ldas-002
luckyus-session-001, luckyus-session-002
luckyus-waf-001, luckyus-waf-002
luckyus-web-001, luckyus-web-002
```

### No SNS Notifications Configured
```
Remaining 67+ clusters have no active SNS notifications
(Snapshots still occur, just no email notifications)
```
