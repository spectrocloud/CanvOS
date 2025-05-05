#!/bin/bash

# Exit immediately if a command exits with a non-zero status.
set -ex
# Treat unset variables as an error when substituting.
set -u
# Pipefail: the return value of a pipeline is the status of the last command to exit with a non-zero status,
# or zero if no command exited with a non-zero status
set -o pipefail

# --- Configuration and Setup ---

ARG_FILE=".arg"

# source if .arg exists
if [[ -f "$ARG_FILE" ]]; then
  source ".arg"
fi

# Function for logging messages
log() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') - $*"
}

log "Starting RAW to AMI creation process."

# --- Dependency Checks ---

log "Checking dependencies..."
# Check for essential commands
for cmd in curl jq aws; do
  if ! command -v "$cmd" &>/dev/null; then
    log "Error: Required command '$cmd' not found." >&2
    log "Please install '$cmd' and try again." >&2
    exit 1
    # fi
  fi
done
log "All dependencies found."

# --- Variable Validation ---
RAW_FILE=$1
log "Validating configuration..."
required_vars=(REGION S3_BUCKET S3_KEY RAW_FILE)
missing_vars=()
for var in "${required_vars[@]}"; do
  # if S3_KEY is not set, set it to the RAW_FILE name
  if [[ "$var" == "S3_KEY" && -z "${!var-}" ]]; then
    S3_KEY=$(basename "$RAW_FILE")
  fi
  if [[ -z "${!var-}" ]]; then # Check if var is unset or empty
    missing_vars+=("$var")
  fi
done

# Validate AWS Credentials - Prefer AWS_PROFILE
if [[ -z "${AWS_PROFILE-}" ]]; then
  log "AWS_PROFILE not set. Checking for AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY..."
  unset AWS_PROFILE
  if [[ -z "${AWS_ACCESS_KEY_ID-}" || -z "${AWS_SECRET_ACCESS_KEY-}" ]]; then
    missing_vars+=("AWS_PROFILE or (AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY)")
  else
    log "Warning: Using AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY from '$ARG_FILE'. Using AWS_PROFILE is recommended for production."
    export AWS_ACCESS_KEY_ID="$AWS_ACCESS_KEY_ID"
    export AWS_SECRET_ACCESS_KEY="$AWS_SECRET_ACCESS_KEY"
    # Consider unsetting AWS_SESSION_TOKEN if sourced, unless explicitly needed and managed.
    # The script had a hardcoded token commented out, ensure no active tokens are sourced insecurely.
    if [[ -n "${AWS_SESSION_TOKEN-}" ]]; then
      export AWS_SESSION_TOKEN="$AWS_SESSION_TOKEN"
      log "Using AWS_SESSION_TOKEN."
    fi
  fi
elif [[ -n "${AWS_ACCESS_KEY_ID-}" || -n "${AWS_SECRET_ACCESS_KEY-}" ]]; then
  log "Warning: AWS_PROFILE is set, but AWS_ACCESS_KEY_ID/AWS_SECRET_ACCESS_KEY are also present in '$ARG_FILE'. AWS_PROFILE will be used."
  # Unset keys if profile is preferred to avoid confusion
  unset AWS_ACCESS_KEY_ID
  unset AWS_SECRET_ACCESS_KEY
  unset AWS_SESSION_TOKEN
fi

if [[ ${#missing_vars[@]} -ne 0 ]]; then
  log "Error: Missing required configuration variables in '$ARG_FILE': ${missing_vars[*]}" >&2
  exit 1
fi

# Validate RAW_FILE existence
if [[ ! -f "$RAW_FILE" ]]; then
  log "Error: RAW file '$RAW_FILE' not found." >&2
  exit 1
fi

log "Configuration validated successfully."

# --- AWS Helper Functions ---

# Execute AWS CLI command with region and profile if set
# Usage: AWS <service> <command> [options...]
AWS() {
  local args=("$@")
  local cmd=("aws" "--region" "$REGION")
  if [[ -n "${AWS_PROFILE-}" ]]; then
    cmd+=("--profile" "$AWS_PROFILE")
  fi
  "${cmd[@]}" "${args[@]}"
}

# Execute AWS CLI command without region, but with profile if set
# Usage: AWSNR <service> <command> [options...]
AWSNR() {
  local args=("$@")
  local cmd=("aws")
  if [[ -n "${AWS_PROFILE-}" ]]; then
    cmd+=("--profile" "$AWS_PROFILE")
  fi
  "${cmd[@]}" "${args[@]}"
}

# Wait for an EC2 snapshot import task to complete.
# Usage: waitForSnapshotCompletion <task_id>
# Returns: Snapshot ID on success, exits on failure.
waitForSnapshotCompletion() {
  local taskID="$1"
  local status
  local snapshot_id

  log "Waiting for snapshot import task '$taskID' to complete..."
  while true; do
    # Query status and handle potential errors if task doesn't exist immediately
    status=$(AWS ec2 describe-import-snapshot-tasks --import-task-ids "$taskID" --query 'ImportSnapshotTasks[0].SnapshotTaskDetail.Status' --output text 2>/dev/null || echo "error")

    if [[ "$status" == "completed" ]]; then
      snapshot_id=$(AWS ec2 describe-import-snapshot-tasks --import-task-ids "$taskID" --query 'ImportSnapshotTasks[0].SnapshotTaskDetail.SnapshotId' --output text)
      log "Snapshot import task '$taskID' completed. Snapshot ID: $snapshot_id"
      echo "$snapshot_id" # Return snapshot ID
      break
    elif [[ "$status" == "deleted" || "$status" == "cancelling" || "$status" == "cancelled" ]]; then
      log "Error: Snapshot import task '$taskID' failed with status: $status" >&2
      # Optionally, get more detailed error message if available
      local status_message
      status_message=$(AWS ec2 describe-import-snapshot-tasks --import-task-ids "$taskID" --query 'ImportSnapshotTasks[0].SnapshotTaskDetail.StatusMessage' --output text 2>/dev/null)
      if [[ -n "$status_message" ]]; then
        log "Status Message: $status_message" >&2
      fi
      exit 1
    elif [[ "$status" == "error" ]]; then
      log "Error querying status for task '$taskID'. Retrying..." >&2
      sleep 15 # Wait longer if query failed
    else
      log "Snapshot import task '$taskID' status: $status. Waiting..."
      sleep 30
    fi
  done
}

# Wait for an EC2 AMI to become available.
# Usage: waitAMI <ami_id> <region>
waitAMI() {
  local amiID="$1"
  local ami_region="$2" # Use a different name to avoid conflict with global REGION
  local status

  log "[$ami_region] Waiting for AMI '$amiID' to become available..."
  while true; do
    status=$(AWSNR ec2 describe-images --region "$ami_region" --image-ids "$amiID" --query "Images[0].State" --output text 2>/dev/null || echo "error")

    if [[ "$status" == "available" ]]; then
      log "[$ami_region] AMI '$amiID' is now available."
      break
    elif [[ "$status" == "pending" ]]; then
      log "[$ami_region] AMI '$amiID' is pending. Waiting..."
      sleep 15 # Increased wait time
    elif [[ "$status" == "error" ]]; then
      log "[$ami_region] Error querying status for AMI '$amiID'. Retrying..." >&2
      sleep 15
    elif [[ "$status" == "failed" ]]; then
      log "[$ami_region] Error: AMI '$amiID' entered failed state." >&2
      # Optionally retrieve reason for failure
      local state_reason
      state_reason=$(AWSNR ec2 describe-images --region "$ami_region" --image-ids "$amiID" --query "Images[0].StateReason.Message" --output text 2>/dev/null)
      if [[ -n "$state_reason" ]]; then
        log "[$ami_region] Failure Reason: $state_reason" >&2
      fi
      exit 1
    else
      # Handle other potential states explicitly if needed (e.g., deregistered)
      log "[$ami_region] Warning: AMI '$amiID' is in an unexpected state: $status." >&2
      sleep 30
    fi
  done
}

# Check if an AMI with the given name exists, otherwise create it from the snapshot.
# Usage: checkImageExistsOrCreate <image_name> <snapshot_id>
checkImageExistsOrCreate() {
  local imageName="$1"
  local snapshotID="$2"
  local imageID
  local description="AMI for ${imageName} created from snapshot ${snapshotID}" # More descriptive

  log "Checking if image '$imageName' exists..."
  # Use filters robustly, checking owner might be necessary depending on account setup
  imageID=$(AWS ec2 describe-images --filters "Name=name,Values=$imageName" "Name=state,Values=available,pending" --query 'Images[?State!=`deregistered`]|[0].ImageId' --output text)

  if [[ "$imageID" != "None" && -n "$imageID" ]]; then
    log "Image '$imageName' already exists with ID: $imageID. Checking state..."
    waitAMI "$imageID" "$REGION" # Ensure existing AMI is actually available
  else
    log "Image '$imageName' does not exist or is not available. Creating from snapshot '$snapshotID'..."

    # Construct BlockDeviceMappings using jq for better readability and safety
    local block_device_mappings
    block_device_mappings=$(jq -n --arg snapshot_id "$snapshotID" '[{DeviceName: "/dev/xvda", Ebs: {SnapshotId: $snapshot_id}}]')

    # Register the image
    imageID=$(AWS ec2 register-image \
      --name "$imageName" \
      --description "$description" \
      --architecture x86_64 \
      --root-device-name /dev/xvda \
      --block-device-mappings "[{\"DeviceName\":\"/dev/xvda\",\"Ebs\":{\"SnapshotId\":\"$snapshotID\"}}]" \
      --virtualization-type hvm \
      --boot-mode uefi \
      --ena-support \
      --query 'ImageId' \
      --output text)

    if [[ -z "$imageID" ]]; then
      log "Error: Failed to register image '$imageName'." >&2
      exit 1
    fi
    log "Image '$imageName' registration initiated with Image ID: $imageID."

    # Add tags immediately after registration starts (optional, can be done after available)
    # log "Tagging image $imageID..."
    # AWS ec2 create-tags --resources "$imageID" --tags Key=Name,Value="$imageName" Key=Project,Value=Kairos # Add relevant tags
    # Check tag creation success?

    # Wait for the newly created AMI to be available
    waitAMI "$imageID" "$REGION"
  fi
  # Return the final, available image ID
  echo "$imageID"
}

# Import a RAW file from S3 as an EC2 snapshot.
# Checks if a snapshot with a specific tag already exists.
# Usage: importAsSnapshot <s3_key>
# Returns: Snapshot ID on success, exits on failure.
importAsSnapshot() {
  local s3Key="$1"
  local snapshotID
  local taskID
  local snapshot_tag_key="SourceS3Key" # Using a specific tag for idempotency check

  # log "Checking for existing snapshot tagged with '$snapshot_tag_key=$s3Key'..."
  # snapshotID=$(AWS ec2 describe-snapshots --filters "Name=tag:$snapshot_tag_key,Values=$s3Key" --query "Snapshots[0].SnapshotId" --output text)
  # if [[ "$snapshotID" != "None" && -n "$snapshotID" ]]; then
  #   log "Snapshot '$snapshotID' already exists for S3 key '$s3Key'."
  #   echo "$snapshotID"
  #   return 0 # Indicate success, snapshot already exists
  # fi

  # log "No existing snapshot found. Importing '$s3Key' from bucket '$S3_BUCKET'..."

  # Use jq to create the disk container JSON safely
  local disk_container_json
  disk_container_json=$(jq -n --arg desc "Snapshot for $s3Key" --arg bucket "$S3_BUCKET" --arg key "$s3Key" '{
    Description: $desc,
    Format: "RAW",
    UserBucket: { S3Bucket: $bucket, S3Key: $key }
  }')

  # Initiate the snapshot import task
  taskID=$(AWS ec2 import-snapshot --description "Import $s3Key" \
    --disk-container "$disk_container_json" \
    --tag-specifications 'ResourceType=import-snapshot-task,Tags=[{Key=Name,Value='"Import-$s3Key"'}]' \
    --query 'ImportTaskId' --output text)

  if [[ -z "$taskID" ]]; then
    log "Error: Failed to initiate snapshot import for '$s3Key'." >&2
    exit 1
  fi
  log "Snapshot import task started with ID: $taskID"

  # Wait for completion and get the Snapshot ID
  snapshotID=$(waitForSnapshotCompletion "$taskID" | tail -1 | tee /dev/fd/2)
  if [[ -z "$snapshotID" ]]; then
    log "Error: waitForSnapshotCompletion did not return a Snapshot ID for task '$taskID'." >&2
    exit 1
  fi

  # log "Adding tag '$snapshot_tag_key=$s3Key' to snapshot '$snapshotID'..."
  # if AWS ec2 create-tags --resources "$snapshotID" --tags Key="$snapshot_tag_key",Value="$s3Key" Key=Name,Value="$s3Key"; then
  #   log "Successfully tagged snapshot '$snapshotID'."
  # else
  #   log "Warning: Failed to tag snapshot '$snapshotID'. Manual tagging might be required." >&2
  #   # Decide if this is a critical failure or just a warning
  #   # exit 1
  # fi

  echo "$snapshotID" # Return the newly created snapshot ID
}

# --- Main Execution ---
# check if object exists in s3
OBJECT_EXISTS=false
if AWS s3 ls "s3://$S3_BUCKET/$S3_KEY" > /dev/null 2>&1; then
  log "Object '$S3_KEY' already exists in s3://$S3_BUCKET/$S3_KEY."
  OBJECT_EXISTS=true
fi

# if object does not exist, upload it
if ! $OBJECT_EXISTS; then
  log "Uploading '$RAW_FILE' to s3://$S3_BUCKET/$S3_KEY..."
  if AWS s3 cp "$RAW_FILE" "s3://$S3_BUCKET/$S3_KEY"; then
    log "Successfully uploaded '$RAW_FILE' to S3."
  else
    log "Error: Failed to upload '$RAW_FILE' to s3://$S3_BUCKET/$S3_KEY." >&2
    exit 1
  fi
fi

# Step 2: Import S3 object as Snapshot
log "Importing S3 object 's3://$S3_BUCKET/$S3_KEY' as EC2 snapshot..."
snapshotID=$(importAsSnapshot "$S3_KEY" | tail -1)
if [[ -z "$snapshotID" ]]; then
  log "Error: Failed to import snapshot from S3 object '$S3_KEY'." >&2
  exit 1
fi
log "Snapshot import process completed. Snapshot ID: $snapshotID"

# Step 3: Create (or find) AMI from Snapshot
# Use S3_KEY or a dedicated AMI name variable for the image name
ami_name="${AMI_NAME:-$S3_KEY}" # Use AMI_NAME from .arg if set, otherwise default to S3_KEY
log "Creating/Verifying AMI '$ami_name' from snapshot '$snapshotID'..."
final_ami_id=$(checkImageExistsOrCreate "$ami_name" "$snapshotID")
if [[ -z "$final_ami_id" ]]; then
  log "Error: Failed to create or verify AMI '$ami_name'." >&2
  exit 1
fi

log "Process completed successfully!"
log "Final AMI ID: $final_ami_id"
log "AMI Name: $ami_name"
log "Region: $REGION"

# Optional: Output AMI ID for automation
# echo "$final_ami_id" > /path/to/output/ami_id.txt

exit 0
