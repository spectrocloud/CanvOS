#!/bin/bash

# Define the directory to be listed; default to secure-boot if none provided
directory="${1:-secure-boot}"

# Print the root directory
echo "$(basename "$(realpath "$directory")")/"

# Function to generate tree view and add comments to specific files
generate_tree() {
    find "$directory" -mindepth 1 -print | sort | sed 's|[^/]*/|   |g' | awk '
    {
        # Replace leading spaces with a combination of pipes and dashes to simulate tree branches
        gsub(/   /, "|   ", $0);
        sub(/\|   $/, "`---", $0);
        print;
    }'
}

# Function to add comments to specific files
function add_comment {
    while read -r line; do
        # Determine filename from the indented line
        filename="${line##* }" # Extract the last part after space, which should be the file name
        case "$filename" in
            "PK.auth"*)
                echo "$line <-- Platform Key"
                ;;
            "KEK.auth"*)
                echo "$line <-- Key Exchange Key"
                ;;
            "db.auth"*)
                echo "$line <-- Signature Database"
                ;;
            "dbx.esl"*)
                echo "$line <-- Forbidden Signatures Database"
                ;;
            "PK.key"*)
                echo "$line <-- Remove me from this directory and keep me safe"
                ;;
            "KEK.key"*)
                echo "$line <-- Remove me from this directory and keep me safe"
                ;;
            *)
                echo "$line"
                ;;
        esac
    done
}

# Generate the tree and pipe it to add comments
generate_tree | add_comment
