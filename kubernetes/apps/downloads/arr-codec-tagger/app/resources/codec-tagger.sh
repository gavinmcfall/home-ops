#!/usr/bin/env bash
# shellcheck disable=SC2154
set -euo pipefail

# Codec tagger for Sonarr and Radarr instances
# Tags series/movies based on the video codecs found in their files

# Helper function to decode base64 and process JSON using jq
_jq() {
    echo "$1" | base64 --decode | jq --raw-output "$2"
}

# Map raw codec to normalized tag
normalize_codec() {
    local codec=$1
    codec=$(echo "$codec" | tr '[:upper:]' '[:lower:]')

    case "$codec" in
        avc|divx|h264|x264|mpeg4)
            echo "codec:h264"
            ;;
        hevc|h265|x265)
            echo "codec:h265"
            ;;
        av1)
            echo "codec:av1"
            ;;
        vc1|vc-1)
            echo "codec:vc1"
            ;;
        mpeg2|mpeg-2)
            echo "codec:mpeg2"
            ;;
        *)
            echo "codec:other"
            ;;
    esac
}

# Process a Sonarr instance
process_sonarr() {
    local url=$1
    local api_key=$2
    local instance_name=$3

    echo "=== Processing Sonarr: ${instance_name} ==="

    local curl_cmd=("curl" "-fsSL" "--header" "X-Api-Key: ${api_key}")

    # Cache existing tags
    local existing_tags
    existing_tags=$("${curl_cmd[@]}" "${url}/api/v3/tag")

    # Get all series
    local series_list
    series_list=$("${curl_cmd[@]}" "${url}/api/v3/series?includeSeasonImages=false" | jq --compact-output 'sort_by(.title)')
    local total_series
    total_series=$(echo "${series_list}" | jq 'length')

    echo "Found ${total_series} series"

    local series_count=1
    for serie in $(echo "${series_list}" | jq --raw-output '.[] | @base64'); do
        local series_id series_title episode_file_count
        series_id=$(_jq "${serie}" ".id")
        series_title=$(_jq "${serie}" ".title")
        episode_file_count=$(_jq "${serie}" ".statistics.episodeFileCount")

        if [[ ${episode_file_count} == "null" || ${episode_file_count} -eq 0 ]]; then
            ((series_count++))
            continue
        fi

        # Get unique codecs for the series
        local codecs
        codecs=$("${curl_cmd[@]}" "${url}/api/v3/episodefile?seriesId=${series_id}" | jq --raw-output '
            [.[].mediaInfo.videoCodec // "other"] | unique | .[]
        ')

        # Normalize codecs to tags
        local normalized_tags=()
        for codec in $codecs; do
            normalized_tags+=("$(normalize_codec "$codec")")
        done
        # Remove duplicates
        IFS=$'\n' normalized_tags=($(printf '%s\n' "${normalized_tags[@]}" | sort -u))

        # Get current series data
        local orig_series_data
        orig_series_data=$("${curl_cmd[@]}" "${url}/api/v3/series/${series_id}?includeSeasonImages=false")
        local series_tags
        series_tags=$(echo "$orig_series_data" | jq --raw-output '.tags')

        # Track tags to add/remove
        local tags_to_add=()
        local tags_to_remove=()

        # Get or create tag IDs for normalized tags
        for tag_label in "${normalized_tags[@]}"; do
            local tag_id
            tag_id=$(echo "${existing_tags}" | jq --raw-output ".[] | select(.label == \"${tag_label}\") | .id")

            if [[ -z "${tag_id}" ]]; then
                # Create tag
                local new_tag
                new_tag=$("${curl_cmd[@]}" -X POST -H "Content-Type: application/json" -d "{\"label\": \"${tag_label}\"}" "${url}/api/v3/tag")
                tag_id=$(echo "${new_tag}" | jq --raw-output '.id')
                existing_tags=$(echo "${existing_tags}" | jq ". += [{\"id\": ${tag_id}, \"label\": \"${tag_label}\"}]")
            fi

            if ! echo "${series_tags}" | jq --exit-status ". | index(${tag_id})" &> /dev/null; then
                tags_to_add+=("$tag_id")
            fi
        done

        # Identify codec tags to remove (tags that start with "codec:" but aren't in normalized_tags)
        for tag_id in $(echo "${series_tags}" | jq --raw-output '.[]'); do
            local tag_label
            tag_label=$(echo "${existing_tags}" | jq --raw-output ".[] | select(.id == ${tag_id}) | .label")
            if [[ "${tag_label}" == codec:* ]]; then
                local should_keep=false
                for keep_tag in "${normalized_tags[@]}"; do
                    if [[ "${tag_label}" == "${keep_tag}" ]]; then
                        should_keep=true
                        break
                    fi
                done
                if [[ "${should_keep}" == "false" ]]; then
                    tags_to_remove+=("$tag_id")
                fi
            fi
        done

        # Apply changes if needed
        if [[ ${#tags_to_add[@]} -gt 0 || ${#tags_to_remove[@]} -gt 0 ]]; then
            local updated_series_data="$orig_series_data"

            if [[ ${#tags_to_add[@]} -gt 0 ]]; then
                updated_series_data=$(echo "${updated_series_data}" | jq --argjson add_tags "$(printf '%s\n' "${tags_to_add[@]}" | jq --raw-input . | jq --slurp 'map(tonumber)')" '
                    .tags = (.tags + $add_tags | unique)
                ')
            fi

            if [[ ${#tags_to_remove[@]} -gt 0 ]]; then
                updated_series_data=$(echo "${updated_series_data}" | jq --argjson remove_tags "$(printf '%s\n' "${tags_to_remove[@]}" | jq --raw-input . | jq --slurp 'map(tonumber)')" '
                    .tags |= map(select(. as $tag | $remove_tags | index($tag) | not))
                ')
            fi

            echo "[${series_count}/${total_series}] Updating ${series_title} (Tags: [${normalized_tags[*]}])"
            "${curl_cmd[@]}" --request PUT --header "Content-Type: application/json" --data "${updated_series_data}" "${url}/api/v3/series" &> /dev/null
        fi

        ((series_count++))
    done

    echo "Completed ${instance_name}"
}

# Process a Radarr instance
process_radarr() {
    local url=$1
    local api_key=$2
    local instance_name=$3

    echo "=== Processing Radarr: ${instance_name} ==="

    local curl_cmd=("curl" "-fsSL" "--header" "X-Api-Key: ${api_key}")

    # Cache existing tags
    local existing_tags
    existing_tags=$("${curl_cmd[@]}" "${url}/api/v3/tag")

    # Get all movies with files
    local movie_list
    movie_list=$("${curl_cmd[@]}" "${url}/api/v3/movie" | jq --compact-output '[.[] | select(.hasFile == true)] | sort_by(.title)')
    local total_movies
    total_movies=$(echo "${movie_list}" | jq 'length')

    echo "Found ${total_movies} movies with files"

    local movie_count=1
    for movie in $(echo "${movie_list}" | jq --raw-output '.[] | @base64'); do
        local movie_id movie_title
        movie_id=$(_jq "${movie}" ".id")
        movie_title=$(_jq "${movie}" ".title")

        # Get movie file info
        local movie_file
        movie_file=$("${curl_cmd[@]}" "${url}/api/v3/moviefile?movieId=${movie_id}")
        local codec
        codec=$(echo "${movie_file}" | jq --raw-output '.[0].mediaInfo.videoCodec // "other"')

        # Normalize codec to tag
        local normalized_tag
        normalized_tag=$(normalize_codec "$codec")

        # Get current movie data
        local orig_movie_data
        orig_movie_data=$("${curl_cmd[@]}" "${url}/api/v3/movie/${movie_id}")
        local movie_tags
        movie_tags=$(echo "$orig_movie_data" | jq --raw-output '.tags')

        # Get or create tag ID
        local tag_id
        tag_id=$(echo "${existing_tags}" | jq --raw-output ".[] | select(.label == \"${normalized_tag}\") | .id")

        if [[ -z "${tag_id}" ]]; then
            # Create tag
            local new_tag
            new_tag=$("${curl_cmd[@]}" -X POST -H "Content-Type: application/json" -d "{\"label\": \"${normalized_tag}\"}" "${url}/api/v3/tag")
            tag_id=$(echo "${new_tag}" | jq --raw-output '.id')
            existing_tags=$(echo "${existing_tags}" | jq ". += [{\"id\": ${tag_id}, \"label\": \"${normalized_tag}\"}]")
        fi

        # Track tags to add/remove
        local tags_to_add=()
        local tags_to_remove=()

        if ! echo "${movie_tags}" | jq --exit-status ". | index(${tag_id})" &> /dev/null; then
            tags_to_add+=("$tag_id")
        fi

        # Identify codec tags to remove
        for existing_tag_id in $(echo "${movie_tags}" | jq --raw-output '.[]'); do
            local tag_label
            tag_label=$(echo "${existing_tags}" | jq --raw-output ".[] | select(.id == ${existing_tag_id}) | .label")
            if [[ "${tag_label}" == codec:* && "${tag_label}" != "${normalized_tag}" ]]; then
                tags_to_remove+=("$existing_tag_id")
            fi
        done

        # Apply changes if needed
        if [[ ${#tags_to_add[@]} -gt 0 || ${#tags_to_remove[@]} -gt 0 ]]; then
            local updated_movie_data="$orig_movie_data"

            if [[ ${#tags_to_add[@]} -gt 0 ]]; then
                updated_movie_data=$(echo "${updated_movie_data}" | jq --argjson add_tags "$(printf '%s\n' "${tags_to_add[@]}" | jq --raw-input . | jq --slurp 'map(tonumber)')" '
                    .tags = (.tags + $add_tags | unique)
                ')
            fi

            if [[ ${#tags_to_remove[@]} -gt 0 ]]; then
                updated_movie_data=$(echo "${updated_movie_data}" | jq --argjson remove_tags "$(printf '%s\n' "${tags_to_remove[@]}" | jq --raw-input . | jq --slurp 'map(tonumber)')" '
                    .tags |= map(select(. as $tag | $remove_tags | index($tag) | not))
                ')
            fi

            echo "[${movie_count}/${total_movies}] Updating ${movie_title} (Tag: ${normalized_tag})"
            "${curl_cmd[@]}" --request PUT --header "Content-Type: application/json" --data "${updated_movie_data}" "${url}/api/v3/movie/${movie_id}" &> /dev/null
        fi

        ((movie_count++))
    done

    echo "Completed ${instance_name}"
}

# Main
echo "Starting codec tagger at $(date)"

# Process Sonarr instances
process_sonarr "${SONARR_URL}" "${SONARR_API_KEY}" "Sonarr"
process_sonarr "${SONARR_UHD_URL}" "${SONARR_UHD_API_KEY}" "Sonarr-UHD"
process_sonarr "${SONARR_FOREIGN_URL}" "${SONARR_FOREIGN_API_KEY}" "Sonarr-Foreign"

# Process Radarr instances
process_radarr "${RADARR_URL}" "${RADARR_API_KEY}" "Radarr"
process_radarr "${RADARR_UHD_URL}" "${RADARR_UHD_API_KEY}" "Radarr-UHD"

echo "Codec tagger completed at $(date)"
