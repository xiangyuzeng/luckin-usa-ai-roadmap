import { WEIGHTS, AREA_TYPE_SCORE_MAP, FOOT_TRAFFIC_BASE_MAP } from './constants.js';
import { findNearestStores, haversine } from './haversine.js';

/**
 * Compute the 5-factor location score.
 * Returns { total, breakdown: {area_type, subway, weekend, cannibalization, rent}, nearest_stores, nearest_distance_mi }
 */
export function computeScore(params, stores) {
  const { area_type, subway_count, weekday_pct, rent_monthly, lat, lon } = params;

  // 1. Area type score (max 35)
  const areaTypeTiers = WEIGHTS.area_type.tiers;
  const areaScore = areaTypeTiers[area_type] ?? 10;

  // 2. Subway access (max 20)
  let subwayScore = 0;
  for (const tier of WEIGHTS.subway_access.tiers) {
    if (subway_count >= tier.min && subway_count <= tier.max) {
      subwayScore = tier.score;
      break;
    }
  }

  // 3. Weekend resilience (max 15)
  let weekendScore = 0;
  for (const tier of WEIGHTS.weekend_resilience.tiers) {
    if (weekday_pct <= tier.max_weekday_pct) {
      weekendScore = tier.score;
      break;
    }
  }

  // 4. Cannibalization (max -15, 0 if far away)
  const nearestStores = findNearestStores(lat, lon, stores);
  const nearestDist = nearestStores.length > 0 ? nearestStores[0].distance_mi : 999;
  let cannibScore = 0;
  for (const tier of WEIGHTS.cannibalization.tiers) {
    if (nearestDist <= tier.max_distance_mi) {
      cannibScore = tier.score;
      break;
    }
  }

  // 5. Rent value (max 15)
  let rentScore = 0;
  for (const tier of WEIGHTS.rent_value.tiers) {
    if (rent_monthly <= tier.max_rent) {
      rentScore = tier.score;
      break;
    }
  }

  const total = areaScore + subwayScore + weekendScore + cannibScore + rentScore;

  return {
    total,
    breakdown: {
      area_type: areaScore,
      subway: subwayScore,
      weekend: weekendScore,
      cannibalization: cannibScore,
      rent: rentScore,
    },
    nearest_stores: nearestStores.slice(0, 5),
    nearest_distance_mi: nearestDist,
  };
}

/**
 * Estimate foot traffic score (0-100) for the Lasso model input.
 * Combines area_type base + subway bonus + walk_score adjustment + competitor effect.
 */
export function estimateFootTraffic(areaType, subwayCount, walkScore, competitors) {
  const base = FOOT_TRAFFIC_BASE_MAP[areaType] ?? 40;

  // Subway bonus: each line adds, capped at +10, scaled by 1.5
  const subwayBonus = Math.min(subwayCount * 1.5, 10);

  // Walk score adjustment: centered around 95, scaled by 0.3
  const wsAdj = walkScore != null ? (walkScore - 95) * 0.3 : 0;

  // Competitor bonus: moderate competition indicates good location
  const compBonus = Math.min(competitors * 0.5, 3);

  const score = Math.max(0, Math.min(100, base + subwayBonus + wsAdj + compBonus));
  return Math.round(score * 10) / 10;
}

/**
 * Compute cannibalization score for the Lasso model (0-1).
 * 0 = on top of existing store, 1 = far away.
 */
export function computeCannibScore(lat, lon, stores) {
  if (stores.length === 0) return 1.0;
  const distances = stores.map((s) => haversine(lat, lon, s.lat, s.lon));
  const minDist = Math.min(...distances);
  // Map: 0mi → 0, 1mi → ~0.8, 2mi+ → ~1.0
  return Math.min(minDist / 1.2, 1.0);
}

/**
 * Get the numeric area_type_score for the Lasso model (0-100 range).
 */
export function computeAreaTypeScore(areaType) {
  return AREA_TYPE_SCORE_MAP[areaType] ?? 40;
}
