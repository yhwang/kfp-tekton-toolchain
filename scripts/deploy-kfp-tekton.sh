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

set -ex

# Need the following env
# - PIPELINE_KUBERNETES_CLUSTER_NAME:   kube cluster name
# - KUBEFLOW_NS:                        namespace for kfp-tekton, defulat: kubeflow

MAX_RETRIES="${MAX_RETRIES:-5}"
SLEEP_TIME="${SLEEP_TIME:-10}"
EXIT_CODE=0
TEKTON_NS="${TEKTON_NS:-"tekton-pipelines"}"

KUSTOMIZE_DIR="${KUSTOMIZE_DIR:-"manifests/kustomize/env/platform-agnostic"}"
MANIFEST="${MANIFEST:-"$ARCHIVE_DIR/kfp-tekton.yaml"}"
KUBEFLOW_NS="${KUBEFLOW_NS:-kubeflow}"

API_SERVER_IMAGE="${API_SERVER_IMAGE:-"docker.io/aipipeline/api-server"}"
NEW_API_SERVER_IMAGE="${NEW_API_SERVER_IMAGE:-"${REGISTRY_URL}/${REGISTRY_NAMESPACE}/api-server:${IMAGE_TAG}"}"
METADATA_WRITER_IMAGE="${METADATA_WRITER_IMAGE:-"docker.io/aipipeline/metadata-writer"}"
NEW_METADATA_WRITER_IMAGE="${NEW_METADATA_WRITER_IMAGE:-"${REGISTRY_URL}/${REGISTRY_NAMESPACE}/metadata-writer:${IMAGE_TAG}"}"
PERSISTENCEAGENT_IMAGE="${PERSISTENCEAGENT_IMAGE:-"docker.io/aipipeline/persistenceagent"}"
NEW_PERSISTENCEAGENT_IMAGE="${NEW_PERSISTENCEAGENT_IMAGE:-"${REGISTRY_URL}/${REGISTRY_NAMESPACE}/persistenceagent:${IMAGE_TAG}"}"
SCHEDULEDWORKFLOW_IMAGE="${SCHEDULEDWORKFLOW_IMAGE:-"docker.io/aipipeline/scheduledworkflow"}"
NEW_SCHEDULEDWORKFLOW_IMAGE="${NEW_SCHEDULEDWORKFLOW_IMAGE:-"${REGISTRY_URL}/${REGISTRY_NAMESPACE}/scheduledworkflow:${IMAGE_TAG}"}"
SA_PATCH=$(cat << EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  labels:
    application-crd-id: kubeflow-pipelines
  name: kubeflow-pipelines-metadata-writer
  namespace: kubeflow
imagePullSecrets:
- name: all-icr-io
---
apiVersion: v1
kind: ServiceAccount
metadata:
  labels:
    application-crd-id: kubeflow-pipelines
  name: ml-pipeline
  namespace: kubeflow
imagePullSecrets:
- name: all-icr-io
---
apiVersion: v1
kind: ServiceAccount
metadata:
  labels:
    application-crd-id: kubeflow-pipelines
  name: ml-pipeline-persistenceagent
  namespace: kubeflow
imagePullSecrets:
- name: all-icr-io
---
apiVersion: v1
kind: ServiceAccount
metadata:
  labels:
    application-crd-id: kubeflow-pipelines
  name: ml-pipeline-scheduledworkflow
  namespace: kubeflow
imagePullSecrets:
- name: all-icr-io
EOF
)

# These env vars should come from the build.properties that `build-image.sh` generates
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

# main job starts from here
# ====================================================
ibmcloud login --apikey "${IBM_CLOUD_API_KEY}" --no-region
ibmcloud target -r "$REGION" -o "$ORG" -s "$SPACE"
ibmcloud ks cluster config -c "$PIPELINE_KUBERNETES_CLUSTER_NAME"

kubectl create ns "$KUBEFLOW_NS"
wait_for_namespace "$KUBEFLOW_NS" "$MAX_RETRIES" "$SLEEP_TIME" || EXIT_CODE=$?

if [[ "$EXIT_CODE" -ne 0 ]]
then
  echo "Deploy unsuccessful. \"${KUBEFLOW_NS}\" not found."
  exit "$EXIT_CODE"
fi

# copy icr secret("all-icr-io") to target namespace
kubectl get secret all-icr-io -n default -o yaml | sed "s/default/${KUBEFLOW_NS}/g" | kubectl apply -f -

# Edit image names in kustomize files 
# No need to build as long as deployed with "kubectl apply -k"
pushd $KUSTOMIZE_DIR > /dev/null

kustomize edit set image "$API_SERVER_IMAGE=$NEW_API_SERVER_IMAGE"
kustomize edit set image "$METADATA_WRITER_IMAGE=$NEW_METADATA_WRITER_IMAGE"
kustomize edit set image "$PERSISTENCEAGENT_IMAGE=$NEW_PERSISTENCEAGENT_IMAGE"
kustomize edit set image "$SCHEDULEDWORKFLOW_IMAGE=$NEW_SCHEDULEDWORKFLOW_IMAGE"
echo "$SA_PATCH" > sa_patch.yaml
kustomize edit add patch sa_patch.yaml

popd > /dev/null

# Build manifest
kustomize build "$KUSTOMIZE_DIR" -o "$MANIFEST"

# Deploy manifest
deploy_with_retries "-f" "$MANIFEST" "$MAX_RETRIES" "$SLEEP_TIME" || EXIT_CODE=$?

if [[ "$EXIT_CODE" -ne 0 ]]
then
  echo "Deploy unsuccessful. Failure applying $KUSTOMIZE_DIR."
  exit 1
fi

# Check if all pods are running - allow 60 retries (10 minutes)

wait_for_pods "$KUBEFLOW_NS" 60 "$SLEEP_TIME" || EXIT_CODE=$?

if [[ "$EXIT_CODE" -ne 0 ]]
then
  echo "Deploy unsuccessful. Not all pods running."
  exit 1
fi

echo "Finished kfp-tekton deployment." 

echo "=========================================================="
echo "Copy and prepare artificates for subsequent stages"
if [[ -z "$ARCHIVE_DIR" || "$ARCHIVE_DIR" == "." ]]; then
  echo -e "Build archive directory contains entire working directory."
else
  echo -e "Copying working dir into build archive directory: ${ARCHIVE_DIR} "
  mkdir -p "$ARCHIVE_DIR"
  find . -mindepth 1 -maxdepth 1 -not -path "./$ARCHIVE_DIR" -exec cp -R '{}' "${ARCHIVE_DIR}/" ';'
fi

cp build.properties "${ARCHIVE_DIR}/" || :

echo "KUBEFLOW_NS=${KUBEFLOW_NS}" >> "${ARCHIVE_DIR}/build.properties"
echo "MANIFEST=${MANIFEST}" >> "${ARCHIVE_DIR}/build.properties"