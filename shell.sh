#!/usr/bin/env sh
export ASCIINEMA_REC=true
export REGISTRY=ghcr.io/andypanix/kcd2023-sigstore-demo
export IMAGE=ghcr.io/andypanix/kcd2023-sigstore-demo
export DOCKER_TAG=1.0.0
export COSIGN_EXPERIMENTAL=1
export SHELL=$(which bash)
docker login ghcr.io -u ${GITHUB_USER} -p ${GITHUB_TOKEN}
kubectx docker-desktop
clear
bash -c "source <(cosign completion bash)"
bash -i
