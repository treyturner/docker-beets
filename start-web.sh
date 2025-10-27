#!/bin/sh
set -e

# Determine config file location
CONFIG="${BEETSDIR:-/config}/config.yaml"

# Ensure config directory exists
mkdir -p "$(dirname "$CONFIG")"

# If no config exists, create a minimal one
if [ ! -f "$CONFIG" ]; then
  printf 'plugins:\n  - web\nweb:\n  host: 0.0.0.0\n' > "$CONFIG"
else
  # Config exists - determine if we need to modify it

  needs_plugin_update=false
  needs_host_update=false

  if ! yq -e '.plugins[]? | select(. == "web")' "$CONFIG" > /dev/null 2>&1; then
    needs_plugin_update=true
  fi

  if ! yq -e '.web.host == "0.0.0.0"' "$CONFIG" > /dev/null 2>&1; then
    needs_host_update=true
  fi

  if [ "$needs_plugin_update" = "true" ] || [ "$needs_host_update" = "true" ]; then
    # Function to create a backup of the config file with date-based naming
    backup_config() {
      local config_file="$1"
      local config_dir
      local config_basename
      local date_stamp
      local backup_base
      local backup_file
      local serial

      config_dir="$(dirname "$config_file")"
      config_basename="$(basename "$config_file" .yaml)"
      date_stamp="$(date +%Y-%m-%d)"
      backup_base="${config_dir}/${config_basename}.${date_stamp}.backup"
      backup_file="${backup_base}.yaml"

      if [ -f "$backup_file" ]; then
        serial=1
        while [ -f "${backup_base}-${serial}.yaml" ]; do
          serial=$((serial + 1))
        done
        backup_file="${backup_base}-${serial}.yaml"
      fi

      cp "$config_file" "$backup_file"
      echo "Created backup: $backup_file"
    }

    backup_config "$CONFIG"

    if [ "$needs_plugin_update" = "true" ]; then
      yq -i '
        .plugins = (.plugins // []) |
        .plugins = (.plugins + ["web"] | unique)
      ' "$CONFIG"
    fi

    if [ "$needs_host_update" = "true" ]; then
      yq -i '.web.host = "0.0.0.0"' "$CONFIG"
    fi

    echo "Updated config to enable web plugin"
  else
    echo "Config already has web plugin and host binding; no changes made"
  fi
fi

# Start beets web server
exec beet web
