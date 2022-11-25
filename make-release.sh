#!/bin/bash
set -e
shopt -s extglob
shopt -s nullglob

RELEASE_DIR=release

NAME="fpc-mqtt-client-$(git describe --tags --first-parent | sed 's/-g[0-9a-f]\{7,9\}//')"

rm -rf $RELEASE_DIR
mkdir -p $RELEASE_DIR/$NAME

cp -r --parents {demo,mqtt}/{**,.}/*.{pas,lpr,lpi,lfm} $RELEASE_DIR/$NAME/
cd $RELEASE_DIR/$NAME
zip -r -9 ../$NAME.zip *
cd ..
rm -rf $NAME
