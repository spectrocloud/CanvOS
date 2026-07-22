#!/bin/bash
# Uncomment the line below to enable debug mode
# set -x

function build_with_proxy() {
    export HTTP_PROXY=$HTTP_PROXY
    export HTTPS_PROXY=$HTTPS_PROXY
    gitconfig=$(envsubst <.gitconfig.template | base64 | tr -d '\n')
    # cleanup any previous earthly-buildkitd
    if [ "$(docker container inspect -f '{{.State.Running}}' earthly-buildkitd)" = "true" ]; then
        docker stop earthly-buildkitd
    fi
    
    # Check if Docker config file exists
    DOCKER_CONFIG_MOUNT=""
    if [ -f "$HOME/.docker/config.json" ]; then
        DOCKER_CONFIG_MOUNT="-v$HOME/.docker/config.json:/root/.docker/config.json"
    fi
    
    # start earthly buildkitd
    docker run -d --privileged \
        --name earthly-buildkitd \
        ${DOCKER_CONFIG_MOUNT:+"$DOCKER_CONFIG_MOUNT"} \
        -v /var/run/docker.sock:/var/run/docker.sock \
        --rm -t \
        -e GLOBAL_CONFIG="$global_config" \
        -e BUILDKIT_TCP_TRANSPORT_ENABLED=true \
        -e http_proxy="$HTTP_PROXY" \
        -e https_proxy="$HTTPS_PROXY" \
        -e HTTPS_PROXY="$HTTPS_PROXY" \
        -e HTTP_PROXY="$HTTP_PROXY" \
        -e NO_PROXY="$NO_PROXY" \
        -e no_proxy="$NO_PROXY" \
        -e EARTHLY_GIT_CONFIG="$gitconfig" \
        -v "$(pwd)/certs:/usr/local/share/ca-certificates:ro" \
        -v earthly-tmp:/tmp/earthly:rw \
        -p 8372:8372 \
        "$SPECTRO_PUB_REPO"/third-party/edge/earthly/buildkitd:"$EARTHLY_VERSION"
    # Update the CA certificates in the container
    docker exec -it earthly-buildkitd update-ca-certificates

    # Run Earthly in Docker to create artifacts  Variables are passed from the .arg file
    docker run --privileged \
        ${DOCKER_CONFIG_MOUNT:+"$DOCKER_CONFIG_MOUNT"} \
        -v /var/run/docker.sock:/var/run/docker.sock \
        --rm --env EARTHLY_BUILD_ARGS -t \
        -e GLOBAL_CONFIG="$global_config" \
        -e EARTHLY_BUILDKIT_HOST=tcp://0.0.0.0:8372 \
        -e BUILDKIT_TLS_ENABLED=false \
        -e http_proxy="$HTTP_PROXY" \
        -e https_proxy="$HTTPS_PROXY" \
        -e HTTPS_PROXY="$HTTPS_PROXY" \
        -e HTTP_PROXY="$HTTP_PROXY" \
        -e NO_PROXY="$NO_PROXY" \
        -e no_proxy="$NO_PROXY" \
        -v "$(pwd)":/workspace \
        -v "$(pwd)/certs:/usr/local/share/ca-certificates:ro" \
        --entrypoint /workspace/earthly-entrypoint.sh \
        "$SPECTRO_PUB_REPO"/third-party/edge/earthly/earthly:"$EARTHLY_VERSION" --allow-privileged "$@"
}

function build_without_proxy() {
    # Check if Docker config file exists
    DOCKER_CONFIG_MOUNT=""
    if [ -f "$HOME/.docker/config.json" ]; then
        DOCKER_CONFIG_MOUNT="-v$HOME/.docker/config.json:/root/.docker/config.json"
    fi
    
    # Run Earthly in Docker to create artifacts  Variables are passed from the .arg file
    docker run --privileged ${DOCKER_CONFIG_MOUNT:+"$DOCKER_CONFIG_MOUNT"} -v /var/run/docker.sock:/var/run/docker.sock --rm --env EARTHLY_BUILD_ARGS -t -e GLOBAL_CONFIG="$global_config" -v "$(pwd)":/workspace "$SPECTRO_PUB_REPO"/third-party/edge/earthly/earthly:"$EARTHLY_VERSION" --allow-privileged "$@"
}

function print_os_pack() {
    # Print the output for use in Palette Profile.
    echo -e '##########################################################################################################'
    echo -e '\nPASTE THE CONTENT BELOW INTO YOUR CLUSTER PROFILE IN PALETTE REPLACING ALL THE CONTENTS IN THE PROFILE\n'
    echo -e '##########################################################################################################'
    echo -e '\n'
    echo -e 'pack:'
    echo -e '  content:'
    echo -e '    images:'
    echo -e '      - image: "{{.spectro.pack.edge-native-byoi.options.system.uri}}"'
    echo -e '  # Below config is default value, please uncomment if you want to modify default values'
    echo -e '  #drain:'
    echo -e '    #cordon: true'
    echo -e '    #timeout: 60 # The length of time to wait before giving up, zero means infinite'
    echo -e '    #gracePeriod: 60 # Period of time in seconds given to each pod to terminate gracefully. If negative, the default value specified in the pod will be used'
    echo -e '    #ignoreDaemonSets: true'
    echo -e '    #deleteLocalData: true # Continue even if there are pods using emptyDir (local data that will be deleted when the node is drained)'
    echo -e '    #force: true # Continue even if there are pods that do not declare a controller'
    echo -e '    #disableEviction: false # Force drain to use delete, even if eviction is supported. This will bypass checking PodDisruptionBudgets, use with caution'
    echo -e '    #skipWaitForDeleteTimeout: 60 # If pod DeletionTimestamp older than N seconds, skip waiting for the pod. Seconds must be greater than 0 to skip.'
    echo -e 'options:'
    echo -e '  system.uri: "{{ .spectro.pack.edge-native-byoi.options.system.registry }}/{{ .spectro.pack.edge-native-byoi.options.system.repo }}:{{ .spectro.pack.edge-native-byoi.options.system.k8sDistribution }}-{{ .spectro.system.kubernetes.version }}-{{ .spectro.pack.edge-native-byoi.options.system.peVersion }}-{{ .spectro.pack.edge-native-byoi.options.system.customTag }}"'
    echo -e '\n'
    echo -e "  system.registry: $IMAGE_REGISTRY"
    echo -e "  system.repo: $IMAGE_REPO"
    echo -e "  system.k8sDistribution: $K8S_DISTRIBUTION"
    echo -e "  system.osName: $OS_DISTRIBUTION"
    echo -e "  system.peVersion: $PE_VERSION"
    echo -e "  system.customTag: $CUSTOM_TAG"
    echo -e "  system.osVersion: $OS_VERSION"
}

global_config="{disable_analytics: true}"
PE_VERSION=$(git describe --abbrev=0 --tags)
SPECTRO_PUB_REPO=us-docker.pkg.dev/palette-images
EARTHLY_VERSION=v0.8.15
source .arg

# Workaround to support deprecated field PROXY_CERT_PATH
if [ -n "$PROXY_CERT_PATH" ]; then
    echo "PROXY_CERT_PATH is deprecated. Please place your certificates in the certs directory."
    echo "Copying the certificates from $PROXY_CERT_PATH to certs/"
    cp $PROXY_CERT_PATH certs/
fi

ALPINE_IMG=$SPECTRO_PUB_REPO/edge/canvos/alpine:3.20
### Verify Dependencies
# Check if Docker is installed
if command -v docker >/dev/null 2>&1; then
    echo "version: $(docker -v)"
else
    echo "Docker not found.  Please use the guide for your platform located https://docs.docker.com/engine/install/ to install Docker."
fi
# Check if the current user has permission to run privileged containers
if ! docker run --rm --privileged "$ALPINE_IMG" sh -c 'echo "Privileged container test"' &>/dev/null; then
    echo "Privileged containers are not allowed for the current user."
    exit 1
fi

# Special handling for MAAS image build: build kairos-raw-image first, then run build-kairos-maas.sh locally
if [[ "$1" == "+maas-image" ]]; then
    # Check that OS_DISTRIBUTION is set to ubuntu (MAAS only supports Ubuntu)
    if [ -z "$OS_DISTRIBUTION" ]; then
        echo "Error: OS_DISTRIBUTION is not set. Please set OS_DISTRIBUTION=ubuntu in .arg file or via environment variable." >&2
        exit 1
    fi
    if [ "$OS_DISTRIBUTION" != "ubuntu" ]; then
        echo "Error: MAAS image build only supports Ubuntu. Current OS_DISTRIBUTION: $OS_DISTRIBUTION" >&2
        echo "Please set OS_DISTRIBUTION=ubuntu in .arg file or via environment variable." >&2
        exit 1
    fi
    echo "=== Building MAAS image: Step 1 - Generating Kairos raw image ==="
    # Build the kairos-raw-image target first with IS_MAAS=true flag
    if [ -z "$HTTP_PROXY" ] && [ -z "$HTTPS_PROXY" ] && [ -z "$(find certs -type f ! -name '.*' -print -quit)" ]; then
        build_without_proxy "+kairos-raw-image" --IS_MAAS=true
        BUILD_EXIT=$?
    else
        build_with_proxy "+kairos-raw-image" --IS_MAAS=true
        BUILD_EXIT=$?
    fi
    
    if [ $BUILD_EXIT -ne 0 ]; then
        echo "Error: Failed to build kairos-raw-image"
        exit 1
    fi
    
    # Verify the raw image was created
    KAIROS_RAW_IMAGE="build/kairos.raw"
    if [ ! -f "$KAIROS_RAW_IMAGE" ]; then
        echo "Error: Kairos raw image not found at $KAIROS_RAW_IMAGE"
        exit 1
    fi
    
    echo "=== Building MAAS image: Step 2 - Creating composite image with build-kairos-maas.sh ==="
    # Verify build-kairos-maas.sh exists
    BUILD_SCRIPT="cloudconfigs/build-kairos-maas.sh"
    if [ ! -f "$BUILD_SCRIPT" ]; then
        echo "Error: build-kairos-maas.sh not found at $BUILD_SCRIPT"
        exit 1
    fi
    
    # Verify curtin-hooks exists
    CURTIN_HOOKS="cloudconfigs/curtin-hooks"
    if [ ! -f "$CURTIN_HOOKS" ]; then
        echo "Error: curtin-hooks not found at $CURTIN_HOOKS"
        exit 1
    fi
    
    # Run the original build-kairos-maas.sh script locally
    # The script expects curtin-hooks to be in ORIG_DIR (the directory where the script is invoked from)
    # Copy curtin-hooks to the repo root (current directory) so the script can find it
    cp "$CURTIN_HOOKS" ./curtin-hooks
    
    # Check for files to add to content partition
    # The build script looks for:
    # - Content files in ./content-* or ./content directory (.zst or .tar files)
    # - SPC file as ./spc.tgz or from CLUSTERCONFIG env var
    # Note: local-ui.tar is handled directly in iso-image build, not in content partition
    HAS_FILES=false
    
    # Check for content-* directories first (e.g., content-3a456a58)
    CONTENT_DIR=""
    for dir in content-*; do
        if [ -d "$dir" ] && [ -n "$(find "$dir" -type f \( -name "*.zst" -o -name "*.tar" \) 2>/dev/null | head -1)" ]; then
            CONTENT_DIR="$dir"
            CONTENT_FILES_COUNT=$(find "$dir" -type f \( -name "*.zst" -o -name "*.tar" \) 2>/dev/null | wc -l)
            echo "Content files found in $dir: $CONTENT_FILES_COUNT file(s) (.zst or .tar)"
            HAS_FILES=true
            break
        fi
    done
    
    # Fallback to plain content directory if no content-* found
    if [ -z "$CONTENT_DIR" ] && [ -d "content" ] && [ -n "$(find content -type f \( -name "*.zst" -o -name "*.tar" \) 2>/dev/null | head -1)" ]; then
        CONTENT_FILES_COUNT=$(find content -type f \( -name "*.zst" -o -name "*.tar" \) 2>/dev/null | wc -l)
        echo "Content files found in content: $CONTENT_FILES_COUNT file(s) (.zst or .tar)"
        HAS_FILES=true
    fi
    
    # Check for SPC file
    if [ -f "spc.tgz" ]; then
        echo "SPC file found (spc.tgz), will be added to content partition"
        HAS_FILES=true
    elif [ -n "${CLUSTERCONFIG:-}" ]; then
        # CLUSTERCONFIG can be a relative or absolute path
        if [ -f "${CLUSTERCONFIG}" ]; then
            echo "SPC file found (from CLUSTERCONFIG): ${CLUSTERCONFIG}, will be added to content partition"
            HAS_FILES=true
        else
            echo "Warning: CLUSTERCONFIG is set to '${CLUSTERCONFIG}' but file not found"
        fi
    fi
    
    # Check for user-data file (edge registration config)
    # Note: user-data is handled directly in setup-recovery.sh, not via content partition
    # This ensures embedded userdata from CanvOS build is properly executed on first boot
    if [ -f "user-data" ] || [ -n "${USER_DATA:-}" ]; then
        echo "user-data file found (will be handled by setup-recovery.sh script)"
    fi
    
    # Check for EDGE_CUSTOM_CONFIG file (content signing key)
    EDGE_CUSTOM_CONFIG_FILE=""
    if [ -n "${EDGE_CUSTOM_CONFIG:-}" ]; then
        if [ -f "${EDGE_CUSTOM_CONFIG}" ]; then
            EDGE_CUSTOM_CONFIG_FILE="${EDGE_CUSTOM_CONFIG}"
            echo "EDGE_CUSTOM_CONFIG file found: ${EDGE_CUSTOM_CONFIG}, will be added to content partition"
            HAS_FILES=true
        else
            echo "Warning: EDGE_CUSTOM_CONFIG is set to '${EDGE_CUSTOM_CONFIG}' but file not found"
        fi
    fi
    
    if [ "$HAS_FILES" = "true" ]; then
        echo "Files will be added to content partition"
    else
        echo "No content files, SPC, or EDGE_CUSTOM_CONFIG found, content partition will be skipped"
    fi
    
    # Get custom MAAS image name from .arg file (sourced earlier) or use default
    MAAS_IMAGE_NAME="${MAAS_IMAGE_NAME:-kairos-ubuntu-maas}"
    # Ensure the name doesn't already have .raw or .raw.gz extension
    MAAS_IMAGE_NAME="${MAAS_IMAGE_NAME%.raw.gz}"
    MAAS_IMAGE_NAME="${MAAS_IMAGE_NAME%.raw}"
    
    # Run the build script from the repo root
    # The script will look for curtin-hooks in ORIG_DIR (which will be the repo root)
    # The script will also look for content files in ./content directory
    # Pass the custom image name as the second parameter
    # Export CLUSTERCONFIG and EDGE_CUSTOM_CONFIG to ensure they're available to the build script
    # Note: USER_DATA is not exported as it's handled directly in setup-recovery.sh from the OEM partition
    export CLUSTERCONFIG
    if [ -n "$EDGE_CUSTOM_CONFIG_FILE" ]; then
        # EDGE_CUSTOM_CONFIG_FILE may be relative or absolute, make it absolute
        if [ "${EDGE_CUSTOM_CONFIG_FILE#/}" = "$EDGE_CUSTOM_CONFIG_FILE" ]; then
            # Relative path
            export EDGE_CUSTOM_CONFIG="$(readlink -f "$EDGE_CUSTOM_CONFIG_FILE")"
        else
            # Absolute path
            export EDGE_CUSTOM_CONFIG="$EDGE_CUSTOM_CONFIG_FILE"
        fi
    fi
    bash "$BUILD_SCRIPT" "$KAIROS_RAW_IMAGE" "$MAAS_IMAGE_NAME"
    BUILD_EXIT=$?
    
    if [ $BUILD_EXIT -ne 0 ]; then
        echo "Error: build-kairos-maas.sh failed with exit code $BUILD_EXIT"
        exit 1
    fi
    
    # Verify the composite image was created (script outputs compressed .raw.gz to ORIG_DIR, which is repo root)
    COMPOSITE_IMAGE="${MAAS_IMAGE_NAME}.raw.gz"
    if [ ! -f "$COMPOSITE_IMAGE" ]; then
        echo "Error: Composite image not found at $COMPOSITE_IMAGE"
        exit 1
    fi
    
    # Move the compressed composite image to build directory for consistency
    mkdir -p build
    mv "$COMPOSITE_IMAGE" "build/$COMPOSITE_IMAGE"
    
    # Generate SHA256 checksum file for the final image
    echo "=== Generating SHA256 checksum ==="
    FINAL_IMAGE_PATH="build/$COMPOSITE_IMAGE"
    sha256sum "$FINAL_IMAGE_PATH" > "${FINAL_IMAGE_PATH}.sha256"
    echo "✅ SHA256 checksum created: ${FINAL_IMAGE_PATH}.sha256"
    
    # Clean up temporary curtin-hooks file from repo root
    rm -f ./curtin-hooks
    
    # Show final image size and checksum
    FINAL_SIZE=$(du -h "$FINAL_IMAGE_PATH" | cut -f1)
    CHECKSUM=$(cat "${FINAL_IMAGE_PATH}.sha256" | cut -d' ' -f1)
    echo "✅ MAAS composite image created and compressed successfully: $FINAL_IMAGE_PATH"
    echo "   Final size: $FINAL_SIZE"
    echo "   SHA256: $CHECKSUM"
    echo "   MAAS will automatically decompress this image during upload."
    exit 0
fi

# Normal build flow for other targets
if [ -z "$HTTP_PROXY" ] && [ -z "$HTTPS_PROXY" ] && [ -z "$(find certs -type f ! -name '.*' -print -quit)" ]; then
    build_without_proxy "$@"
else
    build_with_proxy "$@"
fi

# Verify the command was successful
if [ $? -ne 0 ]; then
    echo "An error occurred while running the command."
    exit 1
fi
# Cleanup builder helper images.
docker rmi "$SPECTRO_PUB_REPO"/third-party/edge/earthly/earthly:"$EARTHLY_VERSION"
if [ "$(docker container inspect -f '{{.State.Running}}' earthly-buildkitd)" = "true" ]; then
    docker stop earthly-buildkitd
fi
docker rmi "$SPECTRO_PUB_REPO"/third-party/edge/earthly/buildkitd:"$EARTHLY_VERSION" 2>/dev/null
docker rmi "$ALPINE_IMG"

if [[ "$1" == "+uki-genkey" ]]; then
    ./keys.sh secure-boot/
fi

# if $1 is in one of the following values, print the output for use in Palette Profile.
targets=("+build-provider-images" "+build-provider-images-fips" "+build-all-images")
for arg in "${targets[@]}"; do
    if [[ "$1" == "$arg" ]]; then
        print_os_pack
    fi
done
