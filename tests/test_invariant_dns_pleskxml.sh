import pytest
import subprocess
import os
import tempfile


@pytest.mark.parametrize("payload", [
    '; rm -rf /',
    '$(whoami)',
    '`id`',
    'test.example.com',
])
def test_shell_metacharacters_not_executed(payload, tmp_path):
    """Invariant: Shell commands never include unsanitized user input - metacharacters must not execute."""
    marker = tmp_path / "pwned"
    # Craft a payload that would create a marker file if injection occurs
    inject_payload = f"; touch {marker}"
    
    script = tmp_path / "test_runner.sh"
    script.write_text(f"""#!/bin/bash
# Minimal stubs so the script can be sourced without network calls
_err() {{ true; }}
_info() {{ true; }}
_debug() {{ true; }}
_post() {{ echo "MOCK_POST"; }}
export pleskxml_uri="https://localhost:8443"
export pleskxml_user="test"
export pleskxml_pass="test"

source "{os.path.abspath('dnsapi/dns_pleskxml.sh')}"

# Call functions with adversarial input - override _pleskxml_api to avoid real calls
_pleskxml_api() {{ echo "MOCK_API_CALL: $1"; }}

fulldomain="{inject_payload}"
txtvalue="{payload}"
dns_pleskxml_add "$fulldomain" "$txtvalue" 2>&1 || true
dns_pleskxml_rm "$fulldomain" "$txtvalue" 2>&1 || true
""")
    script.chmod(0o755)
    
    result = subprocess.run(
        ["bash", str(script)],
        capture_output=True, text=True, timeout=10
    )
    
    # The marker file must NOT exist - if it does, injection succeeded
    assert not marker.exists(), (
        f"Command injection detected with payload: {inject_payload}\n"
        f"stdout: {result.stdout}\nstderr: {result.stderr}"
    )