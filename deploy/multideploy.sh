#!/usr/bin/env sh

################################################################################
# ACME.sh 3rd party deploy plugin for multiple (same) services
################################################################################
# Authors: tomo2403 (creator), https://github.com/tomo2403
# Updated: 2025-03-01
# Issues:  https://github.com/acmesh-official/acme.sh/issues and mention @tomo2403
################################################################################
# Usage (shown values are the examples):
# 1. Set optional environment variables
#   - export MULTIDEPLOY_FILENAME="multideploy.yaml"     - "multideploy.yml" will be automatically used if not set"
#
# 2. Run command:
# acme.sh --deploy --deploy-hook multideploy -d example.com
################################################################################
# Dependencies:
# - yq
################################################################################
# Return value:
# 0 means success, otherwise error.
################################################################################

MULTIDEPLOY_VERSION="1.0"

# Description: This function handles the deployment of certificates to multiple services.
#              It processes the provided certificate files and deploys them according to the
#              configuration specified in the multideploy file.
#
# Parameters:
#   _cdomain     - The domain name for which the certificate is issued.
#   _ckey        - The private key file for the certificate.
#   _ccert       - The certificate file.
#   _cca         - The CA (Certificate Authority) file.
#   _cfullchain  - The full chain certificate file.
#   _cpfx        - The PFX (Personal Information Exchange) file.
multideploy_deploy() {
  _cdomain="$1"
  _ckey="$2"
  _ccert="$3"
  _cca="$4"
  _cfullchain="$5"
  _cpfx="$6"

  _debug _cdomain "$_cdomain"
  _debug _ckey "$_ckey"
  _debug _ccert "$_ccert"
  _debug _cca "$_cca"
  _debug _cfullchain "$_cfullchain"
  _debug _cpfx "$_cpfx"

  MULTIDEPLOY_FILENAME="${MULTIDEPLOY_FILENAME:-$(_getdeployconf MULTIDEPLOY_FILENAME)}"
  if [ -z "$MULTIDEPLOY_FILENAME" ]; then
    MULTIDEPLOY_FILENAME="multideploy.yml"
    _info "MULTIDEPLOY_FILENAME is not set, so I will use 'multideploy.yml'."
  else
    _savedeployconf "MULTIDEPLOY_FILENAME" "$MULTIDEPLOY_FILENAME"
    _debug2 "MULTIDEPLOY_FILENAME" "$MULTIDEPLOY_FILENAME"
  fi

  if ! file=$(_preprocess_deployfile "$MULTIDEPLOY_FILENAME"); then
    _err "Failed to preprocess deploy file."
    return 1
  fi
  _debug3 "File" "$file"

  # Deploy to services
  _deploy_services "$file"
  _exitCode="$?"

  return "$_exitCode"
}

# Description:
#   This function preprocesses the deploy file by checking if 'yq' is installed,
#   verifying the existence of the deploy file, and ensuring only one deploy file is present.
# Arguments:
#   $@ - Posible deploy file names.
# Usage:
#   _preprocess_deployfile "<deploy_file1>" "<deploy_file2>?"
_preprocess_deployfile() {
  # Check if yq is installed
  if ! command -v yq >/dev/null 2>&1; then
    _err "yq is not installed! Please install yq and try again."
    return 1
  fi
  _debug3 "yq is installed."

  # Check if deploy file exists
  for file in "$@"; do
    _debug3 "Checking file" "$DOMAIN_PATH/$file"
    if [ -f "$DOMAIN_PATH/$file" ]; then
      _debug3 "File found"
      if [ -n "$found_file" ]; then
        _err "Multiple deploy files found. Please keep only one deploy file."
        return 1
      fi
      found_file="$file"
    else
      _debug3 "File not found"
    fi
  done

  if [ -z "$found_file" ]; then
    _err "Deploy file not found. Go to https://github.com/acmesh-official/acme.sh/wiki/deployhooks#36-deploying-to-multiple-services-with-the-same-hooks to see how to create one."
    return 1
  fi
  if ! _check_deployfile "$DOMAIN_PATH/$found_file"; then
    _err "Deploy file is not valid: $DOMAIN_PATH/$found_file"
    return 1
  fi

  echo "$DOMAIN_PATH/$found_file"
}

# Description:
#   This function checks the deploy file for version compatibility and the existence of the specified configuration and services.
# Arguments:
#   $1 - The path to the deploy configuration file.
#   $2 - The name of the deploy configuration to use.
# Usage:
#   _check_deployfile "<deploy_file_path>"
_check_deployfile() {
  _deploy_file="$1"
  _debug2 "check: Deploy file" "$_deploy_file"

  # Check version
  _deploy_file_version=$(yq -r '.version' "$_deploy_file")
  if [ "$MULTIDEPLOY_VERSION" != "$_deploy_file_version" ]; then
    _err "As of $PROJECT_NAME $VER, the deploy file needs version $MULTIDEPLOY_VERSION! Your current deploy file is of version $_deploy_file_version."
    return 1
  fi
  _debug2 "check: Deploy file version is compatible: $_deploy_file_version"

  # Extract all services from config
  _services=$(yq -r '.services[].name' "$_deploy_file")

  if [ -z "$_services" ]; then
    _err "Config does not have any services to deploy to."
    return 1
  fi
  _debug2 "check: Config has services."
  echo "$_services" | while read -r _service; do
    _debug3 " - $_service"
  done

  # Check if extracted services exist in services list
  echo "$_services" | while read -r _service; do
    _debug2 "check: Checking service: $_service"
    # Check if service exists
    _service_config=$(yq -r ".services[] | select(.name == \"$_service\")" "$_deploy_file")
    if [ -z "$_service_config" ] || [ "$_service_config" = "null" ]; then
      _err "Service '$_service' not found."
      return 1
    fi

    _service_hook=$(echo "$_service_config" | yq -r ".hook" -)
    if [ -z "$_service_hook" ] || [ "$_service_hook" = "null" ]; then
      _err "Service '$_service' does not have a hook."
      return 1
    fi

    _service_environment=$(echo "$_service_config" | yq -r ".environment" -)
    if [ -z "$_service_environment" ] || [ "$_service_environment" = "null" ]; then
      _err "Service '$_service' does not have an environment."
      return 1
    fi
  done
}

# Description: This function takes a list of environment variables in YAML format,
#              parses them, and exports each key-value pair as environment variables.
# Arguments:
#   $1 - A string containing the list of environment variables in YAML format.
# Usage:
#   _export_envs "$env_list"
_export_envs() {
  _env_list="$1"

  _secure_debug3 "Exporting envs" "$_env_list"

  echo "$_env_list" | yq -r 'to_entries | .[] | .key + "=" + .value' | while IFS='=' read -r _key _value; do
    # Using eval to expand nested variables in the configuration file
    _value=$(eval 'echo "'"$_value"'"')
    _savedeployconf "$_key" "$_value"
    _secure_debug3 "Saved $_key" "$_value"
  done
}

# Description:
#   This function takes a YAML formatted string of environment variables, parses it,
#   and clears each environment variable. It logs the process of clearing each variable.
#
#   Note: Environment variables for a hook may be optional and differ between
#   services using the same hook.
#   If one service sets optional environment variables and another does not, the
#   variables may persist and affect subsequent deployments.
#   Clearing these variables after each service ensures that only the
#   environment variables explicitly specified for each service in the deploy
#   file are used.
# Arguments:
#   $1 - A YAML formatted string containing environment variable key-value pairs.
# Usage:
#   _clear_envs "<yaml_string>"
_clear_envs() {
  _env_list="$1"

  _secure_debug3 "Clearing envs" "$_env_list"
  env_pairs=$(echo "$_env_list" | yq -r 'to_entries | .[] | .key + "=" + .value')

  echo "$env_pairs" | while IFS='=' read -r _key _value; do
    _debug3 "Deleting key" "$_key"
    _cleardomainconf "SAVED_$_key"
    unset -v "$_key"
  done
}

# Description:
#   This function deploys services listed in the deploy configuration file.
# Arguments:
#   $1 - The path to the deploy configuration file.
#   $2 - The list of services to deploy.
# Usage:
#   _deploy_services "<deploy_file_path>" "<services_list>"
_deploy_services() {
  _deploy_file="$1"
  _debug3 "Deploy file" "$_deploy_file"

  _tempfile=$(mktemp)
  trap 'rm -f $_tempfile' EXIT

  yq -r '.services[].name' "$_deploy_file" >"$_tempfile"
  _debug3 "Services" "$(cat "$_tempfile")"

  _failedServices=""
  _failedCount=0
  while read -r _service <&3; do
    _debug2 "Service" "$_service"
    _hook=$(yq -r ".services[] | select(.name == \"$_service\").hook" "$_deploy_file")
    _envs=$(yq -r ".services[] | select(.name == \"$_service\").environment" "$_deploy_file")

    _export_envs "$_envs"
    if ! _deploy_service "$_service" "$_hook"; then
      _failedServices="$_service, $_failedServices"
      _failedCount=$((_failedCount + 1))
    fi
    _clear_envs "$_envs"
  done 3<"$_tempfile"

  _debug3 "Failed services" "$_failedServices"
  _debug2 "Failed count" "$_failedCount"
  if [ -n "$_failedServices" ]; then
    _info "$(__red "Deployment failed") for services: $_failedServices"
  else
    _debug "All services deployed successfully."
  fi

  return "$_failedCount"
}

# Description: Deploys a service using the specified hook.
# Arguments:
#   $1 - The name of the service to deploy.
#   $2 - The hook to use for deployment.
# Usage:
#   _deploy_service <service_name> <hook>
_deploy_service() {
  _name="$1"
  _hook="$2"

  _debug2 "SERVICE" "$_name"
  _debug2 "HOOK" "$_hook"

  _info "$(__green "Deploying") to '$_name' using '$_hook'"
  _deploy "$_cdomain" "$_hook"
}
