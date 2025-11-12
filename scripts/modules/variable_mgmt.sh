ENV_FILE_NAME="./.temp.infra.env"

set_variable() {
    VARIABLE_NAME=$1
    VARIABLE_VALUE=$2

    # Check if variable is already set in environment
    eval "EXISTING_VALUE=\${$VARIABLE_NAME}"
    if [ -n "$EXISTING_VALUE" ]; then
        echo "$EXISTING_VALUE"
        return 0
    fi

    echo "$VARIABLE_NAME=$VARIABLE_VALUE" >> "$ENV_FILE_NAME"
    echo "$VARIABLE_VALUE"
}

prompt_variable() {
    INPUT_PROMPT=$1
    VARIABLE_NAME=$2

    if [ -z "$INPUT_PROMPT" ]; then
        echo "error set_variable: No Input Prompt for Variable passed" >&2
        return 1
    fi

    if [ -z "$VARIABLE_NAME" ]; then
        echo "error set_variable: No Variable name provided" >&2
        return 1
    fi

    # Check if variable is already set in environment
    eval "EXISTING_VALUE=\${$VARIABLE_NAME}"
    if [ -n "$EXISTING_VALUE" ]; then
        echo "$EXISTING_VALUE"
        return 0
    fi

    if [ ! -f "$ENV_FILE_NAME" ]; then
        touch "$ENV_FILE_NAME"
        if [ $? -ne 0 ]; then
            echo "error set_variable: Failed to create env file: $ENV_FILE_NAME" >&2
            return 1
        fi
    fi

    read -rp "$INPUT_PROMPT" VARIABLE_VALUE
    while [[ -z "$VARIABLE_VALUE" ]]; do
      read -rp "$VARIABLE_NAME cannot be empty. Please enter a valid $VARIABLE_NAME: " VARIABLE_NAME
    done

    echo "$VARIABLE_NAME=$VARIABLE_VALUE" >> "$ENV_FILE_NAME"

    echo "$VARIABLE_VALUE"
}

prompt_y_or_n() {
    INPUT_PROMPT=$1
    VARIABLE_NAME=$2

    if [ -z "$INPUT_PROMPT" ]; then
        echo "error prompt_y_or_n: No Input Prompt for Variable passed" >&2
        return 1
    fi

    if [ -z "$VARIABLE_NAME" ]; then
        echo "error prompt_y_or_n: No Variable name provided" >&2
        return 1
    fi

    # Check if variable is already set in environment
    eval "EXISTING_VALUE=\${$VARIABLE_NAME}"
    if [ -n "$EXISTING_VALUE" ]; then
        echo "$EXISTING_VALUE"
        return 0
    fi

    if [ ! -f "$ENV_FILE_NAME" ]; then
        touch "$ENV_FILE_NAME"
        if [ $? -ne 0 ]; then
            echo "error prompt_y_or_n: Failed to create env file: $ENV_FILE_NAME" >&2
            return 1
        fi
    fi

    read -rp "$INPUT_PROMPT" VARIABLE_VALUE
    while [[ "$VARIABLE_VALUE" != "y" && "$VARIABLE_VALUE" != "Y" && "$VARIABLE_VALUE" != "n" && "$VARIABLE_VALUE" != "N" ]]; do
        read -rp "Invalid response. Please enter 'y' or 'n': " VARIABLE_VALUE
    done

    echo "$VARIABLE_NAME=$VARIABLE_VALUE" >> "$ENV_FILE_NAME"

    echo "$VARIABLE_VALUE"
}

load_env() {
    if [ -f "$ENV_FILE_NAME" ]; then
        while true; do
            read -rp "There are saved parameters from a previous run, would you like me to load those? (y/n): " response
            
            if [ "$response" = "y" ] || [ "$response" = "Y" ]; then
                # Load the environment variables
                set -a
                source "$ENV_FILE_NAME"
                set +a
                echo "Environment variables loaded from $ENV_FILE_NAME"
                LOADED_ENV="true"
                return 0
            elif [ "$response" = "n" ] || [ "$response" = "N" ]; then
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