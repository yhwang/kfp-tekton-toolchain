#!/bin/bash
set -xe

# Environment variables needed by this script:
# - REGION: cloud region (us-south as default)
# - ORG:    target organization (dev-advo as default)
# - SPACE:  target space (dev as default)

REGION=${REGION:-"us-south"}
ORG=${ORG:-"dev-advo"}
SPACE=${SPACE:-"dev"}

# Git repo cloned at $WORKING_DIR, copy into $ARCHIVE_DIR and
# could be used by next stage
echo "Checking archive dir presence"
if [ -z "${ARCHIVE_DIR}" ]; then
  echo -e "Build archive directory contains entire working directory."
else
  echo -e "Copying working dir into build archive directory: ${ARCHIVE_DIR} "
  mkdir -p ${ARCHIVE_DIR}
  find . -mindepth 1 -maxdepth 1 -not -path "./$ARCHIVE_DIR" -exec cp -R '{}' "${ARCHIVE_DIR}/" ';'
fi

GIT_COMMIT_SHORT=$(git log -n1 --format=format:"%h")

# Record git info
echo "GIT_URL=${GIT_URL}" >> $ARCHIVE_DIR/build.properties
echo "GIT_BRANCH=${GIT_BRANCH}" >> $ARCHIVE_DIR/build.properties
echo "GIT_COMMIT=${GIT_COMMIT}" >> $ARCHIVE_DIR/build.properties
echo "GIT_COMMIT_SHORT=${GIT_COMMIT_SHORT}" >> $ARCHIVE_DIR/build.properties
echo "SOURCE_BUILD_NUMBER=${BUILD_NUMBER}" >> $ARCHIVE_DIR/build.properties
echo "REGION=${REGION}" >> $ARCHIVE_DIR/build.properties
echo "ORG=${ORG}" >> $ARCHIVE_DIR/build.properties
echo "SPACE=${SPACE}" >> $ARCHIVE_DIR/build.properties
cat $ARCHIVE_DIR/build.properties

make run-go-unittests | tee $ARCHIVE_DIR/run-go-unittests.txt

# check if doi is integrated in this toolchain
if jq -e '.services[] | select(.service_id=="draservicebroker")' _toolchain.json; then
  ibmcloud login --apikey ${IBM_CLOUD_API_KEY} --no-region
  ibmcloud target -r "$REGION" -o "$ORG" -s "$SPACE"
  ibmcloud doi publishbuildrecord --branch ${GIT_BRANCH} --repositoryurl ${GIT_URL} --commitid ${GIT_COMMIT} \
    --buildnumber ${BUILD_NUMBER} --logicalappname ${IMAGE_NAME} --status pass
fi

