# syntax=docker/dockerfile:1.7
ARG PYTHON_VERSION=3.12
ARG PYTHON_BASE_SUFFIX=-alpine
FROM --platform=$BUILDPLATFORM python:${PYTHON_VERSION}${PYTHON_BASE_SUFFIX} AS builder

LABEL org.opencontainers.image.source="https://github.com/beetbox/beets"

# -------- Build-time args you can override at build --------
# Git ref (tag/branch/sha) to build from the beets repo
ARG BEETS_REF=v2.5.1
# Space-separated extra APK packages needed ONLY for building (e.g., ffmpeg-dev)
ARG APK_BUILD_DEPS=""
# Space-separated Python package sources bundled by default alongside beets
# (git URLs allowed; leave blank to skip)
ARG DEFAULT_PIP_SOURCES="beets-beatport4 beets-filetote git+https://github.com/edgars-supe/beets-importreplace.git requests requests_oauthlib beautifulsoup4 pyacoustid pylast langdetect flask Pillow"
# Space-separated distribution names installed in the runtime stage
ARG DEFAULT_PIP_PACKAGES="beets-beatport4 beets-filetote beets-importreplace requests requests_oauthlib beautifulsoup4 pyacoustid pylast langdetect flask Pillow"
# Comma-separated beets extras to enable (controls optional dependencies)
ARG BEETS_PIP_EXTRAS="discogs,beatport"
# Space-separated extra Python packages to build as wheels alongside beets (user override)
ARG PIP_EXTRAS=""
# -----------------------------------------------------------

ENV PYTHONDONTWRITEBYTECODE=1 \
    PIP_NO_CACHE_DIR=1

# Core build deps for Python wheels on Alpine
RUN apk add --no-cache \
      git \
      build-base \
      musl-dev \
      libffi-dev \
      openssl-dev \
      cargo \
      ${APK_BUILD_DEPS}

# Prepare wheelhouse
WORKDIR /build
RUN mkdir -p /wheels

# Fetch beets source at the requested ref
RUN git clone --depth 1 --branch "${BEETS_REF}" https://github.com/beetbox/beets.git

# Build wheels for beets (with selected extras) and any requested packages into /wheels
# Building wheels up front guarantees availability in the final stage
RUN set -eux; \
    extras="${BEETS_PIP_EXTRAS}"; \
    if [ -n "${extras}" ]; then \
      beets_target="./beets[${extras}]"; \
    else \
      beets_target="./beets"; \
    fi; \
    python3 -m pip wheel --wheel-dir /wheels "${beets_target}"; \
    beets_wheel=''; \
    for wheel in /wheels/beets-*.whl; do \
      beets_wheel="${wheel}"; \
      break; \
    done; \
    if [ -z "${beets_wheel}" ] || [ ! -f "${beets_wheel}" ]; then \
      echo "Beets wheel missing after build step" >&2; \
      exit 1; \
    fi; \
    beets_basename="$(basename "${beets_wheel}")"; \
    beets_version="${beets_basename#beets-}"; \
    beets_version="${beets_version%%.whl}"; \
    beets_version="${beets_version%%-py*}"; \
    default_sources="${DEFAULT_PIP_SOURCES}"; \
    default_packages="${DEFAULT_PIP_PACKAGES}"; \
    classification="ok"; \
    clean_version="$(printf '%s' "${beets_version}" | tr -cd '0-9.')"; \
    save_IFS=${IFS}; IFS=.; set -- ${clean_version}; IFS=${save_IFS}; \
    v_major=${1:-0}; \
    v_minor=${2:-0}; \
    v_patch=${3:-0}; \
    if [ "${v_major}" -gt 2 ]; then \
      classification="disable_high"; \
    elif [ "${v_major}" -lt 2 ]; then \
      classification="disable_low"; \
    else \
      if [ "${v_minor}" -gt 4 ]; then \
        classification="disable_high"; \
      elif [ "${v_minor}" -lt 3 ]; then \
        classification="disable_low"; \
      elif [ "${v_minor}" -eq 4 ]; then \
        classification="disable_high"; \
      fi; \
    fi; \
    if [ "${classification}" != "ok" ]; then \
      if [ "${classification}" = "disable_high" ]; then \
        echo "Disabling beets-filetote (requires beets < 2.4.0)" >&2; \
      else \
        echo "Disabling beets-filetote (requires beets >= 2.3.0)" >&2; \
      fi; \
      filtered=''; \
      for pkg in ${default_sources}; do \
        if [ "${pkg}" = "beets-filetote" ] || [ -z "${pkg}" ]; then \
          continue; \
        fi; \
        filtered="${filtered} ${pkg}"; \
      done; \
      default_sources="${filtered# }"; \
      filtered=''; \
      for pkg in ${default_packages}; do \
        if [ "${pkg}" = "beets-filetote" ] || [ -z "${pkg}" ]; then \
          continue; \
        fi; \
        filtered="${filtered} ${pkg}"; \
      done; \
      default_packages="${filtered# }"; \
    fi; \
    tmp_dir="$(mktemp -d)"; \
    mv "${beets_wheel}" "${tmp_dir}/"; \
    if [ -n "${default_sources}" ]; then \
      python3 -m pip wheel --wheel-dir /wheels ${default_sources}; \
    fi; \
    if [ -n "${PIP_EXTRAS}" ]; then \
      python3 -m pip wheel --wheel-dir /wheels ${PIP_EXTRAS}; \
    fi; \
    printf '%s' "${default_packages}" > /wheels/.default-packages; \
    rm -f /wheels/beets-*.whl; \
    mv "${tmp_dir}/${beets_basename}" /wheels/; \
    rmdir "${tmp_dir}"

# ------------------------------------------------------------------------

FROM python:${PYTHON_VERSION}${PYTHON_BASE_SUFFIX} AS runtime

# -------- Runtime args you can override at build --------
# Extra runtime APKs (shared libs/tools your plugins need; e.g., "ffmpeg sqlite")
ARG APK_RUNTIME_EXTRAS=""
# Default directories (you can still bind-mount whatever you want)
ARG CONFIG_DIR=/config
# --------------------------------------------------------

ENV PYTHONDONTWRITEBYTECODE=1 \
    PIP_NO_CACHE_DIR=1 \
    # Runtime-configurable: set user IDs and umask at container start
    PUID=99 \
    PGID=100 \
    UMASK=0022

# Minimal runtime packages + su-exec for dropping privileges
RUN apk add --no-cache \
      bash \
      chromaprint \
      ffmpeg \
      jq \
      libffi \
      openssl \
      su-exec \
      yq \
      ${APK_RUNTIME_EXTRAS}

# Bring in the built wheels and install without hitting the network
ARG DEFAULT_PIP_PACKAGES="beets-beatport4 beets-filetote beets-importreplace requests requests_oauthlib beautifulsoup4 pyacoustid pylast langdetect flask Pillow"
ARG BEETS_PIP_EXTRAS="discogs,beatport"
ARG PIP_EXTRAS=""
COPY --from=builder /wheels /wheels
RUN set -eux; \
    extras="${BEETS_PIP_EXTRAS}"; \
    if [ -n "${extras}" ]; then \
      beets_target="beets[${extras}]"; \
    else \
      beets_target="beets"; \
    fi; \
    python3 -m pip install --no-index --find-links=/wheels "${beets_target}"; \
    default_packages="${DEFAULT_PIP_PACKAGES}"; \
    if [ -f /wheels/.default-packages ]; then \
      default_packages="$(tr '\n' ' ' < /wheels/.default-packages)"; \
    fi; \
    if [ -n "${default_packages}" ]; then \
      python3 -m pip install --no-index --find-links=/wheels ${default_packages}; \
    fi; \
    if [ -n "${PIP_EXTRAS}" ]; then \
      python3 -m pip install --no-index --find-links=/wheels ${PIP_EXTRAS}; \
    fi; \
    rm -rf /wheels

# Create directories and a non-root user at runtime via entrypoint (dynamic UID/GID)
RUN mkdir -p ${CONFIG_DIR}
WORKDIR ${CONFIG_DIR}

# Copy entrypoint
COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

ENV BEETSDIR=${CONFIG_DIR}
ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
CMD ["sh", "-c", "CONFIG=${BEETSDIR:-/config}/config.yaml; mkdir -p \"$(dirname \"$CONFIG\")\"; if [ ! -f \"$CONFIG\" ]; then printf 'plugins:\\n  - web\\nweb:\\n  host: 0.0.0.0\\n' > \"$CONFIG\"; fi; yq -i '.plugins = (.plugins // [])' \"$CONFIG\"; yq -i '.plugins = (.plugins + [\"web\"] | unique)' \"$CONFIG\"; yq -i '.web.host = (.web.host // \"0.0.0.0\")' \"$CONFIG\"; exec beet web"]
