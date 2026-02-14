import React from 'react';

export default function CannibWarning({ nearestStores, nearestDistanceMi }) {
  if (!nearestStores || nearestStores.length === 0) return null;

  const top3 = nearestStores.slice(0, 3);

  let severity, severityLabel, severityColor, bgColor, borderColor;
  if (nearestDistanceMi < 0.15) {
    severity = 'critical';
    severityLabel = '严重 Critical';
    severityColor = 'text-accent-red';
    bgColor = 'bg-red-50';
    borderColor = 'border-red-200';
  } else if (nearestDistanceMi < 0.25) {
    severity = 'high';
    severityLabel = '高风险 High';
    severityColor = 'text-orange-600';
    bgColor = 'bg-orange-50';
    borderColor = 'border-orange-200';
  } else if (nearestDistanceMi < 0.50) {
    severity = 'moderate';
    severityLabel = '中等 Moderate';
    severityColor = 'text-amber-600';
    bgColor = 'bg-amber-50';
    borderColor = 'border-amber-200';
  } else {
    severity = 'low';
    severityLabel = '低 Low';
    severityColor = 'text-accent-green';
    bgColor = 'bg-green-50';
    borderColor = 'border-green-200';
  }

  // Impact estimate: closer = higher cannibalization
  const impactPct = nearestDistanceMi < 0.15 ? 25
    : nearestDistanceMi < 0.25 ? 18
    : nearestDistanceMi < 0.50 ? 10
    : 3;

  return (
    <div>
      <h3 className="text-sm font-semibold text-text-secondary mb-3">自噬分析 Cannibalization Analysis</h3>

      {/* Severity banner */}
      <div className={`${bgColor} ${borderColor} border rounded-lg px-4 py-3 mb-4`}>
        <div className="flex items-center justify-between">
          <span className={`text-sm font-semibold ${severityColor}`}>
            风险等级: {severityLabel}
          </span>
          <span className="text-xs text-text-muted">
            预估影响 Est. impact: ~{impactPct}% 销量分流
          </span>
        </div>
        <p className="text-xs text-text-secondary mt-1">
          最近门店距离 Nearest store: {nearestDistanceMi.toFixed(2)} mi
        </p>
      </div>

      {/* Nearest stores table */}
      <div className="border border-border rounded-lg overflow-hidden">
        <table className="w-full text-sm">
          <thead className="bg-gray-50">
            <tr>
              <th className="px-3 py-2 text-left text-xs text-text-muted font-medium">门店 Store</th>
              <th className="px-3 py-2 text-right text-xs text-text-muted font-medium">距离 Distance</th>
              <th className="px-3 py-2 text-right text-xs text-text-muted font-medium">日均杯数 Cups/Day</th>
            </tr>
          </thead>
          <tbody>
            {top3.map((store) => (
              <tr key={store.name} className="border-t border-border">
                <td className="px-3 py-2 text-text-primary">{store.name}</td>
                <td className="px-3 py-2 text-right metric-value">
                  {store.distance_mi.toFixed(2)} mi
                </td>
                <td className="px-3 py-2 text-right metric-value font-medium">
                  {store.cups}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}
