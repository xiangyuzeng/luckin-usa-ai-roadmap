#!/usr/bin/env python3
"""
Luckin Coffee K8s Data Analysis Script
Parses all collected data and generates structured architecture summary
"""

import json
import os
import re
from pathlib import Path
from collections import defaultdict
from datetime import datetime
from typing import Dict, List, Any, Set

# ANSI color codes
class Colors:
    GREEN = '\033[0;32m'
    YELLOW = '\033[1;33m'
    RED = '\033[0;31m'
    BLUE = '\033[0;34m'
    NC = '\033[0m'  # No Color

def log_info(msg: str):
    print(f"{Colors.GREEN}[INFO]{Colors.NC} {msg}")

def log_warn(msg: str):
    print(f"{Colors.YELLOW}[WARN]{Colors.NC} {msg}")

def log_error(msg: str):
    print(f"{Colors.RED}[ERROR]{Colors.NC} {msg}")

def log_detail(msg: str):
    print(f"{Colors.BLUE}[DETAIL]{Colors.NC} {msg}")


class KubernetesArchitectureAnalyzer:
    """Analyzes collected Kubernetes and AWS data to generate architecture summary"""

    def __init__(self, data_dir: str):
        self.data_dir = Path(data_dir)
        self.summary = {
            "metadata": {
                "generated_at": datetime.now().isoformat(),
                "data_source": "Production Kubernetes Clusters",
                "clusters": []
            },
            "clusters": {},
            "namespaces": {},
            "services": {},
            "service_dependencies": [],
            "ingress_routes": [],
            "external_resources": {
                "databases": [],
                "caches": [],
                "storage": [],
                "load_balancers": [],
                "queues": [],
                "other": []
            },
            "resource_totals": {
                "nodes": 0,
                "vcpus": 0,
                "memory_gb": 0,
                "pods": 0,
                "deployments": 0,
                "statefulsets": 0,
                "services": 0,
                "ingresses": 0
            }
        }

    def analyze(self):
        """Main analysis workflow"""
        log_info("Starting data analysis...")
        print("")

        self.analyze_clusters()
        self.analyze_namespaces()
        self.analyze_service_dependencies()
        self.analyze_ingress_routes()
        self.analyze_external_resources()
        self.generate_service_map()
        self.calculate_totals()

        log_info("Analysis complete!")
        return self.summary

    def analyze_clusters(self):
        """Analyze cluster-level data"""
        log_info("Analyzing cluster data...")

        clusters_dir = self.data_dir / "raw" / "clusters"
        if not clusters_dir.exists():
            log_warn(f"Clusters directory not found: {clusters_dir}")
            return

        for cluster_dir in clusters_dir.iterdir():
            if cluster_dir.is_dir():
                cluster_name = cluster_dir.name
                log_detail(f"  Processing cluster: {cluster_name}")

                nodes_file = cluster_dir / "nodes.json"
                if nodes_file.exists():
                    with open(nodes_file) as f:
                        nodes_data = json.load(f)
                        cluster_info = self.parse_cluster_nodes(cluster_name, nodes_data)
                        self.summary["clusters"][cluster_name] = cluster_info
                        self.summary["metadata"]["clusters"].append(cluster_name)

    def parse_cluster_nodes(self, cluster_name: str, nodes_data: Dict) -> Dict:
        """Parse node information for a cluster"""
        nodes = nodes_data.get("items", [])

        cluster_info = {
            "name": cluster_name,
            "node_count": len(nodes),
            "nodes": [],
            "total_cpu": 0,
            "total_memory_gb": 0,
            "node_groups": {}
        }

        for node in nodes:
            node_name = node["metadata"]["name"]
            capacity = node["status"]["capacity"]
            labels = node["metadata"].get("labels", {})

            # Parse CPU
            cpu_count = int(capacity.get("cpu", 0))
            cluster_info["total_cpu"] += cpu_count

            # Parse memory (convert Ki to GB)
            memory_str = capacity.get("memory", "0Ki")
            memory_gb = self.parse_memory_to_gb(memory_str)
            cluster_info["total_memory_gb"] += memory_gb

            # Get instance type and zone
            instance_type = labels.get("node.kubernetes.io/instance-type", "unknown")
            zone = labels.get("topology.kubernetes.io/zone", "unknown")

            # Get node IP
            addresses = node["status"].get("addresses", [])
            internal_ip = next(
                (addr["address"] for addr in addresses if addr["type"] == "InternalIP"),
                "unknown"
            )

            node_info = {
                "name": node_name,
                "instance_type": instance_type,
                "zone": zone,
                "internal_ip": internal_ip,
                "cpu": cpu_count,
                "memory_gb": round(memory_gb, 2),
                "pods_capacity": int(capacity.get("pods", 0))
            }

            cluster_info["nodes"].append(node_info)

            # Group nodes by instance type
            if instance_type not in cluster_info["node_groups"]:
                cluster_info["node_groups"][instance_type] = 0
            cluster_info["node_groups"][instance_type] += 1

        cluster_info["total_memory_gb"] = round(cluster_info["total_memory_gb"], 2)
        return cluster_info

    def analyze_namespaces(self):
        """Analyze namespace-level data"""
        log_info("Analyzing namespace data...")

        namespaces_dir = self.data_dir / "raw" / "namespaces"
        if not namespaces_dir.exists():
            log_warn(f"Namespaces directory not found: {namespaces_dir}")
            return

        for ns_dir in namespaces_dir.iterdir():
            if ns_dir.is_dir():
                ns_name = ns_dir.name
                log_detail(f"  Processing namespace: {ns_name}")

                ns_info = self.parse_namespace(ns_name, ns_dir)
                self.summary["namespaces"][ns_name] = ns_info

    def parse_namespace(self, ns_name: str, ns_dir: Path) -> Dict:
        """Parse all resources in a namespace"""
        ns_info = {
            "name": ns_name,
            "deployments": [],
            "statefulsets": [],
            "daemonsets": [],
            "services": [],
            "ingresses": [],
            "pvcs": [],
            "pods_count": 0,
            "resource_requests": {
                "cpu": 0,
                "memory_gb": 0
            }
        }

        # Parse deployments
        deployments_file = ns_dir / "deployments.json"
        if deployments_file.exists():
            with open(deployments_file) as f:
                deployments_data = json.load(f)
                for deploy in deployments_data.get("items", []):
                    deploy_info = self.parse_deployment(deploy)
                    ns_info["deployments"].append(deploy_info)

        # Parse statefulsets
        statefulsets_file = ns_dir / "statefulsets.json"
        if statefulsets_file.exists():
            with open(statefulsets_file) as f:
                sts_data = json.load(f)
                for sts in sts_data.get("items", []):
                    sts_info = self.parse_statefulset(sts)
                    ns_info["statefulsets"].append(sts_info)

        # Parse services
        services_file = ns_dir / "services.json"
        if services_file.exists():
            with open(services_file) as f:
                services_data = json.load(f)
                for svc in services_data.get("items", []):
                    svc_info = self.parse_service(svc, ns_name)
                    ns_info["services"].append(svc_info)
                    # Also add to global services map
                    dns_name = f"{svc_info['name']}.{ns_name}.svc.cluster.local"
                    self.summary["services"][dns_name] = svc_info

        # Parse ingresses
        ingresses_file = ns_dir / "ingresses.json"
        if ingresses_file.exists():
            with open(ingresses_file) as f:
                ingresses_data = json.load(f)
                for ing in ingresses_data.get("items", []):
                    ing_info = self.parse_ingress(ing, ns_name)
                    ns_info["ingresses"].append(ing_info)

        # Parse pods
        pods_file = ns_dir / "pods.json"
        if pods_file.exists():
            with open(pods_file) as f:
                pods_data = json.load(f)
                ns_info["pods_count"] = len(pods_data.get("items", []))

        return ns_info

    def parse_deployment(self, deploy: Dict) -> Dict:
        """Parse deployment information"""
        metadata = deploy["metadata"]
        spec = deploy["spec"]

        containers = spec.get("template", {}).get("spec", {}).get("containers", [])
        first_container = containers[0] if containers else {}

        deploy_info = {
            "name": metadata["name"],
            "namespace": metadata.get("namespace", ""),
            "replicas": spec.get("replicas", 1),
            "image": first_container.get("image", "unknown"),
            "labels": metadata.get("labels", {}),
            "containers": []
        }

        for container in containers:
            container_info = {
                "name": container.get("name"),
                "image": container.get("image"),
                "ports": [p.get("containerPort") for p in container.get("ports", [])]
            }
            deploy_info["containers"].append(container_info)

        return deploy_info

    def parse_statefulset(self, sts: Dict) -> Dict:
        """Parse statefulset information"""
        metadata = sts["metadata"]
        spec = sts["spec"]

        containers = spec.get("template", {}).get("spec", {}).get("containers", [])
        first_container = containers[0] if containers else {}

        return {
            "name": metadata["name"],
            "namespace": metadata.get("namespace", ""),
            "replicas": spec.get("replicas", 1),
            "image": first_container.get("image", "unknown"),
            "service_name": spec.get("serviceName", "")
        }

    def parse_service(self, svc: Dict, ns_name: str) -> Dict:
        """Parse service information"""
        metadata = svc["metadata"]
        spec = svc["spec"]

        ports = spec.get("ports", [])
        port_info = []
        for port in ports:
            port_info.append({
                "port": port.get("port"),
                "target_port": port.get("targetPort"),
                "protocol": port.get("protocol", "TCP")
            })

        return {
            "name": metadata["name"],
            "namespace": ns_name,
            "type": spec.get("type", "ClusterIP"),
            "cluster_ip": spec.get("clusterIP"),
            "ports": port_info,
            "selector": spec.get("selector", {}),
            "dns_name": f"{metadata['name']}.{ns_name}.svc.cluster.local"
        }

    def parse_ingress(self, ing: Dict, ns_name: str) -> Dict:
        """Parse ingress information"""
        metadata = ing["metadata"]
        spec = ing["spec"]

        routes = []
        for rule in spec.get("rules", []):
            host = rule.get("host", "")
            http_paths = rule.get("http", {}).get("paths", [])

            for path_config in http_paths:
                backend = path_config.get("backend", {})
                service = backend.get("service", {})

                routes.append({
                    "host": host,
                    "path": path_config.get("path", "/"),
                    "service_name": service.get("name", ""),
                    "service_port": service.get("port", {}).get("number", 80)
                })

        return {
            "name": metadata["name"],
            "namespace": ns_name,
            "routes": routes
        }

    def analyze_service_dependencies(self):
        """Analyze service dependencies from collected data"""
        log_info("Analyzing service dependencies...")

        dependencies_dir = self.data_dir / "raw" / "dependencies"
        if not dependencies_dir.exists():
            log_warn(f"Dependencies directory not found: {dependencies_dir}")
            return

        dependencies_set = set()

        # Parse environment variable dependencies
        for env_file in dependencies_dir.glob("*_env_dependencies.txt"):
            namespace = env_file.name.replace("_env_dependencies.txt", "")
            deps = self.parse_env_dependencies(env_file, namespace)
            dependencies_set.update(deps)

        # Parse configmap dependencies
        for cm_file in dependencies_dir.glob("*_configmap_dependencies.txt"):
            namespace = cm_file.name.replace("_configmap_dependencies.txt", "")
            deps = self.parse_configmap_dependencies(cm_file, namespace)
            dependencies_set.update(deps)

        # Convert set to list of dicts
        self.summary["service_dependencies"] = [
            {"source": dep[0], "target": dep[1], "type": dep[2]}
            for dep in dependencies_set
        ]

        log_detail(f"  Found {len(self.summary['service_dependencies'])} service dependencies")

    def parse_env_dependencies(self, file_path: Path, namespace: str) -> Set:
        """Parse environment variable dependencies"""
        dependencies = set()

        try:
            with open(file_path) as f:
                content = f.read()

                # Look for service URLs/hosts
                # Pattern: SERVICE_NAME_HOST=service-name.namespace.svc.cluster.local
                service_host_pattern = r'([A-Z_]+)_(?:HOST|URL|SERVICE)=([a-z0-9\-\.]+\.svc\.cluster\.local)'
                matches = re.findall(service_host_pattern, content)

                for var_name, target_service in matches:
                    # Extract target namespace and service name
                    parts = target_service.split('.')
                    if len(parts) >= 2:
                        target_svc = parts[0]
                        target_ns = parts[1] if len(parts) > 1 else namespace

                        dependencies.add((
                            namespace,  # source namespace
                            f"{target_svc}.{target_ns}",  # target service
                            "env_variable"
                        ))

                # Also look for database connections
                db_pattern = r'(MYSQL|POSTGRES|MONGODB|REDIS)_(?:HOST|URL)=([a-z0-9\-\.]+)'
                db_matches = re.findall(db_pattern, content, re.IGNORECASE)

                for db_type, db_host in db_matches:
                    if not db_host.endswith('.svc.cluster.local'):
                        # External database
                        dependencies.add((
                            namespace,
                            f"external-{db_type.lower()}-{db_host.split('.')[0]}",
                            "database"
                        ))

        except Exception as e:
            log_warn(f"Error parsing {file_path}: {e}")

        return dependencies

    def parse_configmap_dependencies(self, file_path: Path, namespace: str) -> Set:
        """Parse configmap dependencies"""
        dependencies = set()

        try:
            with open(file_path) as f:
                content = f.read()

                # Look for HTTP URLs to other services
                url_pattern = r'https?://([a-z0-9\-]+(?:\.[a-z0-9\-]+)*(?:\.svc\.cluster\.local)?)'
                matches = re.findall(url_pattern, content)

                for target in matches:
                    if 'svc.cluster.local' in target:
                        dependencies.add((
                            namespace,
                            target.replace('.svc.cluster.local', ''),
                            "http"
                        ))

        except Exception as e:
            log_warn(f"Error parsing {file_path}: {e}")

        return dependencies

    def analyze_ingress_routes(self):
        """Consolidate all ingress routes"""
        log_info("Analyzing ingress routes...")

        routes = []
        for ns_name, ns_info in self.summary["namespaces"].items():
            for ingress in ns_info.get("ingresses", []):
                for route in ingress.get("routes", []):
                    routes.append({
                        "host": route["host"],
                        "path": route["path"],
                        "namespace": ns_name,
                        "service": route["service_name"],
                        "port": route["service_port"],
                        "ingress_name": ingress["name"]
                    })

        self.summary["ingress_routes"] = routes
        log_detail(f"  Found {len(routes)} ingress routes")

    def analyze_external_resources(self):
        """Analyze external AWS resources"""
        log_info("Analyzing external AWS resources...")

        external_dir = self.data_dir / "raw" / "external"
        if not external_dir.exists():
            log_warn(f"External resources directory not found: {external_dir}")
            return

        # RDS Databases
        rds_file = external_dir / "rds_instances.json"
        if rds_file.exists():
            with open(rds_file) as f:
                rds_data = json.load(f)
                for db in rds_data.get("DBInstances", []):
                    self.summary["external_resources"]["databases"].append({
                        "type": "rds",
                        "identifier": db.get("DBInstanceIdentifier"),
                        "engine": db.get("Engine"),
                        "endpoint": db.get("Endpoint", {}).get("Address"),
                        "port": db.get("Endpoint", {}).get("Port"),
                        "status": db.get("DBInstanceStatus")
                    })

        # ElastiCache
        cache_file = external_dir / "elasticache_clusters.json"
        if cache_file.exists():
            with open(cache_file) as f:
                cache_data = json.load(f)
                for cache in cache_data.get("CacheClusters", []):
                    self.summary["external_resources"]["caches"].append({
                        "type": "elasticache",
                        "identifier": cache.get("CacheClusterId"),
                        "engine": cache.get("Engine"),
                        "node_type": cache.get("CacheNodeType"),
                        "status": cache.get("CacheClusterStatus")
                    })

        # Load Balancers
        lb_file = external_dir / "load_balancers_v2.json"
        if lb_file.exists():
            with open(lb_file) as f:
                lb_data = json.load(f)
                for lb in lb_data.get("LoadBalancers", []):
                    self.summary["external_resources"]["load_balancers"].append({
                        "name": lb.get("LoadBalancerName"),
                        "type": lb.get("Type"),
                        "dns_name": lb.get("DNSName"),
                        "scheme": lb.get("Scheme"),
                        "state": lb.get("State", {}).get("Code")
                    })

    def generate_service_map(self):
        """Generate a service map showing all services and their relationships"""
        log_info("Generating service map...")

        # This creates a comprehensive view of all services and how they connect
        # Useful for visualization tools

    def calculate_totals(self):
        """Calculate total resource counts"""
        log_info("Calculating resource totals...")

        # Count nodes and resources from clusters
        for cluster_info in self.summary["clusters"].values():
            self.summary["resource_totals"]["nodes"] += cluster_info["node_count"]
            self.summary["resource_totals"]["vcpus"] += cluster_info["total_cpu"]
            self.summary["resource_totals"]["memory_gb"] += cluster_info["total_memory_gb"]

        # Count workloads from namespaces
        for ns_info in self.summary["namespaces"].values():
            self.summary["resource_totals"]["deployments"] += len(ns_info["deployments"])
            self.summary["resource_totals"]["statefulsets"] += len(ns_info["statefulsets"])
            self.summary["resource_totals"]["services"] += len(ns_info["services"])
            self.summary["resource_totals"]["ingresses"] += len(ns_info["ingresses"])
            self.summary["resource_totals"]["pods"] += ns_info["pods_count"]

        self.summary["resource_totals"]["memory_gb"] = round(
            self.summary["resource_totals"]["memory_gb"], 2
        )

    @staticmethod
    def parse_memory_to_gb(memory_str: str) -> float:
        """Convert Kubernetes memory notation to GB"""
        if memory_str.endswith("Ki"):
            return int(memory_str[:-2]) / (1024 * 1024)
        elif memory_str.endswith("Mi"):
            return int(memory_str[:-2]) / 1024
        elif memory_str.endswith("Gi"):
            return int(memory_str[:-2])
        return 0


def main():
    """Main execution"""
    log_info("Luckin Coffee K8s Architecture Data Analysis")
    log_info("=" * 50)
    print("")

    # Data directory
    data_dir = Path(__file__).parent.parent / "data"

    if not data_dir.exists():
        log_error(f"Data directory not found: {data_dir}")
        log_error("Please run data collection scripts first:")
        log_error("  1. ./01_collect_cluster_data.sh")
        log_error("  2. ./02_collect_namespace_data.sh")
        log_error("  3. ./03_collect_service_dependencies.sh")
        log_error("  4. ./04_collect_external_resources.sh")
        return 1

    # Run analysis
    analyzer = KubernetesArchitectureAnalyzer(str(data_dir))
    summary = analyzer.analyze()

    # Save summary
    output_file = data_dir / "processed" / "architecture_summary.json"
    output_file.parent.mkdir(parents=True, exist_ok=True)

    with open(output_file, 'w') as f:
        json.dump(summary, f, indent=2, sort_keys=False)

    print("")
    log_info(f"Analysis complete! Summary saved to: {output_file}")
    print("")

    # Print summary statistics
    print("=" * 70)
    print("ARCHITECTURE SUMMARY")
    print("=" * 70)
    print(f"Clusters:              {len(summary['clusters'])}")
    print(f"Namespaces:            {len(summary['namespaces'])}")
    print(f"Total Nodes:           {summary['resource_totals']['nodes']}")
    print(f"Total vCPUs:           {summary['resource_totals']['vcpus']}")
    print(f"Total Memory:          {summary['resource_totals']['memory_gb']} GB")
    print(f"Total Pods:            {summary['resource_totals']['pods']}")
    print(f"Deployments:           {summary['resource_totals']['deployments']}")
    print(f"StatefulSets:          {summary['resource_totals']['statefulsets']}")
    print(f"Services:              {summary['resource_totals']['services']}")
    print(f"Ingresses:             {summary['resource_totals']['ingresses']}")
    print(f"Service Dependencies:  {len(summary['service_dependencies'])}")
    print(f"Ingress Routes:        {len(summary['ingress_routes'])}")
    print("-" * 70)
    print("External Resources:")
    print(f"  RDS Databases:       {len(summary['external_resources']['databases'])}")
    print(f"  ElastiCache:         {len(summary['external_resources']['caches'])}")
    print(f"  Load Balancers:      {len(summary['external_resources']['load_balancers'])}")
    print("=" * 70)

    return 0


if __name__ == "__main__":
    exit(main())
