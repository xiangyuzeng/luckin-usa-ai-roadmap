#!/usr/bin/env python3
"""
MySQL 数据库健康检查脚本
检查连接数、缓存命中率、慢查询、锁等待、复制延迟和磁盘I/O
"""

import pymysql
import sys
import argparse
from datetime import datetime
from typing import Dict, Any, Optional


class MySQLHealthChecker:
    def __init__(self, host: str, port: int, user: str, password: str, database: str = ''):
        self.conn_params = {
            'host': host,
            'port': port,
            'user': user,
            'password': password,
            'database': database,
            'cursorclass': pymysql.cursors.DictCursor
        }
        self.conn = None

    def connect(self):
        """建立数据库连接"""
        try:
            self.conn = pymysql.connect(**self.conn_params)
            return True
        except Exception as e:
            print(f"❌ 连接失败: {e}")
            return False

    def close(self):
        """关闭数据库连接"""
        if self.conn:
            self.conn.close()

    def execute_query(self, query: str) -> Optional[Any]:
        """执行查询并返回结果"""
        try:
            with self.conn.cursor() as cursor:
                cursor.execute(query)
                return cursor.fetchall()
        except Exception as e:
            print(f"查询执行错误: {e}")
            return None

    def get_variable(self, var_name: str) -> Optional[str]:
        """获取MySQL变量值"""
        result = self.execute_query(f"SHOW VARIABLES LIKE '{var_name}'")
        if result and len(result) > 0:
            return result[0]['Value']
        return None

    def get_status(self, status_name: str) -> Optional[str]:
        """获取MySQL状态值"""
        result = self.execute_query(f"SHOW STATUS LIKE '{status_name}'")
        if result and len(result) > 0:
            return result[0]['Value']
        return None

    def check_connections(self) -> Dict[str, Any]:
        """检查连接数状态"""
        print("\n" + "="*60)
        print("1. 连接数状态检查")
        print("="*60)

        max_connections = int(self.get_variable('max_connections') or 0)
        current_connections = int(self.get_status('Threads_connected') or 0)
        max_used_connections = int(self.get_status('Max_used_connections') or 0)

        usage_percent = (current_connections / max_connections * 100) if max_connections > 0 else 0

        print(f"最大连接数:       {max_connections}")
        print(f"当前连接数:       {current_connections}")
        print(f"历史最大连接数:   {max_used_connections}")
        print(f"连接使用率:       {usage_percent:.2f}%")

        if usage_percent > 80:
            print("⚠️  警告: 连接使用率超过 80%，建议增加 max_connections")
        elif usage_percent > 90:
            print("❌ 严重: 连接使用率超过 90%，急需增加连接数!")
        else:
            print("✅ 连接数状态正常")

        return {
            'max_connections': max_connections,
            'current_connections': current_connections,
            'usage_percent': usage_percent
        }

    def check_cache_hit_rate(self) -> Dict[str, Any]:
        """检查缓存命中率"""
        print("\n" + "="*60)
        print("2. 缓存命中率检查")
        print("="*60)

        # Query Cache (MySQL 5.7及以下)
        query_cache_enabled = self.get_variable('query_cache_type')
        if query_cache_enabled and query_cache_enabled != 'OFF':
            qc_hits = int(self.get_status('Qcache_hits') or 0)
            qc_inserts = int(self.get_status('Qcache_inserts') or 0)
            qc_not_cached = int(self.get_status('Qcache_not_cached') or 0)

            total = qc_hits + qc_inserts + qc_not_cached
            qc_hit_rate = (qc_hits / total * 100) if total > 0 else 0

            print(f"查询缓存命中率:   {qc_hit_rate:.2f}%")
            print(f"  缓存命中:       {qc_hits}")
            print(f"  缓存未命中:     {qc_inserts}")
        else:
            print("查询缓存:         已禁用 (MySQL 8.0+ 已移除)")
            qc_hit_rate = 0

        # InnoDB Buffer Pool
        print("\nInnoDB Buffer Pool:")
        bp_size = int(self.get_variable('innodb_buffer_pool_size') or 0)
        bp_read_requests = int(self.get_status('Innodb_buffer_pool_read_requests') or 0)
        bp_reads = int(self.get_status('Innodb_buffer_pool_reads') or 0)

        bp_hit_rate = ((bp_read_requests - bp_reads) / bp_read_requests * 100) if bp_read_requests > 0 else 0

        print(f"Buffer Pool 大小: {bp_size / (1024**3):.2f} GB")
        print(f"Buffer Pool 命中率: {bp_hit_rate:.2f}%")
        print(f"  逻辑读取:       {bp_read_requests}")
        print(f"  物理读取:       {bp_reads}")

        if bp_hit_rate < 95:
            print("⚠️  警告: Buffer Pool 命中率低于 95%，建议增加 innodb_buffer_pool_size")
        else:
            print("✅ Buffer Pool 命中率正常")

        return {
            'query_cache_hit_rate': qc_hit_rate,
            'buffer_pool_hit_rate': bp_hit_rate
        }

    def check_slow_queries(self) -> Dict[str, Any]:
        """检查慢查询统计"""
        print("\n" + "="*60)
        print("3. 慢查询统计")
        print("="*60)

        slow_query_log = self.get_variable('slow_query_log')
        long_query_time = float(self.get_variable('long_query_time') or 0)
        slow_queries = int(self.get_status('Slow_queries') or 0)
        total_queries = int(self.get_status('Questions') or 0)

        slow_query_percent = (slow_queries / total_queries * 100) if total_queries > 0 else 0

        print(f"慢查询日志:       {'启用' if slow_query_log == 'ON' else '禁用'}")
        print(f"慢查询阈值:       {long_query_time} 秒")
        print(f"慢查询总数:       {slow_queries}")
        print(f"总查询数:         {total_queries}")
        print(f"慢查询占比:       {slow_query_percent:.4f}%")

        if slow_queries > 0 and slow_query_percent > 0.1:
            print("⚠️  警告: 慢查询占比较高，建议优化查询或索引")
        elif slow_queries > 0:
            print("⚠️  注意: 存在慢查询，建议定期检查慢查询日志")
        else:
            print("✅ 暂无慢查询记录")

        return {
            'slow_queries': slow_queries,
            'total_queries': total_queries,
            'slow_query_percent': slow_query_percent
        }

    def check_locks(self) -> Dict[str, Any]:
        """检查表锁和行锁等待"""
        print("\n" + "="*60)
        print("4. 锁等待检查")
        print("="*60)

        # 表锁
        table_locks_waited = int(self.get_status('Table_locks_waited') or 0)
        table_locks_immediate = int(self.get_status('Table_locks_immediate') or 0)

        total_table_locks = table_locks_waited + table_locks_immediate
        table_lock_wait_rate = (table_locks_waited / total_table_locks * 100) if total_table_locks > 0 else 0

        print(f"表锁等待次数:     {table_locks_waited}")
        print(f"表锁立即获取:     {table_locks_immediate}")
        print(f"表锁等待率:       {table_lock_wait_rate:.4f}%")

        # InnoDB 行锁
        print("\nInnoDB 行锁:")
        row_lock_waits = int(self.get_status('Innodb_row_lock_waits') or 0)
        row_lock_time = int(self.get_status('Innodb_row_lock_time') or 0)
        row_lock_time_avg = int(self.get_status('Innodb_row_lock_time_avg') or 0)
        row_lock_current_waits = int(self.get_status('Innodb_row_lock_current_waits') or 0)

        print(f"行锁等待次数:     {row_lock_waits}")
        print(f"行锁等待时间:     {row_lock_time} ms")
        print(f"平均等待时间:     {row_lock_time_avg} ms")
        print(f"当前等待数:       {row_lock_current_waits}")

        if table_lock_wait_rate > 1:
            print("⚠️  警告: 表锁等待率较高，建议优化表结构或使用 InnoDB")
        if row_lock_waits > 1000:
            print("⚠️  警告: InnoDB 行锁等待次数较多，可能存在锁竞争")
        if row_lock_current_waits > 0:
            print(f"⚠️  注意: 当前有 {row_lock_current_waits} 个事务在等待行锁")

        if table_lock_wait_rate <= 1 and row_lock_waits <= 1000 and row_lock_current_waits == 0:
            print("✅ 锁等待状态正常")

        return {
            'table_lock_wait_rate': table_lock_wait_rate,
            'row_lock_waits': row_lock_waits,
            'row_lock_current_waits': row_lock_current_waits
        }

    def check_replication(self) -> Dict[str, Any]:
        """检查复制延迟"""
        print("\n" + "="*60)
        print("5. 复制延迟检查")
        print("="*60)

        try:
            slave_status = self.execute_query("SHOW SLAVE STATUS")

            if not slave_status or len(slave_status) == 0:
                print("ℹ️  此实例不是从库或未配置主从复制")
                return {'is_slave': False}

            status = slave_status[0]

            slave_io_running = status.get('Slave_IO_Running', 'No')
            slave_sql_running = status.get('Slave_SQL_Running', 'No')
            seconds_behind_master = status.get('Seconds_Behind_Master')
            master_host = status.get('Master_Host', 'N/A')
            last_error = status.get('Last_Error', '')

            print(f"主库地址:         {master_host}")
            print(f"Slave_IO_Running: {slave_io_running}")
            print(f"Slave_SQL_Running: {slave_sql_running}")

            if seconds_behind_master is None:
                print(f"复制延迟:         未知 (复制可能已停止)")
                print("❌ 错误: 复制状态异常")
            else:
                print(f"复制延迟:         {seconds_behind_master} 秒")

                if slave_io_running != 'Yes' or slave_sql_running != 'Yes':
                    print("❌ 错误: 复制线程未运行")
                    if last_error:
                        print(f"   错误信息: {last_error}")
                elif seconds_behind_master > 60:
                    print("⚠️  警告: 复制延迟超过 60 秒")
                elif seconds_behind_master > 10:
                    print("⚠️  注意: 复制延迟超过 10 秒")
                else:
                    print("✅ 复制状态正常")

            return {
                'is_slave': True,
                'slave_io_running': slave_io_running,
                'slave_sql_running': slave_sql_running,
                'seconds_behind_master': seconds_behind_master
            }

        except Exception as e:
            print(f"检查复制状态时出错: {e}")
            return {'is_slave': False, 'error': str(e)}

    def check_disk_io(self) -> Dict[str, Any]:
        """检查磁盘 I/O"""
        print("\n" + "="*60)
        print("6. 磁盘 I/O 检查")
        print("="*60)

        # InnoDB I/O
        print("InnoDB I/O 统计:")
        data_read = int(self.get_status('Innodb_data_read') or 0)
        data_written = int(self.get_status('Innodb_data_written') or 0)
        data_reads = int(self.get_status('Innodb_data_reads') or 0)
        data_writes = int(self.get_status('Innodb_data_writes') or 0)
        os_log_written = int(self.get_status('Innodb_os_log_written') or 0)

        print(f"数据读取量:       {data_read / (1024**3):.2f} GB")
        print(f"数据写入量:       {data_written / (1024**3):.2f} GB")
        print(f"读取操作次数:     {data_reads}")
        print(f"写入操作次数:     {data_writes}")
        print(f"日志写入量:       {os_log_written / (1024**3):.2f} GB")

        # InnoDB 刷盘
        print("\nInnoDB 刷盘统计:")
        pages_flushed = int(self.get_status('Innodb_buffer_pool_pages_flushed') or 0)
        log_writes = int(self.get_status('Innodb_log_writes') or 0)

        print(f"刷新页面数:       {pages_flushed}")
        print(f"日志写入次数:     {log_writes}")

        # 表缓存
        print("\n表缓存:")
        opened_tables = int(self.get_status('Opened_tables') or 0)
        open_tables = int(self.get_status('Open_tables') or 0)
        table_open_cache = int(self.get_variable('table_open_cache') or 0)

        print(f"打开表总数:       {opened_tables}")
        print(f"当前打开表:       {open_tables}")
        print(f"表缓存大小:       {table_open_cache}")

        if open_tables >= table_open_cache * 0.9:
            print("⚠️  警告: 表缓存使用率过高，建议增加 table_open_cache")
        else:
            print("✅ I/O 统计已收集")

        return {
            'data_read_gb': data_read / (1024**3),
            'data_written_gb': data_written / (1024**3),
            'data_reads': data_reads,
            'data_writes': data_writes
        }

    def run_health_check(self):
        """运行完整健康检查"""
        print("\n" + "="*60)
        print(f"MySQL 数据库健康检查报告")
        print(f"检查时间: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
        print(f"数据库地址: {self.conn_params['host']}:{self.conn_params['port']}")
        print("="*60)

        if not self.connect():
            return False

        try:
            # 获取版本信息
            version = self.get_variable('version')
            print(f"MySQL 版本: {version}")

            # 运行各项检查
            self.check_connections()
            self.check_cache_hit_rate()
            self.check_slow_queries()
            self.check_locks()
            self.check_replication()
            self.check_disk_io()

            print("\n" + "="*60)
            print("健康检查完成")
            print("="*60 + "\n")

            return True

        except Exception as e:
            print(f"\n❌ 健康检查过程中发生错误: {e}")
            return False
        finally:
            self.close()


def main():
    parser = argparse.ArgumentParser(description='MySQL 数据库健康检查脚本')
    parser.add_argument('-H', '--host', required=True, help='MySQL 主机地址')
    parser.add_argument('-P', '--port', type=int, default=3306, help='MySQL 端口 (默认: 3306)')
    parser.add_argument('-u', '--user', required=True, help='MySQL 用户名')
    parser.add_argument('-p', '--password', required=True, help='MySQL 密码')
    parser.add_argument('-d', '--database', default='', help='数据库名 (可选)')

    args = parser.parse_args()

    checker = MySQLHealthChecker(
        host=args.host,
        port=args.port,
        user=args.user,
        password=args.password,
        database=args.database
    )

    success = checker.run_health_check()
    sys.exit(0 if success else 1)


if __name__ == '__main__':
    main()
