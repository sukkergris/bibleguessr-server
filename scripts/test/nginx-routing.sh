#!/usr/bin/env bash
set -u
# Routing test for nginx/: runs the generated config in a throwaway nginx
# container against a mock API that echoes what nginx forwards. It never
# touches the running stack. Run `task docker:nginx:generate-conf` first.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../lib-bash" && pwd)/header.sh"

# Checks are expected to fail sometimes; report them instead of aborting.
set +eE
trap - ERR

TEST_DIR="${SCRIPTS_DIR}/test"
NGINX_IMAGE="${NGINX_IMAGE:-docker.io/isuperman/bibleguessr-nginx:${APP_VERSION:-0.0.1}}"
DOMAIN="$(grep -E '^DOMAIN_BG=' "${PROJECT_ROOT}/env/nginx.env" | tail -n1 | cut -d'=' -f2-)"
NET=bg-routing-test
SUT=bg-routing-sut
API=bg-routing-api
CLI=bg-routing-cli
pass=0
fail=0

cleanup() {
    docker rm -f "$SUT" "$API" "$CLI" >/dev/null 2>&1
    docker network rm "$NET" >/dev/null 2>&1
}

# docker cp instead of bind mounts, so this also works with Docker-outside-of-Docker.
start_containers() {
    docker network create "$NET" >/dev/null
    docker create --name "$API" --network "$NET" --network-alias bibleguessr-api nginx:1.31.6-alpine >/dev/null
    docker cp "${TEST_DIR}/mock-api.conf" "$API:/etc/nginx/conf.d/default.conf"
    docker start "$API" >/dev/null

    docker create --name "$SUT" --network "$NET" --entrypoint nginx "$NGINX_IMAGE" \
        -p /cfg/ -c /cfg/nginx.conf -g 'daemon off;' >/dev/null
    docker cp "${PROJECT_ROOT}/nginx/." "$SUT:/cfg/"
    docker cp -L "${PROJECT_ROOT}/development/letsencrypt/." "$SUT:/etc/letsencrypt/"
    docker start "$SUT" >/dev/null

    docker run -d --name "$CLI" --network "$NET" --entrypoint sleep nginx:1.31.6-alpine 300 >/dev/null
    sleep 1
}

req() { docker exec "$CLI" curl -sk --http1.1 --connect-to "${DOMAIN}:443:${SUT}:443" "$@"; }
code() { req -o /dev/null -w '%{http_code}' "$@"; }
headers() { req -D - -o /dev/null "$@" | tr '[:upper:]' '[:lower:]'; }

# check <name> <expected substring> <actual>
check() {
    local name="$1" expected="$2" actual="$3"
    if [[ "$actual" == *"$expected"* ]]; then
        pass=$((pass + 1))
        log::ok "$name"
    else
        fail=$((fail + 1))
        log::error "$name: expected '$expected', got '$actual'"
    fi
}

absent_in_logs() {
    local logs
    logs="$(docker logs "$SUT" 2>&1)"
    [[ "$logs" == *"$1"* ]] && echo present || echo absent
}

main() {
    local base="https://${DOMAIN}" codes asset i client_ip
    cleanup
    trap cleanup EXIT
    start_containers

    if ! docker exec "$SUT" nginx -p /cfg/ -c /cfg/nginx.conf -t >/dev/null 2>&1; then
        docker logs "$SUT"
        log::error "nginx -t failed"
        exit 1
    fi

    # Static frontend
    check "SPA root"                         "<!doctype" "$(req "$base/")"
    check "SPA client route"                 "<!doctype" "$(req "$base/some/route")"
    asset="$(docker exec "$SUT" ls /usr/share/nginx/html/assets | head -n1)"
    check "asset served"                     "200" "$(code "$base/assets/$asset")"
    check "asset cached as immutable"        "public, immutable" "$(headers "$base/assets/$asset")"
    check "missing asset is 404"             "404" "$(code "$base/assets/missing-chunk.js")"
    check "HTTP redirects to HTTPS"          "301" \
        "$(docker exec "$CLI" curl -s -o /dev/null -w '%{http_code}' -H "Host: ${DOMAIN}" "http://${SUT}/")"

    # API routing: prefixes are passed through unchanged
    check "/api/ keeps prefix"               "uri=/api/translations " "$(req "$base/api/translations")"
    check "/api/ passes query string"        "uri=/api/verses/lookup?ref=x " "$(req "$base/api/verses/lookup?ref=x")"
    check "/api/ sends no-cache"             "cache-control: no-cache" "$(headers "$base/api/books")"
    check "/api/*.php goes to API, not tarpit" "uri=/api/x.php" "$(req "$base/api/x.php")"
    check "/api/healthz"                     "uri=/api/healthz " "$(req "$base/api/healthz")"
    check "/sitemap.xml goes to API"         "uri=/sitemap.xml " "$(req "$base/sitemap.xml")"
    check "/hubs/ keeps prefix"              "uri=/hubs/game " \
        "$(req -H 'Upgrade: websocket' -H 'Connection: Upgrade' "$base/hubs/game")"
    check "/hubs/ forwards Upgrade"          "upgrade=websocket connection=upgrade" \
        "$(req -H 'Upgrade: websocket' -H 'Connection: Upgrade' "$base/hubs/game")"

    # Forwarding headers
    client_ip="$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$CLI")"
    check "X-Forwarded-For cannot be spoofed" "xff=${client_ip} " \
        "$(req -H 'X-Forwarded-For: 6.6.6.6' "$base/api/books")"
    check "X-Forwarded-Proto is https"       "proto=https" "$(req "$base/api/books")"

    # Rate limits
    codes=""
    for i in $(seq 1 8); do codes+="$(code -X POST -d 'SECRETBODY' "$base/api/reports") "; done
    check "report limit: 6 allowed, then 429" "200 200 200 200 200 200 429 429 " "$codes"
    codes=""
    for i in $(seq 1 8); do codes+="$(code -X POST "$base/hubs/game") "; done
    check "hub is not rate limited"          "200 200 200 200 200 200 200 200 " "$codes"
    codes=""
    for i in $(seq 1 25); do codes+="$(code "$base/api/rooms") "; done
    check "api limit eventually returns 429" "429" "$codes"

    # Logs
    check "request body never logged"        "absent" "$(absent_in_logs SECRETBODY)"
    check "healthz not logged"               "absent" "$(absent_in_logs /api/healthz)"
    check "no redirection cycle"             "absent" "$(absent_in_logs 'redirection cycle')"

    if [[ $fail -eq 0 ]]; then
        log::ok "$pass/$((pass + fail)) checks passed"
    else
        log::error "$pass/$((pass + fail)) checks passed"
        exit 1
    fi
}

main "$@"
