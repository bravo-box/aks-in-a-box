#!/bin/bash

# Color codes
readonly COLOR_RED='\033[0;31m'
readonly COLOR_GREEN='\033[0;32m'
readonly COLOR_YELLOW='\033[0;33m'
readonly COLOR_BLUE='\033[0;34m'
readonly COLOR_MAGENTA='\033[0;35m'
readonly COLOR_CYAN='\033[0;36m'
readonly COLOR_WHITE='\033[0;37m'
readonly COLOR_RESET='\033[0m'

# Log file variable (will be set by init_log_file)
LOG_FILE=""

# Initialize log file
# Usage: init_log_file
# Creates a log file named after the main script with timestamp
init_log_file() {
    local script_name=$(basename "${BASH_SOURCE[-1]}" .sh)
    local timestamp=$(date +"%m.%d.%Y.%H.%M.%S")
    LOG_FILE="${script_name}-${timestamp}.log"
    
    # Create the log file with initial entry
    echo "Log started at $(date '+%Y-%m-%d %H:%M:%S')" > "$LOG_FILE"
}

# Log function
# Usage: log "message" "color_code"
# Example: log "Success!" "$COLOR_GREEN"
log() {
    local message="$1"
    local color="${2:-$COLOR_RESET}"
    
    echo -e "${color}${message}${COLOR_RESET}"
    log_to_file "$message"
}

# Log to file function
# Usage: log_to_file "message"
# Example: log_to_file "Operation completed successfully"
log_to_file() {
    local message="$1"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # Initialize log file if not already done
    if [[ -z "$LOG_FILE" ]]; then
        init_log_file
    fi
    
    echo "[${timestamp}] ${message}" >> "$LOG_FILE"
}

# Log info function (no color)
# Usage: log_info "message"
# Example: log_info "Processing data..."
log_info() {
    log "$1" "$COLOR_RESET"
}

log_success() {
    log "$1" "$COLOR_GREEN"
}

log_failure() {
    log "$1" "$COLOR_RED"
}

log_error() {
    log "ERROR: $1" "$COLOR_RED"
}

log_heading() {
    log "----------------------------------------------" "$COLOR_CYAN"
    log " $1" "$COLOR_CYAN"
    log "----------------------------------------------" "$COLOR_CYAN"
}