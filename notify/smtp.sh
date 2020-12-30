#!/usr/bin/env sh

# support smtp

# This implementation uses Python (2 or 3), which is available in many environments.
# If you don't have Python, try "mail" notification instead of "smtp".

# SMTP_FROM="from@example.com"  # required
# SMTP_TO="to@example.com"  # required
# SMTP_HOST="smtp.example.com"  # required
# SMTP_PORT="25"  # defaults to 25, 465 or 587 depending on SMTP_SECURE
# SMTP_SECURE="none"  # one of "none", "ssl" (implicit TLS, TLS Wrapper), "tls" (explicit TLS, STARTTLS)
# SMTP_USERNAME=""  # set if SMTP server requires login
# SMTP_PASSWORD=""  # set if SMTP server requires login
# SMTP_TIMEOUT="15"  # seconds for SMTP operations to timeout
# SMTP_PYTHON="/path/to/python"  # defaults to system python3 or python

smtp_send() {
  # Find a Python interpreter:
  SMTP_PYTHON="${SMTP_PYTHON:-$(_readaccountconf_mutable SMTP_PYTHON)}"
  if [ "$SMTP_PYTHON" ]; then
    if _exists "$SMTP_PYTHON"; then
      _saveaccountconf_mutable SMTP_PYTHON "$SMTP_PYTHON"
    else
      _err "SMTP_PYTHON '$SMTP_PYTHON' does not exist."
      return 1
    fi
  else
    # No SMTP_PYTHON setting; try to run default Python.
    # (This is not saved with the conf.)
    if _exists python3; then
      SMTP_PYTHON="python3"
    elif _exists python; then
      SMTP_PYTHON="python"
    else
      _err "Can't locate Python interpreter; please define SMTP_PYTHON."
      return 1
    fi
  fi
  _debug "SMTP_PYTHON" "$SMTP_PYTHON"
  _debug "Python version" "$($SMTP_PYTHON --version 2>&1)"

  # Validate other settings:
  SMTP_FROM="${SMTP_FROM:-$(_readaccountconf_mutable SMTP_FROM)}"
  if [ -z "$SMTP_FROM" ]; then
    _err "You must define SMTP_FROM as the sender email address."
    return 1
  fi

  SMTP_TO="${SMTP_TO:-$(_readaccountconf_mutable SMTP_TO)}"
  if [ -z "$SMTP_TO" ]; then
    _err "You must define SMTP_TO as the recipient email address."
    return 1
  fi

  SMTP_HOST="${SMTP_HOST:-$(_readaccountconf_mutable SMTP_HOST)}"
  if [ -z "$SMTP_HOST" ]; then
    _err "You must define SMTP_HOST as the SMTP server hostname."
    return 1
  fi
  SMTP_PORT="${SMTP_PORT:-$(_readaccountconf_mutable SMTP_PORT)}"

  SMTP_SECURE="${SMTP_SECURE:-$(_readaccountconf_mutable SMTP_SECURE)}"
  SMTP_SECURE="${SMTP_SECURE:-none}"
  case "$SMTP_SECURE" in
  "none") SMTP_DEFAULT_PORT="25" ;;
  "ssl") SMTP_DEFAULT_PORT="465" ;;
  "tls") SMTP_DEFAULT_PORT="587" ;;
  *)
    _err "Invalid SMTP_SECURE='$SMTP_SECURE'. It must be 'ssl', 'tls' or 'none'."
    return 1
    ;;
  esac

  SMTP_USERNAME="${SMTP_USERNAME:-$(_readaccountconf_mutable SMTP_USERNAME)}"
  SMTP_PASSWORD="${SMTP_PASSWORD:-$(_readaccountconf_mutable SMTP_PASSWORD)}"

  SMTP_TIMEOUT="${SMTP_TIMEOUT:-$(_readaccountconf_mutable SMTP_TIMEOUT)}"
  SMTP_DEFAULT_TIMEOUT="15"

  _saveaccountconf_mutable SMTP_FROM "$SMTP_FROM"
  _saveaccountconf_mutable SMTP_TO "$SMTP_TO"
  _saveaccountconf_mutable SMTP_HOST "$SMTP_HOST"
  _saveaccountconf_mutable SMTP_PORT "$SMTP_PORT"
  _saveaccountconf_mutable SMTP_SECURE "$SMTP_SECURE"
  _saveaccountconf_mutable SMTP_USERNAME "$SMTP_USERNAME"
  _saveaccountconf_mutable SMTP_PASSWORD "$SMTP_PASSWORD"
  _saveaccountconf_mutable SMTP_TIMEOUT "$SMTP_TIMEOUT"

  # Send the message:
  if ! _smtp_send "$@"; then
    _err "$smtp_send_output"
    return 1
  fi

  return 0
}

# _send subject content statuscode
# Send the message via Python using SMTP_* settings
_smtp_send() {
  _subject="$1"
  _content="$2"
  _statusCode="$3" #0: success, 1: error 2($RENEW_SKIP): skipped
  _debug "_subject" "$_subject"
  _debug "_content" "$_content"
  _debug "_statusCode" "$_statusCode"

  _debug "SMTP_FROM" "$SMTP_FROM"
  _debug "SMTP_TO" "$SMTP_TO"
  _debug "SMTP_HOST" "$SMTP_HOST"
  _debug "SMTP_PORT" "$SMTP_PORT"
  _debug "SMTP_DEFAULT_PORT" "$SMTP_DEFAULT_PORT"
  _debug "SMTP_SECURE" "$SMTP_SECURE"
  _debug "SMTP_USERNAME" "$SMTP_USERNAME"
  _secure_debug "SMTP_PASSWORD" "$SMTP_PASSWORD"
  _debug "SMTP_TIMEOUT" "$SMTP_TIMEOUT"
  _debug "SMTP_DEFAULT_TIMEOUT" "$SMTP_DEFAULT_TIMEOUT"

  if [ "${DEBUG:-$DEBUG_LEVEL_NONE}" -ge "$DEBUG_LEVEL_2" ]; then
    # Output the SMTP server dialogue. (Note this will include SMTP_PASSWORD!)
    smtp_debug="True"
  else
    smtp_debug=""
  fi

  # language=Python
  smtp_send_output="$(
    $SMTP_PYTHON <<EOF
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

smtp_debug = """$smtp_debug""" == "True"

smtp_host = """$SMTP_HOST"""
smtp_port = int("""${SMTP_PORT:-$SMTP_DEFAULT_PORT}""")
smtp_secure = """$SMTP_SECURE"""
username = """$SMTP_USERNAME"""
password = """$SMTP_PASSWORD"""
timeout=int("""${SMTP_TIMEOUT:-$SMTP_DEFAULT_TIMEOUT}""")  # seconds

from_email="""$SMTP_FROM"""
to_emails="""$SMTP_TO"""  # can be comma-separated
subject="""$_subject"""
content="""$_content"""

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
    smtp.set_debuglevel(smtp_debug)
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
  )"
  _ret=$?
  _debug "smtp_send_output" "$smtp_send_output"
  return "$_ret"
}
