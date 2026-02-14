/**
 * Socrata API: count unique subway lines within 300m of lat/lon.
 * Uses NYC MTA subway station entrances dataset.
 */
export async function getSubwayCount(lat, lon) {
  const token = process.env.MTA_APP_TOKEN;
  const tokenParam = token ? `&$$app_token=${token}` : '';
  const url = `https://data.ny.gov/resource/i9wp-a4ja.json?$where=within_circle(the_geom,${lat},${lon},300)&$limit=50${tokenParam}`;

  const resp = await fetch(url);
  const data = await resp.json();

  if (!Array.isArray(data)) return 0;

  // Count unique lines from all nearby stations
  const lines = new Set();
  for (const station of data) {
    const route = station.line || station.route_1 || '';
    route.split(/[-,\s]+/).forEach((l) => {
      const trimmed = l.trim();
      if (trimmed) lines.add(trimmed);
    });
  }

  return lines.size;
}
