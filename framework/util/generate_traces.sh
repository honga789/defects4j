#!/bin/bash
#
# generate_traces.sh - Generate execution traces for Defects4J bugs
#
# Usage: ./generate_traces.sh -p <project> -b <bug_id> [options]
#
# Options:
#   -p, --project     Project ID (e.g., Math, Lang, Chart)
#   -b, --bug         Bug ID (e.g., 1, 2, 3)
#   -w, --workdir     Working directory (default: /workspace)
#   -o, --output      Output directory for traces (default: /workspace/traces)
#   --max-pass        Max number of passing tests to run (0 = all, default: 0)
#   --max-subtests    Max subtests in a class before switching to single method mode (default: 30)
#   --max-trace-size  Max trace file size in bytes before deletion (default: 1GB)
#   --timeout         Max time in seconds per test before killing (default: 600 = 10 minutes)
#   --filter          Package filter for tracing (e.g., "org.apache.commons.math3")
#   --compress        Compress log files with gzip after generation
#   --cleanup         Remove working directories after completion
#   --skip-pass       Skip running passing tests (only run failing tests)
#   -h, --help        Show this help message
#
# Example:
#   ./generate_traces.sh -p Math -b 1 --compress
#   ./generate_traces.sh -p Math -b 1 --max-pass 50 --filter "org.apache.commons.math3"
#   ./generate_traces.sh -p Math -b 1 --max-subtests 20 --max-trace-size 536870912
#   ./generate_traces.sh -p Math -b 1 --timeout 300 --skip-pass
#

set -e

# Default values
PROJECT=""
BUG_ID=""
WORK_DIR="/workspace"
OUTPUT_DIR="/workspace/traces"
MAX_PASS=0
MAX_SUBTESTS=30
MAX_TRACE_SIZE=1073741824  # 1GB in bytes
TIMEOUT=600  # 10 minutes default
FILTER=""
COMPRESS=false
CLEANUP=false
SKIP_PASS=false

# Script directories
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
D4J_HOME="${D4J_HOME:-/defects4j}"
TRACE_AGENT="${D4J_HOME}/framework/lib/trace-agent/trace-agent.jar"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to count @Test methods in a Java test class
count_test_methods() {
    local test_class="$1"
    local base_dir="$2"
    
    # Get test source directory (cache it to avoid repeated calls)
    if [ -z "$CACHED_TEST_SRC_DIR" ]; then
        CACHED_TEST_SRC_DIR=$(defects4j export -p dir.src.tests 2>/dev/null | head -1 | tr -d '[:space:]')
        [ -z "$CACHED_TEST_SRC_DIR" ] && CACHED_TEST_SRC_DIR="src/test/java"
    fi
    local test_src_dir="$CACHED_TEST_SRC_DIR"
    
    # Convert class name to file path
    local file_path="${base_dir}/${test_src_dir}/${test_class//./\/}.java"
    
    if [ ! -f "$file_path" ]; then
        # Try to find the file
        local class_simple_name="${test_class##*.}"
        file_path=$(find "$base_dir" -name "${class_simple_name}.java" -type f 2>/dev/null | head -1 | tr -d '[:space:]')
    fi
    
    if [ -f "$file_path" ]; then
        # Count @Test annotations - ensure clean integer output
        local count
        count=$(grep -c '@Test' "$file_path" 2>/dev/null || echo "0")
        # Strip all whitespace and ensure it's a valid number
        count=$(echo "$count" | tr -d '[:space:]')
        # Validate it's a number, default to 0 if not
        if [[ "$count" =~ ^[0-9]+$ ]]; then
            echo "$count"
        else
            echo "0"
        fi
    else
        echo "0"
    fi
}

show_help() {
    head -30 "$0" | tail -25 | sed 's/^#//'
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -p|--project)
            PROJECT="$2"
            shift 2
            ;;
        -b|--bug)
            BUG_ID="$2"
            shift 2
            ;;
        -w|--workdir)
            WORK_DIR="$2"
            shift 2
            ;;
        -o|--output)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        --max-pass)
            MAX_PASS="$2"
            shift 2
            ;;
        --max-subtests)
            MAX_SUBTESTS="$2"
            shift 2
            ;;
        --max-trace-size)
            MAX_TRACE_SIZE="$2"
            shift 2
            ;;
        --timeout)
            TIMEOUT="$2"
            shift 2
            ;;
        --filter)
            FILTER="$2"
            shift 2
            ;;
        --compress)
            COMPRESS=true
            shift
            ;;
        --cleanup)
            CLEANUP=true
            shift
            ;;
        --skip-pass)
            SKIP_PASS=true
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Validate required arguments
if [ -z "$PROJECT" ] || [ -z "$BUG_ID" ]; then
    log_error "Project and Bug ID are required!"
    show_help
    exit 1
fi

# Validate trace agent exists
if [ ! -f "$TRACE_AGENT" ]; then
    log_error "Trace agent not found: $TRACE_AGENT"
    log_error "Please build the trace agent first:"
    log_error "  cd ${D4J_HOME}/framework/lib/trace-agent && bash build.sh"
    exit 1
fi

# Setup directories
BUGGY_DIR="${WORK_DIR}/${PROJECT}_${BUG_ID}_buggy"
FIXED_DIR="${WORK_DIR}/${PROJECT}_${BUG_ID}_fixed"
TRACE_OUTPUT_DIR="${OUTPUT_DIR}/${PROJECT}-${BUG_ID}"
FAIL_DIR="${TRACE_OUTPUT_DIR}/fail"
PASS_DIR="${TRACE_OUTPUT_DIR}/pass"

log_info "=========================================="
log_info "Generating traces for ${PROJECT}-${BUG_ID}"
log_info "=========================================="
log_info "Working directory: ${WORK_DIR}"
log_info "Output directory: ${TRACE_OUTPUT_DIR}"
log_info "Trace agent: ${TRACE_AGENT}"
log_info "Max trace size: $((MAX_TRACE_SIZE / 1024 / 1024))MB"
log_info "Test timeout: ${TIMEOUT} seconds"
[ -n "$FILTER" ] && log_info "Package filter: ${FILTER}"
[ "$COMPRESS" = true ] && log_info "Compression: enabled"

# Create output directories
mkdir -p "$FAIL_DIR"
mkdir -p "$PASS_DIR"

# Record start time
START_TIME=$(date +%s)
START_TIME_ISO=$(date -Iseconds)
log_info "Started at: ${START_TIME_ISO}"

# Step 1: Checkout buggy version
log_info "[Step 1/7] Checking out buggy version..."
if [ -d "$BUGGY_DIR" ]; then
    log_warn "Buggy directory already exists, removing..."
    rm -rf "$BUGGY_DIR"
fi
defects4j checkout -p "$PROJECT" -v "${BUG_ID}b" -w "$BUGGY_DIR"

# Step 2: Compile buggy version
log_info "[Step 2/7] Compiling buggy version..."
cd "$BUGGY_DIR"
defects4j compile

# Step 3: Get test information
log_info "[Step 3/7] Getting test information..."
TRIGGER_TESTS=$(defects4j export -p tests.trigger)
ALL_TESTS=$(defects4j export -p tests.all)

# Save test lists for reference
echo "$TRIGGER_TESTS" > "${TRACE_OUTPUT_DIR}/tests_trigger.txt"
echo "$ALL_TESTS" > "${TRACE_OUTPUT_DIR}/tests_all.txt"

TRIGGER_COUNT=$(echo "$TRIGGER_TESTS" | grep -c "." || echo "0")
ALL_COUNT=$(echo "$ALL_TESTS" | grep -c "." || echo "0")
log_info "Trigger tests: ${TRIGGER_COUNT}"
log_info "All tests: ${ALL_COUNT}"

# Step 4: Get classpath and prepare for traced execution
log_info "[Step 4/7] Preparing traced execution environment..."
TEST_CP=$(defects4j export -p cp.test)
CLASSES_DIR=$(defects4j export -p dir.bin.classes)
TESTS_DIR=$(defects4j export -p dir.bin.tests)

# Build agent arguments
AGENT_ARGS=""
if [ -n "$FILTER" ]; then
    AGENT_ARGS="filter=${FILTER}"
fi

# Step 5: Run failing tests with tracing
log_info "[Step 5/7] Running failing tests with tracing..."
log_info "  Max subtests threshold: ${MAX_SUBTESTS}"
log_info "  Max trace size: $((MAX_TRACE_SIZE / 1024 / 1024))MB"
log_info "  Test timeout: ${TIMEOUT} seconds"
FAIL_COUNT=0
FAIL_SKIPPED_SIZE=0
FAIL_SKIPPED_TIMEOUT=0
FAIL_FULL_CLASS_COUNT=0
FAIL_SINGLE_METHOD_COUNT=0
FAIL_SINGLE_METHOD_TESTS=""
FAIL_SKIPPED_SIZE_TESTS=""
FAIL_SKIPPED_TIMEOUT_TESTS=""

while IFS= read -r test; do
    [ -z "$test" ] && continue
    
    # Parse test class and method
    TEST_CLASS=$(echo "$test" | cut -d':' -f1)
    TEST_METHOD=$(echo "$test" | cut -d':' -f3)
    
    # Count test methods in the class
    SUBTEST_COUNT=$(count_test_methods "$TEST_CLASS" "$BUGGY_DIR")
    log_info "  Test class: ${TEST_CLASS} (${SUBTEST_COUNT} @Test methods)"
    
    # Determine run mode
    RUN_MODE="class"  # default: run whole class
    if [ "$SUBTEST_COUNT" -gt "$MAX_SUBTESTS" ]; then
        if [ -n "$TEST_METHOD" ]; then
            RUN_MODE="method"
            log_info "    → Subtest count (${SUBTEST_COUNT}) > threshold (${MAX_SUBTESTS}), running single method: ${TEST_METHOD}"
        else
            log_warn "    → Subtest count (${SUBTEST_COUNT}) > threshold (${MAX_SUBTESTS}), but no method specified, running whole class"
        fi
    fi
    
    # Create safe filename
    if [ "$RUN_MODE" = "method" ]; then
        SAFE_NAME=$(echo "${TEST_CLASS}_${TEST_METHOD}" | tr '.:' '_')
    else
        SAFE_NAME=$(echo "${TEST_CLASS}" | tr '.:' '_')
    fi
    TRACE_FILE="${FAIL_DIR}/${SAFE_NAME}.log"
    
    log_info "  Running: ${test} (mode: ${RUN_MODE})"
    
    # Run test with trace agent (with timeout)
    cd "$BUGGY_DIR"
    TIMED_OUT=false
    if [ "$RUN_MODE" = "method" ]; then
        # Run single test method using SingleTestRunner
        timeout --signal=KILL ${TIMEOUT} java -javaagent:"${TRACE_AGENT}${AGENT_ARGS:+=$AGENT_ARGS}" \
             -Dtrace.output="$TRACE_FILE" \
             -cp "${TRACE_AGENT}:${TEST_CP}" \
             edu.defects4j.trace.SingleTestRunner "$TEST_CLASS" "$TEST_METHOD" \
             2>/dev/null || {
            EXIT_CODE=$?
            if [ $EXIT_CODE -eq 137 ] || [ $EXIT_CODE -eq 124 ]; then
                TIMED_OUT=true
            fi
        }
    else
        # Run whole test class with JUnitCore
        timeout --signal=KILL ${TIMEOUT} java -javaagent:"${TRACE_AGENT}${AGENT_ARGS:+=$AGENT_ARGS}" \
             -Dtrace.output="$TRACE_FILE" \
             -cp "${TRACE_AGENT}:${TEST_CP}" \
             org.junit.runner.JUnitCore "$TEST_CLASS" \
             2>/dev/null || {
            EXIT_CODE=$?
            if [ $EXIT_CODE -eq 137 ] || [ $EXIT_CODE -eq 124 ]; then
                TIMED_OUT=true
            fi
        }
    fi
    
    # Handle timeout
    if [ "$TIMED_OUT" = true ]; then
        log_warn "    → Test timed out after ${TIMEOUT}s, skipping: ${test}"
        rm -f "$TRACE_FILE"
        FAIL_SKIPPED_TIMEOUT=$((FAIL_SKIPPED_TIMEOUT + 1))
        FAIL_SKIPPED_TIMEOUT_TESTS="${FAIL_SKIPPED_TIMEOUT_TESTS}${test}\n"
        continue
    fi
    
    # Check if trace was generated
    if [ -f "$TRACE_FILE" ]; then
        TRACE_SIZE=$(stat -c%s "$TRACE_FILE" 2>/dev/null || stat -f%z "$TRACE_FILE" 2>/dev/null)
        TRACE_SIZE_MB=$((TRACE_SIZE / 1024 / 1024))
        
        # Check if trace exceeds max size
        if [ "$TRACE_SIZE" -gt "$MAX_TRACE_SIZE" ]; then
            log_warn "    → Trace too large (${TRACE_SIZE_MB}MB > $((MAX_TRACE_SIZE / 1024 / 1024))MB), removing: $(basename "$TRACE_FILE")"
            rm -f "$TRACE_FILE"
            FAIL_SKIPPED_SIZE=$((FAIL_SKIPPED_SIZE + 1))
            FAIL_SKIPPED_SIZE_TESTS="${FAIL_SKIPPED_SIZE_TESTS}${test}\n"
        else
            FAIL_COUNT=$((FAIL_COUNT + 1))
            log_info "    → Trace saved: $(basename "$TRACE_FILE") (${TRACE_SIZE_MB}MB)"
            
            # Track run mode
            if [ "$RUN_MODE" = "method" ]; then
                FAIL_SINGLE_METHOD_COUNT=$((FAIL_SINGLE_METHOD_COUNT + 1))
                FAIL_SINGLE_METHOD_TESTS="${FAIL_SINGLE_METHOD_TESTS}${test}\n"
            else
                FAIL_FULL_CLASS_COUNT=$((FAIL_FULL_CLASS_COUNT + 1))
            fi
        fi
    else
        log_warn "    → No trace generated"
    fi
done <<< "$TRIGGER_TESTS"

log_info "Completed ${FAIL_COUNT} failing test traces (full: ${FAIL_FULL_CLASS_COUNT}, single: ${FAIL_SINGLE_METHOD_COUNT}, skipped-size: ${FAIL_SKIPPED_SIZE}, skipped-timeout: ${FAIL_SKIPPED_TIMEOUT})"

# Step 6: Run passing tests with tracing
if [ "$SKIP_PASS" = false ]; then
    log_info "[Step 6/7] Running passing tests with tracing..."
    log_info "  Max subtests threshold: ${MAX_SUBTESTS}"
    
    # Get list of passing tests (exclude trigger tests)
    PASS_TESTS=""
    while IFS= read -r test; do
        [ -z "$test" ] && continue
        # Check if this test is in trigger tests (it's a class, not method)
        IS_TRIGGER=false
        while IFS= read -r trigger; do
            TRIGGER_CLASS=$(echo "$trigger" | cut -d':' -f1)
            if [ "$test" = "$TRIGGER_CLASS" ]; then
                IS_TRIGGER=true
                break
            fi
        done <<< "$TRIGGER_TESTS"
        
        if [ "$IS_TRIGGER" = false ]; then
            PASS_TESTS="${PASS_TESTS}${test}"$'\n'
        fi
    done <<< "$ALL_TESTS"
    
    # Random sample if max-pass is set
    if [ "$MAX_PASS" -gt 0 ]; then
        PASS_TESTS=$(echo "$PASS_TESTS" | grep -v "^$" | shuf -n "$MAX_PASS")
        log_info "Sampled ${MAX_PASS} passing tests"
    fi
    
    PASS_COUNT=0
    PASS_SKIPPED_SUBTESTS=0
    PASS_SKIPPED_SIZE=0
    PASS_SKIPPED_TIMEOUT=0
    PASS_SKIPPED_SIZE_TESTS=""
    PASS_SKIPPED_TIMEOUT_TESTS=""
    
    while IFS= read -r test_class; do
        [ -z "$test_class" ] && continue
        
        # Count test methods in the class
        SUBTEST_COUNT=$(count_test_methods "$test_class" "$BUGGY_DIR")
        
        # Skip if too many subtests
        if [ "$SUBTEST_COUNT" -gt "$MAX_SUBTESTS" ]; then
            log_info "  Skipping: ${test_class} (${SUBTEST_COUNT} subtests > threshold ${MAX_SUBTESTS})"
            PASS_SKIPPED_SUBTESTS=$((PASS_SKIPPED_SUBTESTS + 1))
            continue
        fi
        
        SAFE_NAME=$(echo "$test_class" | tr '.' '_')
        TRACE_FILE="${PASS_DIR}/${SAFE_NAME}.log"
        
        log_info "  Running: ${test_class} (${SUBTEST_COUNT} subtests)"
        
        cd "$BUGGY_DIR"
        TIMED_OUT=false
        timeout --signal=KILL ${TIMEOUT} java -javaagent:"${TRACE_AGENT}${AGENT_ARGS:+=$AGENT_ARGS}" \
             -Dtrace.output="$TRACE_FILE" \
             -cp "${TRACE_AGENT}:${TEST_CP}" \
             org.junit.runner.JUnitCore "$test_class" \
             2>/dev/null || {
            EXIT_CODE=$?
            if [ $EXIT_CODE -eq 137 ] || [ $EXIT_CODE -eq 124 ]; then
                TIMED_OUT=true
            fi
        }
        
        # Handle timeout
        if [ "$TIMED_OUT" = true ]; then
            log_warn "    → Test timed out after ${TIMEOUT}s, skipping: ${test_class}"
            rm -f "$TRACE_FILE"
            PASS_SKIPPED_TIMEOUT=$((PASS_SKIPPED_TIMEOUT + 1))
            PASS_SKIPPED_TIMEOUT_TESTS="${PASS_SKIPPED_TIMEOUT_TESTS}${test_class}\n"
            continue
        fi
        
        if [ -f "$TRACE_FILE" ]; then
            TRACE_SIZE=$(stat -c%s "$TRACE_FILE" 2>/dev/null || stat -f%z "$TRACE_FILE" 2>/dev/null)
            TRACE_SIZE_MB=$((TRACE_SIZE / 1024 / 1024))
            
            # Check if trace exceeds max size
            if [ "$TRACE_SIZE" -gt "$MAX_TRACE_SIZE" ]; then
                log_warn "    → Trace too large (${TRACE_SIZE_MB}MB > $((MAX_TRACE_SIZE / 1024 / 1024))MB), removing"
                rm -f "$TRACE_FILE"
                PASS_SKIPPED_SIZE=$((PASS_SKIPPED_SIZE + 1))
                PASS_SKIPPED_SIZE_TESTS="${PASS_SKIPPED_SIZE_TESTS}${test_class}\n"
            else
                PASS_COUNT=$((PASS_COUNT + 1))
                [ "$TRACE_SIZE_MB" -gt 0 ] && log_info "    → Trace saved (${TRACE_SIZE_MB}MB)"
            fi
        fi
    done <<< "$PASS_TESTS"
    
    log_info "Completed ${PASS_COUNT} passing test traces (skipped: ${PASS_SKIPPED_SUBTESTS} large classes, ${PASS_SKIPPED_SIZE} oversized traces, ${PASS_SKIPPED_TIMEOUT} timeouts)"
else
    log_info "[Step 6/7] Skipping passing tests (--skip-pass)"
fi

# Step 7: Checkout fixed version and generate ground truth
log_info "[Step 7/7] Checking out fixed version and generating ground truth..."
if [ -d "$FIXED_DIR" ]; then
    rm -rf "$FIXED_DIR"
fi
defects4j checkout -p "$PROJECT" -v "${BUG_ID}f" -w "$FIXED_DIR"

# Generate ground truth
python3 "${D4J_HOME}/framework/util/generate_ground_truth.py" \
    -p "$PROJECT" \
    -b "$BUG_ID" \
    --buggy-dir "$BUGGY_DIR" \
    --fixed-dir "$FIXED_DIR" \
    -o "${TRACE_OUTPUT_DIR}/ground-truth.json"

log_info "Ground truth saved to: ${TRACE_OUTPUT_DIR}/ground-truth.json"

# Calculate elapsed time
END_TIME=$(date +%s)
END_TIME_ISO=$(date -Iseconds)
ELAPSED_SECONDS=$((END_TIME - START_TIME))
ELAPSED_MINUTES=$((ELAPSED_SECONDS / 60))
ELAPSED_REMAINING_SECONDS=$((ELAPSED_SECONDS % 60))
log_info "Execution time: ${ELAPSED_MINUTES}m ${ELAPSED_REMAINING_SECONDS}s (${ELAPSED_SECONDS} seconds total)"

# Generate metadata.json with trace execution info
log_info "Generating metadata.json..."

# Count trace files
FAIL_TRACE_COUNT=$(find "$FAIL_DIR" -name "*.log" -o -name "*.log.gz" 2>/dev/null | wc -l | tr -d '[:space:]')
PASS_TRACE_COUNT=$(find "$PASS_DIR" -name "*.log" -o -name "*.log.gz" 2>/dev/null | wc -l | tr -d '[:space:]')

# Calculate total size
FAIL_SIZE=$(du -sb "$FAIL_DIR" 2>/dev/null | cut -f1 || echo "0")
PASS_SIZE=$(du -sb "$PASS_DIR" 2>/dev/null | cut -f1 || echo "0")
TOTAL_SIZE=$((FAIL_SIZE + PASS_SIZE))

# Get trace file list
FAIL_FILES=$(find "$FAIL_DIR" -name "*.log" -o -name "*.log.gz" 2>/dev/null | xargs -I{} basename {} | sort | tr '\n' ',' | sed 's/,$//')
PASS_FILES=$(find "$PASS_DIR" -name "*.log" -o -name "*.log.gz" 2>/dev/null | xargs -I{} basename {} | sort | tr '\n' ',' | sed 's/,$//')

# Format skipped tests lists for JSON
FAIL_SKIPPED_SIZE_JSON=$(echo -e "$FAIL_SKIPPED_SIZE_TESTS" | grep -v '^$' | sed 's/^/"/;s/$/"/' | tr '\n' ',' | sed 's/,$//')
PASS_SKIPPED_SIZE_JSON=$(echo -e "$PASS_SKIPPED_SIZE_TESTS" | grep -v '^$' | sed 's/^/"/;s/$/"/' | tr '\n' ',' | sed 's/,$//')
FAIL_SINGLE_METHOD_JSON=$(echo -e "$FAIL_SINGLE_METHOD_TESTS" | grep -v '^$' | sed 's/^/"/;s/$/"/' | tr '\n' ',' | sed 's/,$//')
FAIL_SKIPPED_TIMEOUT_JSON=$(echo -e "$FAIL_SKIPPED_TIMEOUT_TESTS" | grep -v '^$' | sed 's/^/"/;s/$/"/' | tr '\n' ',' | sed 's/,$//')
PASS_SKIPPED_TIMEOUT_JSON=$(echo -e "$PASS_SKIPPED_TIMEOUT_TESTS" | grep -v '^$' | sed 's/^/"/;s/$/"/' | tr '\n' ',' | sed 's/,$//')

cat > "${TRACE_OUTPUT_DIR}/metadata.json" << EOF
{
    "version": "${PROJECT}-${BUG_ID}",
    "project_id": "${PROJECT}",
    "bug_id": ${BUG_ID},
    "execution": {
        "max_subtests_threshold": ${MAX_SUBTESTS},
        "max_trace_size_bytes": ${MAX_TRACE_SIZE},
        "timeout_seconds": ${TIMEOUT},
        "max_pass_tests": ${MAX_PASS},
        "compression_enabled": ${COMPRESS},
        "package_filter": "${FILTER}"
    },
    "traces": {
        "fail": {
            "count": ${FAIL_TRACE_COUNT:-0},
            "size_bytes": ${FAIL_SIZE},
            "run_mode": {
                "full_class_count": ${FAIL_FULL_CLASS_COUNT:-0},
                "single_method_count": ${FAIL_SINGLE_METHOD_COUNT:-0},
                "single_method_tests": [${FAIL_SINGLE_METHOD_JSON}]
            },
            "skipped_oversized": {
                "count": ${FAIL_SKIPPED_SIZE:-0},
                "tests": [${FAIL_SKIPPED_SIZE_JSON}]
            },
            "skipped_timeout": {
                "count": ${FAIL_SKIPPED_TIMEOUT:-0},
                "tests": [${FAIL_SKIPPED_TIMEOUT_JSON}]
            },
            "files": [$(echo "$FAIL_FILES" | sed 's/,/", "/g' | sed 's/^/"/' | sed 's/$/"/' | sed 's/""//' )]
        },
        "pass": {
            "count": ${PASS_TRACE_COUNT:-0},
            "size_bytes": ${PASS_SIZE},
            "skipped_large_classes": ${PASS_SKIPPED_SUBTESTS:-0},
            "skipped_oversized": {
                "count": ${PASS_SKIPPED_SIZE:-0},
                "tests": [${PASS_SKIPPED_SIZE_JSON}]
            },
            "skipped_timeout": {
                "count": ${PASS_SKIPPED_TIMEOUT:-0},
                "tests": [${PASS_SKIPPED_TIMEOUT_JSON}]
            },
            "files": [$(echo "$PASS_FILES" | sed 's/,/", "/g' | sed 's/^/"/' | sed 's/$/"/' | sed 's/""//' )]
        },
        "total_size_bytes": ${TOTAL_SIZE}
    },
    "paths": {
        "buggy_dir": "${BUGGY_DIR}",
        "fixed_dir": "${FIXED_DIR}",
        "trace_output_dir": "${TRACE_OUTPUT_DIR}"
    },
    "timing": {
        "started_at": "${START_TIME_ISO}",
        "finished_at": "${END_TIME_ISO}",
        "elapsed_seconds": ${ELAPSED_SECONDS}
    },
    "generated_at": "$(date -Iseconds)"
}
EOF

log_info "Metadata saved to: ${TRACE_OUTPUT_DIR}/metadata.json"

# Compress logs if requested
if [ "$COMPRESS" = true ]; then
    log_info "Compressing log files..."
    find "$FAIL_DIR" -name "*.log" -exec gzip {} \;
    find "$PASS_DIR" -name "*.log" -exec gzip {} \;
    log_info "Compression complete"
fi

# Cleanup working directories if requested
if [ "$CLEANUP" = true ]; then
    log_info "Cleaning up working directories..."
    rm -rf "$BUGGY_DIR" "$FIXED_DIR"
    log_info "Cleanup complete"
fi

# Summary
log_info "=========================================="
log_info "Trace generation complete!"
log_info "=========================================="
log_info "Output directory: ${TRACE_OUTPUT_DIR}"
log_info "Failing test traces: ${FAIL_COUNT} (full: ${FAIL_FULL_CLASS_COUNT:-0}, single: ${FAIL_SINGLE_METHOD_COUNT:-0}, skipped-size: ${FAIL_SKIPPED_SIZE:-0}, skipped-timeout: ${FAIL_SKIPPED_TIMEOUT:-0})"
[ "$SKIP_PASS" = false ] && log_info "Passing test traces: ${PASS_COUNT} (skipped-subtests: ${PASS_SKIPPED_SUBTESTS:-0}, skipped-size: ${PASS_SKIPPED_SIZE:-0}, skipped-timeout: ${PASS_SKIPPED_TIMEOUT:-0})"
log_info "Max subtests threshold: ${MAX_SUBTESTS}"
log_info "Max trace size: $((MAX_TRACE_SIZE / 1024 / 1024))MB"
log_info "Test timeout: ${TIMEOUT}s"
log_info "Execution time: ${ELAPSED_MINUTES}m ${ELAPSED_REMAINING_SECONDS}s"
log_info "Ground truth: ${TRACE_OUTPUT_DIR}/ground-truth.json"
log_info "Metadata: ${TRACE_OUTPUT_DIR}/metadata.json"

# List output files
log_info ""
log_info "Files generated:"
ls -la "${TRACE_OUTPUT_DIR}/"
