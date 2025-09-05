#!/bin/bash
# Script to create or delete AWS Secrets Manager and Parameter Store entries with tags (interactive)

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

print_status()   { echo -e "${GREEN}[INFO]${NC} $1"; }
print_warning()  { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error()    { echo -e "${RED}[ERROR]${NC} $1"; }

# Check AWS CLI
if ! command -v aws &>/dev/null; then
    print_error "AWS CLI not installed."
    exit 1
fi

if ! aws sts get-caller-identity &>/dev/null; then
    print_error "AWS credentials not configured. Run 'aws configure'."
    exit 1
fi

# Prompt user for action
echo "What do you want to do?"
select ACTION in "Create" "Delete" "Exit"; do
    case $ACTION in
        Create|Delete) break ;;
        Exit) exit 0 ;;
        *) echo "Invalid choice, try again." ;;
    esac
done

# Ask for names (with defaults)
read -p "Enter the secret name for the AWS Secret Key [default: prod/aws/secret-key]: " SECRET_KEY_SECRET_NAME
read -p "Enter the parameter name for the AWS Access Key [default: /prod/aws/access-key-id]: " ACCESS_KEY_PARAMETER
read -p "Enter the secret name for the PEM file [default: prod/ec2/keypair/my-key]: " PEM_SECRET_NAME

# Apply defaults if empty
SECRET_KEY_SECRET_NAME=${SECRET_KEY_SECRET_NAME:-"prod/aws/secret-key"}
ACCESS_KEY_PARAMETER=${ACCESS_KEY_PARAMETER:-"/prod/aws/access-key-id"}
PEM_SECRET_NAME=${PEM_SECRET_NAME:-"prod/ec2/keypair/my-key"}

# Tags
USER_TAG=$(whoami)
DATE_TAG=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# --- CREATE ---
create_resources() {
    print_status "Creating AWS secrets and parameters with tags..."

    aws secretsmanager create-secret \
        --name "$SECRET_KEY_SECRET_NAME" \
        --secret-string "dummy-secret-key" \
        --tags Key=CreatedBy,Value="$USER_TAG" Key=CreatedAt,Value="$DATE_TAG" \
        --no-cli-pager || print_warning "Secret already exists: $SECRET_KEY_SECRET_NAME"

    aws ssm put-parameter \
        --name "$ACCESS_KEY_PARAMETER" \
        --value "dummy-access-key" \
        --type SecureString \
        --tags Key=CreatedBy,Value="$USER_TAG" Key=CreatedAt,Value="$DATE_TAG" \
        --overwrite \
        --no-cli-pager

    aws secretsmanager create-secret \
        --name "$PEM_SECRET_NAME" \
        --secret-string "dummy-pem-content" \
        --tags Key=CreatedBy,Value="$USER_TAG" Key=CreatedAt,Value="$DATE_TAG" \
        --no-cli-pager || print_warning "Secret already exists: $PEM_SECRET_NAME"

    print_status "✅ Creation complete."
}

# --- DELETE ---
delete_resources() {
    print_status "You are about to delete:"
    echo "  - Secret: $SECRET_KEY_SECRET_NAME"
    echo "  - Parameter: $ACCESS_KEY_PARAMETER"
    echo "  - Secret: $PEM_SECRET_NAME"
    echo
    read -p "⚠️  Are you sure you want to delete these? (y/N): " CONFIRM

    if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
        print_warning "Operation cancelled."
        exit 0
    fi

    if aws secretsmanager describe-secret --secret-id "$SECRET_KEY_SECRET_NAME" &>/dev/null; then
        aws secretsmanager tag-resource \
            --secret-id "$SECRET_KEY_SECRET_NAME" \
            --tags Key=DeletedBy,Value="$USER_TAG" Key=DeletedAt,Value="$DATE_TAG"
        aws secretsmanager delete-secret \
            --secret-id "$SECRET_KEY_SECRET_NAME" \
            --force-delete-without-recovery \
            --no-cli-pager
        print_status "Deleted secret: $SECRET_KEY_SECRET_NAME"
    else
        print_warning "Secret not found: $SECRET_KEY_SECRET_NAME"
    fi

    if aws ssm get-parameter --name "$ACCESS_KEY_PARAMETER" &>/dev/null; then
        aws ssm delete-parameter \
            --name "$ACCESS_KEY_PARAMETER" \
            --no-cli-pager
        print_status "Deleted parameter: $ACCESS_KEY_PARAMETER (DeletedBy=$USER_TAG, DeletedAt=$DATE_TAG)"
    else
        print_warning "Parameter not found: $ACCESS_KEY_PARAMETER"
    fi

    if aws secretsmanager describe-secret --secret-id "$PEM_SECRET_NAME" &>/dev/null; then
        aws secretsmanager tag-resource \
            --secret-id "$PEM_SECRET_NAME" \
            --tags Key=DeletedBy,Value="$USER_TAG" Key=DeletedAt,Value="$DATE_TAG"
        aws secretsmanager delete-secret \
            --secret-id "$PEM_SECRET_NAME" \
            --force-delete-without-recovery \
            --no-cli-pager
        print_status "Deleted secret: $PEM_SECRET_NAME"
    else
        print_warning "Secret not found: $PEM_SECRET_NAME"
    fi

    print_status "✅ Deletion complete."
}

# --- Execute ---
if [[ "$ACTION" == "Create" ]]; then
    create_resources
elif [[ "$ACTION" == "Delete" ]]; then
    delete_resources
fi
