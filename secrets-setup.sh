#!/bin/bash
# Script to set up AWS Secrets Manager and Parameter Store for Terraform

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
    print_error "AWS CLI is not installed. Please install it first."
    exit 1
fi

# Check if AWS credentials are configured
if ! aws sts get-caller-identity &> /dev/null; then
    print_error "AWS credentials are not configured. Please run 'aws configure' first."
    exit 1
fi

print_status "Setting up AWS Secrets Manager and Parameter Store for Terraform..."

# Get user input
read -p "Enter your AWS Access Key ID: " AWS_ACCESS_KEY
read -s -p "Enter your AWS Secret Access Key: " AWS_SECRET_KEY
echo
read -p "Enter the path to your PEM file: " PEM_FILE_PATH
read -p "Enter a name for the secret key secret (default: prod/aws/secret-key): " SECRET_KEY_SECRET_NAME
read -p "Enter a name for the access key parameter (default: /prod/aws/access-key-id): " ACCESS_KEY_PARAMETER
read -p "Enter a name for the PEM file secret (default: prod/ec2/keypair/my-key): " PEM_SECRET_NAME

# Set defaults
SECRET_KEY_SECRET_NAME=${SECRET_KEY_SECRET_NAME:-"prod/aws/secret-key"}
ACCESS_KEY_PARAMETER=${ACCESS_KEY_PARAMETER:-"/prod/aws/access-key-id"}
PEM_SECRET_NAME=${PEM_SECRET_NAME:-"prod/ec2/keypair/my-key"}

# Validate PEM file exists
if [[ ! -f "$PEM_FILE_PATH" ]]; then
    print_error "PEM file not found at: $PEM_FILE_PATH"
    exit 1
fi

print_status "Creating AWS credentials secret..."
# Create secret key secret
aws secretsmanager create-secret \
    --name "$SECRET_KEY_SECRET_NAME" \
    --description "AWS secret key for Terraform EC2 deployment" \
    --secret-string "{\"secret_key\":\"$AWS_SECRET_KEY\"}" \
    --no-cli-pager || {
    print_warning "Secret may already exist. Updating instead..."
    aws secretsmanager update-secret \
        --secret-id "$SECRET_KEY_SECRET_NAME" \
        --secret-string "{\"secret_key\":\"$AWS_SECRET_KEY\"}" \
        --no-cli-pager
}

print_status "Creating AWS access key parameter..."
# Create access key parameter
aws ssm put-parameter \
    --name "$ACCESS_KEY_PARAMETER" \
    --value "$AWS_ACCESS_KEY" \
    --type "SecureString" \
    --description "AWS access key ID for Terraform EC2 deployment" \
    --no-cli-pager || {
    print_warning "Parameter may already exist. Updating instead..."
    aws ssm put-parameter \
        --name "$ACCESS_KEY_PARAMETER" \
        --value "$AWS_ACCESS_KEY" \
        --type "SecureString" \
        --overwrite \
        --no-cli-pager
}

print_status "Creating PEM file secret..."
# Create PEM file secret
aws secretsmanager create-secret \
    --name "$PEM_SECRET_NAME" \
    --description "EC2 Key Pair PEM file for SSH access" \
    --secret-string file://"$PEM_FILE_PATH" \
    --no-cli-pager || {
    print_warning "Secret may already exist. Updating instead..."
    aws secretsmanager update-secret \
        --secret-id "$PEM_SECRET_NAME" \
        --secret-string file://"$PEM_FILE_PATH" \
        --no-cli-pager
}

print_status "Secrets created successfully!"
echo
print_status "Update your terraform.tfvars with the following:"
echo "use_secrets_manager = true"
echo "aws_credentials_secret_name = \"$SECRET_KEY_SECRET_NAME\""
echo "aws_access_key_parameter = \"$ACCESS_KEY_PARAMETER\""
echo "pem_file_secret_name = \"$PEM_SECRET_NAME\""
echo
print_warning "Make sure your Terraform execution environment has the necessary IAM permissions to access these secrets."
echo
print_status "Setup complete!"