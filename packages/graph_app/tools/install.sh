#!/bin/bash

function usage {
  echo
  echo "install.sh [ -n | --no-build ]"
  echo
  echo This command cleans and rebuilds the web app with the ClientKit option. It must be run
  echo from either the main directory of the graph_app package or one of its direct subdirectories.
  echo
  echo "--no-build (-n)   Do not force a rebuild of the app"
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

BUILD=true

for arg in $*
do
  if [ "$arg" == "-n" ]; then
    BUILD=false
  elif [ "$arg" == "--no-build" ]; then
    BUILD=false
  else
    echo Unrecognized argument: "$arg"
    usage
  fi
done

# Relative directories for our source files and destination archive
SRC_EXAMPLE_FILE=lib/series_graphing.dart

if [ -f $SRC_EXAMPLE_FILE ]; then
  REPO_DIR=.
elif [ -f ../$SRC_EXAMPLE_FILE ]; then
  REPO_DIR=..
else
  echo Could not find sample file: $SRC_EXAMPLE_FILE
  usage
fi

BUILD_DIR=$REPO_DIR/build

if [ $BUILD == true ]; then
  echo "---" Cleaning build
  (cd $REPO_DIR; flutter clean)
  echo "---" Building web app with ClientKit
  (cd $REPO_DIR; flutter build web --web-renderer canvaskit)
else
  check_dir $BUILD_DIR
fi

WEB_DIR_NAME=web
TAR_TMP_DIR_NAME=webapp

WEB_DIR=$BUILD_DIR/$WEB_DIR_NAME
TAR_TMP_DIR=$BUILD_DIR/$TAR_TMP_DIR_NAME

DEST_DIR_REL=$REPO_DIR/../../lib/src
check_dir $DEST_DIR_REL
DEST_DIR=`(cd $DEST_DIR_REL; pwd)`
DEST_ZIP_FILE=$DEST_DIR/webapp.zip

# List of files required for serving the web app to a browser
ICONS=(
    icons/Icon-192.png
    icons/Icon-512.png
)

ASSETS=(
    assets/FontManifest.json
    assets/AssetManifest.json
    assets/fonts/MaterialIcons-Regular.otf
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

echo "---" Installing web app to $DEST_ZIP_FILE

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
