/**
 * Haversine distance between two lat/lon points in miles.
 * Reference: site_selection_scoring_model.py:128-135
 */
export function haversine(lat1, lon1, lat2, lon2) {
  const R = 3958.8; // Earth radius in miles
  const dLat = ((lat2 - lat1) * Math.PI) / 180;
  const dLon = ((lon2 - lon1) * Math.PI) / 180;
  const a =
    Math.sin(dLat / 2) ** 2 +
    Math.cos((lat1 * Math.PI) / 180) *
      Math.cos((lat2 * Math.PI) / 180) *
      Math.sin(dLon / 2) ** 2;
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  return R * c;
}

/**
 * Find nearest stores sorted by distance.
 * Returns [{name, distance_mi, cups}, ...]
 */
export function findNearestStores(lat, lon, stores) {
  return stores
    .map((s) => ({
      name: s.name,
      distance_mi: haversine(lat, lon, s.lat, s.lon),
      cups: s.avg_daily_cups,
      area_type: s.area_type,
    }))
    .sort((a, b) => a.distance_mi - b.distance_mi);
}
