# 如何创建 Claude Code Skills

## 什么是 Skill？

Skill 是 Claude Code 的专业化工作流程，当用户提出特定类型的请求时会自动触发。例如：
- 用户说"调查 Redis 性能问题" → 自动触发 `redis-alert-investigation` skill
- 用户说"检查 K8s Pod 问题" → 自动触发 `k8s-alert-investigation` skill

## Skill 目录结构

```
.claude/skills/
├── your-skill-name/
│   └── SKILL.md          # 必需：skill 定义文件
└── another-skill/
    └── SKILL.md
```

## SKILL.md 文件格式

### 1. YAML Front Matter（必需）

```yaml
---
name: skill-name                    # Skill 唯一标识符
description: 触发条件描述...         # 非常重要！决定何时自动触发
allowed-tools: tool1, tool2, ...    # 允许使用的工具列表
---
```

### 2. Markdown 内容（必需）

YAML 后面是 Markdown 格式的执行指令，这是 Claude 执行这个 skill 时会遵循的步骤。

## 完整示例

### 示例 1: MySQL 性能检查 Skill

```bash
mkdir -p .claude/skills/mysql-performance-check
```

创建 `.claude/skills/mysql-performance-check/SKILL.md`:

```markdown
---
name: mysql-performance-check
description: This skill should be used when the user asks to "check MySQL performance", "investigate MySQL slow queries", "analyze MySQL database", mentions MySQL/RDS performance issues, slow queries, connection problems, high CPU usage, or receives database performance alerts.
allowed-tools: Read, Grep, Glob, Bash, WebFetch, mcp__grafana__*, mcp__prometheus__*, mcp__cloudwatch-server__*, mcp__mcp-db-gateway__mysql_query
---

# MySQL Performance Investigation

You are investigating MySQL database performance issues. Follow this systematic protocol.

## Phase 1: Parse Context

Extract from the user message:
- **Database name/identifier**: MySQL instance or RDS identifier
- **Issue type**: Slow queries, high CPU, connection issues, deadlocks
- **Time window**: When the issue occurred
- **Severity**: Critical, warning, or informational

## Phase 2: Check Key Metrics

### 2.1 Query Prometheus for MySQL metrics

```promql
# Connection metrics
mysql_global_status_threads_connected{instance=~"$instance"}
mysql_global_status_max_used_connections{instance=~"$instance"}

# Query performance
rate(mysql_global_status_queries[5m])
rate(mysql_global_status_slow_queries[5m])

# InnoDB metrics
mysql_global_status_innodb_buffer_pool_pages_free
mysql_global_status_innodb_buffer_pool_pages_total
```

### 2.2 Check for slow queries (if database access available)

```sql
-- Show currently running queries
SHOW FULL PROCESSLIST;

-- Check slow query log settings
SHOW VARIABLES LIKE 'slow_query%';
SHOW VARIABLES LIKE 'long_query_time';
```

## Phase 3: Analyze Connection Pool

```promql
# Connection usage over time
mysql_global_status_threads_connected{instance=~"$instance"}

# Max connections configured
mysql_global_variables_max_connections{instance=~"$instance"}
```

Check for:
- Connection exhaustion (threads_connected approaching max_connections)
- Connection leaks (gradually increasing connections)
- Aborted connections

## Phase 4: Query Performance Analysis

### Common Issues

| Symptom | Likely Cause | Investigation |
|---------|--------------|---------------|
| High slow query rate | Missing indexes, full table scans | Check EXPLAIN plans, slow query log |
| Connection exhaustion | Connection pool misconfiguration | Check app connection settings |
| High CPU usage | Inefficient queries, missing indexes | Analyze slow query log |
| Lock contention | Long-running transactions, deadlocks | Check INNODB STATUS |

## Phase 5: Generate Report

Create a structured report:

```markdown
## MySQL Performance Report

### Database Information
- Instance: <name>
- Engine: MySQL/RDS
- Alert/Issue: <description>
- Investigation Time: <timestamp>

### Health Metrics
| Metric | Current | Threshold | Status |
|--------|---------|-----------|--------|
| Connections | X / Y | 80% of max | OK/WARN/CRIT |
| Slow Queries/sec | X | < 1 | OK/WARN/CRIT |
| CPU Usage | X% | < 70% | OK/WARN/CRIT |
| Buffer Pool Hit Rate | X% | > 95% | OK/WARN/CRIT |

### Root Cause
<analysis>

### Recommendations
1. Immediate actions
2. Short-term optimizations
3. Long-term improvements
```

## Quick Reference

| Issue | Command |
|-------|---------|
| Active queries | `SHOW FULL PROCESSLIST` |
| Slow queries | `SELECT * FROM mysql.slow_log LIMIT 10` |
| Lock status | `SHOW ENGINE INNODB STATUS` |
| Table stats | `SHOW TABLE STATUS` |
| Index usage | `SHOW INDEX FROM table_name` |
```

---

### 示例 2: 日志分析 Skill

创建 `.claude/skills/log-analysis/SKILL.md`:

```markdown
---
name: log-analysis
description: Use this skill when the user asks to "analyze logs", "search logs for errors", "investigate application logs", "find log patterns", or mentions log analysis, error tracking, or debugging through logs.
allowed-tools: Read, Grep, Glob, Bash, mcp__grafana__query_loki_logs, mcp__cloudwatch-server__*
---

# Log Analysis Workflow

## Phase 1: Identify Log Source
- Log file paths or Loki/CloudWatch log groups
- Time range for analysis
- Keywords or error patterns to search for

## Phase 2: Search Logs

### For file-based logs:
```bash
grep -i "error\|exception\|fatal" /var/log/app/*.log | tail -n 100
```

### For Loki:
```logql
{app="myapp"} |= "error" | json | line_format "{{.timestamp}} {{.level}} {{.message}}"
```

## Phase 3: Pattern Analysis
- Identify common error patterns
- Count occurrences
- Find correlations with timestamps

## Phase 4: Report Findings
Present top errors, patterns, and recommendations.
```

---

## 关键配置说明

### 1. `description` 字段（最重要！）

这个字段决定了 skill 何时被触发。应该包含：
- ✅ 用户可能使用的关键词
- ✅ 问题的具体描述
- ✅ 相关的服务或技术名称

**好的示例**:
```yaml
description: This skill should be used when the user asks to "investigate Redis alert", "debug cache issues", "check Redis cluster", "analyze Redis performance", mentions Redis/ElastiCache issues, cache memory pressure, high latency, connection exhaustion, evictions, or receives alerts about Redis clusters.
```

**不好的示例**:
```yaml
description: Redis investigation
```

### 2. `allowed-tools` 字段

指定这个 skill 可以使用哪些工具：

**常用工具**:
- `Read` - 读取文件
- `Grep` - 搜索文件内容
- `Glob` - 查找文件
- `Bash` - 执行命令
- `Write` - 写入文件
- `Edit` - 编辑文件
- `WebFetch` - 获取网页内容
- `WebSearch` - 网页搜索

**MCP 服务器工具**（使用通配符）:
- `mcp__grafana__*` - 所有 Grafana 工具
- `mcp__prometheus__*` - 所有 Prometheus 工具
- `mcp__cloudwatch-server__*` - 所有 CloudWatch 工具
- `mcp__mcp-db-gateway__*` - 所有数据库工具

**具体的 MCP 工具**:
- `mcp__grafana__query_prometheus`
- `mcp__mcp-db-gateway__mysql_query`
- `mcp__mcp-db-gateway__redis_command`

## 创建流程

### 方法 1: 手动创建

```bash
# 1. 创建目录
mkdir -p .claude/skills/my-new-skill

# 2. 创建 SKILL.md 文件
nano .claude/skills/my-new-skill/SKILL.md

# 3. 添加内容（参考上面的示例）
```

### 方法 2: 使用脚本创建

创建一个辅助脚本 `create-skill.sh`:

```bash
#!/bin/bash

SKILL_NAME=$1
if [ -z "$SKILL_NAME" ]; then
    echo "Usage: ./create-skill.sh <skill-name>"
    exit 1
fi

SKILL_DIR=".claude/skills/$SKILL_NAME"
mkdir -p "$SKILL_DIR"

cat > "$SKILL_DIR/SKILL.md" << EOF
---
name: $SKILL_NAME
description: TODO - Add description of when to trigger this skill
allowed-tools: Read, Grep, Glob, Bash
---

# $SKILL_NAME

## Phase 1: TODO
Add your investigation steps here...

## Phase 2: TODO
Add analysis steps...

## Phase 3: Generate Report
Create structured output...
EOF

echo "✅ Created skill at: $SKILL_DIR/SKILL.md"
echo "📝 Please edit the file to customize your skill!"
```

使用方法:
```bash
chmod +x create-skill.sh
./create-skill.sh my-awesome-skill
```

## 测试 Skill

创建 skill 后，可以通过以下方式测试：

### 方法 1: 直接调用
```bash
/my-skill-name argument1 argument2
```

### 方法 2: 自然语言触发
说出 description 中包含的关键词，Claude 会自动识别并触发相应的 skill。

## 最佳实践

### ✅ 应该做的

1. **清晰的 description**: 包含所有可能触发的关键词
2. **结构化步骤**: 使用 Phase 1, Phase 2 等组织流程
3. **具体的示例**: 提供 PromQL、SQL 查询示例
4. **标准化输出**: 使用表格或 Markdown 格式化报告
5. **错误处理**: 考虑各种边界情况

### ❌ 应该避免的

1. **模糊的 description**: "A skill for databases" 太宽泛
2. **过于复杂**: 一个 skill 只做一件事
3. **硬编码值**: 使用变量而不是固定值
4. **缺少文档**: 每个步骤都应该有说明

## Skill 示例库

### 基础设施监控
- `redis-alert-investigation` - Redis 性能调查
- `k8s-alert-investigation` - Kubernetes 问题诊断
- `rds-alert-investigation` - RDS 数据库调查
- `ec2-alert-investigation` - EC2 实例问题

### 自定义 Skill 创意
- `cost-analysis` - AWS 成本分析
- `security-audit` - 安全审计
- `deployment-verification` - 部署验证
- `api-performance-check` - API 性能检查
- `backup-verification` - 备份验证

## 调试技巧

如果 skill 没有被触发：
1. 检查 `description` 是否包含用户使用的关键词
2. 确保 YAML front matter 格式正确（三个破折号）
3. 验证 skill 目录名和 `name` 字段一致
4. 查看 skill 文件权限是否正确

## 高级功能

### 参数传递

Skill 可以接收参数：

```markdown
You will receive arguments in the format:
ARGUMENTS: <arg1> <arg2> <arg3>

Parse these arguments to customize your investigation.
```

### 工具链集成

结合多个 MCP 服务器：

```yaml
allowed-tools: mcp__grafana__*, mcp__prometheus__*, mcp__cloudwatch-server__*, mcp__eks-server__*
```

### 条件逻辑

在 skill 中可以包含条件判断：

```markdown
## Phase 2: Check Infrastructure Type

If using AWS:
- Query CloudWatch metrics
- Check RDS/ElastiCache status

If using on-premise:
- Query Prometheus
- Check local Redis instance
```

## 下一步

1. 查看现有 skills: `ls -la .claude/skills/*/SKILL.md`
2. 复制一个相似的 skill 作为模板
3. 根据你的需求修改
4. 测试并迭代改进

## 获取帮助

- 查看现有 skill 的实现参考
- 阅读 Claude Code 文档
- 在社区论坛提问

---

**祝你创建出强大的 Skills！** 🚀
