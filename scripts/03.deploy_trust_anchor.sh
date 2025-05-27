#!/bin/bash

trust_anchor_root=$(builtin cd $(pwd)/..; pwd)/trust-anchor
trust_anchor_name=$(basename $trust_anchor_root)

echo "Updating .participants.tmp file..."
echo "$trust_anchor_name" >> .participants.tmp

echo "*** Trust anchor deployment ***"

echo "Creating trust-anchor namespace..."
kubectl create namespace trust-anchor

echo "Deploying trust-anchor..."
helm repo add data-space-connector https://fiware.github.io/data-space-connector/
helm install trust-anchor-dsc data-space-connector/trust-anchor --version 2.0.0 -f $trust_anchor_root/values.yaml --namespace=trust-anchor

kubectl wait pod --all --for=condition=Ready -n trust-anchor --timeout=300s && kill -INT $(pidof watch) 2>/dev/null &
watch kubectl get pods -n trust-anchor

echo "*** Trust anchor deployed ***"