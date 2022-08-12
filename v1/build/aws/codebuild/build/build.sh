#!/bin/sh
#Only dashisms allowed (https://wiki.archlinux.org/index.php/Dash).

echo "Build Started on $(date)"

#------------------------------------------------------------------------
# BEGIN: Set some default variables and files
#------------------------------------------------------------------------

GITHUB_FILE="github.json"

#------------------------------------------------------------------------
# END: Set some default variables and files
#------------------------------------------------------------------------

#------------------------------------------------------------------------
# BEGIN: Declare some functions
#------------------------------------------------------------------------

#Function to check if the Docker build completed successfully.
check_docker_status () {
  #The $? variable always contains the status code of the previously run command.
  #We can either pass in $? or this function will use it as the default value if nothing is passed in.
  local prev=${1:-$?}

  if [ $prev -eq 0 ]; then
    echo "The docker command has succeeded."
    #Set the deployment tag to "true" since the build has succeeded.
    RUN_DEPLOY="true"
  else
    echo "The docker command has failed."
    #Set the deployment tag to "false" since the build has failed.
    RUN_DEPLOY="false"
    export_variable "RUN_DEPLOY"
    #Kill the build script so that we go no further.
    exit 1
  fi
}

create_github_json () {
  local organization="$1"
  local repository="$2"
  local branch="$3"
  local commit="$4"
  local version="$5"
  local file="$6"
  local base="https://github.com"

  echo "Create the GitHub JSON file..."

  printf '{"organization":"%s","repository":"%s","branch":"%s","commit":"%s","commitUrl":"%s","releaseUrl":"%s"}' "$organization" "$repository" "$branch" "$commit" "$base/$organization/$repository/commit/$commit" "$base/$organization/$repository/releases/tag/v$version" > "./$file"
}

#Because CodeBuild doesn't pass environment between phases, putting in a patch.
export_variable () {
  local key="$1"

  export $key

  local temp=$(printenv | grep -w $key)

  echo "$temp" >> /tmp/build
}

#Function for tagging the image that was just built.
tag_docker_image () {
  local local_image_url="$1"
  local remote_image_url="$2"

  docker tag "$local_image_url:latest" "$remote_image_url:$GIT_REVISION_TAG"
  check_docker_status $?

  docker tag "$local_image_url:latest" "$remote_image_url:$BUILD_ID_TAG"
  check_docker_status $?

  docker tag "$local_image_url:latest" "$remote_image_url:$VERSION_TAG"
  check_docker_status $?

  docker tag "$local_image_url:latest" "$remote_image_url:latest"
  check_docker_status $?
}

#------------------------------------------------------------------------
# END: Declare some functions
#------------------------------------------------------------------------

#------------------------------------------------------------------------
# BEGIN: Variable Check
#------------------------------------------------------------------------

#Source variables from pre_build section.
. /tmp/pre_build

touch /tmp/build

#------------------------------------------------------------------------
# END: Variable Check
#------------------------------------------------------------------------

#------------------------------------------------------------------------
# BEGIN: Run the build process
#------------------------------------------------------------------------

#Change the directory to the application directory...
if [ -z "$APP_BASE_FOLDER" ]; then
  echo "No application version was set, so not changing directory..."
else
  cd "$CODEBUILD_SRC_DIR/$APP_BASE_FOLDER" || exit 1
fi

if [ "$RUN_BUILD" = "true" ]; then

  echo "Creating a file with additional GitHub information."
  create_github_json "$GITHUB_ORGANIZATION" "$GITHUB_REPOSITORY" "$GIT_BRANCH" "$GIT_FULL_REVISION" "$VERSION" "$GITHUB_FILE"

  echo "Checking the docker version..."
  docker version

  if [ -n "$DOCKERHUB_USERNAME" ] && [ -n "$DOCKERHUB_TOKEN" ]; then
    echo "Logging into Docker Hub to increase pull allowance..."
    docker login -u="$DOCKERHUB_USERNAME" -p="$DOCKERHUB_TOKEN"
    check_docker_status $?
  else
    echo "No Docker Hub credentials were set, cannot log in..."
  fi

  echo "Building image from the main Dockerfile..."
  docker build -t "$IMAGE_REPO_NAME:latest" .
  check_docker_status $?

  echo "Tag the image for the primary region..."
  tag_docker_image "$IMAGE_REPO_NAME" "$FIRST_REGION_DOCKER_URL"

  if [ "$SECOND_REGION_DOCKER_URL" != "NONE" ]; then
    echo "Tag the image for the secondary region..."
    tag_docker_image "$IMAGE_REPO_NAME" "$SECOND_REGION_DOCKER_URL"
  else
    echo "The secondary region wasn't set, so not going to tag anything for that region..."
  fi

  if [ "$PROD_FIRST_REGION_DOCKER_URL" != "NONE" ]; then
    echo "Tag the image for the production primary region..."
    tag_docker_image "$IMAGE_REPO_NAME" "$PROD_FIRST_REGION_DOCKER_URL"
  else
    echo "The primary production region wasn't set, so not going to tag anything for that region..."
  fi

  if [ "$PROD_SECOND_REGION_DOCKER_URL" != "NONE" ]; then
    echo "Tag the image for the production secondary region..."
    tag_docker_image "$IMAGE_REPO_NAME" "$PROD_SECOND_REGION_DOCKER_URL"
  else
    echo "The secondary production region wasn't set, so not going to tag anything for that region..."
  fi
else
  echo "Docker image already exists for this GIT hash, not rebuilding image..."
  RUN_DEPLOY="false"
fi

#------------------------------------------------------------------------
# END: Run the build process
#------------------------------------------------------------------------

#------------------------------------------------------------------------
# BEGIN: Export variables to share with other shell scripts
#------------------------------------------------------------------------

export_variable "RUN_DEPLOY"

#------------------------------------------------------------------------
# END: Export variables to share with other shell scripts
#------------------------------------------------------------------------