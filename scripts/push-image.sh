#!/bin/bash
#
# Copyright 2021 kubeflow.org
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
# source: https://raw.githubusercontent.com/open-toolchain/commons/master/scripts/check_registry.sh

# Remove the x if you do need to print out each command
set -xe

IMAGES=${IMAGES:-"api-server persistenceagent metadata-writer scheduledworkflow"}
PUSH_TAG=${PUSH_TAG:-"nightly"}
DOCKERHUB_NAMESPACE=${DOCKERHUB_NAMESPACE:-"aipipeline"}

echo "REGISTRY_URL=${REGISTRY_URL}"
echo "REGISTRY_NAMESPACE=${REGISTRY_NAMESPACE}"
echo "BUILD_NUMBER=${BUILD_NUMBER}"
echo "ARCHIVE_DIR=${ARCHIVE_DIR}"
echo "GIT_BRANCH=${GIT_BRANCH}"
echo "GIT_COMMIT=${GIT_COMMIT}"
echo "GIT_COMMIT_SHORT=${GIT_COMMIT_SHORT}"
echo "REGION=${REGION}"
echo "ORG=${ORG}"
echo "SPACE=${SPACE}"
echo "IMAGE_TAG=${IMAGE_TAG}"

ibmcloud login --apikey "${IBM_CLOUD_API_KEY}" --no-region
ibmcloud target -r "$REGION" -o "$ORG" -s "$SPACE"
ibmcloud ks cluster config -c "$PIPELINE_KUBERNETES_CLUSTER_NAME"
ibmcloud cr login

# copy certs to local env
kubectl cp -n "$DIND_NS" docker:/certs/client ~/.docker
kubectl port-forward -n "$DIND_NS" docker 2376:2376 &
# wait for the port-forward
sleep 5

# login dockerhub
set +x
DOCKER_HOST=tcp://localhost:2376 DOCKER_TLS_VERIFY=1  docker login \
  -u "$DOCKERHUB_USERNAME" -p "$DOCKERHUB_TOKEN"
set -x

for one in $IMAGES; do
  DOCKER_HOST=tcp://localhost:2376 DOCKER_TLS_VERIFY=1  docker pull \
    "${REGISTRY_URL}/${REGISTRY_NAMESPACE}/${one}:${IMAGE_TAG}"

  DOCKER_HOST=tcp://localhost:2376 DOCKER_TLS_VERIFY=1  docker tag \
    "${REGISTRY_URL}/${REGISTRY_NAMESPACE}/${one}:${IMAGE_TAG}" "${DOCKERHUB_NAMESPACE}/${one}:${PUSH_TAG}"

  DOCKER_HOST=tcp://localhost:2376 DOCKER_TLS_VERIFY=1  docker push \
    "${DOCKERHUB_NAMESPACE}/${one}:${PUSH_TAG}"
done

kill %1
