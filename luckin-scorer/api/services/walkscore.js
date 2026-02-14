/**
 * Walk Score API: address + lat/lon → walk score (0-100)
 */
export async function getWalkScore(address, lat, lon) {
  const key = process.env.WALKSCORE_API_KEY;
  if (!key) {
    console.warn('WALKSCORE_API_KEY not set');
    return null;
  }

  const url = `https://api.walkscore.com/score?format=json&address=${encodeURIComponent(address)}&lat=${lat}&lon=${lon}&wsapikey=${key}`;
  const resp = await fetch(url);
  const data = await resp.json();

  if (data.status !== 1) return null;
  return data.walkscore ?? null;
}
