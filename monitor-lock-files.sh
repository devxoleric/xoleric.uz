#!/bin/bash

# Lock file monitoring script
set -e

echo "🔍 Monitoring lock files..."

# Configuration
LOCK_FILES=(
    "frontend/package-lock.json"
    "backend/package-lock.json"
    "deploy.lock.json"
)

CHECK_INTERVAL=60 # seconds
MAX_RETRIES=3

# Function to check lock file
check_lock_file() {
    local file=$1
    local retry_count=0
    
    while [ $retry_count -lt $MAX_RETRIES ]; do
        if [ -f "$file" ]; then
            # Check if file is readable
            if [ -r "$file" ]; then
                # Check if file is valid JSON (for JSON files)
                if [[ "$file" == *.json ]]; then
                    if jq empty "$file" >/dev/null 2>&1; then
                        echo "✅ $file is valid and readable"
                        return 0
                    else
                        echo "❌ $file is invalid JSON"
                        return 1
                    fi
                else
                    echo "✅ $file exists and is readable"
                    return 0
                fi
            else
                echo "❌ $file is not readable"
                return 1
            fi
        else
            echo "❌ $file does not exist"
            return 1
        fi
        
        retry_count=$((retry_count + 1))
        sleep 5
    done
    
    echo "❌ Failed to check $file after $MAX_RETRIES retries"
    return 1
}

# Function to check for lock file conflicts
check_conflicts() {
    echo "Checking for lock file conflicts..."
    
    # Check for package-lock.json and yarn.lock conflicts
    if [ -f "frontend/package-lock.json" ] && [ -f "frontend/yarn.lock" ]; then
        echo "⚠️  Both package-lock.json and yarn.lock exist in frontend"
        echo "   Consider removing one to avoid conflicts"
    fi
    
    if [ -f "backend/package-lock.json" ] && [ -f "backend/yarn.lock" ]; then
        echo "⚠️  Both package-lock.json and yarn.lock exist in backend"
        echo "   Consider removing one to avoid conflicts"
    fi
    
    # Check for Git conflicts in lock files
    if git status --porcelain | grep -q "^UU.*package-lock.json"; then
        echo "❌ Git merge conflict detected in package-lock.json"
        echo "   Run: git checkout --theirs package-lock.json && npm install"
        return 1
    fi
}

# Function to monitor continuously
monitor_continuously() {
    echo "Starting continuous monitoring (interval: ${CHECK_INTERVAL}s)..."
    
    while true; do
        echo ""
        echo "=== Monitoring check at $(date) ==="
        
        all_ok=true
        
        # Check all lock files
        for file in "${LOCK_FILES[@]}"; do
            if ! check_lock_file "$file"; then
                all_ok=false
            fi
        done
        
        # Check for conflicts
        if ! check_conflicts; then
            all_ok=false
        fi
        
        # Check Docker lock
        if docker ps --format 'table {{.Names}}' | grep -q "xoleric"; then
            echo "✅ Docker containers are running"
        else
            echo "❌ Docker containers are not running"
            all_ok=false
        fi
        
        if [ "$all_ok" = true ]; then
            echo "✅ All systems operational"
        else
            echo "⚠️  Some issues detected"
        fi
        
        sleep $CHECK_INTERVAL
    done
}

# Main execution
case "$1" in
    "once")
        # Run checks once
        for file in "${LOCK_FILES[@]}"; do
            check_lock_file "$file"
        done
        check_conflicts
        ;;
    "continuous")
        # Run continuous monitoring
        monitor_continuously
        ;;
    "fix")
        # Fix lock files
        ./fix-lock-files.sh
        ;;
    "validate")
        # Validate all lock files
        echo "Validating all lock files..."
        
        for file in "${LOCK_FILES[@]}"; do
            if [ -f "$file" ]; then
                echo "Validating $file..."
                
                # Check file size
                size=$(stat -c%s "$file")
                if [ "$size" -gt 1000 ]; then
                    echo "  ✅ Size: $size bytes"
                else
                    echo "  ⚠️  Size: $size bytes (might be too small)"
                fi
                
                # Check last modified
                modified=$(stat -c %y "$file")
                echo "  📅 Last modified: $modified"
                
                # For JSON files, check structure
                if [[ "$file" == *.json ]]; then
                    if jq empty "$file" >/dev/null 2>&1; then
                        echo "  ✅ Valid JSON"
                        
                        # Count dependencies
                        if [[ "$file" == *package-lock.json ]]; then
                            deps_count=$(jq '.packages | length' "$file")
                            echo "  📦 Packages: $deps_count"
                        fi
                    else
                        echo "  ❌ Invalid JSON"
                    fi
                fi
            else
                echo "❌ $file not found"
            fi
            echo ""
        done
        ;;
    *)
        echo "Usage: $0 {once|continuous|fix|validate}"
        echo ""
        echo "Commands:"
        echo "  once       - Run checks once"
        echo "  continuous - Run continuous monitoring"
        echo "  fix        - Fix lock files"
        echo "  validate   - Validate lock files"
        exit 1
        ;;
esac
