#!/usr/bin/env bash

export MANIFESTS_DIR="/manifests"
export METADATA_DIR="/metadata"

export SUPPORTED_OCP_VERSIONS="${SUPPORTED_OCP_VERSIONS:-v4.17}"

if [ -z "${REPLACES_VERSION:-}" ] && [ -n "${VERSION:-}" ]; then
  patch=${VERSION##*.}
  if [ "${patch}" -ne 0 ] 2>/dev/null; then
    export REPLACES_VERSION="${VERSION%.*}.$((patch - 1))"
  else
    export REPLACES_VERSION="0.0.0"
  fi
fi 