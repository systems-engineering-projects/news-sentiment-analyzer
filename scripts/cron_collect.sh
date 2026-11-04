#!/bin/bash
# Wrapper script for daily news collection cron job

# Change to the repo root, next to this script
cd "$(dirname "$0")/.."

# Activate virtual environment
source .venv/bin/activate

# Run the collector
python scripts/run_collector.py

# Exit with the script's exit code
exit $?