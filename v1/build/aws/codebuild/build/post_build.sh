#!/bin/sh
#Only dashisms allowed (https://wiki.archlinux.org/index.php/Dash).

echo "Post-Build Started on $(date)"

#------------------------------------------------------------------------
# BEGIN: Declare some functions
#------------------------------------------------------------------------

#Produce the output artifact file...
build_output_artifact () {

    printf '{"firstRegionTag":"%s","secondRegionTag":"%s","firstProdRegionTag":"%s","secondProdRegionTag":"%s"}' "$FIRST_REGION_DOCKER_URL:$GIT_REVISION_TAG" "$SECOND_REGION_DOCKER_URL:$GIT_REVISION_TAG" "$PROD_FIRST_REGION_DOCKER_URL:$GIT_REVISION_TAG" "$PROD_SECOND_REGION_DOCKER_URL:$GIT_REVISION_TAG" > /tmp/build.json

}

#Function to check if the AWS command was successful.
check_aws_status () {
  #The $? variable always contains the status code of the previously run command.
  #We can either pass in $? or this function will use it as the default value if nothing is passed in.
  local prev=${1:-$?}

  if [ $prev -eq 0 ]; then
    echo "AWS CLI command has succeeded."
  else
    echo "AWS CLI command has failed."
    #Kill the build script so that we go no further.
    exit 1
  fi
}

#Function to check if the docker command was successful.
check_docker_status () {
  #The $? variable always contains the status code of the previously run command.
  #We can either pass in $? or this function will use it as the default value if nothing is passed in.
  local prev=${1:-$?}

  if [ $prev -eq 0 ]; then
    echo "The docker command has succeeded."
  else
    echo "The docker command has failed."
    #Kill the build script so that we go no further.
    exit 1
  fi
}

promote_zip_file () {
  local bucket="$1"
  local project="$2"
  local current_env="$3"
  local promote_env="$4"
  local file="$5"
  local region="$6"

  echo "Getting the \"s3://$bucket/$project/$current_env/$file\" file..."
  aws --region "$region" s3api get-object --bucket "$bucket" --key "$project/$current_env/$file" "/tmp/$file"
  check_aws_status $?

  echo "Promoting \"$file\" to \"s3://$bucket/$project/$promote_env/$file\" file..."
  aws s3 cp "/tmp/$file" "s3://$bucket/$project/$promote_env/$file" --region "$region" --quiet
  check_aws_status $?
}

#Push the docker image out to ECR
push_docker_image () {
  local image_url="$1"
  local branch="$2"
  local region="${3:-$AWS_REGION}"
  local account="${4:-$AWS_ACCOUNT_ID}"

  echo "Logging into docker..."
  aws --region "$region" ecr get-login-password | docker login --username "AWS" --password-stdin "$account.dkr.ecr.$region.amazonaws.com"
  check_aws_status $?

  docker push "$image_url:$GIT_REVISION_TAG"
  check_docker_status $?

  docker push "$image_url:$BUILD_ID_TAG"
  check_docker_status $?

  docker push "$image_url:$VERSION_TAG"
  check_docker_status $?

  docker push "$image_url:latest"
  check_docker_status $?

}

reject_approval () {
  local region="$1"
  local codepipeline="$2"

  echo "Checking if the initial CodePipeline Approval action is \"InProgress\"..."
  local status=$(aws --region "$region" codepipeline get-pipeline-state --name "$codepipeline" --query 'stageStates[?stageName==`Deploy`] | [].actionStates[?actionName==`Approval`].latestExecution.status' --output text)
  check_aws_status $?

  if [ "$status" = "InProgress" ]; then
    aws --region "$region" codepipeline put-approval-result --pipeline-name "$codepipeline" --stage-name "Deploy" --action-name "Approval" --token "$(aws --region "$region" codepipeline get-pipeline-state --name "$codepipeline" --query 'stageStates[?stageName==`Deploy`] | [].actionStates[?actionName==`Approval`].latestExecution.token' --output text)" --result "summary=Automatic Rejection,status=Rejected"
    check_aws_status $?
  else
    echo "The CodePipeline is not in the \"InProgress\" state, so nothing to reject..."
  fi

}

tag_environment_images () {
  local remote_image_url="$1"
  local branch="$2"
  local key="${3:-$AWS_ECR_IMAGE_TAG}"
  local region="${4:-$AWS_REGION}"
  local account="${5:-$AWS_ACCOUNT_ID}"

  echo "Logging into docker..."
  aws --region "$region" ecr get-login-password | docker login --username "AWS" --password-stdin "$account.dkr.ecr.$region.amazonaws.com"
  check_aws_status $?

  docker tag "$remote_image_url:latest" "$remote_image_url:$key"
  check_docker_status $?
  docker push "$remote_image_url:$key"
  check_docker_status $?

}

#------------------------------------------------------------------------
# END: Declare some functions
#------------------------------------------------------------------------

#------------------------------------------------------------------------
# BEGIN: Deploy and tag the images and create artifact file
#------------------------------------------------------------------------

#Source variables from pre_build section.
. /tmp/pre_build
. /tmp/build

#Change the directory to the application directory...
if [ -z "$APP_BASE_FOLDER" ]; then
  echo "No application base folder was set, so not changing directory..."
else
  cd "$CODEBUILD_SRC_DIR/$APP_BASE_FOLDER"
fi

if [ "$RUN_DEPLOY" = "true" ]; then

  if [ "$AUTOMATIC_REJECT" = "Yes" ]; then
    echo "Checking to see if there is a pending approval that we want to automatically reject..."
    reject_approval "$AWS_REGION" "$REJECT_CODEPIPELINE"
  else
    echo "Automatic approval rejection is disabled..."
  fi

  echo "Promoting ZIP files..."

  if [ "$UNSTABLE_BRANCH" = "$GIT_BRANCH" ]; then
    promote_zip_file "$S3_ARTIFACT_BUCKET" "$BASE_BUCKET_FOLDER" "$GIT_BRANCH/init" "$AWS_ECR_IMAGE_TAG" "$SERVICE_S3_FILE" "$AWS_REGION"
    promote_zip_file "$S3_ARTIFACT_BUCKET" "$BASE_BUCKET_FOLDER" "$GIT_BRANCH/init" "$AWS_ECR_IMAGE_TAG" "$SERVICE_ENV_S3_FILE" "$AWS_REGION"
    promote_zip_file "$S3_ARTIFACT_BUCKET" "$BASE_BUCKET_FOLDER" "$GIT_BRANCH/init" "$AWS_ECR_IMAGE_TAG" "$TEST_S3_FILE" "$AWS_REGION"
  else
    promote_zip_file "$S3_ARTIFACT_BUCKET" "$BASE_BUCKET_FOLDER" "base" "$AWS_ECR_IMAGE_TAG" "$SERVICE_S3_FILE" "$AWS_REGION"
    promote_zip_file "$S3_ARTIFACT_BUCKET" "$BASE_BUCKET_FOLDER" "base" "$AWS_ECR_IMAGE_TAG" "$TEST_S3_FILE" "$AWS_REGION"
  fi

  echo "Pushing the docker image to the first region..."
  push_docker_image "$FIRST_REGION_DOCKER_URL" "$GIT_BRANCH"

  if [ "$SECOND_REGION_DOCKER_URL" != "NONE" ]; then
    echo "Pushing the docker image to the second region..."
    push_docker_image "$SECOND_REGION_DOCKER_URL" "$GIT_BRANCH" "$AWS_SECOND_REGION"
  fi

  if [ "$PROD_FIRST_REGION_DOCKER_URL" != "NONE" ]; then
    echo "Pushing the docker image to the production first region..."
    push_docker_image "$PROD_FIRST_REGION_DOCKER_URL" "$GIT_BRANCH" "$AWS_REGION" "$AWS_ECR_PROD_ACCOUNT_ID"
  fi

  if [ "$PROD_SECOND_REGION_DOCKER_URL" != "NONE" ]; then
    echo "Pushing the docker image to the production second region..."
    push_docker_image "$PROD_SECOND_REGION_DOCKER_URL" "$GIT_BRANCH" "$AWS_SECOND_REGION" "$AWS_ECR_PROD_ACCOUNT_ID"
  fi

  echo "Tag the appropriate image for each environment..."
  tag_environment_images "$FIRST_REGION_DOCKER_URL" "$GIT_BRANCH" "$AWS_ECR_IMAGE_TAG"

  if [ "$SECOND_REGION_DOCKER_URL" != "NONE" ]; then
    echo "Tag the appropriate image for each environment in the second region..."
    tag_environment_images "$SECOND_REGION_DOCKER_URL" "$GIT_BRANCH" "$AWS_ECR_IMAGE_TAG" "$AWS_SECOND_REGION"
  fi

  if [ "$PROD_FIRST_REGION_DOCKER_URL" != "NONE" ]; then
    echo "Pushing the docker image to the production first region..."
    tag_environment_images "$PROD_FIRST_REGION_DOCKER_URL" "$GIT_BRANCH" "$AWS_ECR_IMAGE_TAG" "$AWS_REGION" "$AWS_ECR_PROD_ACCOUNT_ID"
  fi

  if [ "$PROD_SECOND_REGION_DOCKER_URL" != "NONE" ]; then
    echo "Pushing the docker image to the production second region..."
    tag_environment_images "$PROD_SECOND_REGION_DOCKER_URL" "$GIT_BRANCH" "$AWS_ECR_IMAGE_TAG" "$AWS_SECOND_REGION" "$AWS_ECR_PROD_ACCOUNT_ID"
  fi

  echo "Building the output artifact..."
  build_output_artifact

else
  echo "No docker image was built, nothing to deploy..."
  exit 1
fi

#------------------------------------------------------------------------
# END: Deploy and tag the images and create artifact file
#------------------------------------------------------------------------