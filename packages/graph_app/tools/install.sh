#!/bin/bash

function usage {
  echo
  echo This command must be run after \'flutter build web\' from either
  echo the tools or build directory of the graph_app package.
  echo
  exit 1
}

function check_file {
  if [ ! -f $1 ]; then
    echo File $1 does not exist
    usage
  fi
}

function check_dir {
  if [ ! -d $1 ]; then
    echo Directory $1 does not exist
    usage
  fi
}

# Relative directories for our source files and destination archive
BUILD_DIR=../build
WEB_DIR_NAME=web
TAR_TMP_DIR_NAME=webapp

WEB_DIR=$BUILD_DIR/$WEB_DIR_NAME
TAR_TMP_DIR=$BUILD_DIR/$TAR_TMP_DIR_NAME

DEST_DIR=../../../lib/src
DEST_ZIP_FILE=$DEST_DIR/webapp.zip

# List of files required for serving the web app to a browser
ICONS=(
    icons/Icon-192.png
    icons/Icon-512.png
)

ASSETS=(
    assets/FontManifest.json
    assets/AssetManifest.json
    assets/fonts/MaterialIcons-Regular.ttf
    assets/NOTICES
)

FILES=(
    index.html
    main.dart.js
    flutter_service_worker.js
    favicon.png
    manifest.json
)

ALL_FILES=(
    ${ICONS[*]}
    ${ASSETS[*]}
    ${FILES[*]}
)

# Check that all of the files we need to serve have been produced by 'flutter build web'
for file in ${ALL_FILES[*]}
do
    check_file $WEB_DIR/$file
done

# Check that the destination directory where we plan to install the archive exists
check_dir $DEST_DIR

# Remove previous temp directory and build a minimal directory structure for archiving
rm -rf $TAR_TMP_DIR
for file in ${ALL_FILES[*]}
do
    mkdir -p $TAR_TMP_DIR/$file
    rmdir $TAR_TMP_DIR/$file
    cp $WEB_DIR/$file $TAR_TMP_DIR/$file
done

# Remove the existing archive and replace it with an archive of the new files
rm -f $DEST_ZIP_FILE
(cd $BUILD_DIR; zip -r $DEST_ZIP_FILE $TAR_TMP_DIR_NAME)
rm -rf $TAR_TMP_DIR

echo
echo New web app archive installed in $DEST_ZIP_FILE
