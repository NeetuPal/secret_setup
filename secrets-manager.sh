#!/bin/bash
# secrets-manager.sh
# Manage AWS Secrets Manager and SSM Parameters
# Tags: CreatedBy=$(whoami), CreatedAt=<UTC timestamp>

set -euo pipefail

# Function: create or update SSM Parameter
create_parameter() {
  local name="$1"
  local value="$2"

  echo "[INFO] Checking if parameter $name exists..."
  if aws ssm describe-parameters \
      --parameter-filters "Key=Name,Values=$name" \
      --query "Parameters" --output text | grep -q "$name"; then

    echo "[INFO] Parameter already exists, updating value..."
    aws ssm put-parameter \
      --name "$name" \
      --value "$value" \
      --type String \
      --overwrite >/dev/null

    echo "[INFO] Updating tags for parameter $name..."
    aws ssm add-tags-to-resource \
      --resource-type "Parameter" \
      --resource-id "$name" \
      --tags "Key=CreatedBy,Value=$(whoami)" \
             "Key=CreatedAt,Value=$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

  else
    echo "[INFO] Creating new parameter $name with tags..."
    aws ssm put-parameter \
      --name "$name" \
      --value "$value" \
      --type String \
      --tags "Key=CreatedBy,Value=$(whoami)" \
             "Key=CreatedAt,Value=$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  fi
}

# Function: create a Secret in AWS Secrets Manager
create_secret() {
  local name="$1"
  local value="$2"

  echo "[INFO] Creating secret $name..."
  aws secretsmanager create-secret \
    --name "$name" \
    --secret-string "$value" \
    --tags "Key=CreatedBy,Value=$(whoami)" \
           "Key=CreatedAt,Value=$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
    --query "{ARN:ARN,Name:Name}" --output json || {
      echo "[WARN] Secret $name may already exist. Updating instead..."
      aws secretsmanager put-secret-value \
        --secret-id "$name" \
        --secret-string "$value" \
        --query "{ARN:ARN,Name:Name}" --output json
  }
}

# Function: delete secret safely
delete_secret() {
  local name="$1"
  echo "[INFO] Deleting secret $name..."
  if aws secretsmanager describe-secret --secret-id "$name" >/dev/null 2>&1; then
    aws secretsmanager delete-secret \
      --secret-id "$name" \
      --force-delete-without-recovery \
      --query "{ARN:ARN,Name:Name,DeletionDate:DeletionDate}" --output json
  else
    echo "[WARNING] Secret not found: $name"
  fi
}

# Function: delete parameter safely
delete_parameter() {
  local name="$1"
  echo "[INFO] Deleting parameter $name..."
  if aws ssm get-parameter --name "$name" >/dev/null 2>&1; then
    aws ssm delete-parameter --name "$name"
    echo "[INFO] Deleted parameter: $name"
  else
    echo "[WARNING] Parameter not found: $name"
  fi
}

# Function: list resources created by this script
list_resources() {
  echo "[INFO] Listing AWS resources tagged with CreatedBy=$(whoami)..."

  echo "🔹 Secrets Manager:"
  aws secretsmanager list-secrets \
    --query "SecretList[?Tags[?Key=='CreatedBy' && Value=='$(whoami)']].[Name,ARN]" \
    --output table || echo "[WARN] No secrets found."

  echo ""
  echo "🔹 SSM Parameters:"
  aws ssm describe-parameters \
    --query "Parameters[?Tags[?Key=='CreatedBy' && Value=='$(whoami)']].[Name]" \
    --output table || echo "[WARN] No parameters found."
}

# ------------------ MAIN MENU ------------------
main() {
  echo "What do you want to do?"
  echo "1) Create"
  echo "2) Delete"
  echo "3) Exit"
  echo "4) List"
  read -rp "#? " choice

  secret_aws_key="prod/aws/secret-key"
  param_access_key="/prod/aws/access-key-id"
  pem_secret="prod/ec2/keypair/my-key"

  case "$choice" in
    1)
      read -rp "Enter the secret name for the AWS Secret Key [default: $secret_aws_key]: " input
      secret_aws_key="${input:-$secret_aws_key}"
      read -rp "Enter value for $secret_aws_key [default: dummy-secret-value]: " input
      secret_aws_value="${input:-dummy-secret-value}"

      read -rp "Enter the parameter name for the AWS Access Key [default: $param_access_key]: " input
      param_access_key="${input:-$param_access_key}"
      read -rp "Enter value for $param_access_key [default: dummy-access-key]: " input
      param_access_value="${input:-dummy-access-key}"

      read -rp "Enter the secret name for the PEM file [default: $pem_secret]: " input
      pem_secret="${input:-$pem_secret}"
      read -rp "Enter path to PEM file [default: ./test.pem]: " input
      pem_file="${input:-./test.pem}"

      if [[ -f "$pem_file" ]]; then
        pem_secret_value=$(<"$pem_file")
      else
        echo "[WARNING] File not found: $pem_file, using dummy value"
        pem_secret_value="dummy-pem-content"
      fi

      echo "[INFO] Creating AWS secrets and parameters with tags..."
      create_secret "$secret_aws_key" "$secret_aws_value"
      create_parameter "$param_access_key" "$param_access_value"
      create_secret "$pem_secret" "$pem_secret_value"
      ;;

    2)
      read -rp "Enter the secret name for the AWS Secret Key [default: $secret_aws_key]: " input
      secret_aws_key="${input:-$secret_aws_key}"

      read -rp "Enter the parameter name for the AWS Access Key [default: $param_access_key]: " input
      param_access_key="${input:-$param_access_key}"

      read -rp "Enter the secret name for the PEM file [default: $pem_secret]: " input
      pem_secret="${input:-$pem_secret}"

      echo "[INFO] You are about to delete:"
      echo "  - Secret: $secret_aws_key"
      echo "  - Parameter: $param_access_key"
      echo "  - Secret: $pem_secret"
      read -rp "⚠️  Are you sure you want to delete these? (y/N): " confirm
      if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
        delete_secret "$secret_aws_key"
        delete_parameter "$param_access_key"
        delete_secret "$pem_secret"
        echo "[INFO] ✅ Deletion complete."
      else
        echo "[INFO] ❌ Deletion canceled."
      fi
      ;;

    3) echo "Bye!"; exit 0 ;;

    4) list_resources ;;

    *) echo "[ERROR] Invalid choice."; exit 1 ;;
  esac
}

main "$@"
