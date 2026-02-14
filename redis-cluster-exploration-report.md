# Redis Cluster Exploration Report
**Date:** 2026-02-13
**Environment:** Amazon ElastiCache (Redis 6.0.5, standalone mode)
**Scope:** 10 key Redis clusters in the luckyus platform

---

## Executive Summary

| # | Cluster | Keys | Memory Used | Max Memory | Utilization | Eviction Policy |
|---|---------|------|-------------|------------|-------------|-----------------|
| 1 | luckyus-isales-order | 208 | 4.31 MB | 384 MB | 1.1% | volatile-lfu |
| 2 | luckyus-isales-market | 5,635,070 | **1.28 GB** | **4.79 GB** | **26.7%** | volatile-lfu |
| 3 | luckyus-isales-commodity | 848 | 21.22 MB | 384 MB | 5.5% | volatile-lfu |
| 4 | luckyus-isales-member | 29 | 2.94 MB | 384 MB | 0.8% | volatile-lfu |
| 5 | luckyus-isales-session | 149,834 | 99.73 MB | 384 MB | 26.2% | volatile-lfu |
| 6 | luckyus-shop | 677 | 6.44 MB | 384 MB | 1.7% | volatile-lfu |
| 7 | luckyus-shopsale | 13 | 3.68 MB | 384 MB | 1.0% | volatile-lfu |
| 8 | luckyus-production | 59 | 2.92 MB | 384 MB | 0.8% | volatile-lfu |
| 9 | luckyus-scm-shopstock | 7,274 | 5.59 MB | 384 MB | 1.5% | volatile-lfu |
| 10 | luckyus-iotplatform | 120 | 3.24 MB | 384 MB | 0.8% | volatile-lfu |

**Key Findings:**
- **luckyus-isales-market** is by far the largest cluster at 1.28 GB with 5.6M keys (dedicated 4.79 GB max)
- **luckyus-isales-session** is the second busiest with 150K active sessions
- Most clusters are extremely underutilized (under 5% memory usage)
- All clusters use `volatile-lfu` eviction policy (evict least-frequently-used keys with TTL)
- **Zero evictions** across all clusters -- no memory pressure detected
- All clusters run on Amazon ElastiCache Redis 6.0.5

---

## Detailed Cluster Analysis

---

### 1. luckyus-isales-order (Order Caching)

**Memory:** 4.31 MB used / 384 MB max (1.1%)
**Keys:** 208 (all with TTL, avg TTL ~11,065 seconds = ~3 hours)
**Hit Rate:** 64.4% (13.5M hits / 7.4M misses)
**OPS:** ~3 ops/sec
**Uptime:** 339 days

**Key Patterns Discovered:**
| Pattern | Type | TTL | Size | Description |
|---------|------|-----|------|-------------|
| `orderservice:orderDetail:{orderId}` | string | ~96s | ~8.9 KB | Full order detail JSON, short-lived cache |
| `orderservice:orderList:{userId}:{page}` | string | short | ~33 B | Paginated order list references |
| `payment:orderStatus:{orderId}` | string | ~80s | small | Payment status for orders |
| `orderTaskNo:LKUS:{shopId}:{number}` | string | ~40 hours | small | Order task number sequences per shop |
| `orderTaskNoSeg:LKUS:{shopId}:{number}` | string | varies | small | Order task number segments |
| `OD@LKUS@OCS_{userId}` | string | varies | small | Order customer state |
| `isalesorderservice:LKUS:getShopTimeZone{shopId}` | string | varies | small | Timezone cache per shop |
| `meta@LKUS@paymentMethod` | string | varies | small | Payment method metadata |
| `LKUS_America/New_York` | string | varies | small | Timezone reference data |

**Analysis:** Low-volume, short-TTL cache for active orders. Order details are cached for only ~1-2 minutes, suggesting this serves as a hot-path read-through cache during order processing. The 64% hit rate indicates room for improvement -- possibly order details expire before being read again.

---

### 2. luckyus-isales-market (Marketing Data) -- LARGEST CLUSTER

**Memory:** 1.28 GB used / 4.79 GB max (26.7%)
**Keys:** 5,635,070 (2,943,177 with TTL = 52.2%, 2,691,893 persistent)
**Hit Rate:** 86.9% (4.2M hits / 633K misses)
**OPS:** ~54 ops/sec (highest activity)
**Uptime:** ~16 hours (recently restarted/failed over)
**Avg TTL:** ~12,103,050 seconds = ~140 days for keys with expiry

**Key Patterns Discovered:**
| Pattern | Type | TTL | Description |
|---------|------|-----|-------------|
| `CONTACT_{userId}_{channel}_{status}` | string | NO TTL | Contact/touchpoint tracking per user per channel |
| `CONTACT_day_{userId}_{date}_{channel}` | string | NO TTL | Daily contact frequency counters |
| `CONTACT_week_{userId}_{date}_{channel}` | string | NO TTL | Weekly contact frequency counters |
| `CONTACT_month_{userId}_{month}_{channel}` | string | NO TTL | Monthly contact frequency counters |
| `contact:activity:freq:ctrl:total:{campaignId}:{userId}` | string | with TTL | Campaign frequency control (total contacts) |
| `contact:activity:freq:ctrl:month:{campaignId}:{userId}:{month}` | string | with TTL | Monthly frequency caps per campaign |
| `contact:last:activity:{userId}:{channel}` | string | NO TTL | Last activity timestamp per user |
| `contact:user:contacted:activity:one:day:{userId}:{date}` | string | with TTL | Daily contact dedup flags |
| `contact:userGroupLabel:set:{userId}` | set(~27 items) | NO TTL | User group label memberships (set type) |
| `realtime:ug:event:{type}:{userId}:{eventId}` | string | with TTL | Real-time user group events |
| `isales:realtime:usergroup:koala:message:{userId}_{groupId}_{type}_{msgId}` | string | with TTL | Koala messaging real-time events |
| `MARKETING:COUPON:UNREAD:{userId}:coupon` | set | varies | Unread coupon notifications per user |
| `user:activity:Category:FreqCtrl:{userId}:{category}:{limit}` | string | with TTL | Per-category activity frequency control |

**CRITICAL OBSERVATIONS:**
- **2.69M keys have NO TTL** -- these grow unboundedly over time. This is the primary reason this cluster needs 4.79 GB max memory.
- The `CONTACT_day/week/month` counters without expiry will accumulate historical data forever.
- This cluster was recently restarted (16 hours uptime) -- possibly related to the previously reported memory alert.
- The marketing data is a mix of real-time event processing and persistent user contact history.
- The contact frequency control system (channel 0=push, 1=SMS, 2=email, 5=social) tracks every customer touchpoint.

---

### 3. luckyus-isales-commodity (Product/Commodity Data)

**Memory:** 21.22 MB used / 384 MB max (5.5%)
**Keys:** 848 (all with TTL, avg TTL ~89 seconds = ~1.5 minutes)
**Hit Rate:** 81.6% (302.6M hits / 68.2M misses over lifetime)
**OPS:** ~0 ops/sec (bursty)
**Fragmentation:** 1.94

**Key Patterns Discovered:**
| Pattern | Type | TTL | Size | Description |
|---------|------|-----|------|-------------|
| `isalescommodityservice:LKUS:operateShopSalesSpuDeptSpu{shopId}:{productCode}` | string | ~34s | small | Product availability per shop per SPU (department mapping) |
| `isalescommodityservice:LKUS:en-US:scmCommodityDetails{productCode}` | string | short | ~615 B | Product detail JSON (localized en-US) |
| `isalescommodityservice:LKUS:en-US:scmCommodityNotePlan{productCode}` | string | short | small | Product note/plan data |
| `isalescommodityservice:LKUS:en-US:scmCommodityNutritionV2{productCode}` | string | short | small | Nutritional information V2 |
| `isalescommodityservice:LKUS:en-US:scmUSNutritionInfo{productCode}` | string | short | small | US-specific nutrition info |
| `isalescommodityservice:LKUS:en-US:scmOptionNutritionV2{productCode}` | string | short | small | Option/variant nutrition data |
| `isalescommodityservice:LKUS:en-US:scmOutCommodityRmkOption{productCode}` | string | short | small | Remark/customization options |
| `isalescommodityservice:LKUS:en-US:scmComboDetails{comboCode}` | string | short | small | Combo meal details |
| `isalescommodityservice:LKUS:en-US:scmAllCategorydefault` | string | short | small | All category listing |
| `commodity@LKUS@allergens_{productCode}` | string | short | small | Allergen information |
| `commodity@LKUS@materials_{productCode}` | string | short | small | Materials/ingredients data |
| `commodity@LKUS@skuNutriInfo_{productCode}` | string | short | small | SKU nutrition info |
| `commodity@LKUS@spuNutriInfo_{productCode}` | string | short | small | SPU nutrition info |

**Analysis:** Very short-lived cache (~1.5 min avg TTL) for product catalog data. Despite having only 848 keys, it has processed 370M total lookups over its lifetime -- indicating extremely high read throughput for the menu/product catalog. Product codes follow `PR000XXX` for products and `PF000XXX` for combo meals. Shop IDs visible: 1127, 1128, 1140, 1141, 20008, 20010, 20011, 20031, 20032.

---

### 4. luckyus-isales-member (Member Data)

**Memory:** 2.94 MB used / 384 MB max (0.8%)
**Keys:** 29 (all with TTL, avg TTL ~120 seconds = 2 minutes)
**Hit Rate:** 80.8% (2.9M hits / 692K misses)
**OPS:** ~4 ops/sec

**Key Patterns Discovered:**
| Pattern | Type | TTL | Description |
|---------|------|-----|-------------|
| `M@LKUS@_{userId}` | string | ~120s | Member/customer profile cache by user ID |

**Analysis:** Extremely lightweight cache, only holding ~29 active member profile lookups at any time. Short 2-minute TTL means this is a hot-path cache that refreshes quickly from the database. Despite the small key count, it has processed 3.6M total commands, indicating high throughput on a small set of frequently accessed member profiles.

---

### 5. luckyus-isales-session (Session Management)

**Memory:** 99.73 MB used / 384 MB max (26.2%)
**Keys:** 149,834 (all with TTL, avg TTL ~3,093,618 seconds = ~35.8 days)
**Hit Rate:** 99.6% (78.4M hits / 294K misses) -- EXCELLENT
**OPS:** ~11 ops/sec
**Uptime:** long-running

**Key Patterns Discovered:**
| Pattern | Type | TTL | Size | Description |
|---------|------|-----|------|-------------|
| `{uuid}{timestamp}` | string | ~89 days (max observed: 7.7M seconds) | ~487 B | Session token data (UUID + epoch ms composite key) |

**Analysis:** Session store with ~150K active sessions. Keys are composite of UUID + unix timestamp in milliseconds, making them globally unique. Sessions are relatively large at ~487 bytes each. With a ~36-day average TTL and some sessions lasting up to 89 days, this indicates very long-lived sessions (likely mobile app sessions with "remember me" functionality). The 99.6% hit rate is exceptional -- virtually every session lookup succeeds.

---

### 6. luckyus-shop (Shop Data)

**Memory:** 6.44 MB used / 384 MB max (1.7%)
**Keys:** 677 (669 with TTL, 8 persistent, avg TTL ~434,166 seconds = ~5 days)
**Hit Rate:** 93.7% (22.7M hits / 1.5M misses)
**OPS:** ~0 ops/sec (bursty)

**Key Patterns Discovered:**
| Pattern | Type | TTL | Size | Description |
|---------|------|-----|------|-------------|
| `shopDetails:{shopId}` | string | ~4.4 days | ~3 KB | Full shop detail JSON |
| `mdmDict:LKUS:{locale}:{dictType}` | string | varies | varies | MDM (Master Data Management) dictionary lookups |
| `mdmDict:mdmDict:LKUS:{locale}:{dictType}_#TS#` | string | varies | small | MDM dict cache timestamps |
| `userSelectShop.{hash}` | string | varies | small | User's selected/active shop |
| `IQA2_shop_geo` / `IQA2_shop_geo_{code}` | string | varies | small | QA environment shop geo data |
| `dyDict.order_remark_item` | string | varies | small | Dynamic dictionary for order remarks |
| `isTimeJob:{jobName}:{date}` | string | varies | small | Scheduled job execution flags |

**Analysis:** Shop master data cache. Contains all shop details (~500+ shops with IDs ranging from 410 to 20035), MDM dictionaries (country, province, city, shop level, trademark, cooperation pattern, cargo categories), and user shop selection state. The 5-day average TTL for shop details is appropriate for relatively static master data. The shop IDs include both numeric (legacy) and 20000+ series (newer US locations).

---

### 7. luckyus-shopsale (Shop Sales)

**Memory:** 3.68 MB used / 384 MB max (1.0%)
**Keys:** 13 (all with TTL, avg TTL ~131,651 seconds = ~1.5 days)
**Hit Rate:** 2.9% (1.4M hits / 47.3M misses) -- VERY LOW
**OPS:** ~0 ops/sec

**Key Patterns Discovered:**
| Pattern | Type | TTL | Size | Description |
|---------|------|-----|------|-------------|
| `iopshopsaleservice:LKUS:shop_sale_spu:{shopId}` | string | varies | small | Shop sales SPU data (per shop) |
| `iopshopsaleservice:LKUS:shop_sale_item:{shopId}_{item}` | string | varies | small | Shop sales item data |
| `iopshopsaleservice:no_sale_special_spu_{shopId}` | string | varies | small | Non-sale special SPU flags |
| `iopshopsaleservice:LKUS:en-US:comboDetail.{comboCode}` | string | varies | ~958 B | Combo meal detail (localized) |
| `iopshopsaleservice:mdmDict:LKUS:en-US:MDM_CARGO` | string | varies | small | Cargo MDM dictionary |

**CRITICAL OBSERVATION:** The 2.9% hit rate is alarming. With 47.3M misses vs 1.4M hits, the vast majority of lookups fail to find data in cache. This suggests either: (a) cache keys expire before being re-accessed, (b) application queries patterns that don't match cached keys, or (c) the cache population strategy is ineffective. This cluster warrants investigation for optimization.

---

### 8. luckyus-production (Production Data)

**Memory:** 2.92 MB used / 384 MB max (0.8%)
**Keys:** 59 (all with TTL, avg TTL ~16,488 seconds = ~4.6 hours)
**Hit Rate:** 68.0% (16.8M hits / 7.9M misses)
**OPS:** ~0 ops/sec (bursty)

**Key Patterns Discovered:**
| Pattern | Type | TTL | Size | Description |
|---------|------|-----|------|-------------|
| `iopproduction:getStatus2EstimatedWaitTime:{shopId}` | string | varies | ~196 B | Estimated wait time per shop (production queue) |
| `iopproduction:LKUS:en-US:langSpuCache:{productCode}` | string | varies | small | Localized SPU name cache |
| `iopproduction:LKUS:en-US:langRmkCacheV3:{productCode}` | string | varies | small | Localized remark/option text V3 |
| `iopproduction:ShopInvoice{invoiceCode}` | string | varies | small | Shop invoice configuration |
| `iopproduction:LKUS:iot_prod_codes1` | string | varies | small | IoT production codes mapping |
| `iopproduction:LKUS:printConfig1` | string | varies | small | Print configuration |
| `stock_adjust:idempotent:MASC{date}{sequence}` | string | varies | small | Stock adjustment idempotency keys (today's date: 2602130000XXX) |

**Analysis:** Production/kitchen management cache. Tracks estimated wait times per shop (key for customer-facing apps), localized product names for receipts/displays, invoice settings, and stock adjustment idempotency keys. The stock adjustment keys use format `MASC{YYMMDD}{sequence}` and are date-specific, ensuring daily cleanup.

---

### 9. luckyus-scm-shopstock (Shop Stock)

**Memory:** 5.59 MB used / 384 MB max (1.5%)
**Keys:** 7,274 (all with TTL, avg TTL ~52,506 seconds = ~14.6 hours)
**Hit Rate:** 65.2% (4.6M hits / 2.5M misses)
**OPS:** ~13 ops/sec

**Key Patterns Discovered:**
| Pattern | Type | TTL | Size | Description |
|---------|------|-----|------|-------------|
| `{orderId}-{status1}-{status2}-{flag}` | string | ~24 hours | small | Order stock status tracking (e.g., `118850444603801600-10-10--1`) |
| `iscmshopstock:LOCAL_CACHE_DOMAIN_ORDER_SKU_FORMULA:_{orderId}_{skuCode}-{formula}:LKUS` | string | varies | small | Order SKU formula calculations (ingredient decomposition) |
| `iscmshopstock:LOCAL_CACHE_DOMAIN_GOODS:_{goodsCode}:LKUS` | string | varies | ~646 B | Goods/ingredient master data |
| `iscmshopstock:LOCAL_CACHE_DOMAIN_SPU_FORMULA:_{number}_{productCode}` | string | varies | small | SPU formula definitions |
| `iscmshopstock:LOCAL_CACHE_DOMAIN_PLAN_ID:_{shopId}` | string | varies | small | Shop stock plan IDs |
| `iscmshopstock:CACHE_DOMAIN_PREMADE_MATERIAL:_{materialCode}:LKUS` | string | varies | small | Pre-made material data |

**Analysis:** Inventory/stock management cache. The most interesting pattern is the order stock status keys (`orderId-status1-status2-flag`) which track per-order inventory deductions. Status codes observed: 10 (pending), 20 (confirmed), 40 (in-progress), 90 (completed), with -1 flag and occasional "20" suffix and "R" flags indicating returns. The SKU formula keys decompose products into ingredients for inventory management (e.g., `PR000075-9|6_28_42|3_62_65_73_91` maps a product to its ingredient IDs with quantities).

---

### 10. luckyus-iotplatform (IoT Platform)

**Memory:** 3.24 MB used / 384 MB max (0.8%)
**Keys:** 120 (119 with TTL, 1 persistent, avg TTL ~14 seconds)
**Hit Rate:** 0.7% (6,689 hits / 946,837 misses) -- EXTREMELY LOW
**OPS:** ~4 ops/sec
**Expired Keys:** 46,068,363 (extremely high churn)

**Key Patterns Discovered:**
| Pattern | Type | TTL | Size | Description |
|---------|------|-----|------|-------------|
| `duplicate_message_{deviceType}_{deviceMAC}_{sequence}` | string | ~14s | small | IoT message deduplication (very short TTL) |
| `device_communication` | hash (401 fields) | NO TTL | binary data | Device communication state registry |

**Device Types Observed:**
- `gateway` -- IoT gateways (MAC: c83255dXXXXX, 1a664469bXXX)
- `unfreeze_icebox` -- Freezer/ice box units (highest sequence numbers: 500K+)
- `milk_machine` -- Milk dispensers (MAC: e88da69dXXXX)
- `syrup_machine` -- Syrup dispensers (MAC: ceb81cXXXX, 468b3aXXXX, etc.)
- `juice_machine` -- Juice dispensers
- `Venus_Donlim_1` -- Venus/Donlim branded equipment

**CRITICAL OBSERVATIONS:**
- **46 million expired keys** with only 120 live keys at any time -- this is a massive churn deduplication cache.
- The ~14-second average TTL is perfect for IoT message deduplication (preventing duplicate MQTT/IoT messages).
- The 0.7% hit rate is expected and correct -- the purpose is to SET a key and check if it EXISTS, not GET it. A "miss" means the message is new (not a duplicate).
- The `device_communication` hash with 401 fields stores binary-encoded state for all connected devices.
- Sequence numbers indicate device activity levels: iceboxes are highest volume (~500K+ messages each), followed by syrup machines (~100K), gateways (~80K), milk machines (~30K).

---

## Cross-Cluster Summary

### Memory Distribution
```
luckyus-isales-market:  ████████████████████████████████████████  1.28 GB (89.6%)
luckyus-isales-session: ███                                       99.7 MB (6.9%)
luckyus-isales-commodity: █                                       21.2 MB (1.5%)
luckyus-shop:                                                      6.4 MB (0.4%)
luckyus-scm-shopstock:                                             5.6 MB (0.4%)
All others combined:                                              17.9 MB (1.2%)
                                                          Total: ~1.43 GB
```

### Cache Hit Rates (ranked)
| Cluster | Hit Rate | Assessment |
|---------|----------|------------|
| luckyus-isales-session | 99.6% | Excellent |
| luckyus-shop | 93.7% | Excellent |
| luckyus-isales-market | 86.9% | Good |
| luckyus-isales-commodity | 81.6% | Good |
| luckyus-isales-member | 80.8% | Good |
| luckyus-production | 68.0% | Fair |
| luckyus-scm-shopstock | 65.2% | Fair |
| luckyus-isales-order | 64.4% | Fair |
| luckyus-shopsale | **2.9%** | **Critical** |
| luckyus-iotplatform | 0.7% | Expected (dedup pattern) |

### TTL Strategies
| Cluster | Avg TTL | Strategy |
|---------|---------|----------|
| luckyus-iotplatform | 14 seconds | Ultra-short (dedup) |
| luckyus-isales-commodity | 89 seconds | Very short (hot cache) |
| luckyus-isales-member | 120 seconds | Very short (hot cache) |
| luckyus-isales-order | 3 hours | Short (active orders) |
| luckyus-production | 4.6 hours | Medium (production state) |
| luckyus-scm-shopstock | 14.6 hours | Medium (daily stock) |
| luckyus-shopsale | 1.5 days | Long (sales config) |
| luckyus-isales-session | 35.8 days | Very long (sessions) |
| luckyus-shop | 5 days | Long (master data) |
| luckyus-isales-market | 140 days / persistent | Mixed (some never expire) |

---

## Key Findings and Recommendations

### 1. luckyus-isales-market Memory Growth Risk
- **2.69M keys (48%) have no TTL** and will grow indefinitely
- Contact frequency counters (`CONTACT_day/week/month`) accumulate historical data
- User group labels (`contact:userGroupLabel:set:*`) are persistent sets
- The cluster was recently restarted (16 hours ago) -- potentially due to the memory issue reported in the Redis memory alert investigation
- **Recommendation:** Add TTL to historical contact counters (90-180 days) and review whether all persistent keys truly need to be permanent

### 2. luckyus-shopsale Extremely Low Hit Rate (2.9%)
- 47.3M cache misses vs only 1.4M hits
- Only 13 keys in the entire cache
- **Recommendation:** Investigate the application code querying this cache -- likely the lookup patterns don't match what's cached, or the cache population is broken

### 3. Over-provisioned Clusters
- 8 out of 10 clusters use less than 5% of their 384 MB allocation
- Combined actual usage of these 8 clusters: ~50 MB out of 3.072 GB allocated
- **Recommendation:** Consider smaller instance types for low-usage clusters to reduce cost

### 4. luckyus-isales-order Low Hit Rate (64.4%)
- Order details cached for only ~96 seconds
- 7.4M cache misses suggests many orders are looked up after cache expiry
- **Recommendation:** Consider extending TTL to 5-10 minutes for order details, or evaluate if the access pattern benefits from caching at all

### 5. IoT Platform Architecture is Sound
- The dedup pattern with ~14s TTL and massive key churn (46M expired) is a correct and efficient design
- The 0.7% "hit rate" is actually good -- it means <1% of messages are duplicates
- Device communication hash (401 devices) provides centralized state management

### 6. Session Management is Well-Designed
- 99.6% hit rate indicates excellent cache effectiveness
- ~150K concurrent sessions with ~36-day average lifetime
- ~487 bytes per session is reasonable
- At 26% memory utilization with room to grow

---

## Data Flow Architecture

```
Customer App/POS
       |
       v
[isales-session] -----> Session validation (UUID+timestamp tokens, ~36 day TTL)
       |
       v
[isales-member] ------> Member profile lookup (2 min cache)
       |
       v
[isales-commodity] ---> Product catalog (1.5 min cache, nutrition, allergens, options)
       |
       v
[shop] ---------------> Shop details, timezone, MDM dictionaries (5 day cache)
       |
       v
[shopsale] -----------> Shop sale items, combo details (1.5 day cache)
       |
       v
[isales-order] -------> Order processing (order detail, payment status, task numbers)
       |
       v
[production] ---------> Kitchen/production (wait times, stock adjustments, receipts)
       |
       v
[scm-shopstock] ------> Inventory management (stock deductions, ingredient formulas)
       |
       v
[isales-market] ------> Marketing touchpoints (contact history, frequency control, coupons)
       |
[iotplatform] --------> Equipment monitoring (device dedup, communication state)
```
