#!/bin/sh
#Only dashisms allowed (https://wiki.archlinux.org/index.php/Dash).

#------------------------------------------------------------------------
# BEGIN: Set some default variables and files
#------------------------------------------------------------------------

#Global variables.
COMPARE_FOLDER="compare"
OUTPUT_FILE_FOLDER="tmp"
ZIP_FOLDER="archive"
GIT_METADATA_FILE="git-metadata.json"
BASE_LIST_PATH="env/cfn/codebuild/orchestrator/"

#Get the soure file base (sans extension)
BUILD_FILE_BASE=$(echo "$BUILD_ZIP_FILE" | rev | cut -d. -f2- | rev)
ENV_FILE_BASE=$(echo "$ENV_ZIP_FILE" | rev | cut -d. -f2- | rev)
IAC_FILE_BASE=$(echo "$IAC_ZIP_FILE" | rev | cut -d. -f2- | rev)
SERVICE_FILE_BASE=$(echo "$SERVICE_ZIP_FILE" | rev | cut -d. -f2- | rev)
TEST_FILE_BASE=$(echo "$TEST_ZIP_FILE" | rev | cut -d. -f2- | rev)
SETUP_FILE_BASE=$(echo "$SETUP_ZIP_FILE" | rev | cut -d. -f2- | rev)

#Lists of files to include.
BUILD_INCLUDE_LIST="${BASE_LIST_PATH}${BUILD_FILE_BASE}_include.list"
ENV_INCLUDE_LIST="${BASE_LIST_PATH}${ENV_FILE_BASE}_include.list"
IAC_INCLUDE_LIST="${BASE_LIST_PATH}${IAC_FILE_BASE}_include.list"
SERVICE_INCLUDE_LIST="${BASE_LIST_PATH}${SERVICE_FILE_BASE}_include.list"
TEST_INCLUDE_LIST="${BASE_LIST_PATH}${TEST_FILE_BASE}_include.list"
SETUP_INCLUDE_LIST="${BASE_LIST_PATH}${SETUP_FILE_BASE}_include.list"

#Lists of files to exclude.
BUILD_EXCLUDE_LIST="${BASE_LIST_PATH}${BUILD_FILE_BASE}_exclude.list"
ENV_EXCLUDE_LIST="${BASE_LIST_PATH}${ENV_FILE_BASE}_exclude.list"
IAC_EXCLUDE_LIST="${BASE_LIST_PATH}${IAC_FILE_BASE}_exclude.list"
SERVICE_EXCLUDE_LIST="${BASE_LIST_PATH}${SERVICE_FILE_BASE}_exclude.list"
TEST_EXCLUDE_LIST="${BASE_LIST_PATH}${TEST_FILE_BASE}_exclude.list"
SETUP_EXCLUDE_LIST="${BASE_LIST_PATH}${SETUP_FILE_BASE}_exclude.list"

#------------------------------------------------------------------------
# END: Set some default variables and files
#------------------------------------------------------------------------

#------------------------------------------------------------------------
# BEGIN: Declare some functions
#------------------------------------------------------------------------

#Check if the AWS command was successful.
check_status () {
  #The $? variable always contains the status code of the previously run command.
  #We can either pass in $? or this function will use it as the default value if nothing is passed in.
  local prev=${1:-$?}
  local command="$2"

  if [ $prev -eq 0 ]; then
    echo "The $command command has succeeded."
  else
    echo "The $command command has failed."
    exit 1
  fi
}

#The following function is used when an option has a value.
check_option () {
  local key="$1"
  local value="$2"

  #Check if we have an empty value.
  if [ -z "$value" ] || [ "$(echo "$value" | cut -c1-1)" = "-" ]; then
    echo "Error: Missing value for argument \"$key\"."
    exit 64
  fi

  #Since none of the above conditions were met, we assume we have a valid value.
  SHIFT_COUNT=2
  return 0
}

#Compare two zip files...
#NOTE: zipcmp must be used for the comparison because zip creation metadata will change MD5 hashes.
compare_zip_file () {
  local s3_bucket="$1"
  local project_name="$2"
  local output_folder="$3"
  local compare_folder="$4"
  local zip_folder="$5"
  local zip_filename="$6"
  local codepipeline="$7"
  local region="$8"
  local add_git_info="$9"
  local pushfile="false"
  local status="fail"

  echo "Try to get \"$zip_filename\" compare ZIP file from S3..."
  aws s3 cp "s3://$s3_bucket/$project_name/compare/$zip_filename" "/$output_folder/$compare_folder/$zip_filename" --region "$region"

  #Doing a comparison to see if we should push the new ZIP file or not.
  echo "Checking if ZIP file \"$zip_filename\" exists on S3..."
  if [ -e "/$output_folder/$compare_folder/$zip_filename" ]; then

    #Check if there is a difference between ZIP files.
    echo "Doing zipcmp compare..."
    zipcmp "/$output_folder/$zip_folder/$zip_filename" "/$output_folder/$compare_folder/$zip_filename"

    #If the exit code was 1, then we know there were changes to the ZIP file and it should be uploaded.
    if [ $? -eq 1 ]; then
      echo "Changes to ZIP file \"$zip_filename\"...will push to S3."
      pushfile="true"
    else
      echo "No changes to ZIP file \"$zip_filename\"...will not push ZIP file."
    fi
  else
    echo "ZIP file \"$zip_filename\" doesn't exist on S3...will push to S3."
    pushfile="true"
  fi

  #Push the file if the flag was set to "true" at some point in this run through the loop.
  if [ "$pushfile" = "true" ]; then

    status=$(push_file "/$output_folder/$zip_folder/$zip_filename" "s3://$s3_bucket/$project_name/compare/$zip_filename" "$region")

    echo "Current status is: $status"

    if [ "$status" = "success" ]; then
      echo "Successfully pushed compare file to S3."

      if [ "$add_git_info" = "true" ]; then
        create_deployment_zip "/$output_folder/$zip_folder/$zip_filename"
      fi

      status=$(push_file "/$output_folder/$zip_folder/$zip_filename" "s3://$s3_bucket/$project_name/base/$zip_filename" "$region")

      if [ "$status" = "success" ]; then
        echo "Successfully pushed deployment file to S3."
        start_codepipeline "$codepipeline" "$region"
      else
        echo "Failed to push deployment file to S3."
        exit 1
      fi
    else
      echo "Failed to push compare file to S3."
      exit 1
    fi
  fi
}

#Create a ZIP archive file...
create_compare_zip () {
  local app_base_folder="$1"
  local output_folder="$2"
  local zip_folder="$3"
  local zip_filename="$4"
  local exclude_list="$5"
  local include_list="$6"

  if [ -n "$app_base_folder" ]; then
    exclude_list="$app_base_folder/$exclude_list"
    include_list="$app_base_folder/$include_list"
  fi

  echo "Zipping up files for the \"$zip_filename\" archive..."
  mkdir -p "/$output_folder/$zip_folder"
  zip -X -r "/$output_folder/$zip_folder/$zip_filename" -x@"$exclude_list" . -i@"$include_list"
}

create_deployment_zip () {
  local source_zip="$1"
  local filename="${2:-$GIT_METADATA_FILE}"

  jq -n --arg remoteUrl "$GIT_REMOTE_URL" \
        --arg fullRevision "$GIT_FULL_REVISION" \
        --arg shortRevision "$GIT_SHORT_REVISION" \
        --arg branch "$GIT_BRANCH" \
        --arg message "$GIT_COMMIT_MESSAGE" \
        --arg authorDate "$GIT_COMMIT_DATE" \
        --arg authorName "$GIT_COMMIT_AUTHOR_NAME" \
        --arg authorEmail "$GIT_COMMIT_AUTHOR_EMAIL" \
        --arg organization "$GITHUB_ORGANIZATION" \
        --arg repository "$GITHUB_REPOSITORY" \
        '{"remoteUrl":$remoteUrl,"fullRevision":$fullRevision,"shortRevision":$shortRevision,"branch":$branch,"commitMessage":$message,"authorDate":$authorDate,"authorName":$authorName,"authorEmail":$authorEmail,"organization":$organization,"repository":$repository}' > "./$filename"

  zip -X -r "$source_zip" "./$filename"
}

#Check if required commands exist...
exists () {
  command -v "$1" >/dev/null 2>&1
}

push_file () {
  local source="$1"
  local destination="$2"
  local region="$3"

  aws s3 cp "$source" "$destination" --region "$region" --quiet
  if [ $? -ne 0 ]; then
    echo "fail"
  else
    echo "success"
  fi
}

push_regular_environment () {

  echo "Creating the various ZIP files..."

  #Create Setup ZIP file.
  create_compare_zip  "$APP_BASE_FOLDER" "$OUTPUT_FILE_FOLDER" "$ZIP_FOLDER" "$SETUP_ZIP_FILE" "$SETUP_EXCLUDE_LIST" "$SETUP_INCLUDE_LIST"

  #Create build ZIP file.
  create_compare_zip  "$APP_BASE_FOLDER" "$OUTPUT_FILE_FOLDER" "$ZIP_FOLDER" "$BUILD_ZIP_FILE" "$BUILD_EXCLUDE_LIST" "$BUILD_INCLUDE_LIST"

  #Create environment ZIP file.
  create_compare_zip  "$APP_BASE_FOLDER" "$OUTPUT_FILE_FOLDER" "$ZIP_FOLDER" "$ENV_ZIP_FILE" "$ENV_EXCLUDE_LIST" "$ENV_INCLUDE_LIST"

  #Create IaC ZIP file.
  create_compare_zip  "$APP_BASE_FOLDER" "$OUTPUT_FILE_FOLDER" "$ZIP_FOLDER" "$IAC_ZIP_FILE" "$IAC_EXCLUDE_LIST" "$IAC_INCLUDE_LIST"

  #Create service ZIP file.
  create_compare_zip  "$APP_BASE_FOLDER" "$OUTPUT_FILE_FOLDER" "$ZIP_FOLDER" "$SERVICE_ZIP_FILE" "$SERVICE_EXCLUDE_LIST" "$SERVICE_INCLUDE_LIST"

  #Create test ZIP file.
  create_compare_zip  "$APP_BASE_FOLDER" "$OUTPUT_FILE_FOLDER" "$ZIP_FOLDER" "$TEST_ZIP_FILE" "$TEST_EXCLUDE_LIST" "$TEST_INCLUDE_LIST"

  echo "Comparing the various ZIP files..."

  #Check setup ZIP file.
  compare_zip_file "$S3_BUCKET" "$S3_FOLDER" "$OUTPUT_FILE_FOLDER" "$COMPARE_FOLDER" "$ZIP_FOLDER" "$SETUP_ZIP_FILE" "$SETUP_CODEPIPELINE" "$AWS_REGION" "false"

  #Check service ZIP file.
  compare_zip_file "$S3_BUCKET" "$S3_FOLDER" "$OUTPUT_FILE_FOLDER" "$COMPARE_FOLDER" "$ZIP_FOLDER" "$SERVICE_ZIP_FILE" "NONE" "$AWS_REGION" "true"

  #Check environment ZIP file.
  compare_zip_file "$S3_BUCKET" "$S3_FOLDER" "$OUTPUT_FILE_FOLDER" "$COMPARE_FOLDER" "$ZIP_FOLDER" "$ENV_ZIP_FILE" "NONE" "$AWS_REGION" "true"

  #Check test ZIP file.
  compare_zip_file "$S3_BUCKET" "$S3_FOLDER" "$OUTPUT_FILE_FOLDER" "$COMPARE_FOLDER" "$ZIP_FOLDER" "$TEST_ZIP_FILE" "NONE" "$AWS_REGION" "true"

  #Check IaC ZIP file.
  compare_zip_file "$S3_BUCKET" "$S3_FOLDER" "$OUTPUT_FILE_FOLDER" "$COMPARE_FOLDER" "$ZIP_FOLDER" "$IAC_ZIP_FILE" "$IAC_CODEPIPELINE" "$AWS_REGION" "true"

  #Check build ZIP file.
  compare_zip_file "$S3_BUCKET" "$S3_FOLDER" "$OUTPUT_FILE_FOLDER" "$COMPARE_FOLDER" "$ZIP_FOLDER" "$BUILD_ZIP_FILE" "$BUILD_CODEPIPELINE" "$AWS_REGION" "true"

}

push_unstable_environment () {
  local dev_push_flag="success"

  echo "Pushing the ZIP files to the \"$UNSTABLE_BRANCH\" environment..."

  #Create service ZIP file.
  create_compare_zip  "$APP_BASE_FOLDER" "$OUTPUT_FILE_FOLDER" "$UNSTABLE_BRANCH" "$SERVICE_ZIP_FILE" "$SERVICE_EXCLUDE_LIST" "$SERVICE_INCLUDE_LIST"
  create_deployment_zip "/$OUTPUT_FILE_FOLDER/$UNSTABLE_BRANCH/$SERVICE_ZIP_FILE"
  if [ "$(push_file "/$OUTPUT_FILE_FOLDER/$UNSTABLE_BRANCH/$SERVICE_ZIP_FILE" "s3://$S3_BUCKET/$S3_FOLDER/$UNSTABLE_BRANCH/init/$SERVICE_ZIP_FILE" "$AWS_REGION")" = "fail" ]; then
    dev_push_flag="service"
  fi

  #Create environment ZIP file.
  create_compare_zip  "$APP_BASE_FOLDER" "$OUTPUT_FILE_FOLDER" "$UNSTABLE_BRANCH" "$ENV_ZIP_FILE" "$ENV_EXCLUDE_LIST" "$ENV_INCLUDE_LIST"
  create_deployment_zip "/$OUTPUT_FILE_FOLDER/$UNSTABLE_BRANCH/$ENV_ZIP_FILE"
  if [ "$(push_file "/$OUTPUT_FILE_FOLDER/$UNSTABLE_BRANCH/$ENV_ZIP_FILE" "s3://$S3_BUCKET/$S3_FOLDER/$UNSTABLE_BRANCH/init/$ENV_ZIP_FILE" "$AWS_REGION")" = "fail" ]; then
    dev_push_flag="environment"
  fi

  #Create test ZIP file.
  create_compare_zip  "$APP_BASE_FOLDER" "$OUTPUT_FILE_FOLDER" "$UNSTABLE_BRANCH" "$TEST_ZIP_FILE" "$TEST_EXCLUDE_LIST" "$TEST_INCLUDE_LIST"
  create_deployment_zip "/$OUTPUT_FILE_FOLDER/$UNSTABLE_BRANCH/$TEST_ZIP_FILE"
  if [ "$(push_file "/$OUTPUT_FILE_FOLDER/$UNSTABLE_BRANCH/$TEST_ZIP_FILE" "s3://$S3_BUCKET/$S3_FOLDER/$UNSTABLE_BRANCH/init/$TEST_ZIP_FILE" "$AWS_REGION")" = "fail" ]; then
    dev_push_flag="test"
  fi

  #Create build ZIP file.
  create_compare_zip  "$APP_BASE_FOLDER" "$OUTPUT_FILE_FOLDER" "$UNSTABLE_BRANCH" "$BUILD_ZIP_FILE" "$BUILD_EXCLUDE_LIST" "$BUILD_INCLUDE_LIST"
  create_deployment_zip "/$OUTPUT_FILE_FOLDER/$UNSTABLE_BRANCH/$BUILD_ZIP_FILE"
  if [ "$(push_file "/$OUTPUT_FILE_FOLDER/$UNSTABLE_BRANCH/$BUILD_ZIP_FILE" "s3://$S3_BUCKET/$S3_FOLDER/$UNSTABLE_BRANCH/init/$BUILD_ZIP_FILE" "$AWS_REGION")" = "fail" ]; then
    dev_push_flag="build"
  fi

  if [ "$dev_push_flag" = "success" ]; then
    start_codepipeline "$BUILD_UNSTABLE_CODEPIPELINE" "$AWS_REGION"
  else
    echo "Failed to push \"$dev_push_flag\" ZIP file to S3."
    exit 1
  fi
}

#Because of how CodeBuild does the checkout from GitHub, we have to get creative as to how to get the correct branch name.
retrieve_github_branch () {
  local branch=""
  local trigger="none"

  if [ -n "$CODEBUILD_WEBHOOK_TRIGGER" ]; then
    case "$(echo "$CODEBUILD_WEBHOOK_TRIGGER" | cut -c1-2)" in
      "br") trigger="branch" ; branch=$(echo "$CODEBUILD_WEBHOOK_TRIGGER" | cut -c8-) ;;
      "pr") trigger="pull-request" ;;
      "ta") trigger="tag" ;;
      *) trigger="unknown" ;;
    esac
  fi

  if [ "$trigger" = "branch" ]; then
    #This came from a branch trigger, so output the branch name we parsed.
    echo "$branch"
  elif [ -n "$CODEBUILD_SOURCE_VERSION" ]; then
    #This CodeBuild was triggered directly, most-likely using a branch.
    echo "$CODEBUILD_SOURCE_VERSION"
  else
    #If all else fails, try to get the branch name from git directly.
    git name-rev --name-only HEAD
  fi
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

start_codepipeline () {
  local name="$1"
  local region="$2"
  local query="pipelines[?contains(name, \`$name\`)].name"
  local compare=""

  echo "Check if the \"$name\" CodePipeline exists..."

  compare=$(aws --region "$region" codepipeline list-pipelines --output text --query "$query")
  check_status $? "AWS CLI"

  if [ "$name" = "$compare" ]; then
    echo "The \"$name\" CodePipeline exists, starting CodePipeline..."
    aws --region "$region" codepipeline start-pipeline-execution --name "$name"
    check_status $? "AWS CLI"
  else
    echo "The \"$name\" CodePipeline doesn't exist in this environment, so nothing to trigger."
  fi
}

#------------------------------------------------------------------------
# END: Declare some functions
#------------------------------------------------------------------------

#------------------------------------------------------------------------
# BEGIN: Set Git Variables
#------------------------------------------------------------------------

#Set some git variables...
echo "Retrieve the remote origin URL..."
GIT_REMOTE_URL=$(git config --local remote.origin.url)

echo "Retrieve the full git revision..."
GIT_FULL_REVISION=$(git rev-parse HEAD)
check_status $? "git"

echo "Retrieve the short git revision..."
GIT_SHORT_REVISION=$(git rev-parse --short HEAD)
check_status $? "git"

echo "Retrieve the git branch..."
echo "CODEBUILD_WEBHOOK_TRIGGER: $CODEBUILD_WEBHOOK_TRIGGER"
echo "CODEBUILD_SOURCE_VERSION: $CODEBUILD_SOURCE_VERSION"
GIT_BRANCH=$(retrieve_github_branch)

echo "Retrieve the GitHub commit message..."
GIT_COMMIT_MESSAGE=$(git log -1 --pretty=%B)
check_status $? "git"

echo "Retrieve the GitHub commit date..."
GIT_COMMIT_DATE=$(git log -1 --pretty=%cd --date=local)
check_status $? "git"

echo "Retrieve the GitHub commit author name..."
GIT_COMMIT_AUTHOR_NAME=$(git log -1 --pretty=%an)
check_status $? "git"

echo "Retrieve the GitHub commit auther e-mail..."
GIT_COMMIT_AUTHOR_EMAIL=$(git log -1 --pretty=%ae)
check_status $? "git"

echo "Retrieve the GitHub organization..."
GITHUB_ORGANIZATION=$(retrieve_github_organization "$GIT_REMOTE_URL")
check_status $? "git"

echo "Retrieve the GitHub repository..."
GITHUB_REPOSITORY=$(retrieve_github_repository "$GIT_REMOTE_URL")
check_status $? "git"

#------------------------------------------------------------------------
# END: Set Git Variables
#------------------------------------------------------------------------

#------------------------------------------------------------------------
# BEGIN: Main Build Logic
#------------------------------------------------------------------------

echo "Check if AWS CLI is installed..."
if exists aws; then
  echo "The command \"aws\" exists..."
  echo "Check the version..."
  aws --version
else
  echo "Your system does not have \"aws\" CLI installed.  Please get this command installed."
  exit 1
fi

echo "Check if jq is installed..."
if exists jq; then
  echo "The command \"jq\" exists..."
  echo "Check the version..."
  jq -V
else
  echo "Your system does not have \"jq\" CLI installed.  Please get this command installed."
  exit 1
fi

echo "Check if zip is installed..."
if exists zip; then
  echo "The command \"zip\" exists..."
  echo "Check the version..."
  zip --version
else
  echo "Your system does not have \"zip\".  Please get this command installed."
  exit 1
fi

echo "Check if zipcmp is installed..."
if exists zipcmp; then
  echo "The command \"zipcmp\" exists..."
  echo "Check the version..."
  zipcmp -V
else
  echo "Your system does not have \"zipcmp\".  Please get this command installed."
  exit 1
fi

#Output some variables
echo "Git full revision is: $GIT_FULL_REVISION"
echo "Git short revision is: $GIT_SHORT_REVISION"
echo "Git branch name is: $GIT_BRANCH"
echo "GitHub organization: $GITHUB_ORGANIZATION"
echo "GitHub repository: $GITHUB_REPOSITORY"

echo "Do a directory listing..."
ls -altr

#Loop through the arguments.
while [ $# -gt 0 ]; do
  case "$1" in
    # Required Arguments
    -b|--bucket)  check_option "$1" "$2"; S3_BUCKET="$2"; shift $SHIFT_COUNT;;       # S3 bucket ID.
    -f|--folder)  check_option "$1" "$2"; S3_FOLDER="$2"; shift $SHIFT_COUNT;;       # S3 top folder if not deploying to top level of bucket.
    -r|--region)  check_option "$1" "$2"; REGION="$2"; shift $SHIFT_COUNT;;          # AWS region.
    -v|--version) check_option "$1" "$2"; APP_BASE_FOLDER="$2"; shift $SHIFT_COUNT;; # Application Version folder.
    *) echo "Error: Invalid argument \"$1\"" ; exit 64 ;;
  esac
done

#Check to see if we need to push to the dev/unstable environment.
if [ "$UNSTABLE_BRANCH" = "$GIT_BRANCH" ]; then

  push_unstable_environment

else

  push_regular_environment

fi

#------------------------------------------------------------------------
# END: Main Build Logic
#------------------------------------------------------------------------