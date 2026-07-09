#!/usr/bin/env bash
set -euo pipefail

mods="$(GOFLAGS=-mod=mod go list -m -f '{{.Path}} {{.Version}}' all)"

version_key() {
  local version="${1#v}"
  version="${version%%+*}"
  version="${version%%-*}"
  IFS=. read -r major minor patch rest <<<"$version"
  printf '%06d%06d%06d\n' "${major:-0}" "${minor:-0}" "${patch:-0}"
}

version_lt() {
  [[ "$(version_key "$1")" < "$(version_key "$2")" ]]
}

version_le() {
  [[ "$(version_key "$1")" < "$(version_key "$2")" || "$(version_key "$1")" == "$(version_key "$2")" ]]
}

version_ge() {
  ! version_lt "$1" "$2"
}

selected_version() {
  awk -v mod="$1" '$1 == mod { print $2; exit }' <<<"$mods"
}

require_absent() {
  local mod="$1" version
  version="$(selected_version "$mod")"
  if [ -n "$version" ]; then
    echo "$mod is selected at $version; remove it from the module graph" >&2
    exit 1
  fi
}

require_min() {
  local mod="$1" min="$2" version
  version="$(selected_version "$mod")"
  if [ -n "$version" ] && version_lt "$version" "$min"; then
    echo "$mod is $version, expected >= $min" >&2
    exit 1
  fi
}

require_not_otel_vulnerable() {
  local version
  version="$(selected_version go.opentelemetry.io/otel)"
  if [ -n "$version" ] && version_ge "$version" v1.36.0 && version_le "$version" v1.40.0; then
    echo "go.opentelemetry.io/otel is $version, expected outside vulnerable range v1.36.0-v1.40.x" >&2
    exit 1
  fi
}

require_absent github.com/docker/docker
require_min github.com/docker/cli v29.3.1
require_min github.com/opencontainers/runc v1.3.6
require_min go.mongodb.org/mongo-driver v1.17.7
require_min github.com/gofiber/fiber/v2 v2.52.13
require_min github.com/shamaton/msgpack/v2 v2.4.1
require_min golang.org/x/crypto v0.53.0
require_min golang.org/x/image v0.18.0
require_not_otel_vulnerable

echo "dependency security graph ok"
