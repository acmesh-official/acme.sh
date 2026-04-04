# GitHub Copilot Shell Scripting (sh) Review Instructions for acme.sh

## Overall Goal

Your role is to act as a rigorous yet helpful senior engineer, reviewing Shell script code (`.sh` files) for the [acme.sh](https://github.com/acmesh-official/acme.sh) project. Ensure the code exhibits the highest levels of robustness, security, and portability.
The review must focus on risks unique to Shell scripting, such as proper quoting, robust error handling, and the secure execution of external commands.

## Required Output Format

Organize the feedback into a single, structured report, using the three-level marking system:

1. **Critical Issues (Must Fix Before Merge)**
2. **Suggestions (Improvements to Consider)**
3. **Good Practices (Points to Commend)**

---

## Shell Compatibility

- **POSIX sh only** -- all scripts must target `sh`, not `bash`. No bash-isms allowed.
- **Shebang**: always use `#!/usr/bin/env sh` (not `#!/bin/sh`, not `#!/usr/bin/env bash`).
- **Use `return`, never `exit`** -- scripts are sourced, not executed as subprocesses. `exit` would kill the parent shell.
- **Cross-platform**: code must work on Linux, macOS, FreeBSD, Solaris, and BusyBox environments.

---

## Robustness and Error Handling

- **(Critical)** Enforce the use of the following combination at the start of the script for safety and robustness:
  - `set -e`: Exit immediately if a command exits with a non-zero status.
  - `set -u`: Treat unset variables as an error and exit.
  - `set -o pipefail`: Ensure the whole pipeline fails if any command in the pipe fails.
- **Always check return values** of function calls. If an error occurs, there must be a way to stop execution.
- **Return 1** after `_err` messages:
  ```sh
  if [ -z "$VARIABLE" ]; then
    _err "VARIABLE is required"
    return 1
  fi
  ```
- Check for the use of `mktemp` when creating temporary files to prevent race conditions and security risks.

---

## Security and Quoting

- **(Critical)** Check that all variable expansions (like `$VAR` and `$(COMMAND)`) are properly enclosed in **double quotes** (i.e., `"$VAR"` and `"$(COMMAND)"`) to prevent **Word Splitting** and **Globbing**.
- **(Critical)** Find and flag any hardcoded passwords, keys, tokens, or authentication details.
- Verify that all user input, command-line arguments (`$1`, `$2`, etc.), or environment variables are rigorously validated and sanitized before use.
- Avoid `eval` -- warn against and suggest alternatives, as it can lead to arbitrary code execution.

---

## Use Built-in Helper Functions

Never use raw shell commands when acme.sh provides a wrapper function. This is the most critical rule for portability.

| Instead of | Use |
|---|---|
| `tr '[:upper:]' '[:lower:]'` | `_lower_case()` |
| `head -n 1` | `_head_n 1` |
| `openssl dgst` / `openssl` | `_digest()` / `_hmac()` |
| `date` | `_utc_date()` with `sed`/`tr` |
| `curl` / `wget` | `_get()` or `_post()` |
| `sleep` | `_sleep` |
| `base64` / `openssl base64` | `_base64()` |
| `$(( ))` arithmetic | `_math()` |
| `grep -E` / `grep -Po` | `_egrep_o()` |
| `printf` | `echo` |
| `idn` command | `_idn()` / `_is_idn()` |

When fixing a pattern issue, fix **all instances** in the file, not just the one highlighted.

---

## Forbidden External Tools

Do not use these commands -- they are not portable across all target platforms:

- `jq` (parse JSON with built-in string manipulation)
- `grep -A` (removed throughout the project)
- `grep -Po` (Perl regex not available everywhere)
- `rev`, `xargs`, `iconv`
- If you must depend on an external tool, check with `_exists` first:
  ```sh
  if ! _exists jq; then
    _err "jq is required"
    return 1
  fi
  ```
- Warn against patterns like `for i in $(cat file)` or `for i in $(ls)` and recommend the more robust `while IFS= read -r line` pattern for safely processing file contents or filenames that might contain spaces.

---

## Configuration Management

Use the correct save/read functions depending on hook type:

- **DNS hooks**: `_readaccountconf_mutable` to read API keys, `_saveaccountconf_mutable` to save them. Do not use `_saveaccountconf` or `_readaccountconf`.
- **Deploy hooks**: `_savedeployconf` / `_getdeployconf`
- **Notification hooks**: use account conf functions.
- Save operations should only happen in the correct lifecycle function (e.g., `_issue()`).
- Use environment variables for all configurable values -- do not introduce hardcoded config files.
- Do not clear account conf without a clear reason.

---

## DNS API Conventions

- Read the [DNS API Dev Guide](https://github.com/acmesh-official/acme.sh/wiki/DNS-API-Dev-Guide) before writing a DNS plugin.
- Each file under `dnsapi/` must contain a `{filename}_add` function for adding DNS TXT records.
- The `_get_root()` loop counter `i` must start from `1` (not `2`) to support DNS alias mode.
- The `dns_*_rm()` function must remove records **by TXT value**, not by replacing/updating. See [#1261](https://github.com/acmesh-official/acme.sh/issues/1261).
- Preserve the `dns_*_info` metadata variable block in each DNS script header.

---

## Variable Naming

- Use CamelCase with provider prefix: `KINGHOST_Username` (not `KINGHOST_username`).
- Variable names should use uppercase letters and underscores (e.g., `MY_VARIABLE`), or follow established project conventions.
- Avoid confusingly similar names. Prefer one variable with comma-separated values over multiple variables (e.g., `CZ_Zones` with comma support instead of separate `CZ_Zone` and `CZ_Zones`).
- Do not define variables with the same name in different scopes.
- Variables inside functions should be declared using the `local` keyword to avoid unintentionally modifying global state.

---

## Code Style

- Use `shfmt` for formatting -- CI enforces it.
- Reduce indentation where possible.
- Single space, not double spaces.
- No trailing semicolons after `return` statements.
- Add a newline at the end of every file.
- Use `$(command)` over backticks `` `command` `` for command substitution.

---

## Simplicity

- Prefer hardcoded sensible defaults over unnecessary configuration variables (e.g., use `3600` for TTL instead of a `DESEC_TTL` variable).
- Reject over-engineered solutions. If it can be done in one line, do it in one line.
- Follow existing patterns in the codebase -- new hooks should look like existing hooks.
- Respect user choices: do not `chmod` files that already exist; the user's permissions take priority.

---

## Documentation Requirements

Before a PR can be merged, the following documentation must be provided:

- **Wiki page**: add or update the relevant page:
  - DNS APIs: [dnsapi](https://github.com/acmesh-official/acme.sh/wiki/dnsapi) or [dnsapi2](https://github.com/acmesh-official/acme.sh/wiki/dnsapi2)
  - Deploy hooks: [deployhooks](https://github.com/acmesh-official/acme.sh/wiki/deployhooks)
  - Notification hooks: [notify](https://github.com/acmesh-official/acme.sh/wiki/notify)
  - Options: [Options-and-Params](https://github.com/acmesh-official/acme.sh/wiki/Options-and-Params)
- **In-code usage**: add usage examples in the help text of `acme.sh` itself.
- **README**: add website URLs for new DNS providers.

---

## CI and Merge Hygiene

- All CI checks must pass before merge.
- Rebase to the latest `dev` branch frequently -- do not use merge commits.
- Enable GitHub Actions on your fork to catch errors early.
- Run the [DNS API Test](https://github.com/acmesh-official/acme.sh/wiki/DNS-API-Test) workflow for DNS plugins.
- For Docker changes, ensure the Dockerfile includes any required dependencies.

---

## Debug Logging

- Use `_debug2` (not `_debug3` or other levels) unless there is a specific reason for a different level.

---

## Things to Avoid in Reviews

- Do not comment on purely stylistic issues like spacing or indentation, which should be handled by tools like ShellCheck or `shfmt`.
- Do not be overly verbose unless a significant issue is found. Keep feedback concise and actionable.
