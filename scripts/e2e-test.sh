#!/bin/bash
set -ex

# Need the following env
# - PIPELINE_KUBERNETES_CLUSTER_NAME:       kube cluster name
# - KUBEFLOW_NS:                            kubeflow namespace

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
echo "PIPELINE_KUBERNETES_CLUSTER_NAME=${PIPELINE_KUBERNETES_CLUSTER_NAME}"
echo "KUBEFLOW_NS=${KUBEFLOW_NS}"

# copy files to ARCHIVE_DIR for next stage if needed
echo "Checking archive dir presence"
if [ -z "${ARCHIVE_DIR}" ]; then
  echo -e "Build archive directory contains entire working directory."
else
  echo -e "Copying working dir into build archive directory: ${ARCHIVE_DIR} "
  mkdir -p ${ARCHIVE_DIR}
  find . -mindepth 1 -maxdepth 1 -not -path "./$ARCHIVE_DIR" -exec cp -R '{}' "${ARCHIVE_DIR}/" ';'
fi
cp build.properties $ARCHIVE_DIR/ || :

# Set up kubernetes config
ibmcloud login --apikey ${IBM_CLOUD_API_KEY} --no-region
ibmcloud target -r "$REGION" -o "$ORG" -s "$SPACE"
ibmcloud ks cluster config -c $PIPELINE_KUBERNETES_CLUSTER_NAME

# Prepare python venv and install sdk
python3 -m venv .venv                                                           
source .venv/bin/activate                                                       
pip install wheel 
pip install -e sdk/python
pip install -U setuptools

# flip coin example
run_flip_coin_example() {
  local REV=1
  local DURATION=$1
  shift

  echo " =====   flip coin sample  ====="
  python3 samples/flip-coin/condition.py
  kfp pipeline upload -p e2e-flip-coin samples/flip-coin/condition.yaml || :
  local PIPELINE_ID=$(kfp pipeline list | grep 'e2e-flip-coin' | awk '{print $2}')
  if [[ -z "$PIPELINE_ID" ]]; then
    echo "Failed to upload pipeline"
    return "$REV"
  fi

  local RUN_NAME="e2e-flip-coin-run-$((RANDOM%10000+1))"
  kfp run submit -e exp-e2e-flip-coin -r "$RUN_NAME" -p "$PIPELINE_ID" || :
  local RUN_ID=$(kfp run list | grep "$RUN_NAME" | awk '{print $2}')
  if [[ -z "$RUN_ID" ]]; then
    echo "Failed to submit a run for flip coin pipeline"
    return "$REV"
  fi

  local RUN_STATUS
  ENDTIME=$(date -ud "$DURATION minute" +%s)
  while [[ "$(date -u +%s)" -le "$ENDTIME" ]]; do
    RUN_STATUS=$(kfp run list | grep "$RUN_NAME" | awk '{print $6}')
    if [[ "$RUN_STATUS" == "Completed" ]]; then
      REV=0
      break;
    fi
    echo "  Status of flip coin run: $RUN_STATUS"
    sleep 10
  done

  if [[ "$REV" -eq 0 ]]; then
    echo " =====   flip coin sample PASSED ====="
  else
    echo " =====   flip coin sample FAILED ====="
  fi

  return $REV
}

RESULT=0
run_flip_coin_example 10 || RESULT=$?

if [[ "$RESULT" -ne 0 ]]; then
  echo "e2e test FAILED"
  exit 1
fi