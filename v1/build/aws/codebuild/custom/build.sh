#!/bin/sh
#Only dashisms allowed (https://wiki.archlinux.org/index.php/Dash).

#------------------------------------------------------------------------
# BEGIN: Declare some functions
#------------------------------------------------------------------------

enable_ecr_scanning () {
  local region="$1"
  local account="$2"
  local repository="$3"

  echo "Enable ECR image scanning for \"$repository\" in the \"$region\" region..."

  # Enable ECR image scanning...
  aws --region "$region" ecr put-image-scanning-configuration --registry-id "$account" --repository-name "$repository" --image-scanning-configuration scanOnPush=true

}

#------------------------------------------------------------------------
# END: Declare some functions
#------------------------------------------------------------------------

#------------------------------------------------------------------------
# BEGIN: Main Logic
#------------------------------------------------------------------------

echo "Build Started on $(date)"

# Enable for the primary region.
enable_ecr_scanning "$AWS_REGION" "$AWS_ACCOUNT_ID" "$ECS_REPOSITORY_NAME"

# Enable for the secondary region.
if [ "$AWS_SECOND_REGION" != "NONE" ]; then
  enable_ecr_scanning "$AWS_SECOND_REGION" "$AWS_ACCOUNT_ID" "$ECS_REPOSITORY_NAME"
fi

#------------------------------------------------------------------------
# END: Main Logic
#------------------------------------------------------------------------