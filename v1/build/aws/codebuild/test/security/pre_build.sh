#!/bin/sh
#Only dashisms allowed (https://wiki.archlinux.org/index.php/Dash).

echo "Pre-Build Started on $(date)"

#------------------------------------------------------------------------
# BEGIN: Declare some functions
#------------------------------------------------------------------------

#Check if required commands exist...
exists () {
  command -v "$1" >/dev/null 2>&1
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
# BEGIN: Main Logic
#------------------------------------------------------------------------

if [ -n "$APP_BASE_FOLDER" ]; then
  cd "$CODEBUILD_SRC_DIR/$APP_BASE_FOLDER" || exit 1;
fi

echo "Install the NPM modules..."
npm install

#------------------------------------------------------------------------
# END: Main Logic
#------------------------------------------------------------------------