#!/usr/bin/env bash
set -euo pipefail

: "${GITHUB_REPOSITORY:?Run this script in GitHub Actions}"
: "${GITHUB_OUTPUT:?Missing GitHub Actions output file}"

requested="${REQUESTED_CADDY_VERSION:-}"
requested="${requested#v}"
cloudflare_ref="${CLOUDFLARE_REF:-latest}"
layer4_ref="${LAYER4_REF:-latest}"

if [[ -n "$requested" && ! "$requested" =~ ^2\.[0-9]+\.[0-9]+$ ]]; then
  echo 'caddy_version must be a stable 2.x.y version, optionally prefixed with v.' >&2
  exit 1
fi
for ref in "$cloudflare_ref" "$layer4_ref"; do
  if [[ ! "$ref" =~ ^[A-Za-z0-9._/~+-]+$ ]]; then
    echo 'Invalid module ref: use a version, commit hash, or branch name.' >&2
    exit 1
  fi
done

runtime_tag="caddy:${requested:-2}"
docker pull --platform linux/amd64 "$runtime_tag"
resolved="$(docker run --rm --platform linux/amd64 "$runtime_tag" caddy version)"
version="$(awk 'NR == 1 { print $1 }' <<< "$resolved")"
version="${version#v}"
if [[ ! "$version" =~ ^2\.[0-9]+\.[0-9]+$ ]]; then
  echo 'The official image did not report a stable Caddy 2.x.y version.' >&2
  exit 1
fi
if [[ -n "$requested" && "$requested" != "$version" ]]; then
  echo 'Requested Caddy version does not match the official runtime image.' >&2
  exit 1
fi

builder_tag="caddy:${version}-builder"
docker pull --platform linux/amd64 "$builder_tag"
runtime_image="$(docker image inspect --format '{{index .RepoDigests 0}}' "$runtime_tag")"
builder_image="$(docker image inspect --format '{{index .RepoDigests 0}}' "$builder_tag")"
for image_ref in "$runtime_image" "$builder_image"; do
  if [[ ! "$image_ref" =~ @sha256:[a-f0-9]{64}$ ]]; then
    echo 'Could not resolve the official image digest.' >&2
    exit 1
  fi
done

image="ghcr.io/${GITHUB_REPOSITORY,,}"
{
  printf 'version=%s\n' "$version"
  printf 'image=%s\n' "$image"
  printf 'runtime_image=%s\n' "$runtime_image"
  printf 'builder_image=%s\n' "$builder_image"
  printf 'cloudflare_ref=%s\n' "$cloudflare_ref"
  printf 'layer4_ref=%s\n' "$layer4_ref"
} >> "$GITHUB_OUTPUT"

printf 'Building Caddy v%s for linux/amd64: %s\n' "$version" "$image"
