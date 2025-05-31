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

  OLDIFS=$IFS
  if ! file=$(_preprocess_deployfile "$MULTIDEPLOY_FILENAME"); then
    _err "Failed to preprocess deploy file."
    return 1
  fi
  _debug3 "File" "$file"

  # Deploy to services
  _deploy_services "$file"
  _exitCode="$?"

  # Save deployhook for renewals
  _debug2 "Setting Le_DeployHook"
  _savedomainconf "Le_DeployHook" "multideploy"

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
  IFS=$(printf '\n')
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
  IFS=$OLDIFS

  if [ -n "$found_file" ]; then
    _check_deployfile "$DOMAIN_PATH/$found_file"
  else
    _err "Deploy file not found. Go to https://github.com/acmesh-official/acme.sh/wiki/deployhooks#36-deploying-to-multiple-services-with-the-same-hooks to see how to create one."
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
  _debug2 "Deploy file" "$_deploy_file"

  # Check version
  _deploy_file_version=$(yq '.version' "$_deploy_file")
  if [ "$MULTIDEPLOY_VERSION" != "$_deploy_file_version" ]; then
    _err "As of $PROJECT_NAME $VER, the deploy file needs version $MULTIDEPLOY_VERSION! Your current deploy file is of version $_deploy_file_version."
    return 1
  fi
  _debug2 "Deploy file version is compatible: $_deploy_file_version"

  # Extract all services from config
  _services=$(yq e '.services[].name' "$_deploy_file")
  _debug2 "Services" "$_services"

  if [ -z "$_services" ]; then
    _err "Config does not have any services to deploy to."
    return 1
  fi
  _debug2 "Config has services."

  IFS=$(printf '\n')
  # Check if extracted services exist in services list
  for _service in $_services; do
    _debug2 "Checking service" "$_service"
    # Check if service exists
    if ! yq e ".services[] | select(.name == \"$_service\")" "$_deploy_file" >/dev/null; then
      _err "Service '$_service' not found."
      return 1
    fi

    # Check if service has hook
    if ! yq e ".services[] | select(.name == \"$_service\").hook" "$_deploy_file" >/dev/null; then
      _err "Service '$_service' does not have a hook."
      return 1
    fi

    # Check if service has environment
    if ! yq e ".services[] | select(.name == \"$_service\").environment" "$_deploy_file" >/dev/null; then
      _err "Service '$_service' does not have an environment."
      return 1
    fi
  done
  IFS=$OLDIFS
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

  IFS=$(printf '\n')
  echo "$_env_list" | yq e -r 'to_entries | .[] | .key + "=" + .value' | while IFS='=' read -r _key _value; do
    _value=$(eval echo "$_value")
    _savedeployconf "$_key" "$_value"
    _secure_debug3 "Saved $_key" "$_value"
  done
  IFS=$OLDIFS
}

# Description:
#   This function takes a YAML formatted string of environment variables, parses it,
#   and clears each environment variable. It logs the process of clearing each variable.
# Arguments:
#   $1 - A YAML formatted string containing environment variable key-value pairs.
# Usage:
#   _clear_envs "<yaml_string>"
_clear_envs() {
  _env_list="$1"

  _secure_debug3 "Clearing envs" "$_env_list"
  env_pairs=$(echo "$_env_list" | yq e -r 'to_entries | .[] | .key + "=" + .value')

  IFS=$(printf '\n')
  echo "$env_pairs" | while IFS='=' read -r _key _value; do
    _debug3 "Deleting key" "$_key"
    _cleardomainconf "SAVED_$_key"
    unset -v "$_key"
  done
  IFS="$OLDIFS"
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

  _services=$(yq e '.services[].name' "$_deploy_file")
  _debug3 "Services" "$_services"

  _service_list=$(printf '%s\n' "$_services")

  _failedServices=""
  _failedCount=0
  for _service in $(printf '%s\n' "$_service_list"); do
    _debug2 "Service" "$_service"
    _hook=$(yq e ".services[] | select(.name == \"$_service\").hook" "$_deploy_file")
    _envs=$(yq e ".services[] | select(.name == \"$_service\").environment[]" "$_deploy_file")

    _export_envs "$_envs"
    if ! _deploy_service "$_service" "$_hook"; then
      _failedServices="$_service, $_failedServices"
      _failedCount=$((_failedCount + 1))
    fi
    _clear_envs "$_envs"
  done

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
  return $?
}
