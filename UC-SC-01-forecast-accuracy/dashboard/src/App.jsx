import React, { useState, useMemo } from 'react';
import {
  LineChart, Line, BarChart, Bar, XAxis, YAxis, CartesianGrid,
  Tooltip, Legend, ResponsiveContainer, ReferenceLine, Cell,
  PieChart, Pie, RadarChart, Radar, PolarGrid, PolarAngleAxis,
  PolarRadiusAxis, ComposedChart, Area,
} from 'recharts';

import { systemMetrics, mapeDistribution, summaryInsights } from './data/systemMetrics';
import { STORES, STORES_SORTED, STORE_DAILY_HEATMAP, HEATMAP_DATES } from './data/stores';
import { DAILY_MAPE, WEEKDAY_VS_WEEKEND } from './data/dailyTrend';
import { CATEGORIES } from './data/categories';
import { ALERTS } from './data/alerts';
import { WORST_PRODUCTS, BEST_PRODUCTS } from './data/products';

// ---------------------------------------------------------------------------
// HELPERS
// ---------------------------------------------------------------------------
const mapeColor = (v) => {
  if (v <= 20) return '#22c55e';
  if (v <= 30) return '#eab308';
  if (v <= 40) return '#f97316';
  return '#ef4444';
};

const mapeLabel = (v) => {
  if (v <= 20) return 'Good';
  if (v <= 30) return 'Fair';
  if (v <= 40) return 'Warning';
  return 'Critical';
};

const heatmapBg = (v) => {
  if (v <= 25) return 'bg-green-900/60 text-green-300';
  if (v <= 30) return 'bg-green-800/40 text-green-400';
  if (v <= 35) return 'bg-yellow-900/40 text-yellow-300';
  if (v <= 40) return 'bg-orange-900/40 text-orange-300';
  if (v <= 45) return 'bg-red-900/40 text-red-300';
  return 'bg-red-900/70 text-red-200';
};

const TABS = [
  { id: 'overview', label: 'Overview', labelCn: '概览' },
  { id: 'stores',   label: 'Stores',   labelCn: '门店' },
  { id: 'products', label: 'Products', labelCn: '商品' },
  { id: 'alerts',   label: 'Alerts',   labelCn: '告警' },
];

// ---------------------------------------------------------------------------
// SHARED COMPONENTS
// ---------------------------------------------------------------------------
const ChartTooltip = ({ active, payload, label }) => {
  if (!active || !payload?.length) return null;
  return (
    <div className="bg-dark-card border border-dark-border rounded-lg px-3 py-2 text-xs shadow-xl">
      <p className="font-semibold text-gray-200 mb-1">{label}</p>
      {payload.map((p, i) => (
        <p key={i} style={{ color: p.color }} className="leading-tight">
          {p.name}: {typeof p.value === 'number' ? p.value.toFixed(1) + '%' : p.value}
        </p>
      ))}
    </div>
  );
};

const KPICard = ({ titleEn, titleCn, value, unit, status, target, trend, subtitle }) => {
  const colors = { green: '#22c55e', yellow: '#eab308', red: '#ef4444', blue: '#3b82f6' };
  const c = colors[status] || colors.blue;
  const arrows = { up: '↑', down: '↓', flat: '→' };
  const trendColor = trend === 'down' ? '#22c55e' : trend === 'up' ? '#ef4444' : '#666';

  return (
    <div className="bg-dark-card rounded-xl border border-dark-border relative overflow-hidden flex flex-col gap-1.5 p-5 hover:border-dark-hover transition-colors">
      <div className="absolute top-0 left-0 right-0 h-[3px]" style={{ background: `linear-gradient(90deg, ${c}, ${c}66)` }} />
      <div className="text-xs text-gray-500 leading-snug">
        {titleEn}<br />{titleCn}
      </div>
      <div className="flex items-baseline gap-1.5">
        <span className="text-3xl font-bold leading-none" style={{ color: c }}>
          {value}
        </span>
        {unit && <span className="text-sm text-gray-500">{unit}</span>}
        {trend && (
          <span className="text-lg ml-auto" style={{ color: trendColor }}>
            {arrows[trend] || ''}
          </span>
        )}
      </div>
      <div className="text-[11px] text-gray-600">Target: {target}</div>
      {subtitle && <div className="text-[10px] text-gray-600 mt-0.5">{subtitle}</div>}
    </div>
  );
};

const SectionCard = ({ children, className = '' }) => (
  <div className={`bg-dark-card rounded-xl border border-dark-border p-5 ${className}`}>
    {children}
  </div>
);

const SectionTitle = ({ en, cn, badge }) => (
  <div className="flex items-center gap-3 mb-3">
    <div>
      <h3 className="text-sm font-semibold text-gray-200 tracking-wide">{en}</h3>
      <span className="text-[11px] text-gray-600">{cn}</span>
    </div>
    {badge && (
      <span className="ml-auto text-[10px] font-semibold px-2.5 py-1 rounded-full border" style={{
        color: badge.color, borderColor: badge.color + '44', background: badge.color + '15',
      }}>
        {badge.label}
      </span>
    )}
  </div>
);

// ---------------------------------------------------------------------------
// TAB: OVERVIEW
// ---------------------------------------------------------------------------
const OverviewTab = () => (
  <>
    {/* KPI Cards */}
    <div className="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-5 gap-3 mb-6">
      <KPICard titleEn="Overall MAPE" titleCn="平均绝对百分比误差" value="37.8" unit="%" status="yellow" target="< 25%" trend="up" />
      <KPICard titleEn="WMAPE" titleCn="加权平均绝对误差" value="30.7" unit="%" status="yellow" target="< 20%" trend="flat" />
      <KPICard titleEn="Bias (MFE)" titleCn="偏差（系统性过预测）" value="+9.1" unit="%" status="yellow" target="±5%" trend="up" />
      <KPICard titleEn="Accuracy Rate (±20%)" titleCn="准确率（±20%内）" value="42.3" unit="%" status="red" target="> 70%" trend="down" />
      <KPICard titleEn="Coverage" titleCn="覆盖率" value="94.2" unit="%" status="green" target="> 90%" trend="flat" />
    </div>

    {/* Trend + Store Performance side by side */}
    <div className="grid grid-cols-1 lg:grid-cols-2 gap-5 mb-6">
      {/* Daily MAPE Trend */}
      <SectionCard>
        <SectionTitle en="Daily MAPE Trend (14 Days)" cn="每日MAPE趋势（14天）" />
        <ResponsiveContainer width="100%" height={300}>
          <ComposedChart data={DAILY_MAPE} margin={{ top: 10, right: 20, bottom: 5, left: 0 }}>
            <defs>
              <linearGradient id="mapeArea" x1="0" y1="0" x2="0" y2="1">
                <stop offset="5%" stopColor="#3b82f6" stopOpacity={0.15} />
                <stop offset="95%" stopColor="#3b82f6" stopOpacity={0} />
              </linearGradient>
            </defs>
            <CartesianGrid strokeDasharray="3 3" stroke="#1e1e1e" />
            <XAxis dataKey="date" tick={{ fill: '#666', fontSize: 11 }} />
            <YAxis domain={[20, 50]} tick={{ fill: '#666', fontSize: 11 }} tickFormatter={(v) => `${v}%`} />
            <Tooltip content={<ChartTooltip />} />
            <Legend wrapperStyle={{ fontSize: 11, paddingTop: 8 }} />
            <ReferenceLine y={25} stroke="#22c55e" strokeDasharray="6 4" label={{ value: '25% Target', fill: '#22c55e', fontSize: 10, position: 'insideTopRight' }} />
            <ReferenceLine y={40} stroke="#ef4444" strokeDasharray="6 4" label={{ value: '40% Critical', fill: '#ef4444', fontSize: 10, position: 'insideTopRight' }} />
            <Area type="monotone" dataKey="mape" fill="url(#mapeArea)" stroke="transparent" />
            <Line type="monotone" dataKey="mape" name="Daily MAPE" stroke="#3b82f6" strokeWidth={2} dot={{ r: 3, fill: '#3b82f6' }} activeDot={{ r: 5 }} />
            <Line type="monotone" dataKey="ma7" name="7-Day MA" stroke="#a855f7" strokeWidth={2} strokeDasharray="5 3" dot={false} connectNulls={false} />
          </ComposedChart>
        </ResponsiveContainer>
      </SectionCard>

      {/* Store Performance Bar */}
      <SectionCard>
        <SectionTitle en="Store Performance (MAPE)" cn="门店表现（MAPE）" />
        <ResponsiveContainer width="100%" height={300}>
          <BarChart layout="vertical" data={STORES_SORTED} margin={{ top: 5, right: 30, bottom: 5, left: 10 }}>
            <CartesianGrid strokeDasharray="3 3" stroke="#1e1e1e" />
            <XAxis type="number" domain={[0, 50]} tick={{ fill: '#666', fontSize: 11 }} tickFormatter={(v) => `${v}%`} />
            <YAxis type="category" dataKey="name" width={120} tick={{ fill: '#aaa', fontSize: 11 }} />
            <Tooltip content={<ChartTooltip />} />
            <ReferenceLine x={25} stroke="#22c55e44" strokeDasharray="4 3" />
            <ReferenceLine x={40} stroke="#ef444444" strokeDasharray="4 3" />
            <Bar dataKey="mape" name="MAPE" radius={[0, 4, 4, 0]} barSize={18}>
              {STORES_SORTED.map((s, i) => (
                <Cell key={i} fill={mapeColor(s.mape)} fillOpacity={0.85} />
              ))}
            </Bar>
          </BarChart>
        </ResponsiveContainer>
      </SectionCard>
    </div>

    {/* Category + Distribution side by side */}
    <div className="grid grid-cols-1 lg:grid-cols-2 gap-5 mb-6">
      {/* Category Performance */}
      <SectionCard>
        <SectionTitle en="Category Performance (MAPE)" cn="商品品类表现（MAPE）" />
        <ResponsiveContainer width="100%" height={280}>
          <BarChart data={CATEGORIES} margin={{ top: 10, right: 20, bottom: 5, left: 0 }}>
            <CartesianGrid strokeDasharray="3 3" stroke="#1e1e1e" />
            <XAxis dataKey="name" tick={{ fill: '#666', fontSize: 10, angle: -15, textAnchor: 'end' }} height={55} />
            <YAxis domain={[0, 55]} tick={{ fill: '#666', fontSize: 11 }} tickFormatter={(v) => `${v}%`} />
            <Tooltip content={<ChartTooltip />} />
            <ReferenceLine y={25} stroke="#22c55e44" strokeDasharray="4 3" />
            <ReferenceLine y={40} stroke="#ef444444" strokeDasharray="4 3" />
            <Bar dataKey="mape" name="MAPE" radius={[4, 4, 0, 0]} barSize={36}>
              {CATEGORIES.map((c, i) => (
                <Cell key={i} fill={mapeColor(c.mape)} fillOpacity={0.85} />
              ))}
            </Bar>
          </BarChart>
        </ResponsiveContainer>
        <div className="flex flex-wrap gap-1.5 mt-2">
          {CATEGORIES.map((c) => (
            <span key={c.name} className="bg-dark-bg rounded px-2 py-0.5 text-[11px] text-gray-500 border border-dark-border">
              {c.nameCn} {c.mape}%
            </span>
          ))}
        </div>
      </SectionCard>

      {/* MAPE Distribution Pie */}
      <SectionCard>
        <SectionTitle en="Error Distribution" cn="误差分布" />
        <div className="flex items-center gap-4">
          <ResponsiveContainer width="55%" height={260}>
            <PieChart>
              <Pie
                data={mapeDistribution}
                dataKey="pct"
                nameKey="range"
                cx="50%"
                cy="50%"
                innerRadius={55}
                outerRadius={95}
                strokeWidth={1}
                stroke="#0a0a0a"
              >
                {mapeDistribution.map((entry, i) => (
                  <Cell key={i} fill={entry.color} fillOpacity={0.85} />
                ))}
              </Pie>
              <Tooltip formatter={(v) => `${v}%`} contentStyle={{ background: '#1a1a1a', border: '1px solid #282828', borderRadius: 8, fontSize: 12 }} />
            </PieChart>
          </ResponsiveContainer>
          <div className="flex flex-col gap-1.5 text-xs">
            {mapeDistribution.map((d) => (
              <div key={d.range} className="flex items-center gap-2">
                <span className="w-2.5 h-2.5 rounded-sm flex-shrink-0" style={{ background: d.color }} />
                <span className="text-gray-400 w-16">{d.range}</span>
                <span className="text-gray-300 font-medium tabular-nums">{d.pct}%</span>
                <span className="text-gray-600 tabular-nums">({d.count.toLocaleString()})</span>
              </div>
            ))}
          </div>
        </div>
        <div className="mt-3 pt-3 border-t border-dark-border">
          <div className="text-[11px] text-gray-500 font-medium mb-1.5">Key Insights / 关键发现</div>
          {summaryInsights.map((s, i) => (
            <div key={i} className="flex items-start gap-2 mb-1 text-[11px]">
              <span className="text-accent-blue mt-0.5">•</span>
              <div>
                <span className="text-gray-300">{s.en}</span>
                <span className="text-gray-600 ml-1">/ {s.cn}</span>
              </div>
            </div>
          ))}
        </div>
      </SectionCard>
    </div>

    {/* Weekday vs Weekend */}
    <SectionCard className="mb-6">
      <SectionTitle en="Weekday vs Weekend Performance" cn="工作日 vs 周末表现" badge={{ color: '#f97316', label: `${WEEKDAY_VS_WEEKEND.gap}pp gap` }} />
      <div className="grid grid-cols-2 sm:grid-cols-4 gap-4">
        <div className="bg-dark-bg rounded-lg p-4 border border-dark-border text-center">
          <div className="text-[11px] text-gray-500 mb-1">Weekday MAPE / 工作日</div>
          <div className="text-2xl font-bold" style={{ color: mapeColor(WEEKDAY_VS_WEEKEND.weekday.mape) }}>
            {WEEKDAY_VS_WEEKEND.weekday.mape}%
          </div>
        </div>
        <div className="bg-dark-bg rounded-lg p-4 border border-dark-border text-center">
          <div className="text-[11px] text-gray-500 mb-1">Weekend MAPE / 周末</div>
          <div className="text-2xl font-bold" style={{ color: mapeColor(WEEKDAY_VS_WEEKEND.weekend.mape) }}>
            {WEEKDAY_VS_WEEKEND.weekend.mape}%
          </div>
        </div>
        <div className="bg-dark-bg rounded-lg p-4 border border-dark-border text-center">
          <div className="text-[11px] text-gray-500 mb-1">Weekday WMAPE</div>
          <div className="text-2xl font-bold text-gray-300">{WEEKDAY_VS_WEEKEND.weekday.wmape}%</div>
        </div>
        <div className="bg-dark-bg rounded-lg p-4 border border-dark-border text-center">
          <div className="text-[11px] text-gray-500 mb-1">Weekend WMAPE</div>
          <div className="text-2xl font-bold text-gray-300">{WEEKDAY_VS_WEEKEND.weekend.wmape}%</div>
        </div>
      </div>
    </SectionCard>
  </>
);

// ---------------------------------------------------------------------------
// TAB: STORES
// ---------------------------------------------------------------------------
const StoresTab = () => {
  const [selectedStore, setSelectedStore] = useState(null);

  const storeDetail = selectedStore
    ? STORES.find((s) => s.id === selectedStore)
    : null;

  const storeHeatRow = selectedStore
    ? STORE_DAILY_HEATMAP.find((r) => r.store === selectedStore)
    : null;

  return (
    <>
      {/* Heatmap: Store x Day */}
      <SectionCard className="mb-6">
        <SectionTitle en="Store × Day MAPE Heatmap" cn="门店×日期 MAPE热力图" />
        <div className="overflow-x-auto">
          <table className="w-full text-xs">
            <thead>
              <tr>
                <th className="text-left py-2 px-2 text-gray-500 font-medium sticky left-0 bg-dark-card z-10 min-w-[120px]">Store</th>
                {HEATMAP_DATES.map((d) => (
                  <th key={d} className="text-center py-2 px-1 text-gray-600 font-normal min-w-[52px]">{d}</th>
                ))}
                <th className="text-center py-2 px-2 text-gray-500 font-medium">Avg</th>
              </tr>
            </thead>
            <tbody>
              {STORE_DAILY_HEATMAP.map((row) => {
                const store = STORES.find((s) => s.id === row.store);
                const avg = (row.days.reduce((a, b) => a + b, 0) / row.days.length).toFixed(1);
                return (
                  <tr
                    key={row.store}
                    className={`cursor-pointer transition-colors ${selectedStore === row.store ? 'ring-1 ring-accent-blue/50' : 'hover:bg-dark-hover/30'}`}
                    onClick={() => setSelectedStore(selectedStore === row.store ? null : row.store)}
                  >
                    <td className="py-1.5 px-2 text-gray-300 font-medium sticky left-0 bg-dark-card z-10">
                      <span className="text-gray-500 mr-1">{row.store}</span>
                      {store?.name}
                    </td>
                    {row.days.map((v, i) => (
                      <td key={i} className="py-1 px-0.5">
                        <div className={`heatmap-cell ${heatmapBg(v)}`}>
                          {v.toFixed(0)}
                        </div>
                      </td>
                    ))}
                    <td className="text-center font-semibold tabular-nums" style={{ color: mapeColor(parseFloat(avg)) }}>
                      {avg}%
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
        <div className="flex items-center gap-3 mt-3 text-[10px] text-gray-600">
          <span>Legend:</span>
          {[
            { label: '≤25%', cls: 'bg-green-900/60 text-green-300' },
            { label: '26-30%', cls: 'bg-green-800/40 text-green-400' },
            { label: '31-35%', cls: 'bg-yellow-900/40 text-yellow-300' },
            { label: '36-40%', cls: 'bg-orange-900/40 text-orange-300' },
            { label: '41-45%', cls: 'bg-red-900/40 text-red-300' },
            { label: '>45%', cls: 'bg-red-900/70 text-red-200' },
          ].map((l) => (
            <span key={l.label} className={`${l.cls} px-2 py-0.5 rounded text-[10px]`}>{l.label}</span>
          ))}
        </div>
      </SectionCard>

      {/* Store Detail Panel */}
      {storeDetail && storeHeatRow && (
        <SectionCard className="mb-6">
          <SectionTitle
            en={`Store ${storeDetail.id} — ${storeDetail.name}`}
            cn={`门店 ${storeDetail.id} 详情`}
            badge={{ color: mapeColor(storeDetail.mape), label: mapeLabel(storeDetail.mape) }}
          />
          <div className="grid grid-cols-2 sm:grid-cols-4 gap-4 mb-4">
            <div className="bg-dark-bg rounded-lg p-3 border border-dark-border text-center">
              <div className="text-[11px] text-gray-500">MAPE</div>
              <div className="text-xl font-bold" style={{ color: mapeColor(storeDetail.mape) }}>{storeDetail.mape}%</div>
            </div>
            <div className="bg-dark-bg rounded-lg p-3 border border-dark-border text-center">
              <div className="text-[11px] text-gray-500">WMAPE</div>
              <div className="text-xl font-bold text-gray-300">{storeDetail.wmape}%</div>
            </div>
            <div className="bg-dark-bg rounded-lg p-3 border border-dark-border text-center">
              <div className="text-[11px] text-gray-500">Bias (MFE)</div>
              <div className="text-xl font-bold" style={{ color: storeDetail.bias > 10 ? '#ef4444' : '#eab308' }}>+{storeDetail.bias}%</div>
            </div>
            <div className="bg-dark-bg rounded-lg p-3 border border-dark-border text-center">
              <div className="text-[11px] text-gray-500">Trend</div>
              <div className="text-xl font-bold" style={{ color: storeDetail.trend === 'down' ? '#22c55e' : storeDetail.trend === 'up' ? '#ef4444' : '#666' }}>
                {storeDetail.trend === 'down' ? '↓ Improving' : storeDetail.trend === 'up' ? '↑ Degrading' : '→ Stable'}
              </div>
            </div>
          </div>
          <ResponsiveContainer width="100%" height={200}>
            <LineChart data={storeHeatRow.days.map((v, i) => ({ date: HEATMAP_DATES[i], mape: v }))} margin={{ top: 10, right: 20, bottom: 5, left: 0 }}>
              <CartesianGrid strokeDasharray="3 3" stroke="#1e1e1e" />
              <XAxis dataKey="date" tick={{ fill: '#666', fontSize: 10 }} />
              <YAxis domain={[25, 50]} tick={{ fill: '#666', fontSize: 10 }} tickFormatter={(v) => `${v}%`} />
              <Tooltip content={<ChartTooltip />} />
              <ReferenceLine y={25} stroke="#22c55e44" strokeDasharray="4 3" />
              <ReferenceLine y={40} stroke="#ef444444" strokeDasharray="4 3" />
              <Line type="monotone" dataKey="mape" name="MAPE" stroke={mapeColor(storeDetail.mape)} strokeWidth={2} dot={{ r: 3 }} />
            </LineChart>
          </ResponsiveContainer>
        </SectionCard>
      )}

      {/* Store Comparison Table */}
      <SectionCard>
        <SectionTitle en="Store Comparison Table" cn="门店对比表" />
        <div className="overflow-x-auto">
          <table className="w-full text-sm">
            <thead>
              <tr className="border-b border-dark-border">
                {['Store ID', 'Name', 'MAPE', 'WMAPE', 'Bias', 'Status', 'Trend'].map((h) => (
                  <th key={h} className="text-left py-2.5 px-3 text-gray-500 text-xs font-semibold">{h}</th>
                ))}
              </tr>
            </thead>
            <tbody>
              {STORES_SORTED.map((s) => (
                <tr
                  key={s.id}
                  className="border-b border-dark-border/50 hover:bg-dark-hover/30 cursor-pointer transition-colors"
                  onClick={() => setSelectedStore(selectedStore === s.id ? null : s.id)}
                >
                  <td className="py-2 px-3 font-mono text-accent-blue text-xs">{s.id}</td>
                  <td className="py-2 px-3 text-gray-300">{s.name}</td>
                  <td className="py-2 px-3 font-semibold tabular-nums" style={{ color: mapeColor(s.mape) }}>{s.mape}%</td>
                  <td className="py-2 px-3 text-gray-400 tabular-nums">{s.wmape}%</td>
                  <td className="py-2 px-3 text-gray-400 tabular-nums">+{s.bias}%</td>
                  <td className="py-2 px-3">
                    <span className="text-[10px] font-semibold px-2 py-0.5 rounded-full" style={{
                      color: mapeColor(s.mape),
                      background: mapeColor(s.mape) + '18',
                      border: `1px solid ${mapeColor(s.mape)}44`,
                    }}>
                      {mapeLabel(s.mape)}
                    </span>
                  </td>
                  <td className="py-2 px-3">
                    <span style={{ color: s.trend === 'down' ? '#22c55e' : s.trend === 'up' ? '#ef4444' : '#666' }}>
                      {s.trend === 'down' ? '↓' : s.trend === 'up' ? '↑' : '→'}
                    </span>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </SectionCard>
    </>
  );
};

// ---------------------------------------------------------------------------
// TAB: PRODUCTS
// ---------------------------------------------------------------------------
const ProductsTab = () => {
  const [showBest, setShowBest] = useState(false);
  const products = showBest ? BEST_PRODUCTS : WORST_PRODUCTS;

  return (
    <>
      {/* Toggle */}
      <div className="flex gap-2 mb-5">
        <button
          onClick={() => setShowBest(false)}
          className={`px-4 py-1.5 rounded-lg text-xs font-medium transition-colors ${!showBest ? 'bg-accent-red/20 text-red-400 border border-red-500/30' : 'bg-dark-card text-gray-500 border border-dark-border hover:bg-dark-hover'}`}
        >
          Top 10 Worst / 误差最大
        </button>
        <button
          onClick={() => setShowBest(true)}
          className={`px-4 py-1.5 rounded-lg text-xs font-medium transition-colors ${showBest ? 'bg-green-500/20 text-green-400 border border-green-500/30' : 'bg-dark-card text-gray-500 border border-dark-border hover:bg-dark-hover'}`}
        >
          Top 5 Best / 最准确
        </button>
      </div>

      {/* Product Table */}
      <SectionCard className="mb-6">
        <SectionTitle
          en={showBest ? 'Top 5 Best Predicted Products' : 'Top 10 Worst Predicted Products'}
          cn={showBest ? '预测最准确的前5个商品' : '预测误差最大的前10个商品'}
        />
        <div className="overflow-x-auto">
          <table className="w-full text-sm">
            <thead>
              <tr className="border-b border-dark-border">
                {[
                  { en: '#', cn: '排名' },
                  { en: 'Code', cn: '编码' },
                  { en: 'Product', cn: '商品' },
                  { en: 'Category', cn: '品类' },
                  { en: 'MAPE', cn: '误差' },
                  { en: 'Bias', cn: '偏差' },
                  { en: 'Avg Err', cn: '日均误差' },
                ].map((h) => (
                  <th key={h.en} className="text-left py-2.5 px-3 text-gray-500 text-xs font-semibold whitespace-nowrap">
                    {h.en}<br /><span className="text-gray-700 font-normal">{h.cn}</span>
                  </th>
                ))}
              </tr>
            </thead>
            <tbody>
              {products.map((p) => (
                <tr key={p.rank} className="border-b border-dark-border/30 hover:bg-dark-hover/30 transition-colors">
                  <td className="py-2.5 px-3">
                    <span className={`inline-flex items-center justify-center w-6 h-6 rounded-full text-[11px] font-bold ${
                      !showBest && p.rank <= 3
                        ? 'bg-red-500/15 text-red-400 border border-red-500/30'
                        : showBest && p.rank <= 3
                        ? 'bg-green-500/15 text-green-400 border border-green-500/30'
                        : 'bg-dark-border text-gray-500 border border-dark-hover'
                    }`}>
                      {p.rank}
                    </span>
                  </td>
                  <td className="py-2.5 px-3 font-mono text-accent-blue text-xs">{p.code}</td>
                  <td className="py-2.5 px-3">
                    <div className="text-gray-200">{p.name}</div>
                    <div className="text-gray-600 text-[11px]">{p.nameCn}</div>
                  </td>
                  <td className="py-2.5 px-3 text-gray-500 text-xs">{p.cat}</td>
                  <td className="py-2.5 px-3 font-semibold tabular-nums" style={{ color: mapeColor(p.mape) }}>
                    {p.mape.toFixed(1)}%
                  </td>
                  <td className="py-2.5 px-3">
                    <span className={`text-[11px] font-semibold px-2 py-0.5 rounded ${
                      p.biasDir === 'Over'
                        ? 'bg-orange-500/15 text-orange-400 border border-orange-500/30'
                        : 'bg-blue-500/15 text-blue-400 border border-blue-500/30'
                    }`}>
                      {p.biasDir === 'Over' ? '↑ Over' : '↓ Under'}
                    </span>
                  </td>
                  <td className="py-2.5 px-3 text-gray-400 tabular-nums">{p.avgErr.toFixed(1)} units</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </SectionCard>

      {/* Category Radar */}
      <SectionCard>
        <SectionTitle en="Category Radar — MAPE by Product Type" cn="品类雷达图 — 各类MAPE" />
        <ResponsiveContainer width="100%" height={320}>
          <RadarChart data={CATEGORIES.map((c) => ({ subject: c.name, mape: c.mape, wmape: c.wmape }))}>
            <PolarGrid stroke="#282828" />
            <PolarAngleAxis dataKey="subject" tick={{ fill: '#888', fontSize: 10 }} />
            <PolarRadiusAxis angle={30} domain={[0, 50]} tick={{ fill: '#555', fontSize: 10 }} />
            <Radar name="MAPE" dataKey="mape" stroke="#3b82f6" fill="#3b82f6" fillOpacity={0.2} />
            <Radar name="WMAPE" dataKey="wmape" stroke="#a855f7" fill="#a855f7" fillOpacity={0.1} />
            <Legend wrapperStyle={{ fontSize: 11 }} />
            <Tooltip contentStyle={{ background: '#1a1a1a', border: '1px solid #282828', borderRadius: 8, fontSize: 12 }} />
          </RadarChart>
        </ResponsiveContainer>
      </SectionCard>
    </>
  );
};

// ---------------------------------------------------------------------------
// TAB: ALERTS
// ---------------------------------------------------------------------------
const AlertsTab = () => {
  const [filter, setFilter] = useState('ALL');

  const filtered = filter === 'ALL' ? ALERTS : ALERTS.filter((a) => a.severity === filter);
  const counts = {
    ALL: ALERTS.length,
    CRITICAL: ALERTS.filter((a) => a.severity === 'CRITICAL').length,
    WARNING: ALERTS.filter((a) => a.severity === 'WARNING').length,
    BIAS: ALERTS.filter((a) => a.severity === 'BIAS').length,
    INFO: ALERTS.filter((a) => a.severity === 'INFO').length,
  };

  return (
    <>
      {/* Filter Buttons */}
      <div className="flex flex-wrap gap-2 mb-5">
        {Object.entries(counts).map(([key, count]) => {
          const colorMap = { ALL: '#3b82f6', CRITICAL: '#ef4444', WARNING: '#eab308', BIAS: '#f97316', INFO: '#3b82f6' };
          const c = colorMap[key];
          const active = filter === key;
          return (
            <button
              key={key}
              onClick={() => setFilter(key)}
              className="px-3 py-1.5 rounded-lg text-xs font-medium transition-colors border"
              style={{
                background: active ? c + '20' : '#1a1a1a',
                color: active ? c : '#666',
                borderColor: active ? c + '44' : '#282828',
              }}
            >
              {key} ({count})
            </button>
          );
        })}
      </div>

      {/* Alert Cards */}
      <div className="flex flex-col gap-3">
        {filtered.map((a, i) => (
          <div
            key={i}
            className="bg-dark-card rounded-lg border-l-[3px] p-4"
            style={{ borderColor: a.color, borderTopColor: '#282828', borderRightColor: '#282828', borderBottomColor: '#282828', borderTopWidth: 1, borderRightWidth: 1, borderBottomWidth: 1 }}
          >
            <div className="flex items-center gap-2.5 mb-2 flex-wrap">
              <span
                className="text-[10px] font-bold px-2 py-0.5 rounded tracking-wide"
                style={{ background: a.color + '18', color: a.color, border: `1px solid ${a.color}44` }}
              >
                {a.severity}
              </span>
              <span className="text-[11px] text-gray-600">{a.ts}</span>
            </div>
            <div className="text-sm text-gray-200 leading-relaxed">{a.en}</div>
            <div className="text-xs text-gray-600 mt-1">{a.cn}</div>
          </div>
        ))}
      </div>

      {/* Alert Threshold Reference */}
      <SectionCard className="mt-6">
        <SectionTitle en="Alert Threshold Reference" cn="告警阈值参考" />
        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-3">
          {[
            { label: 'CRITICAL', desc: '7d rolling MAPE > 40% (any store)', color: '#ef4444' },
            { label: 'WARNING', desc: '7d rolling MAPE > 30% (any store)', color: '#eab308' },
            { label: 'BIAS', desc: 'Same-sign MFE for 14+ consecutive days', color: '#f97316' },
            { label: 'COVERAGE', desc: 'Match rate < 90% of store-product-days', color: '#eab308' },
            { label: 'DRIFT', desc: 'WoW MAPE change > 50% (category)', color: '#a855f7' },
          ].map((t) => (
            <div key={t.label} className="bg-dark-bg rounded-lg p-3 border border-dark-border">
              <span className="text-[10px] font-bold px-2 py-0.5 rounded" style={{ background: t.color + '18', color: t.color, border: `1px solid ${t.color}44` }}>
                {t.label}
              </span>
              <div className="text-xs text-gray-400 mt-2">{t.desc}</div>
            </div>
          ))}
        </div>
      </SectionCard>
    </>
  );
};

// ---------------------------------------------------------------------------
// MAIN APP
// ---------------------------------------------------------------------------
export default function App() {
  const [activeTab, setActiveTab] = useState('overview');

  const alertCount = ALERTS.filter((a) => a.severity === 'CRITICAL' || a.severity === 'WARNING').length;

  return (
    <div className="min-h-screen">
      {/* Header */}
      <header className="bg-gradient-to-r from-[#111] to-[#0d1b2a] border-b border-accent-blue/20 px-6 py-5">
        <div className="max-w-[1440px] mx-auto flex items-center justify-between flex-wrap gap-3">
          <div>
            <h1 className="text-xl font-bold text-white tracking-wide">
              <span className="text-accent-blue">SCM</span> Demand Forecast Accuracy Monitor
            </h1>
            <div className="text-sm text-accent-blue/80 font-medium mt-0.5">
              供应链需求预测准确度监控
            </div>
            <div className="text-xs text-gray-600 mt-1.5">
              UC-SC-01 &nbsp;|&nbsp; Luckin Coffee USA &nbsp;|&nbsp; Feb 1 – 14, 2026
              &nbsp;|&nbsp; 10 Stores &nbsp;|&nbsp; ~88 SKUs &nbsp;|&nbsp; {systemMetrics.totalPredictions.toLocaleString()} Predictions
            </div>
          </div>
          <div className="flex items-center gap-3">
            {alertCount > 0 && (
              <span className="flex items-center gap-1.5 bg-red-500/15 border border-red-500/30 text-red-400 text-xs font-semibold px-3 py-1.5 rounded-full">
                <span className="w-2 h-2 rounded-full bg-red-500 animate-pulse" />
                {alertCount} Active
              </span>
            )}
            <span className="flex items-center gap-1.5 bg-yellow-500/15 border border-yellow-500/30 text-yellow-400 text-xs font-semibold px-3 py-1.5 rounded-full">
              <span className="w-2 h-2 rounded-full bg-yellow-500" />
              Needs Attention / 需关注
            </span>
          </div>
        </div>
      </header>

      {/* Tab Navigation */}
      <nav className="bg-dark-card border-b border-dark-border sticky top-0 z-30">
        <div className="max-w-[1440px] mx-auto px-6 flex gap-0">
          {TABS.map((tab) => (
            <button
              key={tab.id}
              onClick={() => setActiveTab(tab.id)}
              className={`px-5 py-3 text-sm font-medium transition-colors relative ${
                activeTab === tab.id
                  ? 'text-accent-blue'
                  : 'text-gray-500 hover:text-gray-300'
              }`}
            >
              {tab.label}
              <span className="text-[10px] text-gray-600 ml-1">{tab.labelCn}</span>
              {activeTab === tab.id && (
                <span className="absolute bottom-0 left-0 right-0 h-[2px] bg-accent-blue rounded-t" />
              )}
              {tab.id === 'alerts' && alertCount > 0 && (
                <span className="ml-1.5 bg-red-500/20 text-red-400 text-[10px] font-bold px-1.5 py-0.5 rounded-full">
                  {alertCount}
                </span>
              )}
            </button>
          ))}
        </div>
      </nav>

      {/* Tab Content */}
      <main className="max-w-[1440px] mx-auto px-6 py-6">
        {activeTab === 'overview' && <OverviewTab />}
        {activeTab === 'stores' && <StoresTab />}
        {activeTab === 'products' && <ProductsTab />}
        {activeTab === 'alerts' && <AlertsTab />}
      </main>

      {/* Footer */}
      <footer className="max-w-[1440px] mx-auto px-6 py-4 border-t border-dark-border flex flex-wrap justify-between gap-3 text-[11px] text-gray-600">
        <div>
          Powered by <span className="text-accent-blue">UC-SC-01 Forecast Accuracy Pipeline</span>
          &nbsp;|&nbsp; Luckin Coffee USA Supply Chain Analytics
        </div>
        <div className="text-right">
          Data refreshed: <span className="text-gray-500">2026-02-15 06:00 EST</span>
          &nbsp;|&nbsp; Next refresh: <span className="text-gray-500">2026-02-16 06:00 EST</span>
        </div>
      </footer>
    </div>
  );
}
