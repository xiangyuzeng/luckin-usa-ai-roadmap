export const STORES = [
  { id: '1127',  name: '8th & Broadway',   mape: 34.2, wmape: 28.5, bias: 8.3,  trend: 'down' },
  { id: '1128',  name: '28th & 6th',       mape: 38.7, wmape: 31.2, bias: 12.1, trend: 'up' },
  { id: '1140',  name: '100 Maiden Ln',    mape: 41.3, wmape: 33.8, bias: 5.6,  trend: 'flat' },
  { id: '1141',  name: '54th & 8th',       mape: 36.9, wmape: 29.4, bias: 9.8,  trend: 'down' },
  { id: '20008', name: '33rd & 10th',      mape: 39.5, wmape: 32.1, bias: 7.2,  trend: 'up' },
  { id: '20010', name: '102 Fulton',       mape: 35.8, wmape: 27.9, bias: 11.4, trend: 'down' },
  { id: '20011', name: '37th & Broadway',  mape: 37.2, wmape: 30.6, bias: 6.9,  trend: 'flat' },
  { id: '20027', name: '21st & 3rd',       mape: 43.1, wmape: 35.2, bias: 14.3, trend: 'up' },
  { id: '20031', name: '15th & 3rd',       mape: 40.8, wmape: 33.5, bias: 10.7, trend: 'up' },
  { id: '20032', name: '221 Grand',        mape: 33.6, wmape: 26.8, bias: 4.2,  trend: 'down' },
];

export const STORES_SORTED = [...STORES].sort((a, b) => a.mape - b.mape);

// Per-store daily MAPE for heatmap (store x day grid)
export const STORE_DAILY_HEATMAP = [
  { store: '1127',  days: [36.1, 33.8, 31.2, 29.7, 35.4, 37.2, 32.1, 34.5, 38.9, 33.2, 30.8, 35.6, 36.8, 31.4] },
  { store: '1128',  days: [42.3, 40.1, 37.5, 35.8, 39.2, 41.6, 36.4, 38.7, 43.1, 37.9, 34.2, 39.8, 40.5, 36.1] },
  { store: '1140',  days: [44.5, 42.8, 39.1, 38.2, 41.7, 43.9, 38.5, 40.3, 45.6, 39.8, 36.5, 42.1, 43.2, 38.8] },
  { store: '1141',  days: [39.2, 37.5, 34.8, 33.1, 37.4, 39.6, 34.2, 36.8, 41.2, 35.6, 32.4, 37.9, 38.7, 34.3] },
  { store: '20008', days: [41.8, 40.2, 37.4, 36.1, 39.8, 42.1, 36.8, 39.2, 43.5, 38.1, 34.8, 40.6, 41.3, 37.5] },
  { store: '20010', days: [38.1, 36.4, 33.2, 31.8, 36.1, 38.3, 33.5, 35.7, 39.8, 34.5, 31.2, 36.8, 37.5, 33.1] },
  { store: '20011', days: [39.5, 37.8, 35.1, 33.6, 37.6, 39.8, 34.5, 37.1, 41.5, 36.2, 33.1, 38.2, 39.1, 34.6] },
  { store: '20027', days: [46.2, 44.5, 41.3, 39.8, 43.5, 45.8, 40.6, 42.8, 47.1, 41.5, 38.2, 44.3, 45.1, 40.8] },
  { store: '20031', days: [43.5, 41.8, 38.6, 37.2, 41.1, 43.4, 38.1, 40.5, 44.8, 39.5, 36.2, 41.8, 42.7, 38.3] },
  { store: '20032', days: [35.8, 34.1, 31.5, 29.8, 34.2, 36.4, 31.2, 33.5, 37.6, 32.4, 29.5, 34.8, 35.6, 31.1] },
];

export const HEATMAP_DATES = [
  'Feb 1', 'Feb 2', 'Feb 3', 'Feb 4', 'Feb 5', 'Feb 6', 'Feb 7',
  'Feb 8', 'Feb 9', 'Feb 10', 'Feb 11', 'Feb 12', 'Feb 13', 'Feb 14',
];
