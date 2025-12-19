# AWS Cloud Image Build Target - Design Document

## 1. Overview

### 1.1 Purpose
The `aws-cloud-image` target in the Earthfile is responsible for converting a CanvOS raw disk image into an Amazon Machine Image (AMI) that can be used to launch EC2 instances on AWS. This target automates the entire process from raw image creation to AMI registration in AWS.

### 1.2 Scope
This design document covers:
- The `aws-cloud-image` target implementation in the Earthfile
- The underlying `create-raw-to-ami.sh` script workflow
- Dependencies and prerequisites
- Configuration requirements
- Security considerations
- Error handling mechanisms

### 1.3 Key Features
- Automated RAW image to AMI conversion pipeline
- S3-based image upload and import
- EC2 snapshot import from S3
- AMI registration with proper configuration
- Support for AWS credentials via profile or access keys
- Idempotent operations (checks for existing resources)

## 2. Architecture

### 2.1 Target Structure

```
aws-cloud-image
├── Base Image: Ubuntu 22.04 (from +ubuntu target)
├── Dependencies: AWS CLI v2, curl, unzip, ca-certificates
├── Input Artifacts: Raw disk image from +cloud-image target
├── Script: create-raw-to-ami.sh
└── Output: AMI registered in AWS EC2
```

### 2.2 Dependency Chain

```
iso-image (with IS_CLOUD_IMAGE=true)
    ↓
cloud-image (creates raw disk image via auroraboot)
    ↓
aws-cloud-image (converts raw to AMI)
```

### 2.3 Component Relationships

```
┌─────────────────┐
│  iso-image      │
│  (installer)    │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  cloud-image    │
│  (auroraboot)   │──► Creates RAW disk image
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ aws-cloud-image │
│  (conversion)   │──► Uploads to S3
└────────┬────────┘    │
         │            │
         │            ▼
         │    ┌──────────────┐
         │    │   S3 Bucket  │
         │    └──────┬───────┘
         │           │
         │           ▼
         │    ┌──────────────┐
         │    │ EC2 Snapshot │
         │    └──────┬───────┘
         │           │
         │           ▼
         └──► ┌──────────────┐
              │  EC2 AMI     │
              └──────────────┘
```

## 3. Detailed Workflow

### 3.1 Target Execution Flow

#### Phase 1: Environment Setup
1. **Base Image**: Starts from `+ubuntu` target (Ubuntu 22.04)
2. **Package Installation**:
   - Updates package lists
   - Installs: `unzip`, `ca-certificates`, `curl`
3. **AWS CLI Installation**:
   - Downloads AWS CLI v2 from official source
   - Extracts and installs to system
   - Removes installation artifacts

#### Phase 2: Configuration
1. **Argument Processing**:
   - `REGION`: AWS region for operations
   - `S3_BUCKET`: S3 bucket for raw image storage
   - `S3_KEY`: S3 object key (defaults to raw file name if not set)
2. **Secret Injection**:
   - `AWS_PROFILE`: AWS credentials profile (preferred)
   - `AWS_ACCESS_KEY_ID`: Access key (alternative)
   - `AWS_SECRET_ACCESS_KEY`: Secret key (alternative)

#### Phase 3: Artifact Preparation
1. **Script Copy**: Copies `create-raw-to-ami.sh` to workdir
2. **Raw Image Copy**: Copies artifacts from `+cloud-image` target
   - Expects a `.raw` file in the copied artifacts
3. **Validation**: Verifies raw file exists before proceeding

#### Phase 4: AMI Creation
1. **Script Execution**: Runs `create-raw-to-ami.sh` with raw file path
2. **Process**: Script handles the complete AMI creation workflow

### 3.2 Script Workflow (`create-raw-to-ami.sh`)

#### Step 1: Configuration Loading
- Sources `.arg` file if present
- Validates required variables:
  - `REGION`
  - `S3_BUCKET`
  - `S3_KEY` (auto-generated from raw file name if not set)
  - AWS credentials (profile or access keys)

#### Step 2: Dependency Checks
- Verifies presence of: `curl`, `jq`, `aws`
- Exits with error if any dependency is missing

#### Step 3: S3 Upload
- Checks if object already exists in S3
- If not exists, uploads raw file to `s3://$S3_BUCKET/$S3_KEY`
- Uses multipart upload for large files (handled by AWS CLI)

#### Step 4: Snapshot Import
- Creates EC2 snapshot import task from S3 object
- Uses `ec2 import-snapshot` API
- Waits for import completion (polls every 30 seconds)
- Handles error states: `deleted`, `cancelling`, `cancelled`
- Returns snapshot ID upon completion

#### Step 5: AMI Registration
- Checks if AMI with given name already exists
- If exists and available, uses existing AMI
- If not exists, registers new AMI from snapshot:
  - Architecture: `x86_64`
  - Root device: `/dev/xvda`
  - Virtualization: `hvm`
  - Boot mode: `uefi`
  - ENA support: enabled
- Waits for AMI to become `available` state
- Returns final AMI ID

## 4. Inputs and Outputs

### 4.1 Required Inputs

#### Earthfile Arguments
```bash
--REGION=<aws-region>           # e.g., us-east-1
--S3_BUCKET=<bucket-name>       # S3 bucket name
--S3_KEY=<object-key>           # Optional, defaults to raw file name
```

#### Secrets (via .secret file or Earthly secrets)
```bash
AWS_PROFILE=<profile-name>      # Preferred method
# OR
AWS_ACCESS_KEY_ID=<access-key>
AWS_SECRET_ACCESS_KEY=<secret-key>
```

#### Dependencies
- `+cloud-image` target must be executed first (provides raw image)
- `cloud-images/config/user-data.yaml` must exist (used by cloud-image)

### 4.2 Outputs

#### Primary Output
- **AMI ID**: Registered AMI in specified AWS region
- **AMI Name**: Based on `AMI_NAME` variable or `S3_KEY`

#### Secondary Outputs
- **EC2 Snapshot**: Created during import process
- **S3 Object**: Raw image file stored in S3 bucket

### 4.3 Artifact Flow

```
+cloud-image
    └──> *.raw file
            └──> /workdir/*.raw
                    └──> create-raw-to-ami.sh
                            └──> S3 Upload
                                    └──> EC2 Snapshot
                                            └──> EC2 AMI
```

## 5. Configuration

### 5.1 .arg File Configuration

```bash
# AWS Cloud Image Configuration
REGION="us-east-1"
S3_BUCKET="my-canvos-images"
S3_KEY="canvos-ubuntu-22.04-k3s-v1.30.0.raw"
AMI_NAME="canvos-ubuntu-22.04-k3s-v1.30.0"  # Optional
```

### 5.2 .secret File Configuration

```bash
# Option 1: Using AWS Profile (Recommended)
AWS_PROFILE="production"

# Option 2: Using Access Keys
AWS_ACCESS_KEY_ID="AKIAIOSFODNN7EXAMPLE"
AWS_SECRET_ACCESS_KEY="wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
```

### 5.3 user-data.yaml Configuration

Located at: `cloud-images/config/user-data.yaml`

```yaml
#cloud-config
install:
  device: /dev/sda
  reboot: true
  poweroff: false
stylus:
  debug: true
  site:
    paletteEndpoint: xxxx.spectrocloud.com
    autoRegister: true
    edgeHostToken: xxxxxxxxxxx
    insecureSkipVerify: false
```

## 6. Error Handling

### 6.1 Validation Errors

| Error Condition | Detection | Handling |
|----------------|-----------|----------|
| Missing dependencies | Command check | Exit with error message |
| Missing required vars | Variable validation | Exit with list of missing vars |
| Raw file not found | File existence check | Exit with directory listing |
| AWS credentials missing | Credential validation | Exit with guidance |

### 6.2 AWS API Errors

| Error Condition | Detection | Handling |
|----------------|-----------|----------|
| S3 upload failure | AWS CLI exit code | Exit with error message |
| Snapshot import failure | Status polling | Exit with status message |
| AMI registration failure | AWS CLI exit code | Exit with error details |
| AMI in failed state | State polling | Exit with failure reason |

### 6.3 Retry Logic

- **Snapshot Import**: Polls every 30 seconds until completion
- **AMI Availability**: Polls every 15 seconds until available
- **Query Failures**: Retries with 15-second delay

### 6.4 Error Messages

The script provides detailed error messages including:
- Missing configuration variables
- AWS API error details
- File system errors
- Process state information

## 7. Security Considerations

### 7.1 Credential Management

#### Best Practices
1. **AWS Profile (Recommended)**:
   - Uses IAM roles and profiles
   - Supports credential rotation
   - Integrates with AWS SSO
   - Stored in `~/.aws/credentials` or `~/.aws/config`

2. **Access Keys (Alternative)**:
   - Must be kept secure
   - Should use least-privilege IAM policies
   - Consider using temporary credentials (session tokens)

#### Secret Handling
- Secrets passed via Earthly `--secret` flags
- Not exposed in build logs
- Script validates credential presence before use

### 7.2 IAM Permissions Required

The AWS credentials must have the following permissions:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:PutObject",
        "s3:GetObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::bucket-name/*",
        "arn:aws:s3:::bucket-name"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "ec2:ImportSnapshot",
        "ec2:DescribeImportSnapshotTasks",
        "ec2:DescribeSnapshots",
        "ec2:RegisterImage",
        "ec2:DescribeImages",
        "ec2:CreateTags"
      ],
      "Resource": "*"
    }
  ]
}
```

### 7.3 Network Security

- S3 uploads use HTTPS
- AWS API calls use TLS
- No unencrypted data transmission

### 7.4 Image Security

- Raw images contain sensitive configuration
- S3 bucket should have encryption enabled
- Consider using S3 bucket policies to restrict access
- AMI should be shared only with authorized accounts

## 8. Dependencies

### 8.1 Build Dependencies

| Component | Version | Purpose |
|-----------|---------|---------|
| Ubuntu | 22.04 | Base image |
| AWS CLI | v2 (latest) | AWS API interactions |
| curl | Latest | HTTP client |
| unzip | Latest | Archive extraction |
| jq | Latest | JSON processing (in script) |

### 8.2 External Services

| Service | Purpose | Required |
|---------|---------|----------|
| AWS S3 | Raw image storage | Yes |
| AWS EC2 | Snapshot import & AMI registration | Yes |
| Internet | Download AWS CLI | Yes |

### 8.3 Earthfile Targets

| Target | Purpose | Required |
|--------|---------|----------|
| `+ubuntu` | Base Ubuntu image | Yes |
| `+cloud-image` | Creates raw disk image | Yes |
| `+iso-image` | Creates installer image | Indirect (via cloud-image) |

## 9. Usage Examples

### 9.1 Basic Usage

```bash
# Build AWS cloud image
./earthly.sh -P +aws-cloud-image \
  --REGION=us-east-1 \
  --S3_BUCKET=my-canvos-images \
  --S3_KEY=canvos-image.raw \
  --ARCH=amd64
```

### 9.2 With AWS Profile

```bash
# Using .secret file with AWS_PROFILE
cat > .secret <<EOF
AWS_PROFILE=production
EOF

./earthly.sh -P +aws-cloud-image \
  --REGION=us-east-1 \
  --S3_BUCKET=my-canvos-images \
  --ARCH=amd64
```

### 9.3 With Access Keys

```bash
# Using .secret file with access keys
cat > .secret <<EOF
AWS_ACCESS_KEY_ID=AKIAIOSFODNN7EXAMPLE
AWS_SECRET_ACCESS_KEY=wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY
EOF

./earthly.sh -P +aws-cloud-image \
  --REGION=us-east-1 \
  --S3_BUCKET=my-canvos-images \
  --ARCH=amd64
```

### 9.4 Complete Build Pipeline

```bash
# Step 1: Build installer image
./earthly.sh +iso-image --ARCH=amd64

# Step 2: Build cloud image (creates raw file)
./earthly.sh +cloud-image --ARCH=amd64

# Step 3: Convert to AMI
./earthly.sh -P +aws-cloud-image \
  --REGION=us-east-1 \
  --S3_BUCKET=my-canvos-images \
  --ARCH=amd64
```

## 10. Performance Considerations

### 10.1 Build Time

- **AWS CLI Installation**: ~30-60 seconds
- **S3 Upload**: Depends on raw image size (typically 1-5 GB)
  - Upload speed: Limited by network bandwidth
  - Large images may take 10-30 minutes
- **Snapshot Import**: AWS-managed process
  - Typically 15-45 minutes for 1-5 GB images
  - Progress can be monitored via AWS console
- **AMI Registration**: ~1-2 minutes after snapshot completion

### 10.2 Optimization Strategies

1. **S3 Upload**:
   - Use S3 Transfer Acceleration if available
   - Consider compressing raw images (though not currently implemented)
   - Use multipart uploads for large files (automatic with AWS CLI)

2. **Snapshot Import**:
   - Process is managed by AWS, no optimization possible
   - Monitor progress via AWS console or CLI

3. **Caching**:
   - Earthly caches intermediate layers
   - Re-running with same inputs uses cached artifacts

## 11. Limitations and Constraints

### 11.1 Current Limitations

1. **Architecture Support**: Currently only supports `x86_64` (hardcoded in script)
2. **Boot Mode**: Fixed to `uefi` (hardcoded in script)
3. **Root Device**: Fixed to `/dev/xvda` (hardcoded in script)
4. **Virtualization**: Fixed to `hvm` (hardcoded in script)
5. **Region**: Single region per build (no multi-region support)

### 11.2 AWS Service Limits

- **Snapshot Import**: Subject to AWS account limits
- **AMI Count**: Subject to AWS account limits (default: 1000 per region)
- **S3 Upload**: Subject to S3 bucket size limits

### 11.3 Known Issues

1. **Large Images**: Very large raw images (>10GB) may experience:
   - Extended upload times
   - Longer snapshot import duration
   - Potential timeout issues

2. **Network Dependencies**: Requires stable internet connection for:
   - AWS CLI download
   - S3 upload
   - AWS API calls

## 12. Future Enhancements

### 12.1 Potential Improvements

1. **Multi-Architecture Support**:
   - Add ARM64 (aarch64) support
   - Dynamic architecture detection

2. **Multi-Region Support**:
   - Copy AMI to multiple regions
   - Parallel processing

3. **Image Optimization**:
   - Automatic compression before upload
   - Image size reduction techniques

4. **Enhanced Monitoring**:
   - Progress bars for long operations
   - Real-time status updates
   - Build time metrics

5. **Advanced Features**:
   - AMI sharing with other accounts
   - Automatic AMI tagging
   - Launch template creation
   - AMI deprecation handling

6. **Error Recovery**:
   - Resume failed uploads
   - Retry failed operations
   - Cleanup on failure

## 13. Troubleshooting

### 13.1 Common Issues

#### Issue: "RAW file not found"
**Cause**: `+cloud-image` target didn't produce a raw file
**Solution**: 
- Verify `+cloud-image` target completed successfully
- Check that `cloud-images/config/user-data.yaml` exists
- Review auroraboot logs in build output

#### Issue: "Missing required configuration variables"
**Cause**: Required variables not set in `.arg` file
**Solution**:
- Ensure `REGION`, `S3_BUCKET` are set
- `S3_KEY` will auto-generate if not set

#### Issue: "AWS credentials not found"
**Cause**: No credentials provided
**Solution**:
- Set `AWS_PROFILE` in `.secret` file, OR
- Set `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` in `.secret` file

#### Issue: "Snapshot import failed"
**Cause**: Various (permissions, S3 access, etc.)
**Solution**:
- Check IAM permissions
- Verify S3 bucket exists and is accessible
- Check AWS service health
- Review snapshot import task details in AWS console

#### Issue: "AMI registration failed"
**Cause**: Invalid snapshot, permissions, etc.
**Solution**:
- Verify snapshot is in `completed` state
- Check IAM permissions for `ec2:RegisterImage`
- Review AMI registration error in AWS console

### 13.2 Debug Mode

Enable debug output by checking:
- Earthly build logs
- Script output (already verbose with `set -x`)
- AWS CloudTrail for API call details
- AWS Console for resource states

## 14. Testing

### 14.1 Unit Testing

- Script validation logic
- AWS helper functions
- Error handling paths

### 14.2 Integration Testing

- End-to-end build pipeline
- AWS resource creation
- Idempotency checks

### 14.3 Manual Testing Checklist

- [ ] Verify `.arg` file configuration
- [ ] Verify `.secret` file with credentials
- [ ] Verify `user-data.yaml` exists
- [ ] Run `+cloud-image` target first
- [ ] Verify raw file exists in build directory
- [ ] Run `+aws-cloud-image` target
- [ ] Verify S3 upload success
- [ ] Verify snapshot import completion
- [ ] Verify AMI registration
- [ ] Test AMI launch in EC2

## 15. References

### 15.1 Related Documentation

- [Earthfile Documentation](https://docs.earthly.dev/)
- [AWS EC2 Import Documentation](https://docs.aws.amazon.com/vm-import/latest/userguide/vmimport.html)
- [AWS CLI Documentation](https://docs.aws.amazon.com/cli/latest/userguide/)
- [Kairos/Auroraboot Documentation](https://kairos.io/docs/)

### 15.2 Related Files

- `Earthfile`: Main build definition
- `cloud-images/scripts/create-raw-to-ami.sh`: Conversion script
- `cloud-images/config/user-data.yaml`: Cloud-init configuration
- `.arg.template`: Argument template file
- `README.md`: Project documentation

---

**Document Version**: 1.0  
**Last Updated**: 2024  
**Author**: Design Document Generator  
**Review Status**: Pending Review

