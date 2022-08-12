#!/bin/sh
#Only dashisms allowed (https://wiki.archlinux.org/index.php/Dash).

#Global variables
PROFILE="aws-profile"
REGION="us-east-2"
TEMPLATE="../../../iac/cfn/setup/main.yaml"
CUSTOMER="customer-name"
EMAIL="team@example.com"
TEAM="team-name"
TAGS="customer=$CUSTOMER contact-email=$EMAIL team=$TEAM"
ACTION_MODE="REPLACE_ON_FAILURE"
SERVICE_ACTION_MODE="CREATE_UPDATE"
NONPROD_PROFILE="NONE"
PROD_PROFILE="NONE"
STACK_NAME="NONE"
STACK_NAME_SUFFIX="-orchestrator"
OVERRIDE_FILE=".setuprc"
GITHUB_ORGANIZATION="warnermedia"
APP_SOURCE_REPOSITORY=${GIT_REPOSITORY:-$(basename $(git remote get-url origin) .git)}

export AWS_PAGER=""

echo "NOTE: The \"jq\" utility and AWS CLI must be installed in order for this script to work."

check_command () {
  local command_name=${1}

  if command -v $command_name > /dev/null 2>&1; then
    echo "The command \"$command_name\" is available."
  else
    echo "The command \"$command_name\" is not available.  Please install before you continue."
    exit 127
  fi
}

run_codebuild () {
  local project="$1"
  local profile="${2:-$PROFILE}"
  local region="${3:-$REGION}"

  aws --profile "$profile" --region "$region" codebuild start-build --project-name "$project"
}

run_deploy () {
  local stack="$1"
  local parameters="$2"
  local tags="$3"
  local profile="${4:-$PROFILE}"
  local region="${5:-$REGION}"
  local template="${6:-$TEMPLATE}"

  aws --profile "$profile" --region "$region" cloudformation deploy --template-file "$template" --stack-name "$stack" --parameter-overrides $parameters --capabilities CAPABILITY_NAMED_IAM CAPABILITY_AUTO_EXPAND --tags $tags

}

#Run the checks for installed commands...
check_command aws
check_command jq

echo "Check if there is a \"$OVERRIDE_FILE\" override file..."

#Source the overrides file if it exists...
if [ -f "$OVERRIDE_FILE" ]; then
  echo "Sourcing the \"$OVERRIDE_FILE\" file..."
  . "$(pwd)/$OVERRIDE_FILE"
fi

echo ""
echo "Is this the first time you are running this script?"
read -p "\"Yes\" or \"No\" (Default: $FIRST_RUN): " first_run
echo "The answer is: ${first_run:-$FIRST_RUN}"

echo ""
echo "Which project directory contains the git hooks that you would like to run with this project?"
read -p "Git hooks directory (Default: $GIT_HOOKS): " git_hooks
echo "The git hooks directory is: ${git_hooks:-$GIT_HOOKS}"

echo ""
read -p "The GitHub organization name (Default: $GITHUB_ORGANIZATION): " github_organization
echo "The GitHub organization name is: ${github_organization:-$GITHUB_ORGANIZATION}"

echo ""
read -p "The application source repository name (Default: $APP_SOURCE_REPOSITORY): " app_source_repository
echo "The application source repository name is: ${app_source_repository:-$APP_SOURCE_REPOSITORY}"

echo ""
echo "If you have a non-prod/prod account split, then give the non-prod and production account numbers."
read -p "Account number for non-prod account (Default: $NONPROD_ACCOUNT): " nonprod_account
echo "The non-prod account number is: ${nonprod_account:-$NONPROD_ACCOUNT}"

echo ""
read -p "Account number for production account (Default: $PROD_ACCOUNT): " prod_account
echo "The production account number is: ${prod_account:-$PROD_ACCOUNT}"

echo ""
echo "If you have a non-prod/prod account split, then give the non-prod and production profiles."
read -p "Target profile for non-prod account (Default: $NONPROD_PROFILE): " nonprod_profile
echo "The non-prod profile is: ${nonprod_profile:-$NONPROD_PROFILE}"

echo ""
read -p "Target profile for prod account (Default: $PROD_PROFILE): " prod_profile
echo "The prod profile is: ${prod_profile:-$PROD_PROFILE}"

echo ""
echo "If you have custom commands that you would like to run after the infrastructure is set up, you can enable them here (possible values: Yes/No)."

echo ""
read -p "Enable custom commands for non-prod (\"Yes\" or \"No\")? (Default: $NONPROD_ENABLE_CUSTOM_COMMANDS): " nonprod_enable_custom_commands
echo "Enable non-prod custom commands: ${nonprod_enable_custom_commands:-$NONPROD_ENABLE_CUSTOM_COMMANDS}"

echo ""
read -p "Enable custom commands for production (\"Yes\" or \"No\")? (Default: $PROD_ENABLE_CUSTOM_COMMANDS): " prod_enable_custom_commands
echo "Enable production custom commands: ${prod_enable_custom_commands:-$PROD_ENABLE_CUSTOM_COMMANDS}"

echo ""
read -p "Base stack name (Default: $STACK_NAME): " stack_name
echo "The base stack name is: ${stack_name:-$STACK_NAME}"

echo ""
read -p "ECS repository name (Default: $ECS_REPO_NAME): " ecs_repo_name
echo "The ECS repository name is: ${ecs_repo_name:-$ECS_REPO_NAME}"

echo ""
read -p "Project name (Default: $PROJECT_NAME): " project_name
echo "The project name is: ${project_name:-$PROJECT_NAME}"

echo ""
read -p "The non-prod S3 bucket name for CodePipeline/CodeBuild artifacts (Default: $NONPROD_S3_ARTIFACT_BUCKET): " nonprod_s3_artifact_bucket
echo "The non-prod S3 bucket is: ${nonprod_s3_artifact_bucket:-$NONPROD_S3_ARTIFACT_BUCKET}"

echo ""
read -p "The prod S3 bucket name for CodePipeline/CodeBuild artifacts (Default: $PROD_S3_ARTIFACT_BUCKET): " prod_s3_artifact_bucket
echo "The prod S3 bucket is: ${prod_s3_artifact_bucket:-$PROD_S3_ARTIFACT_BUCKET}"

echo ""
read -p "Service subdomain (Default: $SERVICE_SUBDOMAIN): " service_subdomain
echo "The service subdomain is: ${service_subdomain:-$SERVICE_SUBDOMAIN}"

echo ""
echo "If you want this application deployed to a second region for all environments, then set that region next."
read -p "Second Region (Default: $SECOND_REGION): " second_region
echo "The second region is: ${second_region:-$SECOND_REGION}"

echo ""
echo "If you would like to set all of the CloudFormation actions to a different action mode, then set that region next."
read -p "CloudFormation Action Mode (Default: $ACTION_MODE): " action_mode
echo "The CloudFormation Action Mode is: ${action_mode:-$ACTION_MODE}"

echo ""
echo "If you would like to set all of the CloudFormation actions (for the ECS services) to a different action mode, then set that region next."
read -p "CloudFormation Service Action Mode (Default: $SERVICE_ACTION_MODE): " service_action_mode
echo "The CloudFormation Service Action Mode is: ${service_action_mode:-$SERVICE_ACTION_MODE}"

if [ -n "${git_hooks:-$GIT_HOOKS}" ]; then
  echo "Setting the active git hooks folder."
  git config --local core.hooksPath ${git_hooks:-$GIT_HOOKS}
fi

if [ -n "${prod_profile:-$PROD_PROFILE}" ]; then
  echo "Creating/Updating Production Stack"
  run_deploy "${stack_name:-$STACK_NAME}$STACK_NAME_SUFFIX" "AppGitHubOrganization=${github_organization:-$GITHUB_ORGANIZATION} AppSourceRepository=${app_source_repository:-$APP_SOURCE_REPOSITORY} ExternalArtifactBucket=${nonprod_s3_artifact_bucket:-$NONPROD_S3_ARTIFACT_BUCKET} EcrNonProdAccount=${nonprod_account:-$NONPROD_ACCOUNT} EcrProdAccount=${prod_account:-$PROD_ACCOUNT} EcsRepositoryName=${ecs_repo_name:-$ECS_REPO_NAME} EnableCustomBuild=${prod_enable_custom_commands:-$PROD_ENABLE_CUSTOM_COMMANDS} ProjectName=${project_name:-$PROJECT_NAME} ServiceSubdomain=${service_subdomain:-$SERVICE_SUBDOMAIN} ActionMode=${action_mode:-$ACTION_MODE} ServiceActionMode=${service_action_mode:-$SERVICE_ACTION_MODE} SecondRegion=${second_region:-$SECOND_REGION} UnstableEnvironment=NONE InitialEnvironment=NONE QaEnvironment=NONE StageEnvironment=NONE TagEnvironment=prod " "$TAGS environment=prod" "${prod_profile:-$PROD_PROFILE}"
  if [ "${first_run:-$FIRST_RUN}" = "Yes" ]; then
    run_codebuild "${project_name:-$PROJECT_NAME}-orchestrator" "${prod_profile:-$PROD_PROFILE}"
  fi
else
  echo "No production profile was set, so not deploying a template to a separate production account..."
fi

if [ -n "${nonprod_profile:-$NONPROD_PROFILE}" ]; then
  echo "Creating/Updating Non-Prod Stack"
  run_deploy "${stack_name:-$STACK_NAME}$STACK_NAME_SUFFIX" "AppGitHubOrganization=${github_organization:-$GITHUB_ORGANIZATION} AppSourceRepository=${app_source_repository:-$APP_SOURCE_REPOSITORY} ExternalArtifactBucket=${prod_s3_artifact_bucket:-$PROD_S3_ARTIFACT_BUCKET} EcrNonProdAccount=${nonprod_account:-$NONPROD_ACCOUNT} EcrProdAccount=${prod_account:-$PROD_ACCOUNT} EcsRepositoryName=${ecs_repo_name:-$ECS_REPO_NAME} EnableCustomBuild=${nonprod_enable_custom_commands:-$NONPROD_ENABLE_CUSTOM_COMMANDS} ProjectName=${project_name:-$PROJECT_NAME} ServiceSubdomain=${service_subdomain:-$SERVICE_SUBDOMAIN} ActionMode=${action_mode:-$ACTION_MODE} ServiceActionMode=${service_action_mode:-$SERVICE_ACTION_MODE} SecondRegion=${second_region:-$SECOND_REGION} ProdEnvironment=NONE TagEnvironment=nonprod " "$TAGS environment=nonprod" "${nonprod_profile:-$NONPROD_PROFILE}"
  if [ "${first_run:-$FIRST_RUN}" = "Yes" ]; then
    run_codebuild "${project_name:-$PROJECT_NAME}-orchestrator" "${nonprod_profile:-$NONPROD_PROFILE}"
  fi
else
  echo "No non-prod profile was set, so not deploying a template to a separate non-prod account..."
fi