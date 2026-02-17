export const systemMetrics = {
  period: { start: '2026-02-01', end: '2026-02-14', days: 14 },
  totalPredictions: 11423,
  mape: { value: 37.8, target: 25, unit: '%' },
  wmape: { value: 30.7, target: 20, unit: '%' },
  rmse: { value: 4521, unit: '' },
  mfe: { value: 9.1, unit: '%', direction: 'over' },
  accuracyRate: { value: 42.3, target: 70, unit: '%' },
  coverage: { value: 94.2, unit: '%' },
  trackingSignal: { value: 2.8, threshold: 4.0, unit: '' },
};

export const mapeDistribution = [
  { range: '<10%', rangeCn: '<10%', pct: 18.2, count: 2079, color: '#22c55e' },
  { range: '10-20%', rangeCn: '10-20%', pct: 24.1, count: 2753, color: '#22c55e' },
  { range: '20-30%', rangeCn: '20-30%', pct: 14.7, count: 1679, color: '#eab308' },
  { range: '30-50%', rangeCn: '30-50%', pct: 19.3, count: 2205, color: '#f97316' },
  { range: '50-100%', rangeCn: '50-100%', pct: 14.2, count: 1622, color: '#ef4444' },
  { range: '>100%', rangeCn: '>100%', pct: 9.5, count: 1085, color: '#dc2626' },
];

export const summaryInsights = [
  { en: '42.3% of predictions within ±20% accuracy', cn: '42.3%的预测在±20%准确率范围内' },
  { en: '9.5% have >100% error (long tail problem)', cn: '9.5%的误差超过100%（长尾问题）' },
  { en: 'Systematic over-prediction bias of +9.1%', cn: '系统性过度预测偏差+9.1%' },
  { en: 'Weekend MAPE 43.1% vs Weekday 35.2% (7.9pp gap)', cn: '周末MAPE 43.1% vs 工作日35.2%（差距7.9个百分点）' },
];
