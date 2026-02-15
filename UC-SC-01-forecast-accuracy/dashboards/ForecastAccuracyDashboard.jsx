import React, { useState } from 'react';
import {
  LineChart, Line, BarChart, Bar, XAxis, YAxis, CartesianGrid,
  Tooltip, Legend, ResponsiveContainer, ReferenceLine, Cell,
} from 'recharts';

// ---------------------------------------------------------------------------
// DATA
// ---------------------------------------------------------------------------

const STORES = [
  { id: '1127',  name: '8th & Broadway',   mape: 34.2, wmape: 28.5, bias: 8.3  },
  { id: '1128',  name: '28th & 6th',       mape: 38.7, wmape: 31.2, bias: 12.1 },
  { id: '1140',  name: '100 Maiden Ln',    mape: 41.3, wmape: 33.8, bias: 5.6  },
  { id: '1141',  name: '54th & 8th',       mape: 36.9, wmape: 29.4, bias: 9.8  },
  { id: '20008', name: '33rd & 10th',      mape: 39.5, wmape: 32.1, bias: 7.2  },
  { id: '20010', name: '102 Fulton',       mape: 35.8, wmape: 27.9, bias: 11.4 },
  { id: '20011', name: '37th & Broadway',  mape: 37.2, wmape: 30.6, bias: 6.9  },
  { id: '20027', name: '21st & 3rd',       mape: 43.1, wmape: 35.2, bias: 14.3 },
  { id: '20031', name: '15th & 3rd',       mape: 40.8, wmape: 33.5, bias: 10.7 },
  { id: '20032', name: '221 Grand',        mape: 33.6, wmape: 26.8, bias: 4.2  },
];

const STORES_SORTED = [...STORES].sort((a, b) => a.mape - b.mape);

const DAILY_MAPE = [
  { date: 'Feb 1',  mape: 41.2, ma7: null },
  { date: 'Feb 2',  mape: 39.8, ma7: null },
  { date: 'Feb 3',  mape: 36.5, ma7: null },
  { date: 'Feb 4',  mape: 34.1, ma7: null },
  { date: 'Feb 5',  mape: 38.9, ma7: null },
  { date: 'Feb 6',  mape: 40.3, ma7: null },
  { date: 'Feb 7',  mape: 35.7, ma7: 38.1 },
  { date: 'Feb 8',  mape: 37.4, ma7: 37.5 },
  { date: 'Feb 9',  mape: 42.1, ma7: 37.9 },
  { date: 'Feb 10', mape: 36.8, ma7: 37.9 },
  { date: 'Feb 11', mape: 33.9, ma7: 37.9 },
  { date: 'Feb 12', mape: 38.6, ma7: 37.8 },
  { date: 'Feb 13', mape: 39.2, ma7: 37.7 },
  { date: 'Feb 14', mape: 34.5, ma7: 37.5 },
];

const CATEGORIES = [
  { name: 'Coffee Beans',          nameCn: '\u5496\u5561\u8c46',       mape: 28.9 },
  { name: 'Beverages / Syrups',    nameCn: '\u996e\u54c1/\u7cd6\u6d46',     mape: 32.4 },
  { name: 'Packaging / Supplies',  nameCn: '\u5305\u88c5/\u8017\u6750',     mape: 35.6 },
  { name: 'Toppings / Ingredients',nameCn: '\u914d\u6599/\u539f\u6599',     mape: 38.3 },
  { name: 'Dairy / Milk',          nameCn: '\u4e73\u5236\u54c1',       mape: 41.2 },
  { name: 'Food Items',            nameCn: '\u98df\u54c1',         mape: 45.8 },
];

const ALERTS = [
  {
    severity: 'CRITICAL', color: '#ff4d4f', ts: '2026-02-14 23:15',
    en: 'Store 20027 (21st & 3rd) MAPE exceeded 40% threshold for 5 consecutive days',
    cn: '\u95e8\u5e9720027\uff0821st & 3rd\uff09MAPE\u8fde\u7eed5\u5929\u8d85\u8fc740%\u9608\u503c',
  },
  {
    severity: 'WARNING', color: '#faad14', ts: '2026-02-14 18:30',
    en: 'Dairy category MAPE trending upward (+15% WoW)',
    cn: '\u4e73\u5236\u54c1\u7c7bMAPE\u5468\u73af\u6bd4\u4e0a\u5347+15%',
  },
  {
    severity: 'BIAS', color: '#fa8c16', ts: '2026-02-14 12:00',
    en: 'Store 1128 (28th & 6th) over-predicting for 12 consecutive days (Bias +12.1%)',
    cn: '\u95e8\u5e971128\uff0828th & 6th\uff09\u8fde\u7eed12\u5929\u9884\u6d4b\u504f\u9ad8\uff08\u504f\u5dee+12.1%\uff09',
  },
  {
    severity: 'WARNING', color: '#faad14', ts: '2026-02-13 22:45',
    en: 'Store 1140 food items MAPE at 52% \u2014 investigate promotions / new items',
    cn: '\u95e8\u5e971140\u98df\u54c1\u7c7bMAPE\u8fbe52%\uff0c\u8bf7\u6392\u67e5\u4fc3\u9500/\u65b0\u54c1\u5f71\u54cd',
  },
  {
    severity: 'INFO', color: '#1890ff', ts: '2026-02-13 09:00',
    en: 'Coverage dropped to 91% for store 20027 \u2014 new store ramp-up period',
    cn: '\u95e8\u5e9720027\u8986\u76d6\u7387\u964d\u81f391%\uff0c\u65b0\u5e97\u722c\u5761\u671f',
  },
  {
    severity: 'INFO', color: '#1890ff', ts: '2026-02-12 14:20',
    en: 'System retraining completed \u2014 next evaluation window begins Feb 15',
    cn: '\u7cfb\u7edf\u91cd\u65b0\u8bad\u7ec3\u5b8c\u6210\uff0c\u4e0b\u4e00\u8bc4\u4f30\u7a97\u53e32\u670815\u65e5\u5f00\u59cb',
  },
];

const WORST_PRODUCTS = [
  { rank: 1,  code: 'GS07565', name: 'Oat Milk',               nameCn: '\u71d5\u9ea6\u5976',       cat: 'Dairy',      mape: 62.3, biasDir: 'Over',  avgErr: 18.4 },
  { rank: 2,  code: 'GS07786', name: 'Whole Milk',             nameCn: '\u5168\u8102\u725b\u5976',     cat: 'Dairy',      mape: 51.3, biasDir: 'Over',  avgErr: 14.7 },
  { rank: 3,  code: 'GS07785', name: 'Half & Half',            nameCn: '\u6de1\u5976\u6cb9',       cat: 'Dairy',      mape: 48.7, biasDir: 'Over',  avgErr: 12.1 },
  { rank: 4,  code: 'GS07467', name: 'Espresso Beans Medium',  nameCn: '\u4e2d\u5ea6\u70d8\u7119\u5496\u5561\u8c46', cat: 'Coffee',     mape: 45.2, biasDir: 'Under', avgErr: 9.8  },
  { rank: 5,  code: 'GS07579', name: 'Vanilla Syrup',          nameCn: '\u9999\u8349\u7cd6\u6d46',     cat: 'Beverage',   mape: 43.8, biasDir: 'Over',  avgErr: 8.3  },
  { rank: 6,  code: 'GS07506', name: 'Purified Water',         nameCn: '\u7eaf\u51c0\u6c34',       cat: 'Beverage',   mape: 42.1, biasDir: 'Under', avgErr: 7.6  },
  { rank: 7,  code: 'GS07743', name: 'Caramel Syrup',          nameCn: '\u7126\u7cd6\u7cd6\u6d46',     cat: 'Beverage',   mape: 40.5, biasDir: 'Over',  avgErr: 6.9  },
  { rank: 8,  code: 'GS07575', name: 'Coconut Milk',           nameCn: '\u6930\u5976',         cat: 'Dairy',      mape: 39.2, biasDir: 'Over',  avgErr: 6.2  },
  { rank: 9,  code: 'GS07510', name: 'Brown Sugar Syrup',      nameCn: '\u7ea2\u7cd6\u7cd6\u6d46',     cat: 'Beverage',   mape: 37.8, biasDir: 'Over',  avgErr: 5.5  },
  { rank: 10, code: 'GS07818', name: 'Ice',                    nameCn: '\u51b0\u5757',         cat: 'Supplies',   mape: 36.4, biasDir: 'Under', avgErr: 4.8  },
];

// ---------------------------------------------------------------------------
// HELPERS
// ---------------------------------------------------------------------------

const mapeColor = (v) => (v <= 25 ? '#52c41a' : v <= 40 ? '#faad14' : '#ff4d4f');

const CustomTooltip = ({ active, payload, label }) => {
  if (!active || !payload?.length) return null;
  return (
    <div style={{
      background: '#1a1a1a', border: '1px solid #303030', borderRadius: 6,
      padding: '10px 14px', fontSize: 12, color: '#e0e0e0',
    }}>
      <p style={{ margin: 0, fontWeight: 600, marginBottom: 4 }}>{label}</p>
      {payload.map((p, i) => (
        <p key={i} style={{ margin: 0, color: p.color }}>
          {p.name}: {typeof p.value === 'number' ? p.value.toFixed(1) + '%' : p.value}
        </p>
      ))}
    </div>
  );
};

// ---------------------------------------------------------------------------
// SUB-COMPONENTS
// ---------------------------------------------------------------------------

const StatusBadge = ({ status, label }) => {
  const colorMap = { green: '#52c41a', yellow: '#faad14', red: '#ff4d4f' };
  return (
    <span style={{
      display: 'inline-flex', alignItems: 'center', gap: 6,
      background: `${colorMap[status]}18`, border: `1px solid ${colorMap[status]}44`,
      borderRadius: 20, padding: '4px 14px', fontSize: 12, fontWeight: 600,
      color: colorMap[status], letterSpacing: 0.3,
    }}>
      <span style={{
        width: 8, height: 8, borderRadius: '50%',
        background: colorMap[status], display: 'inline-block',
        boxShadow: `0 0 6px ${colorMap[status]}`,
      }} />
      {label}
    </span>
  );
};

const KPICard = ({ titleEn, titleCn, value, unit, status, target, trend }) => {
  const colorMap = { green: '#52c41a', yellow: '#faad14', red: '#ff4d4f' };
  const c = colorMap[status] || '#1890ff';
  const trendArrow = trend === 'up' ? '\u2191' : trend === 'down' ? '\u2193' : '\u2192';
  const trendColor = trend === 'down' ? '#52c41a' : trend === 'up' ? '#ff4d4f' : '#888';
  return (
    <div style={{
      background: '#1a1a1a', borderRadius: 10, padding: '20px 22px',
      border: `1px solid ${c}33`, position: 'relative', overflow: 'hidden',
      display: 'flex', flexDirection: 'column', gap: 6,
    }}>
      <div style={{
        position: 'absolute', top: 0, left: 0, right: 0, height: 3,
        background: `linear-gradient(90deg, ${c}, ${c}66)`,
      }} />
      <div style={{ fontSize: 12, color: '#888', lineHeight: 1.3 }}>
        {titleEn}<br />{titleCn}
      </div>
      <div style={{ display: 'flex', alignItems: 'baseline', gap: 6 }}>
        <span style={{ fontSize: 32, fontWeight: 700, color: c, lineHeight: 1 }}>
          {value}
        </span>
        {unit && <span style={{ fontSize: 14, color: '#888' }}>{unit}</span>}
        <span style={{ fontSize: 18, color: trendColor, marginLeft: 'auto' }}>
          {trendArrow}
        </span>
      </div>
      <div style={{ fontSize: 11, color: '#666' }}>Target: {target}</div>
    </div>
  );
};

const SectionTitle = ({ en, cn }) => (
  <div style={{ marginBottom: 12 }}>
    <h3 style={{
      margin: 0, fontSize: 16, fontWeight: 600, color: '#e0e0e0', letterSpacing: 0.2,
    }}>
      {en}
    </h3>
    <span style={{ fontSize: 12, color: '#666' }}>{cn}</span>
  </div>
);

const Card = ({ children, style }) => (
  <div style={{
    background: '#1a1a1a', borderRadius: 10, padding: 22,
    border: '1px solid #282828', ...style,
  }}>
    {children}
  </div>
);

// ---------------------------------------------------------------------------
// MAIN DASHBOARD
// ---------------------------------------------------------------------------

const ForecastAccuracyDashboard = () => {
  const [hoveredStore, setHoveredStore] = useState(null);

  return (
    <div style={{
      background: '#0a0a0a', minHeight: '100vh', color: '#e0e0e0',
      fontFamily: '-apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, "Noto Sans SC", sans-serif',
      padding: '0 0 40px 0',
    }}>
      {/* ================================================================
          1. HEADER
      ================================================================ */}
      <header style={{
        background: 'linear-gradient(135deg, #111 0%, #0d1b2a 100%)',
        borderBottom: '1px solid #1890ff33',
        padding: '20px 32px',
        display: 'flex', alignItems: 'center', justifyContent: 'space-between',
        flexWrap: 'wrap', gap: 12,
      }}>
        <div>
          <h1 style={{
            margin: 0, fontSize: 22, fontWeight: 700, color: '#fff',
            letterSpacing: 0.4,
          }}>
            <span style={{ color: '#1890ff' }}>SCM</span>{' '}
            Demand Forecast Accuracy Monitor
          </h1>
          <div style={{ fontSize: 14, color: '#999', marginTop: 2 }}>
            <span style={{ color: '#1890ff', fontWeight: 500 }}>\u4f9b\u5e94\u94fe\u9700\u6c42\u9884\u6d4b\u51c6\u786e\u5ea6\u76d1\u63a7</span>
          </div>
          <div style={{ fontSize: 12, color: '#666', marginTop: 6 }}>
            UC-SC-01 &nbsp;|&nbsp; Luckin Coffee USA &nbsp;|&nbsp; Feb 1 &ndash; 14, 2026
            &nbsp;|&nbsp; 10 Stores &nbsp;|&nbsp; ~82 Goods/Store &nbsp;|&nbsp; 12,603 Predictions
          </div>
        </div>
        <StatusBadge status="yellow" label="Needs Attention / \u9700\u5173\u6ce8" />
      </header>

      {/* Content wrapper */}
      <div style={{ maxWidth: 1440, margin: '0 auto', padding: '24px 28px' }}>

        {/* ==============================================================
            2. KPI CARDS
        ============================================================== */}
        <div style={{
          display: 'grid',
          gridTemplateColumns: 'repeat(auto-fit, minmax(200px, 1fr))',
          gap: 16, marginBottom: 28,
        }}>
          <KPICard
            titleEn="Overall MAPE" titleCn="\u5e73\u5747\u7edd\u5bf9\u767e\u5206\u6bd4\u8bef\u5dee"
            value="37.8" unit="%" status="yellow"
            target="< 25%" trend="up"
          />
          <KPICard
            titleEn="WMAPE" titleCn="\u52a0\u6743\u5e73\u5747\u7edd\u5bf9\u8bef\u5dee"
            value="30.7" unit="%" status="yellow"
            target="< 20%" trend="flat"
          />
          <KPICard
            titleEn="Bias (MFE)" titleCn="\u504f\u5dee\uff08\u7cfb\u7edf\u6027\u8fc7\u9884\u6d4b\uff09"
            value="+9.1" unit="%" status="yellow"
            target="\u00b15%" trend="up"
          />
          <KPICard
            titleEn="Accuracy Rate (\u00b120%)" titleCn="\u51c6\u786e\u7387\uff08\u00b120%\u5185\uff09"
            value="42.3" unit="%" status="red"
            target="> 70%" trend="down"
          />
          <KPICard
            titleEn="Coverage" titleCn="\u8986\u76d6\u7387"
            value="94.2" unit="%" status="green"
            target="> 90%" trend="flat"
          />
        </div>

        {/* ==============================================================
            3 + 4. TREND CHART  &  STORE PERFORMANCE  (side by side)
        ============================================================== */}
        <div style={{
          display: 'grid',
          gridTemplateColumns: 'repeat(auto-fit, minmax(420px, 1fr))',
          gap: 20, marginBottom: 28,
        }}>
          {/* 3. Daily MAPE Trend */}
          <Card>
            <SectionTitle
              en="Daily MAPE Trend (14 Days)"
              cn="\u6bcf\u65e5MAPE\u8d8b\u52bf\uff0814\u5929\uff09"
            />
            <ResponsiveContainer width="100%" height={300}>
              <LineChart data={DAILY_MAPE} margin={{ top: 10, right: 20, bottom: 5, left: 0 }}>
                <CartesianGrid strokeDasharray="3 3" stroke="#282828" />
                <XAxis dataKey="date" tick={{ fill: '#888', fontSize: 11 }} />
                <YAxis
                  domain={[20, 50]}
                  tick={{ fill: '#888', fontSize: 11 }}
                  tickFormatter={(v) => `${v}%`}
                />
                <Tooltip content={<CustomTooltip />} />
                <Legend
                  wrapperStyle={{ fontSize: 11, color: '#888', paddingTop: 8 }}
                />
                <ReferenceLine
                  y={20} stroke="#52c41a" strokeDasharray="6 4"
                  label={{ value: '20% Target', fill: '#52c41a', fontSize: 10, position: 'insideTopRight' }}
                />
                <ReferenceLine
                  y={30} stroke="#faad14" strokeDasharray="6 4"
                  label={{ value: '30% Warn', fill: '#faad14', fontSize: 10, position: 'insideTopRight' }}
                />
                <Line
                  type="monotone" dataKey="mape" name="Daily MAPE"
                  stroke="#1890ff" strokeWidth={2} dot={{ r: 3, fill: '#1890ff' }}
                  activeDot={{ r: 5 }}
                />
                <Line
                  type="monotone" dataKey="ma7" name="7-Day MA"
                  stroke="#ff85c0" strokeWidth={2} strokeDasharray="5 3"
                  dot={false} connectNulls={false}
                />
              </LineChart>
            </ResponsiveContainer>
          </Card>

          {/* 4. Store Performance */}
          <Card>
            <SectionTitle
              en="Store Performance (MAPE by Store)"
              cn="\u95e8\u5e97\u8868\u73b0\uff08\u5404\u95e8\u5e97MAPE\uff09"
            />
            <ResponsiveContainer width="100%" height={300}>
              <BarChart
                layout="vertical"
                data={STORES_SORTED}
                margin={{ top: 5, right: 30, bottom: 5, left: 10 }}
              >
                <CartesianGrid strokeDasharray="3 3" stroke="#282828" />
                <XAxis
                  type="number" domain={[0, 50]}
                  tick={{ fill: '#888', fontSize: 11 }}
                  tickFormatter={(v) => `${v}%`}
                />
                <YAxis
                  type="category" dataKey="name" width={120}
                  tick={{ fill: '#bbb', fontSize: 11 }}
                />
                <Tooltip content={<CustomTooltip />} />
                <ReferenceLine x={25} stroke="#52c41a55" strokeDasharray="4 3" />
                <ReferenceLine x={40} stroke="#ff4d4f55" strokeDasharray="4 3" />
                <Bar dataKey="mape" name="MAPE" radius={[0, 4, 4, 0]} barSize={18}>
                  {STORES_SORTED.map((s, i) => (
                    <Cell key={i} fill={mapeColor(s.mape)} fillOpacity={0.85} />
                  ))}
                </Bar>
              </BarChart>
            </ResponsiveContainer>
          </Card>
        </div>

        {/* ==============================================================
            5. CATEGORY PERFORMANCE  &  6. ALERTS  (side by side)
        ============================================================== */}
        <div style={{
          display: 'grid',
          gridTemplateColumns: 'repeat(auto-fit, minmax(420px, 1fr))',
          gap: 20, marginBottom: 28,
        }}>
          {/* 5. Category Performance */}
          <Card>
            <SectionTitle
              en="Category Performance (MAPE)"
              cn="\u5546\u54c1\u54c1\u7c7b\u8868\u73b0\uff08MAPE\uff09"
            />
            <ResponsiveContainer width="100%" height={280}>
              <BarChart data={CATEGORIES} margin={{ top: 10, right: 20, bottom: 5, left: 0 }}>
                <CartesianGrid strokeDasharray="3 3" stroke="#282828" />
                <XAxis
                  dataKey="name"
                  tick={{ fill: '#888', fontSize: 10, angle: -20, textAnchor: 'end' }}
                  height={60}
                />
                <YAxis
                  domain={[0, 55]}
                  tick={{ fill: '#888', fontSize: 11 }}
                  tickFormatter={(v) => `${v}%`}
                />
                <Tooltip content={<CustomTooltip />} />
                <ReferenceLine y={25} stroke="#52c41a55" strokeDasharray="4 3" />
                <ReferenceLine y={40} stroke="#ff4d4f55" strokeDasharray="4 3" />
                <Bar dataKey="mape" name="MAPE" radius={[4, 4, 0, 0]} barSize={36}>
                  {CATEGORIES.map((c, i) => (
                    <Cell key={i} fill={mapeColor(c.mape)} fillOpacity={0.85} />
                  ))}
                </Bar>
              </BarChart>
            </ResponsiveContainer>
            <div style={{
              display: 'flex', flexWrap: 'wrap', gap: 8, marginTop: 8,
              fontSize: 11, color: '#888',
            }}>
              {CATEGORIES.map((c) => (
                <span key={c.name} style={{
                  background: '#111', borderRadius: 4, padding: '2px 8px',
                  border: '1px solid #282828',
                }}>
                  {c.nameCn} {c.mape}%
                </span>
              ))}
            </div>
          </Card>

          {/* 6. Alerts Feed */}
          <Card>
            <SectionTitle
              en="Active Alerts"
              cn="\u6d3b\u8dc3\u544a\u8b66"
            />
            <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
              {ALERTS.map((a, i) => (
                <div key={i} style={{
                  background: '#111', borderRadius: 8,
                  border: `1px solid ${a.color}22`,
                  padding: '12px 14px',
                  borderLeft: `3px solid ${a.color}`,
                }}>
                  <div style={{
                    display: 'flex', alignItems: 'center', gap: 8,
                    marginBottom: 6, flexWrap: 'wrap',
                  }}>
                    <span style={{
                      background: `${a.color}22`, color: a.color,
                      fontSize: 10, fontWeight: 700, borderRadius: 4,
                      padding: '2px 8px', letterSpacing: 0.5,
                      border: `1px solid ${a.color}44`,
                    }}>
                      {a.severity}
                    </span>
                    <span style={{ fontSize: 11, color: '#666' }}>{a.ts}</span>
                  </div>
                  <div style={{ fontSize: 13, color: '#d0d0d0', lineHeight: 1.45 }}>
                    {a.en}
                  </div>
                  <div style={{ fontSize: 11, color: '#888', marginTop: 2 }}>
                    {a.cn}
                  </div>
                </div>
              ))}
            </div>
          </Card>
        </div>

        {/* ==============================================================
            7. TOP 10 WORST PREDICTED PRODUCTS
        ============================================================== */}
        <Card style={{ marginBottom: 28 }}>
          <SectionTitle
            en="Top 10 Worst Predicted Products"
            cn="\u9884\u6d4b\u8bef\u5dee\u6700\u5927\u7684\u524d10\u4e2a\u5546\u54c1"
          />
          <div style={{ overflowX: 'auto' }}>
            <table style={{
              width: '100%', borderCollapse: 'separate', borderSpacing: 0,
              fontSize: 13,
            }}>
              <thead>
                <tr>
                  {[
                    { en: '#',           cn: '\u6392\u540d' },
                    { en: 'Goods Code',  cn: '\u5546\u54c1\u7f16\u7801' },
                    { en: 'Product Name',cn: '\u5546\u54c1\u540d\u79f0' },
                    { en: 'Category',    cn: '\u54c1\u7c7b' },
                    { en: 'MAPE',        cn: '\u8bef\u5dee' },
                    { en: 'Bias',        cn: '\u504f\u5dee\u65b9\u5411' },
                    { en: 'Avg Daily Err', cn: '\u65e5\u5747\u8bef\u5dee(\u4ef6)' },
                  ].map((h, i) => (
                    <th key={i} style={{
                      textAlign: 'left', padding: '10px 12px',
                      borderBottom: '1px solid #303030',
                      color: '#888', fontWeight: 600, fontSize: 11,
                      whiteSpace: 'nowrap', letterSpacing: 0.3,
                      position: 'sticky', top: 0, background: '#1a1a1a',
                    }}>
                      {h.en}
                      <br />
                      <span style={{ color: '#555', fontWeight: 400 }}>{h.cn}</span>
                    </th>
                  ))}
                </tr>
              </thead>
              <tbody>
                {WORST_PRODUCTS.map((p) => (
                  <tr
                    key={p.rank}
                    onMouseEnter={() => setHoveredStore(p.rank)}
                    onMouseLeave={() => setHoveredStore(null)}
                    style={{
                      background: hoveredStore === p.rank ? '#222' : 'transparent',
                      transition: 'background 0.15s',
                    }}
                  >
                    <td style={tdStyle}>
                      <span style={{
                        display: 'inline-flex', alignItems: 'center',
                        justifyContent: 'center', width: 24, height: 24,
                        borderRadius: '50%', fontSize: 11, fontWeight: 700,
                        background: p.rank <= 3 ? '#ff4d4f22' : '#282828',
                        color: p.rank <= 3 ? '#ff4d4f' : '#888',
                        border: p.rank <= 3 ? '1px solid #ff4d4f44' : '1px solid #333',
                      }}>
                        {p.rank}
                      </span>
                    </td>
                    <td style={{ ...tdStyle, fontFamily: 'monospace', color: '#1890ff' }}>
                      {p.code}
                    </td>
                    <td style={tdStyle}>
                      <div style={{ color: '#e0e0e0' }}>{p.name}</div>
                      <div style={{ color: '#666', fontSize: 11 }}>{p.nameCn}</div>
                    </td>
                    <td style={{ ...tdStyle, color: '#999' }}>{p.cat}</td>
                    <td style={tdStyle}>
                      <span style={{
                        color: mapeColor(p.mape), fontWeight: 600,
                        fontVariantNumeric: 'tabular-nums',
                      }}>
                        {p.mape.toFixed(1)}%
                      </span>
                    </td>
                    <td style={tdStyle}>
                      <span style={{
                        padding: '2px 10px', borderRadius: 4, fontSize: 11,
                        fontWeight: 600,
                        background: p.biasDir === 'Over' ? '#faad1418' : '#1890ff18',
                        color: p.biasDir === 'Over' ? '#faad14' : '#1890ff',
                        border: `1px solid ${p.biasDir === 'Over' ? '#faad1444' : '#1890ff44'}`,
                      }}>
                        {p.biasDir === 'Over' ? '\u2191 Over' : '\u2193 Under'}
                      </span>
                    </td>
                    <td style={{ ...tdStyle, fontVariantNumeric: 'tabular-nums', color: '#ccc' }}>
                      {p.avgErr.toFixed(1)} units
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </Card>

        {/* ==============================================================
            8. FOOTER
        ============================================================== */}
        <footer style={{
          borderTop: '1px solid #1a1a1a',
          paddingTop: 20,
          display: 'flex', flexWrap: 'wrap', justifyContent: 'space-between',
          gap: 12, fontSize: 11, color: '#555',
        }}>
          <div>
            Powered by{' '}
            <span style={{ color: '#1890ff' }}>UC-SC-01 Forecast Accuracy Pipeline</span>
            {' '}&nbsp;|&nbsp;{' '}
            <span style={{ color: '#666' }}>Luckin Coffee USA Supply Chain Analytics</span>
          </div>
          <div style={{ textAlign: 'right' }}>
            Data refreshed: <span style={{ color: '#888' }}>2026-02-15 06:00 EST</span>
            &nbsp;|&nbsp;
            Next refresh: <span style={{ color: '#888' }}>2026-02-16 06:00 EST</span>
          </div>
        </footer>
      </div>
    </div>
  );
};

// Shared table-cell style
const tdStyle = {
  padding: '10px 12px',
  borderBottom: '1px solid #1e1e1e',
  verticalAlign: 'middle',
  whiteSpace: 'nowrap',
};

export default ForecastAccuracyDashboard;
