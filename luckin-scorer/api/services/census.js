/**
 * Two-step Census income lookup:
 * 1. FCC API: lat/lon → FIPS state + county + tract
 * 2. Census ACS5: tract → B19013_001E median household income
 */
export async function getCensusIncome(lat, lon) {
  // Step 1: Get FIPS codes from FCC
  const fccUrl = `https://geo.fcc.gov/api/census/block/find?latitude=${lat}&longitude=${lon}&format=json`;
  const fccResp = await fetch(fccUrl);
  const fccData = await fccResp.json();

  const fips = fccData?.Block?.FIPS;
  if (!fips || fips.length < 11) return null;

  const state = fips.substring(0, 2);
  const county = fips.substring(2, 5);
  const tract = fips.substring(5, 11);

  // Step 2: Query Census ACS5
  const apiKey = process.env.CENSUS_API_KEY;
  const keyParam = apiKey ? `&key=${apiKey}` : '';
  const censusUrl = `https://api.census.gov/data/2022/acs/acs5?get=B19013_001E&for=tract:${tract}&in=state:${state}%20county:${county}${keyParam}`;

  const censusResp = await fetch(censusUrl);
  const censusData = await censusResp.json();

  if (!Array.isArray(censusData) || censusData.length < 2) return null;

  const income = parseInt(censusData[1][0], 10);
  return isNaN(income) || income < 0 ? null : income;
}
