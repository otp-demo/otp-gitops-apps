#!/usr/bin/env bash

export VSPH_PASS="1234"
export VSPH_USER="1234"
export VSPH_CACERT"$(cat ca.crt)"
export SSH_PRIV="$(cat id_ed25519)"
export SSH_PUB="$(cat id_ed25519.pub)"
export PULL_SECRET=$(cat pullsecret)
export CLUSTER_NAME="vsphere1"

./make_secret-vsphere.sh
