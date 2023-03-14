#!/bin/bash

if [ "$#" -ne 2 ]; then
    echo "usage: $0 <image repo in docker hub> <tag>"
    exit 1
fi

image_repo=$1
shift
image_tag=$1
shift

IFS='.' read -r -a target_version <<< "$image_tag"

all_images=( $(hub-tool tag list --sort updated=desc $image_repo | tail -n+2 | awk '{print $1}') )


for one in "${all_images[@]}"; do
    tag=$(echo "$one" | cut -d: -f2)
    IFS='.' read -r -a current_version <<< "$tag"
    if [[ "${current_version[0]}" -ge "${target_version[0]}" && "${current_version[1]}" -ge "${target_version[1]}" && "${current_version[2]}" -ge "${target_version[2]}" ]]; then
        docker pull "$one"
        docker tag "$one" "quay.io/$one"
        docker push "quay.io/$one"
    fi
done
