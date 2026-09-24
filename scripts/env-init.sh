#!/usr/bin/env bash
set -u

# shellcheck source=/dev/null

source "$(dirname -- "${BASH_SOURCE[0]}")/../lib-bash/header.sh"

ENV_DIR="$(dirname -- "${BASH_SOURCE[0]}")/../env"

mkdir -p "${ENV_DIR}"

SQUIDEX_ENV="${ENV_DIR}/squidex.env"
if [[ ! -f "${SQUIDEX_ENV}" ]]; then
    cat > "${SQUIDEX_ENV}" <<EOF
URLS__BASEURL=
IDENTITY__ALLOWHTTPSCHEME=false
EVENTSTORE__MONGODB__CONFIGURATION=
STORE__MONGODB__CONFIGURATION=
IDENTITY__ADMINEMAIL=
IDENTITY__ADMINPASSWORD=
ASPNETCORE_URLS=http://+:5000
ASSETS__MAXSIZE=209715200
EOF
    log::info "Created ${SQUIDEX_ENV}"
else
    log::info "${SQUIDEX_ENV} already exists, skipping."
fi

BACKUP_ENV="${ENV_DIR}/backup.env"
if [[ ! -f "${BACKUP_ENV}" ]]; then
    cat > "${BACKUP_ENV}" <<EOF
# Squidex backup/sync client settings
SQ_URL=http://squidex:5000
SQ_APP=kort-til-kort
SQ_CLIENT_ID=kort-til-kort:development
SQ_CLIENT_SECRET=

# Optional output location override
# BACKUP__OUTPUT_DIR=/backups
EOF
    log::info "Created ${BACKUP_ENV}"
else
    log::info "${BACKUP_ENV} already exists, skipping."
fi

WEBAPI_ENV="${ENV_DIR}/webapi.env"
if [[ ! -f "${WEBAPI_ENV}" ]]; then
    cat > "${WEBAPI_ENV}" <<EOF
ASPNETCORE_URLS=http://+:8080
ASPNETCORE_ENVIRONMENT=Production

Logging__LogLevel__Default=Information
Logging__LogLevel__Microsoft.AspNetCore=Warning

MailServer__SmtpServer=
MailServer__SmtpPort=587
MailServer__UserName=
MailServer__Password=

NotifyStaffThatNewStudentJustEnrolled__To=
NotifyStaffThatNewStudentJustEnrolled__From=

Turnstile__SecretKey=

# -- Squidex Sitemap Client (OAuth2 + GraphQL) --
SquidexSitemap__GraphQlUrl=http://squidex:5000/api/content/kort-til-kort/graphql
SquidexSitemap__IdentityServerUrl=http://squidex:5000/identity-server/connect/token
SquidexSitemap__ClientId=kort-til-kort:development
SquidexSitemap__ClientSecret=

# Optional host-side runtime overrides used by compose
# WEB_API_LOGFILES_DIR=./web-api-logfiles
EOF
    log::info "Created ${WEBAPI_ENV}"
else
    log::info "${WEBAPI_ENV} already exists, skipping."
fi

YARP_ENV="${ENV_DIR}/yarp.env"
if [[ ! -f "${YARP_ENV}" ]]; then
    cat > "${YARP_ENV}" <<EOF
ASPNETCORE_URLS=http://+:5000

# Optional compose/runtime override
# ASPNETCORE_ENVIRONMENT=Development

SquidexGatewayOptions__ClientId=
SquidexGatewayOptions__ClientSecret=
SquidexGatewayOptions__IdentityServerUrl=
EOF
    log::info "Created ${YARP_ENV}"
else
    log::info "${YARP_ENV} already exists, skipping."
fi

APP_ENV="${ENV_DIR}/app.env"
if [[ ! -f "${APP_ENV}" ]]; then
    printf 'VERSION=\n' > "${APP_ENV}"
    log::info "Created ${APP_ENV}"
else
    log::info "${APP_ENV} already exists, skipping."
fi

NGINX_ENV="${ENV_DIR}/nginx.env"
if [[ ! -f "${NGINX_ENV}" ]]; then
    cat > "${NGINX_ENV}" <<EOF
DOMAIN=

# Optional nginx/runtime overrides
# NGINX_HTTP_PORT=8080
# NGINX_HTTPS_PORT=8443
# NGINX_LOGGING_DRIVER=json-file
# ASSETS__MAXSIZE=209715200
EOF
    log::info "Created ${NGINX_ENV}"
else
    log::info "${NGINX_ENV} already exists, skipping."
fi

LETSENCRYPT_ENV="${ENV_DIR}/letsencrypt.env"
if [[ ! -f "${LETSENCRYPT_ENV}" ]]; then
    cat > "${LETSENCRYPT_ENV}" <<EOF
# Optional Let's Encrypt / certificate overrides
# LETSENCRYPT_CHALLENGES_DIR=./dev/letsencrypt_challenges
# LETSENCRYPT_DIR=./certs
# DEV_CERTS_DIR=/absolute/path/to/your/local/letsencrypt-style/certs
EOF
    log::info "Created ${LETSENCRYPT_ENV}"
else
    log::info "${LETSENCRYPT_ENV} already exists, skipping."
fi

PRERENDER_ENV="${ENV_DIR}/prerender.env"
if [[ ! -f "${PRERENDER_ENV}" ]]; then
    cat > "${PRERENDER_ENV}" <<EOF
PRERENDER_INTERNAL_URL=http://nginx:8888
PRERENDER_PUBLIC_HOST=korttilkort.dk
PRERENDER_CONCURRENCY=3
PRERENDER_TIMEOUT=30000
EOF
    log::info "Created ${PRERENDER_ENV}"
else
    log::info "${PRERENDER_ENV} already exists, skipping."
fi

log::ok "Environment files initialised in ${ENV_DIR}"
