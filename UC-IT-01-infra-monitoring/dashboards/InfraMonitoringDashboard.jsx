/**
 * UC-IT-01: Predictive Infrastructure Monitoring / 预测性基础设施监控
 * React Reference Dashboard Component
 * Displays infrastructure health scores, anomaly alerts, and SPC control charts.
 * Data Source: test.infra_* tables via REST API
 * Dependencies: React 18+, recharts, lucide-react
 * Author: Data Engineering / BI Team  |  Created: 2026-02-15
 */
import React, { useState, useEffect, useMemo, useCallback } from 'react';
import {
  LineChart, Line, XAxis, YAxis, CartesianGrid, Tooltip, Legend,
  ResponsiveContainer, ReferenceLine, PieChart, Pie, Cell,
} from 'recharts';
import {
  Activity, AlertTriangle, CheckCircle, Server, Shield,
  TrendingUp, TrendingDown, Clock, RefreshCw, Search,
} from 'lucide-react';

// --- 1. Constants / 常量 -------------------------------------------------------
/** Health grade color mapping / 健康等级颜色 */
const HEALTH_GRADES = { A: '#4caf50', B: '#2196f3', C: '#ff9800', D: '#ff5722', F: '#f44336' };
/** Alert severity color mapping / 告警等级颜色 */
const SEVERITY_COLORS = { EMERGENCY: '#d32f2f', CRITICAL: '#f44336', WARNING: '#ff9800', INFO: '#2196f3', NONE: '#4caf50' };
/** Monitored service types / 监控服务类型 */
const SERVICE_TYPES = ['REDIS', 'RDS', 'EC2', 'EKS', 'MSK', 'DOCDB', 'OPENSEARCH', 'EMR'];
/** Health dimension weights / 健康维度权重 */
const HEALTH_WEIGHTS = { availability: 0.30, performance: 0.25, capacity: 0.25, error_rate: 0.10, latency: 0.10 };
/** Dashboard tab definitions / 仪表板标签页 */
const VIEW_TABS = [
  { key: 'overview', label: 'Overview / 概览' },      { key: 'fleet', label: 'Fleet Health / 集群健康' },
  { key: 'alerts',   label: 'Anomaly Alerts / 异常告警' }, { key: 'spc', label: 'SPC Charts / SPC 控制图' },
  { key: 'pipeline', label: 'Pipeline Status / 管道状态' },
];
const API_BASE = '/api/infra';

// --- 2. Custom Hooks / 自定义 Hooks --------------------------------------------
/** Fetch fleet instances / 获取集群实例 @param {string} serviceType */
const useFleetData = (serviceType) => {
  const [instances, setInstances] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);
  useEffect(() => {
    setLoading(true);
    const qs = serviceType && serviceType !== 'ALL' ? `?service_type=${serviceType}` : '';
    fetch(`${API_BASE}/fleet${qs}`)
      .then((r) => r.json()).then((d) => { setInstances(d.instances ?? []); setError(null); })
      .catch((e) => setError(e.message)).finally(() => setLoading(false));
  }, [serviceType]);
  return { instances, loading, error };
};

/** Fetch anomaly alerts / 获取异常告警 @param {string} severity @param {number} days */
const useAnomalyAlerts = (severity = 'INFO', days = 7) => {
  const [alerts, setAlerts] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);
  useEffect(() => {
    setLoading(true);
    fetch(`${API_BASE}/alerts?severity=${severity}&days=${days}`)
      .then((r) => r.json()).then((d) => { setAlerts(d.alerts ?? []); setError(null); })
      .catch((e) => setError(e.message)).finally(() => setLoading(false));
  }, [severity, days]);
  return { alerts, loading, error };
};

/** Fetch health scores over time / 获取健康评分趋势 @param {string} serviceType @param {number} days */
const useHealthScores = (serviceType, days = 30) => {
  const [scores, setScores] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);
  useEffect(() => {
    setLoading(true);
    const p = new URLSearchParams({ days });
    if (serviceType && serviceType !== 'ALL') p.set('service_type', serviceType);
    fetch(`${API_BASE}/health?${p}`)
      .then((r) => r.json()).then((d) => { setScores(d.scores ?? []); setError(null); })
      .catch((e) => setError(e.message)).finally(() => setLoading(false));
  }, [serviceType, days]);
  return { scores, loading, error };
};

/** Fetch SPC chart data / 获取 SPC 数据 @param {string} instanceId @param {string} metricName @param {number} days */
const useSPCData = (instanceId, metricName, days = 30) => {
  const [data, setData] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);
  useEffect(() => {
    if (!instanceId || !metricName) { setLoading(false); return; }
    setLoading(true);
    fetch(`${API_BASE}/spc?${new URLSearchParams({ instance: instanceId, metric: metricName, days })}`)
      .then((r) => r.json()).then((d) => { setData(d.data ?? []); setError(null); })
      .catch((e) => setError(e.message)).finally(() => setLoading(false));
  }, [instanceId, metricName, days]);
  return { data, loading, error };
};

// --- 3. Sub-components / 子组件 ------------------------------------------------

/** FleetOverview - Six KPI stat cards / 集群概览六项 KPI */
const FleetOverview = () => {
  const { instances, loading } = useFleetData('ALL');
  const { alerts } = useAnomalyAlerts('WARNING', 7);
  const stats = useMemo(() => {
    if (!instances.length) return null;
    const n = instances.length;
    const avgH = instances.reduce((s, i) => s + (i.composite_score ?? 0), 0) / n;
    const actA = alerts.filter((a) => !a.acknowledged).length;
    const svc  = new Set(instances.map((i) => i.service_type)).size;
    const cov  = instances.filter((i) => i.monitored).length / n * 100;
    const avgZ = instances.reduce((s, i) => s + Math.abs(i.z_score ?? 0), 0) / n;
    return { n, avgH, actA, svc, cov, avgZ };
  }, [instances, alerts]);
  if (loading || !stats) return <div style={S.loading}>Loading fleet overview... / 正在加载集群概览...</div>;
  const cards = [
    { title: 'Total Instances / 实例总数', value: stats.n, icon: <Server size={20} />, color: '#2196f3' },
    { title: 'Fleet Health / 集群健康', value: `${stats.avgH.toFixed(1)}%`, icon: <Shield size={20} />, color: stats.avgH >= 80 ? '#4caf50' : '#ff9800' },
    { title: 'Active Alerts / 活跃告警', value: stats.actA, icon: <AlertTriangle size={20} />, color: stats.actA > 10 ? '#f44336' : '#ff9800' },
    { title: 'Services / 服务类型', value: stats.svc, icon: <Activity size={20} />, color: '#9c27b0' },
    { title: 'Coverage / 覆盖率', value: `${stats.cov.toFixed(1)}%`, icon: <CheckCircle size={20} />, color: '#4caf50' },
    { title: 'Avg |Z-Score|', value: stats.avgZ.toFixed(2), icon: <TrendingUp size={20} />, color: stats.avgZ > 2 ? '#f44336' : '#2196f3' },
  ];
  return (
    <div style={S.kpiGrid}>
      {cards.map((c) => (
        <div key={c.title} style={{ ...S.card, borderTop: `3px solid ${c.color}` }}>
          <div style={S.kpiIcon}>{c.icon}</div>
          <div style={S.kpiValue}>{c.value}</div>
          <div style={S.kpiLabel}>{c.title}</div>
        </div>
      ))}
    </div>
  );
};

/** HealthScoreCard - Instance health donut card / 实例健康环形图卡片 @param {{ instance: object }} props */
const HealthScoreCard = ({ instance }) => {
  const score = instance.composite_score ?? 0;
  const grade = score >= 90 ? 'A' : score >= 75 ? 'B' : score >= 60 ? 'C' : score >= 40 ? 'D' : 'F';
  const gc = HEALTH_GRADES[grade];
  const trend = instance.score_trend ?? 0;
  const donut = [{ name: 'Score', value: score }, { name: 'Rest', value: 100 - score }];
  return (
    <div style={{ ...S.card, width: 260 }}>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
        <span style={{ fontWeight: 600, fontSize: 14 }}>{instance.instance_id}</span>
        <span style={{ fontSize: 12, color: '#8899aa' }}>{instance.service_type}</span>
      </div>
      <div style={{ display: 'flex', alignItems: 'center', gap: 12, marginTop: 12 }}>
        <PieChart width={80} height={80}>
          <Pie data={donut} innerRadius={25} outerRadius={35} dataKey="value" startAngle={90} endAngle={-270}>
            <Cell fill={gc} /><Cell fill="#2d4050" />
          </Pie>
        </PieChart>
        <div>
          <div style={{ fontSize: 28, fontWeight: 700, color: gc }}>{grade}</div>
          <div style={{ fontSize: 13, color: '#8899aa' }}>
            {score.toFixed(1)}% {trend > 0 ? <TrendingUp size={14} color="#4caf50" /> : trend < 0 ? <TrendingDown size={14} color="#f44336" /> : null}
          </div>
        </div>
      </div>
      <div style={{ marginTop: 12, fontSize: 12, color: '#8899aa' }}>
        {Object.entries(HEALTH_WEIGHTS).map(([dim, w]) => (
          <div key={dim} style={{ display: 'flex', justifyContent: 'space-between', marginBottom: 2 }}>
            <span>{dim} ({(w * 100).toFixed(0)}%)</span><span>{instance[`${dim}_score`] ?? '-'}</span>
          </div>
        ))}
      </div>
    </div>
  );
};

/** ServiceFleetGrid - Searchable / sortable grid of HealthScoreCards / 集群网格 @param {{ serviceType: string }} props */
const ServiceFleetGrid = ({ serviceType }) => {
  const { instances, loading } = useFleetData(serviceType);
  const [search, setSearch] = useState('');
  const [sortBy, setSortBy] = useState('composite_score');
  const filtered = useMemo(() => {
    let list = instances;
    if (search) list = list.filter((i) => i.instance_id?.toLowerCase().includes(search.toLowerCase()));
    return [...list].sort((a, b) => (a[sortBy] ?? 0) - (b[sortBy] ?? 0));
  }, [instances, search, sortBy]);
  if (loading) return <div style={S.loading}>Loading fleet... / 正在加载集群...</div>;
  return (
    <div>
      <div style={{ display: 'flex', gap: 12, marginBottom: 16 }}>
        <div style={S.inputGroup}><Search size={14} />
          <input style={S.input} placeholder="Search instance / 搜索实例..." value={search} onChange={(e) => setSearch(e.target.value)} />
        </div>
        <select style={S.select} value={sortBy} onChange={(e) => setSortBy(e.target.value)}>
          <option value="composite_score">Score / 评分</option>
          <option value="instance_id">Instance ID</option>
          <option value="service_type">Service / 服务</option>
        </select>
      </div>
      <div style={S.fleetGrid}>
        {filtered.map((inst) => <HealthScoreCard key={inst.instance_id} instance={inst} />)}
        {filtered.length === 0 && <div style={S.empty}>No instances found / 无实例</div>}
      </div>
    </div>
  );
};

/** AnomalyAlertTable - Sortable alert table with severity badges / 异常告警表 */
const AnomalyAlertTable = () => {
  const { alerts, loading } = useAnomalyAlerts('INFO', 14);
  const [sortCol, setSortCol] = useState('detected_at');
  const [sortAsc, setSortAsc] = useState(false);
  const handleSort = useCallback((col) => {
    setSortAsc((prev) => (col === sortCol ? !prev : false));
    setSortCol(col);
  }, [sortCol]);
  const sorted = useMemo(() => {
    const d = sortAsc ? 1 : -1;
    return [...alerts].sort((a, b) => (a[sortCol] > b[sortCol] ? d : -d));
  }, [alerts, sortCol, sortAsc]);
  if (loading) return <div style={S.loading}>Loading alerts... / 正在加载告警...</div>;
  const cols = [
    { key: 'severity', label: 'Severity / 等级' },     { key: 'instance_id', label: 'Instance / 实例' },
    { key: 'metric_name', label: 'Metric / 指标' },    { key: 'description_en', label: 'Description / 描述' },
    { key: 'z_score', label: 'Z-Score' },               { key: 'detected_at', label: 'Detected / 检测时间' },
    { key: 'actions', label: 'Actions / 操作' },
  ];
  return (
    <div style={{ overflowX: 'auto' }}>
      <table style={S.table}>
        <thead><tr>
          {cols.map((c) => (
            <th key={c.key} style={S.th} onClick={() => c.key !== 'actions' && handleSort(c.key)}>
              {c.label} {sortCol === c.key ? (sortAsc ? '▲' : '▼') : ''}
            </th>
          ))}
        </tr></thead>
        <tbody>
          {sorted.map((a, i) => (
            <tr key={a.alert_id ?? i} style={i % 2 === 0 ? S.trEven : S.trOdd}>
              <td style={S.td}><span style={{ ...S.badge, backgroundColor: SEVERITY_COLORS[a.severity] ?? '#666' }}>{a.severity}</span></td>
              <td style={S.td}>{a.instance_id}</td>
              <td style={S.td}>{a.metric_name}</td>
              <td style={S.td}><div>{a.description_en}</div><div style={{ fontSize: 11, color: '#8899aa' }}>{a.description_cn}</div></td>
              <td style={S.td}>{(a.z_score ?? 0).toFixed(2)}</td>
              <td style={S.td}>{a.detected_at}</td>
              <td style={S.td}>{!a.acknowledged && <button style={S.ackBtn} onClick={() => console.log('ACK', a.alert_id)}>Ack / 确认</button>}</td>
            </tr>
          ))}
        </tbody>
      </table>
      {sorted.length === 0 && <div style={S.empty}>No active alerts / 无活跃告警</div>}
    </div>
  );
};

/** SPCControlChart - Interactive SPC chart with UCL/LCL and WE violations / SPC 控制图 */
const SPCControlChart = ({ instance, metric, days = 30 }) => {
  const { data, loading } = useSPCData(instance, metric, days);
  const cl = useMemo(() => {
    if (!data.length) return { mean: 0, ucl2: 0, lcl2: 0, ucl3: 0, lcl3: 0 };
    const m = data.reduce((s, d) => s + (d.rolling_mean ?? d.value), 0) / data.length;
    const sd = Math.sqrt(data.reduce((s, d) => s + Math.pow(d.value - m, 2), 0) / data.length);
    return { mean: m, ucl2: m + 2 * sd, lcl2: m - 2 * sd, ucl3: m + 3 * sd, lcl3: m - 3 * sd };
  }, [data]);
  const violations = useMemo(() => data.filter((d) => d.we_rule_violation), [data]);
  if (loading) return <div style={S.loading}>Loading SPC data... / 正在加载 SPC 数据...</div>;
  if (!instance) return <div style={S.empty}>Select an instance to view SPC chart / 请选择实例以查看 SPC 图</div>;
  /** Custom tooltip / 自定义提示 */
  const Tip = ({ active, payload }) => {
    if (!active || !payload?.length) return null;
    const d = payload[0].payload;
    return (
      <div style={{ ...S.card, padding: 10, fontSize: 12 }}>
        <div><strong>{d.timestamp}</strong></div>
        <div>Value / 值: {d.value?.toFixed(4)}</div>
        <div>Z-Score: {d.z_score?.toFixed(2)}</div>
        <div>Rolling Mean / 滚动均值: {d.rolling_mean?.toFixed(4)}</div>
        {d.we_rule_violation && <div style={{ color: '#f44336' }}>WE Rule Violation / 违反 WE 规则</div>}
      </div>
    );
  };
  return (
    <div style={S.card}>
      <h3 style={{ margin: '0 0 16px' }}>SPC Control Chart / SPC 控制图</h3>
      <ResponsiveContainer width="100%" height={360}>
        <LineChart data={data} margin={{ top: 10, right: 30, left: 0, bottom: 0 }}>
          <CartesianGrid strokeDasharray="3 3" stroke="#2d4050" />
          <XAxis dataKey="timestamp" tick={{ fill: '#8899aa', fontSize: 11 }} />
          <YAxis tick={{ fill: '#8899aa', fontSize: 11 }} />
          <Tooltip content={<Tip />} /><Legend />
          <Line type="monotone" dataKey="value" stroke="#1a8cff" dot={false} name="Value / 值" />
          <Line type="monotone" dataKey="rolling_mean" stroke="#4caf50" dot={false} strokeDasharray="5 5" name="Mean / 均值" />
          <ReferenceLine y={cl.ucl3} stroke="#f44336" strokeDasharray="4 4" label={{ value: 'UCL 3σ', fill: '#f44336', fontSize: 10 }} />
          <ReferenceLine y={cl.lcl3} stroke="#f44336" strokeDasharray="4 4" label={{ value: 'LCL 3σ', fill: '#f44336', fontSize: 10 }} />
          <ReferenceLine y={cl.ucl2} stroke="#ff9800" strokeDasharray="2 4" label={{ value: '2σ', fill: '#ff9800', fontSize: 10 }} />
          <ReferenceLine y={cl.lcl2} stroke="#ff9800" strokeDasharray="2 4" label={{ value: '2σ', fill: '#ff9800', fontSize: 10 }} />
          <ReferenceLine y={cl.mean} stroke="#4caf50" strokeDasharray="1 2" />
        </LineChart>
      </ResponsiveContainer>
      {violations.length > 0 && (
        <div style={{ marginTop: 8, fontSize: 12, color: '#ff9800' }}>
          {violations.length} WE rule violation(s) detected / 检测到 {violations.length} 条 WE 规则违反
        </div>
      )}
    </div>
  );
};

/** HealthTrendChart - Composite score trend line chart / 健康趋势图 */
const HealthTrendChart = ({ serviceType, days = 30 }) => {
  const { scores, loading } = useHealthScores(serviceType, days);
  if (loading) return <div style={S.loading}>Loading trend... / 正在加载趋势...</div>;
  return (
    <div style={S.card}>
      <h3 style={{ margin: '0 0 16px' }}>Health Trend / 健康趋势</h3>
      <ResponsiveContainer width="100%" height={280}>
        <LineChart data={scores} margin={{ top: 10, right: 30, left: 0, bottom: 0 }}>
          <CartesianGrid strokeDasharray="3 3" stroke="#2d4050" />
          <XAxis dataKey="date" tick={{ fill: '#8899aa', fontSize: 11 }} />
          <YAxis domain={[0, 100]} tick={{ fill: '#8899aa', fontSize: 11 }} />
          <Tooltip contentStyle={{ backgroundColor: '#1e2d3d', border: '1px solid #2d4050', color: '#e8edf2' }} />
          <Legend />
          <Line type="monotone" dataKey="avg_score" stroke="#1a8cff" name="Avg Score / 平均分" />
          <Line type="monotone" dataKey="min_score" stroke="#ff5722" strokeDasharray="3 3" name="Min / 最低" />
          <ReferenceLine y={60} stroke="#ff9800" strokeDasharray="4 4" label={{ value: 'Threshold / 阈值', fill: '#ff9800', fontSize: 10 }} />
        </LineChart>
      </ResponsiveContainer>
    </div>
  );
};

/** PipelineStatus - Recent ETL pipeline runs / 管道状态 */
const PipelineStatus = () => {
  const [runs, setRuns] = useState([]);
  const [loading, setLoading] = useState(true);
  useEffect(() => {
    fetch(`${API_BASE}/pipeline/runs?limit=10`)
      .then((r) => r.json()).then((d) => setRuns(d.runs ?? []))
      .catch(() => {}).finally(() => setLoading(false));
  }, []);
  if (loading) return <div style={S.loading}>Loading pipeline status... / 正在加载管道状态...</div>;
  const icon = (st) => {
    if (st === 'SUCCESS') return <CheckCircle size={14} color="#4caf50" />;
    if (st === 'RUNNING') return <RefreshCw size={14} color="#2196f3" />;
    if (st === 'FAILED')  return <AlertTriangle size={14} color="#f44336" />;
    return <Clock size={14} color="#8899aa" />;
  };
  return (
    <div>
      {runs.map((r) => (
        <div key={r.run_id} style={{ ...S.card, marginBottom: 12 }}>
          <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: 8 }}>
            <span style={{ fontWeight: 600 }}>Run #{r.run_id}</span>
            <span style={{ fontSize: 12, color: '#8899aa' }}>{r.started_at}</span>
          </div>
          <div style={{ display: 'flex', gap: 16, flexWrap: 'wrap' }}>
            {(r.steps ?? []).map((step) => (
              <div key={step.name} style={{ display: 'flex', alignItems: 'center', gap: 4, fontSize: 13 }}>{icon(step.status)} {step.name}</div>
            ))}
          </div>
          {r.error_message && <div style={{ marginTop: 6, fontSize: 12, color: '#f44336' }}>{r.error_message}</div>}
        </div>
      ))}
      {runs.length === 0 && <div style={S.empty}>No pipeline runs found / 无管道运行记录</div>}
    </div>
  );
};

// --- 4. Main Component / 主组件 ------------------------------------------------
/** InfraMonitoringDashboard - Top-level dashboard with tab navigation / 顶层仪表板 */
const InfraMonitoringDashboard = () => {
  const [activeView, setActiveView] = useState('overview');
  const [selectedService, setSelectedService] = useState('ALL');
  const [selectedInstance, setSelectedInstance] = useState(null);
  const [selectedMetric, setSelectedMetric] = useState('memory_used_bytes');
  const [timeRange, setTimeRange] = useState(30);
  return (
    <div className="infra-dashboard" style={S.container}>
      <header style={S.header}>
        <h1 style={{ margin: 0, fontSize: 22 }}>UC-IT-01: Infrastructure Health Monitor</h1>
        <p style={{ margin: '4px 0 0', opacity: 0.85, fontSize: 14 }}>预测性基础设施监控</p>
      </header>
      <nav style={S.tabBar}>
        {VIEW_TABS.map((t) => (
          <button key={t.key} style={activeView === t.key ? { ...S.tab, ...S.tabActive } : S.tab} onClick={() => setActiveView(t.key)}>{t.label}</button>
        ))}
        {activeView === 'fleet' && (
          <select style={{ ...S.select, marginLeft: 'auto' }} value={selectedService} onChange={(e) => setSelectedService(e.target.value)}>
            <option value="ALL">All Services / 所有服务</option>
            {SERVICE_TYPES.map((s) => <option key={s} value={s}>{s}</option>)}
          </select>
        )}
        <select style={{ ...S.select, marginLeft: activeView !== 'fleet' ? 'auto' : 8 }} value={timeRange} onChange={(e) => setTimeRange(Number(e.target.value))}>
          <option value={7}>7 Days / 7 天</option><option value={14}>14 Days / 14 天</option>
          <option value={30}>30 Days / 30 天</option><option value={90}>90 Days / 90 天</option>
        </select>
      </nav>
      <main style={S.content}>
        {activeView === 'overview' && <><FleetOverview /><HealthTrendChart serviceType={selectedService} days={timeRange} /></>}
        {activeView === 'fleet' && <ServiceFleetGrid serviceType={selectedService} />}
        {activeView === 'alerts' && <AnomalyAlertTable />}
        {activeView === 'spc' && (
          <div>
            <div style={{ display: 'flex', gap: 12, marginBottom: 16 }}>
              <input style={S.input} placeholder="Instance ID / 实例 ID" value={selectedInstance ?? ''} onChange={(e) => setSelectedInstance(e.target.value || null)} />
              <select style={S.select} value={selectedMetric} onChange={(e) => setSelectedMetric(e.target.value)}>
                <option value="memory_used_bytes">Memory / 内存</option><option value="cpu_utilization">CPU</option>
                <option value="connections_active">Connections / 连接数</option><option value="disk_io_bytes">Disk I/O</option>
                <option value="network_bytes_in">Network In / 入站流量</option>
              </select>
            </div>
            <SPCControlChart instance={selectedInstance} metric={selectedMetric} days={timeRange} />
          </div>
        )}
        {activeView === 'pipeline' && <PipelineStatus />}
      </main>
      <footer style={S.footer}>UC-IT-01 Predictive Infrastructure Monitoring | Data Engineering Team | React Reference Dashboard</footer>
    </div>
  );
};

// --- 5. Inline Styles / 内联样式 ------------------------------------------------
const S = {
  container:  { backgroundColor: '#0f1419', color: '#e8edf2', minHeight: '100vh', fontFamily: 'Inter, system-ui, sans-serif', padding: 24 },
  header:     { background: 'linear-gradient(135deg, #00529B, #1a8cff)', padding: '24px 32px', borderRadius: 10, marginBottom: 20 },
  tabBar:     { display: 'flex', alignItems: 'center', gap: 4, backgroundColor: '#1e2d3d', padding: 6, borderRadius: 10, marginBottom: 20, flexWrap: 'wrap' },
  tab:        { padding: '8px 16px', backgroundColor: 'transparent', color: '#8899aa', border: 'none', borderRadius: 6, cursor: 'pointer', fontSize: 13, whiteSpace: 'nowrap' },
  tabActive:  { backgroundColor: '#00529B', color: '#ffffff' },
  content:    { minHeight: 400 },
  card:       { backgroundColor: '#1e2d3d', borderRadius: 10, padding: 20, border: '1px solid #2d4050' },
  kpiGrid:    { display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(200px, 1fr))', gap: 16, marginBottom: 20 },
  kpiIcon:    { marginBottom: 8, opacity: 0.7 },
  kpiValue:   { fontSize: 28, fontWeight: 700, marginBottom: 4 },
  kpiLabel:   { fontSize: 12, color: '#8899aa' },
  fleetGrid:  { display: 'flex', flexWrap: 'wrap', gap: 16 },
  inputGroup: { display: 'flex', alignItems: 'center', gap: 6, backgroundColor: '#1e2d3d', border: '1px solid #2d4050', borderRadius: 6, padding: '6px 10px' },
  input:      { background: 'transparent', border: 'none', color: '#e8edf2', outline: 'none', fontSize: 13, minWidth: 180 },
  select:     { backgroundColor: '#1e2d3d', color: '#e8edf2', border: '1px solid #2d4050', borderRadius: 6, padding: '6px 10px', fontSize: 13 },
  table:      { width: '100%', borderCollapse: 'collapse', fontSize: 13 },
  th:         { textAlign: 'left', padding: '10px 12px', borderBottom: '2px solid #2d4050', color: '#8899aa', cursor: 'pointer', whiteSpace: 'nowrap', fontSize: 12 },
  td:         { padding: '10px 12px', borderBottom: '1px solid #2d4050' },
  trEven:     { backgroundColor: '#1e2d3d' },
  trOdd:      { backgroundColor: '#17242f' },
  badge:      { padding: '2px 8px', borderRadius: 4, color: '#fff', fontSize: 11, fontWeight: 600 },
  ackBtn:     { padding: '4px 12px', backgroundColor: '#00529B', color: '#fff', border: 'none', borderRadius: 4, cursor: 'pointer', fontSize: 12 },
  loading:    { padding: 40, textAlign: 'center', color: '#8899aa' },
  empty:      { padding: 40, textAlign: 'center', color: '#556677' },
  footer:     { marginTop: 40, padding: 16, textAlign: 'center', fontSize: 12, color: '#556677', borderTop: '1px solid #2d4050' },
};

// --- 6. Export / 导出 ----------------------------------------------------------
export default InfraMonitoringDashboard;
