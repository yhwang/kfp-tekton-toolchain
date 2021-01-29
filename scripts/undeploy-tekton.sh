#!/bin/bash
set -ex
# Need the following env var
# - KUBEFLOW_NS:                        namespace for kfp-tekton, defulat: kubeflow

KUBEFLOW_NS="${KUBEFLOW_NS:-kubeflow}"

# These env vars should come from the build.properties that `build-image.sh` generates
echo "PIPELINE_KUBERNETES_CLUSTER_NAME=${PIPELINE_KUBERNETES_CLUSTER_NAME}"
echo "TEKTON_VERSION=${TEKTON_VERSION}"
echo "TEKTON_NS=${TEKTON_NS}"
echo "TEKTON_MANIFEST=${TEKTON_MANIFEST}"
echo "KUBEFLOW_NS=${KUBEFLOW_NS}"
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

ibmcloud login --apikey ${IBM_CLOUD_API_KEY} --no-region
ibmcloud target -r "$REGION" -o "$ORG" -s "$SPACE"
ibmcloud ks cluster config -c $PIPELINE_KUBERNETES_CLUSTER_NAME

kubectl delete -f $TEKTON_MANIFEST_FILENAME || :
kubectl delete MutatingWebhookConfiguration cache-webhook-kubeflow webhook.pipeline.tekton.dev || :
kubectl delete ns $KUBEFLOW_NS || :

echo "Finished kfp-tekton undeployment."