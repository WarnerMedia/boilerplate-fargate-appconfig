#!/bin/sh
#Only dashisms allowed (https://wiki.archlinux.org/index.php/Dash).

echo "Pre-Build Started on $(date)"

#------------------------------------------------------------------------
# BEGIN: Set some default variables and files
#------------------------------------------------------------------------

#Set a default image tag.
DEFAULT_IMAGE_TAG="latest"
RUN_BUILD="false"
UPDATE_PACKAGE_FILE="false"
PACKAGE_FILE_UPDATED="false"
PACKAGE_FILE="package.json"
GIT_METADATA_FILE="git-metadata.json"

#Create a file for transporting variables to other phases.
touch /tmp/pre_build

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

check_docker_image () {
  local repository="$1"
  local current_tag="${2:-$DEFAULT_IMAGE_TAG}"
  local region="${3:-$AWS_REGION}"

  local ecr_tag=$(aws --region "$region" ecr describe-images --repository-name "$repository" --image-ids imageTag="$current_tag" --output text --query 'imageDetails[].imageTags[?contains(@, `version-`)]')
  check_status $? "AWS CLI"

  echo "Check if the \"$current_tag\" tag is equal to the \"$ecr_tag\" tag..."
  if [ "$current_tag" = "$ecr_tag" ]; then
    echo "An image already exists in the ECS Repository with the \"$ecr_tag\" tag in the \"$region\" region."
    RUN_BUILD="false"
    UPDATE_PACKAGE_FILE="true"
  else
    echo "No image exists in the ECS Repository with the \"$current_tag\" tag in the \"$region\" region, so the image will be built."
    RUN_BUILD="true"
    UPDATE_PACKAGE_FILE="false"
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

#Check if the AWS command was successful.
check_status () {
  #The $? variable always contains the status code of the previously run command.
  #We can either pass in $? or this function will use it as the default value if nothing is passed in.
  local prev=${1:-$?}
  local command="$2"

  if [ $prev -eq 0 ]; then
    echo "The $command command has succeeded."
    #Set the build tag to "true" since the build has succeeded.
    RUN_BUILD="true"
  else
    echo "The $command command has failed."
    #Set the build tag to "false" since the build has failed.
    RUN_BUILD="false"
    export_variable "RUN_BUILD"
    #Kill the build script so that we go no further.
    exit 1
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

retrieve_github_organization () {
  local remote="$1"

  if [ "$(echo "$remote" | cut -c1-15)" = "git@github.com:" ]; then
    echo "$remote" | cut -c16- | cut -d/ -f1
  elif [ "$(echo "$remote" | cut -c1-19)" = "https://github.com/" ]; then
    echo "$remote" | cut -c20- | cut -d/ -f1
  else
    echo "UNKNOWN"
  fi
}

retrieve_github_repository () {
  local remote="$1"

  if [ "$(echo "$remote" | cut -c1-15)" = "git@github.com:" ]; then
    echo "$remote" | cut -c16- | rev | cut -c5- | rev | cut -d/ -f2-
  elif [ "$(echo "$remote" | cut -c1-19)" = "https://github.com/" ]; then
    echo "$remote" | cut -c20- | rev | cut -c5- | rev | cut -d/ -f2-
  else
    echo "UNKNOWN"
  fi
}

update_package_file () {
  local owner="$1"
  local repository="$2"
  local base_folder="$3"
  local filename="$4"
  local token="$5"
  local branch="$6"
  local message="$7"
  local content=$(base64 --wrap=0 ./$filename)
  local sha="NONE"
  local full_path="NONE"
  local put_response="NONE"

  echo "The git branch: $branch"

  if [ -z "$base_folder" ]; then
    echo "No base folder is set, getting the \"$filename\" from the root directory..."
    full_path="repos/$owner/$repository/contents/$filename"
    sha=$(curl -s -X GET https://api.github.com/$full_path?ref=$branch -H "Authorization: token $token" | jq -r .sha)
  else
    echo "Base folder is set, getting the \"$filename\" from the \"$base_folder\" directory..."
    full_path="repos/$owner/$repository/contents/$base_folder/$filename"
    sha=$(curl -s -X GET https://api.github.com/$full_path?ref=$branch -H "Authorization: token $token" | jq -r .sha)
  fi

  check_status $? "GitHub"

  echo "File SHA is: $sha"

  put_response=$(curl -s -X PUT https://api.github.com/$full_path \
  -H "Authorization: token $token" \
  -d @- << EOF
{
  "branch": "$branch",
  "content": "$content",
  "message": "$message",
  "sha": "$sha"
}
EOF
)

  check_status $? "GitHub"

  echo "Get the updated SHA..."
  sha=$(echo "$put_response" | jq -r .commit.sha)

  echo "Updated SHA: $sha"

  if [ $(echo -n "$sha" | wc -m) -eq 40 ]; then
    echo "Updating the full git SHA to \"$sha\"..."
    GIT_FULL_REVISION="$sha"
    GIT_SHORT_REVISION=$(echo "$sha" | cut -c1-7)
  else
    echo "Didn't get a valid SHA back from GitHub..."
    exit 1
  fi

}

update_version () {

  echo "Checking if the Docker image already exists in the \"$AWS_REGION\" region..."
  check_docker_image "$IMAGE_REPO_NAME" "$VERSION_TAG"

  if [ "$AWS_SECOND_REGION" = "NONE" ]; then
    echo "The second region wasn't set, so not going to check that region..."
  else
    echo "Attempting to pull this image to see if it already exists in the \"$AWS_SECOND_REGION\" region..."
    check_docker_image "$IMAGE_REPO_NAME" "$VERSION_TAG" "$AWS_SECOND_REGION"
  fi

  if [ "$UPDATE_PACKAGE_FILE" = "true" ]; then
     PACKAGE_FILE_UPDATED="true"

      echo "Automatically bumping the NPM patch version..."

      TEMP_VERSION=$(npm version patch)
      check_status $? "NPM"

      #Remove the "v" from the version...
      VERSION=$(echo "$TEMP_VERSION" | cut -c2-)

      #Set the version tag...
      if [ "$UNSTABLE_BRANCH" = "$GIT_BRANCH" ]; then
        echo "Adding the \"$GIT_BRANCH\" environment to the version tag..."
        VERSION_TAG="version-$VERSION-$GIT_BRANCH"
      else
        echo "Using the standard version tag..."
        VERSION_TAG="version-$VERSION"
      fi

      #Check again to make sure the version we just set isn't already in use...
      update_version
  fi

}

update_version_tag () {
  #Set the version tag...
  if [ "$UNSTABLE_BRANCH" = "$GIT_BRANCH" ]; then
    echo "Adding the \"$GIT_BRANCH\" environment to the version tag..."
    VERSION_TAG="version-$VERSION-$GIT_BRANCH"
  else
    echo "Using the standard version tag..."
    VERSION_TAG="version-$VERSION"
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

check_cmd_exists "git"

check_cmd_exists "jq"

#------------------------------------------------------------------------
# END: Check for prerequisite commands
#------------------------------------------------------------------------

#------------------------------------------------------------------------
# BEGIN: Set a number of variables
#------------------------------------------------------------------------

#Change the directory to the application directory...
if [ -z "$APP_BASE_FOLDER" ]; then
  echo "No application version was set, so not changing directory..."
else
  cd "$CODEBUILD_SRC_DIR/$APP_BASE_FOLDER" || exit 1
fi

echo "Extract some METADATA from the package.json file..."
NAME=$(cat "$PACKAGE_FILE" | jq -r '.name')
VERSION=$(cat "$PACKAGE_FILE" | jq -r '.version')

echo "Extract the CodePipeline name and CodeBuild ID..."
CURRENT_PIPELINE=$(printf "%s" "$CODEBUILD_INITIATOR" | rev | cut -d/ -f1 | rev)
BUILD_ID=$(printf "%s" "$CODEBUILD_BUILD_ID" | sed "s/.*:\([[:xdigit:]]\{7\}\).*/\1/")

#Check if the git metadata JSON file exists...
if [ -f "$CODEBUILD_SRC_DIR/$GIT_METADATA_FILE" ]; then
  echo "The \"$GIT_METADATA_FILE\" file exists."
else
  echo "The \"$GIT_METADATA_FILE\" file does not exist and is required in order to proceed."
  exit 1
fi

#Set some git variables...
echo "Get the remote origin URL..."
GIT_REMOTE_URL=$(cat "$CODEBUILD_SRC_DIR/$GIT_METADATA_FILE" | jq -r '.remoteUrl')

echo "Get the full git revision..."
GIT_FULL_REVISION=$(cat "$CODEBUILD_SRC_DIR/$GIT_METADATA_FILE" | jq -r '.fullRevision')

echo "Get the short git revision..."
GIT_SHORT_REVISION=$(cat "$CODEBUILD_SRC_DIR/$GIT_METADATA_FILE" | jq -r '.shortRevision')

echo "Get the git branch..."
GIT_BRANCH=$(cat "$CODEBUILD_SRC_DIR/$GIT_METADATA_FILE" | jq -r '.branch')

echo "Retrieve the GitHub organization..."
GITHUB_ORGANIZATION=$(cat "$CODEBUILD_SRC_DIR/$GIT_METADATA_FILE" | jq -r '.organization')

echo "Retrieve the GitHub repository..."
GITHUB_REPOSITORY=$(cat "$CODEBUILD_SRC_DIR/$GIT_METADATA_FILE" | jq -r '.repository')

check_variable "$GIT_REMOTE_URL" "git remote URL"

check_variable "$GIT_FULL_REVISION" "git full revision"

check_variable "$GIT_SHORT_REVISION" "git short revision"

check_variable "$GIT_BRANCH" "git branch"

check_variable "$GITHUB_ORGANIZATION" "GitHub organization"

check_variable "$GITHUB_REPOSITORY" "GitHub repository"

#Set a date variable...
DATETIME_ET=$(TZ="America/New_York" date +"%Y%m%d%H%M%S")

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

#------------------------------------------------------------------------
# END: Set a number of variables
#------------------------------------------------------------------------

#------------------------------------------------------------------------
# BEGIN: Check if docker images already exist and set variables
#------------------------------------------------------------------------

#Update the version tag...
update_version_tag

#Update the version, if needed.
update_version

#Update the version tag...
update_version_tag

#Update the version in GitHub if we had to advance the version...
if [ "$PACKAGE_FILE_UPDATED" = "true" ]; then
  #Update the package.json patch version...
  update_package_file "$GITHUB_ORGANIZATION" "$GITHUB_REPOSITORY" "$APP_BASE_FOLDER" "$PACKAGE_FILE" "$GITHUB_TOKEN" "$GIT_BRANCH" "Automatic patch version update to: $VERSION"
fi

echo "Setting some build tags..."
BUILD_ID_TAG="codebuild-$BUILD_ID"
GIT_REVISION_TAG="git-$GIT_FULL_REVISION" #Need the full hash for advanced git interactions.

#------------------------------------------------------------------------
# END: Check if docker images already exist and set variables
#------------------------------------------------------------------------

#------------------------------------------------------------------------
# BEGIN: Output a number of variables
#------------------------------------------------------------------------

#CodeBuild-specific environment variables...
echo "CodeBuild Source Version: $CODEBUILD_SOURCE_VERSION"

#General environment variables...
echo "Application name is: $NAME"
echo "Application version is: $VERSION"
echo "Build tag is: $BUILD_ID_TAG"
echo "Git revision tag is: $GIT_REVISION_TAG"
echo "Version tag is: $VERSION_TAG"
echo "Initiating CodePipeline is: $CODEBUILD_INITIATOR"
echo "Current CodePipeline name is: $CURRENT_PIPELINE"
echo "Full git revision is: $GIT_FULL_REVISION"
echo "Short git revision is: $GIT_SHORT_REVISION"
echo "Current time in the Eastern Time Zone is: $DATETIME_ET"
echo "First region docker URL: $FIRST_REGION_DOCKER_URL"
echo "Second region docker URL: $SECOND_REGION_DOCKER_URL"
echo "Production first region docker URL: $PROD_FIRST_REGION_DOCKER_URL"
echo "Production second region docker URL: $PROD_SECOND_REGION_DOCKER_URL"

#------------------------------------------------------------------------
# END: Output a number of variables
#------------------------------------------------------------------------

#------------------------------------------------------------------------
# BEGIN: Export variables to share with other shell scripts
#------------------------------------------------------------------------

export_variable "BUILD_ID"
export_variable "BUILD_ID_TAG"
export_variable "CURRENT_PIPELINE"
export_variable "DATETIME_ET"
export_variable "DEFAULT_IMAGE_TAG"
export_variable "FIRST_REGION_DOCKER_URL"
export_variable "GIT_BRANCH"
export_variable "GIT_FULL_REVISION"
export_variable "GIT_REVISION_TAG"
export_variable "GIT_SHORT_REVISION"
export_variable "GITHUB_ORGANIZATION"
export_variable "GITHUB_REPOSITORY"
export_variable "NAME"
export_variable "PROD_FIRST_REGION_DOCKER_URL"
export_variable "PROD_SECOND_REGION_DOCKER_URL"
export_variable "RUN_BUILD"
export_variable "SECOND_REGION_DOCKER_URL"
export_variable "VERSION"
export_variable "VERSION_TAG"

#------------------------------------------------------------------------
# END: Export variables to share with other shell scripts
#------------------------------------------------------------------------