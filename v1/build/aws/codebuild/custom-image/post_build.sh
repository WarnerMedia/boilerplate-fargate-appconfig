#!/bin/sh
#Only dashisms allowed (https://wiki.archlinux.org/index.php/Dash).

echo "Post-Build Started on $(date)"

#------------------------------------------------------------------------
# BEGIN: Declare some functions
#------------------------------------------------------------------------

#Produce the output artifact file...
build_output_artifact () {

    printf '{"imageTag":"%s"}' "$DOCKER_URL:$CUSTOM_IMAGE_TAG-$GIT_REVISION_TAG" > /tmp/build.json

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

#Push the docker image out to ECR
push_docker_image () {
  local image_url="$1"
  local region="${2:-$AWS_REGION}"
  local account="${3:-$AWS_ACCOUNT_ID}"

  echo "Logging into docker..."
  aws --region "$region" ecr get-login-password | docker login --username "AWS" --password-stdin "$account.dkr.ecr.$region.amazonaws.com"
  check_aws_status $?

  docker push "$image_url:$CUSTOM_IMAGE_TAG-$GIT_REVISION_TAG"
  check_docker_status $?

  docker push "$image_url:$CUSTOM_IMAGE_TAG-$BUILD_ID_TAG"
  check_docker_status $?

  docker push "$image_url:$CUSTOM_IMAGE_TAG-$VERSION_TAG"
  check_docker_status $?

  docker push "$image_url:$CUSTOM_IMAGE_TAG-latest"
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
  cd "$CODEBUILD_SRC_DIR/$CUSTOM_IMAGE_PATH/$CUSTOM_IMAGE_TAG" || exit 1
else
  cd "$CODEBUILD_SRC_DIR/$APP_BASE_FOLDER/$CUSTOM_IMAGE_PATH/$CUSTOM_IMAGE_TAG" || exit 1
fi


if [ "$RUN_DEPLOY" = "true" ]; then

  echo "Pushing the docker image to the first region..."
  push_docker_image "$DOCKER_URL"

  echo "Building the output artifact..."
  build_output_artifact

else
  echo "No docker image was built, nothing to deploy..."
  exit 1
fi

#------------------------------------------------------------------------
# END: Deploy and tag the images and create artifact file
#------------------------------------------------------------------------