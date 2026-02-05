#!/usr/bin/env python3
"""
RDS Graviton Migration Analysis Script
Analyzes x86 instances and recommends Graviton migration with cost savings
"""

import json
import csv
from datetime import datetime

# RDS instance data from AWS
instances = [
    {"InstanceId": "aws-luckyus-cdpactivity-rw", "Engine": "mysql", "EngineVersion": "8.0.40", "InstanceClass": "db.t4g.medium", "MultiAZ": True},
    {"InstanceId": "aws-luckyus-dbatest-rw", "Engine": "mysql", "EngineVersion": "8.0.42", "InstanceClass": "db.t4g.micro", "MultiAZ": True},
    {"InstanceId": "aws-luckyus-devops-rw", "Engine": "mysql", "EngineVersion": "8.0.40", "InstanceClass": "db.t4g.medium", "MultiAZ": True},
    {"InstanceId": "aws-luckyus-difynew-rw", "Engine": "postgres", "EngineVersion": "16.10", "InstanceClass": "db.r5.xlarge", "MultiAZ": True},
    {"InstanceId": "aws-luckyus-dify-rw", "Engine": "postgres", "EngineVersion": "16.8", "InstanceClass": "db.r5.xlarge", "MultiAZ": True},
    {"InstanceId": "aws-luckyus-fichargecontrol-rw", "Engine": "mysql", "EngineVersion": "8.0.40", "InstanceClass": "db.t4g.micro", "MultiAZ": True},
    {"InstanceId": "aws-luckyus-fitax-rw", "Engine": "mysql", "EngineVersion": "8.0.40", "InstanceClass": "db.t4g.micro", "MultiAZ": True},
    {"InstanceId": "aws-luckyus-framework01-rw", "Engine": "mysql", "EngineVersion": "8.0.40", "InstanceClass": "db.t4g.medium", "MultiAZ": True},
    {"InstanceId": "aws-luckyus-framework02-rw", "Engine": "mysql", "EngineVersion": "8.0.40", "InstanceClass": "db.t4g.medium", "MultiAZ": True},
    {"InstanceId": "aws-luckyus-iadmin-rw", "Engine": "mysql", "EngineVersion": "8.0.40", "InstanceClass": "db.t4g.micro", "MultiAZ": True},
    {"InstanceId": "aws-luckyus-ibillingcentersrv-rw", "Engine": "mysql", "EngineVersion": "8.0.40", "InstanceClass": "db.t4g.micro", "MultiAZ": True},
    {"InstanceId": "aws-luckyus-ibizconfigcenter-rw", "Engine": "mysql", "EngineVersion": "8.0.40", "InstanceClass": "db.t4g.micro", "MultiAZ": True},
    {"InstanceId": "aws-luckyus-icyberdata-rw", "Engine": "mysql", "EngineVersion": "8.0.40", "InstanceClass": "db.t4g.medium", "MultiAZ": True},
    {"InstanceId": "aws-luckyus-iehr-rw", "Engine": "mysql", "EngineVersion": "8.0.40", "InstanceClass": "db.t4g.micro", "MultiAZ": True},
    {"InstanceId": "aws-luckyus-ifiaccounting-rw", "Engine": "mysql", "EngineVersion": "8.0.40", "InstanceClass": "db.t4g.micro", "MultiAZ": True},
    {"InstanceId": "aws-luckyus-igers-rw", "Engine": "mysql", "EngineVersion": "8.0.40", "InstanceClass": "db.t4g.micro", "MultiAZ": True},
    {"InstanceId": "aws-luckyus-ijumpserver-jumpserver-rw", "Engine": "mysql", "EngineVersion": "8.0.40", "InstanceClass": "db.t4g.micro", "MultiAZ": True},
    {"InstanceId": "aws-luckyus-ilsopdevopsdata-rw", "Engine": "mysql", "EngineVersion": "8.0.40", "InstanceClass": "db.t4g.micro", "MultiAZ": True},
    {"InstanceId": "aws-luckyus-iluckyams-rw", "Engine": "mysql", "EngineVersion": "8.0.42", "InstanceClass": "db.t4g.micro", "MultiAZ": True},
    {"InstanceId": "aws-luckyus-iluckyauthapi-rw", "Engine": "mysql", "EngineVersion": "8.0.40", "InstanceClass": "db.t4g.micro", "MultiAZ": True},
    {"InstanceId": "aws-luckyus-iluckydorisops-rw", "Engine": "mysql", "EngineVersion": "8.0.40", "InstanceClass": "db.t4g.micro", "MultiAZ": True},
    {"InstanceId": "aws-luckyus-iluckyhealth-rw", "Engine": "mysql", "EngineVersion": "8.0.40", "InstanceClass": "db.t3.small", "MultiAZ": True},
    {"InstanceId": "aws-luckyus-iluckymedia-rw", "Engine": "mysql", "EngineVersion": "8.0.40", "InstanceClass": "db.t4g.micro", "MultiAZ": True},
    {"InstanceId": "aws-luckyus-iopenadmin-rw", "Engine": "mysql", "EngineVersion": "8.0.40", "InstanceClass": "db.t4g.micro", "MultiAZ": True},
    {"InstanceId": "aws-luckyus-iopenlinker-rw", "Engine": "mysql", "EngineVersion": "8.0.40", "InstanceClass": "db.t4g.micro", "MultiAZ": True},
    {"InstanceId": "aws-luckyus-iopenservice-rw", "Engine": "mysql", "EngineVersion": "8.0.40", "InstanceClass": "db.t4g.micro", "MultiAZ": True},
    {"InstanceId": "aws-luckyus-iopocp-rw", "Engine": "mysql", "EngineVersion": "8.0.40", "InstanceClass": "db.t4g.micro", "MultiAZ": True},
    {"InstanceId": "aws-luckyus-iopshopexpand-rw", "Engine": "mysql", "EngineVersion": "8.0.40", "InstanceClass": "db.t4g.micro", "MultiAZ": True},
    {"InstanceId": "aws-luckyus-iotplatform-rw", "Engine": "mysql", "EngineVersion": "8.0.40", "InstanceClass": "db.t4g.medium", "MultiAZ": True},
    {"InstanceId": "aws-luckyus-ipermission-rw", "Engine": "mysql", "EngineVersion": "8.0.40", "InstanceClass": "db.t4g.micro", "MultiAZ": True},
    {"InstanceId": "aws-luckyus-ireplenishment-rw", "Engine": "mysql", "EngineVersion": "8.0.40", "InstanceClass": "db.t4g.micro", "MultiAZ": True},
    {"InstanceId": "aws-luckyus-iriskcontrolservice-rw", "Engine": "mysql", "EngineVersion": "8.0.40", "InstanceClass": "db.t4g.micro", "MultiAZ": True},
    {"InstanceId": "aws-luckyus-isalescdp-rw", "Engine": "mysql", "EngineVersion": "8.0.40", "InstanceClass": "db.t4g.micro", "MultiAZ": True},
    {"InstanceId": "aws-luckyus-isalesdatamarketing-rw", "Engine": "mysql", "EngineVersion": "8.0.40", "InstanceClass": "db.t4g.medium", "MultiAZ": True},
    {"InstanceId": "aws-luckyus-isalesmembermarketing-rw", "Engine": "mysql", "EngineVersion": "8.0.40", "InstanceClass": "db.t4g.micro", "MultiAZ": True},
    {"InstanceId": "aws-luckyus-isalesprivatedomain-rw", "Engine": "mysql", "EngineVersion": "8.0.40", "InstanceClass": "db.t4g.medium", "MultiAZ": True},
    {"InstanceId": "aws-luckyus-iunifiedreconcile-rw", "Engine": "mysql", "EngineVersion": "8.0.40", "InstanceClass": "db.t4g.micro", "MultiAZ": True},
    {"InstanceId": "aws-luckyus-iworkflowmidlayer-rw", "Engine": "mysql", "EngineVersion": "8.0.40", "InstanceClass": "db.t4g.medium", "MultiAZ": True},
    {"InstanceId": "aws-luckyus-ldas01-rw", "Engine": "mysql", "EngineVersion": "8.0.41", "InstanceClass": "db.t4g.large", "MultiAZ": True},
    {"InstanceId": "aws-luckyus-ldas-rw", "Engine": "mysql", "EngineVersion": "8.0.40", "InstanceClass": "db.t4g.large", "MultiAZ": True},
    {"InstanceId": "aws-luckyus-mfranchise-rw", "Engine": "mysql", "EngineVersion": "8.0.40", "InstanceClass": "db.t4g.micro", "MultiAZ": True},
    {"InstanceId": "aws-luckyus-opempefficiency-rw", "Engine": "mysql", "EngineVersion": "8.0.40", "InstanceClass": "db.t4g.micro", "MultiAZ": True},
    {"InstanceId": "aws-luckyus-oplog-rw", "Engine": "mysql", "EngineVersion": "8.0.40", "InstanceClass": "db.t4g.micro", "MultiAZ": True},
    {"InstanceId": "aws-luckyus-opproduction-rw", "Engine": "mysql", "EngineVersion": "8.0.40", "InstanceClass": "db.t4g.micro", "MultiAZ": True},
    {"InstanceId": "aws-luckyus-opqualitycontrol-rw", "Engine": "mysql", "EngineVersion": "8.0.40", "InstanceClass": "db.t4g.micro", "MultiAZ": True},
    {"InstanceId": "aws-luckyus-opshop-rw", "Engine": "mysql", "EngineVersion": "8.0.40", "InstanceClass": "db.t4g.medium", "MultiAZ": True},
    {"InstanceId": "aws-luckyus-opshopsale-rw", "Engine": "mysql", "EngineVersion": "8.0.40", "InstanceClass": "db.t4g.micro", "MultiAZ": True},
    {"InstanceId": "aws-luckyus-pgilkmap-rw", "Engine": "postgres", "EngineVersion": "17.4", "InstanceClass": "db.m5.large", "MultiAZ": True},
    {"InstanceId": "aws-luckyus-pubdm-rw", "Engine": "mysql", "EngineVersion": "8.0.40", "InstanceClass": "db.t4g.micro", "MultiAZ": True},
    {"InstanceId": "aws-luckyus-salescrm-rw", "Engine": "mysql", "EngineVersion": "8.0.40", "InstanceClass": "db.t4g.medium", "MultiAZ": True},
    {"InstanceId": "aws-luckyus-salesmarketing-rw", "Engine": "mysql", "EngineVersion": "8.0.40", "InstanceClass": "db.t4g.xlarge", "MultiAZ": True},
    {"InstanceId": "aws-luckyus-salesorder-rw", "Engine": "mysql", "EngineVersion": "8.0.40", "InstanceClass": "db.t4g.medium", "MultiAZ": True},
    {"InstanceId": "aws-luckyus-salespayment-rw", "Engine": "mysql", "EngineVersion": "8.0.40", "InstanceClass": "db.t4g.medium", "MultiAZ": True},
    {"InstanceId": "aws-luckyus-scm-asset-rw", "Engine": "mysql", "EngineVersion": "8.0.40", "InstanceClass": "db.t4g.micro", "MultiAZ": True},
    {"InstanceId": "aws-luckyus-scmcommodity-rw", "Engine": "mysql", "EngineVersion": "8.0.40", "InstanceClass": "db.t4g.medium", "MultiAZ": True},
    {"InstanceId": "aws-luckyus-scm-openapi-rw", "Engine": "mysql", "EngineVersion": "8.0.40", "InstanceClass": "db.t4g.micro", "MultiAZ": True},
    {"InstanceId": "aws-luckyus-scm-ordering-rw", "Engine": "mysql", "EngineVersion": "8.0.40", "InstanceClass": "db.t4g.micro", "MultiAZ": True},
    {"InstanceId": "aws-luckyus-scm-plan-rw", "Engine": "mysql", "EngineVersion": "8.0.40", "InstanceClass": "db.t4g.micro", "MultiAZ": True},
    {"InstanceId": "aws-luckyus-scm-purchase-rw", "Engine": "mysql", "EngineVersion": "8.0.40", "InstanceClass": "db.t4g.micro", "MultiAZ": True},
    {"InstanceId": "aws-luckyus-scm-shopstock-rw", "Engine": "mysql", "EngineVersion": "8.0.40", "InstanceClass": "db.t4g.medium", "MultiAZ": True},
    {"InstanceId": "aws-luckyus-scmsrm-rw", "Engine": "mysql", "EngineVersion": "8.0.40", "InstanceClass": "db.t4g.micro", "MultiAZ": True},
    {"InstanceId": "aws-luckyus-scm-wds-rw", "Engine": "mysql", "EngineVersion": "8.0.40", "InstanceClass": "db.t4g.micro", "MultiAZ": True},
    {"InstanceId": "aws-luckyus-scm-wmssimulate-rw", "Engine": "mysql", "EngineVersion": "8.0.40", "InstanceClass": "db.t4g.micro", "MultiAZ": True},
    {"InstanceId": "aws-luckyus-upush-rw", "Engine": "mysql", "EngineVersion": "8.0.40", "InstanceClass": "db.t4g.medium", "MultiAZ": True},
    {"InstanceId": "docdb-devops", "Engine": "docdb", "EngineVersion": "5.0.0", "InstanceClass": "db.t3.medium", "MultiAZ": False},
    {"InstanceId": "docdb-devops2", "Engine": "docdb", "EngineVersion": "5.0.0", "InstanceClass": "db.t3.medium", "MultiAZ": False},
    {"InstanceId": "docdb-devops3", "Engine": "docdb", "EngineVersion": "5.0.0", "InstanceClass": "db.t3.medium", "MultiAZ": False},
    {"InstanceId": "docdb-gia", "Engine": "docdb", "EngineVersion": "5.0.0", "InstanceClass": "db.r6g.large", "MultiAZ": False},
    {"InstanceId": "docdb-gia2", "Engine": "docdb", "EngineVersion": "5.0.0", "InstanceClass": "db.t4g.medium", "MultiAZ": False},
    {"InstanceId": "docdb-gia3", "Engine": "docdb", "EngineVersion": "5.0.0", "InstanceClass": "db.r6g.large", "MultiAZ": False},
    {"InstanceId": "docdb-iot", "Engine": "docdb", "EngineVersion": "5.0.0", "InstanceClass": "db.t3.medium", "MultiAZ": False},
    {"InstanceId": "docdb-iot2", "Engine": "docdb", "EngineVersion": "5.0.0", "InstanceClass": "db.t3.medium", "MultiAZ": False},
    {"InstanceId": "docdb-iot3", "Engine": "docdb", "EngineVersion": "5.0.0", "InstanceClass": "db.t3.medium", "MultiAZ": False},
    {"InstanceId": "recovery-dbatest", "Engine": "mysql", "EngineVersion": "8.0.40", "InstanceClass": "db.t3.small", "MultiAZ": True},
]

# x86 to Graviton mapping
x86_to_graviton = {
    "db.t3.micro": "db.t4g.micro",
    "db.t3.small": "db.t4g.small",
    "db.t3.medium": "db.t4g.medium",
    "db.t3.large": "db.t4g.large",
    "db.t3.xlarge": "db.t4g.xlarge",
    "db.t3.2xlarge": "db.t4g.2xlarge",
    "db.m5.large": "db.m6g.large",
    "db.m5.xlarge": "db.m6g.xlarge",
    "db.m5.2xlarge": "db.m6g.2xlarge",
    "db.m5.4xlarge": "db.m6g.4xlarge",
    "db.m6i.large": "db.m6g.large",
    "db.m6i.xlarge": "db.m6g.xlarge",
    "db.r5.large": "db.r6g.large",
    "db.r5.xlarge": "db.r6g.xlarge",
    "db.r5.2xlarge": "db.r6g.2xlarge",
    "db.r5.4xlarge": "db.r6g.4xlarge",
    "db.r6i.large": "db.r6g.large",
    "db.r6i.xlarge": "db.r6g.xlarge",
}

# AWS On-Demand pricing for RDS us-east-1 (hourly rates)
# Source: AWS RDS pricing page for MySQL/PostgreSQL in us-east-1
x86_hourly_pricing = {
    "db.t3.micro": 0.017,
    "db.t3.small": 0.034,
    "db.t3.medium": 0.068,
    "db.t3.large": 0.136,
    "db.t3.xlarge": 0.272,
    "db.t3.2xlarge": 0.544,
    "db.m5.large": 0.171,
    "db.m5.xlarge": 0.342,
    "db.m5.2xlarge": 0.684,
    "db.m5.4xlarge": 1.368,
    "db.m6i.large": 0.178,
    "db.m6i.xlarge": 0.356,
    "db.r5.large": 0.24,
    "db.r5.xlarge": 0.48,
    "db.r5.2xlarge": 0.96,
    "db.r5.4xlarge": 1.92,
    "db.r6i.large": 0.252,
    "db.r6i.xlarge": 0.504,
}

graviton_hourly_pricing = {
    "db.t4g.micro": 0.016,
    "db.t4g.small": 0.032,
    "db.t4g.medium": 0.065,
    "db.t4g.large": 0.129,
    "db.t4g.xlarge": 0.258,
    "db.t4g.2xlarge": 0.516,
    "db.m6g.large": 0.154,
    "db.m6g.xlarge": 0.307,
    "db.m6g.2xlarge": 0.614,
    "db.m6g.4xlarge": 1.228,
    "db.r6g.large": 0.228,
    "db.r6g.xlarge": 0.456,
    "db.r6g.2xlarge": 0.912,
    "db.r6g.4xlarge": 1.824,
}

# EDP discount
EDP_DISCOUNT = 0.31

# Check if instance class is x86 (not Graviton)
def is_x86_instance(instance_class):
    graviton_markers = ['g.', '4g.', '6g.', '7g.']
    return not any(marker in instance_class for marker in graviton_markers)

# Get Graviton equivalent
def get_graviton_equivalent(instance_class):
    return x86_to_graviton.get(instance_class, "N/A")

# Check engine version compatibility
def is_graviton_compatible(engine, version):
    if engine == "mysql":
        major_version = float(version.split('.')[0] + '.' + version.split('.')[1])
        return major_version >= 8.0
    elif engine == "postgres":
        major_version = int(version.split('.')[0])
        return major_version >= 13
    elif engine == "docdb":
        major_version = float(version.split('.')[0])
        return major_version >= 4.0
    return False

# Calculate monthly cost
def calculate_monthly_cost(instance_class, multi_az, is_graviton=False, engine="mysql"):
    pricing = graviton_hourly_pricing if is_graviton else x86_hourly_pricing
    hourly_rate = pricing.get(instance_class, 0)

    # Multi-AZ doubles the cost
    if multi_az:
        hourly_rate *= 2

    # Monthly hours (730)
    monthly_cost = hourly_rate * 730

    # Apply EDP discount
    monthly_cost *= (1 - EDP_DISCOUNT)

    return round(monthly_cost, 2)

# Determine migration risk
def get_migration_risk(multi_az, is_replica=False):
    if is_replica:
        return "LOW"
    elif multi_az:
        return "MEDIUM"
    else:
        return "MEDIUM"

# Determine migration method
def get_migration_method(multi_az, is_replica=False):
    if is_replica:
        return "Test on replica, then modify"
    elif multi_az:
        return "Modify with failover"
    else:
        return "Modify with scheduled downtime"

def main():
    # Analyze instances
    x86_candidates = []
    already_graviton = []

    for inst in instances:
        instance_class = inst["InstanceClass"]

        if is_x86_instance(instance_class):
            graviton_class = get_graviton_equivalent(instance_class)
            compatible = is_graviton_compatible(inst["Engine"], inst["EngineVersion"])

            current_cost = calculate_monthly_cost(instance_class, inst["MultiAZ"], is_graviton=False)

            if graviton_class != "N/A" and compatible:
                projected_cost = calculate_monthly_cost(graviton_class, inst["MultiAZ"], is_graviton=True)
                monthly_savings = current_cost - projected_cost
            else:
                projected_cost = current_cost
                monthly_savings = 0
                graviton_class = "N/A - Mapping not available" if graviton_class == "N/A" else graviton_class

            x86_candidates.append({
                "instance_id": inst["InstanceId"],
                "engine": inst["Engine"],
                "version": inst["EngineVersion"],
                "current_class": instance_class,
                "graviton_class": graviton_class,
                "current_monthly_cost": current_cost,
                "projected_cost": projected_cost,
                "monthly_savings": monthly_savings,
                "migration_risk": get_migration_risk(inst["MultiAZ"]),
                "migration_method": get_migration_method(inst["MultiAZ"]),
                "compatible": compatible,
                "multi_az": inst["MultiAZ"]
            })
        else:
            already_graviton.append(inst)

    # Write CSV for migration candidates
    csv_file = "/app/rds_graviton_migration_candidates.csv"
    with open(csv_file, 'w', newline='') as f:
        writer = csv.writer(f)
        writer.writerow([
            "instance_id", "engine", "version", "current_class", "graviton_class",
            "current_monthly_cost", "projected_cost", "monthly_savings",
            "migration_risk", "migration_method"
        ])

        for inst in sorted(x86_candidates, key=lambda x: -x["monthly_savings"]):
            writer.writerow([
                inst["instance_id"],
                inst["engine"],
                inst["version"],
                inst["current_class"],
                inst["graviton_class"],
                f"${inst['current_monthly_cost']:.2f}",
                f"${inst['projected_cost']:.2f}",
                f"${inst['monthly_savings']:.2f}",
                inst["migration_risk"],
                inst["migration_method"]
            ])

    # Print summary report
    print("=" * 100)
    print("RDS GRAVITON MIGRATION ANALYSIS REPORT")
    print("=" * 100)
    print(f"Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print(f"EDP Discount Applied: {EDP_DISCOUNT*100}%")
    print()

    print("SUMMARY STATISTICS")
    print("-" * 50)
    print(f"Total RDS/DocDB Instances: {len(instances)}")
    print(f"Already on Graviton: {len(already_graviton)}")
    print(f"x86 Migration Candidates: {len(x86_candidates)}")
    print()

    total_current = sum(i["current_monthly_cost"] for i in x86_candidates)
    total_projected = sum(i["projected_cost"] for i in x86_candidates)
    total_savings = sum(i["monthly_savings"] for i in x86_candidates)

    print("COST IMPACT (x86 Candidates Only)")
    print("-" * 50)
    print(f"Current Monthly Cost:    ${total_current:.2f}")
    print(f"Projected Monthly Cost:  ${total_projected:.2f}")
    print(f"Monthly Savings:         ${total_savings:.2f}")
    print(f"Annual Savings:          ${total_savings * 12:.2f}")
    print()

    print("MIGRATION CANDIDATES BY INSTANCE CLASS")
    print("-" * 50)
    class_summary = {}
    for inst in x86_candidates:
        key = f"{inst['current_class']} -> {inst['graviton_class']}"
        if key not in class_summary:
            class_summary[key] = {"count": 0, "savings": 0}
        class_summary[key]["count"] += 1
        class_summary[key]["savings"] += inst["monthly_savings"]

    for key, val in sorted(class_summary.items(), key=lambda x: -x[1]["savings"]):
        print(f"{key}: {val['count']} instances, ${val['savings']:.2f}/month savings")
    print()

    print("DETAILED MIGRATION CANDIDATES (sorted by savings)")
    print("-" * 100)
    print(f"{'Instance ID':<45} {'Engine':<10} {'Current':<15} {'Graviton':<15} {'Savings/mo':<12} {'Risk'}")
    print("-" * 100)

    for inst in sorted(x86_candidates, key=lambda x: -x["monthly_savings"]):
        print(f"{inst['instance_id']:<45} {inst['engine']:<10} {inst['current_class']:<15} {inst['graviton_class']:<15} ${inst['monthly_savings']:<11.2f} {inst['migration_risk']}")

    print()
    print("ALREADY ON GRAVITON (No Action Needed)")
    print("-" * 100)
    graviton_by_class = {}
    for inst in already_graviton:
        cls = inst["InstanceClass"]
        if cls not in graviton_by_class:
            graviton_by_class[cls] = 0
        graviton_by_class[cls] += 1

    for cls, count in sorted(graviton_by_class.items()):
        print(f"  {cls}: {count} instances")

    print()
    print(f"CSV file written to: {csv_file}")
    print()

    return x86_candidates, already_graviton

if __name__ == "__main__":
    main()
