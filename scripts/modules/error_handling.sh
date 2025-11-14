# --- ERROR HANDLER ---
# This function will be called whenever an error occurs
error_handler() {
    local exit_code=$?
    local line_number=$1
    
    log_error "Script failed at line $line_number with exit code $exit_code"
    
    # Call capture_configuration if it exists
    if declare -f capture_configuration > /dev/null; then
        log_info "Capturing configuration for debugging..."
        capture_configuration 2>/dev/null || log_error "Failed to capture configuration"
    fi
    
    log_error "Check the log file for details: $LOG_FILE"
    exit $exit_code
}