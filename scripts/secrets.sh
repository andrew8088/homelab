#!/bin/sh

if [ $# -ne 1 ]; then
    echo "Usage: $0 <namespace>"
    echo "Deploy secrets to the specified namespace only"
    exit 1
fi

NAMESPACE="$1"

iso_to_epoch() {
    date -d "$1" +%s 2>/dev/null || date -j -f "%Y-%m-%dT%H:%M:%S" "$1" +%s 2>/dev/null
}

needs_update() {
    local title=$1
    local namespace=$2
    local op_updated=$3
    
    if ! kubectl get secret "$title" -n "$NAMESPACE" >/dev/null 2>&1; then
        echo "ℹ️ does not exist, creating"
        return 0
    fi
    
    k8s_created=$(kubectl get secret "$title" -n "$NAMESPACE" -o jsonpath='{.metadata.creationTimestamp}' 2>/dev/null)
    
    if [ -z "$k8s_created" ]; then
        echo "‼️ could not get creation time, recreating"
        return 0
    fi
    
    op_epoch=$(iso_to_epoch "$op_updated")
    k8s_epoch=$(iso_to_epoch "$k8s_created")
    
    if [ -z "$op_epoch" ] || [ -z "$k8s_epoch" ]; then
        echo "‼️ could not parse timestamps, recreating"
        return 0
    fi
    
    if [ "$op_epoch" -gt "$k8s_epoch" ]; then
        echo "ℹ️ item is newer, recreating"
        return 0
    else
        echo "✅ item is up to date, skipping"
        return 1
    fi
}

op item list --vault homelab --tags "$NAMESPACE" | sed '1d' | awk '{print $2}' | while read title; do
    echo "🔑 $title"
    
    content=$(op item get "$title" --vault homelab --format json)
    
    if [ -z "$content" ]; then
        echo "‼️ Could not retrieve content, skipping"
        continue
    fi
    
    op_updated=$(echo "$content" | jq -r '.updated_at // .updatedAt // empty')
    
    if [ -z "$op_updated" ]; then
        echo "‼️ Could not get timestamp, recreating"
        op_updated="1970-01-01T00:00:00Z"
    fi
        
    if needs_update "$title" "$NAMESPACE" "$op_updated"; then
        literals=$(echo "$content" | jq -r '.fields[] | select(.id!="notesPlain") | "--from-literal=\(.label)=\(.value)"' | tr '\n' ' ')
        
        if [ -z "$literals" ]; then
            echo "‼️ no fields, skipping"
            continue
        fi
        
        if eval "kubectl create secret generic \"$title\" --namespace=\"$NAMESPACE\" $literals --dry-run=client -o yaml | kubectl apply -f -"; then
            echo "✅ successfully applied secret $title in namespace $NAMESPACE"
        else
            echo "‼️ failed to apply secret $title in namespace $NAMESPACE"
        fi
    fi
done
