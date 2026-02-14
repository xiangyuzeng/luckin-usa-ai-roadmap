import React, { useState } from 'react';
import axios from 'axios';
import LoginScreen from './components/LoginScreen.jsx';
import InputForm from './components/InputForm.jsx';
import ResultsDashboard from './components/ResultsDashboard.jsx';
import { predictWeeklyCups } from './lib/model.js';
import { computeScore, estimateFootTraffic, computeCannibScore, computeAreaTypeScore } from './lib/scoring.js';
import { calculatePL } from './lib/economics.js';
import { STORES, PASSWORD } from './lib/constants.js';

const LOADING_STAGES = [
  '正在获取地址数据 Fetching address data...',
  '正在查询人口统计 Querying demographics...',
  '正在计算模型预测 Computing ML prediction...',
  '正在生成评分报告 Generating score report...',
];

export default function App() {
  const [authed, setAuthed] = useState(false);
  const [loading, setLoading] = useState(false);
  const [loadingStage, setLoadingStage] = useState('');
  const [results, setResults] = useState(null);
  const [inputData, setInputData] = useState(null);
  const [error, setError] = useState('');

  const handleLogin = (pw) => {
    if (pw === PASSWORD) {
      setAuthed(true);
      setError('');
    } else {
      setError('密码错误 Incorrect password');
    }
  };

  const handleAnalyze = async (formData) => {
    setLoading(true);
    setError('');
    setInputData(formData);

    try {
      // Stage 1: Enrich via API
      setLoadingStage(LOADING_STAGES[0]);
      let enriched = {};
      try {
        const resp = await axios.post('/api/enrich', { address: formData.address });
        enriched = resp.data;
      } catch {
        // API may not be running — use manual overrides only
      }

      setLoadingStage(LOADING_STAGES[1]);

      // Merge: form overrides take priority over enriched values
      const lat = formData.lat ?? enriched.lat;
      const lon = formData.lon ?? enriched.lon;
      const medianIncome = formData.median_income ?? enriched.median_income ?? 85000;
      const subwayCount = formData.subway_count ?? enriched.subway_count ?? 0;
      const walkScore = formData.walk_score ?? enriched.walk_score ?? 90;
      const competitorDensity = formData.competitor_density ?? enriched.competitor_density ?? 3;
      const weekdayPct = formData.weekday_pct ?? 0.60;
      const areaType = formData.area_type;
      const rentMonthly = formData.rent_monthly;
      const sqft = formData.sqft;

      if (lat == null || lon == null) {
        setError('无法获取坐标，请手动输入经纬度 Could not get coordinates. Please enter lat/lon manually.');
        setLoading(false);
        return;
      }

      setLoadingStage(LOADING_STAGES[2]);

      // Derive model features
      const footTrafficScore = estimateFootTraffic(areaType, subwayCount, walkScore, competitorDensity);
      const areaTypeScore = computeAreaTypeScore(areaType);
      const nearSubway = subwayCount >= 3 ? 1 : 0;
      const weekendRatio = 1 - weekdayPct;
      const cannibalizationScore = computeCannibScore(lat, lon, STORES);
      const rentPerSqft = sqft > 0 ? rentMonthly / sqft : 100;

      const features = {
        foot_traffic_score: footTrafficScore,
        subway_count: subwayCount,
        weekday_pct: weekdayPct,
        area_type_score: areaTypeScore,
        competitor_density: competitorDensity,
        near_subway: nearSubway,
        median_income: medianIncome,
        rent_per_sqft: rentPerSqft,
        weekend_ratio: weekendRatio,
        cannibalization_score: cannibalizationScore,
      };

      // ML prediction
      const prediction = predictWeeklyCups(features);

      // 5-factor scoring
      const score = computeScore(
        { area_type: areaType, subway_count: subwayCount, weekday_pct: weekdayPct, rent_monthly: rentMonthly, lat, lon },
        STORES
      );

      // P&L
      const pl = calculatePL(prediction.predicted_weekly_cups, rentMonthly, sqft);

      setLoadingStage(LOADING_STAGES[3]);

      // Generate warnings
      const warnings = generateWarnings(lat, lon, rentMonthly, pl, score);

      setResults({
        prediction,
        score,
        pl,
        warnings,
        features,
        enriched: {
          lat, lon, medianIncome, subwayCount, walkScore, competitorDensity,
          formatted_address: enriched.formatted_address || formData.address,
        },
        formData,
      });
    } catch (err) {
      console.error(err);
      setError('分析失败 Analysis failed: ' + (err.message || 'Unknown error'));
    } finally {
      setLoading(false);
      setLoadingStage('');
    }
  };

  const handleBack = () => {
    setResults(null);
  };

  if (!authed) {
    return <LoginScreen onLogin={handleLogin} error={error} />;
  }

  if (results) {
    return <ResultsDashboard results={results} onBack={handleBack} />;
  }

  return (
    <div className="min-h-screen bg-bg">
      <header className="bg-white border-b border-border px-6 py-4 no-print">
        <div className="max-w-5xl mx-auto flex items-center justify-between">
          <div>
            <h1 className="text-xl font-bold text-text-primary">☕ 瑞幸咖啡 选址评估系统</h1>
            <p className="text-sm text-text-muted">Luckin Coffee Site Selection Tool</p>
          </div>
          <button
            onClick={() => setAuthed(false)}
            className="text-sm text-text-muted hover:text-text-secondary"
          >
            退出 Logout
          </button>
        </div>
      </header>

      <main className="max-w-3xl mx-auto px-4 py-8">
        {error && (
          <div className="mb-4 p-3 bg-red-50 border border-red-200 rounded-lg text-red-700 text-sm">
            {error}
          </div>
        )}
        <InputForm onAnalyze={handleAnalyze} loading={loading} loadingStage={loadingStage} />
      </main>
    </div>
  );
}

function generateWarnings(lat, lon, rentMonthly, pl, score) {
  const warnings = [];

  // Extrapolation: non-Manhattan latitude range (~40.70 - 40.80)
  if (lat < 40.700 || lat > 40.810) {
    warnings.push({
      type: 'extrapolation',
      severity: 'warning',
      text: '模型外推警告：该位置不在曼哈顿范围内，预测可能不准确',
      textEn: 'Extrapolation warning: Location outside Manhattan training data range',
    });
  }

  // Rent/revenue > 25%
  if (pl.rent_to_revenue > 25) {
    warnings.push({
      type: 'rent_ratio',
      severity: 'warning',
      text: `租金/收入比过高 (${pl.rent_to_revenue}%)，建议低于25%`,
      textEn: `Rent-to-revenue ratio ${pl.rent_to_revenue}% exceeds 25% threshold`,
    });
  }

  // Over budget (> $20K)
  if (rentMonthly > 20000) {
    warnings.push({
      type: 'over_budget',
      severity: 'danger',
      text: `月租金 $${rentMonthly.toLocaleString()} 超出 $20,000 预算上限`,
      textEn: `Monthly rent $${rentMonthly.toLocaleString()} exceeds $20,000 budget cap`,
    });
  }

  // Close cannibalization (< 0.35mi)
  if (score.nearest_distance_mi < 0.35) {
    const nearestName = score.nearest_stores[0]?.name || '';
    warnings.push({
      type: 'cannibalization',
      severity: score.nearest_distance_mi < 0.15 ? 'danger' : 'warning',
      text: `距离最近门店 ${nearestName} 仅 ${score.nearest_distance_mi.toFixed(2)} 英里，存在自相残杀风险`,
      textEn: `Only ${score.nearest_distance_mi.toFixed(2)}mi from ${nearestName} — cannibalization risk`,
    });
  }

  return warnings;
}
