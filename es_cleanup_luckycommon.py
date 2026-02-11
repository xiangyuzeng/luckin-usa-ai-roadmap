#!/usr/bin/env python3
"""
AWS Elasticsearch (luckycommon) 磁盘空间清理脚本

用途: 自动清理超过指定天数的旧索引，释放磁盘空间
集群: luckycommon
账号: 257394478466
区域: us-east-1

使用方法:
    python3 es_cleanup_luckycommon.py --endpoint https://search-luckycommon-xxx.us-east-1.es.amazonaws.com --days 30 --dry-run
    python3 es_cleanup_luckycommon.py --endpoint https://search-luckycommon-xxx.us-east-1.es.amazonaws.com --days 30  # 真实执行

需要安装: pip3 install requests python-dateutil
"""

import argparse
import requests
import json
import re
from datetime import datetime, timedelta
from dateutil import parser as date_parser
import sys
import logging

# 配置日志
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)


class ElasticsearchCleaner:
    def __init__(self, endpoint, verify_ssl=True):
        """初始化ES清理器

        Args:
            endpoint: ES集群endpoint URL
            verify_ssl: 是否验证SSL证书
        """
        self.endpoint = endpoint.rstrip('/')
        self.verify_ssl = verify_ssl
        self.session = requests.Session()

    def get_cluster_health(self):
        """获取集群健康状态"""
        try:
            response = self.session.get(
                f"{self.endpoint}/_cluster/health",
                verify=self.verify_ssl,
                timeout=10
            )
            response.raise_for_status()
            return response.json()
        except Exception as e:
            logger.error(f"获取集群健康状态失败: {e}")
            return None

    def get_all_indices(self):
        """获取所有索引列表"""
        try:
            response = self.session.get(
                f"{self.endpoint}/_cat/indices?format=json",
                verify=self.verify_ssl,
                timeout=30
            )
            response.raise_for_status()
            return response.json()
        except Exception as e:
            logger.error(f"获取索引列表失败: {e}")
            return []

    def parse_index_date(self, index_name):
        """从索引名称中提取日期

        支持的格式:
        - logstash-2026-01-28
        - application-logs-2026.01.28
        - logs-2026-01-28-001

        Args:
            index_name: 索引名称

        Returns:
            datetime对象或None
        """
        # 尝试多种日期格式
        patterns = [
            r'(\d{4}-\d{2}-\d{2})',  # 2026-01-28
            r'(\d{4}\.\d{2}\.\d{2})', # 2026.01.28
            r'(\d{4}_\d{2}_\d{2})',   # 2026_01_28
        ]

        for pattern in patterns:
            match = re.search(pattern, index_name)
            if match:
                date_str = match.group(1)
                try:
                    # 尝试解析日期
                    return datetime.strptime(date_str.replace('.', '-').replace('_', '-'), '%Y-%m-%d')
                except ValueError:
                    continue

        return None

    def find_old_indices(self, days_threshold=30, patterns=None):
        """查找超过指定天数的旧索引

        Args:
            days_threshold: 天数阈值，超过此天数的索引将被标记
            patterns: 索引名称模式列表，只处理匹配的索引（可选）

        Returns:
            符合条件的索引列表
        """
        all_indices = self.get_all_indices()
        if not all_indices:
            logger.warning("未获取到任何索引")
            return []

        cutoff_date = datetime.now() - timedelta(days=days_threshold)
        old_indices = []

        logger.info(f"总索引数: {len(all_indices)}")
        logger.info(f"截止日期: {cutoff_date.strftime('%Y-%m-%d')}")
        logger.info(f"将查找 {days_threshold} 天之前的索引")

        for index in all_indices:
            index_name = index.get('index', '')

            # 跳过系统索引
            if index_name.startswith('.'):
                continue

            # 如果指定了模式，检查是否匹配
            if patterns:
                if not any(re.match(pattern.replace('*', '.*'), index_name) for pattern in patterns):
                    continue

            # 尝试从索引名称解析日期
            index_date = self.parse_index_date(index_name)

            if index_date and index_date < cutoff_date:
                old_indices.append({
                    'name': index_name,
                    'date': index_date,
                    'size': index.get('store.size', 'unknown'),
                    'docs_count': index.get('docs.count', 'unknown'),
                    'status': index.get('status', 'unknown')
                })

        # 按日期排序
        old_indices.sort(key=lambda x: x['date'])

        return old_indices

    def delete_index(self, index_name):
        """删除指定索引

        Args:
            index_name: 要删除的索引名称

        Returns:
            (成功标志, 响应消息)
        """
        try:
            response = self.session.delete(
                f"{self.endpoint}/{index_name}",
                verify=self.verify_ssl,
                timeout=30
            )
            response.raise_for_status()
            result = response.json()

            if result.get('acknowledged'):
                return True, "删除成功"
            else:
                return False, f"删除失败: {result}"

        except Exception as e:
            return False, f"删除异常: {e}"

    def get_disk_usage(self):
        """获取磁盘使用情况"""
        try:
            response = self.session.get(
                f"{self.endpoint}/_cat/allocation?format=json",
                verify=self.verify_ssl,
                timeout=10
            )
            response.raise_for_status()
            return response.json()
        except Exception as e:
            logger.error(f"获取磁盘使用情况失败: {e}")
            return []

    def force_merge_index(self, index_pattern, max_num_segments=1):
        """对索引执行force merge

        Args:
            index_pattern: 索引名称或模式
            max_num_segments: 最大segment数量

        Returns:
            (成功标志, 响应消息)
        """
        try:
            response = self.session.post(
                f"{self.endpoint}/{index_pattern}/_forcemerge",
                params={
                    'max_num_segments': max_num_segments,
                    'only_expunge_deletes': 'true'
                },
                verify=self.verify_ssl,
                timeout=300
            )
            response.raise_for_status()
            result = response.json()
            return True, result
        except Exception as e:
            return False, f"Force merge失败: {e}"


def main():
    parser = argparse.ArgumentParser(
        description='AWS Elasticsearch 索引清理工具',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
使用示例:
  # 查看30天之前的所有索引（不删除）
  python3 es_cleanup_luckycommon.py --endpoint https://search-xxx.es.amazonaws.com --days 30 --dry-run

  # 删除30天之前的logstash索引
  python3 es_cleanup_luckycommon.py --endpoint https://search-xxx.es.amazonaws.com --days 30 --pattern "logstash-*"

  # 删除60天之前的所有索引
  python3 es_cleanup_luckycommon.py --endpoint https://search-xxx.es.amazonaws.com --days 60 --yes
        """
    )

    parser.add_argument(
        '--endpoint',
        required=True,
        help='ES集群endpoint URL (例: https://search-luckycommon-xxx.us-east-1.es.amazonaws.com)'
    )
    parser.add_argument(
        '--days',
        type=int,
        default=30,
        help='删除多少天之前的索引 (默认: 30)'
    )
    parser.add_argument(
        '--pattern',
        action='append',
        help='索引名称模式，可多次指定 (例: --pattern "logstash-*" --pattern "old-logs-*")'
    )
    parser.add_argument(
        '--dry-run',
        action='store_true',
        help='仅模拟执行，不实际删除'
    )
    parser.add_argument(
        '--yes',
        action='store_true',
        help='跳过确认提示，直接执行'
    )
    parser.add_argument(
        '--force-merge',
        action='store_true',
        help='删除后对剩余索引执行force merge'
    )
    parser.add_argument(
        '--no-verify-ssl',
        action='store_true',
        help='不验证SSL证书'
    )

    args = parser.parse_args()

    # 创建清理器
    cleaner = ElasticsearchCleaner(
        endpoint=args.endpoint,
        verify_ssl=not args.no_verify_ssl
    )

    # 检查集群健康
    logger.info("=" * 60)
    logger.info("检查集群健康状态...")
    health = cleaner.get_cluster_health()
    if not health:
        logger.error("无法连接到ES集群，请检查endpoint是否正确")
        sys.exit(1)

    logger.info(f"集群名称: {health.get('cluster_name')}")
    logger.info(f"集群状态: {health.get('status')}")
    logger.info(f"节点数量: {health.get('number_of_nodes')}")

    if health.get('status') == 'red':
        logger.error("集群状态为RED，建议先解决集群问题后再清理索引")
        sys.exit(1)

    # 获取磁盘使用情况
    logger.info("\n当前磁盘使用情况:")
    disk_usage = cleaner.get_disk_usage()
    for node in disk_usage[:3]:  # 只显示前3个节点
        logger.info(f"  节点: {node.get('node', 'N/A')}")
        logger.info(f"    总容量: {node.get('disk.total', 'N/A')}")
        logger.info(f"    已使用: {node.get('disk.used', 'N/A')}")
        logger.info(f"    可用: {node.get('disk.avail', 'N/A')}")
        logger.info(f"    使用率: {node.get('disk.percent', 'N/A')}%")

    # 查找旧索引
    logger.info("\n" + "=" * 60)
    logger.info(f"查找超过 {args.days} 天的旧索引...")
    old_indices = cleaner.find_old_indices(
        days_threshold=args.days,
        patterns=args.pattern
    )

    if not old_indices:
        logger.info("未找到符合条件的旧索引")
        return

    # 显示找到的索引
    logger.info(f"\n找到 {len(old_indices)} 个符合条件的索引:")
    total_size = 0
    for idx in old_indices:
        logger.info(f"  - {idx['name']:<50} | 日期: {idx['date'].strftime('%Y-%m-%d')} | 大小: {idx['size']:<10} | 文档数: {idx['docs_count']}")

    # 如果是dry-run模式，这里就结束
    if args.dry_run:
        logger.info("\n[DRY RUN] 模拟模式，未执行实际删除")
        logger.info(f"如需删除，请移除 --dry-run 参数")
        return

    # 确认删除
    if not args.yes:
        logger.warning("\n" + "=" * 60)
        logger.warning("⚠️  即将删除以上索引，此操作不可恢复！")
        logger.warning("=" * 60)
        confirm = input(f"\n确认删除这 {len(old_indices)} 个索引？ (yes/no): ")
        if confirm.lower() != 'yes':
            logger.info("操作已取消")
            return

    # 执行删除
    logger.info("\n开始删除索引...")
    success_count = 0
    failed_count = 0

    for idx in old_indices:
        index_name = idx['name']
        logger.info(f"\n删除索引: {index_name}")

        success, message = cleaner.delete_index(index_name)
        if success:
            logger.info(f"  ✅ {message}")
            success_count += 1
        else:
            logger.error(f"  ❌ {message}")
            failed_count += 1

        # 避免请求过快
        import time
        time.sleep(1)

    # 删除完成后的统计
    logger.info("\n" + "=" * 60)
    logger.info("删除操作完成")
    logger.info(f"  成功: {success_count}")
    logger.info(f"  失败: {failed_count}")

    # 再次检查磁盘使用情况
    logger.info("\n删除后磁盘使用情况:")
    disk_usage_after = cleaner.get_disk_usage()
    for node in disk_usage_after[:3]:
        logger.info(f"  节点: {node.get('node', 'N/A')}")
        logger.info(f"    可用: {node.get('disk.avail', 'N/A')}")
        logger.info(f"    使用率: {node.get('disk.percent', 'N/A')}%")

    # 如果指定了force-merge
    if args.force_merge and success_count > 0:
        logger.info("\n" + "=" * 60)
        logger.info("执行Force Merge...")
        logger.warning("⚠️  Force merge可能耗时较长，请耐心等待...")

        # 对剩余的旧索引执行force merge
        remaining_patterns = set()
        for idx in old_indices:
            # 提取索引前缀
            parts = idx['name'].split('-')
            if len(parts) >= 2:
                pattern = f"{parts[0]}-{parts[1]}-*"
                remaining_patterns.add(pattern)

        for pattern in remaining_patterns:
            logger.info(f"\nForce merge索引模式: {pattern}")
            success, message = cleaner.force_merge_index(pattern)
            if success:
                logger.info(f"  ✅ Force merge完成")
            else:
                logger.error(f"  ❌ {message}")

    logger.info("\n" + "=" * 60)
    logger.info("所有操作完成")
    logger.info("=" * 60)


if __name__ == '__main__':
    try:
        main()
    except KeyboardInterrupt:
        logger.warning("\n\n操作被用户中断")
        sys.exit(1)
    except Exception as e:
        logger.error(f"\n发生错误: {e}", exc_info=True)
        sys.exit(1)
