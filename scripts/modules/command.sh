# --- ERROR HANDLER FUNCTION ---
run_az_command() {
  local cmd="$1"
  local error_msg="${2:-Azure CLI command failed}"
  local output
  local exit_code
  
  # Capture stdout while allowing stderr to display on screen
  # This preserves visual indicators and progress messages
  log_to_file "Executing command: $cmd"
  output=$(eval "$cmd" 2>/dev/tty)
  exit_code=$?
  
  if [[ $exit_code -ne 0 ]]; then
    log_error "$error_msg"
    log_error "Command: $cmd"
    log_error "Exit code: $exit_code"
    log_error "Output: $output"
    capture_configuration
    return 1
  fi
  
  # Return output for commands that need it
  echo "$output"
}