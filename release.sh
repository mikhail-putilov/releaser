#!/bin/sh
#
# TITLE       : release.sh
# DESCRIPTION : скрипт автоматического создания релизных веток во всех репозиториях и запуск билда.
# AUTHOR      : Путилов Михаил Юрьевич SBT-Putilov-MYu
# DATE        : 18.12.2017
# VERSION     : 0.1.0
# USAGE       : bash ./release.sh -r 0.1.0 -d 0.2.0-SNAPSHOT
#             : или 
#             : bash ./release.sh --releaseVersion 0.1.0 --developVersion 0.2.0-SNAPSHOT
#             :
#             : где -r это создаваемая релизная ветка от develop
#             : а -d это новая версия develop (инкремент)
#             : скрипт ничего не пушит, все изменения локальные
# REPOSITORY  : https://github.com/YOUR_USER/your_project

# we want to fail fast our script in case non null exit code
set -e
set -o pipefail



#### <parse arguments> ####
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
#### </parse arguments> ####



#### <non null check arguments> ####
if [[ -z "$releaseVersion" ]]; then
	echo '-r or --releaseVersion must be set in order to set new release version'
	exit 3
fi
if [[ -z "$developVersion" ]]; then
	echo '-d or --developVersion must be set in order to set new development version'
	exit 4
fi
#### </non null check arguments> ####



#### <helper definitions> ####
releaseBranchName="release/${releaseVersion}"
releaseMessageCommit="[RELEASE v${releaseVersion}]"

# get folder where release.sh is located
reactor="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

build_module() {
	mvn clean install -U
}

print_line() {
	echo '[INFO] ------------------------------------------------------------------------'
}

set_versions() {
	mvn versions:set -DgenerateBackupPoms=false \
		-DprocessAllModules=true \
		-DnewVersion="$1" \
		-DoldVersion=* \
		-DgroupId=* \
		-DartifactId=*
}
#### </helper definitions> ####



#### <main> ####
# get paths of all modules in current pom
cd "$reactor"
modules=( $(mvn -q --also-make exec:exec -Dexec.executable="pwd") )
print_line



####   <validating> ####
echo '[INFO] Validating modules...'
print_line
# validate working tree and existing of release branches
for module in "${modules[@]}"; do
	echo "[INFO] Exec: cd ${module}"
	cd "$module"
	echo "[INFO] Checking if release branch ${releaseBranchName} is already created..."
	if git show-ref --verify -q refs/heads/${releaseBranchName}; then
		echo "[ERROR] Branch name ${releaseBranchName} already exists in ${module}. Proceed with exit without changes."
		exit 1
	else
		echo "[INFO] No branch with name ${releaseBranchName} is detected."
	fi
	echo '[INFO] Checking if working tree is clean...'
	if [[ $(git status --porcelain) ]]; then
		echo "[ERROR] Working tree is not clean in ${module}. Proceed with exit without changes"
	else
		echo '[INFO] Working tree is okay'
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
####   </validating> ####



####   <version bumping in develop> ####
echo '[INFO] Bumping develop version up to $developVersion...'
print_line
cd "$reactor"
# set version for all develop branches
set_versions "$developVersion"

echo '[INFO] Committing changes in develop...'
print_line
# commit new version
for module in "${modules[@]}"; do
	cd "$module"
	echo "[INFO] Committing changes in ${module}..."
	git commit -am "Bump version up to $developVersion" 
	print_line
done
####   </version bumping in develop> ####



####   <creating release branches> ####
echo '[INFO] Creating release branches...'
print_line
# clean && create release branches
for module in "${modules[@]}"; do
	echo '[INFO] Exec: git clean -f:'
	git clean -f
	echo "[INFO] Exec: git checkout -b ${releaseBranchName} HEAD^:"
	# create release branch from previous commit
	git checkout -b $releaseBranchName HEAD^
	echo "[INFO] Exec: done '${module}'"
	print_line
done
####   </creating release branches> ####



####   <set release version in release branches> ####
cd "$reactor"
# set version for all release branches
set_versions "$releaseVersion"

echo '[INFO] Building release branches...'
print_line
# build and commit
for module in "${modules[@]}"; do
	cd "$module"
	build_module
	print_line
done
####   </set release version in release branches> ####



####   <commit release branches> ####
echo '[INFO] Commiting release branches...'
print_line
for module in "${modules[@]}"; do
	# only if build is succeeded we commit release branch
	git commit -am "${releaseMessageCommit}"
	print_line
done
####   </commit release branches> ####



#### </main> ####

