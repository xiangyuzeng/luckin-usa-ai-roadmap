#!/bin/bash
#
# Luckin Coffee K8s Data Collection - Phase 4: External Resources
# Discovers AWS resources (RDS, ElastiCache, S3, etc.) that services depend on
#
# Usage: ./04_collect_external_resources.sh
#

set -euo pipefail

# Configuration
REGION="us-east-1"
OUTPUT_DIR="../data/raw/external"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_detail() { echo -e "${BLUE}[DETAIL]${NC} $1"; }

mkdir -p "$OUTPUT_DIR"

log_info "Starting external resources discovery at $TIMESTAMP"
log_info "Region: $REGION"
echo ""

#==============================================================================
# Verify AWS Access
#==============================================================================
verify_aws_access() {
    log_info "Verifying AWS credentials..."

    if ! aws sts get-caller-identity > "$OUTPUT_DIR/aws_identity.json" 2>&1; then
        log_error "AWS credentials not configured or insufficient permissions"
        log_error "Please configure AWS CLI with appropriate credentials"
        exit 1
    fi

    local account_id=$(cat "$OUTPUT_DIR/aws_identity.json" | jq -r '.Account')
    local user_arn=$(cat "$OUTPUT_DIR/aws_identity.json" | jq -r '.Arn')

    log_info "AWS Account: $account_id"
    log_info "User/Role: $user_arn"
    echo ""
}

#==============================================================================
# RDS Databases
#==============================================================================
discover_rds() {
    log_info "Discovering RDS database instances..."

    # Get all RDS instances
    aws rds describe-db-instances \
        --region "$REGION" \
        --output json \
        > "$OUTPUT_DIR/rds_instances.json" 2>&1 || {
        log_warn "Failed to retrieve RDS instances (may lack permissions)"
        echo '{"DBInstances":[]}' > "$OUTPUT_DIR/rds_instances.json"
        return
    }

    # Create human-readable summary
    local output_file="$OUTPUT_DIR/rds_instances.txt"
    echo "=== RDS Database Instances ===" > "$output_file"
    echo "Timestamp: $TIMESTAMP" >> "$output_file"
    echo "" >> "$output_file"

    aws rds describe-db-instances \
        --region "$REGION" \
        --query 'DBInstances[*].[DBInstanceIdentifier,DBInstanceClass,Engine,EngineVersion,Endpoint.Address,Endpoint.Port,DBInstanceStatus,MultiAZ,StorageType,AllocatedStorage]' \
        --output table >> "$output_file" 2>&1 || true

    local count=$(cat "$OUTPUT_DIR/rds_instances.json" | jq '.DBInstances | length')
    log_info "  Found $count RDS instances"

    # Get RDS cluster information (Aurora)
    aws rds describe-db-clusters \
        --region "$REGION" \
        --output json \
        > "$OUTPUT_DIR/rds_clusters.json" 2>&1 || {
        echo '{"DBClusters":[]}' > "$OUTPUT_DIR/rds_clusters.json"
    }

    local cluster_count=$(cat "$OUTPUT_DIR/rds_clusters.json" | jq '.DBClusters | length')
    if [ "$cluster_count" -gt 0 ]; then
        log_info "  Found $cluster_count Aurora clusters"
    fi
}

#==============================================================================
# ElastiCache (Redis/Memcached)
#==============================================================================
discover_elasticache() {
    log_info "Discovering ElastiCache clusters..."

    # Get Redis clusters
    aws elasticache describe-cache-clusters \
        --region "$REGION" \
        --show-cache-node-info \
        --output json \
        > "$OUTPUT_DIR/elasticache_clusters.json" 2>&1 || {
        log_warn "Failed to retrieve ElastiCache clusters (may lack permissions)"
        echo '{"CacheClusters":[]}' > "$OUTPUT_DIR/elasticache_clusters.json"
        return
    }

    # Create human-readable summary
    local output_file="$OUTPUT_DIR/elasticache_clusters.txt"
    echo "=== ElastiCache Clusters ===" > "$output_file"
    echo "Timestamp: $TIMESTAMP" >> "$output_file"
    echo "" >> "$output_file"

    aws elasticache describe-cache-clusters \
        --region "$REGION" \
        --query 'CacheClusters[*].[CacheClusterId,Engine,EngineVersion,CacheNodeType,NumCacheNodes,CacheClusterStatus]' \
        --output table >> "$output_file" 2>&1 || true

    local count=$(cat "$OUTPUT_DIR/elasticache_clusters.json" | jq '.CacheClusters | length')
    log_info "  Found $count ElastiCache clusters"

    # Get replication groups (Redis clusters with replication)
    aws elasticache describe-replication-groups \
        --region "$REGION" \
        --output json \
        > "$OUTPUT_DIR/elasticache_replication_groups.json" 2>&1 || {
        echo '{"ReplicationGroups":[]}' > "$OUTPUT_DIR/elasticache_replication_groups.json"
    }
}

#==============================================================================
# S3 Buckets
#==============================================================================
discover_s3() {
    log_info "Discovering S3 buckets..."

    # List all buckets
    aws s3api list-buckets \
        --output json \
        > "$OUTPUT_DIR/s3_buckets.json" 2>&1 || {
        log_warn "Failed to retrieve S3 buckets (may lack permissions)"
        echo '{"Buckets":[]}' > "$OUTPUT_DIR/s3_buckets.json"
        return
    }

    local count=$(cat "$OUTPUT_DIR/s3_buckets.json" | jq '.Buckets | length')
    log_info "  Found $count S3 buckets"

    # Get bucket names for easier reference
    cat "$OUTPUT_DIR/s3_buckets.json" | jq -r '.Buckets[].Name' > "$OUTPUT_DIR/s3_bucket_names.txt"
}

#==============================================================================
# Load Balancers (ALB/NLB/CLB)
#==============================================================================
discover_load_balancers() {
    log_info "Discovering Load Balancers..."

    # Application Load Balancers (ALBv2)
    aws elbv2 describe-load-balancers \
        --region "$REGION" \
        --output json \
        > "$OUTPUT_DIR/load_balancers_v2.json" 2>&1 || {
        log_warn "Failed to retrieve ALB/NLB (may lack permissions)"
        echo '{"LoadBalancers":[]}' > "$OUTPUT_DIR/load_balancers_v2.json"
        return
    }

    local count=$(cat "$OUTPUT_DIR/load_balancers_v2.json" | jq '.LoadBalancers | length')
    log_info "  Found $count ALB/NLB load balancers"

    # Target groups
    aws elbv2 describe-target-groups \
        --region "$REGION" \
        --output json \
        > "$OUTPUT_DIR/target_groups.json" 2>&1 || {
        echo '{"TargetGroups":[]}' > "$OUTPUT_DIR/target_groups.json"
    }

    # Classic Load Balancers (if any)
    aws elb describe-load-balancers \
        --region "$REGION" \
        --output json \
        > "$OUTPUT_DIR/load_balancers_classic.json" 2>&1 || {
        echo '{"LoadBalancerDescriptions":[]}' > "$OUTPUT_DIR/load_balancers_classic.json"
    }
}

#==============================================================================
# SQS Queues
#==============================================================================
discover_sqs() {
    log_info "Discovering SQS queues..."

    aws sqs list-queues \
        --region "$REGION" \
        --output json \
        > "$OUTPUT_DIR/sqs_queues.json" 2>&1 || {
        log_warn "Failed to retrieve SQS queues (may lack permissions)"
        echo '{"QueueUrls":[]}' > "$OUTPUT_DIR/sqs_queues.json"
        return
    }

    local count=$(cat "$OUTPUT_DIR/sqs_queues.json" | jq '.QueueUrls | length // 0')
    log_info "  Found $count SQS queues"
}

#==============================================================================
# SNS Topics
#==============================================================================
discover_sns() {
    log_info "Discovering SNS topics..."

    aws sns list-topics \
        --region "$REGION" \
        --output json \
        > "$OUTPUT_DIR/sns_topics.json" 2>&1 || {
        log_warn "Failed to retrieve SNS topics (may lack permissions)"
        echo '{"Topics":[]}' > "$OUTPUT_DIR/sns_topics.json"
        return
    }

    local count=$(cat "$OUTPUT_DIR/sns_topics.json" | jq '.Topics | length')
    log_info "  Found $count SNS topics"
}

#==============================================================================
# DynamoDB Tables
#==============================================================================
discover_dynamodb() {
    log_info "Discovering DynamoDB tables..."

    aws dynamodb list-tables \
        --region "$REGION" \
        --output json \
        > "$OUTPUT_DIR/dynamodb_tables.json" 2>&1 || {
        log_warn "Failed to retrieve DynamoDB tables (may lack permissions)"
        echo '{"TableNames":[]}' > "$OUTPUT_DIR/dynamodb_tables.json"
        return
    }

    local count=$(cat "$OUTPUT_DIR/dynamodb_tables.json" | jq '.TableNames | length')
    log_info "  Found $count DynamoDB tables"
}

#==============================================================================
# Lambda Functions
#==============================================================================
discover_lambda() {
    log_info "Discovering Lambda functions..."

    aws lambda list-functions \
        --region "$REGION" \
        --output json \
        > "$OUTPUT_DIR/lambda_functions.json" 2>&1 || {
        log_warn "Failed to retrieve Lambda functions (may lack permissions)"
        echo '{"Functions":[]}' > "$OUTPUT_DIR/lambda_functions.json"
        return
    }

    local count=$(cat "$OUTPUT_DIR/lambda_functions.json" | jq '.Functions | length')
    log_info "  Found $count Lambda functions"
}

#==============================================================================
# API Gateway
#==============================================================================
discover_api_gateway() {
    log_info "Discovering API Gateway APIs..."

    # REST APIs
    aws apigateway get-rest-apis \
        --region "$REGION" \
        --output json \
        > "$OUTPUT_DIR/api_gateway_rest.json" 2>&1 || {
        log_warn "Failed to retrieve API Gateway REST APIs (may lack permissions)"
        echo '{"items":[]}' > "$OUTPUT_DIR/api_gateway_rest.json"
        return
    }

    local rest_count=$(cat "$OUTPUT_DIR/api_gateway_rest.json" | jq '.items | length')
    log_info "  Found $rest_count REST APIs"

    # HTTP APIs (v2)
    aws apigatewayv2 get-apis \
        --region "$REGION" \
        --output json \
        > "$OUTPUT_DIR/api_gateway_http.json" 2>&1 || {
        echo '{"Items":[]}' > "$OUTPUT_DIR/api_gateway_http.json"
    }

    local http_count=$(cat "$OUTPUT_DIR/api_gateway_http.json" | jq '.Items | length')
    if [ "$http_count" -gt 0 ]; then
        log_info "  Found $http_count HTTP APIs"
    fi
}

#==============================================================================
# CloudFront Distributions
#==============================================================================
discover_cloudfront() {
    log_info "Discovering CloudFront distributions..."

    aws cloudfront list-distributions \
        --output json \
        > "$OUTPUT_DIR/cloudfront_distributions.json" 2>&1 || {
        log_warn "Failed to retrieve CloudFront distributions (may lack permissions)"
        echo '{"DistributionList":{"Items":[]}}' > "$OUTPUT_DIR/cloudfront_distributions.json"
        return
    }

    local count=$(cat "$OUTPUT_DIR/cloudfront_distributions.json" | jq '.DistributionList.Items | length')
    log_info "  Found $count CloudFront distributions"
}

#==============================================================================
# Secrets Manager
#==============================================================================
discover_secrets_manager() {
    log_info "Discovering Secrets Manager secrets (metadata only)..."

    aws secretsmanager list-secrets \
        --region "$REGION" \
        --output json \
        > "$OUTPUT_DIR/secrets_manager.json" 2>&1 || {
        log_warn "Failed to retrieve Secrets Manager secrets (may lack permissions)"
        echo '{"SecretList":[]}' > "$OUTPUT_DIR/secrets_manager.json"
        return
    }

    local count=$(cat "$OUTPUT_DIR/secrets_manager.json" | jq '.SecretList | length')
    log_info "  Found $count secrets (metadata only, no secret values)"
}

#==============================================================================
# Main Execution
#==============================================================================
main() {
    log_info "Phase 4: External Resources Discovery"
    log_info "======================================"
    echo ""

    verify_aws_access

    discover_rds
    echo ""

    discover_elasticache
    echo ""

    discover_s3
    echo ""

    discover_load_balancers
    echo ""

    discover_sqs
    echo ""

    discover_sns
    echo ""

    discover_dynamodb
    echo ""

    discover_lambda
    echo ""

    discover_api_gateway
    echo ""

    discover_cloudfront
    echo ""

    discover_secrets_manager
    echo ""

    log_info "External resources discovery complete!"
    log_info "Data saved to: $OUTPUT_DIR"

    # Generate summary
    cat > "$OUTPUT_DIR/external_resources_summary.txt" << EOF
External Resources Summary
==========================
Timestamp: $TIMESTAMP
Region: $REGION

Resources Discovered:
EOF

    # Count each resource type
    for file in "$OUTPUT_DIR"/*.json; do
        if [ -f "$file" ]; then
            local basename=$(basename "$file" .json)
            local count=0

            case "$basename" in
                rds_instances)
                    count=$(jq '.DBInstances | length' "$file")
                    echo "  - RDS Instances: $count" >> "$OUTPUT_DIR/external_resources_summary.txt"
                    ;;
                elasticache_clusters)
                    count=$(jq '.CacheClusters | length' "$file")
                    echo "  - ElastiCache Clusters: $count" >> "$OUTPUT_DIR/external_resources_summary.txt"
                    ;;
                s3_buckets)
                    count=$(jq '.Buckets | length' "$file")
                    echo "  - S3 Buckets: $count" >> "$OUTPUT_DIR/external_resources_summary.txt"
                    ;;
                load_balancers_v2)
                    count=$(jq '.LoadBalancers | length' "$file")
                    echo "  - Load Balancers (ALB/NLB): $count" >> "$OUTPUT_DIR/external_resources_summary.txt"
                    ;;
                sqs_queues)
                    count=$(jq '.QueueUrls | length // 0' "$file")
                    echo "  - SQS Queues: $count" >> "$OUTPUT_DIR/external_resources_summary.txt"
                    ;;
                dynamodb_tables)
                    count=$(jq '.TableNames | length' "$file")
                    echo "  - DynamoDB Tables: $count" >> "$OUTPUT_DIR/external_resources_summary.txt"
                    ;;
                lambda_functions)
                    count=$(jq '.Functions | length' "$file")
                    echo "  - Lambda Functions: $count" >> "$OUTPUT_DIR/external_resources_summary.txt"
                    ;;
            esac
        fi
    done

    cat "$OUTPUT_DIR/external_resources_summary.txt"

    echo ""
    log_info "Next steps:"
    log_info "1. Run ./05_analyze_data.py to parse and correlate all collected data"
    log_info "2. Review the generated architecture_summary.json"
}

main
