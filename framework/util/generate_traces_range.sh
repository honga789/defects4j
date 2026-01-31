#!/bin/bash
#
# generate_traces_range.sh - Run generate_traces.sh for a range of bug IDs
#
# Usage: ./generate_traces_range.sh -p <project> --bug-start <start> --bug-end <end> [options]
#
# Required Options:
#   -p, --project     Project ID (e.g., Math, Lang, Chart)
#   --bug-start       Starting bug ID
#   --bug-end         Ending bug ID
#
# Optional (same as generate_traces.sh):
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
#   ./generate_traces_range.sh -p Math --bug-start 1 --bug-end 10
#   ./generate_traces_range.sh -p Math --bug-start 1 --bug-end 5 --max-pass 50 --compress --cleanup
#

set -e

# Default values (same as generate_traces.sh)
PROJECT=""
BUG_START=""
BUG_END=""
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

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -p|--project)
            PROJECT="$2"
            shift 2
            ;;
        --bug-start)
            BUG_START="$2"
            shift 2
            ;;
        --bug-end)
            BUG_END="$2"
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
            head -33 "$0" | tail -28 | sed 's/^#//'
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use -h or --help for usage information"
            exit 1
            ;;
    esac
done

# Validate required arguments
if [ -z "$PROJECT" ]; then
    echo "Error: Project name is required (-p)"
    exit 1
fi

if [ -z "$BUG_START" ]; then
    echo "Error: Starting bug ID is required (--bug-start)"
    exit 1
fi

if [ -z "$BUG_END" ]; then
    echo "Error: Ending bug ID is required (--bug-end)"
    exit 1
fi

if [ "$BUG_START" -gt "$BUG_END" ]; then
    echo "Error: Starting bug ID must be less than or equal to ending bug ID"
    exit 1
fi

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Create log file in defects4j workspace
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
LOG_FILE="logs_generate_traces_${PROJECT}_${BUG_START}_to_${BUG_END}_${TIMESTAMP}.log"

# Build base command arguments
CMD_ARGS="-p $PROJECT"
[ -n "$WORK_DIR" ] && CMD_ARGS="$CMD_ARGS -w $WORK_DIR"
[ -n "$OUTPUT_DIR" ] && CMD_ARGS="$CMD_ARGS -o $OUTPUT_DIR"
[ "$MAX_PASS" != "0" ] && CMD_ARGS="$CMD_ARGS --max-pass $MAX_PASS"
[ "$MAX_SUBTESTS" != "30" ] && CMD_ARGS="$CMD_ARGS --max-subtests $MAX_SUBTESTS"
[ "$MAX_TRACE_SIZE" != "1073741824" ] && CMD_ARGS="$CMD_ARGS --max-trace-size $MAX_TRACE_SIZE"
[ "$TIMEOUT" != "600" ] && CMD_ARGS="$CMD_ARGS --timeout $TIMEOUT"
[ -n "$FILTER" ] && CMD_ARGS="$CMD_ARGS --filter $FILTER"
[ "$COMPRESS" = true ] && CMD_ARGS="$CMD_ARGS --compress"
[ "$CLEANUP" = true ] && CMD_ARGS="$CMD_ARGS --cleanup"
[ "$SKIP_PASS" = true ] && CMD_ARGS="$CMD_ARGS --skip-pass"

echo "========================================" | tee "$LOG_FILE"
echo "Generate Traces Range: $PROJECT bugs $BUG_START to $BUG_END" | tee -a "$LOG_FILE"
echo "Log file: $LOG_FILE" | tee -a "$LOG_FILE"
echo "========================================" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

# Loop through bug range
for BUG_ID in $(seq $BUG_START $BUG_END); do
    echo "========================================" | tee -a "$LOG_FILE"
    echo "Processing $PROJECT Bug #$BUG_ID" | tee -a "$LOG_FILE"
    echo "Started at: $(date)" | tee -a "$LOG_FILE"
    echo "========================================" | tee -a "$LOG_FILE"
    
    # Run generate_traces.sh and capture all output
    bash "$SCRIPT_DIR/generate_traces.sh" $CMD_ARGS -b "$BUG_ID" 2>&1 | tee -a "$LOG_FILE"
    
    echo "" | tee -a "$LOG_FILE"
    echo "Finished $PROJECT Bug #$BUG_ID at: $(date)" | tee -a "$LOG_FILE"
    echo "" | tee -a "$LOG_FILE"
done

echo "========================================" | tee -a "$LOG_FILE"
echo "All bugs processed" | tee -a "$LOG_FILE"
echo "Log saved to: $LOG_FILE" | tee -a "$LOG_FILE"
echo "========================================" | tee -a "$LOG_FILE"

exit 0
