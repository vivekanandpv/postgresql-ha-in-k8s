#!/bin/bash
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

ARCH="$(uname -m)"
case "$ARCH" in
  arm64|aarch64) TARGETARCH="arm64" ;;
  x86_64|amd64)  TARGETARCH="amd64" ;;
  *) echo "Unsupported architecture: ${ARCH}" >&2; exit 1 ;;
esac

log "building ${IMAGE} (TARGETARCH=${TARGETARCH})"
docker build \
  --build-arg TARGETARCH="${TARGETARCH}" \
  -t "${IMAGE}" \
  "${REPO_ROOT}/docker/patroni-postgres"

log "loading ${IMAGE} into kind cluster '${CLUSTER_NAME}'"
kind load docker-image "${IMAGE}" --name "${CLUSTER_NAME}"
