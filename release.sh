#!/usr/bin/env sh
SCRIPT=`realpath $0`
SCRIPTPATH=`dirname $SCRIPT`

cd "$SCRIPTPATH"
mix deps.get
mix deps.clean --unused


MIX_ENV=prod mix build
rm -rf "$SCRIPTPATH"/release
mkdir release
cp bin/* release/
cp exls_archives/exls.ez release/exls.ez

# cd "$SCRIPTPATH"/apps/language_server
# mix escript.build
# cd "$SCRIPTPATH"/apps/debugger
# mix escript.build
