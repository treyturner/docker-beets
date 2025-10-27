#!/bin/sh
set -e

# Apply umask for the whole process tree
umask "${UMASK:-0002}"

# Defaults (can be overridden at runtime)
PUID="${PUID:-99}"
PGID="${PGID:-100}"

# Install runtime packages if requested
if [ -n "${RUNTIME_APK_PACKAGES}" ]; then
  echo "Installing runtime APK packages: ${RUNTIME_APK_PACKAGES}"
  apk add --no-cache ${RUNTIME_APK_PACKAGES}
fi

if [ -n "${RUNTIME_PIP_PACKAGES}" ]; then
  echo "Installing runtime Python packages: ${RUNTIME_PIP_PACKAGES}"
  python3 -m pip install --no-cache-dir ${RUNTIME_PIP_PACKAGES}
fi

# Create group if missing
if ! getent group "${PGID}" >/dev/null 2>&1; then
  addgroup -g "${PGID}" -S beets >/dev/null 2>&1 || true
fi

# Determine group name for su-exec
GRP_NAME="$(getent group "${PGID}" | cut -d: -f1)"
[ -z "${GRP_NAME}" ] && GRP_NAME="beets"

# Create user if missing
if ! getent passwd "${PUID}" >/dev/null 2>&1; then
  adduser -S -D -H -u "${PUID}" -G "${GRP_NAME}" beets >/dev/null 2>&1 || true
fi

USR_NAME="$(getent passwd "${PUID}" | cut -d: -f1)"
[ -z "${USR_NAME}" ] && USR_NAME="beets"

# Ensure ownership of /config (best-effort; ignore failures)
chown -R "${PUID}:${PGID}" /config 2>/dev/null || true

# Exec the requested command as the target user
exec su-exec "${PUID}:${PGID}" "$@"
