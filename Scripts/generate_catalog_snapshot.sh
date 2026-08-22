#!/bin/zsh

set -euo pipefail

script_directory="${0:A:h}"
project_directory="${script_directory:h}"
output_file="${1:-${project_directory}/TallyDex/Resources/catalog-en.json}"
working_directory="$(mktemp -d)"
snapshot_file="${working_directory}/catalog-en.json"
next_snapshot_file="${working_directory}/catalog-en-next.json"
series_index_file="${working_directory}/series.json"

cleanup() {
    rm -rf "${working_directory}"
}
trap cleanup EXIT

curl --fail --silent --show-error --retry 3 \
    "https://api.tcgdex.net/v2/en/series" \
    --output "${series_index_file}"

generated_at="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
jq --null-input --arg generatedAt "${generated_at}" \
    '{schemaVersion: 1, generatedAt: $generatedAt, language: "en", series: []}' \
    > "${snapshot_file}"

while IFS= read -r series_id; do
    detail_file="${working_directory}/${series_id}.json"
    curl --fail --silent --show-error --retry 3 \
        "https://api.tcgdex.net/v2/en/series/${series_id}" \
        --output "${detail_file}"

    jq --slurpfile detail "${detail_file}" \
        '.series += [($detail[0] | {
            series: {
                id: .id,
                name: .name,
                logoURL: (.logo // null)
            },
            sets: [((.sets // []) | reverse)[] | {
                id: .id,
                seriesID: $detail[0].id,
                name: .name,
                logoURL: (.logo // null),
                symbolURL: (.symbol // null),
                officialCardCount: .cardCount.official,
                totalCardCount: (.cardCount.total // .cardCount.official),
                releaseDate: null
            }]
        })]' \
        "${snapshot_file}" > "${next_snapshot_file}"
    mv "${next_snapshot_file}" "${snapshot_file}"
done < <(jq -r '[.[] | select(.id != "tcgp") | .id] | reverse[]' "${series_index_file}")

mkdir -p "${output_file:h}"
mv "${snapshot_file}" "${output_file}"

series_count="$(jq '.series | length' "${output_file}")"
set_count="$(jq '[.series[].sets[]] | length' "${output_file}")"
echo "Wrote ${series_count} series and ${set_count} sets to ${output_file}"
