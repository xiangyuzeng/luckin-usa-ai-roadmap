/**
 * Google Geocoding API: address → {lat, lon, formatted_address}
 */
export async function geocode(address) {
  const key = process.env.GOOGLE_MAPS_API_KEY;
  if (!key) {
    console.warn('GOOGLE_MAPS_API_KEY not set, geocode unavailable');
    return null;
  }

  const url = `https://maps.googleapis.com/maps/api/geocode/json?address=${encodeURIComponent(address)}&key=${key}`;
  const resp = await fetch(url);
  const data = await resp.json();

  if (data.status !== 'OK' || !data.results?.length) {
    return null;
  }

  const result = data.results[0];
  return {
    lat: result.geometry.location.lat,
    lon: result.geometry.location.lng,
    formatted_address: result.formatted_address,
  };
}
