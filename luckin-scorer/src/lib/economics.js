import { ECON } from './constants.js';

/**
 * Calculate full P&L from weekly cup prediction.
 *
 * Revenue = weekly_cups × 4.33 × $5.50
 * COGS = monthly_cups × $1.50
 * Labor = $15,000/month
 * Other = $3,000/month (supplies)
 * ROI = (profit / total_cost) × 100
 * Breakeven = fixed_costs / (margin × 30)
 */
export function calculatePL(weeklyPred, rentMonthly, sqft) {
  const weeksPerMonth = ECON.weeks_per_month;
  const cupPrice = ECON.cup_price;
  const cogsPerCup = ECON.cogs_per_cup;
  const marginPerCup = ECON.margin_per_cup;
  const laborMonthly = ECON.labor_monthly;
  const suppliesMonthly = ECON.supplies_monthly;

  const monthlyCups = weeklyPred * weeksPerMonth;
  const dailyCups = weeklyPred / 7;

  const revenue = monthlyCups * cupPrice;
  const cogs = monthlyCups * cogsPerCup;
  const totalCost = rentMonthly + laborMonthly + suppliesMonthly + cogs;
  const profit = revenue - totalCost;
  const roi = totalCost > 0 ? (profit / totalCost) * 100 : 0;

  const fixedCosts = rentMonthly + laborMonthly + suppliesMonthly;
  const breakevenCupsPerDay = marginPerCup > 0 ? fixedCosts / (marginPerCup * 30) : 0;

  const rentToRevenue = revenue > 0 ? (rentMonthly / revenue) * 100 : 0;
  const rentPerSqft = sqft > 0 ? rentMonthly / sqft : 0;

  let riskFlag;
  if (roi > 15) riskFlag = 'Strong';
  else if (roi > 0) riskFlag = 'Viable';
  else riskFlag = 'Risky';

  return {
    monthly_cups: Math.round(monthlyCups),
    daily_cups: Math.round(dailyCups),
    revenue: Math.round(revenue),
    cogs: Math.round(cogs),
    labor: laborMonthly,
    rent: rentMonthly,
    supplies: suppliesMonthly,
    total_cost: Math.round(totalCost),
    profit: Math.round(profit),
    roi: Math.round(roi * 10) / 10,
    breakeven_cups_per_day: Math.round(breakevenCupsPerDay),
    rent_to_revenue: Math.round(rentToRevenue * 10) / 10,
    rent_per_sqft: Math.round(rentPerSqft * 10) / 10,
    risk_flag: riskFlag,
  };
}
