#!/bin/bash

# This script cleans up old images in container registry based on age and a tag
#
# For development registry it deletes images based on the following rules:
# Delete all untagged images
# Keep tagged images for 30 days
# Keep latest tag for 6 month
#
# In any other registry it deletes only untagged images

# Environment variables example usage:
    # "TO_DELETE=true",
    # "REGISTRY=myregistry",
    # "CLEAN_ONLY_UNTAGGED=false",
    # "NOTAG_MAX_AGE=30",
    # "LATEST_MAX_AGE=182",
    # "EXCLUDE_REPOS=excluded_repository_01|excluded_repository_02"

# Default values
to_delete="${TO_DELETE:-"false"}"
notag_max_age="${NOTAG_MAX_AGE:-30}" # days
latest_max_age="${LATEST_MAX_AGE:-182}" # days
registry="${REGISTRY:-"myregistry"}"
clean_only_untagged="${CLEAN_ONLY_UNTAGGED:-"true"}"

# Convert strings to arrays
default_IFS="$IFS"
exclude_repos_string="${EXCLUDE_REPOS:-"excluded_repository_01|excluded_repository_02"}"
IFS=", "
exclude_repos=($exclude_repos_string)
IFS="$default_IFS"

# Set counters
free_space=0
total_free_space=0

now=$(date +%s)
# For MacOs use this date command:
# now=$(date -j -f "%a %b %d %T %Z %Y" "`date`" "+%s")

used_space_before=$(az acr show-usage --name $registry | jq --raw-output '.value[0] | .currentValue')/1024/1024
echo "! Current usage in ${registry}: $(( $used_space_before )) MiB"

mapfile -t repositories < <(az acr repository list -n $registry -o tsv)
for repository in "${repositories[@]}"; do
    if [[ ! "${repository}" =~ (${exclude_repos[@]}) ]]; then
        read -ra repository <<< "$repository"
        mapfile -t manifests < <(az acr manifest list-metadata --registry $registry --name $repository | \
        jq -r '(.[] | [.lastUpdateTime, .imageSize, .digest, .tags[0] // "-"]) | @tsv' | sort -k 1)

        for manifest in "${manifests[@]}"; do
            read -ra manifest <<< "$manifest"
            # For MacOs use this date command:
            # manifest_date="$(date -j -f '%Y-%m-%dT%T' ${manifest[0]} '+%s' append 2>/dev/null)"
            manifest_date="$(date -d "${manifest[0]}" +%s)"
            manifest_age="$((($now - $manifest_date) / 86400))" #days

            if [ "${manifest[3]}" == "-" ] || ([ "$clean_only_untagged" == "false" ] && (([ "${manifest[3]}" != "latest" ] && [ "$manifest_age" -gt "$notag_max_age" ]) || ([ "${manifest[3]}" == "latest" ] && [ "$manifest_age" -gt "$latest_max_age" ]))); then
                echo "Will delete $repository:${manifest[3]}, $(( ${manifest[1]}/1024/1024 )) MiB, $manifest_age days old, ${manifest[2]}"
                if [ "$to_delete" == "true" ]; then
                    az acr repository delete --yes --name $registry --image $repository@${manifest[2]}
                fi
                free_space=$(( $free_space + ${manifest[1]}/1024/1024 ))
            fi
        done

        echo "$(( $free_space )) MiB will be freed in $repository"
        total_free_space=$(( $total_free_space + $free_space ))
        free_space=0
    fi
done
echo "$(( $total_free_space )) MiB will be freed"

used_space_after=$(az acr show-usage --name $registry | jq --raw-output '.value[0] | .currentValue')/1024/1024
echo "Usage in ${registry} after cleaning up: $(( $used_space_after )) MiB"
echo "Freed $(( $used_space_before - $used_space_after )) MiB"
