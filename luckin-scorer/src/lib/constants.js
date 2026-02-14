import MODEL_DATA from '../../data/model_artifacts.json';
import STORES_DATA from '../../data/active_stores.json';
import WEIGHTS_DATA from '../../data/scoring_weights.json';
import ECON_DATA from '../../data/unit_economics.json';
import PIPELINE_DATA from '../../data/pipeline_locations.json';

export const MODEL = MODEL_DATA;
export const STORES = STORES_DATA;
export const WEIGHTS = WEIGHTS_DATA;
export const ECON = ECON_DATA;
export const PIPELINE = PIPELINE_DATA;

export const PASSWORD = 'luckin2026';

export const AREA_TYPE_OPTIONS = [
  { value: 'university_tourist', label: '大学/旅游区 University Tourist' },
  { value: 'commercial_transit_hub', label: '商业交通枢纽 Commercial Transit Hub' },
  { value: 'tourist_ethnic_enclave', label: '旅游/特色街区 Tourist Ethnic Enclave' },
  { value: 'financial_office', label: '金融/办公区 Financial Office' },
  { value: 'mixed_commercial', label: '混合商业 Mixed Commercial' },
  { value: 'theater_tourist', label: '剧院/旅游 Theater Tourist' },
  { value: 'tech_office', label: '科技/办公 Tech Office' },
  { value: 'residential_mixed', label: '住宅混合 Residential Mixed' },
  { value: 'residential', label: '住宅区 Residential' },
  { value: 'emerging_commercial', label: '新兴商业 Emerging Commercial' },
  { value: 'government_office', label: '政府/办公 Government Office' },
  { value: 'premium_office', label: '高端办公 Premium Office' },
  { value: 'major_transit_hub', label: '大型交通枢纽 Major Transit Hub' },
];

// Numeric 0-100 mapping for the Lasso model's area_type_score feature
export const AREA_TYPE_SCORE_MAP = {
  university_tourist: 95,
  major_transit_hub: 90,
  commercial_transit_hub: 80,
  commercial_tourist: 75,
  tourist_ethnic_enclave: 70,
  theater_tourist: 65,
  financial_office: 55,
  tech_office: 50,
  mixed_commercial: 45,
  government_office: 40,
  emerging_commercial: 35,
  residential_mixed: 25,
  residential_commercial: 20,
  mixed_commercial_residential: 20,
  university_residential: 30,
  government_residential: 25,
  premium_office: 60,
  office_transit: 55,
  office_commercial: 50,
  residential: 10,
};

// Base foot traffic estimates by area type (0-100 scale)
export const FOOT_TRAFFIC_BASE_MAP = {
  university_tourist: 85,
  major_transit_hub: 95,
  commercial_transit_hub: 75,
  commercial_tourist: 70,
  tourist_ethnic_enclave: 65,
  theater_tourist: 60,
  financial_office: 55,
  tech_office: 45,
  mixed_commercial: 50,
  government_office: 40,
  emerging_commercial: 35,
  residential_mixed: 30,
  residential_commercial: 30,
  mixed_commercial_residential: 35,
  university_residential: 40,
  government_residential: 30,
  premium_office: 55,
  office_transit: 60,
  office_commercial: 50,
  residential: 20,
};
