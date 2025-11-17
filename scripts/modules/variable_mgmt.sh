ENV_FILE_NAME="./.temp.infra.env"

prompt_variable() {
    INPUT_PROMPT=$1
    VARIABLE_NAME=$2

    validate_params "prompt_variable" "$INPUT_PROMPT" "$VARIABLE_NAME" || return 1

    check_existing_value "$VARIABLE_NAME" && return 0

    ensure_env_file_exists || return 1

    read -rp "$INPUT_PROMPT" VARIABLE_VALUE
    while [[ -z "$VARIABLE_VALUE" ]]; do
        read -rp "$VARIABLE_NAME cannot be empty. Please enter a valid $VARIABLE_NAME: " VARIABLE_VALUE
    done

    set_variable "$VARIABLE_NAME" "$VARIABLE_VALUE"
}

prompt_y_or_n() {
    INPUT_PROMPT=$1
    VARIABLE_NAME=$2

    validate_params "prompt_y_or_n" "$INPUT_PROMPT" "$VARIABLE_NAME" || return 1

    check_existing_value "$VARIABLE_NAME" && return 0

    ensure_env_file_exists || return 1

    while true; do
        read -rp "$INPUT_PROMPT" VARIABLE_VALUE
        VARIABLE_VALUE=$(echo "$VARIABLE_VALUE" | tr '[:upper:]' '[:lower:]')
        if [[ "$VARIABLE_VALUE" =~ ^[yn]$ ]]; then
            break
        fi
        echo "Invalid response. Please enter 'y' or 'n'." >&2
    done

    set_variable "$VARIABLE_NAME" "$VARIABLE_VALUE"
}
check_existing_value() {
    local VARIABLE_NAME=$1
    
    eval "EXISTING_VALUE=\${$VARIABLE_NAME}"
    if [ -n "$EXISTING_VALUE" ]; then
        echo "$EXISTING_VALUE"
        return 0
    fi
    
    return 1
}

ensure_env_file_exists() {
    if [ ! -f "$ENV_FILE_NAME" ]; then
        touch "$ENV_FILE_NAME"
        if [ $? -ne 0 ]; then
            echo "error: Failed to create env file: $ENV_FILE_NAME" >&2
            return 1
        fi
    fi
    return 0
}

set_variable() {
    VARIABLE_NAME=$1
    VARIABLE_VALUE=$2

    check_existing_value "$VARIABLE_NAME" && return 0

    echo "$VARIABLE_NAME=$VARIABLE_VALUE" >> "$ENV_FILE_NAME"
    echo "$VARIABLE_VALUE"
}

validate_params() {
    local FUNCTION_NAME=$1
    local INPUT_PROMPT=$2
    local VARIABLE_NAME=$3

    if [ -z "$INPUT_PROMPT" ]; then
        echo "error $FUNCTION_NAME: No Input Prompt for Variable passed" >&2
        return 1
    fi

    if [ -z "$VARIABLE_NAME" ]; then
        echo "error $FUNCTION_NAME: No Variable name provided" >&2
        return 1
    fi

    return 0
}

load_env() {
    if [ -f "$ENV_FILE_NAME" ]; then
        while true; do
            read -rp "There are saved parameters from a previous run, would you like me to load those? (y/n): " response
            response=$(echo "$response" | tr '[:upper:]' '[:lower:]')
            
            if [[ "$response" == "y" ]]; then
                # Load the environment variables
                set -a
                source "$ENV_FILE_NAME"
                set +a
                echo "Environment variables loaded from $ENV_FILE_NAME"
                LOADED_ENV="true"
                return 0
            elif [[ "$response" == "n" ]]; then
                rm "$ENV_FILE_NAME"
                echo "Previous parameters deleted."
                LOADED_ENV="false"
                return 0
            else
                echo "Invalid response. Please enter 'y' or 'n'."
            fi
        done
    fi
    
    return 0
}
update_env_var() {
  local VAR_NAME="$1"
  local VAR_VALUE="$2"

  # Create file if it doesn't exist
  if [[ ! -f "$ENV_FILE_NAME" ]]; then
    touch "$ENV_FILE_NAME"
  fi

  # Check if variable exists in file
  if grep -q "^${VAR_NAME}=" "$ENV_FILE_NAME"; then
    # Update existing entry (handles special characters in value)
    sed -i "s|^${VAR_NAME}=.*|${VAR_NAME}=${VAR_VALUE}|" "$ENV_FILE_NAME"
  else
    # Append new entry
    echo "${VAR_NAME}=${VAR_VALUE}" >> "$ENV_FILE_NAME"
  fi
}