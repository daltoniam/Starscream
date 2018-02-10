#!/bin/sh

defaultXcodePath="/Applications/Xcode.app/Contents/Developer"
realXcodePath="`xcode-select -p`"

fatal() {
echo "[fatal] $1" 1>&2
exit 1
}

absPath() {
case "$1" in
/*)
printf "%s\n" "$1"
;;
*)
printf "%s\n" "$PWD/$1"
;;
esac;
}

scriptDir="`dirname $0`"
scriptName="`basename $0`"
absScriptDir="`cd $scriptDir; pwd`"

main() {
for f in `find ${absScriptDir} -name Starscream.modulemap`; do
cat ${f} | sed "s,${defaultXcodePath},${realXcodePath},g" > ${f}.new || fatal "Failed to update modulemap ${f}"
mv ${f}.new ${f} || fatal "Failed to replace modulemap ${f}"
done
rm -f ${absScriptDir}/module.modulemap
}

main $*
