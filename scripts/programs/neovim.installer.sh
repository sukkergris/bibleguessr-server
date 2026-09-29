#!/usr/bin/env bash
# Neovim installer (pinned version) for Linux (x86_64/arm64) and macOS (x86_64/arm64).
# Works standalone, e.g. `COPY` + `RUN` in a Dockerfile: it does not source lib-bash/header.sh,
# because that needs the whole repo (root-marker) to be present.
#
# Environment:
#   NVIM_VERSION      Release tag to install (default v0.12.5). Never "latest"/"stable"/"nightly".
#   NVIM_SHA256       SHA-256 of the tarball. Required knowledge for versions without a built-in value;
#                     if unset, it is read from the GitHub release API ("digest" field).
#   NVIM_INSTALL_DIR  Parent dir for versioned installs (default /opt -> /opt/nvim-<version>).
#   NVIM_BIN_DIR      Where the `nvim` symlink goes (default /usr/local/bin).
#   TARGETARCH        Set by Docker BuildKit (amd64/arm64); overrides `uname -m`.
#   GITHUB_TOKEN      Optional; only used for the API lookup to avoid the anonymous rate limit.
set -euo pipefail

NVIM_VERSION="${NVIM_VERSION:-v0.12.5}"
NVIM_INSTALL_DIR="${NVIM_INSTALL_DIR:-/opt}"
NVIM_BIN_DIR="${NVIM_BIN_DIR:-/usr/local/bin}"

log() { printf '[nvim-install] %s\n' "$*" >&2; }
die() { printf '[nvim-install] ERROR: %s\n' "$*" >&2; exit 1; }

# Accept "0.12.5" as well as "v0.12.5", but only exact release tags: moving tags like
# "stable"/"nightly" would defeat the version lock.
[[ "${NVIM_VERSION}" == v* ]] || NVIM_VERSION="v${NVIM_VERSION}"
[[ "${NVIM_VERSION}" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] \
  || die "NVIM_VERSION must be an exact release tag like v0.12.5 (got '${NVIM_VERSION}')"

NVIM_DEST="${NVIM_INSTALL_DIR}/nvim-${NVIM_VERSION}"
NVIM_LINK="${NVIM_BIN_DIR}/nvim"

OS=""
ASSET=""
TMP_DIR=""
PARTIAL_DIR=""

detect_asset() {
  local kernel arch

  kernel="$(uname -s)"
  # BuildKit's TARGETARCH describes the image being built, which is what we want even when
  # `uname -m` reports something else (e.g. under emulation).
  arch="${TARGETARCH:-$(uname -m)}"

  case "${kernel}" in
    Linux) OS="linux" ;;
    Darwin) OS="macos" ;;
    *) die "unsupported OS '${kernel}' (supported: Linux, Darwin)" ;;
  esac

  case "${arch}" in
    x86_64 | amd64) arch="x86_64" ;;
    aarch64 | arm64) arch="arm64" ;;
    *) die "unsupported architecture '${arch}' on ${kernel} (supported: x86_64/amd64, aarch64/arm64)" ;;
  esac

  ASSET="nvim-${OS}-${arch}.tar.gz"
}

known_sha256() {
  case "${NVIM_VERSION}/${ASSET}" in
    v0.12.5/nvim-linux-x86_64.tar.gz) echo "bce0f56eda1f1b1db6eee8f4133d7a38813ea07933837dd1777411ca384c6875" ;;
    v0.12.5/nvim-linux-arm64.tar.gz) echo "1aa5ca085249580ae0f91eb14f27ec0919773ff2d99a163d03f3d6c21ac29725" ;;
    v0.12.5/nvim-macos-x86_64.tar.gz) echo "81f4518622cb059b450ee2e498c6a1082a222f6bd89589de5bbcf0c6a68aa3fd" ;;
    v0.12.5/nvim-macos-arm64.tar.gz) echo "65fb000099e47ca1b762584c484cc833f40e30851a0ec450d4174e16317c1f9b" ;;
    *) return 1 ;;
  esac
}

# Reads assets[].digest ("sha256:<hex>") for ASSET from the release API.
api_sha256() {
  local api_url="https://api.github.com/repos/neovim/neovim/releases/tags/${NVIM_VERSION}"
  local json digest
  local -a headers=(-H "Accept: application/vnd.github+json")

  if [[ -n "${GITHUB_TOKEN:-}" ]]; then
    headers+=(-H "Authorization: Bearer ${GITHUB_TOKEN}")
  fi

  json="$(curl -fsSL --retry 3 "${headers[@]}" "${api_url}")" \
    || die "could not fetch release metadata from ${api_url}"

  if command -v jq >/dev/null 2>&1; then
    digest="$(jq -r --arg name "${ASSET}" \
      '.assets[] | select(.name == $name) | .digest // empty' <<<"${json}")"
  else
    # No jq: put every key/value on its own line, find the asset's "name", then take the
    # "digest" that follows it. Stop at "browser_download_url" (the last key of an asset),
    # so an asset without a digest can never pick up the next asset's digest.
    digest="$(tr ',' '\n' <<<"${json}" | awk -v name="${ASSET}" '
      $0 ~ "\"name\"[[:space:]]*:[[:space:]]*\"" name "\"" { found = 1; next }
      found && /"digest"[[:space:]]*:/ {
        if (match($0, /sha256:[0-9a-fA-F]+/)) print substr($0, RSTART, RLENGTH)
        exit
      }
      found && /"browser_download_url"/ { exit }
    ')"
  fi

  digest="${digest#sha256:}"
  [[ -n "${digest}" ]] \
    || die "no sha256 digest for ${ASSET} in release ${NVIM_VERSION}; set NVIM_SHA256 explicitly"
  echo "${digest}"
}

resolve_sha256() {
  if [[ -n "${NVIM_SHA256:-}" ]]; then
    echo "${NVIM_SHA256}"
  elif known_sha256; then
    :
  else
    log "no built-in checksum for ${NVIM_VERSION}/${ASSET}; reading it from the GitHub API"
    api_sha256
  fi
}

file_sha256() {
  local hash
  if [[ "${OS}" == "macos" ]]; then
    hash="$(shasum -a 256 "$1")"
  else
    hash="$(sha256sum "$1")"
  fi
  echo "${hash%% *}"
}

# Succeeds if `<bin> --version` reports exactly NVIM_VERSION.
has_version() {
  local bin="$1" out
  [[ -x "${bin}" ]] || return 1
  # Capture the whole output instead of piping to `head`: with pipefail, an early-closing
  # pipe could make a successful check look like a failure.
  out="$("${bin}" --version 2>/dev/null)" || return 1
  [[ "${out%%$'\n'*}" == "NVIM ${NVIM_VERSION}" ]]
}

# Nearest existing ancestor of a path (the dir that must be writable to create it).
existing_ancestor() {
  local dir="$1"
  while [[ ! -e "${dir}" ]]; do
    dir="$(dirname -- "${dir}")"
  done
  echo "${dir}"
}

# Runs a command with sudo only when needed: not as root, and not when the given dir (or its
# nearest existing ancestor) is writable. Pass the dir whose contents the command changes.
as_owner_of() {
  local target="$1"
  shift
  if [[ "${EUID}" -eq 0 || -w "$(existing_ancestor "${target}")" ]]; then
    "$@"
  elif command -v sudo >/dev/null 2>&1; then
    sudo "$@"
  else
    die "'${target}' is not writable and sudo is not available"
  fi
}

cleanup() {
  if [[ -n "${TMP_DIR}" ]]; then
    rm -rf -- "${TMP_DIR}"
  fi
  if [[ -n "${PARTIAL_DIR}" && -e "${PARTIAL_DIR}" ]]; then
    as_owner_of "${NVIM_INSTALL_DIR}" rm -rf -- "${PARTIAL_DIR}" || true
  fi
}

main() {
  detect_asset

  # Idempotency: check the binary this script manages, not whatever `nvim` is first on PATH
  # (e.g. Debian's /usr/bin/nvim or Homebrew's).
  if has_version "${NVIM_LINK}"; then
    log "Neovim ${NVIM_VERSION} is already installed at ${NVIM_LINK}; nothing to do."
    exit 0
  fi

  if has_version "${NVIM_DEST}/bin/nvim"; then
    log "${NVIM_DEST} already exists; only switching the symlink."
    link_and_verify
    exit 0
  fi

  local url="https://github.com/neovim/neovim/releases/download/${NVIM_VERSION}/${ASSET}"
  local expected actual

  expected="$(resolve_sha256)"
  expected="$(tr '[:upper:]' '[:lower:]' <<<"${expected}")"
  [[ "${expected}" =~ ^[0-9a-f]{64}$ ]] || die "invalid SHA-256 value '${expected}'"

  trap cleanup EXIT
  TMP_DIR="$(mktemp -d)"

  log "Downloading ${url}"
  # -f: fail on HTTP errors instead of saving an HTML error page.
  curl -fsSL --retry 3 -o "${TMP_DIR}/${ASSET}" "${url}"

  actual="$(file_sha256 "${TMP_DIR}/${ASSET}")"
  [[ "${actual}" == "${expected}" ]] \
    || die "checksum mismatch for ${ASSET}: expected ${expected}, got ${actual}"
  log "Checksum OK (${actual})"

  # Extract next to the final dir and rename at the end, so an interrupted run never leaves
  # a half-populated /opt/nvim-<version>. --no-same-owner: as root, tar would otherwise keep
  # the CI runner's uid from the archive.
  PARTIAL_DIR="${NVIM_DEST}.partial"
  as_owner_of "${NVIM_INSTALL_DIR}" rm -rf -- "${PARTIAL_DIR}"
  as_owner_of "${NVIM_INSTALL_DIR}" mkdir -p "${PARTIAL_DIR}"
  as_owner_of "${NVIM_INSTALL_DIR}" tar --no-same-owner --strip-components=1 \
    -xzf "${TMP_DIR}/${ASSET}" -C "${PARTIAL_DIR}"

  if [[ "${OS}" == "macos" ]]; then
    # Gatekeeper blocks quarantined binaries. curl normally doesn't set the attribute, and
    # xattr fails when it is absent, so a failure here is expected and ignored.
    as_owner_of "${PARTIAL_DIR}" xattr -dr com.apple.quarantine "${PARTIAL_DIR}" 2>/dev/null || true
  fi

  has_version "${PARTIAL_DIR}/bin/nvim" \
    || die "extracted binary does not report version ${NVIM_VERSION}"

  as_owner_of "${NVIM_INSTALL_DIR}" rm -rf -- "${NVIM_DEST}"
  as_owner_of "${NVIM_INSTALL_DIR}" mv -- "${PARTIAL_DIR}" "${NVIM_DEST}"
  PARTIAL_DIR=""

  link_and_verify
}

link_and_verify() {
  # Symlink the versioned binary: switching version = re-run with another NVIM_VERSION;
  # nvim resolves the symlink to find its runtime files in ../share.
  as_owner_of "${NVIM_BIN_DIR}" mkdir -p "${NVIM_BIN_DIR}"
  as_owner_of "${NVIM_BIN_DIR}" ln -sfn "${NVIM_DEST}/bin/nvim" "${NVIM_LINK}"

  has_version "${NVIM_LINK}" \
    || die "verification failed: ${NVIM_LINK} --version does not report ${NVIM_VERSION}"

  log "Installed Neovim ${NVIM_VERSION}: ${NVIM_LINK} -> ${NVIM_DEST}/bin/nvim"

  local on_path
  on_path="$(command -v nvim 2>/dev/null || true)"
  if [[ "${on_path}" != "${NVIM_LINK}" ]]; then
    log "Note: 'nvim' on PATH resolves to '${on_path:-<nothing>}', not ${NVIM_LINK}."
  fi
  log "Installed versions (remove unused ones with rm -rf):"
  ls -d "${NVIM_INSTALL_DIR}"/nvim-v* >&2
}

main "$@"
