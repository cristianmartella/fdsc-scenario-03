# Copyright 2025 Cristian Martella
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

#!/bin/bash

echo "*** Kubernetes Dashboard deployment ***"

# Add kubernetes-dashboard repository
helm repo add kubernetes-dashboard https://kubernetes.github.io/dashboard/ 
# Deploy a Helm Release named "kubernetes-dashboard" using the kubernetes-dashboard chart
helm upgrade --install kubernetes-dashboard kubernetes-dashboard/kubernetes-dashboard --create-namespace --namespace kubernetes-dashboard

# Apply the necessary Kubernetes resources for the dashboard
kubectl apply -f ../charts/kubernetes-dashboard/templates

echo "Waiting for the kubernetes-dashboard pods to be ready..."
kubectl wait pod --all --for=condition=Ready -n kubernetes-dashboard --timeout=60s &>/dev/null && kill -INT $(pidof watch) 2>/dev/null &
watch kubectl get pods -n kubernetes-dashboard

echo -e "########################## DASHBOARD TOKEN ##########################"
kubectl get secret admin-user -n kubernetes-dashboard -o jsonpath="{.data.token}" | base64 -d
echo -e "\n\n"

kubectl -n kubernetes-dashboard port-forward svc/kubernetes-dashboard-kong-proxy 8444:443 &>/dev/null &
echo -e "Kubernetes Dashboard is now accessible at https://localhost:8444"
echo -e"To access the dashboard, use the token above."