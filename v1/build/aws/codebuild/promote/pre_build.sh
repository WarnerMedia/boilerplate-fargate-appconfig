#!/bin/sh
#Only dashisms allowed (https://wiki.archlinux.org/index.php/Dash).

echo "Pre-Build Started on $(date)"

#------------------------------------------------------------------------
# BEGIN: Set some default variables and files
#------------------------------------------------------------------------

#Create a file for transporting variables to other phases.
touch /tmp/pre_build

#Set a date variable...
DATETIME_ET=$(TZ="America/New_York" date +"%Y.%m.%d")
GIT_METADATA_FILE="git-metadata.json"

#------------------------------------------------------------------------
# END: Set some default variables and files
#------------------------------------------------------------------------

#------------------------------------------------------------------------
# BEGIN: Declare some functions
#------------------------------------------------------------------------

#Build a docker URL...
build_docker_url () {
  local account_id="$1"
  local region="$2"
  local image_repo="$3"

  echo "$account_id.dkr.ecr.$region.amazonaws.com/$image_repo"
}

#Check if the AWS command was successful.
check_aws_status () {
  #The $? variable always contains the status code of the previously run command.
  #We can either pass in $? or this function will use it as the default value if nothing is passed in.
  local prev=${1:-$?}

  if [ $prev -eq 0 ]; then
    echo "AWS CLI command has succeeded."
    #Set the build tag to "true" since the build has succeeded.
    RUN_BUILD="true"
  else
    echo "AWS CLI command has failed."
    #Set the build tag to "false" since the build has failed.
    RUN_BUILD="false"
    export RUN_BUILD
    #Kill the build script so that we go no further.
    exit 1
  fi
}

check_cmd_exists () {
  local cmd="$1"

  if exists $cmd; then
    echo "The command \"$cmd\" is installed."
  else
    echo "The command \"$cmd\" is not installed."
    exit 1
  fi
}

check_variable () {
  local variable="$1"
  local message="$2"

  if [ -z "$variable" ]; then
    echo "The $message was not retrieved successfully."
    exit 1
  else
    echo "The $message is: $variable"
  fi
}

#Check if required commands exist...
exists () {
  command -v "$1" >/dev/null 2>&1
}

#Because CodeBuild doesn't pass environment between phases, putting in a patch.
export_variable () {
  local key="$1"

  export $key

  local temp=$(printenv | grep -w $key)

  echo "$temp" >> /tmp/pre_build
}

#Attempt to pull a docker image...
pull_docker_image () {
  local image_url="$1"
  local image_digest="$2"
  local region="${3:-$AWS_REGION}"
  local account="${4:-$AWS_ACCOUNT_ID}"

  echo "Logging into docker for the \"$region\" region..."
  aws --region "$region" ecr get-login-password | docker login --username "AWS" --password-stdin "$account.dkr.ecr.$region.amazonaws.com"
  check_aws_status $?

  #Try to pull an image with the same GIT tag.
  #NOTE: We could also list out the images and see if the tag exits, but doing a pull makes sure there aren't issues with the image.
  docker pull "$image_url@$image_digest"

  if [ $? -ne 0 ]; then
    echo "No docker image with tag \"$image_digest\" exists..."
    RUN_BUILD="true"
  else
    echo "A docker image with tag \"$image_digest\" exists..."
    RUN_BUILD="false"
  fi

}

retrieve_github_latest_release () {
  local full_path="repos/$GITHUB_ORGANIZATION/$GITHUB_REPOSITORY/releases/latest"

  local tag=$(curl -s -X GET https://api.github.com/$full_path \
  -H "Accept: application/vnd.github.v3+json" \
  -H "Authorization: token $GITHUB_TOKEN" | jq -r .tag_name)

  if [ -z "$tag" ] || [ "$tag" = "null" ]; then
      echo "none"
  else
      echo "$tag"
  fi
}

#------------------------------------------------------------------------
# END: Declare some functions
#------------------------------------------------------------------------

#------------------------------------------------------------------------
# BEGIN: Check for prerequisite commands
#------------------------------------------------------------------------

check_cmd_exists "aws"

check_cmd_exists "curl"

check_cmd_exists "docker"

#------------------------------------------------------------------------
# END: Check for prerequisite commands
#------------------------------------------------------------------------

#------------------------------------------------------------------------
# BEGIN: Set a number of variables
#------------------------------------------------------------------------

if [ -z "$APP_BASE_FOLDER" ]; then
  echo "No application version was set, so not changing directory..."
else
  echo "Application version was set, changing directory..."
  cd "$CODEBUILD_SRC_DIR/$APP_BASE_FOLDER" || exit 1
fi

if [ -f "$CODEBUILD_SRC_DIR/$GIT_METADATA_FILE" ]; then
  echo "The \"$GIT_METADATA_FILE\" file exists."
else
  echo "The \"$GIT_METADATA_FILE\" file does not exist and is required in order to proceed."
  exit 1
fi

echo "Retrieve the GitHub organization..."
GITHUB_ORGANIZATION=$(cat "$CODEBUILD_SRC_DIR/$GIT_METADATA_FILE" | jq -r '.organization')

echo "Retrieve the GitHub repository..."
GITHUB_REPOSITORY=$(cat "$CODEBUILD_SRC_DIR/$GIT_METADATA_FILE" | jq -r '.repository')

echo "Retrieve the GitHub repository..."
GITHUB_PREV_RELEASE=$(retrieve_github_latest_release)

echo "Retrieve the ECR image git tag..."
GITHUB_COMMIT=$(aws --region "$AWS_REGION" ecr describe-images --repository-name "$IMAGE_REPO_NAME" --image-ids imageDigest="$AWS_ECR_IMAGE_DIGEST" --output text --query 'imageDetails[].imageTags[?contains(@, `git-`)]' | cut -c5-44)

check_variable "$GITHUB_COMMIT" "git commit"

echo "Retrive the ECR image version tag..."
ECR_VERSION=$(aws --region "$AWS_REGION" ecr describe-images --repository-name "$IMAGE_REPO_NAME" --image-ids imageDigest="$AWS_ECR_IMAGE_DIGEST" --output text --query 'imageDetails[].imageTags[?contains(@, `version-`)]' | cut -d- -f2)

check_variable "$GITHUB_ORGANIZATION" "GitHub organization"

check_variable "$GITHUB_REPOSITORY" "GitHub repository"

check_variable "$GITHUB_PREV_RELEASE" "GitHub previous release"

check_variable "$GITHUB_COMMIT" "git commit"

check_variable "$ECR_VERSION" "ECR version"

#Regional docker URL...
FIRST_REGION_DOCKER_URL=$(build_docker_url "$AWS_ACCOUNT_ID" "$AWS_REGION" "$IMAGE_REPO_NAME")

if [ "$AWS_SECOND_REGION" = "NONE" ]; then
  echo "The second region was not set, so not building the docker URL for the second region."
  SECOND_REGION_DOCKER_URL="NONE"
else
  SECOND_REGION_DOCKER_URL=$(build_docker_url "$AWS_ACCOUNT_ID" "$AWS_SECOND_REGION" "$IMAGE_REPO_NAME")
fi

#Production docker URL...
if [ -z "$AWS_ECR_PROD_ACCOUNT_ID" ]; then
  echo "No ECR production Account ID was passed in, so not building the docker URL(s) for production."
  PROD_FIRST_REGION_DOCKER_URL="NONE"
else
  PROD_FIRST_REGION_DOCKER_URL=$(build_docker_url "$AWS_ECR_PROD_ACCOUNT_ID" "$AWS_REGION" "$IMAGE_REPO_NAME")
  if [ "$AWS_SECOND_REGION" = "NONE" ]; then
    echo "The second region was not set, so not building the production docker URL for the second region."
    PROD_SECOND_REGION_DOCKER_URL="NONE"
  else
    PROD_SECOND_REGION_DOCKER_URL=$(build_docker_url "$AWS_ECR_PROD_ACCOUNT_ID" "$AWS_SECOND_REGION" "$IMAGE_REPO_NAME")
  fi
fi

#General environment variables...
echo "First region docker URL: $FIRST_REGION_DOCKER_URL"
echo "Second region docker URL: $SECOND_REGION_DOCKER_URL"
echo "Production first region docker URL: $PROD_FIRST_REGION_DOCKER_URL"
echo "Production second region docker URL: $PROD_SECOND_REGION_DOCKER_URL"

#------------------------------------------------------------------------
# END: Set a number of variables
#------------------------------------------------------------------------

#------------------------------------------------------------------------
# BEGIN: Check if docker images already exist
#------------------------------------------------------------------------

echo "Pull the specific Docker image that we want to tag from the \"$AWS_REGION\" region..."
pull_docker_image "$FIRST_REGION_DOCKER_URL" "$AWS_ECR_IMAGE_DIGEST" "$AWS_REGION"

if [ "$AWS_SECOND_REGION" = "NONE" ]; then
  echo "The second region wasn't set, so not going to check that region..."
else
  echo "Pull the specific Docker image that we want to tag from the \"$AWS_SECOND_REGION\" region..."
  pull_docker_image "$SECOND_REGION_DOCKER_URL" "$AWS_ECR_IMAGE_DIGEST" "$AWS_SECOND_REGION"
fi

#Production docker URL...
if [ -z "$AWS_ECR_PROD_ACCOUNT_ID" ]; then
  echo "No ECR production Account ID was passed in, so not pulling a Docker image for production."
  PROD_FIRST_REGION_DOCKER_URL="NONE"
else
  pull_docker_image "$PROD_FIRST_REGION_DOCKER_URL" "$AWS_ECR_IMAGE_DIGEST" "$AWS_REGION" "$AWS_ECR_PROD_ACCOUNT_ID"
  if [ "$AWS_SECOND_REGION" = "NONE" ]; then
    echo "The second region was not set, so not pulling a Docker image for production in the second region."
    PROD_SECOND_REGION_DOCKER_URL="NONE"
  else
    pull_docker_image "$PROD_SECOND_REGION_DOCKER_URL" "$AWS_ECR_IMAGE_DIGEST"  "$AWS_SECOND_REGION" "$AWS_ECR_PROD_ACCOUNT_ID"
  fi
fi

#------------------------------------------------------------------------
# END: Check if docker images already exist
#------------------------------------------------------------------------

#------------------------------------------------------------------------
# BEGIN: Export variables to share with other shell scripts
#------------------------------------------------------------------------

export_variable "DATETIME_ET"
export_variable "ECR_VERSION"
export_variable "GITHUB_ORGANIZATION"
export_variable "GITHUB_REPOSITORY"
export_variable "GITHUB_PREV_RELEASE"
export_variable "GITHUB_COMMIT"
export_variable "FIRST_REGION_DOCKER_URL"
export_variable "SECOND_REGION_DOCKER_URL"
export_variable "PROD_FIRST_REGION_DOCKER_URL"
export_variable "PROD_SECOND_REGION_DOCKER_URL"

#------------------------------------------------------------------------
# END: Export variables to share with other shell scripts
#------------------------------------------------------------------------