# syntax=docker/dockerfile:1
ARG CADDY_TAG=2.11.9
FROM --platform=$BUILDPLATFORM caddy:${CADDY_TAG}-builder AS builder
ARG TARGETOS
ARG TARGETARCH
ARG CLOUDFLARE_REF=a8737d095ad5a48ca031cea6ab704057dbc2d250
ENV CGO_ENABLED=0
ENV XCADDY_SETCAP=0
RUN GOOS="${TARGETOS}" GOARCH="${TARGETARCH}" \
    xcaddy build "${CADDY_VERSION}" --output /usr/bin/caddy \
    --with github.com/caddy-dns/cloudflare@${CLOUDFLARE_REF}

FROM caddy:${CADDY_TAG}-alpine
ARG CADDY_TAG
COPY --from=builder /usr/bin/caddy /usr/bin/caddy
RUN test "$(caddy version | cut -d ' ' -f 1)" = "v${CADDY_TAG}" \
    && caddy list-modules | grep -Fx 'dns.providers.cloudflare'
