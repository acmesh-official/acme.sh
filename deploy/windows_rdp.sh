#!/usr/bin/env sh

# install a certificate on a Windows host over OpenSSH and bind it to the Remote
# Desktop listener (RDP-Tcp).
#
# One ssh invocation does the whole job:
#   * the PFX is built locally, base64'd, and embedded as a string literal
#     inside a generated PowerShell script;
#   * the script is piped to `powershell.exe -Command -` over ssh. No scp,
#     no temp files on the Windows host.
#
# First run:
#   export DEPLOY_WIN_RDP_HOST=winserver.example.com
#   acme.sh --deploy -d winserver.example.com --deploy-hook windows_rdp
#
# Available variables:
#   DEPLOY_WIN_RDP_HOST        required   SSH host
#   DEPLOY_WIN_RDP_USER        optional   SSH user, must be a local administrator (can also by set via ssh_config)
#   DEPLOY_WIN_RDP_PORT        optional   SSH port, default 22
#   DEPLOY_WIN_RDP_SSH_OPTS    optional   extra ssh options, e.g.
#   									  "-i /root/.ssh/win_id_ed25519 -o StrictHostKeyChecking=yes"
#   DEPLOY_WIN_RDP_LISTENER    optional   RDP listener name, default RDP-Tcp
#   DEPLOY_WIN_RDP_RESTART     optional   "1" to restart TermService after install.
#   									  Active RDP sessions will drop!

windows_rdp_deploy() {
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

  if ! _exists "ssh"; then
    _err "ssh is required but was not found in PATH."
    return 1
  fi

  # ---- configuration ------------------------------------------------------
  _getdeployconf DEPLOY_WIN_RDP_HOST
  _getdeployconf DEPLOY_WIN_RDP_USER
  _getdeployconf DEPLOY_WIN_RDP_PORT
  _getdeployconf DEPLOY_WIN_RDP_SSH_OPTS
  _getdeployconf DEPLOY_WIN_RDP_LISTENER
  _getdeployconf DEPLOY_WIN_RDP_RESTART

  if [ -z "$DEPLOY_WIN_RDP_HOST" ]; then
    _err "DEPLOY_WIN_RDP_HOST must be set."
    return 1
  fi

  _savedeployconf DEPLOY_WIN_RDP_HOST "$DEPLOY_WIN_RDP_HOST"
  [ -n "$DEPLOY_WIN_RDP_USER" ] && _savedeployconf DEPLOY_WIN_RDP_USER "$DEPLOY_WIN_RDP_USER"
  [ -n "$DEPLOY_WIN_RDP_PORT" ] && _savedeployconf DEPLOY_WIN_RDP_PORT "$DEPLOY_WIN_RDP_PORT"
  [ -n "$DEPLOY_WIN_RDP_SSH_OPTS" ] && _savedeployconf DEPLOY_WIN_RDP_SSH_OPTS "$DEPLOY_WIN_RDP_SSH_OPTS"
  [ -n "$DEPLOY_WIN_RDP_LISTENER" ] && _savedeployconf DEPLOY_WIN_RDP_LISTENER "$DEPLOY_WIN_RDP_LISTENER"
  [ -n "$DEPLOY_WIN_RDP_RESTART" ] && _savedeployconf DEPLOY_WIN_RDP_RESTART "$DEPLOY_WIN_RDP_RESTART"

  _port="${DEPLOY_WIN_RDP_PORT:-22}"
  _listener="${DEPLOY_WIN_RDP_LISTENER:-RDP-Tcp}"
  if [ -n "$DEPLOY_WIN_RDP_USER" ]; then
    _target="$DEPLOY_WIN_RDP_USER@$DEPLOY_WIN_RDP_HOST"
  else
    _target="$DEPLOY_WIN_RDP_HOST"
  fi
  _pfx_pass="acme"

  # ---- build thumbprint + PFX locally ------------------------------------
  _thumb="$(_fingerprint "$_ccert" 'sha1')"
  if [ -z "$_thumb" ]; then
    _err "Failed to compute certificate thumbprint."
    return 1
  fi
  _debug "Thumbprint: $_thumb"

  _debug "Building PFX at $_pfx_file"
  _pfx_file="$(_mktemp)"
  if ! _toPkcs "$_pfx_file" "$_ckey" "$_ccert" "$_cca" "$_pfx_pass"; then
    _err "Failed to build PFX archive."
    rm -f "$_pfx_file"
    return 1
  fi
  _pfx_b64=$(_base64 "multiline" <"$_pfx_file")
  rm -f "$_pfx_file"

  # ---- build installer script --------------------------------------------
  if [ "$DEPLOY_WIN_RDP_RESTART" = "1" ]; then
    _restart_ps='Restart-Service -Name TermService -Force'
  else
    _restart_ps='# New RdP connections will pick up the new cert automatically.'
  fi

  # Escape every literal `$` with `\$` so the shell does not expand it.
  # Values substituted from shell: $_pfx_b64, $_pfx_pass, $_thumb, $_listener.
  _ps1=$(
    cat <<PSEOF

\$ErrorActionPreference = 'Stop'

\$pfxBytes = [Convert]::FromBase64String('${_pfx_b64}')

# Note: It is quite important to use a X509Certificate2Collection here in any case, since we otherwise
# could run into quite a lot of trouble when importing the certificate including its entire chain
# and its private key. Windows might behave arbitrarily and not consistently import the certificate
# at all - unless "Exportable" is included in the storage flags. However, then the certificate seems
# unaccessible to TermService for some weird reasons despite all permissions being set (at least on my
# Win 11 lab machine). This might be some security setting that prevents TermService from working with
# exportable keys? I don't know - importing the entire collection including chain or not always fixes
# the issues.
#
# Note2: If you should have kicked yourself out for some reason, then deleting the certificate will make
# TermService restore the original, self-signed certificate after at least after the second login attempt.
# Deleting the certificate can be easily accomplished via the Powershell, since SSH access will still be
# present in any case - the following command should get you out of trouble:
# \$cert = Get-ChildItem -Path 'Cert:\LocalMachine\My\\${_thumb}' | Select-Object -First 1 | Remove-Item

\$flags    = [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]'MachineKeySet,PersistKeySet'
\$certs    = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2Collection
\$certs.Import(\$pfxBytes, '${_pfx_pass}', \$flags)

\$store = [System.Security.Cryptography.X509Certificates.X509Store]::new('My', 'LocalMachine')
\$store.Open('ReadWrite')
\$store.AddRange(\$certs)
\$store.Close()
Write-Host "Installed certs into LocalMachine\\My"

\$ts = Get-CimInstance -Namespace root/cimv2/terminalservices -ClassName Win32_TSGeneralSetting -Filter "TerminalName='${_listener}'"
if (-not \$ts) { throw "Listener '${_listener}' not found." }
Set-CimInstance -InputObject \$ts -Property @{SSLCertificateSHA1Hash="${_thumb}"}
Write-Host "Listener ${_listener} now uses ${_thumb}"

${_restart_ps}
PSEOF
  )
  _debug "Powershell script:${_ps1}"

  # ---- run over a single ssh connection ----------------------------------
  _ssh_opts="-o BatchMode=yes -p $_port"
  if [ -n "$DEPLOY_WIN_RDP_SSH_OPTS" ]; then
    _ssh_opts="$_ssh_opts $DEPLOY_WIN_RDP_SSH_OPTS"
  fi

  _info "Deploying to $DEPLOY_WIN_RDP_HOST ..."
  # shellcheck disable=SC2086
  if ! printf '%s\n' "$_ps1" | ssh $_ssh_opts "$_target" \
    'powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command -'; then
    _err "Remote install failed. Re-run acme.sh with --debug to see the PowerShell output."
    return 1
  fi

  _info "Certificate for $_cdomain deployed and bound to $_listener on $DEPLOY_WIN_RDP_HOST."
  return 0
}
