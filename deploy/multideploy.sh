#!/usr/bin/env sh

# MULTIDEPLOY_CONFIG="default"

########  Public functions #####################

MULTIDEPLOY_VERSION="1.0"
MULTIDEPLOY_FILENAME="multideploy.yaml"

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

  _preprocess_deployfile "$DOMAIN_DIR/$MULTIDEPLOY_FILENAME"

  MULTIDEPLOY_CONFIG="${MULTIDEPLOY_CONFIG:-$(_getdeployconf MULTIDEPLOY_CONFIG)}"
  if [ -z "$MULTIDEPLOY_CONFIG" ]; then
    MULTIDEPLOY_CONFIG="default"
    _info "MULTIDEPLOY_CONFIG is not set, so I will use 'default'."
  else
    _savedeployconf "MULTIDEPLOY_CONFIG" "$MULTIDEPLOY_CONFIG"
    _debug2 "MULTIDEPLOY_CONFIG" "$MULTIDEPLOY_CONFIG"
  fi

  # TODO: Deploy to services
}

####################  Private functions below #####################

# deploy_filepath
_preprocess_deployfile() {
  deploy_file="$1"

  # Check if yq is installed
  if ! command -v yq >/dev/null 2>&1; then
    _err "yq is not installed! Please install yq and try again."
    return 1
  fi

  # Check if deploy file exists and create a default template if not
  if [ -f "$deploy_file" ]; then
    _debug3 "Deploy file found."
    _check_deployfile "$deploy_file" "$MULTIDEPLOY_CONFIG"
  else
    # TODO: Replace URL with wiki link
    _err "Deploy file not found. Go to https://CHANGE_URL_TO_WIKI to see how to create one."
    return 1
  fi
}

# deploy_filepath deploy_config
_check_deployfile() {
  deploy_file="$1"
  deploy_config="$3"

  # Check version
  deploy_file_version=$(yq '.version' "$deploy_file")
  if [ "$MULTIDEPLOY_VERSION" != "$deploy_file_version" ]; then
    _err "As of $PROJECT_NAME $VER, the deploy file needs version $MULTIDEPLOY_VERSION! Your current deploy file is of version $deploy_file_version."
    return 1
  fi

  # Check if config exists
  if ! yq e ".configs[] | select(.name == \"$deploy_config\")" "$deploy_file" >/dev/null; then
    _err "Config '$deploy_config' not found."
    return 1
  fi

  # Extract all services from config
  services=$(yq e ".configs[] | select(.name == \"$deploy_config\").services[]" "$deploy_file")

  if [ -z "$services" ]; then
    _err "Config '$deploy_config' does not have any services to deploy to."
    return 1
  fi

  # Check if extracted services exist in services list
  for service in $services; do
    if ! yq e ".services[] | select(.name == \"$service\")" "$deploy_file" >/dev/null; then
      _err "Service '$service' not found."
      return 1
    fi

    # Check if service has hook
    if ! yq e ".services[] | select(.name == \"$service\").hook" "$deploy_file" >/dev/null; then
      _err "Service '$service' does not have a hook."
      return 1
    fi

    # Check if service has environment
    if ! yq e ".services[] | select(.name == \"$service\").environment" "$deploy_file" >/dev/null; then
      _err "Service '$service' does not an environment."
      return 1
    fi
  done
}
