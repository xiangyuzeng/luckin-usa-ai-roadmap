# Comprehensive Database Exploration Report
## LuckyUS Marketing, Customer & Member Databases
### Generated: 2026-02-13

---

## EXECUTIVE SUMMARY

| # | Server | Database | Tables | Largest Table | Largest Row Count |
|---|--------|----------|--------|---------------|-------------------|
| 1 | aws-luckyus-isalescdp-rw | luckyus_isales_cdp | 4 | t_realtime_user_group_log | ~2.3M |
| 2 | aws-luckyus-isalesdatamarketing-rw | luckyus_isalesdatamarketing | 26 | _t_user_traffic_distribution_new | ~6.7M |
| 3 | aws-luckyus-isalesmembermarketing-rw | luckyus_isalesmembermarketing | 24 | t_member_level_period | 2 (mostly empty) |
| 4 | aws-luckyus-isalesprivatedomain-rw | luckyus_isales_privatedomain | 25 | t_reach_task_user_record | ~640K |
| 5 | aws-luckyus-cdpactivity-rw | luckyus_cdp_activity | 36 | t_contact_record | **~27M** |
| 6 | aws-luckyus-iluckyams-rw | luckyus_iluckyams | 10 | t_publish_package | 40 |
| 7 | aws-luckyus-upush-rw | 8 databases | 520+ | sms_bulk_deliver_record_lucky | ~2.3M |

**Total tenant: LKUS (Lucky US)**

---

## DATABASE 1: luckyus_isales_cdp (CDP - Customer Data Platform)
**Server:** aws-luckyus-isalescdp-rw
**Purpose:** Real-time customer event tracking and user state management

### Tables & Row Counts

| Table | ~Rows | Data Size | Description |
|-------|-------|-----------|-------------|
| t_realtime_user_group_log | 2,337,831 | 228 MB | Logs when users enter/exit user groups |
| t_user_state | 980,816 | 175 MB | Current state of user attributes |
| t_user_event_track | 168,196 | 35 MB | Detailed user event tracking |
| t_user_event | 65,182 | 7.5 MB | Core user event records |

### Key Table: t_user_event
**Columns:** id (PK, bigint), user_no (varchar 200, indexed), event_type (tinyint, indexed), event_sub_type (tinyint), event_value (varchar 200), event_time (timestamp, indexed), tenant (varchar 10), create_time, modify_time, msg_id (varchar 200, indexed), event_state_value

**Sample Data:**
```
id=389615515 | user_no=3588797569025 | event_type=3 | event_time=2026-02-13T19:13:03 | tenant=LKUS
id=389615514 | user_no=3596922613761 | event_type=2 | event_time=2026-02-13T19:13:03 | tenant=LKUS
```

### Key Table: t_user_state
**Columns:** id (PK), user_no (indexed), event_type, event_value, event_state_value, event_time, msg_id, tenant, create_time, modify_time

**Sample Data:**
```
id=1825865532518042578 | user_no=3593956995073 | event_type=8 | event_value=LKUSCP118806900749246464 | event_state_value=1
```

### Key Table: t_realtime_user_group_log
**Columns:** id (PK), user_no (indexed), group_no, event_id, cause_by, be_removed, tenant, create_time (indexed)

---

## DATABASE 2: luckyus_isalesdatamarketing (Data Marketing / A-B Testing)
**Server:** aws-luckyus-isalesdatamarketing-rw
**Purpose:** A/B testing experiments, traffic distribution, touchpoints, and real-time tactics

### Tables & Row Counts

| Table | ~Rows | Data Size | Description |
|-------|-------|-----------|-------------|
| _t_user_traffic_distribution_new | 6,734,736 | 1.4 GB | New user traffic distribution (experiment allocation) |
| t_user_hit_experiment_record | 6,470,973 | 966 MB | Records of users hitting experiments |
| t_user_traffic_distribution | 2,353,812 | 546 MB | User experiment group assignment |
| t_user_experiment_domain_record | 137,480 | 16 MB | User experiment domain records |
| t_user_search_history | 9,525 | 1.5 MB | User search history |
| t_operate_log | 223 | 312 KB | Operator audit log |
| t_experiment_group | 187 | 2.1 MB | Experiment groups definition |
| t_experiment_layer | 78 | 5.5 MB | Experiment layers |
| t_experiment | 77 | 16 KB | Experiment definitions |
| t_realtime_tactic_condition | 26 | 16 KB | Realtime tactic conditions |
| t_experiment_domain | 7 | 256 KB | Experiment domains |
| t_content_language | 6 | 16 KB | Content language mappings |
| special_tactic_layer | 3 | 16 KB | Special tactic layer config |
| t_touchpoint_link | 1 | 16 KB | Touchpoint links |
| t_touchpoint_link_shop_mapping | 1 | 16 KB | Touchpoint-shop mapping |
| t_realtime_tactic | 1 | 16 KB | Realtime tactics |
| t_realtime_tactic_benefit | 1 | 16 KB | Tactic benefits |
| t_realtime_tactic_style | 1 | 16 KB | Tactic display styles |
| t_show_style_conf | 1 | 16 KB | Show style configuration |
| t_contact_limit_conf | 1 | 16 KB | Contact frequency limit config |
| t_touchpoint | 0 | - | Touchpoint definitions (empty) |
| t_touchpoint_campaign | 0 | - | Touchpoint campaigns (empty) |
| t_touchpoint_category | 0 | - | Touchpoint categories (empty) |
| t_realtime_tactic_record | 0 | - | Tactic execution records (empty) |
| t_user_experiment_record | 0 | - | User experiment records (empty) |
| t_algorithm_recommend_record | 0 | - | Algorithm recommendation records (empty) |

### Key Table: t_experiment
**Columns:** id, experiment_no (unique), experiment_name, start_time, end_time, type, enable_status, experiment_layer_no (indexed), traffic_distribution_method, traffic_percents, remark, creator info, modifier info, tenant, version

**Sample Data:**
```
id=398 | experiment_no=LKUSTM118767120761774081 | name=来访未购0130 | start=2026-01-30 | type=1 | enable_status=2 | tenant=LKUS
id=397 | experiment_no=LKUSTM118743649906442240 | name=0126来访未购ab5折6折 | start=2026-01-26 | type=1 | enable_status=2 | tenant=LKUS
```

---

## DATABASE 3: luckyus_isalesmembermarketing (Member Marketing / Loyalty)
**Server:** aws-luckyus-isalesmembermarketing-rw
**Purpose:** Member levels, benefits, points, medals, and growth tasks

### Tables & Row Counts

| Table | ~Rows | Description |
|-------|-------|-------------|
| t_member_level_period | 2 | Member level periods |
| t_member | 0 | Core member records |
| t_member_level | 0 | Member level assignments |
| t_member_level_benefit | 0 | Level-specific benefits |
| t_member_level_income | 0 | Level income records |
| t_member_level_income_item | 0 | Income detail items |
| t_member_level_purchase | 0 | Level purchase records |
| t_member_benefit | 0 | Member benefits |
| t_member_benefit_coupon | 0 | Benefit coupons |
| t_member_benefit_premium_good | 0 | Premium goods benefits |
| t_member_benefit_record | 0 | Benefit usage records |
| t_member_growth_task | 0 | Growth task definitions |
| t_member_growth_task_operate_record | 0 | Growth task execution log |
| t_member_medal | 0 | Member medals |
| t_member_special_benefit | 0 | Special benefits |
| t_medal_config | 0 | Medal configuration |
| t_level | 0 | Level definitions |
| t_level_benefit | 0 | Level benefit config |
| t_level_transfer_record | 0 | Level transfer records |
| t_level_transfer_history | 0 | Level transfer history |
| t_point_change_record | 0 | Points change log |
| t_common_content_language | 0 | Content i18n |
| t_operate_log | 0 | Operation log |
| t_user_group_growth_user_info | 0 | User group growth info |

**NOTE:** This database is mostly EMPTY -- the member/loyalty system appears to be provisioned but not yet populated with production data for the US market.

### Key Table: t_member
**Columns:** id, user_no (indexed), member_level_no, level_no (indexed), expire_time (indexed), lucky_points (decimal 10,2), member_type, is_retained_level, tenant, version, create_time, modify_time

---

## DATABASE 4: luckyus_isales_privatedomain (Private Domain / Outreach)
**Server:** aws-luckyus-isalesprivatedomain-rw
**Purpose:** WhatsApp/Email outreach, reach tasks, mail templates, private domain user management

### Tables & Row Counts

| Table | ~Rows | Data Size | Description |
|-------|-------|-----------|-------------|
| t_reach_task_user_record | 640,528 | 331 MB | Individual user outreach records |
| t_reach_message_send_request | 617,929 | 352 MB | Message send requests |
| t_reach_task_record | 615,523 | 381 MB | Reach task execution records |
| t_mail_template | 46 | 1.5 MB | Email templates |
| t_private_domain_user | 42 | 16 KB | Private domain users |
| t_mail_send_address | 8 | 16 KB | Email sender addresses |
| t_mail_dns_record | 6 | 16 KB | DNS records for email domains |
| t_mail_domain | 5 | 16 KB | Email domains |
| t_private_domain_account | 4 | 16 KB | Private domain accounts (WhatsApp etc.) |
| t_group | 0 | - | User groups |
| t_group_user | 0 | - | Group user membership |
| t_guide_link_traffic_distribution | 0 | - | Guide link traffic split |
| t_material | 0 | - | Marketing materials |
| t_operate_log | 0 | - | Operation log |
| t_prepare_reach_user | 0 | - | Users prepared for outreach |
| t_private_domain_location | 0 | - | Location data |
| t_private_domain_shop_config | 0 | - | Shop config |
| t_session_record | 0 | - | Chat session records |
| t_template | 0 | - | Message templates |
| t_template_material | 0 | - | Template materials |
| t_user_assigned_account | 0 | - | Account assignment |
| t_user_group_info | 0 | - | User group info |
| t_whatsapp_api_account_extend | 0 | - | WhatsApp API account extensions |
| t_whatsapp_app_account_extend | 0 | - | WhatsApp app account extensions |
| t_whatsapp_app_group_extend | 0 | - | WhatsApp group extensions |

### Key Table: t_reach_task_record
**Columns:** id, task_no (unique), media_type, media_mode, status, message_status, expected_start_time (indexed), expected_end_time, account_no, receivers (text), content (text), remark (text), tenant, version, task_source, template_no, receiver_type, message_type, send_address_no

**Sample Data:**
```
id=25294627 | task_no=b4ba2e20... | media_type=2 | status=3 | expected_start=2026-02-09T14:02:47 | tenant=LKUS | task_source=userGroup
```

### Key Table: t_private_domain_user
**Columns:** id, user_no (indexed), third_user_no (indexed), name, support_status, contact_status, media_type, last_contact_account (indexed), last_contact_time, extend (text), tenant, version, private_domain_user_no (indexed), first_contact_account, first_contact_time, api_mode_contact_count, app_mode_contact_count, api_last_contact_time, app_last_contact_time

---

## DATABASE 5: luckyus_cdp_activity (CDP Activities / Contact Management)
**Server:** aws-luckyus-cdpactivity-rw
**Purpose:** Marketing contact activities, campaigns, channel management, blacklists, frequency control, templates

### Tables & Row Counts

| Table | ~Rows | Data Size | Description |
|-------|-------|-----------|-------------|
| **t_contact_record** | **27,075,883** | **5.5 GB** | **Core contact/outreach records (LARGEST TABLE)** |
| t_contact_activity_instance_sub_task_record | 292,045 | 54 MB | Activity instance sub-task execution |
| t_channel_unsubscribe | 23,461 | 2.5 MB | Channel unsubscribe records |
| t_contact_activity_instance_record | 5,162 | 1.5 MB | Activity instance records |
| t_common_content_language | 1,668 | 360 KB | i18n content translations |
| t_contact_activity_log | 1,083 | 192 KB | Activity execution log |
| t_contact_activity_channel | 532 | 192 KB | Activity channel config |
| t_contact_activity | 525 | 360 KB | Marketing activity definitions |
| t_contact_template | 406 | 176 KB | Contact message templates |
| t_contact_template_audit_record | 394 | 64 KB | Template audit trail |
| t_push_test_log | 387 | 240 KB | Push notification test log |
| t_contact_app_push_template | 171 | 64 KB | App push templates |
| t_contact_global_restrict | 96 | 16 KB | Global contact restrictions |
| t_contact_activity_frequency_ctrl_rule | 31 | 16 KB | Frequency control rules |
| t_contact_activity_category | 10 | 16 KB | Activity categories |
| t_contact_blacklist | 3 | 16 KB | Contact blacklists |
| t_contact_blacklist_detail | 1 | 16 KB | Blacklist details |
| t_contact_ack_error_rule | 0 | - | ACK error rules |
| t_contact_activity_category_freq | 0 | - | Category frequency limits |
| t_contact_activity_ref_wa | 0 | - | Activity WhatsApp references |
| t_contact_activity_sms_suffix_config_record | 0 | - | SMS suffix config |
| t_contact_blacklist_operate_record | 0 | - | Blacklist operation log |
| t_contact_marketing_grant_rule | 0 | - | Marketing grant rules |
| t_contact_marketing_grant_rule_activity_ref | 0 | - | Grant rule activity references |
| t_contact_template_extend | 0 | - | Template extensions |
| t_label | 0 | - | Labels |
| t_label_ref | 0 | - | Label references |
| t_user_group_freq_ctrl_mode | 0 | - | User group freq control modes |
| t_user_ug_contact_freq_ctrl_rule | 0 | - | UG contact freq rules |
| t_usergroup_contact_freq_ref | 0 | - | UG contact freq references |
| t_usergroup_contact_frequency_ctrl_rule | 0 | - | UG frequency control rules |
| t_wa_contact_activity_instance_record | 0 | - | WhatsApp activity instances |
| t_account_daily_data | 0 | - | Account daily aggregation |
| t_account_limit | 0 | - | Account limits |
| t_account_limit_relation | 0 | - | Account limit relations |
| t_account_limit_upgrade | 0 | - | Account limit upgrade history |

### Key Table: t_contact_record (27M rows -- LARGEST in entire system)
**Columns (31):** id, activity_id (indexed), user_no (indexed), channel, tenant, contact_time (indexed), create_time (indexed), whatsapp_latest_contact_time, whatsapp_latest_contact_operator_account, whatsapp_provider, whatsapp_api_latest_contact_operator_account, whatsapp_api_latest_contact_time, activity_no, activity_instance_no (indexed), sub_task_no, channel_contact_status, send_coupon_status, contact_begin_time, contact_complete_time, uncontact_reason, modify_time, message_id (indexed), event_type, special_tactic_layer_no, experiment_group_no, deleted, template_no, use_backup_account, use_backup_template, image_media_no, text_media_no

**Sample Data:**
```
id=831893204 | activity_id=4642 | user_no=3589857955841 | tenant=LKUS | contact_time=2026-02-13T19:04:24
id=831893203 | activity_id=4642 | user_no=3596060645377 | tenant=LKUS | contact_time=2026-02-13T19:00:53
```

### Key Table: t_contact_activity (525 activities)
**Columns (37):** id, activity_no (unique), activity_name (unique), activity_status (indexed), global_restrict, max_contact_per_day, trigger_type, trigger_time, valid_time_begin/end, trigger_cycle, week_day, month_day, contact_time, latest_contact_time, user_group, user_id_contain, test_user_id, activity_bonus, proposal_no, proposal_name, contact_type, tenant, create/modify user info, deleted, recent_trigger_time, priority, match_type, activity_type, limit_contact_time, activity_category, send_coupon_type

**Sample Data:**
```
id=4779 | activity_no=LKUSCD118849497362546688 | name=新客券包补券循环 | status=3 | trigger_type=2 | tenant=LKUS | created=2026-02-13
id=4777 | name=0212价格实验未覆盖用户_0_15 6限品+7折不限品 | status=3 | trigger_type=2 | created=2026-02-12
```

---

## DATABASE 6: luckyus_iluckyams (AMS - App Management System)
**Server:** aws-luckyus-iluckyams-rw
**Purpose:** Mobile app management, publishing, packaging, launch configs, gray-scale rules

### Tables & Row Counts

| Table | ~Rows | Description |
|-------|-------|-------------|
| t_publish_package | 40 | Publish package records |
| t_launch | 35 | App launch configurations |
| t_publish | 27 | App publish records |
| t_package | 22 | Package definitions |
| t_app | 18 | Application definitions |
| t_metadata_type | 2 | Metadata type config |
| t_metadata | 1 | Metadata records |
| t_gray_rule | 1 | Gray-scale (canary) rules |
| t_audit | 0 | Audit records |
| t_channel | 0 | Distribution channels |

### Key Table: t_app
**Columns:** id, tree_node, package_name, app_name, platform (enum: Android/IOS/HarmonyOS), supported_business, icon, lsop_app_id, git_addr, note, status, created_at, updated_at

**Sample Data:**
```
id=1 | tree_node=iluckyclientandroid | package=com.luckin.client.i | name=国际版用户端Android | platform=Android
id=2 | tree_node=iusluckyclientharmony | package=com.luckin.client.usa | name=美国版用户端鸿蒙 | platform=HarmonyOS
id=3 | tree_node=iluckyemployeeios | package=com.luckin.employee.i | name=国际工作站iOS | platform=IOS
```

---

## DATABASE 7: aws-luckyus-upush-rw (Push Notification / Messaging Platform)
**Server:** aws-luckyus-upush-rw
**Purpose:** SMS, Email, App Push, Short URLs, User Center, MDM (Master Data Management)

### Sub-databases (8 total):

#### 7a. luckyus_iupushadmin (Push Admin) -- 7 tables
| Table | ~Rows | Description |
|-------|-------|-------------|
| base_menu | - | Admin menu items |
| base_user | - | Admin users |
| t_flow_auth_user | - | Flow auth users |
| t_flow_order | - | Flow orders |
| t_flow_order_detail | - | Flow order details |
| t_sms_provider_error_msg | - | SMS provider error messages |
| t_sys_log_info | - | System log |

#### 7b. luckyus_iupushsms (SMS) -- 85 tables (sharded)
**Key non-sharded tables:**

| Table | ~Rows | Description |
|-------|-------|-------------|
| sms_bulk_deliver_record_lucky | 2,259,120 | Bulk SMS delivery records |
| sms_sent_bulk_lucky | 946,914 | Bulk SMS sent records |
| sms_deliver_record_lucky | 706,227 | Single SMS delivery records |
| sms_template | ~dozens | SMS templates |
| sms_template_provider_record | - | Provider template records |
| sms_black_list | - | SMS blacklist |
| sms_white_list | - | SMS whitelist |
| sms_custom_no | - | Custom sender numbers |
| sms_ext_no_relation | - | Extension number relations |
| sms_mo_info | - | Mobile originated messages |
| sms_statistics_record | - | Statistics records |
| t_inter_channel | - | Internal channels |
| t_inter_channel_invokers | - | Channel invokers |
| t_msg_rule | - | Message rules |
| t_provider_price_config | - | Provider pricing |
| t_collect_verifycode | - | Verification codes collected |
| t_sent_verifycode_sms | - | Sent verification codes |
| t_sms_reply_info | - | SMS reply info |
| t_verifycode_filled_statistics | - | Verification fill stats |
| voice_sms_fail_record | - | Voice SMS failures |
| voice_whitelist_for_inner | - | Voice whitelist |

**Sharded tables (32 shards each):**
- `sms_receipt_0000` to `sms_receipt_0031` (~89K-130K rows each) -- SMS delivery receipts
- `sms_sent_0000` to `sms_sent_0031` -- Individual SMS send records

**SMS Template Columns:** id, template_id (indexed), template_name, template_content (text), remark, template_type, create_time, modify_time, prod_line, from_app_name, from_app_ip, status, tenant_code, creator, modifier

#### 7c. luckyus_iupushemail (Email) -- 7 tables
| Table | Description |
|-------|-------------|
| t_attach_info | Email attachments |
| t_inter_channel | Internal channels |
| t_inter_channel_invokers | Channel invokers |
| t_mail_bulk_content | Bulk email content |
| t_mail_content | Email content |
| t_mail_send_bulk_n | Bulk email send records |
| t_mail_send_n | Single email send records |

#### 7d. luckyus_iupushapp (App Push) -- 33 tables (sharded)
**Sharded tables (32 shards):**
- `msg_center_0000` to `msg_center_0031` -- App push message center (100K-1.6M rows per shard)
  - Largest: msg_center_0004 = 1,590,865 rows
  - Total estimated: ~7-8 million messages

**Non-sharded:**
- `t_msg_statistics` -- Message statistics

#### 7e. luckyus_iupushaid (Short URL / Link Tracking) -- 24 tables (sharded)
| Table | Description |
|-------|-------------|
| t_channel | Channels |
| t_domain_provider | Domain providers |
| t_max_uuid | Max UUID tracker |
| t_short_url_access_statistics | URL access statistics |
| t_short_url_register | Short URL registration |
| t_short_url_statistics | Short URL statistics |
| t_short_url_map_0000-0008 | Short URL mappings (9 shards) |
| t_shorturl_access_record_0000-0008 | URL access records (9 shards) |

#### 7f. luckyus_iupushusercenter (User Center) -- 4 tables
| Table | ~Rows | Description |
|-------|-------|-------------|
| t_lucky_member | 273,757 | Core member/user records |
| t_lucky_employee_device | - | Employee device records |
| t_sensitive_word | - | Sensitive word filter |
| t_sensitive_word_whitelist | - | Sensitive word whitelist |

**Key Table: t_lucky_member (273K records)**
**Columns:** id, user_no (unique), origin, type, status, tenant, area_code, mask_phone_no, phone_no_encryption (indexed), security_version, create_time, modify_time, is_bind_phone, reg_id (indexed), device_no (indexed), tea_device_no, tea_reg_id, user_timezone, user_timezone_offset

**Sample Data:**
```
id=3967671 | user_no=3627028461569 | origin=6 | type=0 | status=1 | tenant=LKUS | area_code=+1 | mask_phone=61****5117
id=3967669 | user_no=3627028314113 | origin=4 | type=5 | status=1 | tenant=LKUS | area_code= | mask_phone=null
```

#### 7g. luckyus_mdm (Master Data Management) -- 358 tables
**Purpose:** Enterprise master data including shops, countries, currencies, warehouses, brands, commodities, financial entities, departments, employees, and more. Mostly reference data tables with both data tables and their _language translation counterparts.

**Key MDM data domains:**
- Geographic: country, province, city, county, time_zone
- Business: shop, brand, enterprise, tenant, system_platform
- Financial: currency, rate, cost, bank, bankbranch, payment terms
- Logistics: warehouse, carriers, transport_vehicle_type
- Products: commodity_base_info, commodity_category, commodity_sku
- HR: oversea_dept, oversea_post, employee, department
- NC (ERP): account, accountbook, cashflow, supplier

#### 7h. luckyus_mdmadmin (MDM Admin) -- 309 tables
**Purpose:** Admin interface for MDM. Similar table structure to luckyus_mdm plus admin-specific tables (t_business, t_log, t_oa_workflow_notice, t_power, t_user_role).

---

## CROSS-DATABASE RELATIONSHIP MAP

```
                    +---------------------------+
                    |   t_lucky_member (273K)   |  <-- luckyus_iupushusercenter
                    |   user_no, phone, device  |
                    +----------+----------------+
                               |
                      user_no  |
                               v
+-------------------+    +-----------+    +---------------------+
| t_user_event(65K) |<-->| user_no   |<-->| t_user_state(980K)  |
| t_user_event_     |    |           |    | CDP state tracking  |
|   track (168K)    |    |           |    +---------------------+
| CDP events        |    |           |         luckyus_isales_cdp
+-------------------+    |           |
  luckyus_isales_cdp     |           |
                         v           v
              +---------------------------+
              | t_contact_record (27M)    |  <-- luckyus_cdp_activity
              | activity_id, user_no,     |
              | channel, contact_time     |
              +----------+----------------+
                         |
                activity_id
                         v
              +---------------------------+
              | t_contact_activity (525)  |  <-- luckyus_cdp_activity
              | activity_no, name, status |
              +---------------------------+
                         |
              experiment linkage
                         v
              +---------------------------+
              | t_experiment (77)         |  <-- luckyus_isalesdatamarketing
              | A/B test definitions      |
              +---------------------------+
                         |
                         v
              +---------------------------+
              | t_user_hit_experiment     |  <-- luckyus_isalesdatamarketing
              |   _record (6.5M)          |
              +---------------------------+

           outreach via private domain
              +---------------------------+
              | t_reach_task_record(615K) |  <-- luckyus_isales_privatedomain
              | task_no, media_type,      |
              | status, template_no       |
              +---------------------------+
                         |
              message delivery
                         v
              +---------------------------+
              | SMS: sms_sent_* (sharded) |  <-- luckyus_iupushsms
              | Email: t_mail_send_*      |  <-- luckyus_iupushemail
              | Push: msg_center_*        |  <-- luckyus_iupushapp
              +---------------------------+
```

---

## KEY METRICS SUMMARY

| Metric | Value |
|--------|-------|
| Total database servers | 7 |
| Total unique databases | 14 |
| Total tables (approx) | ~550+ |
| Largest single table | t_contact_record: 27M rows, 5.5 GB data + 10 GB index |
| Total registered users (upush) | ~274K |
| Total user events (CDP) | ~65K events + ~981K state records |
| Total contact records | ~27M |
| Total marketing activities | 525 |
| Total experiments | 77 |
| Total SMS bulk deliveries | ~2.3M |
| Total app push messages | ~7-8M (across shards) |
| Total private domain reach tasks | ~616K |
| Tenant code | LKUS (Lucky US) |
| Member marketing data | Mostly empty (system provisioned, not populated) |

---

## NOTABLE OBSERVATIONS

1. **t_contact_record is the dominant table** at 27M rows and 16 GB total (data + index). This is the single largest data store and represents all outreach/contact touchpoints.

2. **Sharding strategy** is used extensively in the upush system: SMS receipts (32 shards), SMS sent (32 shards), msg_center (32 shards), short_url_map (9 shards), shorturl_access_record (9 shards).

3. **Member Marketing is provisioned but empty** -- the loyalty/membership system (levels, benefits, points, medals) has full schema but 0 rows. This appears to be pre-production or not yet launched for LKUS.

4. **A/B testing is heavily used** with 77 experiments and 6.5M user-experiment hit records, indicating active optimization of marketing campaigns.

5. **MDM is massive** with 358+ tables in luckyus_mdm alone, covering comprehensive enterprise master data (geographic, financial, logistics, HR, products).

6. **WhatsApp integration** is evident across multiple databases (private domain, CDP activity) with WhatsApp-specific columns and tables, suggesting it is a key outreach channel.

7. **All data belongs to tenant LKUS** -- this is a single-tenant deployment for Lucky US operations.
