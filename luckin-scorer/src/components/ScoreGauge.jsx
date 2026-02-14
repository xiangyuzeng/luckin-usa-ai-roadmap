import React from 'react';

/**
 * SVG semi-circular gauge (0-100), color gradient red→amber→green.
 */
export default function ScoreGauge({ score, label }) {
  const clampedScore = Math.max(0, Math.min(100, score));
  const angle = (clampedScore / 100) * 180;

  // Color based on score
  let color;
  if (clampedScore >= 65) color = '#059669'; // green
  else if (clampedScore >= 45) color = '#D97706'; // amber
  else color = '#DC2626'; // red

  let recommendation;
  if (clampedScore >= 70) recommendation = '强烈推荐 Strongly Recommended';
  else if (clampedScore >= 55) recommendation = '推荐 Recommended';
  else if (clampedScore >= 40) recommendation = '谨慎推荐 Recommended with Caution';
  else recommendation = '不推荐 Not Recommended';

  // SVG arc path
  const cx = 100, cy = 90, r = 75;
  const startAngle = Math.PI;
  const endAngle = Math.PI + (angle * Math.PI) / 180;

  const x1 = cx + r * Math.cos(startAngle);
  const y1 = cy + r * Math.sin(startAngle);
  const x2 = cx + r * Math.cos(endAngle);
  const y2 = cy + r * Math.sin(endAngle);
  const largeArc = angle > 180 ? 1 : 0;

  const bgX2 = cx + r * Math.cos(0);
  const bgY2 = cy + r * Math.sin(0);

  return (
    <div className="flex flex-col items-center">
      <svg viewBox="0 0 200 110" className="w-48 h-auto">
        {/* Background arc (gray) */}
        <path
          d={`M ${x1} ${y1} A ${r} ${r} 0 1 1 ${bgX2} ${bgY2}`}
          fill="none"
          stroke="#E5E7EB"
          strokeWidth="12"
          strokeLinecap="round"
        />
        {/* Score arc (colored) */}
        {clampedScore > 0 && (
          <path
            d={`M ${x1} ${y1} A ${r} ${r} 0 ${largeArc} 1 ${x2} ${y2}`}
            fill="none"
            stroke={color}
            strokeWidth="12"
            strokeLinecap="round"
          />
        )}
        {/* Score text */}
        <text x={cx} y={cy - 5} textAnchor="middle" className="metric-value" fontSize="32" fontWeight="bold" fill={color}>
          {clampedScore}
        </text>
        <text x={cx} y={cy + 14} textAnchor="middle" fontSize="10" fill="#9CA3AF">
          / 100
        </text>
      </svg>
      {label && <p className="text-xs text-text-muted mt-1">{label}</p>}
      <p className="text-sm font-medium mt-1" style={{ color }}>{recommendation}</p>
    </div>
  );
}
