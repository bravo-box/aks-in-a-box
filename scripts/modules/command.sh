# --- ERROR HANDLER FUNCTION ---
run_az_command() {
  local cmd="$1"
  local error_msg="${2:-Azure CLI command failed}"
  local output
  local exit_code
  
  # Capture stdout while allowing stderr to display on screen
  # This preserves visual indicators and progress messages
  log_to_file "Executing command: $cmd"
  
  # Check if we have a TTY available (interactive environment)
  if [[ -t 0 ]] && [[ -e /dev/tty ]]; then
    output=$(eval "$cmd" 2>/dev/tty)
  else
    # Non-interactive environment (like GitHub Actions), redirect to stderr
    output=$(eval "$cmd" 2>&2)
  fi
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