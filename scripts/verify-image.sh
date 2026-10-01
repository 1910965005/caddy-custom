#!/usr/bin/env bash
set -euo pipefail

: "${VERIFY_IMAGE:?Set VERIFY_IMAGE to the image to verify}"
: "${EXPECTED_CADDY_VERSION:?Set the expected version, e.g. v2.x.y}"

project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
temporary_dir="$(mktemp -d)"
container_name="caddy-custom-ci-${GITHUB_RUN_ID:-$$}-${GITHUB_RUN_ATTEMPT:-1}"
cleanup() {
  docker rm -f "$container_name" >/dev/null 2>&1 || true
  rm -rf -- "$temporary_dir"
}
trap cleanup EXIT

platform="$(docker image inspect --format '{{.Os}}/{{.Architecture}}' "$VERIFY_IMAGE")"
test "$platform" = linux/amd64
actual_version="$(docker run --rm "$VERIFY_IMAGE" caddy version | awk 'NR == 1 { print $1 }')"
test "$actual_version" = "$EXPECTED_CADDY_VERSION"
docker run --rm "$VERIFY_IMAGE" caddy list-modules --versions > "$project_dir/modules.txt"
for module in dns.providers.cloudflare layer4 layer4.handlers.proxy; do
  awk -v expected="$module" '$1 == expected { found = 1 } END { exit !found }' "$project_dir/modules.txt"
done

# Validate both deployment configurations with a syntactically valid dummy token.
# No real credentials, certificate requests, or network access are needed here.
cp -R "$project_dir/config" "$temporary_dir/config"
cp "$temporary_dir/config/layer4.caddy.example" "$temporary_dir/config/layer4.caddy"
for configuration in default with-l4; do
  if [[ "$configuration" == with-l4 ]]; then
    sed -i 's@# import /etc/caddy/layer4.caddy@import /etc/caddy/layer4.caddy@' "$temporary_dir/config/Caddyfile"
  fi
  docker run --rm --network none \
    -e DOMAIN=caddy.example.com -e ACME_EMAIL=ci@example.com \
    -e CF_API_TOKEN=0123456789012345678901234567890123456789 \
    -e L4_TCP_UPSTREAM=127.0.0.1:5432 -e L4_UDP_UPSTREAM=127.0.0.1:51820 \
    -v "$temporary_dir/config:/etc/caddy:ro" \
    "$VERIFY_IMAGE" caddy adapt --config /etc/caddy/Caddyfile --adapter caddyfile --validate \
    > "$temporary_dir/${configuration}.json"
done

# Check Compose interpolation and the additional L4 port mappings.
DOMAIN=caddy.example.com ACME_EMAIL=ci@example.com CF_API_TOKEN=ci-placeholder \
  docker compose -f "$project_dir/compose.yaml" -f "$project_dir/compose.l4.yaml" config --quiet

docker run --detach --name "$container_name" \
  -p 127.0.0.1::18080/tcp -p 127.0.0.1::18443/tcp \
  -p 127.0.0.1::18443/udp -p 127.0.0.1::15432/tcp -p 127.0.0.1::15182/udp \
  -v "$project_dir/ci/Smoke.Caddyfile:/etc/caddy/Caddyfile:ro" \
  "$VERIFY_IMAGE"

http_port="$(docker port "$container_name" 18080/tcp | awk -F: 'NR == 1 { print $NF }')"
https_port="$(docker port "$container_name" 18443/tcp | awk -F: 'NR == 1 { print $NF }')"
tcp_port="$(docker port "$container_name" 15432/tcp | awk -F: 'NR == 1 { print $NF }')"
udp_port="$(docker port "$container_name" 15182/udp | awk -F: 'NR == 1 { print $NF }')"
if ! python3 "$project_dir/ci/smoke.py" "$http_port" "$https_port" "$tcp_port" "$udp_port"; then
  docker logs "$container_name" >&2
  exit 1
fi

echo 'Verified: amd64, exact Caddy version, Cloudflare/L4 modules, configuration validation, HTTP/HTTPS, TCP proxy and UDP proxy.'
