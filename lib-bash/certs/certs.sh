#!/usr/bin/env bash

# Bash version of pragma once
[[ -n "${_CERTS_LOADED:-}" ]] && return 0
_CERTS_LOADED=1

_CERTS_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# ------------------------------------------------------------------
# generate_reg_cnf DOMAIN
#
# Produces an OpenSSL config file from the template, substituting DOMAIN.
# LESSON: Functions return values via stdout. The caller captures the result
# with command substitution: cnf="$(generate_reg_cnf example.com)"
# ------------------------------------------------------------------
generate_reg_cnf() {
  local domain="$1"
  local template="$_CERTS_DIR/../openssl/reg.cnf.template"
  local output

  # LESSON: mktemp creates a real, empty file with a guaranteed-unique name
  # and prints its path. --suffix keeps the .cnf extension so openssl
  # recognizes it. The file is ours to fill and ours to delete.
  output="$(mktemp --suffix=.cnf)"

  sed -e "s/{DOMAIN}/${domain}/g" "$template" > "$output"
  printf "%s\n" "$output"
}

# ------------------------------------------------------------------
# create_dummy_cert [OUT_DIR]
#
# Creates a minimal self-signed cert — no SAN, no passphrase, 10-year validity.
# Used as a placeholder so nginx can start before a real cert exists.
# LESSON: "${1:-$PROJECT_ROOT/nginx/ssl}" is a default-value substitution.
# If $1 is unset or empty, use the fallback on the right of :-.
# ------------------------------------------------------------------
create_dummy_cert() {
  local out_dir="${1:-$PROJECT_ROOT/nginx/ssl}"

  mkdir -p "$out_dir"
  openssl req -x509 -nodes \
    -newkey rsa:2048 \
    -days 3650 \
    -out "$out_dir/dummy.crt" \
    -keyout "$out_dir/dummy.key" \
    -subj "/CN=_"
}

# ------------------------------------------------------------------
# create_selfsigned_cert CERT_NAME [DAYS] [CERT_DIR]
#
# Generates a real self-signed cert using the reg.cnf template (with SANs).
# LESSON: local variables keep the function's state private. Without local,
# cert_name/days/cert_dir would leak into the caller's environment.
# LESSON: cnf_file="$(generate_reg_cnf ...)" — one function calls another
# and captures its stdout. This is how you compose bash functions.
# ------------------------------------------------------------------
create_selfsigned_cert() {
  local cert_name="$1"
  local days="${2:-825}"
  local cert_dir="${3:-$PROJECT_ROOT/certs/live/$cert_name}"
  local cnf_file

  mkdir -p "$cert_dir"

  cnf_file="$(generate_reg_cnf "$cert_name")"

  # LESSON: trap ... EXIT runs when this shell exits for any reason —
  # normal return, an error, or a signal. Registering it right after
  # mktemp means the temp file is always deleted, even if openssl fails.
  # 'rm -f' is silent if the file is already gone.
  trap 'rm -f "$cnf_file"' RETURN

  openssl genrsa -out "$cert_dir/$cert_name.key" 2048

  openssl req -x509 -new \
    -key "$cert_dir/$cert_name.key" \
    -sha256 -days "$days" \
    -out "$cert_dir/$cert_name.crt" \
    -config "$cnf_file" \
    -extensions v3_req

  chmod 644 "$cert_dir/$cert_name.crt" "$cert_dir/$cert_name.key"
}

# ------------------------------------------------------------------
# trust_dev_cert CERT_FILE DOMAIN
#
# Routes certificate trust to the platform-specific implementation.
# ------------------------------------------------------------------
trust_dev_cert() {
  local cert_file="$1"
  local domain="$2"

  # Trust-store installation is host-level and should not run from containers.
  if [[ -f "/.dockerenv" ]] || [[ -f "/run/.containerenv" ]]; then
    printf 'Refusing to trust cert inside container runtime. Run this step on host instead.\n' >&2
    printf 'Detected container while processing domain: %s\n' "$domain" >&2
    return 1
  fi

  if is_macos; then
    bash "$_CERTS_DIR/trust-dev-cert.macos.sh" "$cert_file" "$domain"
    return $?
  fi

  if [[ "${IS_WSL:-false}" == "true" ]]; then
    bash "$_CERTS_DIR/trust-dev-cert.windows.sh" "$cert_file" "$domain"
    return $?
  fi

  if is_linux; then
    bash "$_CERTS_DIR/trust-dev-cert.linux.sh" "$cert_file" "$domain"
    return $?
  fi

  if is_windows; then
    bash "$_CERTS_DIR/trust-dev-cert.windows.sh" "$cert_file" "$domain"
    return $?
  fi

  printf 'Unsupported OS: %s\n' "${OS:-unknown}" >&2
  return 1
}
# Crate selfsigned certs letsencrypt style
create_selfsigned_letsencrypt_files() {
  local domain="${1:?domain required}"
  local req_cnf="${2:-$PROJECT_ROOT/development/letsencrypt/live/$domain/req.cnf}"
  local days="${3:-825}"
  local live_dir="${PROJECT_ROOT}/development/letsencrypt/live/${domain}"

  local key_file="${live_dir}/privkey.pem"
  local cert_file="${live_dir}/cert.pem"
  local fullchain_file="${live_dir}/fullchain.pem"

  if [[ ! -f "${req_cnf}" ]]; then
    printf 'Missing req.cnf: %s\n' "${req_cnf}" >&2
    return 1
  fi

  mkdir -p "${live_dir}"

  openssl genrsa -out "${key_file}" 2048 || return 1

  openssl req -x509 -new \
    -key "${key_file}" \
    -sha256 -days "${days}" \
    -out "${cert_file}" \
    -config "${req_cnf}" \
    -extensions v3_req || return 1

  # For self-signed dev certs, fullchain is just the leaf cert.
  cp "${cert_file}" "${fullchain_file}" || return 1

  chmod 600 "${key_file}"
  chmod 644 "${cert_file}" "${fullchain_file}"

  printf '%s\n' "${cert_file}"
}