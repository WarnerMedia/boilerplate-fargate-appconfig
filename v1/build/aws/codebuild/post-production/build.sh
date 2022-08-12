#!/bin/sh
#Only dashisms allowed (https://wiki.archlinux.org/index.php/Dash).

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

check_branch () {
  local owner="$1"
  local repository="$2"
  local token="$3"
  local branch="$4"
  local sha="$5"
  local status="fail"

  echo "Check if the \"$branch\" branch exists..."
  status=$(github_retrieve_branch "$owner" "$repository" "$branch" "$token")

  if [ "$status" = "fail" ]; then
    echo "Create the \"$branch\" branch based on the \"$sha\" SHA."
    github_create_branch "$owner" "$repository" "$token" "$branch" "$sha"
  else
    echo "Update the \"$branch\" branch based on the \"$sha\" SHA."
    github_update_branch "$owner" "$repository" "$branch" "$token" "$sha"
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

check_status () {
  #The $? variable always contains the status code of the previously run command.
  #We can either pass in $? or this function will use it as the default value if nothing is passed in.
  local prev=${1:-$?}
  local command="$2"

  if [ $prev -ne 0 ]; then
    echo "The $command command has failed."
    #Kill the build script so that we go no further.
    exit 1
  fi
}

ecr_retrieve_git_tag () {
  local repository="$1"
  local digest="$2"
  local region="${3:-$AWS_REGION}"
  local sha="NONE"

  local sha=$(aws --region "$region" ecr describe-images --repository-name "$repository" --image-ids imageDigest="$digest" --output text --query 'imageDetails[].imageTags[?contains(@, `git-`)]' | cut -c5-)
  check_status $? "AWS CLI"

  if [ $(echo -n "$sha" | wc -m) -eq 40 ]; then
    echo "Updating the full git SHA to \"$sha\"..."
    GIT_FULL_REVISION="$sha"
    GIT_SHORT_REVISION=$(echo "$sha" | cut -c1-7)
  else
    echo "Didn't get a valid SHA back from GitHub..."
    exit 1
  fi
}

#Check if required commands exist...
exists () {
  command -v "$1" >/dev/null 2>&1
}

github_create_branch () {
  local owner="$1"
  local repository="$2"
  local token="$3"
  local branch="$4"
  local sha="$5"
  local response="404"

  response=$(curl -s -o /dev/null -w "%{http_code}" -X POST https://api.github.com/repos/$owner/$repository/git/refs \
  -H "Authorization: token $token" \
  -d @- << EOF
{
  "ref": "refs/heads/$branch",
  "sha": "$sha"
}
EOF
)

  check_status $? "GitHub branch create"

  if [ "$response" = "201" ]; then
    echo "success"
  else
    echo "fail"
  fi
}

github_retrieve_branch () {
  local owner="$1"
  local repository="$2"
  local branch="$3"
  local token="$4"
  local response="404"

  response=$(curl -s -o /dev/null -w "%{http_code}" -X GET https://api.github.com/repos/$owner/$repository/git/ref/heads/$branch -H "Authorization: token $token")

  check_status $? "GitHub retrieve branch"

  if [ "$response" = "200" ]; then
    echo "success"
  else
    echo "fail"
  fi
}

github_delete_branch () {
  local owner="$1"
  local repository="$2"
  local branch="$3"
  local token="$4"
  local sha="$5"
  local response="404"

  response=$(curl -s -o /dev/null -w "%{http_code}" -X DELETE https://api.github.com/repos/$owner/$repository/git/refs/heads/$branch \
  -H "Authorization: token $token" \
  -d @- << EOF
{
  "sha": "$sha",
  "force": true
}
EOF
)

  check_status $? "GitHub branch delete"

  if [ "$response" = "204" ]; then
    echo "success"
  else
    echo "fail"
  fi
}

github_update_branch () {
  local owner="$1"
  local repository="$2"
  local branch="$3"
  local token="$4"
  local sha="$5"
  local response="404"

  echo "Update the \"$branch\" branch with the \"$sha\" SHA..."

  local response=$(curl -s -o /dev/null -w "%{http_code}" -X PATCH https://api.github.com/repos/$owner/$repository/git/refs/heads/$branch \
  -H "Authorization: token $token" \
  -d @- << EOF
{
  "sha": "$sha",
  "force": true
}
EOF
)

  check_status $? "GitHub branch update"

  if [ "$response" = "200" ]; then
    echo "success"
  else
    echo "fail"
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

#------------------------------------------------------------------------
# END: Check for prerequisite commands
#------------------------------------------------------------------------

#------------------------------------------------------------------------
# BEGIN: Set a number of variables
#------------------------------------------------------------------------

if [ -f "$CODEBUILD_SRC_DIR/$GIT_METADATA_FILE" ]; then
  echo "The \"$GIT_METADATA_FILE\" file exists."
else
  echo "The \"$GIT_METADATA_FILE\" file does not exist and is required in order to proceed.."
  exit 1
fi

#Set some git variables...
echo "Get the remote origin URL..."
GIT_REMOTE_URL=$(cat "$CODEBUILD_SRC_DIR/$GIT_METADATA_FILE" | jq -r '.remoteUrl')

ecr_retrieve_git_tag "$IMAGE_REPO_NAME" "$AWS_ECR_IMAGE_DIGEST" "$AWS_REGION"

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

#------------------------------------------------------------------------
# END: Set a number of variables
#------------------------------------------------------------------------

#------------------------------------------------------------------------
# BEGIN: Main Logic
#------------------------------------------------------------------------

check_branch "$GITHUB_ORGANIZATION" "$GITHUB_REPOSITORY" "$GITHUB_TOKEN" "$UNSTABLE_BRANCH" "$GIT_FULL_REVISION"

#------------------------------------------------------------------------
# END: Main Logic
#------------------------------------------------------------------------