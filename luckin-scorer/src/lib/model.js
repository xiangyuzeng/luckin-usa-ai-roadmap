import { MODEL } from './constants.js';

/**
 * Predict weekly cups using the trained Lasso model.
 *
 * CRITICAL: Must follow exact sequence from score_new_location.py:104-133
 *   1. Build raw vector in feature_cols order (10 features)
 *   2. Z-score standardize: (X[i] - mean[i]) / scale[i]
 *   3. Append interaction: X_scaled[foot_traffic] * (1 - competitor_density_RAW / 20)
 *      NOTE: scaled foot_traffic × raw competitor — this asymmetry is intentional
 *   4. Dot product of 11 coefficients + intercept 2366.9375
 *   5. Floor at 0
 *   6. 90% CI: pred ± 1.645 × 95.77
 */
export function predictWeeklyCups(features) {
  const featureCols = MODEL.feature_cols;
  const scalerMean = MODEL.scaler_mean;
  const scalerScale = MODEL.scaler_scale;
  const coef = MODEL.coef;
  const intercept = MODEL.intercept;
  const rmse = MODEL.metrics.rmse;

  // Step 1: Build raw feature vector in exact order
  const X_raw = featureCols.map((f) => features[f]);

  // Step 2: Z-score standardize
  const X_scaled = X_raw.map((val, i) => (val - scalerMean[i]) / scalerScale[i]);

  // Step 3: Append interaction term
  // foot_traffic_score is index 0, competitor_density is index 4
  const ftIdx = featureCols.indexOf('foot_traffic_score');
  const cdIdx = featureCols.indexOf('competitor_density');
  const interaction = X_scaled[ftIdx] * (1 - X_raw[cdIdx] / 20);
  X_scaled.push(interaction);

  // Step 4: Dot product + intercept
  let pred = intercept;
  for (let i = 0; i < coef.length; i++) {
    pred += X_scaled[i] * coef[i];
  }

  // Step 5: Floor at 0
  pred = Math.max(pred, 0);

  // Step 6: 90% confidence interval
  const lower90 = Math.max(pred - 1.645 * rmse, 0);
  const upper90 = pred + 1.645 * rmse;

  return {
    predicted_weekly_cups: Math.round(pred),
    cups_lower_90: Math.round(lower90),
    cups_upper_90: Math.round(upper90),
    predicted_daily_cups: Math.round(pred / 7),
  };
}
