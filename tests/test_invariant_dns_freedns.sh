import pytest
import subprocess
import os


@pytest.mark.parametrize("payload", [
    '$(rm -rf /tmp/pwned)',           # command substitution exploit
    '`id > /tmp/pwned`',             # backtick command injection
    '; echo pwned > /tmp/pwned;',    # semicolon injection
    'legitimate-domain.example.com',  # valid input (baseline)
])
def test_freedns_no_shell_injection_in_domain(payload, tmp_path):
    """Invariant: Shell metacharacters in domain names must not execute arbitrary commands."""
    marker_file = tmp_path / "pwned"
    
    # Source the script and call dns_freedns_rm with adversarial domain/data_id
    # We expect the function to fail gracefully (non-zero exit or error message)
    # but NEVER execute injected shell commands.
    script = f"""
        export FREEDNS_User="testuser"
        export FREEDNS_Password="testpass"
        export _H1=""
        # Stub network functions to avoid real HTTP calls
        _get() {{ return 1; }}
        _post() {{ return 1; }}
        _err() {{ :; }}
        _info() {{ :; }}
        _debug() {{ :; }}
        _debug2() {{ :; }}
        _debug3() {{ :; }}
        _contains() {{ echo "$1" | grep -qF "$2"; }}
        _urlencode() {{ echo "$1"; }}
        export PWNED_MARKER="{marker_file}"
        export -f _get _post _err _info _debug _debug2 _debug3 _contains _urlencode
        . ./dnsapi/dns_freedns.sh
        data_id='{payload}'
        fulldomain='{payload}'
        dns_freedns_rm "$fulldomain" "test_txt_value" 2>/dev/null
        exit 0
    """
    
    result = subprocess.run(
        ["bash", "-c", script],
        capture_output=True,
        text=True,
        timeout=10,
        cwd=os.path.dirname(os.path.dirname(os.path.abspath(__file__))) or "."
    )
    
    # The critical security invariant: no injected command was executed
    assert not marker_file.exists(), \
        f"Shell injection succeeded with payload: {payload}"
    assert not os.path.exists("/tmp/pwned"), \
        f"Shell injection wrote to /tmp/pwned with payload: {payload}"