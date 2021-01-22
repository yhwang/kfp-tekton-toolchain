#!/bin/bash
# source: https://raw.githubusercontent.com/open-toolchain/commons/master/scripts/check_registry.sh
# Environment variables needed by this script:
# - REGION:               cloud region (us-south as default)
# - ORG:                  target organization (dev-advo as default)
# - SPACE:                target space (dev as default)
# - IMAGE_NAME:           image name
# - REGISTRY_URL:         registry url
# - REGISTRY_NAMESPACE:   namespace for the image
# - DOCKER_ROOT:          docker root
# - DOCKER_FILE:          docker file
# - GIT_BRANCH:           git branch
# - GIT_COMMIT:           git commit hash
# - GIT_COMMIT_SHORT:     git commit hash short

REGION=${REGION:="us-south"}
ORG=${ORG:="dev-advo"}
SPACE=${SPACE:="dev"}

set -xe

ibmcloud login --apikey ${IBM_CLOUD_API_KEY} --no-region
ibmcloud target -r "$REGION" -o "$ORG" -s "$SPACE"

echo "REGISTRY_URL=${REGISTRY_URL}"
echo "REGISTRY_NAMESPACE=${REGISTRY_NAMESPACE}"
echo "IMAGE_NAME=${IMAGE_NAME}"
echo "DOCKER_ROOT=${DOCKER_ROOT}"
echo "DOCKER_FILE=${DOCKER_FILE}"

# These env vars should come from the build.properties that `run-test.sh` generates
echo "BUILD_NUMBER=${BUILD_NUMBER}"
echo "ARCHIVE_DIR=${ARCHIVE_DIR}"
echo "GIT_BRANCH=${GIT_BRANCH}"
echo "GIT_COMMIT=${GIT_COMMIT}"
echo "GIT_COMMIT_SHORT=${GIT_COMMIT_SHORT}"
echo "REGION=${REGION}"
echo "ORG=${ORG}"
echo "SPACE=${SPACE}"

# View build properties
if [ -f build.properties ]; then
  echo "build.properties:"
  cat build.properties | grep -v -i password
else
  echo "build.properties : not found"
fi
# also run 'env' command to find all available env variables
# or learn more about the available environment variables at:
# https://cloud.ibm.com/docs/services/ContinuousDelivery/pipeline_deploy_var.html#deliverypipeline_environment

echo "=========================================================="
echo "Checking registry current plan and quota"
ibmcloud cr plan || true
ibmcloud cr quota || true
echo "If needed, discard older images using: ibmcloud cr image-rm"
echo "Checking registry namespace: ${REGISTRY_NAMESPACE}"
NS=$( ibmcloud cr namespaces | grep ${REGISTRY_NAMESPACE} ||: )
if [ -z "${NS}" ]; then
    echo "Registry namespace ${REGISTRY_NAMESPACE} not found, creating it."
    ibmcloud cr namespace-add ${REGISTRY_NAMESPACE}
    echo "Registry namespace ${REGISTRY_NAMESPACE} created."
else
    echo "Registry namespace ${REGISTRY_NAMESPACE} found."
fi
echo -e "Existing images in registry"
ibmcloud cr images --restrict ${REGISTRY_NAMESPACE}/${IMAGE_NAME}

KEEP=1
echo -e "PURGING REGISTRY, only keeping last ${KEEP} image(s) based on image digests"
COUNT=0
LIST=$( ibmcloud cr images --restrict ${REGISTRY_NAMESPACE}/${IMAGE_NAME} --no-trunc --format '{{ .Created }} {{ .Repository }}@{{ .Digest }}' | sort -r -u | awk '{print $2}' )
while read -r IMAGE_URL ; do
  if [[ "$COUNT" -lt "$KEEP" ]]; then
    echo "Keeping image digest: ${IMAGE_URL}"
  else
    ibmcloud cr image-rm "${IMAGE_URL}"
  fi
  COUNT=$((COUNT+1))
done <<< "$LIST"

echo -e "Existing images in registry after clean up"
ibmcloud cr images --restrict ${REGISTRY_NAMESPACE}/${IMAGE_NAME}

IMAGE_TAG=${BUILD_NUMBER}-${GIT_COMMIT_SHORT}
echo "=========================================================="
echo -e "BUILDING CONTAINER IMAGE: ${IMAGE_NAME}:${IMAGE_TAG}"
if [ -z "${DOCKER_ROOT}" ]; then DOCKER_ROOT=. ; fi
if [ -z "${DOCKER_FILE}" ]; then DOCKER_FILE=Dockerfile ; fi
if [ -z "$EXTRA_BUILD_ARGS" ]; then
  echo -e ""
else
  for buildArg in $EXTRA_BUILD_ARGS; do
    if [ "$buildArg" == "--build-arg" ]; then
      echo -e ""
    else
      BUILD_ARGS="${BUILD_ARGS} --opt build-arg:$buildArg"
    fi
  done
fi

ibmcloud cr build -f ${DOCKER_FILE} --tag ${REGISTRY_URL}/${REGISTRY_NAMESPACE}/${IMAGE_NAME}:${IMAGE_TAG} ${DOCKER_ROOT}
ibmcloud cr image-inspect ${REGISTRY_URL}/${REGISTRY_NAMESPACE}/${IMAGE_NAME}:${IMAGE_TAG}

# Set PIPELINE_IMAGE_URL for subsequent jobs in stage (e.g. Vulnerability Advisor)
export PIPELINE_IMAGE_URL="$REGISTRY_URL/$REGISTRY_NAMESPACE/$IMAGE_NAME:$IMAGE_TAG"
ibmcloud cr images --restrict ${REGISTRY_NAMESPACE}/${IMAGE_NAME}

######################################################################################
# Copy any artifacts that will be needed for deployment and testing to $WORKSPACE    #
######################################################################################
echo "=========================================================="
echo "COPYING ARTIFACTS needed for deployment and testing (in particular build.properties)"

echo "Checking archive dir presence"
if [ -z "${ARCHIVE_DIR}" ]; then
  echo -e "Build archive directory contains entire working directory."
else
  echo -e "Copying working dir into build archive directory: ${ARCHIVE_DIR} "
  mkdir -p ${ARCHIVE_DIR}
  find . -mindepth 1 -maxdepth 1 -not -path "./$ARCHIVE_DIR" -exec cp -R '{}' "${ARCHIVE_DIR}/" ';'
fi

# Persist env variables into a properties file (build.properties) so that all pipeline stages consuming this
# build as input and configured with an environment properties file valued 'build.properties'
# will be able to reuse the env variables in their job shell scripts.

# If already defined build.properties from prior build job, append to it.
cp build.properties $ARCHIVE_DIR/ || :

# IMAGE information from build.properties is used in Helm Chart deployment to set the release name
echo "IMAGE_NAME=${IMAGE_NAME}" >> $ARCHIVE_DIR/build.properties
echo "IMAGE_TAG=${IMAGE_TAG}" >> $ARCHIVE_DIR/build.properties
# REGISTRY information from build.properties is used in Helm Chart deployment to generate cluster secret
echo "REGISTRY_URL=${REGISTRY_URL}" >> $ARCHIVE_DIR/build.properties
echo "REGISTRY_NAMESPACE=${REGISTRY_NAMESPACE}" >> $ARCHIVE_DIR/build.properties
echo "GIT_BRANCH=${GIT_BRANCH}" >> $ARCHIVE_DIR/build.properties
echo "File 'build.properties' created for passing env variables to subsequent pipeline jobs:"
cat $ARCHIVE_DIR/build.properties | grep -v -i password
