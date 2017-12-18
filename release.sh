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
# COMMENTS    : release.sh надеется найти агрегирующий pom.xml рядом с собой, в котором будут указаны все остальные проекты в секции modules.
# скрипт узнает пути до папок всех модулей (включая и путь до папки которая содержит агрегирующий pom.xml). После этого выполняет проверку:
# 1) существует ли уже релизная ветка
# 2) совпадает ли новая версия develop и текущая
# 3) есть ли незакомиченые изменения в каком-либо из модулей
# Если хотя бы одно из условий true, то скрипт выходит не начиная работу, а иначе обновляет версию develop ветки, создает релизные ветки во всех модулях и запускает
# билд mvn clean install -U из агрегирующего pom.xml. Если билд успешен, то все изменения в релизных ветках (измененная версия pom.xml) комитятся.

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
isAllScriptSucceeded=''
releaseBranchName="release/${releaseVersion}"
releaseMessageCommit="[RELEASE v${releaseVersion}]"

# get folder where release.sh is located
reactor="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

fail() {
	echo "[ERROR] $1" && exit 1
}

build_module() {
	mvn clean install -U
}

print_line() {
	echo '[INFO] ------------------------------------------------------------------------'
}

print_header() {
	echo "[INFO] $1"
	print_line
}

set_versions() {
	mvn versions:set -DgenerateBackupPoms=false \
		-DprocessAllModules=true \
		-DnewVersion="$1" \
		-DoldVersion=* \
		-DgroupId=* \
		-DartifactId=*
}

checkpoint() {
	git tag release-sh-checkpoint || fail 'release-sh-checkpoint tag already exists! Something went horribly wrong'
}

remove_checkpoint() {
	git tag -d release-sh-checkpoint || fail 'release-sh-checkpoint tag is not found! Something went horribly wrong'
}

rollback_to_checkpoint() {
	git clean -f || fail 'Cannot run git clean -f'
	git reset --hard HEAD || fail 'Cannot run git reset --hard HEAD'
	git checkout develop || fail 'Cannot run git checkout develop'
	git reset --hard release-sh-checkpoint || fail 'Cannot run git reset --hard release-sh-checkpoint'
}

finish() {
	if [[ $isAllScriptSucceeded == 'false' ]]; then
		cd "$reactor" || fail 'reactor is not defined at the resource cleaning phase'
		modules=( $(mvn -q --also-make exec:exec -Dexec.executable="pwd") )
		for module in "${modules[@]}"; do
			cd "$module"
			if git rev-parse -q --verify "refs/tags/release-sh-checkpoint"; then
				rollback_to_checkpoint
				remove_checkpoint
				set +e
				git branch -D "$releaseBranchName"

				set -e
			else
				fail 'No checkpoint release-sh-checkpoint tag is found. Cannot rollback to checkpoint'
			fi
		done
	fi
}

trap finish EXIT

#### </helper definitions> ####



#### <main> ####
# get paths of all modules in current pom
cd "$reactor"
modules=( $(mvn -q --also-make exec:exec -Dexec.executable="pwd") )
print_line



####   <validating> ####
print_header 'Validating modules...'
# validate working tree and existing of release branches
for module in "${modules[@]}"; do
	echo "[INFO] Exec: cd ${module}"
	cd "$module"
	echo "[INFO] Checking if release branch ${releaseBranchName} is already created..."
	if git show-ref --verify -q "refs/heads/${releaseBranchName}"; then
		fail "Branch name ${releaseBranchName} already exists in ${module}. Proceed with exit without changes."
	else
		echo "[INFO] No branch with name ${releaseBranchName} is detected."
	fi
	echo '[INFO] Checking if working tree is clean...'
	if [[ $(git status --porcelain) ]]; then
		fail "Working tree is not clean in ${module}. Proceed with exit without changes"
	else
		echo '[INFO] Working tree is okay'
	fi
	
	git checkout develop
	git pull origin develop

	currentDevelopVersion=$(mvn help:evaluate -Dexpression=project.version | grep -v "^\[INFO")
	if [[ "$currentDevelopVersion" == "$developVersion" ]]; then
		fail "Next development version $developVersion == current development version"
	fi
	print_line
done
####   </validating> ####



####   <creating checkpoint for rollback> ####
for module in "${modules[@]}"; do
	cd "$module"
	checkpoint
done
# now we have something to rollback to, so let isAllScriptSucceeded to be explicit false (it was empty string)
isAllScriptSucceeded='false'
####   </creating checkpoint for rollback> ####



####   <version bumping in develop> ####
print_header "Bumping develop version up to $developVersion..."
cd "$reactor"
# set version for all develop branches
set_versions "$developVersion"

print_header 'Committing changes in develop...'
# commit new version
for module in "${modules[@]}"; do
	cd "$module"
	echo "[INFO] Committing changes in ${module}..."
	git commit -am "Bump version up to $developVersion" 
	print_line
done
####   </version bumping in develop> ####



####   <creating release branches> ####
print_header 'Creating release branches...'
# clean && create release branches
for module in "${modules[@]}"; do
	cd "$module"
	echo "[INFO] Exec: git checkout -b ${releaseBranchName} HEAD^:"
	# create release branch from previous commit
	git checkout -b "$releaseBranchName" HEAD^
	echo "[INFO] Exec: done '${module}'"
	print_line
done
####   </creating release branches> ####



####   <set release version in release branches and building> ####
cd "$reactor"
# set version for all release branches
set_versions "$releaseVersion"
fail 'lol'
print_header 'Building release branches...'
build_module
####   </set release version in release branches and building> ####



####   <commit release branches> ####
print_header 'Commiting release branches...'
for module in "${modules[@]}"; do
	cd "$module"
	# only if build is succeeded we commit release branch
	git commit -am "${releaseMessageCommit}"
	print_line
done
####   </commit release branches> ####
isAllScriptSucceeded='true'


#### </main> ####




