#!/bin/bash

################################################################################
# RDS Analytics Tables Setup Script
# 
# This script creates analytics tables in the RDS PostgreSQL database for
# Kafka consumers to persist predictions and high-risk customer alerts.
#
# Usage:
#   ./make_rds.sh                    # Create tables if not exists
#   ./make_rds.sh --overwrite        # Drop and recreate all tables
#   ./make_rds.sh --check            # Check if tables exist
#   ./make_rds.sh --verify           # Verify tables and show row counts
################################################################################

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

################################################################################
# Functions
################################################################################

print_header() {
    echo ""
    echo -e "${BLUE}â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”${NC}"
    echo ""
}

print_success() {
    echo -e "${GREEN}âœ… $1${NC}"
}

print_error() {
    echo -e "${RED}âŒ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}âš ï¸  $1${NC}"
}

print_info() {
    echo -e "${BLUE}â„¹ï¸  $1${NC}"
}

# Load environment variables
load_env() {
    if [ -f "$SCRIPT_DIR/.env" ]; then
        print_info "Loading environment variables from .env"
        set -a
        source "$SCRIPT_DIR/.env"
        set +a
        
        # Handle different naming conventions
        # If RDS_USERNAME exists but RDS_USER doesn't, use RDS_USERNAME
        if [ -z "$RDS_USER" ] && [ -n "$RDS_USERNAME" ]; then
            export RDS_USER="$RDS_USERNAME"
        fi
        
        # Use RDS_ANALYTICS_DB for analytics tables, fallback to RDS_DB_NAME
        if [ -z "$RDS_ANALYTICS_DB" ] && [ -n "$RDS_DB_NAME" ]; then
            export RDS_ANALYTICS_DB="$RDS_DB_NAME"
        fi
    else
        print_error ".env file not found!"
        exit 1
    fi
}

# Check if required environment variables are set
check_env() {
    local missing=0
    
    if [ -z "$RDS_HOST" ]; then
        print_error "RDS_HOST not set in .env"
        missing=1
    fi
    
    if [ -z "$RDS_PORT" ]; then
        print_error "RDS_PORT not set in .env"
        missing=1
    fi
    
    if [ -z "$RDS_USER" ]; then
        print_error "RDS_USER not set in .env"
        missing=1
    fi
    
    if [ -z "$RDS_PASSWORD" ]; then
        print_error "RDS_PASSWORD not set in .env"
        missing=1
    fi
    
    if [ -z "$RDS_ANALYTICS_DB" ]; then
        print_error "RDS_ANALYTICS_DB not set in .env"
        missing=1
    fi
    
    if [ $missing -eq 1 ]; then
        exit 1
    fi
    
    print_success "All required environment variables are set"
    print_info "RDS Host: $RDS_HOST"
    print_info "Database: $RDS_ANALYTICS_DB"
    print_info "User: $RDS_USER"
}

# Check if psql is installed
check_psql() {
    if ! command -v psql &> /dev/null; then
        print_error "psql is not installed. Please install PostgreSQL client."
        print_info "macOS: brew install postgresql"
        print_info "Ubuntu: sudo apt-get install postgresql-client"
        exit 1
    fi
    print_success "psql is installed"
}

# Test RDS connection
test_connection() {
    print_info "Testing RDS connection..."
    
    if PGPASSWORD="$RDS_PASSWORD" psql \
        -h "$RDS_HOST" \
        -p "$RDS_PORT" \
        -U "$RDS_USER" \
        -d "$RDS_ANALYTICS_DB" \
        -c "SELECT 1;" > /dev/null 2>&1; then
        print_success "RDS connection successful"
        return 0
    else
        print_error "Failed to connect to RDS"
        print_info "Please check your credentials and network access"
        return 1
    fi
}

# Check if tables exist
check_tables() {
    print_header "CHECKING EXISTING TABLES"
    
    local tables=("churn_predictions" "high_risk_customers" "churn_metrics_hourly" "churn_metrics_daily")
    local exists=0
    
    for table in "${tables[@]}"; do
        if PGPASSWORD="$RDS_PASSWORD" psql \
            -h "$RDS_HOST" \
            -p "$RDS_PORT" \
            -U "$RDS_USER" \
            -d "$RDS_ANALYTICS_DB" \
            -tAc "SELECT EXISTS (SELECT FROM information_schema.tables WHERE table_name='$table');" 2>/dev/null | grep -q 't'; then
            print_success "Table '$table' exists"
            exists=$((exists + 1))
        else
            print_warning "Table '$table' does not exist"
        fi
    done
    
    echo ""
    print_info "Found $exists out of ${#tables[@]} tables"
    return $exists
}

# Drop all analytics tables
drop_tables() {
    print_header "DROPPING EXISTING TABLES"
    
    print_warning "This will delete all data in analytics tables!"
    read -p "Are you sure you want to continue? (yes/no): " confirm
    
    if [ "$confirm" != "yes" ]; then
        print_info "Operation cancelled"
        exit 0
    fi
    
    print_info "Dropping tables..."
    
    PGPASSWORD="$RDS_PASSWORD" psql \
        -h "$RDS_HOST" \
        -p "$RDS_PORT" \
        -U "$RDS_USER" \
        -d "$RDS_ANALYTICS_DB" \
        <<EOF
DROP TABLE IF EXISTS churn_predictions CASCADE;
DROP TABLE IF EXISTS high_risk_customers CASCADE;
DROP TABLE IF EXISTS churn_metrics_hourly CASCADE;
DROP TABLE IF EXISTS churn_metrics_daily CASCADE;
DROP VIEW IF EXISTS churn_summary_view CASCADE;
EOF
    
    print_success "All tables dropped successfully"
}

# Create tables
create_tables() {
    print_header "CREATING ANALYTICS TABLES"
    
    if [ ! -f "$SCRIPT_DIR/sql/create_analytics_tables.sql" ]; then
        print_error "SQL file not found: sql/create_analytics_tables.sql"
        exit 1
    fi
    
    print_info "Executing SQL script..."
    
    if PGPASSWORD="$RDS_PASSWORD" psql \
        -h "$RDS_HOST" \
        -p "$RDS_PORT" \
        -U "$RDS_USER" \
        -d "$RDS_ANALYTICS_DB" \
        -f "$SCRIPT_DIR/sql/create_analytics_tables.sql" > /dev/null 2>&1; then
        print_success "Tables created successfully"
    else
        print_error "Failed to create tables"
        exit 1
    fi
}

# Verify tables and show row counts
verify_tables() {
    print_header "VERIFYING TABLES AND DATA"
    
    print_info "Checking table structure..."
    PGPASSWORD="$RDS_PASSWORD" psql \
        -h "$RDS_HOST" \
        -p "$RDS_PORT" \
        -U "$RDS_USER" \
        -d "$RDS_ANALYTICS_DB" \
        -c "\dt churn*"
    
    echo ""
    print_info "Checking row counts..."
    PGPASSWORD="$RDS_PASSWORD" psql \
        -h "$RDS_HOST" \
        -p "$RDS_PORT" \
        -U "$RDS_USER" \
        -d "$RDS_ANALYTICS_DB" \
        <<EOF
SELECT 
    'churn_predictions' as table_name, 
    COUNT(*) as row_count 
FROM churn_predictions
UNION ALL
SELECT 
    'high_risk_customers' as table_name, 
    COUNT(*) as row_count 
FROM high_risk_customers
UNION ALL
SELECT 
    'churn_metrics_hourly' as table_name, 
    COUNT(*) as row_count 
FROM churn_metrics_hourly
UNION ALL
SELECT 
    'churn_metrics_daily' as table_name, 
    COUNT(*) as row_count 
FROM churn_metrics_daily;
EOF
    
    echo ""
    print_success "Verification complete"
}

# Show usage
show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Create analytics tables in RDS PostgreSQL database for Kafka consumers.

OPTIONS:
    (no args)       Create tables if they don't exist (safe, default)
    --overwrite     Drop and recreate all tables (WARNING: deletes all data)
    --check         Check if tables exist without creating them
    --verify        Verify tables exist and show row counts
    --help          Show this help message

EXAMPLES:
    $0                    # Create tables if not exists
    $0 --overwrite        # Drop and recreate all tables
    $0 --check            # Check if tables exist
    $0 --verify           # Verify tables and show data

TABLES CREATED:
    - churn_predictions      Individual customer predictions
    - high_risk_customers    High-risk customer alerts (risk >= 0.7)
    - churn_metrics_hourly   Hourly aggregated metrics
    - churn_metrics_daily    Daily aggregated metrics

EOF
}

################################################################################
# Main Script
################################################################################

main() {
    local mode="create"
    
    # Parse arguments
    case "${1:-}" in
        --overwrite)
            mode="overwrite"
            ;;
        --check)
            mode="check"
            ;;
        --verify)
            mode="verify"
            ;;
        --help|-h)
            show_usage
            exit 0
            ;;
        "")
            mode="create"
            ;;
        *)
            print_error "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
    
    print_header "RDS ANALYTICS TABLES SETUP"
    
    # Load and check environment
    load_env
    check_env
    check_psql
    
    # Test connection
    if ! test_connection; then
        print_warning "RDS is not accessible from your local machine (VPC restriction)"
        print_info "Use one of these methods instead:"
        print_info "1. Run from AWS Console RDS Query Editor"
        print_info "2. Use AWS Systems Manager Session Manager with port forwarding"
        print_info "3. Run SQL manually in Airflow UI (Admin > Variables > SQL Lab)"
        echo ""
        print_info "SQL file location: sql/create_analytics_tables.sql"
        exit 1
    fi
    
    # Execute based on mode
    case "$mode" in
        check)
            check_tables
            ;;
        verify)
            check_tables
            verify_tables
            ;;
        overwrite)
            check_tables
            drop_tables
            create_tables
            verify_tables
            print_success "Tables recreated successfully!"
            ;;
        create)
            check_tables
            existing=$?
            
            if [ $existing -eq 4 ]; then
                print_info "All tables already exist"
                read -p "Do you want to verify them? (yes/no): " verify
                if [ "$verify" = "yes" ]; then
                    verify_tables
                fi
            else
                print_info "Creating missing tables..."
                create_tables
                verify_tables
                print_success "Setup complete!"
            fi
            ;;
    esac
    
    echo ""
    print_header "NEXT STEPS"
    print_info "1. Check Kafka consumer logs: make ecs-logs-kafka"
    print_info "2. Verify data is being written: $0 --verify"
    print_info "3. Monitor predictions: SELECT COUNT(*) FROM churn_predictions;"
    echo ""
}

# Run main function
main "$@"

