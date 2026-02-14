import React from 'react';
import { BarChart, Bar, XAxis, YAxis, Tooltip, Cell, ResponsiveContainer, ReferenceLine } from 'recharts';

const FACTOR_META = {
  area_type: { label: '区域类型 Area Type', max: 35, color: '#0891B2' },
  subway: { label: '地铁 Subway Access', max: 20, color: '#7C3AED' },
  weekend: { label: '周末韧性 Weekend', max: 15, color: '#D97706' },
  cannibalization: { label: '自噬风险 Cannib.', max: -15, color: '#DC2626' },
  rent: { label: '租金价值 Rent Value', max: 15, color: '#059669' },
};

export default function FactorBreakdown({ breakdown }) {
  const data = Object.entries(breakdown).map(([key, value]) => {
    const meta = FACTOR_META[key];
    return {
      name: meta.label,
      score: value,
      max: Math.abs(meta.max),
      color: meta.color,
      isNegative: meta.max < 0,
    };
  });

  return (
    <div>
      <h3 className="text-sm font-semibold text-text-secondary mb-3">五维评分 Factor Breakdown</h3>
      <div className="space-y-3">
        {data.map((item) => (
          <div key={item.name} className="flex items-center gap-3">
            <div className="w-36 text-xs text-text-secondary truncate">{item.name}</div>
            <div className="flex-1 h-5 bg-gray-100 rounded-full relative overflow-hidden">
              {item.isNegative ? (
                // Negative factor: show penalty from right
                <div
                  className="absolute right-0 top-0 h-full rounded-full opacity-80"
                  style={{
                    width: `${(Math.abs(item.score) / item.max) * 100}%`,
                    backgroundColor: item.color,
                  }}
                />
              ) : (
                <div
                  className="absolute left-0 top-0 h-full rounded-full"
                  style={{
                    width: `${(item.score / item.max) * 100}%`,
                    backgroundColor: item.color,
                  }}
                />
              )}
            </div>
            <div className="w-16 text-right text-xs font-mono font-medium" style={{ color: item.color }}>
              {item.score > 0 ? '+' : ''}{item.score} / {item.isNegative ? `-${item.max}` : item.max}
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}
