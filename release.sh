#!/bin/sh

releaseVersion="0.1.0"
developVersion="0.1.1-SNAPSHOT"
releaseName="release/${releaseVersion}"
releasePrefix="[RELEASE ${releaseVersion}]"

set -e
set -o pipefail

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
	echo "[INFO] Checking if release branch ${releaseName} is already created..."
	if git show-ref --verify -q refs/heads/${releaseName}
	then
		echo "[ERROR] Branch name ${releaseName} already exists in ${module}. Proceed with exit without changes."
		exit 1
	else
		echo "[INFO] No branch with name ${releaseName} is detected."
	fi
	echo "[INFO] Checking if working tree is clean..."
	if [[ `git status --porcelain` ]]; then
		echo "[ERROR] Working tree is not clean in ${module}. Proceed with exit without changes"
	else
		echo "[INFO] Working tree is okay"
	fi
	
	git checkout develop
	git pull origin develop
	print_line
done

# set version for all develop branches
mvn versions:set -DgenerateBackupPoms=false -DprocessAllModules=true -DnewVersion="$developVersion"


for module in ${modules[@]}
do
	git commit -am "Bump version up to $developVersion" 
done

echo "[INFO] Creating release branches..."
print_line
# clean && create release branches
for module in ${modules[@]}
do
	echo "[INFO] Exec: git clean -f:"
	git clean -f
	echo "[INFO] Exec: git checkout -b ${releaseName} HEAD^:"
	# create release branch from previous commit
	git checkout -b $releaseName HEAD^
	echo "[INFO] Exec: done '${module}'"
	print_line
done

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
	git commit -am "${releasePrefix}"
	print_line
done

