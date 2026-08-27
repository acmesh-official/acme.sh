#!/usr/bin/env sh

# TrueNAS deploy script for SCALE/CORE using websocket (websocat binary)
# It is recommend to use a wildcard certificate
#
# Tested with TrueNAS SCALE 25.10 (API "wss://host/api/current", JSON-RPC 2.0).
#
# Unlike "truenas_ws" hook, this script does NOT use midclt, the truenas_api_client Python package.
# It only depends on:
#   - jq
#   - websocat  (a static binary you deploy)
#
# Why: avoids installing a Python environment / TrueNAS package on OPNsense
# just to push a certificate.
#
# IMPORTANT: This script is written in pure POSIX sh (no coproc, no bash arrays).
#
#
# ---------------------------------------------------------------------------
# Environment variables
# ---------------------------------------------------------------------------
#
# # Use the folowing URL to create a new API token: <TRUENAS_HOSTNAME OR IP>/ui/apikeys
#
# Required:
#   export DEPLOY_TRUENAS_APIKEY="<API_KEY_GENERATED_IN_THE_WEB_UI>"
#
# Optional:
#   export DEPLOY_TRUENAS_HOSTNAME="<TRUENAS_HOSTNAME_OR_IP>				(required on first run)
#   export DEPLOY_TRUENAS_PROTOCOL="ws"						# ws or wss		(default: ws)
#   export DEPLOY_TRUENAS_PORT="80"							# 80, 443, 8443	(default: 80)
#   export DEPLOY_TRUENAS_UPDATE_FTP="no"					# yes or no 	(default: no) also updates the FTP certificate
#   export DEPLOY_TRUENAS_UPDATE_APPS="no"					# yes or no		(default: no) also updates the certificate for any
#								iX app exposing a "certificate_id" option.
#								WARNING: this redeploys (restarts) every matching app.
# ---------------------------------------------------------------------------

########################
### Public functions ###
########################

# truenas_websocat_deploy
#
# Deploy new certificate to TrueNAS services with websocat binary
#
# Arguments
#  1: Domain
#  2: Key-File
#  3: Certificate-File
#  4: CA-File
#  5: FullChain-File
# Returns:
#  0: Success
#  1: Missing or invalid API Key
#  2: TrueNAS not ready (health check failed)
#  3: (reserved)
#  4: FTP & iX App cert error
#  5: WebUI cert error
#  6: Certificate creation job error
#  7: Websocat / transport call error (socket write/read failed)
#  8: Missing binary or invalid configuration
#  9: TrueNAS API returned an explicit error (JSON-RPC .error field)

truenas_websocat_deploy() {
	_jq_bin="/usr/local/bin/jq"
	_websocat_bin=$(command -v websocat 2>/dev/null)
	if [ -z "$_websocat_bin" ]; then
		_err "websocat binary not found in PATH. Install it with: pkg install websocat"
		return 8
	fi

	_domain="$1"
	_file_key="$2"
	_file_cert="$3"
	_file_cca="$4"
	_file_fullchain="$5"
	_debug _domain "$_domain"
	_debug _file_key "$_file_key"
	_debug _file_cert "$_file_cert"
	_debug _file_ca "$_file_cca"
	_debug _file_fullchain "$_file_fullchain"

	if [ ! -x "$_jq_bin" ]; then
		_err "Binary not found or not executable: $_jq_bin"
		return 8
	fi
	if [ ! -x "$_websocat_bin" ]; then
		_err "Binary not found or not executable: $_websocat_bin"
		return 8
	fi

	### ---- Configuration ----

	_info "Checking environment variables..."
	_getdeployconf DEPLOY_TRUENAS_APIKEY
	_getdeployconf DEPLOY_TRUENAS_HOSTNAME
	_getdeployconf DEPLOY_TRUENAS_PROTOCOL
	_getdeployconf DEPLOY_TRUENAS_PORT
	_getdeployconf DEPLOY_TRUENAS_UPDATE_FTP
	_getdeployconf DEPLOY_TRUENAS_UPDATE_APPS

	# Check API Key
	if [ -z "$DEPLOY_TRUENAS_APIKEY" ]; then
		_err "TrueNAS API key not found, please set the DEPLOY_TRUENAS_APIKEY environment variable."
		return 1
	fi
	# Check Hostname, default to localhost if not set
	if [ -z "$DEPLOY_TRUENAS_HOSTNAME" ]; then
		_info "TrueNAS hostname not set. Using 'localhost'."
		DEPLOY_TRUENAS_HOSTNAME="localhost"
	fi

	# Check protocol, default to wss (encrypted) if not set: the payload
	# carries the API key and the private key in plain text.
	if [ -z "$DEPLOY_TRUENAS_PROTOCOL" ]; then
		_info "TrueNAS protocol not set. Using 'ws'."
		DEPLOY_TRUENAS_PROTOCOL="ws"
	fi

	# Check port, default to 443 if not set
	if [ -z "$DEPLOY_TRUENAS_PORT" ]; then
		_info "TrueNAS port not set. Using '80'."
		DEPLOY_TRUENAS_PORT="80"
	fi
	case "$DEPLOY_TRUENAS_PORT" in
	'' | *[!0-9]*)
		_err "Invalid TrueNAS port '$DEPLOY_TRUENAS_PORT'. DEPLOY_TRUENAS_PORT must be numeric."
		return 8
		;;
	esac

	_ws_uri="$DEPLOY_TRUENAS_PROTOCOL://$DEPLOY_TRUENAS_HOSTNAME:$DEPLOY_TRUENAS_PORT/api/current"

	# Check FTP update, default to no if not set
	if [ -z "$DEPLOY_TRUENAS_UPDATE_FTP" ]; then
		_info "Certificate update for FTP is not set. Using 'no'."
		DEPLOY_TRUENAS_UPDATE_FTP="no"
	fi

		# Check Apps update, default to no if not set
	if [ -z "$DEPLOY_TRUENAS_UPDATE_APPS" ]; then
		_info "Certificate update for Apps is not set. Using 'no'."
		DEPLOY_TRUENAS_UPDATE_APPS="no"
	fi

	_debug2 DEPLOY_TRUENAS_HOSTNAME "$DEPLOY_TRUENAS_HOSTNAME"
	_debug2 DEPLOY_TRUENAS_PROTOCOL "$DEPLOY_TRUENAS_PROTOCOL"
	_debug2 DEPLOY_TRUENAS_UPDATE_FTP "$DEPLOY_TRUENAS_UPDATE_FTP"
	_debug2 DEPLOY_TRUENAS_UPDATE_APPS "$DEPLOY_TRUENAS_UPDATE_APPS"
	_debug _ws_uri "$_ws_uri"
	_secure_debug2 DEPLOY_TRUENAS_APIKEY "$DEPLOY_TRUENAS_APIKEY"
	_info "Environment variables: OK"  
  
	### ---- Persistent WebSocket connection (FIFOs, sh/dash compatible) ----
	#
	# Authentication is tied to the WebSocket connection: the SAME connection
	# must stay open from login until the end, otherwise every subsequent call
	# comes back unauthenticated. We use two FIFOs + `exec` to talk to a
	# background websocat process, without relying on bash-only extensions.

	_ws_tmpdir=$(mktemp -d /tmp/truenas_ws.XXXXXX) || { _err "mktemp failed"; return 3; }
	_ws_fifo_in="${_ws_tmpdir}/in"
	_ws_fifo_out="${_ws_tmpdir}/out"
	mkfifo "$_ws_fifo_in" "$_ws_fifo_out" || { _err "mkfifo failed"; rm -rf "$_ws_tmpdir"; return 3; }

	"$_websocat_bin" -n -k "$_ws_uri" <"$_ws_fifo_in" >"$_ws_fifo_out" 2>"${_ws_tmpdir}/err.log" &
	_ws_pid=$!

	# Opening "in" for read+write avoids a deadlock if websocat hasn't opened
	# the fifo for reading yet at the time we write to it.
	exec 3<>"$_ws_fifo_in"
	exec 4<"$_ws_fifo_out"

	sleep 1
	if ! kill -0 "$_ws_pid" 2>/dev/null; then
		_err "websocat exited prematurely."
		_err "$(cat "${_ws_tmpdir}/err.log" 2>/dev/null)"
		exec 3>&- 4<&-
		rm -rf "$_ws_tmpdir"
		return 3
	fi

	_ws_req_counter=0

	_ws_cleanup() {
		exec 3>&- 2>/dev/null
		exec 4<&- 2>/dev/null
		[ -n "$_ws_pid" ] && kill "$_ws_pid" 2>/dev/null
		rm -rf "$_ws_tmpdir" 2>/dev/null
	}

	# _rpc_call <method> <json_params>
	# Does NOT log the payload/response: some calls (certificate.create,
	# core.get_jobs) contain the certificate and private key in plain text,
	# which would massively bloat the logs.
	_rpc_call() {
		_method="$1"
		_params="$2"
		_ws_req_counter=$((_ws_req_counter + 1))
		_req_id="$_ws_req_counter"

		_payload=$("$_jq_bin" -c -n \
		--arg jsonrpc "2.0" \
		--arg id "$_req_id" \
		--arg method "$_method" \
		--argjson params "$_params" \
		'{jsonrpc: $jsonrpc, id: $id, method: $method, params: $params}')

		printf '%s\n' "$_payload" >&3 || { _err "Socket write failed (method: $_method)"; return 7; }
		IFS= read -r _response <&4 || { _err "Socket read failed (method: $_method)"; return 7; }

		printf '%s' "$_response"
	}

	# _rpc_has_error <response> <label> -> returns 0 (and prints) if an error was found, 1 otherwise
	_rpc_has_error() {
		_msg=$(printf '%s' "$1" | "$_jq_bin" -r '.error.message // empty' 2>/dev/null)
		if [ -n "$_msg" ]; then
			_err "RPC error ($2): $_msg"
			return 0
		fi
		return 1
	}

	# _wait_for_job <jobid> -> prints the job's JSON result to stdout
	_wait_for_job() {
		_jobid="$1"
		while true; do
			sleep 1
			_job_resp=$(_rpc_call "core.get_jobs" "[[[\"id\",\"=\",${_jobid}]]]") || return 6
			if _rpc_has_error "$_job_resp" "core.get_jobs"; then return 6; fi
			_state=$(printf '%s' "$_job_resp" | "$_jq_bin" -r '.result[0].state // empty')
			case "$_state" in
				SUCCESS)
					printf '%s' "$_job_resp" | "$_jq_bin" -c '.result[0].result'
					return 0
				;;
				FAILED | ABORTED)
					_err "Job $_jobid failed: $(printf '%s' "$_job_resp" | "$_jq_bin" -c '.result[0].error')"
					return 6
				;;
				"")
					_err "Job $_jobid: unexpected response."
					return 6
				;;
			esac
		done
	}

	### ---- 1. Health check ----

	_info "Testing connection to TrueNAS WebSocket at $_ws_uri..."
	_ping_resp=$(_rpc_call "core.ping" "[]") || { _ws_cleanup; return 7; }
	if _rpc_has_error "$_ping_resp" "core.ping"; then _ws_cleanup; return 9; fi
	if [ "$(printf '%s' "$_ping_resp" | "$_jq_bin" -r '.result // empty')" != "pong" ]; then
		_err "Health check failed (no pong received)."
		_ws_cleanup
		return 2
	fi
	_info "Health check OK (pong received)."

	### ---- 2. Authentication & Check ----

	_info "Authenticating with API Key..."
	_key_params=$("$_jq_bin" -c -n --arg k "$DEPLOY_TRUENAS_APIKEY" '[$k]')
	_auth_resp=$(_rpc_call "auth.login_with_api_key" "$_key_params") || { _ws_cleanup; return 7; }
	if _rpc_has_error "$_auth_resp" "auth.login_with_api_key"; then _ws_cleanup; return 9; fi
	if [ "$(printf '%s' "$_auth_resp" | "$_jq_bin" -r '.result // empty')" != "true" ]; then
		_err "Authentication failed (invalid API key?)."
		_ws_cleanup
		return 1
	fi
	_info "Connected to TrueNAS ($_ws_uri)."

	_savedeployconf DEPLOY_TRUENAS_APIKEY "$DEPLOY_TRUENAS_APIKEY"
	_savedeployconf DEPLOY_TRUENAS_HOSTNAME "$DEPLOY_TRUENAS_HOSTNAME"
	_savedeployconf DEPLOY_TRUENAS_PROTOCOL "$DEPLOY_TRUENAS_PROTOCOL"
	_savedeployconf DEPLOY_TRUENAS_PORT "$DEPLOY_TRUENAS_PORT"
	_savedeployconf DEPLOY_TRUENAS_UPDATE_FTP "$DEPLOY_TRUENAS_UPDATE_FTP"
	_savedeployconf DEPLOY_TRUENAS_UPDATE_APPS "$DEPLOY_TRUENAS_UPDATE_APPS"

	_info "Checking TrueNAS system version..."
	_ver_resp=$(_rpc_call "system.info" "[]") || { _ws_cleanup; return 7; }
	if _rpc_has_error "$_ver_resp" "system.info"; then _ws_cleanup; return 9; fi
	_sys_version=$(printf '%s' "$_ver_resp" | "$_jq_bin" -r '.result.version // .result // "Unknown"')
	_info "TrueNAS System Version: $_sys_version"

	### ---- 3. Read certificate files ----

	_info "Reading certificate files for $_domain..."
	if [ ! -f "$_file_fullchain" ] || [ ! -f "$_file_key" ]; then
		_err "Certificate or key file not found."
		_ws_cleanup
		return 5
	fi
	_cert_content=$("$_jq_bin" -sR . "$_file_fullchain")
	_key_content=$("$_jq_bin" -sR . "$_file_key")

	_safe_domain=$(echo "$_domain" | tr '*.' '_')
	_cert_name="acme_${_safe_domain}_$(date +%Y%m%d_%H%M%S)"
	_debug _certname "$_cert_name"

	### ---- 4. Current Web UI certificate ----

	_info "Retrieving current Web UI configuration..."
	_config_resp=$(_rpc_call "system.general.config" "[]") || { _ws_cleanup; return 7; }
	if _rpc_has_error "$_config_resp" "system.general.config"; then _ws_cleanup; return 9; fi
	_old_cert_id=$(printf '%s' "$_config_resp" | "$_jq_bin" -r '.result.ui_certificate.id // .result.ui_certificate // empty')
	_info "Current Web UI Certificate ID: ${_old_cert_id:-None}"

	### ---- 5. Import the new certificate (asynchronous job) ----

	_info "Importing new certificate '$_cert_name'..."
	_create_params=$("$_jq_bin" -n \
		--arg name "$_cert_name" \
		--argjson cert "$_cert_content" \
		--argjson key "$_key_content" \
		'[{create_type: "CERTIFICATE_CREATE_IMPORTED", name: $name, certificate: $cert, privatekey: $key}]')

	_new_cert_resp=$(_rpc_call "certificate.create" "$_create_params") || { _ws_cleanup; return 7; }
	if _rpc_has_error "$_new_cert_resp" "certificate.create"; then _ws_cleanup; return 9; fi
	_new_cert_jobid=$(printf '%s' "$_new_cert_resp" | "$_jq_bin" -r '.result // empty')

	case "$_new_cert_jobid" in
		'' | *[!0-9]*)
		_err "Unexpected response from certificate.create (expected a job ID)."
		_ws_cleanup
		return 6
		;;
	esac

	_info "Import job certificate started (job ID: $_new_cert_jobid), waiting..."
	_job_result=$(_wait_for_job "$_new_cert_jobid") || { _ws_cleanup; return 6; }
	_new_cert_id=$(printf '%s' "$_job_result" | "$_jq_bin" -r '.id // empty')

	if [ -z "$_new_cert_id" ]; then
		_err "Could not retrieve the imported certificate's ID."
		_ws_cleanup
		return 6
	fi
	_info "Certificate imported: '$_cert_name' (ID $_new_cert_id)."

  ### ---- 6. Assign to the Web UI ----

	_info "Assigning certificate ID $_new_cert_id to Web UI..."
	_update_resp=$(_rpc_call "system.general.update" "[{\"ui_certificate\": ${_new_cert_id}}]") || { _ws_cleanup; return 7; }
	if _rpc_has_error "$_update_resp" "system.general.update"; then _ws_cleanup; return 9; fi
	_assigned_id=$(printf '%s' "$_update_resp" | "$_jq_bin" -r '.result.ui_certificate.id // .result.ui_certificate // empty')

	if [ "$_assigned_id" != "$_new_cert_id" ]; then
		_err "Failed to assign the certificate to the Web UI."
		_ws_cleanup
		return 5
	fi

	_info "Restarting TrueNAS Web UI service..."
	_restart_resp=$(_rpc_call "system.general.ui_restart" "[]")
	_rpc_has_error "$_restart_resp" "system.general.ui_restart"
	_info "Web UI certificate updated and UI restarted."
	# Need TrueNas to sleep before perform other actions
	_info "Waiting for Web UI restart."
	sleep 5

	### ---- 7. FTP (optional) ----

	if [ "$DEPLOY_TRUENAS_UPDATE_FTP" = "yes" ]; then
		_info "Sending certicate for FTP service..."
		_ftp_resp=$(_rpc_call "ftp.update" "[{\"ssltls_certificate\": ${_new_cert_id}}]") || { _ws_cleanup; return 4; }
		if _rpc_has_error "$_ftp_resp" "ftp.update"; then
			_err "Failed to update the FTP certificate."
			_ws_cleanup
			return 4
		else
			_ftp_certid=$(printf '%s' "$_ftp_resp" | "$_jq_bin" -r '.result.ssltls_certificate // empty')
			if [ "$_ftp_certid" = "$_new_cert_id" ]; then
				_info "FTP certificate updated."
			else
				_err "FTP certificate: unexpected response."
				_ws_cleanup
				return 4
			fi
		fi
	fi

  ### ---- 8. iX Apps (optional - redeploys every matching app) ----

	if [ "$DEPLOY_TRUENAS_UPDATE_APPS" = "yes" ]; then
		_info "Sending certicate for iX Apps..."
		_apps_resp=$(_rpc_call "app.query" "[]") || { _ws_cleanup; return 4; }
		if _rpc_has_error "$_apps_resp" "app.query"; then
			_err "Could not list apps."
			_ws_cleanup
			return 4
		else
			for _app_name in $(printf '%s' "$_apps_resp" | "$_jq_bin" -r '.result[].name'); do
				_app_cfg=$(_rpc_call "app.config" "[\"${_app_name}\"]") || { _ws_cleanup; return 4; }
				_has_cert_opt=$(printf '%s' "$_app_cfg" | "$_jq_bin" -r '.result.network // {} | has("certificate_id")' 2>/dev/null)
				if [ "$_has_cert_opt" = "true" ]; then
					_info "Updating certificate for app '$_app_name' (this will redeploy it)..."
					_app_update_resp=$(_rpc_call "app.update" "[\"${_app_name}\", {\"values\": {\"network\": {\"certificate_id\": ${_new_cert_id}}}}]") || { _ws_cleanup; return 4; }
					_app_jobid=$(printf '%s' "$_app_update_resp" | "$_jq_bin" -r '.result // empty')
					case "$_app_jobid" in
						'' | *[!0-9]*)
						_err "App '$_app_name': no job ID returned."
						_ws_cleanup
						return 4
						;;
						*)
						if ! _wait_for_job "$_app_jobid" >/dev/null; then
							_err "App '$_app_name': update not confirmed."
							_ws_cleanup
							return 4
						fi
						;;
					esac
				fi
			done
		fi
	fi

	### ---- 9. Delete the old certificate (non blocking) ----

	if [ -n "$_old_cert_id" ] && [ "$_old_cert_id" != "$_new_cert_id" ] && [ "$_old_cert_id" != "null" ]; then
		_del_resp=$(_rpc_call "certificate.delete" "[${_old_cert_id}]")
		if ! _rpc_has_error "$_del_resp" "certificate.delete"; then
			_del_jobid=$(printf '%s' "$_del_resp" | "$_jq_bin" -r '.result // empty')
			case "$_del_jobid" in
				'' | *[!0-9]*) : ;;
				*) _wait_for_job "$_del_jobid" >/dev/null || _info "Old certificate: deletion not confirmed ."
				;;
			esac
		fi
	fi

	_ws_cleanup
	_info "TrueNAS deployment completed successfully."
	return 0
}
