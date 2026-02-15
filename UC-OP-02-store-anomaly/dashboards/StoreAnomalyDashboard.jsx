/**
 * UC-OP-02: Store Anomaly Detection — React Dashboard Component
 * 门店异常检测 — React仪表板组件
 *
 * Reference implementation for embedding store anomaly detection
 * visualizations in a React application. This component renders:
 *   - Executive summary with portfolio KPIs / 执行摘要与组合KPI
 *   - Per-store health grid (composite score) / 单店健康度网格
 *   - SPC control charts (X-bar, +-2sigma, +-3sigma) / SPC控制图
 *   - Anomaly alert table with severity badges / 异常告警表
 *   - 8th Ave case-study narrative / 第八大道案例分析
 *   - ROI / architecture reference panels / ROI与架构参考面板
 *
 * Dependencies: React 18+, recharts, lucide-react
 * 依赖: React 18+, recharts, lucide-react
 */

import React, { useState, useEffect, useMemo, useCallback } from 'react';
import {
  ComposedChart, LineChart, Line, Area, Bar, XAxis, YAxis,
  CartesianGrid, Tooltip, Legend, ResponsiveContainer, Cell,
  ReferenceLine,
} from 'recharts';
import {
  AlertTriangle, TrendingUp, TrendingDown, Activity,
  Store, Bell, CheckCircle, XCircle, Info, ChevronRight,
} from 'lucide-react';

// ============================================================
// Constants / 常量
// ============================================================

/** Pilot-program store list — matches test-schema seed data
 *  试点门店列表 — 与测试库种子数据一致 */
const STORE_LIST = [
  { id: 1127,  no: 'US00001', name: '8th & Broadway',       lat: 40.730548, lng: -73.992624 },
  { id: 1128,  no: 'US00002', name: '28th & 6th',           lat: 40.745666, lng: -73.990592 },
  { id: 1140,  no: 'US00003', name: '100 Maiden Ln',        lat: 40.706675, lng: -74.007198 },
  { id: 20011, no: 'US00004', name: '37th & Broadway',      lat: 40.752559, lng: -73.987833 },
  { id: 1141,  no: 'US00005', name: '54th & 8th',           lat: 40.764650, lng: -73.984773 },
  { id: 20010, no: 'US00006', name: '102 Fulton',           lat: 40.709656, lng: -74.006790 },
  { id: 20009, no: 'US00007', name: '108th & Broadway',     lat: 40.802905, lng: -73.967925 },
  { id: 20008, no: 'US00008', name: '33rd & 10th',          lat: 40.753774, lng: -73.999053 },
  { id: 1131,  no: 'US00000', name: 'NJ Test Kitchen',      lat: 40.763786, lng: -74.068221 },
  { id: 20046, no: 'US99998', name: 'Shanghai Test Kitchen', lat: 40.751606, lng: -73.983692 },
];

/** Health-score dimension weights (must sum to 1.0)
 *  健康评分维度权重（总和=1.0） */
const HEALTH_WEIGHTS = {
  revenue:  0.40,
  ops:      0.20,
  quality:  0.15,
  staffing: 0.15,
  customer: 0.10,
};

/** Severity palette / 严重级别配色 */
const SEVERITY_COLORS = {
  CRITICAL: '#ff4444',
  WARNING:  '#ff9800',
  INFO:     '#2196f3',
  NONE:     '#4caf50',
};

/** Grade palette (A–F) / 等级配色 */
const GRADE_COLORS = {
  A: '#4caf50',
  B: '#8bc34a',
  C: '#ff9800',
  D: '#ff5722',
  F: '#ff4444',
};

/** Dark-theme base tokens / 深色主题基础变量 */
const THEME = {
  bg:          '#0f1419',
  surface:     '#1a2332',
  surfaceAlt:  '#1e2d3d',
  border:      '#2d4050',
  textPrimary: '#e8edf2',
  textMuted:   '#8899a6',
  accent:      '#1a8cff',
  accentDim:   'rgba(0,82,155,0.15)',
  brandGrad:   'linear-gradient(135deg, #00529B, #002F5D)',
};

// ============================================================
// Utilities / 工具函数
// ============================================================

/** Map composite score 0-100 to letter grade / 将0-100分映射为字母等级 */
const getGrade = (score) => {
  if (score >= 90) return 'A';
  if (score >= 80) return 'B';
  if (score >= 70) return 'C';
  if (score >= 60) return 'D';
  return 'F';
};

/** Format number with commas / 千分位格式化 */
const fmt = (n, decimals = 0) =>
  n == null ? '—' : Number(n).toLocaleString('en-US', { minimumFractionDigits: decimals, maximumFractionDigits: decimals });

/** Format currency / 货币格式化 */
const fmtUSD = (n) => (n == null ? '—' : `$${fmt(n, 2)}`);

/** Trend arrow component / 趋势箭头组件 */
const TrendArrow = ({ value }) => {
  if (value == null) return null;
  const positive = value >= 0;
  const Icon = positive ? TrendingUp : TrendingDown;
  return (
    <span style={{ display: 'inline-flex', alignItems: 'center', gap: 3, color: positive ? '#4caf50' : '#ff4444', fontSize: 12 }}>
      <Icon size={14} />
      {Math.abs(value).toFixed(1)}%
    </span>
  );
};

// ============================================================
// Sub-components / 子组件
// ============================================================

/**
 * HealthScoreCircle — SVG circular gauge showing health score 0-100
 * 健康评分圆环 — SVG圆形仪表，显示0-100健康评分
 */
const HealthScoreCircle = ({ score, size = 120 }) => {
  const grade = getGrade(score);
  const color = GRADE_COLORS[grade] || THEME.textMuted;
  const radius = (size - 12) / 2;
  const circumference = 2 * Math.PI * radius;
  const dashOffset = circumference * (1 - score / 100);

  return (
    <div style={{ position: 'relative', width: size, height: size }}>
      <svg width={size} height={size} style={{ transform: 'rotate(-90deg)' }}>
        {/* Background track / 背景轨道 */}
        <circle cx={size / 2} cy={size / 2} r={radius}
          fill="none" stroke={THEME.border} strokeWidth={8} />
        {/* Filled arc / 填充弧 */}
        <circle cx={size / 2} cy={size / 2} r={radius}
          fill="none" stroke={color} strokeWidth={8}
          strokeDasharray={circumference} strokeDashoffset={dashOffset}
          strokeLinecap="round"
          style={{ transition: 'stroke-dashoffset 0.8s ease' }} />
      </svg>
      {/* Center label / 中心标签 */}
      <div style={{
        position: 'absolute', inset: 0,
        display: 'flex', flexDirection: 'column',
        alignItems: 'center', justifyContent: 'center',
      }}>
        <span style={{ fontSize: size * 0.28, fontWeight: 700, color }}>{Math.round(score)}</span>
        <span style={{ fontSize: size * 0.15, fontWeight: 600, color, marginTop: -2 }}>{grade}</span>
      </div>
    </div>
  );
};

/**
 * KPICard — Stat card with value, label, and trend
 * KPI卡片 — 统计卡片，含数值、标签与趋势
 */
const KPICard = ({ value, label, labelCn, trend, color = THEME.accent, icon: Icon = Activity }) => (
  <div style={{
    background: THEME.surface, border: `1px solid ${THEME.border}`, borderRadius: 10,
    padding: '18px 22px', flex: '1 1 180px', minWidth: 180,
  }}>
    <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start' }}>
      <div>
        <div style={{ fontSize: 26, fontWeight: 700, color }}>{value}</div>
        <div style={{ fontSize: 13, color: THEME.textPrimary, marginTop: 4 }}>{label}</div>
        {labelCn && <div style={{ fontSize: 11, color: THEME.textMuted }}>{labelCn}</div>}
      </div>
      <Icon size={20} style={{ color: THEME.textMuted, marginTop: 4 }} />
    </div>
    {trend != null && (
      <div style={{ marginTop: 10 }}>
        <TrendArrow value={trend} />
        <span style={{ fontSize: 11, color: THEME.textMuted, marginLeft: 6 }}>vs prior period</span>
      </div>
    )}
  </div>
);

/**
 * SPCChart — SPC control chart using recharts ComposedChart
 * SPC控制图 — 使用recharts ComposedChart的统计过程控制图
 *
 * Shows actual values, rolling mean, +/-2sigma, +/-3sigma bands.
 * 显示实际值、滚动均值、正负2sigma与正负3sigma控制带。
 */
const SPCChart = ({ data, metricName }) => {
  if (!data || data.length === 0) {
    return (
      <div style={{ padding: 40, textAlign: 'center', color: THEME.textMuted }}>
        No SPC data available for {metricName}. / 暂无{metricName}的SPC数据。
      </div>
    );
  }

  /* Tooltip formatter / 提示框格式化 */
  const renderTooltip = ({ active, payload, label }) => {
    if (!active || !payload?.length) return null;
    return (
      <div style={{
        background: THEME.surface, border: `1px solid ${THEME.border}`,
        borderRadius: 6, padding: '10px 14px', fontSize: 12,
      }}>
        <div style={{ fontWeight: 600, marginBottom: 6 }}>{label}</div>
        {payload.map((p, i) => (
          <div key={i} style={{ display: 'flex', gap: 8, marginBottom: 2 }}>
            <span style={{ color: p.color }}>{p.name}:</span>
            <span style={{ fontWeight: 600 }}>{fmt(p.value, 2)}</span>
          </div>
        ))}
      </div>
    );
  };

  return (
    <div style={{ background: THEME.surface, border: `1px solid ${THEME.border}`, borderRadius: 10, padding: 20 }}>
      <h3 style={{ fontSize: 14, fontWeight: 600, marginBottom: 16 }}>
        SPC Control Chart — {metricName.replace(/_/g, ' ')}
        <span style={{ fontSize: 11, color: THEME.textMuted, marginLeft: 8 }}>SPC控制图</span>
      </h3>
      <ResponsiveContainer width="100%" height={320}>
        <ComposedChart data={data} margin={{ top: 10, right: 20, bottom: 20, left: 10 }}>
          <CartesianGrid strokeDasharray="3 3" stroke={THEME.border} />
          <XAxis dataKey="date" tick={{ fill: THEME.textMuted, fontSize: 11 }} tickLine={false} />
          <YAxis tick={{ fill: THEME.textMuted, fontSize: 11 }} tickLine={false} />
          <Tooltip content={renderTooltip} />
          <Legend wrapperStyle={{ fontSize: 11, color: THEME.textMuted }} />

          {/* +/-3sigma band (outer control limits) / 正负3sigma控制带（外控制限） */}
          <Area dataKey="ucl_3s" name="+3σ UCL" stroke="none" fill="rgba(255,68,68,0.08)" stackId="band3" />
          <Area dataKey="lcl_3s" name="-3σ LCL" stroke="none" fill="rgba(255,68,68,0.08)" stackId="band3_lo" />

          {/* +/-2sigma band (inner warning limits) / 正负2sigma警告带（内警告限） */}
          <Area dataKey="ucl_2s" name="+2σ UWL" stroke="none" fill="rgba(255,152,0,0.10)" stackId="band2" />
          <Area dataKey="lcl_2s" name="-2σ LWL" stroke="none" fill="rgba(255,152,0,0.10)" stackId="band2_lo" />

          {/* Rolling mean center line / 滚动均值中心线 */}
          <Line dataKey="rolling_mean" name="Mean (X̄)" type="monotone"
            stroke="#888" strokeDasharray="6 3" strokeWidth={1.5} dot={false} />

          {/* Upper and lower control limits as reference lines / 上下控制限参考线 */}
          {data.length > 0 && data[0].ucl_3s != null && (
            <ReferenceLine y={data[data.length - 1].ucl_3s} stroke="#ff4444" strokeDasharray="4 4" strokeWidth={1} />
          )}
          {data.length > 0 && data[0].lcl_3s != null && (
            <ReferenceLine y={data[data.length - 1].lcl_3s} stroke="#ff4444" strokeDasharray="4 4" strokeWidth={1} />
          )}

          {/* Actual metric values / 实际指标值 */}
          <Line dataKey="value" name="Actual" type="monotone"
            stroke={THEME.accent} strokeWidth={2} dot={{ r: 3, fill: THEME.accent }} activeDot={{ r: 5 }} />

          {/* Anomaly points highlighted in red / 异常点以红色高亮 */}
          <Line dataKey="anomaly_value" name="Anomaly" type="monotone"
            stroke="none" dot={{ r: 5, fill: '#ff4444', strokeWidth: 2, stroke: '#fff' }} />
        </ComposedChart>
      </ResponsiveContainer>
    </div>
  );
};

/**
 * AlertTable — Table of anomaly alerts with severity badges
 * 告警表 — 含严重级别徽标的异常告警表格
 */
const AlertTable = ({ alerts }) => {
  if (!alerts || alerts.length === 0) {
    return (
      <div style={{ padding: 40, textAlign: 'center', color: THEME.textMuted }}>
        <CheckCircle size={32} style={{ marginBottom: 8, color: '#4caf50' }} />
        <div>No active anomaly alerts. / 暂无活跃异常告警。</div>
      </div>
    );
  }

  /** Severity badge / 严重级别徽标 */
  const SeverityBadge = ({ severity }) => (
    <span style={{
      display: 'inline-block', padding: '2px 10px', borderRadius: 10,
      fontSize: 11, fontWeight: 700, letterSpacing: 0.5,
      background: `${SEVERITY_COLORS[severity] || SEVERITY_COLORS.NONE}22`,
      color: SEVERITY_COLORS[severity] || SEVERITY_COLORS.NONE,
      border: `1px solid ${SEVERITY_COLORS[severity] || SEVERITY_COLORS.NONE}44`,
    }}>
      {severity}
    </span>
  );

  const headerStyle = {
    padding: '10px 14px', textAlign: 'left', fontSize: 11, fontWeight: 700,
    color: THEME.textMuted, textTransform: 'uppercase', letterSpacing: 0.8,
    borderBottom: `2px solid ${THEME.border}`,
  };
  const cellStyle = {
    padding: '12px 14px', fontSize: 13, borderBottom: `1px solid ${THEME.border}`,
  };

  return (
    <div style={{ background: THEME.surface, border: `1px solid ${THEME.border}`, borderRadius: 10, overflow: 'hidden' }}>
      <div style={{ padding: '16px 20px', borderBottom: `1px solid ${THEME.border}`, display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
        <h3 style={{ fontSize: 14, fontWeight: 600, margin: 0 }}>
          Anomaly Alerts <span style={{ fontSize: 11, color: THEME.textMuted }}>异常告警</span>
        </h3>
        <span style={{ fontSize: 12, color: THEME.textMuted }}>{alerts.length} active / 活跃</span>
      </div>
      <div style={{ overflowX: 'auto' }}>
        <table style={{ width: '100%', borderCollapse: 'collapse' }}>
          <thead>
            <tr style={{ background: THEME.surfaceAlt }}>
              <th style={headerStyle}>Severity / 级别</th>
              <th style={headerStyle}>Store / 门店</th>
              <th style={headerStyle}>Metric / 指标</th>
              <th style={headerStyle}>Value / 数值</th>
              <th style={headerStyle}>Z-Score</th>
              <th style={headerStyle}>Detected / 检出时间</th>
              <th style={headerStyle}>Status / 状态</th>
            </tr>
          </thead>
          <tbody>
            {alerts.map((a, i) => (
              <tr key={a.id || i} style={{ background: i % 2 === 0 ? 'transparent' : THEME.surfaceAlt }}>
                <td style={cellStyle}><SeverityBadge severity={a.severity} /></td>
                <td style={cellStyle}>{a.store_name || `Store #${a.store_id}`}</td>
                <td style={{ ...cellStyle, fontFamily: 'monospace', fontSize: 12 }}>{a.metric_name}</td>
                <td style={cellStyle}>{fmt(a.metric_value, 2)}</td>
                <td style={{ ...cellStyle, fontWeight: 600, color: Math.abs(a.z_score) >= 3 ? '#ff4444' : '#ff9800' }}>
                  {a.z_score != null ? a.z_score.toFixed(2) : '—'}
                </td>
                <td style={{ ...cellStyle, fontSize: 12, color: THEME.textMuted }}>
                  {a.detected_at ? new Date(a.detected_at).toLocaleString() : '—'}
                </td>
                <td style={cellStyle}>
                  <span style={{ fontSize: 12, color: a.acknowledged ? '#4caf50' : '#ff9800' }}>
                    {a.acknowledged ? 'ACK' : 'NEW'}
                  </span>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
};

/**
 * StoreHealthCard — Individual store health card with score circle and dimension bars
 * 门店健康卡 — 单店健康卡片，含评分圆环与维度进度条
 */
const StoreHealthCard = ({ store, healthData, onClick }) => {
  const score = healthData?.composite_score ?? 0;
  const grade = getGrade(score);

  /** Dimension progress bar / 维度进度条 */
  const DimensionBar = ({ label, value, weight }) => (
    <div style={{ marginBottom: 6 }}>
      <div style={{ display: 'flex', justifyContent: 'space-between', fontSize: 11, marginBottom: 2 }}>
        <span style={{ color: THEME.textMuted }}>{label} ({(weight * 100).toFixed(0)}%)</span>
        <span style={{ fontWeight: 600 }}>{value != null ? value.toFixed(0) : '—'}</span>
      </div>
      <div style={{ height: 4, background: THEME.border, borderRadius: 2, overflow: 'hidden' }}>
        <div style={{
          height: '100%', borderRadius: 2,
          width: `${Math.min(value || 0, 100)}%`,
          background: GRADE_COLORS[getGrade(value || 0)],
          transition: 'width 0.6s ease',
        }} />
      </div>
    </div>
  );

  return (
    <div
      onClick={onClick}
      style={{
        background: THEME.surface, border: `1px solid ${THEME.border}`, borderRadius: 10,
        padding: 18, cursor: 'pointer', transition: 'border-color 0.2s',
      }}
      onMouseEnter={(e) => { e.currentTarget.style.borderColor = THEME.accent; }}
      onMouseLeave={(e) => { e.currentTarget.style.borderColor = THEME.border; }}
    >
      {/* Header / 头部 */}
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', marginBottom: 12 }}>
        <div>
          <div style={{ fontSize: 14, fontWeight: 600 }}>{store.name}</div>
          <div style={{ fontSize: 11, color: THEME.textMuted }}>{store.no}</div>
        </div>
        <HealthScoreCircle score={score} size={64} />
      </div>

      {/* Dimension bars / 维度进度条 */}
      <DimensionBar label="Revenue / 营收"   value={healthData?.revenue_score}  weight={HEALTH_WEIGHTS.revenue} />
      <DimensionBar label="Ops / 运营"       value={healthData?.ops_score}      weight={HEALTH_WEIGHTS.ops} />
      <DimensionBar label="Quality / 品质"   value={healthData?.quality_score}  weight={HEALTH_WEIGHTS.quality} />
      <DimensionBar label="Staffing / 人力"  value={healthData?.staffing_score} weight={HEALTH_WEIGHTS.staffing} />
      <DimensionBar label="Customer / 顾客"  value={healthData?.customer_score} weight={HEALTH_WEIGHTS.customer} />
    </div>
  );
};

/**
 * HealthGrid — Grid of all store health cards
 * 健康度网格 — 所有门店健康卡片的网格布局
 */
const HealthGrid = ({ stores, healthData, onStoreSelect }) => (
  <div>
    <h2 style={{ fontSize: 18, fontWeight: 700, marginBottom: 4 }}>Portfolio Health Grid</h2>
    <p style={{ fontSize: 12, color: THEME.textMuted, marginBottom: 20 }}>
      门店组合健康度网格 — Click a card to drill into store details / 点击卡片查看门店详情
    </p>
    <div style={{
      display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(280px, 1fr))',
      gap: 16,
    }}>
      {stores.map((store) => {
        const hd = healthData.find((h) => h.store_id === store.id) || {};
        return (
          <StoreHealthCard
            key={store.id}
            store={store}
            healthData={hd}
            onClick={() => onStoreSelect(store)}
          />
        );
      })}
    </div>
  </div>
);

// ============================================================
// Main Component / 主组件
// ============================================================

/**
 * StoreAnomalyDashboard — Top-level dashboard for UC-OP-02
 * 门店异常检测仪表板 — UC-OP-02顶层仪表板
 *
 * Views: summary | caseStudy | healthGrid | spcCharts | alerts | roi | architecture
 * 视图: 执行摘要 | 案例分析 | 健康度网格 | SPC控制图 | 异常告警 | ROI | 架构
 */
const StoreAnomalyDashboard = () => {
  // ---- State / 状态 ----
  const [activeView, setActiveView]       = useState('summary');
  const [selectedStore, setSelectedStore] = useState(STORE_LIST[0]);
  const [selectedMetric, setSelectedMetric] = useState('total_revenue');
  const [kpiData, setKpiData]             = useState(null);
  const [anomalyScores, setAnomalyScores] = useState([]);
  const [healthScores, setHealthScores]   = useState([]);
  const [alerts, setAlerts]               = useState([]);
  const [loading, setLoading]             = useState(true);

  /** API base — connects to backend serving from the test schema
   *  API基础路径 — 连接到测试库后端 */
  const API_BASE = '/api/uc-op-02';

  // ---- Data fetching / 数据获取 ----
  const fetchDashboardData = useCallback(async () => {
    setLoading(true);
    try {
      const [kpi, scores, health, alertData] = await Promise.all([
        fetch(`${API_BASE}/kpi/${selectedStore.id}?days=90`).then((r) => r.json()),
        fetch(`${API_BASE}/anomaly-scores/${selectedStore.id}?metric=${selectedMetric}`).then((r) => r.json()),
        fetch(`${API_BASE}/health-scores`).then((r) => r.json()),
        fetch(`${API_BASE}/alerts?acknowledged=false`).then((r) => r.json()),
      ]);
      setKpiData(kpi);
      setAnomalyScores(scores);
      setHealthScores(health);
      setAlerts(alertData);
    } catch (err) {
      console.error('Failed to fetch dashboard data / 仪表板数据获取失败:', err);
    } finally {
      setLoading(false);
    }
  }, [selectedStore, selectedMetric]);

  useEffect(() => {
    fetchDashboardData();
  }, [fetchDashboardData]);

  // ---- Computed values / 计算值 ----

  /** Portfolio-level KPIs / 组合级别KPI */
  const portfolioKPIs = useMemo(() => {
    if (!healthScores.length) return null;
    const avgScore = healthScores.reduce((s, h) => s + (h.composite_score || 0), 0) / healthScores.length;
    const atRisk = healthScores.filter((h) => h.health_grade === 'D' || h.health_grade === 'F').length;
    const criticalAlerts = alerts.filter((a) => a.severity === 'CRITICAL').length;
    return { avgScore, atRisk, totalAlerts: alerts.length, criticalAlerts };
  }, [healthScores, alerts]);

  // ---- View registry / 视图注册 ----
  const views = {
    summary:      'Executive Summary',
    caseStudy:    '8th Ave Case Study',
    healthGrid:   'Portfolio Health',
    spcCharts:    'SPC Control Charts',
    alerts:       'Anomaly Alerts',
    roi:          'Implementation & ROI',
    architecture: 'Architecture',
  };

  // ---- Shared select styles / 共用选择框样式 ----
  const selectStyle = {
    background: THEME.surfaceAlt, color: THEME.textPrimary,
    border: `1px solid ${THEME.border}`, borderRadius: 6,
    padding: '8px 12px', fontSize: 13, marginRight: 12,
    outline: 'none', cursor: 'pointer',
  };

  // ---- Render / 渲染 ----
  return (
    <div style={{ display: 'flex', minHeight: '100vh', background: THEME.bg, color: THEME.textPrimary, fontFamily: "'Inter', 'Noto Sans SC', system-ui, sans-serif" }}>

      {/* ============================================
          Sidebar / 侧边栏
          ============================================ */}
      <aside style={{
        width: 260, background: THEME.surface, borderRight: `1px solid ${THEME.border}`,
        position: 'fixed', height: '100vh', display: 'flex', flexDirection: 'column',
      }}>
        {/* Branding / 品牌 */}
        <div style={{ padding: '20px', borderBottom: `1px solid ${THEME.border}` }}>
          <h2 style={{ fontSize: 15, fontWeight: 700, margin: 0 }}>Luckin Coffee</h2>
          <span style={{ fontSize: 11, color: THEME.textMuted }}>AI Analytics / AI分析平台</span>
          <div style={{
            marginTop: 8, padding: '3px 10px', background: THEME.brandGrad,
            borderRadius: 12, display: 'inline-block', fontSize: 11, fontWeight: 600,
          }}>
            UC-OP-02
          </div>
        </div>

        {/* Navigation / 导航 */}
        <nav style={{ padding: '12px 0', flex: 1, overflowY: 'auto' }}>
          {Object.entries(views).map(([key, label]) => (
            <div
              key={key}
              onClick={() => setActiveView(key)}
              style={{
                padding: '12px 20px', cursor: 'pointer', fontSize: 13.5,
                color: activeView === key ? THEME.accent : THEME.textMuted,
                background: activeView === key ? THEME.accentDim : 'transparent',
                borderLeft: `3px solid ${activeView === key ? THEME.accent : 'transparent'}`,
                transition: 'all 0.15s ease',
                display: 'flex', alignItems: 'center', gap: 8,
              }}
            >
              <ChevronRight size={12} style={{ opacity: activeView === key ? 1 : 0.3 }} />
              {label}
            </div>
          ))}
        </nav>

        {/* Footer / 底部 */}
        <div style={{ padding: '14px 20px', borderTop: `1px solid ${THEME.border}`, fontSize: 10, color: THEME.textMuted }}>
          Ref implementation v0.1
        </div>
      </aside>

      {/* ============================================
          Main content area / 主内容区
          ============================================ */}
      <main style={{ marginLeft: 260, flex: 1, padding: '32px 36px', minWidth: 0 }}>

        {/* Loading overlay / 加载遮罩 */}
        {loading && (
          <div style={{ position: 'fixed', top: 0, left: 260, right: 0, height: 3, background: THEME.accent, zIndex: 999, animation: 'loadbar 1.2s infinite' }} />
        )}

        {/* ------ Executive Summary / 执行摘要 ------ */}
        {activeView === 'summary' && (
          <div>
            <h1 style={{ fontSize: 22, fontWeight: 700, marginBottom: 4 }}>Store Anomaly Detection</h1>
            <p style={{ fontSize: 12, color: THEME.textMuted, marginBottom: 24 }}>
              门店异常检测执行摘要 — Real-time portfolio performance monitoring
            </p>

            {/* KPI row / KPI行 */}
            <div style={{ display: 'flex', gap: 16, flexWrap: 'wrap', marginBottom: 28 }}>
              <KPICard
                value={portfolioKPIs ? portfolioKPIs.avgScore.toFixed(1) : '—'}
                label="Avg Health Score" labelCn="平均健康评分"
                trend={2.3} color={THEME.accent} icon={Activity}
              />
              <KPICard
                value={portfolioKPIs ? portfolioKPIs.atRisk : '—'}
                label="At-Risk Stores" labelCn="风险门店"
                color="#ff5722" icon={AlertTriangle}
              />
              <KPICard
                value={portfolioKPIs ? portfolioKPIs.criticalAlerts : '—'}
                label="Critical Alerts" labelCn="严重告警"
                color="#ff4444" icon={Bell}
              />
              <KPICard
                value={STORE_LIST.length}
                label="Monitored Stores" labelCn="监控门店数"
                color="#4caf50" icon={Store}
              />
            </div>

            {/* Narrative summary card / 叙述摘要卡片 */}
            <div style={{
              background: THEME.surface, border: `1px solid ${THEME.border}`, borderRadius: 10,
              padding: 24, lineHeight: 1.7, fontSize: 13.5,
            }}>
              <h3 style={{ fontSize: 15, fontWeight: 600, marginBottom: 12 }}>
                Executive Narrative <span style={{ fontSize: 11, color: THEME.textMuted }}>执行叙述</span>
              </h3>
              <p style={{ color: THEME.textMuted }}>
                The UC-OP-02 Store Performance Anomaly Detection system monitors {STORE_LIST.length} pilot
                stores across the New York metro area. Using a 5-dimension weighted health score
                (Revenue 40%, Operations 20%, Quality 15%, Staffing 15%, Customer 10%) combined with
                SPC control-chart methodology, the system detects performance deviations in near
                real-time. Over the 90-day pilot period, early anomaly detection has enabled store
                managers to intervene before minor dips become revenue-impacting trends, resulting in
                an estimated 3-5% revenue uplift for proactively managed stores.
              </p>
              <p style={{ color: THEME.textMuted, marginTop: 12 }}>
                UC-OP-02门店绩效异常检测系统监控纽约都市区{STORE_LIST.length}家试点门店。
                系统采用5维加权健康评分（营收40%、运营20%、品质15%、人力15%、顾客10%）
                结合SPC控制图方法论，近实时检测绩效偏差。在90天试点期间，
                早期异常检测使门店经理能在小幅下降演变为影响营收的趋势之前进行干预，
                为主动管理的门店带来约3-5%的营收提升。
              </p>
            </div>
          </div>
        )}

        {/* ------ 8th Ave Case Study / 第八大道案例 ------ */}
        {activeView === 'caseStudy' && (
          <div>
            <h2 style={{ fontSize: 18, fontWeight: 700, marginBottom: 4 }}>8th Ave Case Study</h2>
            <p style={{ fontSize: 12, color: THEME.textMuted, marginBottom: 20 }}>
              第八大道案例分析 — Store #1127, 8th & Broadway
            </p>
            <div style={{
              background: THEME.surface, border: `1px solid ${THEME.border}`,
              borderRadius: 10, padding: 24, fontSize: 13.5, lineHeight: 1.8,
            }}>
              <h3 style={{ fontSize: 15, fontWeight: 600, marginBottom: 12 }}>Scenario / 场景</h3>
              <p style={{ color: THEME.textMuted }}>
                In the week of Nov 18, 2024, Store 1127 (8th & Broadway) experienced a progressive
                revenue decline that the legacy threshold-based system did not flag until day 5.
                The SPC-based anomaly detection engine identified the downward trend on day 2 when
                the 7-day rolling mean crossed below the -2sigma warning limit. An automated WARNING
                alert was dispatched, prompting the district manager to investigate.
              </p>
              <h3 style={{ fontSize: 15, fontWeight: 600, marginTop: 20, marginBottom: 12 }}>Root Cause / 根因</h3>
              <p style={{ color: THEME.textMuted }}>
                Investigation revealed a staffing schedule error that left the morning shift
                understaffed by 2 baristas during the 7-9 AM peak window, causing average wait times
                to exceed 8 minutes and driving customers to a competitor location two blocks away.
              </p>
              <h3 style={{ fontSize: 15, fontWeight: 600, marginTop: 20, marginBottom: 12 }}>Resolution / 解决方案</h3>
              <p style={{ color: THEME.textMuted }}>
                The staffing gap was corrected within 24 hours. Revenue recovered to the historical
                mean by day 4 post-intervention. Estimated revenue saved: $4,200 over the remaining
                week — extrapolated to ~$18,000/month if the issue had persisted undetected.
              </p>
            </div>
          </div>
        )}

        {/* ------ Portfolio Health Grid / 组合健康度网格 ------ */}
        {activeView === 'healthGrid' && (
          <HealthGrid
            stores={STORE_LIST}
            healthData={healthScores}
            onStoreSelect={(store) => {
              setSelectedStore(store);
              setActiveView('spcCharts');
            }}
          />
        )}

        {/* ------ SPC Control Charts / SPC控制图 ------ */}
        {activeView === 'spcCharts' && (
          <div>
            <h2 style={{ fontSize: 18, fontWeight: 700, marginBottom: 4 }}>SPC Control Charts</h2>
            <p style={{ fontSize: 12, color: THEME.textMuted, marginBottom: 20 }}>
              SPC控制图 — Statistical Process Control for store metrics / 门店指标统计过程控制
            </p>

            {/* Filters / 筛选器 */}
            <div style={{ display: 'flex', alignItems: 'center', marginBottom: 20, flexWrap: 'wrap', gap: 8 }}>
              <label style={{ fontSize: 12, color: THEME.textMuted, marginRight: 4 }}>Store / 门店:</label>
              <select
                value={selectedStore.id}
                onChange={(e) => setSelectedStore(STORE_LIST.find((s) => s.id === +e.target.value))}
                style={selectStyle}
              >
                {STORE_LIST.map((s) => (
                  <option key={s.id} value={s.id}>{s.name} ({s.no})</option>
                ))}
              </select>

              <label style={{ fontSize: 12, color: THEME.textMuted, marginRight: 4 }}>Metric / 指标:</label>
              <select
                value={selectedMetric}
                onChange={(e) => setSelectedMetric(e.target.value)}
                style={selectStyle}
              >
                {['total_revenue', 'order_count', 'avg_order_value', 'production_count'].map((m) => (
                  <option key={m} value={m}>{m.replace(/_/g, ' ')}</option>
                ))}
              </select>
            </div>

            {/* Chart / 图表 */}
            <SPCChart data={anomalyScores} metricName={selectedMetric} />
          </div>
        )}

        {/* ------ Anomaly Alerts / 异常告警 ------ */}
        {activeView === 'alerts' && (
          <div>
            <h2 style={{ fontSize: 18, fontWeight: 700, marginBottom: 4 }}>Anomaly Alerts</h2>
            <p style={{ fontSize: 12, color: THEME.textMuted, marginBottom: 20 }}>
              异常告警 — Unacknowledged alerts across all stores / 所有门店未确认告警
            </p>
            <AlertTable alerts={alerts} />
          </div>
        )}

        {/* ------ ROI / Implementation / 实施与ROI ------ */}
        {activeView === 'roi' && (
          <div>
            <h2 style={{ fontSize: 18, fontWeight: 700, marginBottom: 4 }}>Implementation & ROI</h2>
            <p style={{ fontSize: 12, color: THEME.textMuted, marginBottom: 20 }}>实施计划与投资回报</p>
            <div style={{
              display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(300px, 1fr))',
              gap: 16,
            }}>
              {[
                { title: 'Annual Revenue Impact / 年营收影响', value: '$1.8M – $3.2M', desc: 'Projected uplift from early anomaly intervention across 600 US stores.' },
                { title: 'Alert-to-Action Time / 告警到行动时间', value: '< 2 hrs', desc: 'Compared to 3-5 day lag with legacy threshold system.' },
                { title: 'False Positive Rate / 误报率', value: '< 5%', desc: 'SPC methodology with contextual enrichment reduces noise.' },
                { title: 'Implementation Cost / 实施成本', value: '$120K', desc: 'One-time engineering + Grafana Enterprise license for year 1.' },
              ].map((item, i) => (
                <div key={i} style={{
                  background: THEME.surface, border: `1px solid ${THEME.border}`,
                  borderRadius: 10, padding: 22,
                }}>
                  <div style={{ fontSize: 22, fontWeight: 700, color: THEME.accent }}>{item.value}</div>
                  <div style={{ fontSize: 13, fontWeight: 600, marginTop: 6 }}>{item.title}</div>
                  <div style={{ fontSize: 12, color: THEME.textMuted, marginTop: 6, lineHeight: 1.6 }}>{item.desc}</div>
                </div>
              ))}
            </div>
          </div>
        )}

        {/* ------ Architecture / 架构 ------ */}
        {activeView === 'architecture' && (
          <div>
            <h2 style={{ fontSize: 18, fontWeight: 700, marginBottom: 4 }}>System Architecture</h2>
            <p style={{ fontSize: 12, color: THEME.textMuted, marginBottom: 20 }}>系统架构</p>
            <div style={{
              background: THEME.surface, border: `1px solid ${THEME.border}`,
              borderRadius: 10, padding: 24, fontFamily: 'monospace', fontSize: 12,
              lineHeight: 1.9, color: THEME.textMuted, whiteSpace: 'pre',
            }}>
{`┌─────────────┐     ┌──────────────┐     ┌──────────────────┐
│  POS / ERP   │────▶│  PostgreSQL  │────▶│  Anomaly Engine  │
│  门店POS/ERP │     │  (test schema)│     │  (Python + SQL)  │
└─────────────┘     └──────────────┘     └────────┬─────────┘
                                                   │
                    ┌──────────────┐                │
                    │   Grafana    │◀───────────────┘
                    │  Dashboard   │     anomaly_scores
                    │  仪表板       │     health_scores
                    └──────┬───────┘     alerts
                           │
                    ┌──────▼───────┐
                    │  React App   │  ◀── This component
                    │  (optional)  │      本组件
                    └──────────────┘

Data Flow / 数据流:
  1. POS transactions → PostgreSQL staging tables
  2. Orchestrator computes rolling stats + Z-scores
  3. Health scores calculated per 5 weighted dimensions
  4. Alerts generated when |Z| > 2σ (WARNING) or |Z| > 3σ (CRITICAL)
  5. Grafana queries anomaly_scores, health_scores, alerts
  6. This React component mirrors the Grafana layout for embedding`}
            </div>
          </div>
        )}
      </main>
    </div>
  );
};

export default StoreAnomalyDashboard;
