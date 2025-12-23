#!/usr/bin/env bash
set -euo pipefail

# Config
CONTAINER="${BEETS_CONTAINER:-beets}"
BEETS_BIN="/usr/local/bin/beet"
DOCKER_USER_OPT=(--user "${BEETS_PUID:-99}:${BEETS_PGID:-100}")

# --- helpers ----------------------------------------------------------------

inside_container() {
  [[ -f /.dockerenv ]]
}

# Return index of the first non-flag (subcommand), or -1 if none
find_cmd_index() {
  local -a a=( "$@" )
  for ((i=0; i<${#a[@]}; i++)); do
    case "${a[i]}" in -*) ;; *) echo "$i"; return 0;; esac
  done
  echo -1
}

# Detect any --set / -s that specifies library=
has_library_set() {
  local -a a=( "$@" )
  for ((i=0; i<${#a[@]}; i++)); do
    case "${a[i]}" in
      --set|-s)
        (( i+1 < ${#a[@]} )) && [[ "${a[i+1]}" == *"library="* ]] && return 0
        ;;
      --set=*|-s=*)
        [[ "${a[i]#*=}" == *"library="* ]] && return 0
        ;;
    esac
  done
  return 1
}

# Build argv with default library injected only when needed
build_argv_with_library_default() {
  local -a in=( "$@" )
  local cmd_idx; cmd_idx="$(find_cmd_index "${in[@]}")"
  [[ "$cmd_idx" == "-1" ]] && { printf '%s\0' "${in[@]}"; return; }

  local sub="${in[$cmd_idx]}"
  [[ "$sub" != "import" ]] && { printf '%s\0' "${in[@]}"; return; }

  if has_library_set "${in[@]}"; then
    printf '%s\0' "${in[@]}"; return
  fi

  # insert --set library=Music right after 'import'
  local -a out
  out+=( "${in[@]:0:$cmd_idx+1}" )
  out+=( --set "library=Music" )
  out+=( "${in[@]:$cmd_idx+1}" )
  printf '%s\0' "${out[@]}"
}

# --- main -------------------------------------------------------------------

if [[ $# -eq 0 ]]; then
  if ! inside_container; then
    # No args and outside: open an interactive shell in the existing container
    exec docker exec -it "${DOCKER_USER_OPT[@]}" "$CONTAINER" bash -l
  else
    # No args and inside: just run beet with no args (help/usage)
    exec "$BEETS_BIN"
  fi
fi

if ! inside_container; then
  # Outside container: run beet first, then keep the shell open in that container
  mapfile -d '' beet_argv < <(build_argv_with_library_default "$@")
  exec docker exec -it "${DOCKER_USER_OPT[@]}" "$CONTAINER" bash -lc '
    set -e
    /usr/local/bin/beet "$@"
    status=$?
    printf "beet exit status: %s\n" "$status"
    exec bash -l
  ' bash "${beet_argv[@]}"
else
  # Inside container: run beet with adjusted args
  mapfile -d '' beet_argv < <(build_argv_with_library_default "$@")
  exec "$BEETS_BIN" "${beet_argv[@]}"
fi
