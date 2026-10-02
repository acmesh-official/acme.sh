# GitHub Copilot Shell Scripting (sh) Review Instructions

## 🎯 Overall Goal

Your role is to act as a rigorous yet helpful senior engineer, reviewing Shell script code (`.sh` files). Ensure the code exhibits the highest levels of robustness, security, and portability.
The review must focus on risks unique to Shell scripting, such as proper quoting, robust error handling, and the secure execution of external commands.

## 📝 Required Output Format

Please adhere to the previous format: organize the feedback into a single, structured report, using the three-level marking system:

1.  **🔴 Critical Issues (Must Fix Before Merge)**
2.  **🟡 Suggestions (Improvements to Consider)**
3.  **✅ Good Practices (Points to Commend)**

---

## 🔍 Focus Areas and Rules for Shell

### 1. Robustness and Error Handling

* **Shebang:** Check that the script starts with the correct Shebang, must be "#!/usr/bin/env sh".
* **Startup Options:** **(🔴 Critical)** Enforce the use of the following combination at the start of the script for safety and robustness:
    * `set -e`: Exit immediately if a command exits with a non-zero status.
    * `set -u`: Treat unset variables as an error and exit.
    * `set -o pipefail`: Ensure the whole pipeline fails if any command in the pipe fails.
* **Exit Codes:** Ensure functions and the main script use `exit 0` for success and a non-zero exit code upon failure.
* **Temporary Files:** Check for the use of `mktemp` when creating temporary files to prevent race conditions and security risks.

### 2. Security and Quoting

* **Variable Quoting:** **(🔴 Critical)** Check that all variable expansions (like `$VAR` and `$(COMMAND)`) are properly enclosed in **double quotes** (i.e., `"$VAR"` and `"$(COMMAND)"`) to prevent **Word Splitting** and **Globbing**.
* **Hardcoded Secrets:** **(🔴 Critical)** Find and flag any hardcoded passwords, keys, tokens, or authentication details.
* **Untrusted Input:** Verify that all user input, command-line arguments (`$1`, `$2`, etc.), or environment variables are rigorously validated and sanitized before use.
* **Avoid `eval`:** Warn against and suggest alternatives to using `eval`, as it can lead to arbitrary code execution.

### 3. Readability and Maintainability

* **Function Usage:** Recommend wrapping complex or reusable logic within clearly named functions.
* **Local Variables:** Check that variables inside functions are declared using the `local` keyword to avoid unintentionally modifying global state.
* **Naming Convention:** Variable names should use uppercase letters and underscores (e.g., `MY_VARIABLE`), or follow established project conventions.
* **Test Conditions:** Encourage the use of Bash's **double brackets `[[ ... ]]`** for conditional tests, as it is generally safer and more powerful (e.g., supports pattern matching and avoids Word Splitting) than single brackets `[ ... ]`.
* **Command Substitution:** Encourage using `$(command)` over backticks `` `command` `` for command substitution, as it is easier to nest and improves readability.

### 4. External Commands and Environment

* **`for` Loops:** Warn against patterns like `for i in $(cat file)` or `for i in $(ls)` and recommend the more robust `while IFS= read -r line` pattern for safely processing file contents or filenames that might contain spaces.
* **Use existing acme.sh functions whenever possible.** For example: do not use `tr '[:upper:]' '[:lower:]'`, use `_lower_case` instead.
* **Do not use `head -n`.** Use the `_head_n()` function instead.
* **Do not use `curl` or `wget`.** Use the `_post()` and `_get()` functions instead.

---

### 5. Review Rules for Files Under `dnsapi/`:

* **Each file must contain a `{filename}_add` function** for adding DNS TXT records. It should use `_readaccountconf_mutable` to read the API key and `_saveaccountconf_mutable` to save it. Do not use `_saveaccountconf` or `_readaccountconf`.


## ❌ Things to Avoid

* Do not comment on purely stylistic issues like spacing or indentation, which should be handled by tools like ShellCheck or Prettier.
* Do not be overly verbose unless a significant issue is found. Keep feedback concise and actionable.





