#!/bin/bash
# secrets-manager.sh
# Manage AWS Secrets Manager and SSM Parameters
# Tags: CreatedBy=$(whoami), CreatedAt=<UTC timestamp>

set -euo pipefail

CREATED_BY="$(whoami)"

# ---------------- FUNCTIONS ----------------

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
      --tags "Key=CreatedBy,Value=$CREATED_BY" \
             "Key=CreatedAt,Value=$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

  else
    echo "[INFO] Creating new parameter $name with tags..."
    aws ssm put-parameter \
      --name "$name" \
      --value "$value" \
      --type String \
      --tags "Key=CreatedBy,Value=$CREATED_BY" \
             "Key=CreatedAt,Value=$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  fi
}

create_secret() {
  local name="$1"
  local value="$2"

  echo "[INFO] Creating secret $name..."
  aws secretsmanager create-secret \
    --name "$name" \
    --secret-string "$value" \
    --tags "Key=CreatedBy,Value=$CREATED_BY" \
           "Key=CreatedAt,Value=$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
    --query "{ARN:ARN,Name:Name}" --output json || {
      echo "[WARN] Secret $name may already exist. Updating instead..."
      aws secretsmanager put-secret-value \
        --secret-id "$name" \
        --secret-string "$value" \
        --query "{ARN:ARN,Name:Name}" --output json
  }
}

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

list_resources() {
  echo "[INFO] Listing all AWS resources created by: $CREATED_BY"

  echo "🔑 Secrets Manager:"
  aws secretsmanager list-secrets \
    --query "SecretList[?Tags[?Key=='CreatedBy' && Value=='$CREATED_BY']].[Name,ARN]" \
    --output table || echo "[INFO] No secrets found."

  echo ""
  echo "📦 SSM Parameters:"
  aws ssm describe-parameters \
    --query "Parameters[?Tags[?Key=='CreatedBy' && Value=='$CREATED_BY']].[Name,Type]" \
    --output table || echo "[INFO] No parameters found."
}

# ---------------- MAIN MENU ----------------
main() {
  echo "What do you want to do?"
  echo "1) Create"
  echo "2) Delete"
  echo "3) List"
  echo "4) Exit"
  read -rp "#? " choice

  secret_aws_key="prod/aws/secret-key"
  param_access_key="/prod/aws/access-key-id"
  pem_secret="prod/ec2/keypair/my-key"

  case "$choice" in
    1)
      read -rp "Enter the secret name for the AWS Secret Key [default: $secret_aws_key]: " input
      secret_aws_key="${input:-$secret_aws_key}"

      read -rp "Enter the parameter name for the AWS Access Key [default: $param_access_key]: " input
      param_access_key="${input:-$param_access_key}"

      read -rp "Enter the secret name for the PEM file [default: $pem_secret]: " input
      pem_secret="${input:-$pem_secret}"

      echo "[INFO] Creating AWS secrets and parameters with tags..."
      create_secret "$secret_aws_key" "dummy-secret-value"
      create_parameter "$param_access_key" "dummy-access-key"
      create_secret "$pem_secret" "dummy-pem-content"
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
      read -rp "⚠️  Are you sure you want to
