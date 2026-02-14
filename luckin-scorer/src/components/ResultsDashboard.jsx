import React from 'react';
import ScoreGauge from './ScoreGauge.jsx';
import FactorBreakdown from './FactorBreakdown.jsx';
import PLTable from './PLTable.jsx';
import CannibWarning from './CannibWarning.jsx';
import ComparisonChart from './ComparisonChart.jsx';
import { MODEL } from '../lib/constants.js';

export default function ResultsDashboard({ results, onBack }) {
  const { prediction, score, pl, warnings, features, enriched, formData } = results;

  const riskColors = {
    Strong: { bg: 'bg-green-50', text: 'text-accent-green', border: 'border-green-200', label: '强 Strong' },
    Viable: { bg: 'bg-amber-50', text: 'text-amber-600', border: 'border-amber-200', label: '可行 Viable' },
    Risky: { bg: 'bg-red-50', text: 'text-accent-red', border: 'border-red-200', label: '高风险 Risky' },
  };
  const risk = riskColors[pl.risk_flag] || riskColors.Risky;

  return (
    <div className="min-h-screen bg-bg">
      {/* Header */}
      <header className="bg-white border-b border-border px-6 py-4 no-print">
        <div className="max-w-6xl mx-auto flex items-center justify-between">
          <div>
            <h1 className="text-xl font-bold text-text-primary">☕ 选址评估报告</h1>
            <p className="text-sm text-text-muted">{enriched.formatted_address}</p>
          </div>
          <div className="flex gap-2">
            <button
              onClick={() => window.print()}
              className="px-4 py-2 text-sm border border-border rounded-lg hover:bg-gray-50 transition-colors"
            >
              🖨 打印 Print
            </button>
            <button
              onClick={onBack}
              className="px-4 py-2 text-sm bg-accent-teal text-white rounded-lg hover:bg-accent-teal/90 transition-colors no-print"
            >
              ← 返回 Back
            </button>
          </div>
        </div>
      </header>

      <main className="max-w-6xl mx-auto px-4 py-6">
        {/* Warnings */}
        {warnings.length > 0 && (
          <div className="mb-6 space-y-2 no-print">
            {warnings.map((w, i) => (
              <div
                key={i}
                className={`px-4 py-3 rounded-lg border text-sm ${
                  w.severity === 'danger'
                    ? 'bg-red-50 border-red-200 text-red-700'
                    : 'bg-amber-50 border-amber-200 text-amber-700'
                }`}
              >
                <span className="font-medium">⚠ {w.text}</span>
                <span className="block text-xs mt-0.5 opacity-75">{w.textEn}</span>
              </div>
            ))}
          </div>
        )}

        {/* Grid layout */}
        <div className="grid grid-cols-1 md:grid-cols-2 gap-6">

          {/* Card 1: Header Score */}
          <div className="bg-card border border-border rounded-card p-6 md:col-span-2">
            <div className="flex flex-col md:flex-row items-center justify-between gap-6">
              <div className="flex-1 flex flex-col items-center">
                <ScoreGauge score={score.total} label="综合评分 Total Score" />
              </div>

              <div className="flex-1 text-center md:text-left">
                <div className="mb-4">
                  <p className="text-sm text-text-muted mb-1">预测日均杯数 Predicted Daily Cups</p>
                  <p className="text-5xl font-bold metric-value text-text-primary">
                    {prediction.predicted_daily_cups}
                  </p>
                  <p className="text-sm text-text-muted mt-1">
                    周均 Weekly: {prediction.predicted_weekly_cups.toLocaleString()} 杯
                  </p>
                </div>

                <div className={`inline-flex items-center gap-2 px-4 py-2 rounded-lg border ${risk.bg} ${risk.border}`}>
                  <span className={`text-sm font-bold ${risk.text}`}>{risk.label}</span>
                  <span className="text-xs text-text-muted">ROI: {pl.roi}%</span>
                </div>
              </div>

              <div className="flex-1">
                <div className="bg-bg rounded-lg p-4 border border-border">
                  <p className="text-xs text-text-muted mb-2">90% 置信区间 Confidence Interval</p>
                  <div className="flex items-center gap-2">
                    <span className="text-sm metric-value text-text-secondary">{prediction.cups_lower_90}</span>
                    <div className="flex-1 h-3 bg-gray-200 rounded-full relative">
                      <div
                        className="absolute h-full bg-accent-teal/30 rounded-full"
                        style={{
                          left: `${(prediction.cups_lower_90 / (prediction.cups_upper_90 * 1.1)) * 100}%`,
                          right: `${100 - (prediction.cups_upper_90 / (prediction.cups_upper_90 * 1.1)) * 100}%`,
                        }}
                      />
                      <div
                        className="absolute w-2.5 h-full bg-accent-teal rounded-full"
                        style={{ left: `${(prediction.predicted_weekly_cups / (prediction.cups_upper_90 * 1.1)) * 100}%` }}
                      />
                    </div>
                    <span className="text-sm metric-value text-text-secondary">{prediction.cups_upper_90}</span>
                  </div>
                  <p className="text-xs text-text-muted mt-2">杯/周 cups/week | RMSE: {MODEL.metrics.rmse.toFixed(1)}</p>
                </div>
              </div>
            </div>
          </div>

          {/* Card 2: Factor Breakdown */}
          <div className="bg-card border border-border rounded-card p-6">
            <FactorBreakdown breakdown={score.breakdown} />
          </div>

          {/* Card 3: P&L */}
          <div className="bg-card border border-border rounded-card p-6">
            <PLTable pl={pl} />
          </div>

          {/* Card 4: Cannibalization */}
          <div className="bg-card border border-border rounded-card p-6">
            <CannibWarning
              nearestStores={score.nearest_stores}
              nearestDistanceMi={score.nearest_distance_mi}
            />
          </div>

          {/* Card 5: Comparison Chart */}
          <div className="bg-card border border-border rounded-card p-6">
            <ComparisonChart
              predictedDailyCups={prediction.predicted_daily_cups}
              locationName={enriched.formatted_address}
            />
          </div>

          {/* Card 6: Input Summary & Model Caveats */}
          <div className="bg-card border border-border rounded-card p-6 md:col-span-2">
            <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
              {/* Input Summary */}
              <div>
                <h3 className="text-sm font-semibold text-text-secondary mb-3">输入摘要 Input Summary</h3>
                <div className="grid grid-cols-2 gap-2 text-sm">
                  <SummaryItem label="地址 Address" value={formData.address} span />
                  <SummaryItem label="区域类型 Area Type" value={formData.area_type} />
                  <SummaryItem label="月租金 Rent" value={`$${formData.rent_monthly?.toLocaleString()}`} />
                  <SummaryItem label="面积 Sqft" value={formData.sqft} />
                  <SummaryItem label="工作日% Weekday" value={`${(formData.weekday_pct * 100).toFixed(0)}%`} />
                  <SummaryItem label="坐标 Coordinates" value={`${enriched.lat?.toFixed(4)}, ${enriched.lon?.toFixed(4)}`} />
                  <SummaryItem label="收入 Income" value={enriched.medianIncome ? `$${enriched.medianIncome.toLocaleString()}` : 'N/A'} />
                  <SummaryItem label="地铁 Subway" value={`${enriched.subwayCount} 线`} />
                  <SummaryItem label="步行分 Walk" value={enriched.walkScore ?? 'N/A'} />
                  <SummaryItem label="竞品 Competitors" value={enriched.competitorDensity ?? 'N/A'} />
                </div>
              </div>

              {/* Model Caveats */}
              <div>
                <h3 className="text-sm font-semibold text-text-secondary mb-3">模型说明 Model Caveats</h3>
                <ul className="text-xs text-text-muted space-y-2">
                  <li>• 模型基于8家曼哈顿门店训练 (R²={MODEL.metrics.r2.toFixed(3)}, MAPE={MODEL.metrics.mape.toFixed(1)}%)</li>
                  <li>• Trained on 8 Manhattan stores; non-Manhattan predictions are extrapolations</li>
                  <li>• 置信区间使用 RMSE={MODEL.metrics.rmse.toFixed(1)} 的 1.645 倍标准差计算</li>
                  <li>• 90% CI uses ±1.645 × RMSE heuristic (not bootstrap)</li>
                  <li>• 实际表现受季节、天气、营销活动等因素影响</li>
                  <li>• Actual performance affected by seasonality, weather, marketing</li>
                  <li>• 单位经济假设: 杯价$5.50, 毛利$2.30, 人工$15K/月</li>
                </ul>
              </div>
            </div>
          </div>

        </div>
      </main>
    </div>
  );
}

function SummaryItem({ label, value, span }) {
  return (
    <div className={span ? 'col-span-2' : ''}>
      <span className="text-text-muted text-xs">{label}</span>
      <p className="text-text-primary font-medium text-sm truncate">{value}</p>
    </div>
  );
}
