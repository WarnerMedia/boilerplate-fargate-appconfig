#!/bin/sh
#Only dashisms allowed (https://wiki.archlinux.org/index.php/Dash).

echo "Pre-Build Started on $(date)"

#------------------------------------------------------------------------
# BEGIN: Main Logic
#------------------------------------------------------------------------

echo "Docker Image URL: $TEST_IMAGE"

echo "Log into ECR..."
aws --region "$AWS_REGION" ecr get-login-password | docker login --username "AWS" --password-stdin "$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com"

if [ -n "$APP_BASE_FOLDER" ]; then
  cd "$CODEBUILD_SRC_DIR/$APP_BASE_FOLDER" || exit 1;
fi

echo "Install the NPM modules..."
npm install

echo "Run docker compose..."
docker-compose up -d

#------------------------------------------------------------------------
# END: Main Logic
#------------------------------------------------------------------------