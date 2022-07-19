#!/usr/local/bin/bash
# This script cleans up old images in container registry based on age and a tag
#
# For aerodromedev:
# Delete all untagged images
# Keep tagged images for 30 days
# Keep latest tag for 6 month
#

max_age=30 # days
latest_max_age=182 # days
free_space=0
total_free_space=0
now=$(date -j -f "%a %b %d %T %Z %Y" "`date`" "+%s")
registry="registry_name"
exclude_repos=("excluded_repository1", "excluded_repository2")

mapfile -t repositories < <(az acr repository list -n $registry -o tsv)
for repository in "${repositories[@]}"; do
    if [[ ! "${exclude_repos[@]}" =~ "${repository}" ]]; then
        read -ra repository <<< "$repository"
        mapfile -t manifests < <(az acr manifest list-metadata --registry $registry --name $repository | \
        jq -r '(.[] | [.lastUpdateTime, .imageSize, .digest, .tags[0] // "-"]) | @tsv' | sort -k 1)

        for manifest in "${manifests[@]}"; do
            read -ra manifest <<< "$manifest"
            manifest_date="$(date -j -f '%Y-%m-%dT%T' ${manifest[0]} '+%s' append 2>/dev/null)"
            manifest_age="$((($now - $manifest_date) / 86400))" #days

            if [ "${manifest[3]}" == "-" ] || (([ "${manifest[3]}" != "latest" ] && [ "$manifest_age" -gt "$max_age" ]) || ([ "${manifest[3]}" == "latest" ] && [ "$manifest_age" -gt "$latest_max_age" ])); then
                echo "Will delete $repository, ${manifest[2]} it's $manifest_age days old, $(( ${manifest[1]}/1024/1024 )) Mb. Tag: ${manifest[3]}"
    #            az acr repository delete --name $registry --image $repository@${manifest[2]}
                free_space=$(( $free_space + ${manifest[1]} ))
            fi
        done 
        
        echo "$(( $free_space/1024/1024 )) Mb will be freed in $repository"
        total_free_space=$(( $total_free_space + $free_space ))
        free_space=0
    fi
done
echo "$(( $total_free_space/1024/1024 )) Mb will be freed"
