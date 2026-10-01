# syntax=docker/dockerfile:1

# GitHub Actions resolves these to matching official images pinned by digest.
ARG CADDY_BUILDER_IMAGE=caddy:2-builder
ARG CADDY_RUNTIME_IMAGE=caddy:2

FROM ${CADDY_BUILDER_IMAGE} AS builder
ARG TARGETARCH
ARG CADDY_BUILD_VERSION
ARG CLOUDFLARE_REF=latest
ARG LAYER4_REF=latest

ENV CGO_ENABLED=0

RUN --mount=type=cache,target=/go/pkg/mod \
    --mount=type=cache,target=/root/.cache/go-build \
    set -eu; \
    test "${TARGETARCH}" = "amd64"; \
    build_version="${CADDY_BUILD_VERSION:-${CADDY_VERSION}}"; \
    case "${build_version}" in v2.*) ;; *) echo 'Expected a stable Caddy v2 version' >&2; exit 1 ;; esac; \
    xcaddy build "${build_version}" \
        --output /usr/bin/caddy \
        --with "github.com/caddy-dns/cloudflare@${CLOUDFLARE_REF}" \
        --with "github.com/mholt/caddy-l4@${LAYER4_REF}"; \
    actual_version="$(/usr/bin/caddy version | awk 'NR == 1 { print $1 }')"; \
    test "${actual_version}" = "${build_version}"; \
    mkdir -p /build-info; \
    /usr/bin/caddy version > /build-info/version.txt; \
    /usr/bin/caddy list-modules --versions > /build-info/modules.txt; \
    /usr/bin/caddy build-info > /build-info/go-build.txt; \
    grep -Eq '^dns\.providers\.cloudflare([[:space:]]|$)' /build-info/modules.txt; \
    grep -Eq '^layer4([[:space:]]|$)' /build-info/modules.txt; \
    grep -Eq '^layer4\.handlers\.proxy([[:space:]]|$)' /build-info/modules.txt

FROM ${CADDY_RUNTIME_IMAGE}

LABEL org.opencontainers.image.title="caddy-custom" \
      org.opencontainers.image.description="Caddy 2 with Cloudflare DNS and Layer 4 TCP/UDP proxy modules; linux/amd64" \
      org.opencontainers.image.source="https://github.com/1910965005/caddy-custom"

COPY --from=builder /usr/bin/caddy /usr/bin/caddy
COPY --from=builder /build-info/ /usr/share/caddy-custom/

# Keep the official runtime's command, ports, /data and /config conventions.
# Site configuration and credentials are supplied only at runtime.
