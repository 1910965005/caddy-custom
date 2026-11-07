#!/usr/bin/env bash
set -euo pipefail
image="${1:?Usage: smoke-test.sh IMAGE}"
container="caddy-smoke-${RANDOM}"
cleanup() {
  docker logs "$container" 2>/dev/null || true
  docker rm -f "$container" >/dev/null 2>&1 || true
}
trap cleanup EXIT
docker run --rm "$image" caddy version
docker run --rm "$image" caddy list-modules | grep -Fx 'dns.providers.cloudflare'
docker run --rm -v "$PWD/conf:/etc/caddy:ro" "$image" \
  caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile
docker run --rm -v "$PWD/examples:/examples:ro" "$image" \
  caddy adapt --config /examples/Caddyfile.cloudflare --adapter caddyfile >/dev/null
docker run -d --name "$container" -p 127.0.0.1::80 \
  -v "$PWD/conf:/etc/caddy:ro" "$image"
port="$(docker port "$container" 80/tcp | sed 's/.*://')"
# Docker may accept connections before Caddy is ready, causing either a
# refused connection or a reset. Retry readiness, but require the exact body.
for attempt in {1..30}; do
  if response="$(curl --fail --silent --show-error --max-time 2 "http://127.0.0.1:${port}")"; then
    if [[ "$response" == "Caddy custom image is running." ]]; then
      printf '%s\n' "$response"
      exit 0
    fi
  fi
  sleep 1
done
echo "Caddy did not return the expected HTTP response before the deadline" >&2
exit 1
