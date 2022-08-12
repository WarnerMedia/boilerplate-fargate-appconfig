#!/bin/sh
#Only dashisms allowed (https://wiki.archlinux.org/index.php/Dash).

echo "Build Started on $(date)"

#------------------------------------------------------------------------
# BEGIN: Set some default variables and files
#------------------------------------------------------------------------

#Global variables.
GIT_METADATA_FILE="git-metadata.json"

#------------------------------------------------------------------------
# END: Set some default variables and files
#------------------------------------------------------------------------

#------------------------------------------------------------------------
# BEGIN: Declare some functions
#------------------------------------------------------------------------

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

#------------------------------------------------------------------------
# END: Declare some functions
#------------------------------------------------------------------------

#------------------------------------------------------------------------
# BEGIN: Set a number of variables
#------------------------------------------------------------------------

if [ -f "$CODEBUILD_SRC_DIR/$GIT_METADATA_FILE" ]; then
  echo "The \"$GIT_METADATA_FILE\" file exists."
else
  echo "The \"$GIT_METADATA_FILE\" file does not exist and is required in order to proceed."
  exit 1
fi

#Set some git variables...
echo "Get the remote origin URL..."
GIT_REMOTE_URL=$(cat "$CODEBUILD_SRC_DIR/$GIT_METADATA_FILE" | jq -r '.remoteUrl')

echo "Get the git branch..."
GIT_BRANCH=$(cat "$CODEBUILD_SRC_DIR/$GIT_METADATA_FILE" | jq -r '.branch')

echo "Get the git full revision..."
GIT_FULL_REVISION=$(cat "$CODEBUILD_SRC_DIR/$GIT_METADATA_FILE" | jq -r '.fullRevision')

echo "Retrieve the GitHub organization..."
GITHUB_ORGANIZATION=$(cat "$CODEBUILD_SRC_DIR/$GIT_METADATA_FILE" | jq -r '.organization')

echo "Retrieve the GitHub repository..."
GITHUB_REPOSITORY=$(cat "$CODEBUILD_SRC_DIR/$GIT_METADATA_FILE" | jq -r '.repository')

check_variable "$GIT_REMOTE_URL" "git remote URL"

check_variable "$GIT_BRANCH" "git branch"

check_variable "$GIT_FULL_REVISION" "git full revision"

check_variable "$GITHUB_ORGANIZATION" "GitHub organization"

check_variable "$GITHUB_REPOSITORY" "GitHub repository"

#------------------------------------------------------------------------
# END: Set a number of variables
#------------------------------------------------------------------------

#------------------------------------------------------------------------
# BEGIN: Main Logic
#------------------------------------------------------------------------

if [ -n "$APP_BASE_FOLDER" ]; then
  cd "$CODEBUILD_SRC_DIR/$APP_BASE_FOLDER" || exit 1;
fi

echo "Run the security tests..."
npm run test-security

#------------------------------------------------------------------------
# END: Main Logic
#------------------------------------------------------------------------