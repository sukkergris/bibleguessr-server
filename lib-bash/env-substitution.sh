#!/usr/bin/env bash
set -u

[[ -n "${_ENV_SUBSTITUTION_LOADED:-}" ]] && return 0
_ENV_SUBSTITUTION_LOADED=1

load_module "logging"
load_module "helpers"

process_template() {
  local template="$1"
  local output="${template%.template}"

  local vars=(
    LIMIT_RATE
    ASSET_EXPIRES
    DOMAIN_KFK
    DOMAIN_CVP
    DOMAIN_BG
    DOMAIN_VW
  )

  local subst
  subst=$(printf " \${%s}" "${vars[@]}")
  subst="${subst:1}"

  envsubst "$subst" < "$template" > "$output"
  echo "Generated: ${output}"
}

process_templates() {
  local folder="$1"
  local env_folder="$2"

  load_env_files "${env_folder}"

  TEMPLATES=$(find "$folder" -type f -name "*.template" 2>/dev/null)

  if [[ -z "$TEMPLATES" ]]; then
    log::warn "No templates found in '$folder'"
    return 0
  fi

  while IFS= read -r template; do
    process_template "${template}"
  done <<< "$TEMPLATES"
}
