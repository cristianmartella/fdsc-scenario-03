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

echo "*** Rust API Test deployment ***"

kubectl apply -f ../charts/rustapitest/templates -n provider

if [ $? -ne 0 ]; then
    echo "Error deploying Rust API Test. Please check the logs."
    exit 1
else
    echo "Rust API Test deployed successfully."
fi