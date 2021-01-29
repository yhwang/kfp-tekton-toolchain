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

set -xe

# Environment variables needed by this script:
# - REGION: cloud region (us-south as default)
# - ORG:    target organization (dev-advo as default)
# - SPACE:  target space (dev as default)

REGION=${REGION:-"us-south"}
ORG=${ORG:-"dev-advo"}
SPACE=${SPACE:-"dev"}
GIT_COMMIT_SHORT=$(git log -n1 --format=format:"%h")

# Git repo cloned at $WORKING_DIR, copy into $ARCHIVE_DIR and
# could be used by next stage
echo "Checking archive dir presence"
if [[ -z "$ARCHIVE_DIR" || "$ARCHIVE_DIR" == "." ]]; then
  echo -e "Build archive directory contains entire working directory."
else
  echo -e "Copying working dir into build archive directory: ${ARCHIVE_DIR} "
  mkdir -p "$ARCHIVE_DIR"
  find . -mindepth 1 -maxdepth 1 -not -path "./${ARCHIVE_DIR}" -exec cp -R '{}' "${ARCHIVE_DIR}/" ';'
fi

# Record git info
echo "GIT_URL=${GIT_URL}" >> "${ARCHIVE_DIR}/build.properties"
echo "GIT_BRANCH=${GIT_BRANCH}" >> "${ARCHIVE_DIR}/build.properties"
echo "GIT_COMMIT=${GIT_COMMIT}" >> "${ARCHIVE_DIR}/build.properties"
echo "GIT_COMMIT_SHORT=${GIT_COMMIT_SHORT}" >> "${ARCHIVE_DIR}/build.properties"
echo "SOURCE_BUILD_NUMBER=${BUILD_NUMBER}" >> "${ARCHIVE_DIR}/build.properties"
echo "REGION=${REGION}" >> "${ARCHIVE_DIR}/build.properties"
echo "ORG=${ORG}" >> "${ARCHIVE_DIR}/build.properties"
echo "SPACE=${SPACE}" >> "${ARCHIVE_DIR}/build.properties"
cat "${ARCHIVE_DIR}/build.properties" | grep -v -i password

ibmcloud login --apikey "${IBM_CLOUD_API_KEY}" --no-region
ibmcloud target -r "$REGION" -o "$ORG" -s "$SPACE"

make run-go-unittests | tee "${ARCHIVE_DIR}/run-go-unittests.txt"