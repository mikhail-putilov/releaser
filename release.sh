#!/bin/sh
# Usage:
# sh ./release.sh -r 0.1.0 -d 0.1.1-SNAPSHOT
# which means:
#  1) we a releasing 0.1.0 version
#  2) preparing for development of a new 0.1.1 version

# release.sh doesn't push any changes

set -e
set -o pipefail

POSITIONAL=()
while [[ $# -gt 0 ]]
do
key="$1"

case $key in
    -r|--releaseVersion)
    releaseVersion="$2"
    shift # past argument
    shift # past value
    ;;
    -d|--developVersion)
    developVersion="$2"
    shift # past argument
    shift # past value
    ;;
    --default)
    DEFAULT=YES
    shift # past argument
    ;;
    *)    # unknown option
    POSITIONAL+=("$1") # save it in an array for later
    shift # past argument
    ;;
esac
done
set -- "${POSITIONAL[@]}" # restore positional parameters

if [ -z "$releaseVersion" ]; then
    echo "-r or --releaseVersion must be set in order to set new release version"
    exit 3
fi
if [ -z "$developVersion" ]; then
    echo "-d or --developVersion must be set in order to set new development version"
    exit 4
fi

releaseBranchName="release/${releaseVersion}"
releaseMessageCommit="[RELEASE v${releaseVersion}]"


function mark {
    export $1=`pwd`;
}

# remember this folder as reactor
mark reactor

function build_module {
	mvn clean install -U
}

function print_line {
	echo "[INFO] ------------------------------------------------------------------------"
}

# get all pathes of all modules in current pom
modules=( $(mvn -q --also-make exec:exec -Dexec.executable="pwd") )

print_line

echo "[INFO] Validating modules..."
print_line
# validate working tree and existing of release branches
for module in ${modules[@]}
do
	echo "[INFO] Exec: cd ${module}"
	cd "$module"
	echo "[INFO] Checking if release branch ${releaseBranchName} is already created..."
	if git show-ref --verify -q refs/heads/${releaseBranchName}
	then
		echo "[ERROR] Branch name ${releaseBranchName} already exists in ${module}. Proceed with exit without changes."
		exit 1
	else
		echo "[INFO] No branch with name ${releaseBranchName} is detected."
	fi
	echo "[INFO] Checking if working tree is clean..."
	if [[ `git status --porcelain` ]]; then
		echo "[ERROR] Working tree is not clean in ${module}. Proceed with exit without changes"
	else
		echo "[INFO] Working tree is okay"
	fi
	
	git checkout develop
	git pull origin develop

	currentDevelopVersion=$(mvn help:evaluate -Dexpression=project.version | grep -v "^\[INFO")
	if [[ "$currentDevelopVersion" == "$developVersion" ]]; then
		echo "[ERROR] Next development version $developVersion == current development version"
		exit 2
	fi
	print_line
done

echo "[INFO] Bumping develop version up to $developVersion..."
print_line
cd "${reactor}"
# set version for all develop branches
mvn versions:set -DgenerateBackupPoms=false -DprocessAllModules=true -DnewVersion="$developVersion"

echo "[INFO] Committing changes in develop..."
print_line
# commit new version
for module in ${modules[@]}
do
	cd "$module"
	echo "[INFO] Committing changes in ${module}..."
	git commit -am "Bump version up to $developVersion" 
	print_line
done

echo "[INFO] Creating release branches..."
print_line
# clean && create release branches
for module in ${modules[@]}
do
	echo "[INFO] Exec: git clean -f:"
	git clean -f
	echo "[INFO] Exec: git checkout -b ${releaseBranchName} HEAD^:"
	# create release branch from previous commit
	git checkout -b $releaseBranchName HEAD^
	echo "[INFO] Exec: done '${module}'"
	print_line
done

cd "${reactor}"
# set version for all release branches
mvn versions:set -DgenerateBackupPoms=false -DprocessAllModules=true -DnewVersion="$releaseVersion"

echo "[INFO] Building release branches..."
print_line
# build and commit
for module in ${modules[@]}
do
	cd "$module"
	build_module
	print_line
done

echo "[INFO] Commiting release branches..."
print_line
for module in ${modules[@]}
do
	# only if build is succeeded we commit release branch
	git commit -am "${releaseMessageCommit}"
	print_line
done

