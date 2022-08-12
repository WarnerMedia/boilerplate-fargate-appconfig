#!/bin/sh
#Only dashisms allowed (https://wiki.archlinux.org/index.php/Dash).

echo "Build Started on $(date)"

#------------------------------------------------------------------------
# BEGIN: Declare some functions
#------------------------------------------------------------------------

#Function to check if the AWS command was successful.
check_status () {
  #The $? variable always contains the status code of the previously run command.
  #We can either pass in $? or this function will use it as the default value if nothing is passed in.
  local prev=${1:-$?}
  local command="$2"

  if [ $prev -eq 0 ]; then
    echo "The $command command has succeeded."
  else
    echo "The $command command has failed."
    #Kill the build script so that we go no further.
    exit 1
  fi
}

create_release_github_commit () {
  local owner="$1"
  local repository="$2"
  local token="$3"
  local tag="$4"
  local prev_release="$5"
  local prerelease="$6"
  local digest="$7"
  local ecr="$8"
  local commit="$9"
  local body="(Initial Release)"

  echo "Tagging git hash \"$commit\" with the following tag: $tag"

  if [ "$prev_release" = "none" ]; then
    body="$body\n\nECR Information:\n\n1. Repository: $ecr\n2. Digest: $digest"
  else
    body="[ [Release Changelog](https://github.com/$owner/$repository/compare/$prev_release...$tag) ]\n\nECR Information:\n\n1. Repository: $ecr\n2. Digest: $digest"
  fi

  # Create a new release tag.
  curl -s -X POST https://api.github.com/repos/$owner/$repository/releases \
  -H "Authorization: token $token" \
  -d @- << EOF
{
  "tag_name": "$tag",
  "target_commitish": "$commit",
  "name": "$tag",
  "body": "$body",
  "draft": false,
  "prerelease": $prerelease
}
EOF

check_status $? "GitHub"

}

#Because CodeBuild doesn't pass environment between phases, putting in a patch.
export_variable () {
  local key="$1"

  export $key

  local temp=$(printenv | grep -w $key)

  echo "$temp" >> /tmp/build
}

promote_zip_file () {
  local bucket="$1"
  local prod_bucket="$2"
  local project="$3"
  local current_env="$4"
  local promote_env="$5"
  local file=$(echo "$6" | cut -d: -f1)
  local version=$(echo "$6" | cut -d: -f2-)
  local region="$7"

  echo "Getting the \"s3://$bucket/$project/$current_env/$file\" file..."
  aws --region "$region" s3api get-object --bucket "$bucket" --key "$project/$current_env/$file" --version-id "$version" "/tmp/$file"
  check_status $? "AWS CLI"


  if [ "$promote_env" = "prod" ]; then
    echo "Promoting \"$file\" to \"s3://$prod_bucket/$project/$promote_env/$file\" file with \"bucket-owner-full-control\" ACL and KMS Key..."
    aws s3 cp "/tmp/$file" "s3://$prod_bucket/$project/$promote_env/$file" --region "$region" --quiet --acl bucket-owner-full-control
    check_status $? "AWS CLI"
  else
    echo "Promoting \"$file\" to \"s3://$bucket/$project/$promote_env/$file\" file..."
    aws s3 cp "/tmp/$file" "s3://$bucket/$project/$promote_env/$file" --region "$region" --quiet
    check_status $? "AWS CLI"
  fi
}

#Move the environment tag 
tag_environment_images () {
  local remote_image_url="$1"
  local digest="${2:-$AWS_ECR_IMAGE_DIGEST}"
  local env="${3:-$APPROVAL_ENV}"
  local region="${4:-$AWS_REGION}"
  local account="${5:-$AWS_ACCOUNT_ID}"

  echo "Logging into docker..."
  aws --region "$region" ecr get-login-password | docker login --username "AWS" --password-stdin "$account.dkr.ecr.$region.amazonaws.com"
  check_status $? "AWS CLI"

  docker tag "$remote_image_url@$digest" "$remote_image_url:$env"
  check_status $? "docker"
  docker push "$remote_image_url:$env"
  check_status $? "docker"

}

tag_github_commit () {
  local owner="$1"
  local repository="$2"
  local token="$3"
  local tag="$4"
  local commit="$5"

  # POST a new ref to repo via Github API
  curl -s -X POST https://api.github.com/repos/$owner/$repository/git/refs \
  -H "Authorization: token $token" \
  -d @- << EOF
{
  "ref": "refs/tags/$tag",
  "sha": "$commit"
}
EOF

  check_status $? "GitHub"

}

update_release_github_commit () {
  local owner="$1"
  local repository="$2"
  local token="$3"
  local tag="$4"
  local prerelease="$5"

  echo "Updating release \"$tag\" for full release..."

  # POST a new ref to repo via Github API
  local id=$(curl -s -X GET https://api.github.com/repos/$owner/$repository/releases/tags/$tag -H "Authorization: token $token" | jq -r '.id')

  check_status $? "GitHub"

  # POST a new ref to repo via Github API
  curl -s -X PATCH https://api.github.com/repos/$owner/$repository/releases/$id \
  -H "Authorization: token $token" \
  -d @- << EOF
{
  "prerelease": $prerelease
}
EOF

  check_status $? "GitHub"

}

#------------------------------------------------------------------------
# END: Declare some functions
#------------------------------------------------------------------------

#------------------------------------------------------------------------
# BEGIN: Deploy and tag the images and create artifact file
#------------------------------------------------------------------------

#Source variables from pre_build section.
. /tmp/pre_build

#Change the directory to the application directory...
if [ -z "$APP_BASE_FOLDER" ]; then
  echo "No application version was set, so not changing directory..."
else
  cd "$CODEBUILD_SRC_DIR/$APP_BASE_FOLDER" || exit 1
fi

echo "Prmote the ZIP files..."

promote_zip_file "$NONPROD_BUCKET" "$PROD_BUCKET" "$PROJECT_NAME" "$CURRENT_ENV" "$APPROVAL_ENV" "$SERVICE_S3_FILE" "$AWS_REGION"
promote_zip_file "$NONPROD_BUCKET" "$PROD_BUCKET" "$PROJECT_NAME" "$CURRENT_ENV" "$APPROVAL_ENV" "$TEST_S3_FILE" "$AWS_REGION"

echo "Tag the appropriate image for each environment..."
tag_environment_images "$FIRST_REGION_DOCKER_URL" "$AWS_ECR_IMAGE_DIGEST" "$APPROVAL_ENV"

if [ "$SECOND_REGION_DOCKER_URL" != "NONE" ]; then
  echo "Tag the appropriate image for each environment in the second region..."
  tag_environment_images "$SECOND_REGION_DOCKER_URL" "$AWS_ECR_IMAGE_DIGEST" "$APPROVAL_ENV" "$AWS_SECOND_REGION"
fi

if [ "$PROD_FIRST_REGION_DOCKER_URL" != "NONE" ]; then
  echo "Pushing the docker image to the production first region..."
  tag_environment_images "$PROD_FIRST_REGION_DOCKER_URL" "$AWS_ECR_IMAGE_DIGEST" "$APPROVAL_ENV" "$AWS_REGION" "$AWS_ECR_PROD_ACCOUNT_ID"
fi

if [ "$PROD_SECOND_REGION_DOCKER_URL" != "NONE" ]; then
  echo "Pushing the docker image to the production second region..."
  tag_environment_images "$PROD_SECOND_REGION_DOCKER_URL" "$AWS_ECR_IMAGE_DIGEST" "$APPROVAL_ENV" "$AWS_SECOND_REGION" "$AWS_ECR_PROD_ACCOUNT_ID"
fi

#GitHub tagging...
if [ "$APPROVAL_ENV" = "$PRERELEASE_ENV" ]; then
  echo "This is the \"$PRERELEASE_ENV\" environment, so tagging the commit for pre-release in GitHub..."
  #TODO: Research if there is any need to do a manual tag.  Since the release API call creates the tag, it seems like it is probably not needed.
  #      Commenting out this call but keeping the function for the time-being, in case we find a need.
  #tag_github_commit "$GITHUB_ORGANIZATION" "$GITHUB_REPOSITORY" "$GITHUB_TOKEN" "v$ECR_VERSION" "$GITHUB_COMMIT"
  create_release_github_commit "$GITHUB_ORGANIZATION" "$GITHUB_REPOSITORY" "$GITHUB_TOKEN" "v$ECR_VERSION" "$GITHUB_PREV_RELEASE" "true" "$AWS_ECR_IMAGE_DIGEST" "$IMAGE_REPO_NAME" "$GITHUB_COMMIT"
fi

if [ "$APPROVAL_ENV" = "$RELEASE_ENV" ]; then
  echo "This is the \"$RELEASE_ENV\" environment, so updating the release to a full release GitHub..."
  update_release_github_commit "$GITHUB_ORGANIZATION" "$GITHUB_REPOSITORY" "$GITHUB_TOKEN" "v$ECR_VERSION" "false"
fi

#------------------------------------------------------------------------
# END: Deploy and tag the images and create artifact file
#------------------------------------------------------------------------