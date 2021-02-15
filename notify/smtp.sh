#!/usr/bin/env sh

# support smtp

# Please report bugs to https://github.com/acmesh-official/acme.sh/issues/3358

# This implementation uses either curl or Python (3 or 2.7).
# (See also the "mail" notify hook, which supports other ways to send mail.)

# SMTP_FROM="from@example.com"  # required
# SMTP_TO="to@example.com"  # required
# SMTP_HOST="smtp.example.com"  # required
# SMTP_PORT="25"  # defaults to 25, 465 or 587 depending on SMTP_SECURE
# SMTP_SECURE="none"  # one of "none", "ssl" (implicit TLS, TLS Wrapper), "tls" (explicit TLS, STARTTLS)
# SMTP_USERNAME=""  # set if SMTP server requires login
# SMTP_PASSWORD=""  # set if SMTP server requires login
# SMTP_TIMEOUT="30"  # seconds for SMTP operations to timeout
# SMTP_BIN="/path/to/curl_or_python"  # default finds first of curl, python3, or python on PATH

# subject content statuscode
smtp_send() {
  _SMTP_SUBJECT="$1"
  _SMTP_CONTENT="$2"
  # UNUSED: _statusCode="$3" # 0: success, 1: error 2($RENEW_SKIP): skipped

  # Load config:
  SMTP_FROM="${SMTP_FROM:-$(_readaccountconf_mutable SMTP_FROM)}"
  SMTP_TO="${SMTP_TO:-$(_readaccountconf_mutable SMTP_TO)}"
  SMTP_HOST="${SMTP_HOST:-$(_readaccountconf_mutable SMTP_HOST)}"
  SMTP_PORT="${SMTP_PORT:-$(_readaccountconf_mutable SMTP_PORT)}"
  SMTP_SECURE="${SMTP_SECURE:-$(_readaccountconf_mutable SMTP_SECURE)}"
  SMTP_USERNAME="${SMTP_USERNAME:-$(_readaccountconf_mutable SMTP_USERNAME)}"
  SMTP_PASSWORD="${SMTP_PASSWORD:-$(_readaccountconf_mutable SMTP_PASSWORD)}"
  SMTP_TIMEOUT="${SMTP_TIMEOUT:-$(_readaccountconf_mutable SMTP_TIMEOUT)}"
  SMTP_BIN="${SMTP_BIN:-$(_readaccountconf_mutable SMTP_BIN)}"

  _debug "SMTP_FROM" "$SMTP_FROM"
  _debug "SMTP_TO" "$SMTP_TO"
  _debug "SMTP_HOST" "$SMTP_HOST"
  _debug "SMTP_PORT" "$SMTP_PORT"
  _debug "SMTP_SECURE" "$SMTP_SECURE"
  _debug "SMTP_USERNAME" "$SMTP_USERNAME"
  _secure_debug "SMTP_PASSWORD" "$SMTP_PASSWORD"
  _debug "SMTP_TIMEOUT" "$SMTP_TIMEOUT"
  _debug "SMTP_BIN" "$SMTP_BIN"

  _debug "_SMTP_SUBJECT" "$_SMTP_SUBJECT"
  _debug "_SMTP_CONTENT" "$_SMTP_CONTENT"

  # Validate config and apply defaults:
  # _SMTP_* variables are the resolved (with defaults) versions of SMTP_*.
  # (The _SMTP_* versions will not be stored in account conf.)

  if [ -n "$SMTP_BIN" ] && ! _exists "$SMTP_BIN"; then
    _err "SMTP_BIN '$SMTP_BIN' does not exist."
    return 1
  fi
  _SMTP_BIN="$SMTP_BIN"
  if [ -z "$_SMTP_BIN" ]; then
    # Look for a command that can communicate with an SMTP server.
    # (Please don't add sendmail, ssmtp, mutt, mail, or msmtp here.
    # Those are already handled by the "mail" notify hook.)
    for cmd in curl python3 python2.7 python pypy3 pypy; do
      if _exists "$cmd"; then
        _SMTP_BIN="$cmd"
        break
      fi
    done
    if [ -z "$_SMTP_BIN" ]; then
      _err "The smtp notify-hook requires curl or Python, but can't find any."
      _err 'If you have one of them, define SMTP_BIN="/path/to/curl_or_python".'
      _err 'Otherwise, see if you can use the "mail" notify-hook instead.'
      return 1
    fi
    _debug "_SMTP_BIN" "$_SMTP_BIN"
  fi

  if [ -z "$SMTP_FROM" ]; then
    _err "You must define SMTP_FROM as the sender email address."
    return 1
  fi
  _SMTP_FROM="$SMTP_FROM"

  if [ -z "$SMTP_TO" ]; then
    _err "You must define SMTP_TO as the recipient email address."
    return 1
  fi
  _SMTP_TO="$SMTP_TO"

  if [ -z "$SMTP_HOST" ]; then
    _err "You must define SMTP_HOST as the SMTP server hostname."
    return 1
  fi
  _SMTP_HOST="$SMTP_HOST"

  _SMTP_SECURE="${SMTP_SECURE:-none}"
  case "$_SMTP_SECURE" in
  "none") smtp_default_port="25" ;;
  "ssl") smtp_default_port="465" ;;
  "tls") smtp_default_port="587" ;;
  *)
    _err "Invalid SMTP_SECURE='$SMTP_SECURE'. It must be 'ssl', 'tls' or 'none'."
    return 1
    ;;
  esac

  _SMTP_PORT="${SMTP_PORT:-$smtp_default_port}"
  if [ -z "$SMTP_PORT" ]; then
    _debug "_SMTP_PORT" "$_SMTP_PORT"
  fi

  _SMTP_USERNAME="$SMTP_USERNAME"
  _SMTP_PASSWORD="$SMTP_PASSWORD"
  _SMTP_TIMEOUT="${SMTP_TIMEOUT:-30}"

  # Run with --debug 2 (or above) to echo the transcript of the SMTP session.
  # Careful: this may include SMTP_PASSWORD in plaintext!
  if [ "${DEBUG:-$DEBUG_LEVEL_NONE}" -ge "$DEBUG_LEVEL_2" ]; then
    _SMTP_SHOW_TRANSCRIPT="True"
  else
    _SMTP_SHOW_TRANSCRIPT=""
  fi

  # Send the message:
  case "$(basename "$_SMTP_BIN")" in
  curl) _smtp_send=_smtp_send_curl ;;
  py*) _smtp_send=_smtp_send_python ;;
  *)
    _err "Can't figure out how to invoke $_SMTP_BIN."
    _err "Check your SMTP_BIN setting."
    return 1
    ;;
  esac

  if ! smtp_output="$($_smtp_send)"; then
    _err "Error sending message with $_SMTP_BIN."
    if [ -n "$smtp_output" ]; then
      _err "$smtp_output"
    fi
    return 1
  fi

  # Save config only if send was successful:
  _saveaccountconf_mutable SMTP_BIN "$SMTP_BIN"
  _saveaccountconf_mutable SMTP_FROM "$SMTP_FROM"
  _saveaccountconf_mutable SMTP_TO "$SMTP_TO"
  _saveaccountconf_mutable SMTP_HOST "$SMTP_HOST"
  _saveaccountconf_mutable SMTP_PORT "$SMTP_PORT"
  _saveaccountconf_mutable SMTP_SECURE "$SMTP_SECURE"
  _saveaccountconf_mutable SMTP_USERNAME "$SMTP_USERNAME"
  _saveaccountconf_mutable SMTP_PASSWORD "$SMTP_PASSWORD"
  _saveaccountconf_mutable SMTP_TIMEOUT "$SMTP_TIMEOUT"

  return 0
}

# Send the message via curl using _SMTP_* variables
_smtp_send_curl() {
  # curl passes --mail-from and --mail-rcpt directly to the SMTP protocol without
  # additional parsing, and SMTP requires addr-spec only (no display names).
  # In the future, maybe try to parse the addr-spec out for curl args (non-trivial).
  if _email_has_display_name "$_SMTP_FROM"; then
    _err "curl smtp only allows a simple email address in SMTP_FROM."
    _err "Change your SMTP_FROM='$SMTP_FROM' to remove the display name."
    return 1
  fi
  if _email_has_display_name "$_SMTP_TO"; then
    _err "curl smtp only allows simple email addresses in SMTP_TO."
    _err "Change your SMTP_TO='$SMTP_TO' to remove the display name(s)."
    return 1
  fi

  # Build curl args in $@

  case "$_SMTP_SECURE" in
  none)
    set -- --url "smtp://${_SMTP_HOST}:${_SMTP_PORT}"
    ;;
  ssl)
    set -- --url "smtps://${_SMTP_HOST}:${_SMTP_PORT}"
    ;;
  tls)
    set -- --url "smtp://${_SMTP_HOST}:${_SMTP_PORT}" --ssl-reqd
    ;;
  *)
    # This will only occur if someone adds a new SMTP_SECURE option above
    # without updating this code for it.
    _err "Unhandled _SMTP_SECURE='$_SMTP_SECURE' in _smtp_send_curl"
    _err "Please re-run with --debug and report a bug."
    return 1
    ;;
  esac

  set -- "$@" \
    --upload-file - \
    --mail-from "$_SMTP_FROM" \
    --max-time "$_SMTP_TIMEOUT"

  # Burst comma-separated $_SMTP_TO into individual --mail-rcpt args.
  _to="${_SMTP_TO},"
  while [ -n "$_to" ]; do
    _rcpt="${_to%%,*}"
    _to="${_to#*,}"
    set -- "$@" --mail-rcpt "$_rcpt"
  done

  _smtp_login="${_SMTP_USERNAME}:${_SMTP_PASSWORD}"
  if [ "$_smtp_login" != ":" ]; then
    set -- "$@" --user "$_smtp_login"
  fi

  if [ "$_SMTP_SHOW_TRANSCRIPT" = "True" ]; then
    set -- "$@" --verbose
  else
    set -- "$@" --silent --show-error
  fi

  raw_message="$(_smtp_raw_message)"

  _debug2 "curl command:" "$_SMTP_BIN" "$*"
  _debug2 "raw_message:\n$raw_message"

  echo "$raw_message" | "$_SMTP_BIN" "$@"
}

# Output an RFC-822 / RFC-5322 email message using _SMTP_* variables
_smtp_raw_message() {
  echo "From: $_SMTP_FROM"
  echo "To: $_SMTP_TO"
  echo "Subject: $(_mime_encoded_word "$_SMTP_SUBJECT")"
  if _exists date; then
    echo "Date: $(date +'%a, %-d %b %Y %H:%M:%S %z')"
  fi
  echo "Content-Type: text/plain; charset=utf-8"
  echo "X-Mailer: acme.sh --notify-hook smtp"
  echo
  echo "$_SMTP_CONTENT"
}

# Convert text to RFC-2047 MIME "encoded word" format if it contains non-ASCII chars
# text
_mime_encoded_word() {
  _text="$1"
  # (regex character ranges like [a-z] can be locale-dependent; enumerate ASCII chars to avoid that)
  _ascii='] $`"'"[!#%&'()*+,./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ~^_abcdefghijklmnopqrstuvwxyz{|}~-"
  if expr "$_text" : "^.*[^$_ascii]" >/dev/null; then
    # At least one non-ASCII char; convert entire thing to encoded word
    printf "%s" "=?UTF-8?B?$(printf "%s" "$_text" | _base64)?="
  else
    # Just printable ASCII, no conversion needed
    printf "%s" "$_text"
  fi
}

# Simple check for display name in an email address (< > or ")
# email
_email_has_display_name() {
  _email="$1"
  expr "$_email" : '^.*[<>"]' > /dev/null
}


# Send the message via Python using _SMTP_* variables
_smtp_send_python() {
  _debug "Python version" "$("$_SMTP_BIN" --version 2>&1)"

  # language=Python
  "$_SMTP_BIN" <<EOF
# This code is meant to work with either Python 2.7.x or Python 3.4+.
try:
    try:
        from email.message import EmailMessage
    except ImportError:
        from email.mime.text import MIMEText as EmailMessage  # Python 2
    from smtplib import SMTP, SMTP_SSL, SMTPException
    from socket import error as SocketError
except ImportError as err:
    print("A required Python standard package is missing. This system may have"
          " a reduced version of Python unsuitable for sending mail: %s" % err)
    exit(1)

show_transcript = """$_SMTP_SHOW_TRANSCRIPT""" == "True"

smtp_host = """$_SMTP_HOST"""
smtp_port = int("""$_SMTP_PORT""")
smtp_secure = """$_SMTP_SECURE"""
username = """$_SMTP_USERNAME"""
password = """$_SMTP_PASSWORD"""
timeout=int("""$_SMTP_TIMEOUT""")  # seconds

from_email="""$_SMTP_FROM"""
to_emails="""$_SMTP_TO"""  # can be comma-separated
subject="""$_SMTP_SUBJECT"""
content="""$_SMTP_CONTENT"""

try:
    msg = EmailMessage()
    msg.set_content(content)
except (AttributeError, TypeError):
    # Python 2 MIMEText
    msg = EmailMessage(content)
msg["Subject"] = subject
msg["From"] = from_email
msg["To"] = to_emails

smtp = None
try:
    if smtp_secure == "ssl":
        smtp = SMTP_SSL(smtp_host, smtp_port, timeout=timeout)
    else:
        smtp = SMTP(smtp_host, smtp_port, timeout=timeout)
    smtp.set_debuglevel(show_transcript)
    if smtp_secure == "tls":
        smtp.starttls()
    if username or password:
        smtp.login(username, password)
    smtp.sendmail(msg["From"], msg["To"].split(","), msg.as_string())

except SMTPException as err:
    # Output just the error (skip the Python stack trace) for SMTP errors
    print("Error sending: %r" % err)
    exit(1)

except SocketError as err:
    print("Error connecting to %s:%d: %r" % (smtp_host, smtp_port, err))
    exit(1)

finally:
    if smtp is not None:
        smtp.quit()
EOF
}
