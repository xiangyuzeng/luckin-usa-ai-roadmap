import express from 'express';
import cors from 'cors';
import dotenv from 'dotenv';
import { geocode } from './services/geocode.js';
import { getCensusIncome } from './services/census.js';
import { getSubwayCount } from './services/mta.js';
import { getWalkScore } from './services/walkscore.js';
import { getCompetitorDensity } from './services/places.js';

dotenv.config();

const app = express();
app.use(cors());
app.use(express.json());

/**
 * POST /api/enrich
 * Accepts { address }, returns enriched location data.
 * Geocode is required; other enrichments fail gracefully.
 */
app.post('/api/enrich', async (req, res) => {
  const { address } = req.body;
  if (!address) {
    return res.status(400).json({ error: '地址不能为空 Address is required' });
  }

  try {
    // Step 1: Geocode (required)
    const geo = await geocode(address);
    if (!geo) {
      return res.status(400).json({ error: '无法解析地址 Could not geocode address' });
    }

    const { lat, lon, formatted_address } = geo;

    // Step 2: Parallel enrichment (each can fail independently)
    const [income, subway, walkScore, competitors] = await Promise.allSettled([
      getCensusIncome(lat, lon),
      getSubwayCount(lat, lon),
      getWalkScore(address, lat, lon),
      getCompetitorDensity(lat, lon),
    ]);

    res.json({
      lat,
      lon,
      formatted_address,
      median_income: income.status === 'fulfilled' ? income.value : null,
      subway_count: subway.status === 'fulfilled' ? subway.value : null,
      walk_score: walkScore.status === 'fulfilled' ? walkScore.value : null,
      competitor_density: competitors.status === 'fulfilled' ? competitors.value : null,
    });
  } catch (err) {
    console.error('Enrich error:', err.message);
    res.status(500).json({ error: '服务器错误 Server error' });
  }
});

const PORT = process.env.PORT || 3001;
app.listen(PORT, () => {
  console.log(`API server running on port ${PORT}`);
});
