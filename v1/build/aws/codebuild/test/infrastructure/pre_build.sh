#!/bin/sh
#Only dashisms allowed (https://wiki.archlinux.org/index.php/Dash).

echo "Pre-Build Started on $(date)"

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