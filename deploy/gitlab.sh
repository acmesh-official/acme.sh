#!/usr/bin/env sh

# Script to deploy certificate to a Gitlab hosted page

# The following variables exported from environment will be used.
# If not set then values previously saved in domain.conf file are used.

# All the variables are required

# export GITLAB_TOKEN="xxxxxxx"
# export GITLAB_PROJECT_ID=012345
# export GITLAB_DOMAIN="mydomain.com"

gitlab_deploy() {
  _cdomain="$1"
  _ckey="$2"
  _ccert="$3"
  _cca="$4"
  _cfullchain="$5"

  _debug _cdomain "$_cdomain"
  _debug _ckey "$_ckey"
  _debug _ccert "$_ccert"
  _debug _cca "$_cca"
  _debug _cfullchain "$_cfullchain"

  if [ -z "$GITLAB_TOKEN" ]; then
    if [ -z "$Le_Deploy_gitlab_token" ]; then
      _err "GITLAB_TOKEN not defined."
      return 1
    fi
  else
    Le_Deploy_gitlab_token="$GITLAB_TOKEN"
    _savedomainconf Le_Deploy_gitlab_token "$Le_Deploy_gitlab_token"
  fi

  if [ -z "$GITLAB_PROJECT_ID" ]; then
    if [ -z "$Le_Deploy_gitlab_project_id" ]; then
      _err "GITLAB_PROJECT_ID not defined."
      return 1
    fi
  else
    Le_Deploy_gitlab_project_id="$GITLAB_PROJECT_ID"
    _savedomainconf Le_Deploy_gitlab_project_id "$Le_Deploy_gitlab_project_id"
  fi

  if [ -z "$GITLAB_DOMAIN" ]; then
    if [ -z "$Le_Deploy_gitlab_domain" ]; then
      _err "GITLAB_DOMAIN not defined."
      return 1
    fi
  else
    Le_Deploy_gitlab_domain="$GITLAB_DOMAIN"
    _savedomainconf Le_Deploy_gitlab_domain "$Le_Deploy_gitlab_domain"
  fi

  curl -s --fail --request PUT --header "PRIVATE-TOKEN: $Le_Deploy_gitlab_token" --form "certificate=@$_cfullchain" --form "key=@$_ckey" "https://gitlab.com/api/v4/projects/$Le_Deploy_gitlab_project_id/pages/domains/$Le_Deploy_gitlab_domain" >/dev/null && exit 0

  # Exit curl status code if curl didn't work
  exit $?
}
