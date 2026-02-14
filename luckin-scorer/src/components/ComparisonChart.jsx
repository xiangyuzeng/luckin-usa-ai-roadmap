import React from 'react';
import { BarChart, Bar, XAxis, YAxis, Tooltip, Cell, ResponsiveContainer, ReferenceLine } from 'recharts';
import { STORES, PIPELINE } from '../lib/constants.js';

export default function ComparisonChart({ predictedDailyCups, locationName }) {
  // Build comparison data: existing stores + top pipeline + candidate
  const storeData = STORES.map((s) => ({
    name: s.name,
    cups: s.avg_daily_cups,
    type: 'active',
  }));

  const pipelineData = PIPELINE.slice(0, 3).map((p) => ({
    name: p.name,
    cups: p.projected_daily_cups,
    type: 'pipeline',
  }));

  const candidate = {
    name: '候选 Candidate',
    cups: predictedDailyCups,
    type: 'candidate',
  };

  const allData = [...storeData, ...pipelineData, candidate]
    .sort((a, b) => b.cups - a.cups);

  const colorMap = {
    active: '#0891B2',
    pipeline: '#9CA3AF',
    candidate: '#7C3AED',
  };

  return (
    <div>
      <h3 className="text-sm font-semibold text-text-secondary mb-3">门店对比 Store Comparison (杯/天 cups/day)</h3>
      <ResponsiveContainer width="100%" height={300}>
        <BarChart data={allData} layout="vertical" margin={{ left: 10, right: 20 }}>
          <XAxis type="number" fontSize={11} tickFormatter={(v) => v.toLocaleString()} />
          <YAxis type="category" dataKey="name" fontSize={11} width={110} />
          <Tooltip
            formatter={(value) => [`${value} 杯/天`, '日均杯数']}
            contentStyle={{ fontSize: 12, borderRadius: 8 }}
          />
          <Bar dataKey="cups" radius={[0, 4, 4, 0]}>
            {allData.map((entry, idx) => (
              <Cell
                key={idx}
                fill={colorMap[entry.type]}
                fillOpacity={entry.type === 'candidate' ? 1 : 0.75}
                stroke={entry.type === 'candidate' ? '#7C3AED' : 'none'}
                strokeWidth={entry.type === 'candidate' ? 2 : 0}
              />
            ))}
          </Bar>
        </BarChart>
      </ResponsiveContainer>
      <div className="flex gap-4 justify-center mt-2 text-xs text-text-muted">
        <span className="flex items-center gap-1"><span className="w-3 h-3 rounded" style={{ backgroundColor: '#0891B2' }} /> 现有门店 Active</span>
        <span className="flex items-center gap-1"><span className="w-3 h-3 rounded" style={{ backgroundColor: '#9CA3AF' }} /> 在建 Pipeline</span>
        <span className="flex items-center gap-1"><span className="w-3 h-3 rounded" style={{ backgroundColor: '#7C3AED' }} /> 候选 Candidate</span>
      </div>
    </div>
  );
}
