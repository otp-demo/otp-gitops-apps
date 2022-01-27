#!/usr/bin/env bash

export AWS_KEY="awskey"
export AWS_ID="awsid"
export SSH_PRIV="$(cat id_ed25519)"
export SSH_PUB="$(cat id_ed25519.pub)"
export PULL_SECRET=$(cat pullsecret)
export CLUSTER_NAME="aws1"
export REGION="ap-southeast-1"
export POD_CIDR="10.128.0.0/14"
export SVC_CIDR="172.30.0.0/16"
export BASE_DOMAIN="mutihybridcloudkitchen.com"

./make_secret-aws.sh