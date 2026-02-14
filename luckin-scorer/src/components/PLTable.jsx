import React from 'react';

export default function PLTable({ pl }) {
  const rows = [
    { label: '月收入 Revenue', value: pl.revenue, type: 'revenue' },
    { label: '原料成本 COGS', value: -pl.cogs, type: 'cost' },
    { label: '人工成本 Labor', value: -pl.labor, type: 'cost' },
    { label: '月租金 Rent', value: -pl.rent, type: 'cost' },
    { label: '其他 Supplies/Other', value: -pl.supplies, type: 'cost' },
    { label: '净利润 Net Profit', value: pl.profit, type: 'profit' },
  ];

  const fmt = (v) => {
    const abs = Math.abs(v);
    const str = '$' + abs.toLocaleString();
    return v < 0 ? `-${str}` : str;
  };

  return (
    <div>
      <h3 className="text-sm font-semibold text-text-secondary mb-3">损益表 P&L Statement</h3>
      <div className="border border-border rounded-lg overflow-hidden">
        <table className="w-full text-sm">
          <tbody>
            {rows.map((row) => {
              const isProfit = row.type === 'profit';
              const profitColor = row.value >= 0 ? 'text-accent-green' : 'text-accent-red';
              return (
                <tr
                  key={row.label}
                  className={`border-b border-border last:border-0 ${isProfit ? 'bg-gray-50 font-bold' : ''}`}
                >
                  <td className="px-4 py-2.5 text-text-secondary">{row.label}</td>
                  <td className={`px-4 py-2.5 text-right metric-value ${isProfit ? profitColor : row.type === 'cost' ? 'text-accent-red' : 'text-text-primary'}`}>
                    {fmt(row.value)}
                  </td>
                </tr>
              );
            })}
          </tbody>
        </table>
      </div>

      {/* KPI row */}
      <div className="grid grid-cols-3 gap-3 mt-4">
        <KPIBadge
          label="ROI"
          value={`${pl.roi}%`}
          color={pl.roi > 15 ? '#059669' : pl.roi > 0 ? '#D97706' : '#DC2626'}
        />
        <KPIBadge
          label="盈亏平衡 Breakeven"
          value={`${pl.breakeven_cups_per_day} 杯/天`}
        />
        <KPIBadge
          label="租收比 Rent/Rev"
          value={`${pl.rent_to_revenue}%`}
          color={pl.rent_to_revenue > 25 ? '#DC2626' : '#059669'}
        />
      </div>
    </div>
  );
}

function KPIBadge({ label, value, color }) {
  return (
    <div className="bg-bg rounded-lg px-3 py-2 text-center border border-border">
      <div className="text-xs text-text-muted">{label}</div>
      <div className="text-sm font-bold metric-value" style={color ? { color } : {}}>
        {value}
      </div>
    </div>
  );
}
