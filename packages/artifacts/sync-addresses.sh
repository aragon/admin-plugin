#!/usr/bin/env bash

# Sync the addresses from osx-commons/configs

usage() {
  echo "Usage: $(basename "$0") <source_directory> <destination_file>" >&2
  echo "  <source_directory>: Path to the directory containing the source JSON files." >&2
  echo "  <destination_file>: Path to the addresses.json file to be created/overwritten." >&2
}

if [[ $# -ne 2 ]]; then
  echo "Error: Expected 2 arguments." >&2
  usage
  exit 1
fi

SOURCE_DIR="$1"
DEST_FILE="$2"

UNSUPPORTED_NETWORKS=(
    "goerli"
    "baseGoerli"
    "devSepolia"
)

# Checks

if [[ ! -d "$SOURCE_DIR" ]]; then
    echo "Error: Source directory '$SOURCE_DIR' not found." >&2
    exit 1
fi

if ! command -v jq &> /dev/null; then
    echo "Error: 'jq' command not found. Please install jq." >&2
    exit 1
fi

if [ "$SOURCE_DIR" == "$(dirname $DEST_FILE)" ]; then
    echo "Error: The destination file cannot be in the same path as the destination file" >&2
    exit 1
fi

# Helpers

containsElement () {
  local seeking=$1; shift
  local in=1 # Not found
  for element; do
    if [[ "$element" == "$seeking" ]]; then
      in=0 # Found
      break
    fi
  done
  return $in
}

networkAlias () {
    local network="$1"

    if [[ "$network" == "baseMainnet" ]]; then printf "base"
    elif [[ "$network" == "bscMainnet" ]]; then printf "bsc"
    elif [[ "$network" == "modeMainnet" ]]; then printf "mode"
    elif [[ "$network" == "zksyncMainnet" ]]; then printf "zksync"
    else printf "$network"
    fi
}

# Ready

echo "Processing $SOURCE_DIR"

# Create a temporary file to store intermediate JSON structures
# Each line in this file will be a JSON object like: {"pluginRepo": {"network_name": "value"}}
TEMP_MERGE_FILE=$(mktemp)

# Clean the temp file when the script exits
trap 'rm -f "$TEMP_MERGE_FILE"' EXIT

# List source address files
find "$SOURCE_DIR" -maxdepth 1 -name '*.json' | sort | while read source_file; do
    filename=$(basename "$source_file")
    network="${filename%.json}"

    if containsElement "$network" "${UNSUPPORTED_NETWORKS[@]}"; then
        echo "Skipping deprecated network: $network"
        continue
    fi

    echo "Processing $filename:"

    # Extract the address
    value=$(jq -er '.["v1.4.0"].AdminRepoProxy.address // .["v1.3.0"].AdminRepoProxy.address // empty' "$source_file")
    jq_exit_code=$?

    if [[ $jq_exit_code -ne 0 || "$value" == "null" ]]; then
        echo "  Warning: Could not find 'AdminRepoProxy' under 'v1.4.0' or 'v1.3.0' in '$filename'. Skipping." >&2
        continue
    fi

    echo "  Found $value"
    jq -n --arg network "$(networkAlias $network)" --arg value "$value" \
        '{pluginRepo: {($network): $value}}' >> "$TEMP_MERGE_FILE"
done

echo "Merging addresses..."
jq -s 'map(.pluginRepo) | add | {pluginRepo: .}' "$TEMP_MERGE_FILE" > "$DEST_FILE"


if [[ $? -ne 0 ]]; then
    echo "Error: Failed to merge the values into '$DEST_FILE'" >&2
    exit 1
fi

echo "Addresses written to '$DEST_FILE'"
exit 0
