import React, { useState } from 'react';
import { AREA_TYPE_OPTIONS } from '../lib/constants.js';

export default function InputForm({ onAnalyze, loading, loadingStage }) {
  const [address, setAddress] = useState('');
  const [rentMonthly, setRentMonthly] = useState('');
  const [sqft, setSqft] = useState('');
  const [areaType, setAreaType] = useState('mixed_commercial');
  const [weekdayPct, setWeekdayPct] = useState(0.60);
  const [showOverrides, setShowOverrides] = useState(false);
  const [enriched, setEnriched] = useState(false);
  const [enrichData, setEnrichData] = useState(null);
  const [fetchingData, setFetchingData] = useState(false);

  // Override fields
  const [lat, setLat] = useState('');
  const [lon, setLon] = useState('');
  const [medianIncome, setMedianIncome] = useState('');
  const [subwayCount, setSubwayCount] = useState('');
  const [walkScore, setWalkScore] = useState('');
  const [competitorDensity, setCompetitorDensity] = useState('');

  const handleFetchData = async () => {
    if (!address.trim()) return;
    setFetchingData(true);
    try {
      const resp = await fetch('/api/enrich', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ address }),
      });
      const data = await resp.json();
      if (data.error) {
        // API may not be available; allow manual entry
        setEnriched(true);
        return;
      }
      setEnrichData(data);
      if (data.lat != null && !lat) setLat(String(data.lat));
      if (data.lon != null && !lon) setLon(String(data.lon));
      if (data.median_income != null && !medianIncome) setMedianIncome(String(data.median_income));
      if (data.subway_count != null && !subwayCount) setSubwayCount(String(data.subway_count));
      if (data.walk_score != null && !walkScore) setWalkScore(String(data.walk_score));
      if (data.competitor_density != null && !competitorDensity) setCompetitorDensity(String(data.competitor_density));
      setEnriched(true);
    } catch {
      // API not running — proceed with manual entry
      setEnriched(true);
    } finally {
      setFetchingData(false);
    }
  };

  const handleSubmit = (e) => {
    e.preventDefault();
    const formData = {
      address,
      rent_monthly: Number(rentMonthly),
      sqft: Number(sqft),
      area_type: areaType,
      weekday_pct: weekdayPct,
      lat: lat ? Number(lat) : undefined,
      lon: lon ? Number(lon) : undefined,
      median_income: medianIncome ? Number(medianIncome) : undefined,
      subway_count: subwayCount ? Number(subwayCount) : undefined,
      walk_score: walkScore ? Number(walkScore) : undefined,
      competitor_density: competitorDensity ? Number(competitorDensity) : undefined,
    };
    onAnalyze(formData);
  };

  const isValid = address.trim() && rentMonthly && sqft && (enriched || (lat && lon));

  return (
    <div className="bg-card border border-border rounded-card p-6">
      <h2 className="text-lg font-bold text-text-primary mb-1">📍 新址评估 New Location Assessment</h2>
      <p className="text-sm text-text-muted mb-6">输入候选门店信息进行预测分析 Enter candidate store details for predictive analysis</p>

      <form onSubmit={handleSubmit} className="space-y-6">
        {/* Required section */}
        <div>
          <h3 className="text-sm font-semibold text-text-secondary mb-3 uppercase tracking-wide">必填信息 Required</h3>
          <div className="space-y-4">
            <div>
              <label className="block text-sm font-medium text-text-secondary mb-1">地址 Address</label>
              <div className="flex gap-2">
                <input
                  type="text"
                  value={address}
                  onChange={(e) => { setAddress(e.target.value); setEnriched(false); }}
                  className="flex-1 px-3 py-2 border border-border rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-accent-teal/30 focus:border-accent-teal"
                  placeholder="例: 154 Bleecker St, New York, NY 10012"
                />
                <button
                  type="button"
                  onClick={handleFetchData}
                  disabled={!address.trim() || fetchingData}
                  className="px-4 py-2 bg-accent-teal text-white rounded-lg text-sm font-medium hover:bg-accent-teal/90 disabled:opacity-50 disabled:cursor-not-allowed whitespace-nowrap transition-colors"
                >
                  {fetchingData ? '获取中...' : '获取数据 Fetch Data'}
                </button>
              </div>
            </div>

            <div className="grid grid-cols-2 gap-4">
              <div>
                <label className="block text-sm font-medium text-text-secondary mb-1">月租金 Monthly Rent ($)</label>
                <input
                  type="number"
                  value={rentMonthly}
                  onChange={(e) => setRentMonthly(e.target.value)}
                  className="w-full px-3 py-2 border border-border rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-accent-teal/30 focus:border-accent-teal"
                  placeholder="15000"
                />
              </div>
              <div>
                <label className="block text-sm font-medium text-text-secondary mb-1">面积 Square Feet</label>
                <input
                  type="number"
                  value={sqft}
                  onChange={(e) => setSqft(e.target.value)}
                  className="w-full px-3 py-2 border border-border rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-accent-teal/30 focus:border-accent-teal"
                  placeholder="800"
                />
              </div>
            </div>

            <div>
              <label className="block text-sm font-medium text-text-secondary mb-1">区域类型 Area Type</label>
              <select
                value={areaType}
                onChange={(e) => setAreaType(e.target.value)}
                className="w-full px-3 py-2 border border-border rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-accent-teal/30 focus:border-accent-teal bg-white"
              >
                {AREA_TYPE_OPTIONS.map((opt) => (
                  <option key={opt.value} value={opt.value}>{opt.label}</option>
                ))}
              </select>
            </div>
          </div>
        </div>

        {/* Enriched/Override section */}
        {enriched && (
          <div>
            <div className="flex items-center justify-between mb-3">
              <h3 className="text-sm font-semibold text-text-secondary uppercase tracking-wide">
                自动填充数据 Auto-Enriched Data
              </h3>
              <button
                type="button"
                onClick={() => setShowOverrides(!showOverrides)}
                className="text-xs text-accent-teal hover:underline"
              >
                {showOverrides ? '隐藏 Hide' : '手动修改 Override'}
              </button>
            </div>

            {!showOverrides && (
              <div className="grid grid-cols-3 gap-3 text-sm">
                <EnrichedBadge label="纬度 Lat" value={lat || '—'} />
                <EnrichedBadge label="经度 Lon" value={lon || '—'} />
                <EnrichedBadge label="收入 Income" value={medianIncome ? `$${Number(medianIncome).toLocaleString()}` : '—'} />
                <EnrichedBadge label="地铁 Subway" value={subwayCount || '—'} />
                <EnrichedBadge label="步行 Walk Score" value={walkScore || '—'} />
                <EnrichedBadge label="竞品 Competitors" value={competitorDensity || '—'} />
              </div>
            )}

            {showOverrides && (
              <div className="grid grid-cols-2 gap-4">
                <OverrideField label="纬度 Latitude" value={lat} onChange={setLat} placeholder="40.7283" />
                <OverrideField label="经度 Longitude" value={lon} onChange={setLon} placeholder="-73.9996" />
                <OverrideField label="中位收入 Median Income" value={medianIncome} onChange={setMedianIncome} placeholder="85000" />
                <OverrideField label="地铁线数 Subway Lines" value={subwayCount} onChange={setSubwayCount} placeholder="6" />
                <OverrideField label="步行分数 Walk Score" value={walkScore} onChange={setWalkScore} placeholder="95" />
                <OverrideField label="竞品数量 Competitors" value={competitorDensity} onChange={setCompetitorDensity} placeholder="3" />
              </div>
            )}
          </div>
        )}

        {/* Optional: Weekday % slider */}
        <div>
          <h3 className="text-sm font-semibold text-text-secondary mb-3 uppercase tracking-wide">可选参数 Optional</h3>
          <div>
            <label className="block text-sm font-medium text-text-secondary mb-1">
              工作日占比 Weekday %: <span className="font-mono text-accent-teal">{(weekdayPct * 100).toFixed(0)}%</span>
            </label>
            <input
              type="range"
              min="0.40"
              max="0.85"
              step="0.01"
              value={weekdayPct}
              onChange={(e) => setWeekdayPct(Number(e.target.value))}
              className="w-full accent-accent-teal"
            />
            <div className="flex justify-between text-xs text-text-muted">
              <span>40% (周末为主)</span>
              <span>85% (工作日为主)</span>
            </div>
          </div>
        </div>

        {/* Loading overlay */}
        {loading && (
          <div className="p-4 bg-accent-teal/5 border border-accent-teal/20 rounded-lg">
            <div className="flex items-center gap-3">
              <div className="w-5 h-5 border-2 border-accent-teal border-t-transparent rounded-full animate-spin" />
              <span className="text-sm text-accent-teal font-medium">{loadingStage}</span>
            </div>
          </div>
        )}

        {/* Submit */}
        <button
          type="submit"
          disabled={!isValid || loading}
          className="w-full py-3 bg-accent-teal text-white rounded-lg font-medium hover:bg-accent-teal/90 disabled:opacity-50 disabled:cursor-not-allowed transition-colors"
        >
          {loading ? '分析中 Analyzing...' : '开始分析 Analyze'}
        </button>
      </form>
    </div>
  );
}

function EnrichedBadge({ label, value }) {
  return (
    <div className="bg-bg rounded-lg px-3 py-2 border border-border">
      <div className="text-xs text-text-muted">{label}</div>
      <div className="text-sm font-medium text-text-primary metric-value">{value}</div>
    </div>
  );
}

function OverrideField({ label, value, onChange, placeholder }) {
  return (
    <div>
      <label className="block text-xs font-medium text-text-secondary mb-1">{label}</label>
      <input
        type="number"
        step="any"
        value={value}
        onChange={(e) => onChange(e.target.value)}
        className="w-full px-3 py-2 border border-border rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-accent-teal/30 focus:border-accent-teal"
        placeholder={placeholder}
      />
    </div>
  );
}
