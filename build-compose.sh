#!/usr/bin/env bash
###
# File: build-compose.sh
# Project: scripts
# File Created: Wednesday, 10th April 2024 7:49:13 am
# Author: Josh.5 (jsunnex@gmail.com)
# -----
# Last Modified: Friday, 11th July 2025 2:01:53 pm
# Modified By: Josh.5 (jsunnex@gmail.com)
###

set -euo pipefail

# Function to get the latest image SHA from Docker Hub
get_latest_tag_from_docker_hub() {
    local image_name="$1"
    local image_tag="$2"
    local image_name_encoded
    local token
    local api_url
    local manifest_digest
    local manifest_digest_header
    local multi_platform_index_digest
    # Encode the image name for API compatibility
    image_name_encoded=$(echo "${image_name:?}" | sed 's/\//%2F/g')
    # Obtain an authentication token.
    token=$(curl -s "https://auth.docker.io/token?service=registry.docker.io&scope=repository:${image_name_encoded:?}:pull" | jq -r '.token')
    # Fetch the manifest list for the specified tag and extract the Docker-Content-Digest header.
    # This requires specifying the Accept header for the manifest list format.
    api_url=https://index.docker.io/v2
    #api_url="https://registry.hub.docker.com/v2"
    #api_url="https://registry.docker.io/v2"
    #api_url="https://registry-1.docker.io/v2"
    #api_url="https://hub.docker.com/v2"
    # Attempt to fetch the manifest list to check if this is a multi-arch image
    manifest_digest=$(curl -s -H "Authorization: Bearer $token" \
        -H "Accept: application/vnd.docker.distribution.manifest.list.v2+json" \
        "https://registry-1.docker.io/v2/${image_name_encoded:?}/manifests/${image_tag}")
    # Check if the response contains a 'manifests' array
    if echo "${manifest_digest:?}" | jq -e '.manifests' >/dev/null; then
        # The image supports multi-arch (has a 'manifests' array)
        # Fetch the manifest list for the specified tag and extract the Docker-Content-Digest header.
        # This requires specifying the Accept header for the manifest list format.
        manifest_digest_header=$(curl -s -I -H "Authorization: Bearer $token" -H "Accept: application/vnd.docker.distribution.manifest.list.v2+json" "https://registry-1.docker.io/v2/${image_name_encoded:?}/manifests/${image_tag}")
        # Extract the Docker-Content-Digest value
        multi_platform_index_digest=$(echo "${manifest_digest_header:?}" | grep -i 'Docker-Content-Digest' | awk '{print $2}' | tr -d $'\r')
    else
        # The image does not support multi-arch, fall back to single manifest
        manifest_digest_header=$(curl -s -I -H "Authorization: Bearer $token" -H "Accept: application/vnd.docker.distribution.manifest.v2+json" "${api_url:?}/${image_name_encoded:?}/manifests/${image_tag}")
        # Extract the Docker-Content-Digest value
        multi_platform_index_digest=$(echo "${manifest_digest_header:?}" | grep -i 'Docker-Content-Digest' | awk '{print $2}' | tr -d $'\r')
    fi
    # Return this extracted value
    echo "${multi_platform_index_digest:-}"
}

# Function to get the latest image SHA from Docker Hub or GHCR
get_latest_tag_from_ghcr() {
    local image_name="$1"
    local image_tag="$2"
    # Encode the image name for API compatibility
    local image_name_encoded=$(echo "${image_name#ghcr.io/}" | sed 's/\//%2F/g')
    # Obtain an authentication token.
    local scope="repository:${image_name#ghcr.io/}:pull"
    local token=$(curl -s "https://ghcr.io/token?service=ghcr.io&scope=${scope}" | jq -r '.token')
    # Fetch the manifest list for the specified tag and extract the Docker-Content-Digest header.
    local accept_header="application/vnd.oci.image.index.v1+json, application/vnd.docker.distribution.manifest.list.v2+json"
    # Fetch the manifest list for the specified tag and extract the Docker-Content-Digest header.
    local manifest_digest_header=$(curl -s -I -H "Authorization: Bearer $token" -H "Accept: ${accept_header:?}" "https://ghcr.io/v2/${image_name_encoded:?}/manifests/${image_tag}")
    # Extract the Docker-Content-Digest value
    local multi_platform_index_digest=$(echo "${manifest_digest_header}" | grep -i 'Docker-Content-Digest' | awk '{print $2}' | tr -d $'\r')
    # Return this extracted value
    echo "${multi_platform_index_digest:-}"
}

# Function to get the latest image SHA from Quay.io
get_latest_tag_from_quay() {
    local image_name="$1"
    local image_tag="$2"
    # Encode the image name for API compatibility
    local image_name_encoded=$(echo "${image_name#quay.io/}" | sed 's/\//%2F/g')
    # Fetch the manifest list for the specified tag and extract the Docker-Content-Digest header.
    local accept_header="application/vnd.oci.image.index.v1+json, application/vnd.docker.distribution.manifest.list.v2+json"
    # Fetch the manifest list for the specified tag and extract the Docker-Content-Digest header.
    local manifest_digest_header=$(curl -s -I -H "Accept: ${accept_header:?}" "https://quay.io/v2/${image_name_encoded:?}/manifests/${image_tag}")
    # Extract the Docker-Content-Digest value
    local multi_platform_index_digest=$(echo "${manifest_digest_header}" | grep -i 'Docker-Content-Digest' | awk '{print $2}' | tr -d $'\r')
    # Return this extracted value
    echo "${multi_platform_index_digest:-}"
}

process_template() {
    local template_name="$(basename "${1}")"
    local templates_dir="$(dirname "${1}")"
    local build_path="${templates_dir:?}/build"
    local dist_path="${templates_dir:?}/dist"
    # Create dist path
    mkdir -p "${build_path:?}" "${dist_path:?}"
    # Copy template
    cp -f "${templates_dir:?}/${template_name}" "${dist_path:?}/${template_name}"
    # Define your docker-compose file location
    local DOCKER_COMPOSE_FILE="${dist_path:?}/${template_name}"
    local ENV_EXAMPLE_FILE="${DOCKER_COMPOSE_FILE%.y*ml}.env.example"

    # Read each line in the docker-compose file
    while IFS= read -r line; do
        if [[ $line == *"image:"* ]]; then
            if [[ $line == *":latest"* ]] || [[ $line == *"#>convert_sha256" ]]; then
                # Extract the image name and tag
                local image_name_with_tag=$(echo $line | sed -n 's/.*image: \(.*\)/\1/p' | awk '{print $1}')
                local image_name=$(echo $image_name_with_tag | cut -d':' -f1)
                local image_tag=$(echo $image_name_with_tag | cut -d':' -f2)

                echo "--> Fetching SHA for image '${image_name}:${image_tag}'"

                if [[ $image_name == ghcr.io/* ]]; then
                    local new_image_tag="$(get_latest_tag_from_ghcr "$image_name" "$image_tag")"
                elif [[ $image_name == quay.io/* ]]; then
                    local new_image_tag="$(get_latest_tag_from_quay "$image_name" "$image_tag")"
                else
                    local new_image_tag="$(get_latest_tag_from_docker_hub "$image_name" "$image_tag")"
                fi

                # Replace the tag with the SHA in the docker-compose file
                if [ -n "${new_image_tag:-}" ]; then
                    echo "    > Updating template to use '${image_name}@${new_image_tag:?}'."
                    sed -i "s|${image_name_with_tag}.*$|${image_name}@${new_image_tag:?}|g" "${DOCKER_COMPOSE_FILE}"
                else
                    echo "    > Failed to fetch image digest for image '${image_name}:${image_tag}'. Keeping it as is."
                fi
            else
                # Extract the image name
                image_name=$(echo $line | sed -n 's/.*image: \(.*\)/\1/p')
                echo "--> Ignoring '${image_name:?}' as it is not configured to use 'latest' or '#>convert_sha256'"
            fi
        elif [[ $line == *"# RELEASE:"* ]]; then
            local tag_release=$(echo $line | sed -n 's/.*RELEASE: \(.*\)/\1/p' | awk '{print $1}')
            echo ${tag_release:?} >>"${build_path:?}"/tags.txt
        elif [[ $line == *"<GIT_COMMIT_SHORT_SHA>"* ]]; then
            if [[ -n "${GITHUB_SHA:-}" ]]; then
                short_sha="${GITHUB_SHA:0:7}"
                echo "--> Replacing <GIT_COMMIT_SHORT_SHA> with ${short_sha}"
                sed -i "s|<GIT_COMMIT_SHORT_SHA>|${short_sha}|g" "${DOCKER_COMPOSE_FILE}"
            else
                echo "--> GITHUB_SHA not set, removing placeholder line"
                sed -i "/<GIT_COMMIT_SHORT_SHA>/d" "${DOCKER_COMPOSE_FILE}"
            fi
        fi
    done <"${DOCKER_COMPOSE_FILE:?}"

    # Extract configuration block (if one exists)
    if grep -q "# <config_start>" "${DOCKER_COMPOSE_FILE:?}"; then
        sed -n '/# <config_start>/,/# <config_end>/p' "${DOCKER_COMPOSE_FILE:?}" | sed '/# <config_start>/d;/# <config_end>/d;s/^#   //' >"${ENV_EXAMPLE_FILE:?}"
        echo "--> Configuration example extracted to: ${ENV_EXAMPLE_FILE:?}"
    else
        echo "--> No configuration block found in ${DOCKER_COMPOSE_FILE:?}. No example env file is created."
    fi
}

path_arg="${@:?}"
if [ -d "${path_arg:?}" ]; then
    for file in "${path_arg:?}"/docker-compose*.yml; do
        # Check if file exists to avoid processing in case no files match
        if [ -e "${file:?}" ]; then
            echo "Processing template '${file:?}'."
            process_template "${file:?}"
        fi
    done
else
    # Check if docker_swarm_templates_path is a file
    if [ -f "${path_arg:?}" ]; then
        echo "Processing template '${path_arg:?}'."
        process_template "${path_arg:?}"
    fi
fi
