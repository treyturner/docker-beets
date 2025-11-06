# syntax=docker/dockerfile:1.7
ARG PYTHON_VERSION=3.12 \
    PYTHON_BASE_SUFFIX=alpine

FROM --platform=$BUILDPLATFORM python:${PYTHON_VERSION}${PYTHON_BASE_SUFFIX:+-${PYTHON_BASE_SUFFIX#-}} AS builder

LABEL \
  org.opencontainers.image.title="beets" \
  org.opencontainers.image.description="A customizable Docker image for beets - the music library manager and tagger." \
  org.opencontainers.image.url="https://github.com/beetbox/beets" \
  org.opencontainers.image.source="https://github.com/beetbox/beets" \
  org.opencontainers.image.licenses="MIT" \
  org.opencontainers.image.documentation="https://beets.readthedocs.io/en/latest/" \
  org.opencontainers.image.vendor="Trey Turner"

# -------- Build-time args you can override at build --------
# Git ref (tag/branch/sha) to build from the beets repo
ARG BEETS_REF=v2.5.1
# Space-separated extra APK packages needed ONLY for building (e.g., ffmpeg-dev)
ARG APK_BUILD_DEPS=""
# Space-separated Python package sources bundled by default alongside beets
# (git URLs allowed; leave blank to skip)
ARG DEFAULT_PIP_SOURCES="beets-beatport4 beets-filetote git+https://github.com/edgars-supe/beets-importreplace.git requests requests_oauthlib beautifulsoup4 pyacoustid pylast python3-discogs-client langdetect flask Pillow"
# Space-separated distribution names installed in the runtime stage
ARG DEFAULT_PIP_PACKAGES="beets-beatport4 beets-filetote beets-importreplace requests requests_oauthlib beautifulsoup4 pyacoustid pylast python3-discogs-client langdetect flask Pillow"
# Space-separated user Python packages to bundle (wheels built & installed)
ARG USER_PIP_PACKAGES=""
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

# Build wheels for beets and any requested packages into /wheels
# Building wheels up front guarantees availability in the final stage
RUN set -eux; \
    python3 -m pip wheel --wheel-dir /wheels ./beets; \
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
    beets_version="$(printf '%s' "${beets_basename}" | sed -E 's/^beets-([0-9]+(\.[0-9]+)*)-.*/\1/')"; \
    if [ -z "${beets_version}" ] || [ "${beets_version}" = "${beets_basename}" ]; then \
      echo "Unable to parse beets version from wheel name: ${beets_basename}" >&2; \
      exit 1; \
    fi; \
    default_sources="${DEFAULT_PIP_SOURCES}"; \
    default_packages="${DEFAULT_PIP_PACKAGES}"; \
    case "${beets_version}" in \
      2.3.*) keep_filetote=true ;; \
      *) keep_filetote=false ;; \
    esac; \
    if [ "${keep_filetote}" != "true" ]; then \
      echo "Disabling beets-filetote (requires beets >= 2.3.0 and < 2.4.0)" >&2; \
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
    if [ -n "${USER_PIP_PACKAGES}" ]; then \
      python3 -m pip wheel --wheel-dir /wheels ${USER_PIP_PACKAGES}; \
    fi; \
    printf '%s' "${default_packages}" > /wheels/.default-packages; \
    rm -f /wheels/beets-*.whl; \
    mv "${tmp_dir}/${beets_basename}" /wheels/; \
    rmdir "${tmp_dir}"

# ------------------------------------------------------------------------

FROM python:${PYTHON_VERSION}${PYTHON_BASE_SUFFIX:+-${PYTHON_BASE_SUFFIX#-}} AS runtime

# -------- Runtime args you can override at build --------
# Extra runtime APKs (shared libs/tools your plugins need; e.g., "ffmpeg sqlite")
ARG APK_RUNTIME_EXTRAS=""
# Default directories (you can still bind-mount whatever you want)
ARG CONFIG_DIR=/config
# --------------------------------------------------------

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    # Runtime-configurable: set user IDs and umask at container start
    PUID=99 \
    PGID=100 \
    UMASK=0002

STOPSIGNAL SIGINT

# Minimal runtime packages + su-exec for dropping privileges
RUN apk add --no-cache \
      bash \
      chromaprint \
      ffmpeg \
      imagemagick \
      jq \
      libffi \
      openssl \
      su-exec \
      yq \
      ${APK_RUNTIME_EXTRAS}

# Bring in the built wheels and install without hitting the network
ARG DEFAULT_PIP_PACKAGES="beets-beatport4 beets-filetote beets-importreplace requests requests_oauthlib beautifulsoup4 pyacoustid pylast python3-discogs-client langdetect flask Pillow"
ARG USER_PIP_PACKAGES=""
COPY --from=builder /wheels /wheels
RUN set -eux; \
    python3 -m pip install --no-index --find-links=/wheels beets; \
    default_packages="${DEFAULT_PIP_PACKAGES}"; \
    if [ -f /wheels/.default-packages ]; then \
      default_packages="$(tr '\n' ' ' < /wheels/.default-packages)"; \
    fi; \
    if [ -n "${default_packages}" ]; then \
      python3 -m pip install --no-index --find-links=/wheels ${default_packages}; \
    fi; \
    if [ -n "${USER_PIP_PACKAGES}" ]; then \
      python3 -m pip install --no-index --find-links=/wheels ${USER_PIP_PACKAGES}; \
    fi; \
    rm -rf /wheels

# Create directories and a non-root user at runtime via entrypoint (dynamic UID/GID)
RUN mkdir -p ${CONFIG_DIR}
WORKDIR ${CONFIG_DIR}

# Copy entrypoint and startup scripts
COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
COPY start-web.sh /usr/local/bin/start-web.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh /usr/local/bin/start-web.sh

# Include upstream license for compliance
RUN install -d /usr/share/licenses/beets
COPY --from=builder /build/beets/LICENSE /usr/share/licenses/beets/LICENSE

ENV BEETSDIR=${CONFIG_DIR}
ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
CMD ["/usr/local/bin/start-web.sh"]
