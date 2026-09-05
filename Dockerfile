# syntax=docker/dockerfile:1.7
ARG PYTHON_VERSION=3.14 \
    PYTHON_BASE_SUFFIX=alpine

FROM --platform=$BUILDPLATFORM python:${PYTHON_VERSION}${PYTHON_BASE_SUFFIX:+-${PYTHON_BASE_SUFFIX#-}} AS dependency-builder

LABEL \
  org.opencontainers.image.title="beets" \
  org.opencontainers.image.description="A customizable Docker image for beets - the music library manager and tagger." \
  org.opencontainers.image.url="https://github.com/treyturner/docker-beets" \
  org.opencontainers.image.source="https://github.com/treyturner/docker-beets" \
  org.opencontainers.image.licenses="MIT" \
  org.opencontainers.image.documentation="https://beets.readthedocs.io/en/latest/" \
  org.opencontainers.image.vendor="Trey Turner"

# -------- Build-time args you can override at build --------
# Git ref (tag/branch/sha) to build from the beets repo
ARG BEETS_REF=v2.13.1
# Space-separated extra APK packages needed ONLY for building (e.g., ffmpeg-dev)
ARG APK_BUILD_DEPS=""
# Space-separated Python package sources bundled by default alongside beets
# (git URLs allowed; leave blank to skip)
ARG DEFAULT_PIP_SOURCES="beets-beatport4 git+https://github.com/treyturner/beets-filetote.git git+https://github.com/edgars-supe/beets-importreplace.git beets-tidalv1 beets-nohirescd titlecase requests requests-oauthlib beautifulsoup4 pyacoustid pylast python3-discogs-client langdetect flask Pillow"
# Space-separated distribution names installed in the runtime stage
ARG DEFAULT_PIP_PACKAGES="beets-beatport4 beets-filetote beets-importreplace beets-tidalv1 beets-nohirescd titlecase requests requests-oauthlib beautifulsoup4 pyacoustid pylast python3-discogs-client langdetect flask Pillow"
# Space-separated override mappings ("pkg=spec") replacing sources in DEFAULT_PIP_SOURCES
ARG PIP_SOURCE_OVERRIDES=""
# Space-separated user Python packages to bundle (wheels built & installed)
ARG USER_PIP_PACKAGES=""
# -----------------------------------------------------------

ENV PYTHONDONTWRITEBYTECODE=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

# Core build deps for Python wheels on Alpine
RUN --mount=type=cache,id=builder-apk,target=/var/cache/apk,sharing=locked \
    apk add --no-cache \
      build-base \
      cargo \
      cmake \
      git \
      libffi-dev \
      musl-dev \
      openssl-dev \
      ${APK_BUILD_DEPS}

# Prepare wheelhouse
WORKDIR /build
RUN mkdir -p /wheels

# Fetch beets source at the requested ref
RUN git clone --depth 1 --branch "${BEETS_REF}" https://github.com/beetbox/beets.git

# Build an unpatched beets wheel and all third-party wheels before copying the
# patches into the image. The unpatched wheel supplies beets metadata to pip's
# dependency resolver and is replaced by the patched wheel in the final image.
RUN --mount=type=cache,id=builder-pip,target=/root/.cache/pip,sharing=locked \
    set -eux; \
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
      2.3.*|2.4.*|2.5.*|2.6.*|2.7.*|2.8.*|2.9.*|2.10.*|2.11.*|2.12.*|2.13.*) keep_filetote=true ;; \
      *) keep_filetote=false ;; \
    esac; \
    if [ "${keep_filetote}" != "true" ]; then \
      echo "Disabling beets-filetote (requires beets >= 2.3.0 and < 2.14.0)" >&2; \
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
    overrides="${PIP_SOURCE_OVERRIDES}"; \
    if [ -n "${overrides}" ]; then \
      for override in ${overrides}; do \
        pkg="${override%%=*}"; \
        src="${override#*=}"; \
        if [ -z "${pkg}" ] || [ -z "${src}" ] || [ "${pkg}" = "${src}" ]; then \
          echo "Invalid pip override '${override}'. Expected key=value." >&2; \
          exit 1; \
        fi; \
        filtered=''; \
        for entry in ${default_sources}; do \
          if [ "${entry}" = "${pkg}" ]; then \
            continue; \
          fi; \
          filtered="${filtered} ${entry}"; \
        done; \
        default_sources="${filtered# }"; \
        if [ -n "${default_sources}" ]; then \
          default_sources="${default_sources} ${src}"; \
        else \
          default_sources="${src}"; \
        fi; \
      done; \
    fi; \
    tmp_dir="$(mktemp -d)"; \
    mv "${beets_wheel}" "${tmp_dir}/"; \
    if [ -n "${default_sources}" ]; then \
      python3 -m pip wheel --wheel-dir /wheels "${tmp_dir}/${beets_basename}" ${default_sources}; \
    fi; \
    if [ -n "${USER_PIP_PACKAGES}" ]; then \
      python3 -m pip wheel --wheel-dir /wheels "${tmp_dir}/${beets_basename}" ${USER_PIP_PACKAGES}; \
    fi; \
    printf '%s' "${default_packages}" > /wheels/.default-packages; \
    mv "${tmp_dir}/${beets_basename}" /wheels/; \
    rmdir "${tmp_dir}"

FROM dependency-builder AS builder

# Apply patches whose configured version range includes this beets release.
# patches/series columns are: patch, inclusive minimum, optional exclusive maximum.
COPY patches/ /patches/
RUN <<'EOF'
set -eux

if [ ! -f /patches/series ]; then
  echo "Missing patch manifest: /patches/series" >&2
  exit 1
fi

beets_version="$({
  awk -F'"' '/^version[[:space:]]*=/ { print $2; exit }' beets/pyproject.toml
} 2>/dev/null || true)"
if [ -z "${beets_version}" ]; then
  beets_version="$({
    awk -F'"' '/^__version__[[:space:]]*=/ { print $2; exit }' beets/beets/__init__.py
  } 2>/dev/null || true)"
fi
if [ -z "${beets_version}" ]; then
  echo "Unable to determine the beets version for ${BEETS_REF}" >&2
  exit 1
fi

listed_patches=' '
while read -r patch_file min_version max_version extra; do
  case "${patch_file}" in
    ''|'#'*) continue ;;
  esac

  if [ -n "${extra:-}" ]; then
    echo "Invalid patch manifest entry for ${patch_file}: expected 2 or 3 columns" >&2
    exit 1
  fi
  if [ -z "${min_version:-}" ]; then
    echo "Missing minimum version for ${patch_file}" >&2
    exit 1
  fi
  case "${patch_file}" in
    */*)
      echo "Invalid patch filename '${patch_file}'; expected an issue number followed by .diff" >&2
      exit 1
      ;;
  esac
  case "${patch_file}" in
    *.diff) ;;
    *)
      echo "Invalid patch filename '${patch_file}'; expected an issue number followed by .diff" >&2
      exit 1
      ;;
  esac
  issue_number="${patch_file%.diff}"
  case "${issue_number}" in
    ''|*[!0-9]*)
      echo "Invalid patch filename '${patch_file}'; expected an issue number followed by .diff" >&2
      exit 1
      ;;
  esac
  if [ ! -f "/patches/${patch_file}" ]; then
    echo "Patch listed in manifest does not exist: ${patch_file}" >&2
    exit 1
  fi
  case "${listed_patches}" in
    *" ${patch_file} "*)
      echo "Patch is listed more than once: ${patch_file}" >&2
      exit 1
      ;;
  esac
  listed_patches="${listed_patches}${patch_file} "

  applies="$(python3 -c '
import sys

try:
    from packaging.version import InvalidVersion, Version
except ImportError:
    from pip._vendor.packaging.version import InvalidVersion, Version

def parse(value):
    try:
        return Version(value)
    except InvalidVersion as error:
        raise SystemExit(f"Invalid PEP 440 version: {value}") from error

current = parse(sys.argv[1])
minimum = parse(sys.argv[2])
maximum = parse(sys.argv[3]) if sys.argv[3] else None
if maximum is not None and maximum <= minimum:
    raise SystemExit("Maximum patch version must be greater than its minimum")
print("yes" if current >= minimum and (maximum is None or current < maximum) else "no")
' "${beets_version}" "${min_version}" "${max_version:-}")"

  if [ "${applies}" != yes ]; then
    echo "Skipping issue #${issue_number} patch for beets ${beets_version} (range: >=${min_version}${max_version:+, <${max_version}})"
    continue
  fi

  changed_paths="$(sed -n \
    -e 's|^--- a/||p' \
    -e 's|^+++ b/||p' \
    "/patches/${patch_file}")"
  for changed_path in ${changed_paths}; do
    case "/${changed_path}" in
      */pyproject.toml|*/setup.py|*/setup.cfg|*/uv.lock|*/poetry.lock|*/pdm.lock|*/hatch.toml|*/Pipfile|*/Pipfile.lock|*/requirements*.txt|*/constraints*.txt|*/requirements/*)
        echo "Patch ${patch_file} changes dependency metadata (${changed_path}); patches are applied after dependency wheels are built" >&2
        exit 1
        ;;
    esac
  done

  if git -C beets apply --reverse --check "/patches/${patch_file}" 2>/dev/null; then
    echo "Skipping issue #${issue_number} patch: fix is already present in ${BEETS_REF}"
    continue
  fi

  echo "Applying issue #${issue_number} patch for beets ${beets_version}"
  git -C beets apply --check "/patches/${patch_file}"
  git -C beets apply "/patches/${patch_file}"
done < /patches/series

for patch_path in /patches/*.diff; do
  if [ ! -e "${patch_path}" ]; then
    continue
  fi
  patch_file="${patch_path##*/}"
  case "${listed_patches}" in
    *" ${patch_file} "*) ;;
    *)
      echo "Patch is missing from /patches/series: ${patch_file}" >&2
      exit 1
      ;;
  esac
done
EOF

# Build only the final patched beets wheel. Third-party dependency resolution
# was completed in the patch-independent dependency-builder stage.
RUN --mount=type=cache,id=builder-pip,target=/root/.cache/pip,sharing=locked \
    set -eux; \
    mkdir -p /beets-wheel; \
    python3 -m pip wheel --no-deps --wheel-dir /beets-wheel ./beets; \
    set -- /beets-wheel/beets-*.whl; \
    if [ "$#" -ne 1 ] || [ ! -f "$1" ]; then \
      echo "Expected exactly one patched beets wheel" >&2; \
      exit 1; \
    fi

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
RUN --mount=type=cache,id=runtime-apk,target=/var/cache/apk,sharing=locked \
    apk add \
      bash \
      chromaprint \
      curl \
      ffmpeg \
      imagemagick \
      jq \
      libffi \
      openssl \
      su-exec \
      yq \
      ${APK_RUNTIME_EXTRAS}

# Install the patch-independent wheelhouse, including an unpatched beets wheel
# used to satisfy plugin dependencies. The next layer replaces beets itself.
ARG USER_PIP_PACKAGES=""
COPY --from=dependency-builder /wheels /wheels
RUN set -eux; \
    python3 -m pip install --no-index --find-links=/wheels beets; \
    if [ ! -f /wheels/.default-packages ]; then \
      echo "Missing /wheels/.default-packages from builder stage" >&2; \
      exit 1; \
    fi; \
    default_packages="$(tr '\n' ' ' < /wheels/.default-packages)"; \
    if [ -n "${default_packages}" ]; then \
      python3 -m pip install --no-index --find-links=/wheels ${default_packages}; \
    fi; \
    if [ -n "${USER_PIP_PACKAGES}" ]; then \
      python3 -m pip install --no-index --find-links=/wheels ${USER_PIP_PACKAGES}; \
    fi; \
    rm -rf /wheels; \
    mkdir -p "${CONFIG_DIR}"

# Install the patched beets wheel separately so patch-only changes do not
# invalidate third-party package installation.
COPY --from=builder /beets-wheel /beets-wheel
RUN set -eux; \
    set -- /beets-wheel/beets-*.whl; \
    if [ "$#" -ne 1 ] || [ ! -f "$1" ]; then \
      echo "Expected exactly one patched beets wheel" >&2; \
      exit 1; \
    fi; \
    python3 -m pip install --no-index --no-deps --force-reinstall "$1"; \
    rm -rf /beets-wheel

# Set working directory to the config mount (entrypoint handles UID/GID setup)
WORKDIR ${CONFIG_DIR}

# Copy entrypoint and startup scripts
COPY --chmod=755 docker-entrypoint.sh start-web.sh /usr/local/bin/

# Include upstream license for compliance
COPY --from=builder /build/beets/LICENSE /usr/share/licenses/beets/LICENSE

ENV BEETSDIR=${CONFIG_DIR}
ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
CMD ["/usr/local/bin/start-web.sh"]
