#!/usr/bin/env bash
# Analyse bottlenecks i Docker/Compose setup
# Gennemgår pull policies, build operationer, network overhead, volumes og logging

set -u

WORKSPACE_ROOT="${1:-.}"
DIVIDER="═══════════════════════════════════════════════════════════════════"

report() {
    local level="$1"
    local msg="$2"
    case "$level" in
        INFO)   echo "ℹ️  $msg" ;;
        OK)     echo "✓  $msg" ;;
        WARN)   echo "⚠️  $msg" ;;
        BOTTLENECK) echo "🔴 BOTTLENECK: $msg" ;;
    esac
}

echo "$DIVIDER"
echo "DOCKER BOTTLENECK ANALYSE"
echo "$DIVIDER"
echo ""

# 1. Docker image pull policies
echo "📦 PULL POLICIES"
echo "───────────────────────────────────────────────────────────────────"
if find "$WORKSPACE_ROOT" -name "docker-compose*.yml" -type f | head -5 | grep -q .; then
    compose_files=$(find "$WORKSPACE_ROOT" -name "docker-compose*.yml" -type f)
    while IFS= read -r compose_file; do
        echo "  File: $(basename "$compose_file")"
        if grep -q "pull_policy: missing" "$compose_file"; then
            report OK "pull_policy: missing er konfigureret"
        elif grep -q "image:" "$compose_file"; then
            report BOTTLENECK "Services har 'image:' uden pull_policy — vil altid tjekke registry"
        fi
        
        if grep -q "build:" "$compose_file"; then
            report BOTTLENECK "build: service fundet — Docker vil bygge hver gang (eller bruge cache)"
            while IFS= read -r build_ctx; do
                [ -z "$build_ctx" ] && continue
                report WARN "  └─ kontekst: $(echo "$build_ctx" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
            done < <(grep -A 1 "build:" "$compose_file" | grep "context:" | head -3)
        fi
    done <<< "$compose_files"
else
    report WARN "Ingen docker-compose filer fundet"
fi
echo ""

# 2. Dockerfile analyse
echo "🐳 DOCKERFILE ANALYSE"
echo "───────────────────────────────────────────────────────────────────"
dockerfile_count=$(find "$WORKSPACE_ROOT" -name "Dockerfile*" -type f | wc -l)
if [ "$dockerfile_count" -gt 0 ]; then
    report OK "Fundet $dockerfile_count Dockerfile(s)"
    find "$WORKSPACE_ROOT" -name "Dockerfile*" -type f | head -5 | while IFS= read -r df; do
        base_image=$(head -5 "$df" | grep "^FROM" | head -1 | awk '{print $2}')
        if [ -n "$base_image" ]; then
            size_hint="(varierer)"
            if echo "$base_image" | grep -q "alpine"; then
                size_hint="(lille ~6-10 MB)"
                report OK "  └─ $base_image $size_hint"
            elif echo "$base_image" | grep -q "slim"; then
                size_hint="(medium ~20-30 MB)"
                report OK "  └─ $base_image $size_hint"
            else
                size_hint="(stor ~100+ MB)"
                report BOTTLENECK "  └─ $base_image $size_hint — overvej alpine/slim"
            fi
        fi
    done
else
    report WARN "Ingen Dockerfiles fundet"
fi
echo ""

# 3. Volume mounts analyse
echo "💾 VOLUME MOUNTS (overhead check)"
echo "───────────────────────────────────────────────────────────────────"
compose_files=$(find "$WORKSPACE_ROOT" -name "docker-compose*.yml" -type f 2>/dev/null)
if [ -n "$compose_files" ]; then
    volume_count=$(grep -h "^      - " "$compose_files" | grep -v "^#" | wc -l)
    report OK "Fundet $volume_count volume/bind mounts"
    
    bind_mount_count=$(grep -h "^\s*- \.\." "$compose_files" | wc -l)
    if [ "$bind_mount_count" -gt 0 ]; then
        report WARN "  └─ $bind_mount_count bind mounts (../) — synkronisering kan være langsom på slow networks"
    fi
    
    ro_mount_count=$(grep -h ":ro$" "$compose_files" | wc -l)
    if [ "$ro_mount_count" -gt 0 ]; then
        report OK "  └─ $ro_mount_count read-only mounts (mindre overhead)"
    fi
else
    report WARN "Ingen docker-compose filer analyseret"
fi
echo ""

# 4. Network analysis
echo "🌐 NETWORK CONFIGURATION"
echo "───────────────────────────────────────────────────────────────────"
if grep -q "networks:" "$WORKSPACE_ROOT"/docker-compose*.yml 2>/dev/null; then
    report OK "Custom networks defineret — adskiller trafik"
else
    report WARN "Ingen custom networks — bruger default bridge"
fi
echo ""

# 5. Logging overhead
echo "📊 LOGGING CONFIGURATION"
echo "───────────────────────────────────────────────────────────────────"
if grep -q "logging:" "$WORKSPACE_ROOT"/**/docker-compose*.yml 2>/dev/null; then
    report OK "Logging er konfigureret"
    max_size=$(grep -h "max-size:" "$WORKSPACE_ROOT"/**/docker-compose*.yml 2>/dev/null | head -1)
    if [ -n "$max_size" ]; then
        echo "  └─ $max_size (log rotation)"
    fi
else
    report BOTTLENECK "Ingen logging-konfiguration — logs kan fylde diskplads uendelig"
fi
echo ""

# 6. Konkrete tiltag baseret på fund
echo "💡 KONKRETE TILTAG FOR LANGSOM FORBINDELSE"
echo "───────────────────────────────────────────────────────────────────"
echo ""

action_count=0

# Tjek for build: services
if find "$WORKSPACE_ROOT" -name "docker-compose*.yml" -type f -exec grep -l "build:" {} \; 2>/dev/null | head -1 | grep -q .; then
    action_count=$((action_count + 1))
    echo "🎯 TILBUD $action_count: KONVERTER 'build:' SERVICES TIL 'image:' + 'pull_policy: missing'"
    echo ""
    echo "   Problemet:"
    echo "   • build: får Docker til at bygge images lokalt hver gang"
    echo "   • Selv med caching tjekkes Dockerfile — langsomt på dårlig forbindelse"
    echo ""
    echo "   Løsningen:"
    echo "   • Brug direkte 'image:' med fast versionsnummer"
    echo "   • Tilføj 'pull_policy: missing' — hent kun hvis ikke lokalt"
    echo ""
    echo "   Eksempel (før):"
    echo "   ┌──────────────────────────────────────────"
    echo "   │ nginx:"
    echo "   │   build:"
    echo "   │     context: ."
    echo "   │     dockerfile: Dockerfile.nginx"
    echo "   └──────────────────────────────────────────"
    echo ""
    echo "   Efter (anbefalet for dårlig forbindelse):"
    echo "   ┌──────────────────────────────────────────"
    echo "   │ nginx:"
    echo "   │   image: nginx:1.31.0-alpine-slim"
    echo "   │   pull_policy: missing"
    echo "   └──────────────────────────────────────────"
    echo ""
fi

# Tjek for image: uden pull_policy
if find "$WORKSPACE_ROOT" -name "docker-compose*.yml" -type f -exec grep -l "image:" {} \; 2>/dev/null | while read -r cf; do
    if grep -q "image:" "$cf" && ! grep -q "pull_policy:" "$cf"; then
        echo "found"
        break
    fi
done | grep -q found; then
    action_count=$((action_count + 1))
    echo "🎯 TILBUD $action_count: TILFØJ 'pull_policy: missing' TIL ALLE 'image:' SERVICES"
    echo ""
    echo "   Problemet:"
    echo "   • Uden pull_policy tjekker Compose registry hver gang (selv om image er lokalt)"
    echo "   • Registry-tjek slår failover hvis forbindelsen er dårlig"
    echo ""
    echo "   Løsningen:"
    echo "   • Tilføj 'pull_policy: missing' — tjekker KUN hvis image mangler lokalt"
    echo ""
    echo "   Eksempel:"
    echo "   ┌──────────────────────────────────────────"
    echo "   │ dev:"
    echo "   │   image: debian:12-slim"
    echo "   │   pull_policy: missing    ← TILFØJ"
    echo "   └──────────────────────────────────────────"
    echo ""
fi

# Tjek for Dockerfile uden alpine/slim
if find "$WORKSPACE_ROOT" -name "Dockerfile*" -type f -exec grep "^FROM" {} + | grep -v -E "(alpine|slim|distroless)" | grep -q .; then
    action_count=$((action_count + 1))
    echo "🎯 TILBUD $action_count: BRUG MINDRE BASE IMAGES"
    echo ""
    echo "   Problemet:"
    echo "   • Fulde OS-images (ubuntu, debian uden slim) er 100+ MB"
    echo "   • På 1 Mbps forbindelse betyder det 100+ sekunder download"
    echo ""
    echo "   Løsningen:"
    echo "   • Brug alpine (~6-10 MB) eller slim-varianter (~20-30 MB)"
    echo "   • Faste versionsnumre sikrer reproducibltet"
    echo ""
    echo "   Eksempel:"
    echo "   ┌──────────────────────────────────────────"
    echo "   │ Fra: FROM ubuntu:22.04"
    echo "   │ Til:  FROM alpine:3.19"
    echo "   │       eller debian:12-slim"
    echo "   └──────────────────────────────────────────"
    echo ""
fi

# Tjek for bind mounts
if find "$WORKSPACE_ROOT" -name "docker-compose*.yml" -type f -exec grep -E '^\s*- \.\.' {} \; 2>/dev/null | grep -q .; then
    action_count=$((action_count + 1))
    echo "🎯 TILBUD $action_count: MINIMÉR BIND MOUNTS PÅ DÅRLIG FORBINDELSE"
    echo ""
    echo "   Problemet:"
    echo "   • Bind mounts (../) kræver konstant filsynkronisering"
    echo "   • Hver filændring skal synkroniseres over netværket"
    echo ""
    echo "   Løsningen for offline udvikling:"
    echo "   • Gennemgå hvilke bind mounts er nødvendige"
    echo "   • Overvej local volumes eller COPY i Dockerfile"
    echo ""
fi

# Tjek for ingen logging-config
if ! find "$WORKSPACE_ROOT" -name "docker-compose*.yml" -type f -exec grep -l "max-size:" {} \; 2>/dev/null | grep -q .; then
    action_count=$((action_count + 1))
    echo "🎯 TILBUD $action_count: KONFIGURÉR LOG ROTATION"
    echo ""
    echo "   Problemet:"
    echo "   • Uden log rotation fyldes disk over tid"
    echo "   • logs kan blive så store at de fylder forbindelsen"
    echo ""
    echo "   Løsningen:"
    echo "   ┌──────────────────────────────────────────"
    echo "   │ logging:"
    echo "   │   driver: json-file"
    echo "   │   options:"
    echo "   │     max-size: \"10m\"    # max 10 MB per log"
    echo "   │     max-file: \"3\"      # kun hold 3 logs"
    echo "   └──────────────────────────────────────────"
    echo ""
fi

if [ "$action_count" -eq 0 ]; then
    report OK "Ingen kritiske bottlenecks fundet! Din setup ser godt ud for dårlig forbindelse."
else
    echo "─────────────────────────────────────────────────────────────────"
    echo "ℹ️  Gennemgået $action_count konkrete tiltag."
    echo ""
fi

echo "$DIVIDER"
echo "Analyse fuldført."
echo ""
