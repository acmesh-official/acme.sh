#!/usr/bin/env sh

# support smtp

# Please report bugs to https://github.com/acmesh-official/acme.sh/issues/3358

# This implementation uses either curl or Python (3 or 2.7).
# (See also the "mail" notify hook, which supports other ways to send mail.)

# SMTP_FROM="from@example.com"  # required
# SMTP_TO="to@example.com"  # required
# SMTP_HOST="smtp.example.com"  # required
# SMTP_PORT="25"  # defaults to 25, 465 or 587 depending on SMTP_SECURE
# SMTP_SECURE="tls"  # one of "none", "ssl" (implicit TLS, TLS Wrapper), "tls" (explicit TLS, STARTTLS)
# SMTP_USERNAME=""  # set if SMTP server requires login
# SMTP_PASSWORD=""  # set if SMTP server requires login
# SMTP_TIMEOUT="30"  # seconds for SMTP operations to timeout
# SMTP_BIN="/path/to/python_or_curl"  # default finds first of python3, python2.7, python, pypy3, pypy, curl on PATH

SMTP_SECURE_DEFAULT="tls"
SMTP_TIMEOUT_DEFAULT="30"

# subject content statuscode
smtp_send() {
  SMTP_SUBJECT="$1"
  SMTP_CONTENT="$2"
  # UNUSED: _statusCode="$3" # 0: success, 1: error 2($RENEW_SKIP): skipped

  # Load and validate config:
  SMTP_BIN="$(_readaccountconf_mutable_default SMTP_BIN)"
  if [ -n "$SMTP_BIN" ] && ! _exists "$SMTP_BIN"; then
    _err "SMTP_BIN '$SMTP_BIN' does not exist."
    return 1
  fi
  if [ -z "$SMTP_BIN" ]; then
    # Look for a command that can communicate with an SMTP server.
    # (Please don't add sendmail, ssmtp, mutt, mail, or msmtp here.
    # Those are already handled by the "mail" notify hook.)
    for cmd in python3 python2.7 python pypy3 pypy curl; do
      if _exists "$cmd"; then
        SMTP_BIN="$cmd"
        break
      fi
    done
    if [ -z "$SMTP_BIN" ]; then
      _err "The smtp notify-hook requires curl or Python, but can't find any."
      _err 'If you have one of them, define SMTP_BIN="/path/to/curl_or_python".'
      _err 'Otherwise, see if you can use the "mail" notify-hook instead.'
      return 1
    fi
  fi
  _debug SMTP_BIN "$SMTP_BIN"
  _saveaccountconf_mutable_default SMTP_BIN "$SMTP_BIN"

  SMTP_FROM="$(_readaccountconf_mutable_default SMTP_FROM)"
  SMTP_FROM="$(_clean_email_header "$SMTP_FROM")"
  if [ -z "$SMTP_FROM" ]; then
    _err "You must define SMTP_FROM as the sender email address."
    return 1
  fi
  if _email_has_display_name "$SMTP_FROM"; then
    _err "SMTP_FROM must be only a simple email address (sender@example.com)."
    _err "Change your SMTP_FROM='$SMTP_FROM' to remove the display name."
    return 1
  fi
  _debug SMTP_FROM "$SMTP_FROM"
  _saveaccountconf_mutable_default SMTP_FROM "$SMTP_FROM"

  SMTP_TO="$(_readaccountconf_mutable_default SMTP_TO)"
  SMTP_TO="$(_clean_email_header "$SMTP_TO")"
  if [ -z "$SMTP_TO" ]; then
    _err "You must define SMTP_TO as the recipient email address(es)."
    return 1
  fi
  if _email_has_display_name "$SMTP_TO"; then
    _err "SMTP_TO must be only simple email addresses (to@example.com,to2@example.com)."
    _err "Change your SMTP_TO='$SMTP_TO' to remove the display name(s)."
    return 1
  fi
  _debug SMTP_TO "$SMTP_TO"
  _saveaccountconf_mutable_default SMTP_TO "$SMTP_TO"

  SMTP_HOST="$(_readaccountconf_mutable_default SMTP_HOST)"
  if [ -z "$SMTP_HOST" ]; then
    _err "You must define SMTP_HOST as the SMTP server hostname."
    return 1
  fi
  _debug SMTP_HOST "$SMTP_HOST"
  _saveaccountconf_mutable_default SMTP_HOST "$SMTP_HOST"

  SMTP_SECURE="$(_readaccountconf_mutable_default SMTP_SECURE "$SMTP_SECURE_DEFAULT")"
  case "$SMTP_SECURE" in
  "none") smtp_port_default="25" ;;
  "ssl") smtp_port_default="465" ;;
  "tls") smtp_port_default="587" ;;
  *)
    _err "Invalid SMTP_SECURE='$SMTP_SECURE'. It must be 'ssl', 'tls' or 'none'."
    return 1
    ;;
  esac
  _debug SMTP_SECURE "$SMTP_SECURE"
  _saveaccountconf_mutable_default SMTP_SECURE "$SMTP_SECURE" "$SMTP_SECURE_DEFAULT"

  SMTP_PORT="$(_readaccountconf_mutable_default SMTP_PORT "$smtp_port_default")"
  case "$SMTP_PORT" in
  *[!0-9]*)
    _err "Invalid SMTP_PORT='$SMTP_PORT'. It must be a port number."
    return 1
    ;;
  esac
  _debug SMTP_PORT "$SMTP_PORT"
  _saveaccountconf_mutable_default SMTP_PORT "$SMTP_PORT" "$smtp_port_default"

  SMTP_USERNAME="$(_readaccountconf_mutable_default SMTP_USERNAME)"
  _debug SMTP_USERNAME "$SMTP_USERNAME"
  _saveaccountconf_mutable_default SMTP_USERNAME "$SMTP_USERNAME"

  SMTP_PASSWORD="$(_readaccountconf_mutable_default SMTP_PASSWORD)"
  _secure_debug SMTP_PASSWORD "$SMTP_PASSWORD"
  _saveaccountconf_mutable_default SMTP_PASSWORD "$SMTP_PASSWORD"

  SMTP_TIMEOUT="$(_readaccountconf_mutable_default SMTP_TIMEOUT "$SMTP_TIMEOUT_DEFAULT")"
  _debug SMTP_TIMEOUT "$SMTP_TIMEOUT"
  _saveaccountconf_mutable_default SMTP_TIMEOUT "$SMTP_TIMEOUT" "$SMTP_TIMEOUT_DEFAULT"

  SMTP_X_MAILER="$(_clean_email_header "$PROJECT_NAME $VER --notify-hook smtp")"

  # Run with --debug 2 (or above) to echo the transcript of the SMTP session.
  # Careful: this may include SMTP_PASSWORD in plaintext!
  if [ "${DEBUG:-$DEBUG_LEVEL_NONE}" -ge "$DEBUG_LEVEL_2" ]; then
    SMTP_SHOW_TRANSCRIPT="True"
  else
    SMTP_SHOW_TRANSCRIPT=""
  fi

  SMTP_SUBJECT=$(_clean_email_header "$SMTP_SUBJECT")
  _debug SMTP_SUBJECT "$SMTP_SUBJECT"
  _debug SMTP_CONTENT "$SMTP_CONTENT"

  # Send the message:
  case "$(basename "$SMTP_BIN")" in
  curl) _smtp_send=_smtp_send_curl ;;
  py*) _smtp_send=_smtp_send_python ;;
  *)
    _err "Can't figure out how to invoke '$SMTP_BIN'."
    _err "Check your SMTP_BIN setting."
    return 1
    ;;
  esac

  if ! smtp_output="$($_smtp_send)"; then
    _err "Error sending message with $SMTP_BIN."
    if [ -n "$smtp_output" ]; then
      _err "$smtp_output"
    fi
    return 1
  fi

  return 0
}

# Strip CR and NL from text to prevent MIME header injection
# text
_clean_email_header() {
  printf "%s" "$(echo "$1" | tr -d "\r\n")"
}

# Simple check for display name in an email address (< > or ")
# email
_email_has_display_name() {
  _email="$1"
  expr "$_email" : '^.*[<>"]' >/dev/null
}

##
## curl smtp sending
##

# Send the message via curl using SMTP_* variables
_smtp_send_curl() {
  # Build curl args in $@
  case "$SMTP_SECURE" in
  none)
    set -- --url "smtp://${SMTP_HOST}:${SMTP_PORT}"
    ;;
  ssl)
    set -- --url "smtps://${SMTP_HOST}:${SMTP_PORT}"
    ;;
  tls)
    set -- --url "smtp://${SMTP_HOST}:${SMTP_PORT}" --ssl-reqd
    ;;
  *)
    # This will only occur if someone adds a new SMTP_SECURE option above
    # without updating this code for it.
    _err "Unhandled SMTP_SECURE='$SMTP_SECURE' in _smtp_send_curl"
    _err "Please re-run with --debug and report a bug."
    return 1
    ;;
  esac

  set -- "$@" \
    --upload-file - \
    --mail-from "$SMTP_FROM" \
    --max-time "$SMTP_TIMEOUT"

  # Burst comma-separated $SMTP_TO into individual --mail-rcpt args.
  _to="${SMTP_TO},"
  while [ -n "$_to" ]; do
    _rcpt="${_to%%,*}"
    _to="${_to#*,}"
    set -- "$@" --mail-rcpt "$_rcpt"
  done

  _smtp_login="${SMTP_USERNAME}:${SMTP_PASSWORD}"
  if [ "$_smtp_login" != ":" ]; then
    set -- "$@" --user "$_smtp_login"
  fi

  if [ "$SMTP_SHOW_TRANSCRIPT" = "True" ]; then
    set -- "$@" --verbose
  else
    set -- "$@" --silent --show-error
  fi

  raw_message="$(_smtp_raw_message)"

  _debug2 "curl command:" "$SMTP_BIN" "$*"
  _debug2 "raw_message:\n$raw_message"

  echo "$raw_message" | "$SMTP_BIN" "$@"
}

# Output an RFC-822 / RFC-5322 email message using SMTP_* variables.
# (This assumes variables have already been cleaned for use in email headers.)
_smtp_raw_message() {
  echo "From: $SMTP_FROM"
  echo "To: $SMTP_TO"
  echo "Subject: $(_mime_encoded_word "$SMTP_SUBJECT")"
  echo "Date: $(_rfc2822_date)"
  echo "Content-Type: text/plain; charset=utf-8"
  echo "X-Mailer: $SMTP_X_MAILER"
  echo
  echo "$SMTP_CONTENT"
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

# Output current date in RFC-2822 Section 3.3 format as required in email headers
# (e.g., "Mon, 15 Feb 2021 14:22:01 -0800")
_rfc2822_date() {
  # Notes:
  #   - this is deliberately not UTC, because it "SHOULD express local time" per spec
  #   - the spec requires weekday and month in the C locale (English), not localized
  #   - this date format specifier has been tested on Linux, Mac, Solaris and FreeBSD
  _old_lc_time="$LC_TIME"
  LC_TIME=C
  date +'%a, %-d %b %Y %H:%M:%S %z'
  LC_TIME="$_old_lc_time"
}

##
## Python smtp sending
##

# Send the message via Python using SMTP_* variables
_smtp_send_python() {
  _debug "Python version" "$("$SMTP_BIN" --version 2>&1)"

  # language=Python
  "$SMTP_BIN" <<PYTHON
# This code is meant to work with either Python 2.7.x or Python 3.4+.
try:
    try:
        from email.message import EmailMessage
        from email.policy import default as email_policy_default
    except ImportError:
        # Python 2 (or < 3.3)
        from email.mime.text import MIMEText as EmailMessage
        email_policy_default = None
    from email.utils import formatdate as rfc2822_date
    from smtplib import SMTP, SMTP_SSL, SMTPException
    from socket import error as SocketError
except ImportError as err:
    print("A required Python standard package is missing. This system may have"
          " a reduced version of Python unsuitable for sending mail: %s" % err)
    exit(1)

show_transcript = """$SMTP_SHOW_TRANSCRIPT""" == "True"

smtp_host = """$SMTP_HOST"""
smtp_port = int("""$SMTP_PORT""")
smtp_secure = """$SMTP_SECURE"""
username = """$SMTP_USERNAME"""
password = """$SMTP_PASSWORD"""
timeout=int("""$SMTP_TIMEOUT""")  # seconds
x_mailer="""$SMTP_X_MAILER"""

from_email="""$SMTP_FROM"""
to_emails="""$SMTP_TO"""  # can be comma-separated
subject="""$SMTP_SUBJECT"""
content="""$SMTP_CONTENT"""

try:
    msg = EmailMessage(policy=email_policy_default)
    msg.set_content(content)
except (AttributeError, TypeError):
    # Python 2 MIMEText
    msg = EmailMessage(content)
msg["Subject"] = subject
msg["From"] = from_email
msg["To"] = to_emails
msg["Date"] = rfc2822_date(localtime=True)
msg["X-Mailer"] = x_mailer

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
PYTHON
}

##
## Conf helpers
##

#_readaccountconf_mutable_default name default_value
# Given a name like MY_CONF:
#   - if MY_CONF is set and non-empty, output $MY_CONF
#   - if MY_CONF is set _empty_, output $default_value
#     (lets user `export MY_CONF=` to clear previous saved value
#     and return to default, without user having to know default)
#   - otherwise if _readaccountconf_mutable MY_CONF is non-empty, return that
#     (value of SAVED_MY_CONF from account.conf)
#   - otherwise output $default_value
_readaccountconf_mutable_default() {
  _name="$1"
  _default_value="$2"

  eval "_value=\"\$$_name\""
  eval "_name_is_set=\"\${${_name}+true}\""
  # ($_name_is_set is "true" if $$_name is set to anything, including empty)
  if [ -z "${_value}" ] && [ "${_name_is_set:-}" != "true" ]; then
    _value="$(_readaccountconf_mutable "$_name")"
  fi
  if [ -z "${_value}" ]; then
    _value="$_default_value"
  fi
  printf "%s" "$_value"
}

#_saveaccountconf_mutable_default name value default_value base64encode
# Like _saveaccountconf_mutable, but if value is default_value
# then _clearaccountconf_mutable instead
_saveaccountconf_mutable_default() {
  _name="$1"
  _value="$2"
  _default_value="$3"
  _base64encode="$4"

  if [ "$_value" != "$_default_value" ]; then
    _saveaccountconf_mutable "$_name" "$_value" "$_base64encode"
  else
    _clearaccountconf_mutable "$_name"
  fi
}
