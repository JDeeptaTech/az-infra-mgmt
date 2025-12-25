``` text

#!/bin/bash

# Script: pod-memory-analyzer.sh
# Analyzes current memory usage and provides safe increase recommendations

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
THRESHOLD_PERCENT=80  # Warning threshold for current usage
SAFETY_MARGIN=20      # Percentage to keep as buffer
MIN_INCREASE_PERCENT=10
MAX_INCREASE_PERCENT=200

print_header() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}"
}

print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to convert memory units to MiB
convert_to_mebibytes() {
    local value=$1
    local unit=$(echo "$value" | tr -d '0-9.')
    
    if [[ -z "$unit" ]]; then
        echo "$value"  # Assume it's already in bytes or unitless
        return
    fi
    
    local num=$(echo "$value" | tr -dc '0-9.')
    
    case $unit in
        "Ki"|"k")
            echo "scale=2; $num / 1024" | bc
            ;;
        "Mi"|"M"|"m")
            echo "$num"
            ;;
        "Gi"|"G"|"g")
            echo "scale=2; $num * 1024" | bc
            ;;
        "Ti"|"T"|"t")
            echo "scale=2; $num * 1024 * 1024" | bc
            ;;
        *)
            echo "$num"  # Unknown unit, return as-is
            ;;
    esac
}

# Function to get node allocatable memory
get_node_allocatable_memory() {
    local node=$1
    kubectl get node $node -o json | jq -r '.status.allocatable.memory' | sed 's/Ki//'
}

# Function to get node memory capacity
get_node_memory_capacity() {
    local node=$1
    kubectl get node $node -o json | jq -r '.status.capacity.memory' | sed 's/Ki//'
}

# Function to calculate available memory on node
calculate_available_node_memory() {
    local node=$1
    
    # Get node memory usage from metrics server
    if command -v kubectl-top &> /dev/null || kubectl top nodes &> /dev/null; then
        local node_usage=$(kubectl top node $node --no-headers | awk '{print $3}' | sed 's/MiB//' 2>/dev/null || echo "0")
        local node_capacity=$(kubectl describe node $node | grep -A 5 "Capacity" | grep memory | awk '{print $2}' | sed 's/Ki//')
        
        if [[ ! -z "$node_usage" && ! -z "$node_capacity" ]]; then
            # Convert capacity from KiB to MiB
            local capacity_mib=$(echo "scale=2; $node_capacity / 1024" | bc)
            local available_mib=$(echo "scale=2; $capacity_mib - $node_usage" | bc)
            echo "$available_mib"
            return
        fi
    fi
    
    # Fallback: get from allocatable
    local allocatable_kib=$(get_node_allocatable_memory $node)
    local allocated_kib=$(kubectl describe node $node | grep -A 5 "Allocated resources" | grep memory | awk '{print $3}' | sed 's/Mi//')
    
    # Convert allocated from Mi to KiB if needed
    if [[ "$allocated_kib" == *"Mi"* ]]; then
        allocated_kib=$(echo "$allocated_kib" | sed 's/Mi//')
        allocated_kib=$(echo "$allocated_kib * 1024" | bc)
    fi
    
    local available_kib=$(echo "scale=2; $allocatable_kib - $allocated_kib" | bc)
    local available_mib=$(echo "scale=2; $available_kib / 1024" | bc)
    
    echo "$available_mib"
}

# Main analysis function
analyze_pod_memory() {
    local namespace=$1
    local pod_name=$2
    
    print_header "MEMORY ANALYSIS FOR POD: $pod_name"
    
    # Get pod details
    local pod_json=$(kubectl get pod $pod_name -n $namespace -o json 2>/dev/null)
    
    if [[ -z "$pod_json" ]]; then
        print_error "Pod $pod_name not found in namespace $namespace"
        exit 1
    fi
    
    # Get node name
    local node_name=$(echo "$pod_json" | jq -r '.spec.nodeName')
    print_info "Node: $node_name"
    
    # Get current memory requests and limits
    local containers=$(echo "$pod_json" | jq -r '.spec.containers[] | .name')
    
    for container in $containers; do
        print_header "Container: $container"
        
        # Get current memory request and limit
        local current_request=$(echo "$pod_json" | jq -r ".spec.containers[] | select(.name == \"$container\") | .resources.requests.memory // \"N/A\"")
        local current_limit=$(echo "$pod_json" | jq -r ".spec.containers[] | select(.name == \"$container\") | .resources.limits.memory // \"N/A\"")
        
        echo "Current Memory Request: $current_request"
        echo "Current Memory Limit: $current_limit"
        
        # Get actual memory usage
        local usage_mib="N/A"
        if command -v kubectl-top &> /dev/null || kubectl top pods &> /dev/null; then
            usage_mib=$(kubectl top pod $pod_name -n $namespace --containers 2>/dev/null | grep "$container" | awk '{print $3}' | sed 's/Mi//' || echo "N/A")
        fi
        
        if [[ "$usage_mib" != "N/A" ]]; then
            echo "Current Memory Usage: ${usage_mib}Mi"
            
            # Convert current request to MiB for comparison
            if [[ "$current_request" != "N/A" ]]; then
                local request_mib=$(convert_to_mebibytes "$current_request")
                local usage_percent=$(echo "scale=2; ($usage_mib / $request_mib) * 100" | bc 2>/dev/null || echo "0")
                
                echo -n "Usage vs Request: "
                if (( $(echo "$usage_percent > $THRESHOLD_PERCENT" | bc -l 2>/dev/null) )); then
                    echo -e "${YELLOW}${usage_percent}%${NC} (Above ${THRESHOLD_PERCENT}% threshold)"
                else
                    echo -e "${GREEN}${usage_percent}%${NC}"
                fi
                
                # Calculate recommended increase
                if (( $(echo "$usage_percent > $THRESHOLD_PERCENT" | bc -l 2>/dev/null) )); then
                    # Calculate based on current usage with safety margin
                    local recommended_mib=$(echo "scale=2; $usage_mib * (1 + $SAFETY_MARGIN/100)" | bc)
                    local increase_percent=$(echo "scale=2; (($recommended_mib / $request_mib) - 1) * 100" | bc)
                    
                    # Apply bounds
                    if (( $(echo "$increase_percent < $MIN_INCREASE_PERCENT" | bc -l 2>/dev/null) )); then
                        increase_percent=$MIN_INCREASE_PERCENT
                        recommended_mib=$(echo "scale=2; $request_mib * (1 + $MIN_INCREASE_PERCENT/100)" | bc)
                    fi
                    
                    if (( $(echo "$increase_percent > $MAX_INCREASE_PERCENT" | bc -l 2>/dev/null) )); then
                        increase_percent=$MAX_INCREASE_PERCENT
                        recommended_mib=$(echo "scale=2; $request_mib * (1 + $MAX_INCREASE_PERCENT/100)" | bc)
                    fi
                    
                    # Convert back to human readable
                    local recommended_human=$(convert_to_human "$recommended_mib")
                    
                    echo -e "${YELLOW}Recommended new memory request: ${recommended_human}${NC}"
                    echo "Increase by: ${increase_percent}%"
                    
                    # Check if node has enough capacity
                    local available_node_memory=$(calculate_available_node_memory "$node_name")
                    local required_additional=$(echo "scale=2; $recommended_mib - $request_mib" | bc)
                    
                    if (( $(echo "$available_node_memory > $required_additional" | bc -l 2>/dev/null) )); then
                        echo -e "${GREEN}✓ Node has sufficient available memory${NC}"
                        echo "Available on node: ${available_node_memory}Mi"
                        echo "Additional needed: ${required_additional}Mi"
                    else
                        echo -e "${RED}✗ Node may not have enough available memory${NC}"
                        echo "Available on node: ${available_node_memory}Mi"
                        echo "Additional needed: ${required_additional}Mi"
                        echo "Consider:"
                        echo "1. Lower increase percentage"
                        echo "2. Schedule pod to different node"
                        echo "3. Add more nodes to cluster"
                    fi
                else
                    echo -e "${GREEN}Current memory request appears sufficient${NC}"
                    echo "No increase recommended at this time"
                fi
            fi
        else
            print_warning "Memory usage metrics not available. Install metrics-server."
            echo "To install metrics-server: kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml"
        fi
        
        # Analyze memory limit vs request
        if [[ "$current_limit" != "N/A" && "$current_request" != "N/A" ]]; then
            local limit_mib=$(convert_to_mebibytes "$current_limit")
            local request_mib=$(convert_to_mebibytes "$current_request")
            
            if [[ "$limit_mib" != "0" && "$request_mib" != "0" ]]; then
                local limit_ratio=$(echo "scale=2; $limit_mib / $request_mib" | bc)
                echo "Limit/Request Ratio: $limit_ratio"
                
                if (( $(echo "$limit_ratio < 1.5" | bc -l 2>/dev/null) )); then
                    echo -e "${YELLOW}Consider increasing limit to at least 1.5x request for burst handling${NC}"
                fi
            fi
        fi
        
        echo ""
    done
    
    # Check for OOM kills
    print_header "OOM HISTORY CHECK"
    local oom_events=$(kubectl get events -n $namespace --field-selector involvedObject.name=$pod_name --sort-by='.lastTimestamp' | grep -i "oom\|outofmemory" || true)
    
    if [[ -n "$oom_events" ]]; then
        print_error "OOM kills detected! Immediate increase recommended."
        echo "$oom_events"
        echo ""
        echo -e "${RED}ACTION REQUIRED: Increase memory by at least 50%${NC}"
    else
        echo -e "${GREEN}No OOM kills detected${NC}"
    fi
}

convert_to_human() {
    local mib=$1
    
    if (( $(echo "$mib > 1024" | bc -l 2>/dev/null) )); then
        echo "$(echo "scale=2; $mib / 1024" | bc)Gi"
    else
        echo "${mib}Mi"
    fi
}

# Batch analysis for all pods in namespace
analyze_all_pods() {
    local namespace=$1
    
    print_header "BATCH ANALYSIS FOR NAMESPACE: $namespace"
    
    # Get all pods
    local pods=$(kubectl get pods -n $namespace -o jsonpath='{.items[*].metadata.name}')
    
    if [[ -z "$pods" ]]; then
        print_error "No pods found in namespace $namespace"
        exit 1
    fi
    
    local total_pods=0
    local pods_need_increase=0
    
    for pod in $pods; do
        echo ""
        print_header "Analyzing pod: $pod"
        
        # Quick analysis without detailed container breakdown
        local pod_json=$(kubectl get pod $pod -n $namespace -o json)
        local containers=$(echo "$pod_json" | jq -r '.spec.containers[].name')
        
        for container in $containers; do
            local current_request=$(echo "$pod_json" | jq -r ".spec.containers[] | select(.name == \"$container\") | .resources.requests.memory // \"N/A\"")
            
            if [[ "$current_request" != "N/A" ]] && kubectl top pods &> /dev/null; then
                local usage_mib=$(kubectl top pod $pod -n $namespace --containers 2>/dev/null | grep "$container" | awk '{print $3}' | sed 's/Mi//' || echo "0")
                local request_mib=$(convert_to_mebibytes "$current_request")
                
                if [[ "$usage_mib" != "0" && "$request_mib" != "0" ]]; then
                    local usage_percent=$(echo "scale=2; ($usage_mib / $request_mib) * 100" | bc 2>/dev/null || echo "0")
                    
                    echo "Container: $container"
                    echo "  Request: $current_request"
                    echo "  Usage: ${usage_mib}Mi (${usage_percent}%)"
                    
                    if (( $(echo "$usage_percent > $THRESHOLD_PERCENT" | bc -l 2>/dev/null) )); then
                        echo -e "  ${YELLOW}Status: NEEDS INCREASE${NC}"
                        ((pods_need_increase++))
                        
                        # Quick recommendation
                        local recommended_mib=$(echo "scale=2; $usage_mib * 1.3" | bc)  # 30% buffer
                        echo "  Quick recommendation: ~$(convert_to_human $recommended_mib)"
                    else
                        echo -e "  ${GREEN}Status: OK${NC}"
                    fi
                fi
            fi
        done
        
        ((total_pods++))
    done
    
    echo ""
    print_header "SUMMARY"
    echo "Total pods analyzed: $total_pods"
    echo "Pods needing memory increase: $pods_need_increase"
    
    if [[ $pods_need_increase -gt 0 ]]; then
        echo -e "${YELLOW}Consider running detailed analysis on specific pods${NC}"
    fi
}

# Generate patch file for memory increase
generate_patch_file() {
    local namespace=$1
    local pod_name=$2
    local container=$3
    local new_memory=$4
    
    cat <<EOF > memory-patch-${pod_name}.yaml
apiVersion: apps/v1
kind: Deployment  # Change to StatefulSet/DaemonSet if needed
metadata:
  name: $(kubectl get pod $pod_name -n $namespace -o jsonpath='{.metadata.ownerReferences[?(@.kind=="Deployment")].name}')
  namespace: $namespace
spec:
  template:
    spec:
      containers:
      - name: $container
        resources:
          requests:
            memory: "$new_memory"
          limits:
            memory: "$(echo $new_memory | sed 's/[0-9.]*/& * 1.5/' | bc -l)Mi"  # 1.5x request
EOF
    
    print_info "Patch file created: memory-patch-${pod_name}.yaml"
    echo "Apply with: kubectl apply -f memory-patch-${pod_name}.yaml"
}

# Usage
usage() {
    echo "Usage: $0 [options]"
    echo ""
    echo "Options:"
    echo "  -n, --namespace <namespace>    Kubernetes namespace (default: default)"
    echo "  -p, --pod <pod-name>          Analyze specific pod"
    echo "  -a, --all                      Analyze all pods in namespace"
    echo "  -t, --threshold <percent>     Usage threshold percentage (default: 80)"
    echo "  -s, --safety <percent>        Safety margin percentage (default: 20)"
    echo "  -h, --help                     Show this help"
    echo ""
    echo "Examples:"
    echo "  $0 -n production -p my-app-xyz123  # Analyze specific pod"
    echo "  $0 -n default --all                # Analyze all pods"
    echo "  $0 -n staging -p api --threshold 90"
}

main() {
    local namespace="default"
    local pod_name=""
    local analyze_all=false
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -n|--namespace)
                namespace="$2"
                shift 2
                ;;
            -p|--pod)
                pod_name="$2"
                shift 2
                ;;
            -a|--all)
                analyze_all=true
                shift
                ;;
            -t|--threshold)
                THRESHOLD_PERCENT="$2"
                shift 2
                ;;
            -s|--safety)
                SAFETY_MARGIN="$2"
                shift 2
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                echo "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
    
    # Check if kubectl is available
    if ! command -v kubectl &> /dev/null; then
        print_error "kubectl not found. Please install kubectl."
        exit 1
    fi
    
    # Check if connected to cluster
    if ! kubectl cluster-info &> /dev/null; then
        print_error "Not connected to Kubernetes cluster"
        exit 1
    fi
    
    # Run analysis
    if [[ "$analyze_all" == true ]]; then
        analyze_all_pods "$namespace"
    elif [[ -n "$pod_name" ]]; then
        analyze_pod_memory "$namespace" "$pod_name"
    else
        print_error "Please specify either --pod or --all"
        usage
        exit 1
    fi
}

# Run main function
main "$@"


===


#!/bin/bash

# Quick memory check script
NAMESPACE=${1:-default}

echo "=== QUICK MEMORY ANALYSIS ==="
echo "Namespace: $NAMESPACE"
echo ""

# Get pods with memory usage
kubectl top pods -n $NAMESPACE

echo ""
echo "=== DETAILED ANALYSIS ==="

# Get all deployments
kubectl get deployments -n $NAMESPACE -o json | jq -r '.items[] | .metadata.name' | while read deploy; do
    echo ""
    echo "Deployment: $deploy"
    
    # Get current memory request
    kubectl get deployment $deploy -n $NAMESPACE -o json | jq -r '.spec.template.spec.containers[].resources.requests.memory // "Not set"'
    
    # Get pod and check usage
    POD=$(kubectl get pods -n $NAMESPACE -l app=$deploy -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    if [[ -n "$POD" ]]; then
        echo "Pod: $POD"
        kubectl top pod $POD -n $NAMESPACE --containers
    fi
    echo "---"
done
====================


#!/usr/bin/env python3
# memory_calculator.py - Calculate optimal memory increase

import subprocess
import json
import sys
import math

def get_pod_memory_metrics(namespace, pod_name):
    """Get pod memory metrics"""
    try:
        # Get pod memory usage
        cmd = f"kubectl top pod {pod_name} -n {namespace} --containers"
        result = subprocess.run(cmd, shell=True, capture_output=True, text=True)
        
        if result.returncode != 0:
            return None
        
        lines = result.stdout.strip().split('\n')
        metrics = {}
        
        for line in lines[1:]:  # Skip header
            parts = line.split()
            if len(parts) >= 3:
                container = parts[1]
                usage_mib = parts[2].replace('Mi', '')
                metrics[container] = float(usage_mib)
        
        return metrics
    except:
        return None

def calculate_recommended_memory(current_request_mib, current_usage_mib, 
                                threshold=80, safety_margin=30,
                                min_increase=10, max_increase=200):
    """Calculate recommended memory based on usage patterns"""
    
    # Calculate usage percentage
    usage_percent = (current_usage_mib / current_request_mib) * 100
    
    recommendations = {
        'current_request': current_request_mib,
        'current_usage': current_usage_mib,
        'usage_percent': usage_percent,
        'needs_increase': usage_percent > threshold
    }
    
    if usage_percent > threshold:
        # Calculate based on current usage with safety margin
        recommended_mib = current_usage_mib * (1 + safety_margin/100)
        
        # Ensure minimum increase
        min_recommended = current_request_mib * (1 + min_increase/100)
        recommended_mib = max(recommended_mib, min_recommended)
        
        # Apply maximum increase limit
        max_allowed = current_request_mib * (1 + max_increase/100)
        recommended_mib = min(recommended_mib, max_allowed)
        
        recommendations['recommended_mib'] = recommended_mib
        recommendations['increase_percent'] = ((recommended_mib / current_request_mib) - 1) * 100
        recommendations['increase_mib'] = recommended_mib - current_request_mib
        
        # Convert to human readable
        if recommended_mib >= 1024:
            recommendations['recommended_human'] = f"{recommended_mib/1024:.1f}Gi"
        else:
            recommendations['recommended_human'] = f"{recommended_mib:.0f}Mi"
    
    return recommendations

def main():
    if len(sys.argv) < 4:
        print("Usage: python memory_calculator.py <namespace> <pod> <current-memory>")
        print("Example: python memory_calculator.py default my-pod 512Mi")
        sys.exit(1)
    
    namespace = sys.argv[1]
    pod = sys.argv[2]
    current_memory = sys.argv[3]
    
    # Convert current memory to MiB
    if current_memory.endswith('Mi'):
        current_mib = float(current_memory[:-2])
    elif current_memory.endswith('Gi'):
        current_mib = float(current_memory[:-2]) * 1024
    else:
        print(f"Unknown memory unit: {current_memory}")
        sys.exit(1)
    
    # Get metrics
    metrics = get_pod_memory_metrics(namespace, pod)
    
    if not metrics:
        print(f"Could not get metrics for pod {pod}")
        sys.exit(1)
    
    print(f"\nAnalysis for pod: {pod}")
    print(f"Current memory request: {current_memory} ({current_mib:.0f}Mi)")
    print("\nContainers:")
    
    for container, usage_mib in metrics.items():
        print(f"\n  {container}:")
        print(f"    Usage: {usage_mib}Mi")
        
        rec = calculate_recommended_memory(current_mib, usage_mib)
        
        print(f"    Usage vs Request: {rec['usage_percent']:.1f}%")
        
        if rec['needs_increase']:
            print(f"    ✅ RECOMMENDED INCREASE: {rec['recommended_human']}")
            print(f"    Increase by: {rec['increase_percent']:.1f}% ({rec['increase_mib']:.0f}Mi)")
        else:
            print("    ✅ Current memory sufficient")

if __name__ == "__main__":
    main()





















