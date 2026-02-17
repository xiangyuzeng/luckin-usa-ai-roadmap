export const ALERTS = [
  {
    severity: 'CRITICAL',
    color: '#ef4444',
    ts: '2026-02-14 23:15',
    en: 'Store 20027 (21st & 3rd) MAPE exceeded 40% threshold for 5 consecutive days',
    cn: '门店20027（21st & 3rd）MAPE连续5天超过40%阈值',
  },
  {
    severity: 'WARNING',
    color: '#eab308',
    ts: '2026-02-14 18:30',
    en: 'Dairy category MAPE trending upward (+15% WoW)',
    cn: '乳制品类MAPE周环比上升+15%',
  },
  {
    severity: 'BIAS',
    color: '#f97316',
    ts: '2026-02-14 12:00',
    en: 'Store 1128 (28th & 6th) over-predicting for 12 consecutive days (Bias +12.1%)',
    cn: '门店1128（28th & 6th）连续12天预测偏高（偏差+12.1%）',
  },
  {
    severity: 'WARNING',
    color: '#eab308',
    ts: '2026-02-13 22:45',
    en: 'Store 1140 food items MAPE at 52% — investigate promotions / new items',
    cn: '门店1140食品类MAPE达52%，请排查促销/新品影响',
  },
  {
    severity: 'INFO',
    color: '#3b82f6',
    ts: '2026-02-13 09:00',
    en: 'Coverage dropped to 91% for store 20027 — new store ramp-up period',
    cn: '门店20027覆盖率降至91%，新店爬坡期',
  },
  {
    severity: 'INFO',
    color: '#3b82f6',
    ts: '2026-02-12 14:20',
    en: 'System retraining completed — next evaluation window begins Feb 15',
    cn: '系统重新训练完成，下一评估窗口2月15日开始',
  },
];

export const ALERT_THRESHOLDS = {
  critical: { mape7d: 40, label: 'P1 — 7d rolling MAPE > 40%' },
  warning:  { mape7d: 30, label: 'P2 — 7d rolling MAPE > 30%' },
  bias:     { consecutiveDays: 14, label: 'P2 — Same-sign MFE 14+ days' },
  coverage: { minPct: 90, label: 'P2 — Coverage < 90%' },
  drift:    { wowChange: 50, label: 'P3 — WoW MAPE change > 50%' },
};
