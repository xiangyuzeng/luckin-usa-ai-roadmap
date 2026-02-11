# AWS Elasticsearch (luckycommon) 磁盘空间清理详细操作手册

> **集群名称**: luckycommon
> **账号ID**: 257394478466
> **区域**: us-east-1
> **当前磁盘空间**: 9.96 GB (危险状态)
> **操作优先级**: P0 紧急

---

## 📋 前置准备

### 1. 确认ES Endpoint

```bash
# 在jumpserver或堡垒机上执行
# 方法1: 通过AWS CLI获取endpoint
aws es describe-elasticsearch-domain \
  --domain-name luckycommon \
  --region us-east-1 \
  --query 'DomainStatus.Endpoint' \
  --output text

# 方法2: 如果已知endpoint（替换为实际值）
# 格式通常为: search-luckycommon-xxxxxxxxxxxx.us-east-1.es.amazonaws.com
export ES_ENDPOINT="https://search-luckycommon-xxxxxxxxxxxx.us-east-1.es.amazonaws.com"
```

### 2. 测试连接

```bash
# 测试ES是否可达
curl -X GET "${ES_ENDPOINT}/_cluster/health?pretty"

# 预期输出应包含:
# {
#   "cluster_name" : "257394478466:luckycommon",
#   "status" : "green",
#   ...
# }
```

### 3. 安装必要工具（如未安装）

```bash
# 检查curl版本
curl --version

# 如需安装jq用于JSON格式化（可选）
# Ubuntu/Debian:
sudo apt-get install jq -y

# CentOS/RHEL:
sudo yum install jq -y

# macOS:
brew install jq
```

---

## 🚨 P0 紧急操作：立即释放空间

### 步骤1: 查看当前所有索引及大小

**目的**: 找出占用空间最大的索引

```bash
# 执行查询，按存储大小降序排列
curl -X GET "${ES_ENDPOINT}/_cat/indices?v&h=index,store.size,pri.store.size,docs.count,status&s=store.size:desc" | head -20

# 如果安装了jq，可以用这个更详细的命令
curl -X GET "${ES_ENDPOINT}/_cat/indices?format=json" | jq -r '.[] | select(.status == "open") | [.index, .["store.size"], .["docs.count"]] | @tsv' | sort -k2 -hr | head -20
```

**预期输出示例**:
```
index                           store.size  pri.store.size  docs.count  status
logstash-2026-01-20            2.5gb       1.2gb           8234567     open
logstash-2026-01-19            2.3gb       1.1gb           7823456     open
old-application-logs-2025-12   1.8gb       900mb           5234123     open
...
```

**⚠️ 重要提示**:
- 记录下要删除的索引名称
- 确认这些是可以删除的旧数据
- **不要删除当天或昨天的索引**

---

### 步骤2: 删除超过30天的旧索引

#### 2.1 先备份索引列表（重要！）

```bash
# 保存当前所有索引到文件
curl -X GET "${ES_ENDPOINT}/_cat/indices?v" > /tmp/es_indices_backup_$(date +%Y%m%d_%H%M%S).txt

# 查看备份文件
cat /tmp/es_indices_backup_*.txt
```

#### 2.2 方法A: 删除指定日期之前的索引（安全）

```bash
# 示例：删除2025年12月的索引
# 先查询确认有哪些
curl -X GET "${ES_ENDPOINT}/_cat/indices/logstash-2025-12*?v"

# ⚠️ 确认无误后再执行删除
curl -X DELETE "${ES_ENDPOINT}/logstash-2025-12-01"
curl -X DELETE "${ES_ENDPOINT}/logstash-2025-12-02"
# ... 继续删除其他日期

# 或者使用通配符（危险！请谨慎）
# curl -X DELETE "${ES_ENDPOINT}/logstash-2025-12-*"
```

#### 2.3 方法B: 使用脚本批量删除（推荐）

创建删除脚本：

```bash
cat > /tmp/delete_old_indices.sh << 'EOF'
#!/bin/bash

# ES Endpoint
ES_ENDPOINT="https://search-luckycommon-xxxxxxxxxxxx.us-east-1.es.amazonaws.com"

# 获取所有索引
indices=$(curl -s -X GET "${ES_ENDPOINT}/_cat/indices?h=index")

# 定义要删除的日期范围（示例：2025年11月和12月）
DELETE_PATTERNS=(
  "logstash-2025-11-*"
  "logstash-2025-12-*"
  "old-logs-2025-*"
)

echo "===== 索引删除操作 ====="
echo "开始时间: $(date)"
echo ""

for pattern in "${DELETE_PATTERNS[@]}"; do
  echo "正在查找匹配 $pattern 的索引..."

  # 使用通配符匹配
  matching_indices=$(echo "$indices" | grep -E "$(echo $pattern | sed 's/\*/.*/g')")

  if [ -z "$matching_indices" ]; then
    echo "  未找到匹配的索引"
    continue
  fi

  echo "  找到以下索引:"
  echo "$matching_indices" | sed 's/^/    /'
  echo ""

  # 逐个删除（安全模式）
  while IFS= read -r index; do
    if [ -n "$index" ]; then
      echo "  删除索引: $index"
      response=$(curl -s -X DELETE "${ES_ENDPOINT}/${index}")

      if echo "$response" | grep -q '"acknowledged":true'; then
        echo "    ✅ 删除成功"
      else
        echo "    ❌ 删除失败: $response"
      fi

      # 避免请求过快
      sleep 1
    fi
  done <<< "$matching_indices"

  echo ""
done

echo "===== 操作完成 ====="
echo "结束时间: $(date)"
EOF

# 赋予执行权限
chmod +x /tmp/delete_old_indices.sh

# 执行前请再次确认ES_ENDPOINT
# 执行脚本
bash /tmp/delete_old_indices.sh
```

#### 2.4 验证删除结果

```bash
# 检查磁盘空间是否增加
curl -X GET "${ES_ENDPOINT}/_cat/allocation?v"

# 预期: available字段应该有增加

# 检查集群健康
curl -X GET "${ES_ENDPOINT}/_cluster/health?pretty"

# 预期: status仍为"green"

# 再次查看所有索引
curl -X GET "${ES_ENDPOINT}/_cat/indices?v&h=index,store.size&s=store.size:desc" | head -10
```

**预期效果**: 释放 3-5 GB 空间

---

### 步骤3: Force Merge清理已删除文档

**目的**: 回收被标记为删除但未实际释放的磁盘空间

#### 3.1 查看哪些索引有大量已删除文档

```bash
# 查看各索引的删除文档数量
curl -X GET "${ES_ENDPOINT}/_cat/indices?v&h=index,docs.count,docs.deleted,store.size&s=docs.deleted:desc" | head -10
```

**输出示例**:
```
index                    docs.count  docs.deleted  store.size
logstash-2026-01-15     5234123     823456        1.8gb
application-logs-old    2345678     456789        1.2gb
```

#### 3.2 对含有大量删除文档的索引执行Force Merge

```bash
# 对单个索引执行（示例）
curl -X POST "${ES_ENDPOINT}/logstash-2026-01-15/_forcemerge?max_num_segments=1&only_expunge_deletes=true"

# 或对所有旧索引执行（慎重！可能耗时较长）
# 建议在低峰期（凌晨）执行
curl -X POST "${ES_ENDPOINT}/logstash-2025-*/_forcemerge?max_num_segments=1&only_expunge_deletes=true"
```

**⚠️ 注意事项**:
- Force merge会占用CPU和I/O资源
- 建议在业务低峰期执行
- 不要对当天索引执行
- 执行期间集群性能可能下降

#### 3.3 监控Force Merge进度

```bash
# 查看当前正在执行的任务
curl -X GET "${ES_ENDPOINT}/_tasks?detailed=true&actions=*forcemerge"

# 查看节点统计
curl -X GET "${ES_ENDPOINT}/_nodes/stats/indices/segments?pretty"
```

#### 3.4 验证

```bash
# 再次检查磁盘空间
curl -X GET "${ES_ENDPOINT}/_cat/allocation?v"

# 检查已删除文档是否减少
curl -X GET "${ES_ENDPOINT}/_cat/indices?v&h=index,docs.count,docs.deleted,store.size&s=docs.deleted:desc" | head -10
```

**预期效果**: 释放额外 1-2 GB 空间

---

## 📅 P1 短期方案：配置数据生命周期管理

### 步骤4: 配置Index Lifecycle Management (ILM)

#### 4.1 创建ILM策略

```bash
# 创建30天自动删除的策略
curl -X PUT "${ES_ENDPOINT}/_ilm/policy/luckycommon-logs-policy" \
-H 'Content-Type: application/json' \
-d '{
  "policy": {
    "phases": {
      "hot": {
        "min_age": "0ms",
        "actions": {
          "rollover": {
            "max_age": "7d",
            "max_size": "10gb",
            "max_docs": 10000000
          },
          "set_priority": {
            "priority": 100
          }
        }
      },
      "warm": {
        "min_age": "7d",
        "actions": {
          "shrink": {
            "number_of_shards": 1
          },
          "forcemerge": {
            "max_num_segments": 1
          },
          "set_priority": {
            "priority": 50
          }
        }
      },
      "cold": {
        "min_age": "14d",
        "actions": {
          "set_priority": {
            "priority": 0
          },
          "freeze": {}
        }
      },
      "delete": {
        "min_age": "30d",
        "actions": {
          "delete": {}
        }
      }
    }
  }
}'
```

#### 4.2 验证策略创建

```bash
# 查看策略
curl -X GET "${ES_ENDPOINT}/_ilm/policy/luckycommon-logs-policy?pretty"

# 查看所有ILM策略
curl -X GET "${ES_ENDPOINT}/_ilm/policy?pretty"
```

#### 4.3 应用ILM策略到现有索引

```bash
# 方法1: 更新索引模板（新索引自动应用）
curl -X PUT "${ES_ENDPOINT}/_index_template/logstash-template" \
-H 'Content-Type: application/json' \
-d '{
  "index_patterns": ["logstash-*"],
  "template": {
    "settings": {
      "index.lifecycle.name": "luckycommon-logs-policy",
      "index.lifecycle.rollover_alias": "logstash"
    }
  }
}'

# 方法2: 对现有索引应用策略
curl -X PUT "${ES_ENDPOINT}/logstash-*/_settings" \
-H 'Content-Type: application/json' \
-d '{
  "index.lifecycle.name": "luckycommon-logs-policy"
}'
```

#### 4.4 查看ILM执行状态

```bash
# 查看ILM执行情况
curl -X GET "${ES_ENDPOINT}/_ilm/explain/logstash-*?pretty"

# 查看ILM状态
curl -X GET "${ES_ENDPOINT}/_ilm/status?pretty"
```

---

### 步骤5: 调整副本数量（可选）

**⚠️ 警告**: 降低副本数会降低数据冗余性，请谨慎评估

#### 5.1 检查当前副本配置

```bash
# 查看所有索引的副本数
curl -X GET "${ES_ENDPOINT}/_cat/indices?v&h=index,rep,pri,docs.count,store.size" | head -20
```

#### 5.2 如果副本数>1，可以考虑降低

```bash
# 示例：将旧索引副本数从2降为1
curl -X PUT "${ES_ENDPOINT}/logstash-2025-*/_settings" \
-H 'Content-Type: application/json' \
-d '{
  "index": {
    "number_of_replicas": 1
  }
}'

# 或者对特定索引
curl -X PUT "${ES_ENDPOINT}/old-logs-*/_settings" \
-H 'Content-Type: application/json' \
-d '{
  "index": {
    "number_of_replicas": 0
  }
}'
```

**注意**:
- 生产环境不建议副本数为0
- 当前索引和重要索引保持至少1个副本

#### 5.3 验证

```bash
# 检查副本数是否已更新
curl -X GET "${ES_ENDPOINT}/_cat/indices?v&h=index,rep,pri"

# 检查磁盘空间
curl -X GET "${ES_ENDPOINT}/_cat/allocation?v"
```

---

## 🔧 P2 长期方案：扩容和优化

### 步骤6: 扩容EBS存储卷

#### 6.1 通过AWS Console扩容

**操作路径**:
1. 登录 AWS Console
2. 进入 **OpenSearch Service**
3. 选择 domain: **luckycommon**
4. 点击 **Edit domain** 或 **Actions** > **Edit cluster configuration**
5. 找到 **Data nodes** 配置
6. 修改 **EBS volume size** 从当前容量增加到 **50 GB** 或更高
7. 点击 **Save changes**

**预期时间**: 30-60分钟（无需停机）

#### 6.2 通过AWS CLI扩容

```bash
# 查看当前配置
aws es describe-elasticsearch-domain \
  --domain-name luckycommon \
  --region us-east-1 \
  --query 'DomainStatus.EBSOptions'

# 更新EBS卷大小（示例：扩容到50GB）
aws es update-elasticsearch-domain-config \
  --domain-name luckycommon \
  --region us-east-1 \
  --ebs-options EBSEnabled=true,VolumeType=gp3,VolumeSize=50

# 监控更新进度
aws es describe-elasticsearch-domain \
  --domain-name luckycommon \
  --region us-east-1 \
  --query 'DomainStatus.[Processing,UpgradeProcessing]'
```

#### 6.3 验证扩容结果

```bash
# 等待15-60分钟后验证
curl -X GET "${ES_ENDPOINT}/_cat/allocation?v"

# 应该看到更大的disk.total值
```

---

### 步骤7: 设置磁盘水位线告警阈值

#### 7.1 调整集群水位线设置

```bash
# 查看当前水位线设置
curl -X GET "${ES_ENDPOINT}/_cluster/settings?include_defaults=true&pretty" | grep -A 5 "watermark"

# 更新水位线配置（临时生效）
curl -X PUT "${ES_ENDPOINT}/_cluster/settings" \
-H 'Content-Type: application/json' \
-d '{
  "transient": {
    "cluster.routing.allocation.disk.watermark.low": "85%",
    "cluster.routing.allocation.disk.watermark.high": "90%",
    "cluster.routing.allocation.disk.watermark.flood_stage": "95%"
  }
}'

# 永久生效
curl -X PUT "${ES_ENDPOINT}/_cluster/settings" \
-H 'Content-Type: application/json' \
-d '{
  "persistent": {
    "cluster.routing.allocation.disk.watermark.low": "85%",
    "cluster.routing.allocation.disk.watermark.high": "90%",
    "cluster.routing.allocation.disk.watermark.flood_stage": "95%"
  }
}'
```

---

## ✅ 操作验证清单

### 最终验证步骤

```bash
# 1. 检查集群健康
curl -X GET "${ES_ENDPOINT}/_cluster/health?pretty"
# 预期: status = "green"

# 2. 检查磁盘空间
curl -X GET "${ES_ENDPOINT}/_cat/allocation?v"
# 预期: disk.avail > 15GB (扩容后应该更多)

# 3. 检查节点状态
curl -X GET "${ES_ENDPOINT}/_cat/nodes?v&h=name,heap.percent,ram.percent,cpu,load_1m,disk.avail,node.role"

# 4. 检查索引数量和大小
curl -X GET "${ES_ENDPOINT}/_cat/indices?v" | wc -l
curl -X GET "${ES_ENDPOINT}/_cat/indices?v&h=index,store.size&s=store.size:desc" | head -10

# 5. 验证ILM策略
curl -X GET "${ES_ENDPOINT}/_ilm/policy?pretty"

# 6. 检查是否有索引处于只读状态
curl -X GET "${ES_ENDPOINT}/_cat/indices?v&h=index,status" | grep -v open
```

### 验证标准

| 检查项 | 预期值 | 当前状态 |
|--------|--------|---------|
| 集群状态 | Green | ✅ / ❌ |
| 可用磁盘 | > 15 GB | ✅ / ❌ |
| 磁盘使用率 | < 80% | ✅ / ❌ |
| ILM策略 | 已配置 | ✅ / ❌ |
| 节点数量 | 7 | ✅ / ❌ |
| 未分配分片 | 0 | ✅ / ❌ |

---

## 🔄 回滚方案

### 如果删除索引后出现问题

```bash
# 1. 停止进一步的删除操作
# 按 Ctrl+C 终止正在运行的脚本

# 2. 检查备份文件
cat /tmp/es_indices_backup_*.txt

# 3. 如果有快照备份，可以恢复
curl -X GET "${ES_ENDPOINT}/_snapshot?pretty"
curl -X POST "${ES_ENDPOINT}/_snapshot/backup_repo/snapshot_name/_restore"

# 4. 联系DBA团队协助恢复
```

### 如果Force Merge导致性能问题

```bash
# 取消正在进行的force merge任务
curl -X POST "${ES_ENDPOINT}/_tasks/_cancel?actions=*forcemerge"

# 等待集群恢复正常
curl -X GET "${ES_ENDPOINT}/_cluster/health?wait_for_status=yellow&timeout=50s"
```

---

## 📞 紧急联系方式

**出现问题时联系**:
- DBA团队: [团队联系方式]
- 基础架构团队: [团队联系方式]
- On-Call工程师: [On-Call电话]

**关键日志位置**:
- ES操作日志: `/tmp/delete_old_indices.sh` 输出
- 索引备份: `/tmp/es_indices_backup_*.txt`
- CloudWatch日志: CloudWatch > Log Groups > `/aws/opensearch/luckycommon`

---

## 📊 操作后监控

**持续监控（1周）**:

```bash
# 每日检查脚本
cat > /tmp/daily_es_check.sh << 'EOF'
#!/bin/bash
ES_ENDPOINT="https://search-luckycommon-xxxxxxxxxxxx.us-east-1.es.amazonaws.com"

echo "===== $(date) ====="
echo ""
echo "集群健康:"
curl -s -X GET "${ES_ENDPOINT}/_cluster/health?pretty" | grep -E "status|number_of"
echo ""
echo "磁盘使用:"
curl -s -X GET "${ES_ENDPOINT}/_cat/allocation?v" | head -5
echo ""
echo "索引数量:"
curl -s -X GET "${ES_ENDPOINT}/_cat/indices?v" | wc -l
echo ""
echo "最大索引:"
curl -s -X GET "${ES_ENDPOINT}/_cat/indices?v&h=index,store.size&s=store.size:desc" | head -3
echo ""
EOF

chmod +x /tmp/daily_es_check.sh

# 设置定时任务（可选）
# crontab -e
# 0 10 * * * /tmp/daily_es_check.sh >> /var/log/es_daily_check.log 2>&1
```

---

**文档版本**: v1.0
**最后更新**: 2026-01-28
**操作人**: [填写你的名字]
**审核人**: [DBA Team Lead]
