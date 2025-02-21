#!/usr/bin/env sh

# MULTIDEPLOY_CONFIG="default"

########  Public functions #####################

MULTIDEPLOY_VERSION="1.0"
MULTIDEPLOY_FILENAME="multideploy.yml"
MULTIDEPLOY_FILENAME2="multideploy.yaml"

# domain keyfile certfile cafile fullchain pfx
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

  DOMAIN_DIR=$_cdomain
  if echo "$DOMAIN_PATH" | grep -q "$ECC_SUFFIX"; then
    DOMAIN_DIR="$DOMAIN_DIR"_ecc
  fi
  _debug2 "DOMAIN_DIR" "$DOMAIN_DIR"

  MULTIDEPLOY_CONFIG="${MULTIDEPLOY_CONFIG:-$(_getdeployconf MULTIDEPLOY_CONFIG)}"
  if [ -z "$MULTIDEPLOY_CONFIG" ]; then
    MULTIDEPLOY_CONFIG="default"
    _info "MULTIDEPLOY_CONFIG is not set, so I will use 'default'."
  else
    _savedeployconf "MULTIDEPLOY_CONFIG" "$MULTIDEPLOY_CONFIG"
    _debug2 "MULTIDEPLOY_CONFIG" "$MULTIDEPLOY_CONFIG"
  fi

  # Deploy to services
  _services=$(_get_services_list "$DOMAIN_DIR/$MULTIDEPLOY_FILENAME" "$MULTIDEPLOY_CONFIG")
  _full_services=$(_get_full_services_list "$DOMAIN_DIR/$MULTIDEPLOY_FILENAME" "$_services")
  _deploy_services "$DOMAIN_DIR/$MULTIDEPLOY_FILENAME" "$_full_services"

  # Save deployhook for renewals
  _debug2 "Setting Le_DeployHook"
  _savedomainconf "Le_DeployHook" "multideploy"

  return 0
}

####################  Private functions below #####################

# deploy_filepath
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

  if [ -n "$found_file" ]; then
    _check_deployfile "$DOMAIN_PATH/$found_file" "$MULTIDEPLOY_CONFIG"
  else
    # TODO: Replace URL with wiki link
    _err "Deploy file not found. Go to https://CHANGE_URL_TO_WIKI to see how to create one."
    return 1
  fi
}

# deploy_filepath _deploy_config
_check_deployfile() {
  _deploy_file="$1"
  _deploy_config="$2"

  _debug2 "Deploy file" "$_deploy_file"
  _debug2 "Deploy config" "$_deploy_config"

  # Check version
  _deploy_file_version=$(yq '.version' "$_deploy_file")
  if [ "$MULTIDEPLOY_VERSION" != "$_deploy_file_version" ]; then
    _err "As of $PROJECT_NAME $VER, the deploy file needs version $MULTIDEPLOY_VERSION! Your current deploy file is of version $_deploy_file_version."
    return 1
  fi
  _debug2 "Deploy file version is compatible: $_deploy_file_version"

  # Check if config exists
  if ! yq e ".configs[] | select(.name == \"$_deploy_config\")" "$_deploy_file" >/dev/null; then
    _err "Config '$_deploy_config' not found."
    return 1
  fi
  _debug2 "Config found: $_deploy_config"

  # Extract all services from config
  _services=$(_get_services_list "$_deploy_file" "$_deploy_config")
  _debug2 "Services" "$_services"

  if [ -z "$_services" ]; then
    _err "Config '$_deploy_config' does not have any services to deploy to."
    return 1
  fi
  _debug2 "Config has services."

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
      _err "Service '$_service' does not an environment."
      return 1
    fi
  done
}

# deploy_filepath deploy_config
_get_services_list() {
  _deploy_file="$1"
  _deploy_config="$2"

  _debug2 "Getting services list"
  _debug3 "Deploy file" "$_deploy_file"
  _debug3 "Deploy config" "$_deploy_config"

  _services=$(yq e ".configs[] | select(.name == \"$_deploy_config\").services[]" "$_deploy_file")
  echo "$_services"
}

# deploy_filepath service_names
_get_full_services_list() {
  _deploy_file="$1"
  shift
  _service_names="$*"

  _debug3 "Deploy file" "$_deploy_file"
  _debug3 "Service names" "$_service_names"

  _full_services=""
  for _service in $_service_names; do
    _full_service=$(yq e ".services[] | select(.name == \"$_service\")" "$_deploy_file")
    _full_services="$_full_services
$_full_service"
  done

  echo "$_full_services"
}

# env_list
_export_envs() {
  _env_list="$1"

  _secure_debug3 "Exporting envs" "$_env_list"

  for _env in $_env_list; do
    _key=$(echo "$_env" | cut -d '=' -f1)
    _value=$(echo "$_env" | cut -d '=' -f2-)
    _savedomainconf "$_key" "$_value"
    _secure_debug3 "Saved $_key" "$_value"
  done
}

_clear_envs() {
  _env_list="$1"

  _secure_debug3 "Clearing envs" "$_env_list"

  for _env in $_env_list; do
    _key=$(echo "$_env" | cut -d '=' -f1)
    _debug3 "Deleting key" "$_key"
    _cleardomainconf "SAVED_$_key"
    unset "$_key"
  done
}

# deploy_filepath services_array
_deploy_services() {
  _deploy_file="$1"
  shift
  _services="$*"

  _debug3 "Deploy file" "$_deploy_file"
  _debug3 "Services" "$_services"

  for _service in $_services; do
    _hook=$(yq e ".services[] | select(.name == \"$_service\").hook" "$_deploy_file")
    _envs=$(yq e ".services[] | select(.name == \"$_service\").environment[]" "$_deploy_file")
    _export_envs "$_envs"
    _deploy_service "$_service" "$_hook"
    _clear_envs "$_envs"
  done
}

_deploy_service() {
  _name="$1"
  _hook="$2"

  _debug2 "SERVICE" "$_name"
  _debug2 "HOOK" "$_hook"

  _info "$(__green "Deploying") to '$_name' using '$_hook'"
  if echo "$DOMAIN_PATH" | grep -q "$ECC_SUFFIX"; then
    _debug2 "User wants to use ECC."
    deploy "$_cdomain" "$_hook" "isEcc"
  else
    deploy "$_cdomain" "$_hook"
  fi
}
