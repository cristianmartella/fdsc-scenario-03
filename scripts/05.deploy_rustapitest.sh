#!/bin/bash

echo "*** Rust API Test deployment ***"

kubectl apply -f ../charts/rustapitest/templates -n provider

if [ $? -ne 0 ]; then
    echo "Error deploying Rust API Test. Please check the logs."
    exit 1
else
    echo "Rust API Test deployed successfully."
fi