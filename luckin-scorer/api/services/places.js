/**
 * Google Places Nearby Search: count cafes/coffee shops within 402m (~0.25mi).
 */
export async function getCompetitorDensity(lat, lon) {
  const key = process.env.GOOGLE_MAPS_API_KEY;
  if (!key) {
    console.warn('GOOGLE_MAPS_API_KEY not set, places unavailable');
    return null;
  }

  const url = `https://maps.googleapis.com/maps/api/place/nearbysearch/json?location=${lat},${lon}&radius=402&type=cafe&keyword=coffee&key=${key}`;
  const resp = await fetch(url);
  const data = await resp.json();

  if (data.status !== 'OK' && data.status !== 'ZERO_RESULTS') return null;

  return data.results?.length ?? 0;
}
