#!/usr/bin/env sh

#DEPLOY_DOCKER_CONTAINER_LABEL="xxxxxxx"

#DEPLOY_DOCKER_CONTAINER_KEY_FILE="/path/to/key.pem"
#DEPLOY_DOCKER_CONTAINER_CERT_FILE="/path/to/cert.pem"
#DEPLOY_DOCKER_CONTAINER_CA_FILE="/path/to/ca.pem"
#DEPLOY_DOCKER_CONTAINER_FULLCHAIN_FILE="/path/to/fullchain.pem"
#DEPLOY_DOCKER_CONTAINER_RELOAD_CMD="service nginx force-reload"

_DEPLOY_DOCKER_WIKI="https://github.com/acmesh-official/acme.sh/wiki/deploy-to-docker-containers"

_DOCKER_HOST_DEFAULT="/var/run/docker.sock"

docker_deploy() {
  _cdomain="$1"
  _ckey="$2"
  _ccert="$3"
  _cca="$4"
  _cfullchain="$5"
  _debug _cdomain "$_cdomain"
  _getdeployconf DEPLOY_DOCKER_CONTAINER_LABEL
  _debug2 DEPLOY_DOCKER_CONTAINER_LABEL "$DEPLOY_DOCKER_CONTAINER_LABEL"
  if [ -z "$DEPLOY_DOCKER_CONTAINER_LABEL" ]; then
    _err "The DEPLOY_DOCKER_CONTAINER_LABEL variable is not defined, we use this label to find the container."
    _err "See: $_DEPLOY_DOCKER_WIKI"
  fi

  _savedeployconf DEPLOY_DOCKER_CONTAINER_LABEL "$DEPLOY_DOCKER_CONTAINER_LABEL"

  if [ "$DOCKER_HOST" ]; then
    _saveaccountconf DOCKER_HOST "$DOCKER_HOST"
  fi

  if _exists docker && docker version | grep -i docker >/dev/null; then
    _info "Using docker command"
    export _USE_DOCKER_COMMAND=1
  else
    export _USE_DOCKER_COMMAND=
  fi

  export _USE_UNIX_SOCKET=
  if [ -z "$_USE_DOCKER_COMMAND" ]; then
    export _USE_REST=
    if [ "$DOCKER_HOST" ]; then
      _debug "Try use docker host: $DOCKER_HOST"
      export _USE_REST=1
    else
      export _DOCKER_SOCK="$_DOCKER_HOST_DEFAULT"
      _debug "Try use $_DOCKER_SOCK"
      if [ ! -e "$_DOCKER_SOCK" ] || [ ! -w "$_DOCKER_SOCK" ]; then
        _err "$_DOCKER_SOCK is not available"
        return 1
      fi
      export _USE_UNIX_SOCKET=1
      if ! _exists "curl"; then
        _err "Please install curl first."
        _err "We need curl to work."
        return 1
      fi
      if ! _check_curl_version; then
        return 1
      fi
    fi
  fi

  _getdeployconf DEPLOY_DOCKER_CONTAINER_KEY_FILE
  _debug2 DEPLOY_DOCKER_CONTAINER_KEY_FILE "$DEPLOY_DOCKER_CONTAINER_KEY_FILE"
  if [ "$DEPLOY_DOCKER_CONTAINER_KEY_FILE" ]; then
    _savedeployconf DEPLOY_DOCKER_CONTAINER_KEY_FILE "$DEPLOY_DOCKER_CONTAINER_KEY_FILE"
  fi

  _getdeployconf DEPLOY_DOCKER_CONTAINER_CERT_FILE
  _debug2 DEPLOY_DOCKER_CONTAINER_CERT_FILE "$DEPLOY_DOCKER_CONTAINER_CERT_FILE"
  if [ "$DEPLOY_DOCKER_CONTAINER_CERT_FILE" ]; then
    _savedeployconf DEPLOY_DOCKER_CONTAINER_CERT_FILE "$DEPLOY_DOCKER_CONTAINER_CERT_FILE"
  fi

  _getdeployconf DEPLOY_DOCKER_CONTAINER_CA_FILE
  _debug2 DEPLOY_DOCKER_CONTAINER_CA_FILE "$DEPLOY_DOCKER_CONTAINER_CA_FILE"
  if [ "$DEPLOY_DOCKER_CONTAINER_CA_FILE" ]; then
    _savedeployconf DEPLOY_DOCKER_CONTAINER_CA_FILE "$DEPLOY_DOCKER_CONTAINER_CA_FILE"
  fi

  _getdeployconf DEPLOY_DOCKER_CONTAINER_FULLCHAIN_FILE
  _debug2 DEPLOY_DOCKER_CONTAINER_FULLCHAIN_FILE "$DEPLOY_DOCKER_CONTAINER_FULLCHAIN_FILE"
  if [ "$DEPLOY_DOCKER_CONTAINER_FULLCHAIN_FILE" ]; then
    _savedeployconf DEPLOY_DOCKER_CONTAINER_FULLCHAIN_FILE "$DEPLOY_DOCKER_CONTAINER_FULLCHAIN_FILE"
  fi

  _getdeployconf DEPLOY_DOCKER_CONTAINER_RELOAD_CMD
  _debug2 DEPLOY_DOCKER_CONTAINER_RELOAD_CMD "$DEPLOY_DOCKER_CONTAINER_RELOAD_CMD"
  if [ "$DEPLOY_DOCKER_CONTAINER_RELOAD_CMD" ]; then
    _savedeployconf DEPLOY_DOCKER_CONTAINER_RELOAD_CMD "$DEPLOY_DOCKER_CONTAINER_RELOAD_CMD" "base64"
  fi

  _cid="$(_get_id "$DEPLOY_DOCKER_CONTAINER_LABEL")"
  _info "Container id: $_cid"
  if [ -z "$_cid" ]; then
    _err "can not find container id"
    return 1
  fi

  if [ "$DEPLOY_DOCKER_CONTAINER_KEY_FILE" ]; then
    if ! _docker_cp "$_cid" "$_ckey" "$DEPLOY_DOCKER_CONTAINER_KEY_FILE"; then
      return 1
    fi
  fi

  if [ "$DEPLOY_DOCKER_CONTAINER_CERT_FILE" ]; then
    if ! _docker_cp "$_cid" "$_ccert" "$DEPLOY_DOCKER_CONTAINER_CERT_FILE"; then
      return 1
    fi
  fi

  if [ "$DEPLOY_DOCKER_CONTAINER_CA_FILE" ]; then
    if ! _docker_cp "$_cid" "$_cca" "$DEPLOY_DOCKER_CONTAINER_CA_FILE"; then
      return 1
    fi
  fi

  if [ "$DEPLOY_DOCKER_CONTAINER_FULLCHAIN_FILE" ]; then
    if ! _docker_cp "$_cid" "$_cfullchain" "$DEPLOY_DOCKER_CONTAINER_FULLCHAIN_FILE"; then
      return 1
    fi
  fi

  if [ "$DEPLOY_DOCKER_CONTAINER_RELOAD_CMD" ]; then
    _info "Reloading: $DEPLOY_DOCKER_CONTAINER_RELOAD_CMD"
    if ! _docker_exec "$_cid" "$DEPLOY_DOCKER_CONTAINER_RELOAD_CMD"; then
      return 1
    fi
  fi
  return 0
}

#label
_get_id() {
  _label="$1"
  if [ "$_USE_DOCKER_COMMAND" ]; then
    docker ps -f label="$_label" --format "{{.ID}}"
  elif [ "$_USE_REST" ]; then
    _err "Not implemented yet."
    return 1
  elif [ "$_USE_UNIX_SOCKET" ]; then
    _req="{\"label\":[\"$_label\"]}"
    _debug2 _req "$_req"
    _req="$(printf "%s" "$_req" | _url_encode)"
    _debug2 _req "$_req"
    listjson="$(_curl_unix_sock "${_DOCKER_SOCK:-$_DOCKER_HOST_DEFAULT}" GET "/containers/json?filters=$_req")"
    _debug2 "listjson" "$listjson"
    echo "$listjson" | tr '{,' '\n' | grep -i '"id":' | _head_n 1 | cut -d '"' -f 4
  else
    _err "Not implemented yet."
    return 1
  fi
}

#id  cmd
_docker_exec() {
  _eargs="$*"
  _debug2 "_docker_exec $_eargs"
  _dcid="$1"
  shift
  if [ "$_USE_DOCKER_COMMAND" ]; then
    docker exec -i "$_dcid" sh -c "$*"
  elif [ "$_USE_REST" ]; then
    _err "Not implemented yet."
    return 1
  elif [ "$_USE_UNIX_SOCKET" ]; then
    _cmd="$*"
    #_cmd="$(printf "%s" "$_cmd" | sed 's/ /","/g')"
    _debug2 _cmd "$_cmd"
    #create exec instance:
    cjson="$(_curl_unix_sock "$_DOCKER_SOCK" POST "/containers/$_dcid/exec" "{\"Cmd\": [\"sh\", \"-c\", \"$_cmd\"]}")"
    _debug2 cjson "$cjson"
    execid="$(echo "$cjson" | cut -d '"' -f 4)"
    _debug execid "$execid"
    ejson="$(_curl_unix_sock "$_DOCKER_SOCK" POST "/exec/$execid/start" "{\"Detach\": false,\"Tty\": false}")"
    _debug2 ejson "$ejson"
    if [ "$ejson" ]; then
      _err "$ejson"
      return 1
    fi
  else
    _err "Not implemented yet."
    return 1
  fi
}

#id from  to
_docker_cp() {
  _dcid="$1"
  _from="$2"
  _to="$3"
  _info "Copying file from $_from to $_to"
  _dir="$(dirname "$_to")"
  _debug2 _dir "$_dir"
  if ! _docker_exec "$_dcid" mkdir -p "$_dir"; then
    _err "Can not create dir: $_dir"
    return 1
  fi
  if [ "$_USE_DOCKER_COMMAND" ]; then
    if [ "$DEBUG" ] && [ "$DEBUG" -ge "2" ]; then
      _docker_exec "$_dcid" tee "$_to" <"$_from"
    else
      _docker_exec "$_dcid" tee "$_to" <"$_from" >/dev/null
    fi
    if [ "$?" = "0" ]; then
      _info "Success"
      return 0
    else
      _info "Error"
      return 1
    fi
  elif [ "$_USE_REST" ]; then
    _err "Not implemented yet."
    return 1
  elif [ "$_USE_UNIX_SOCKET" ]; then
    _frompath="$_from"
    if _startswith "$_frompath" '/'; then
      _frompath="$(echo "$_from" | cut -b 2-)" #remove the first '/' char
    fi
    _debug2 "_frompath" "$_frompath"
    _toname="$(basename "$_to")"
    _debug2 "_toname" "$_toname"
    _debug2 "_from" "$_from"
    if ! tar --transform="s,$(printf "%s" "$_frompath" | tr '*' .),$_toname," -cz "$_from" 2>/dev/null | _curl_unix_sock "$_DOCKER_SOCK" PUT "/containers/$_dcid/archive?noOverwriteDirNonDir=1&path=$(printf "%s" "$_dir" | _url_encode)" '@-' "Content-Type: application/octet-stream"; then
      _err "copy error"
      return 1
    fi
    return 0
  else
    _err "Not implemented yet."
    return 1
  fi

}

#sock method  endpoint data content-type
_curl_unix_sock() {
  _socket="$1"
  _method="$2"
  _endpoint="$3"
  _data="$4"
  _ctype="$5"
  if [ -z "$_ctype" ]; then
    _ctype="Content-Type: application/json"
  fi
  _debug _data "$_data"
  _debug2 "url" "http://localhost$_endpoint"
  if [ "$_CURL_NO_HOST" ]; then
    _cux_url="http:$_endpoint"
  else
    _cux_url="http://localhost$_endpoint"
  fi

  if [ "$DEBUG" ] && [ "$DEBUG" -ge "2" ]; then
    curl -vvv --silent --unix-socket "$_socket" -X "$_method" --data-binary "$_data" --header "$_ctype" "$_cux_url"
  else
    curl --silent --unix-socket "$_socket" -X "$_method" --data-binary "$_data" --header "$_ctype" "$_cux_url"
  fi

}

_check_curl_version() {
  _cversion="$(curl -V | grep '^curl ' | cut -d ' ' -f 2)"
  _debug2 "_cversion" "$_cversion"

  _major="$(_getfield "$_cversion" 1 '.')"
  _debug2 "_major" "$_major"

  _minor="$(_getfield "$_cversion" 2 '.')"
  _debug2 "_minor" "$_minor"

  if [ "$_major$_minor" -lt "740" ]; then
    _err "curl v$_cversion doesn't support unit socket"
    _err "Please upgrade to curl 7.40 or later."
    return 1
  fi
  if [ "$_major$_minor" -lt "750" ]; then
    _debug "Use short host name"
    export _CURL_NO_HOST=1
  else
    export _CURL_NO_HOST=
  fi
  return 0
}
