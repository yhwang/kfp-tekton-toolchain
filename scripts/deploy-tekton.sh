#!/bin/bash
set -ex

# Need the following env
# - PIPELINE_KUBERNETES_CLUSTER_NAME:       kube cluster name
# - TEKTON_VERSION:                         tekton version
# - TEKTON_NS:                              tekton namespace, defulat: tekton-pipeline

# These env vars should come from the build.properties that `build-image.sh` generates
echo "REGISTRY_URL=${REGISTRY_URL}"
echo "REGISTRY_NAMESPACE=${REGISTRY_NAMESPACE}"
echo "IMAGE_NAME=${IMAGE_NAME}"
echo "BUILD_NUMBER=${BUILD_NUMBER}"
echo "ARCHIVE_DIR=${ARCHIVE_DIR}"
echo "GIT_BRANCH=${GIT_BRANCH}"
echo "GIT_COMMIT=${GIT_COMMIT}"
echo "GIT_COMMIT_SHORT=${GIT_COMMIT_SHORT}"
echo "REGION=${REGION}"
echo "ORG=${ORG}"
echo "SPACE=${SPACE}"

MAX_RETRIES="${MAX_RETRIES:-5}"
SLEEP_TIME="${SLEEP_TIME:-10}"
EXIT_CODE=0
TEKTON_NS="${TEKTON_NS:-"tekton-pipelines"}"
# Previous versions use form: "previous/vX.Y.Z"
TEKTON_VERSION="${TEKTON_VERSION:-"latest"}"
TEKTON_MANIFEST="${TEKTON_MANIFEST:-https://storage.googleapis.com/tekton-releases/pipeline/${TEKTON_VERSION}/release.yaml}"

echo "PIPELINE_KUBERNETES_CLUSTER_NAME=${PIPELINE_KUBERNETES_CLUSTER_NAME}"
echo "TEKTON_VERSION=${TEKTON_VERSION}"
echo "TEKTON_NS=${TEKTON_NS}"

# Retrive tekton yaml and store it to ARCHIVE_DIR and
# could be used at cleanup stage
TEKTON_MANIFEST_FILENAME=tekton-manifest.yaml
curl -sSL "$TEKTON_MANIFEST" -o "${ARCHIVE_DIR}/${TEKTON_MANIFEST_FILENAME}"

ibmcloud login --apikey ${IBM_CLOUD_API_KEY} --no-region
ibmcloud target -r "$REGION" -o "$ORG" -s "$SPACE"
ibmcloud ks cluster config -c $PIPELINE_KUBERNETES_CLUSTER_NAME

# Make sure the cluster is running and get the ip_address
ip_addr=$(ibmcloud ks workers --cluster $PIPELINE_KUBERNETES_CLUSTER_NAME | grep normal | awk '{ print $2 }')
if [ -z $ip_addr ]; then
  echo "$PIPELINE_KUBERNETES_CLUSTER_NAME not created or workers not ready"
  exit 1
fi

kubectl apply -f "${ARCHIVE_DIR}/${TEKTON_MANIFEST_FILENAME}"

wait_for_namespace $TEKTON_NS $MAX_RETRIES $SLEEP_TIME || EXIT_CODE=$?

if [[ $EXIT_CODE -ne 0 ]]
then
  echo "Deploy unsuccessful. \"${TEKTON_NS}\" not found."
  exit $EXIT_CODE
fi

wait_for_pods $TEKTON_NS $MAX_RETRIES $SLEEP_TIME || EXIT_CODE=$?

if [[ $EXIT_CODE -ne 0 ]]
then
  echo "Deploy unsuccessful. Not all pods running."
  exit 1
fi

echo "Finished tekton deployment."

echo "Checking archive dir presence"
if [ -z "${ARCHIVE_DIR}" ]; then
  echo -e "Build archive directory contains entire working directory."
else
  echo -e "Copying working dir into build archive directory: ${ARCHIVE_DIR} "
  mkdir -p ${ARCHIVE_DIR}
  find . -mindepth 1 -maxdepth 1 -not -path "./$ARCHIVE_DIR" -exec cp -R '{}' "${ARCHIVE_DIR}/" ';'
fi

cp build.properties $ARCHIVE_DIR/ || :

echo "TEKTON_NS=${TEKTON_NS}" >> $ARCHIVE_DIR/build.properties
echo "PIPELINE_KUBERNETES_CLUSTER_NAME=${PIPELINE_KUBERNETES_CLUSTER_NAME}" >> $ARCHIVE_DIR/build.properties
echo "TEKTON_VERSION=${TEKTON_VERSION}" >> $ARCHIVE_DIR/build.properties
echo "TEKTON_MANIFEST=${TEKTON_MANIFEST}" >> $ARCHIVE_DIR/build.properties
echo "TEKTON_MANIFEST_FILENAME=${TEKTON_MANIFEST_FILENAME}" >> $ARCHIVE_DIR/build.properties
