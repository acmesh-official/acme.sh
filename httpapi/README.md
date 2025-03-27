# HTTP API Validation Plugin

This directory contains plugins for acme.sh's HTTP API validation system. These plugins allow you to deploy ACME HTTP-01 challenge files to remote servers using various methods without requiring direct filesystem access.

## Usage

To use an HTTP API validation plugin, there are two ways to specify it:

### Method 1: Using the `--webroot` parameter with the plugin name prefix:

```bash
acme.sh --issue -d example.com --webroot http_scp
```

### Method 2: Using the dedicated `--http-api` parameter:

```bash
acme.sh --issue -d example.com --http-api http_scp
```

The second method is preferred as it's more explicit about the validation method being used.

## Available Plugins

- `http_scp`: Deploy challenge files via SCP to a remote web server
- `http_local`: Deploy challenge files to a local directory (for testing)

## Using HTTP API Plugins

Before using an HTTP API plugin, you need to set the required environment variables:

```bash
# For SCP plugin
export HTTP_SCP_USER="username"
export HTTP_SCP_HOST="example.com"
export HTTP_SCP_PATH="/var/www/html"
# Optional
export HTTP_SCP_PORT="22"
export HTTP_SCP_KEY="/path/to/ssh/key"

# For Local plugin
export HTTP_LOCAL_DIR="/var/www/html"
export HTTP_LOCAL_MKDIR="true"  # Create directory if it doesn't exist
export HTTP_LOCAL_VERIFY="true"  # Simple curl verification

# Then issue your certificate
acme.sh --issue -d example.com --http-api http_scp
```

These environment variables will be saved to your account configuration for future use.

## Creating Your Own Plugin

Plugins are shell scripts with at least two functions:

1. `<plugin-name>_deploy`: Deploy the challenge file
2. `<plugin-name>_rm`: Remove the challenge file

Here's a minimal example:

```bash
#!/usr/bin/env sh

# Deploy the challenge file
http_myplugin_deploy() {
  local domain="$1"
  local token="$2"
  local keyauthorization="$3"

  # Deploy the challenge file to your web server
  # ...

  return 0  # Return 0 for success, non-zero for failure
}

# Remove the challenge file
http_myplugin_rm() {
  local domain="$1"
  local token="$2"
  
  # Remove the challenge file
  # ...
  
  return 0  # Return 0 for success, non-zero for failure
}
```

## Plugin Configuration

Typically, plugins will need configuration settings like server addresses, credentials, etc. These should be provided as environment variables:

```bash
export HTTP_MYPLUGIN_HOST="example.com"
export HTTP_MYPLUGIN_USER="username"
export HTTP_MYPLUGIN_PASSWORD="password"
# etc...

acme.sh --issue -d example.com --http-api http_myplugin
```

Alternatively, you can save these values in your acme.sh account configuration file for future use.

## Example: Using the SCP Plugin

```bash
# Set required environment variables
export HTTP_SCP_USER="username"
export HTTP_SCP_HOST="remote.server.com"
export HTTP_SCP_PATH="/var/www/html"
# Optional:
export HTTP_SCP_PORT="22"
export HTTP_SCP_KEY="/path/to/ssh/key"

# Issue certificate using SCP validation
acme.sh --issue -d example.com --http-api http_scp
```
