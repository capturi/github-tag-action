#!/bin/bash

set -e
set -o xtrace

if [[ -z "$GITHUB_TOKEN" ]]; then
	echo "Set the GITHUB_TOKEN env variable."
	exit 1
fi

# config
default_semvar_bump=${DEFAULT_BUMP:-minor}
release_branches=${RELEASE_BRANCHES:-master}

repo_fullname=$(jq -r ".repository.full_name" "$GITHUB_EVENT_PATH")

git remote set-url origin https://x-access-token:$GITHUB_TOKEN@github.com/$repo_fullname.git
git config --global user.email "actions@github.com"
git config --global user.name "GitHub Merge Action"

pre_release="true"
IFS=',' read -ra branch <<< "$release_branches"
for b in "${branch[@]}"; do
    echo "Is $b a match for ${GITHUB_REF#'refs/heads/'}"
    if [[ "${GITHUB_REF#'refs/heads/'}" =~ $b ]]
    then
        pre_release="false"
    fi
done
echo "pre_release = $pre_release"

git fetch origin $BRANCH --tags

# get latest tag
tag=$(git describe --tags `git rev-list --tags --max-count=1`)
tag_commit=$(git rev-list -n 1 $tag)

# get current commit hash for tag
commit=$(git rev-parse HEAD)

if [ "$tag_commit" == "$commit" ]; then
    echo "No new commits since previous tag. Bumping..."
    # echo ::set-output name=tag::$tag
    # exit 0
fi

# if there are none, start tags at 0.0.0
if [ -z "$tag" ]
then
    log=$(git log --pretty=oneline)
    tag=0.0.0
else
    log=$(git log $tag..HEAD --pretty=oneline)
fi

# get commit logs and determine home to bump the version
# supports #major, #minor, #patch (anything else will be 'minor')
case "$log" in
    *#major* ) new=$(semver bump major $tag);;
    *#minor* ) new=$(semver bump minor $tag);;
    *#patch* ) new=$(semver bump patch $tag);;
    * ) new=$(semver bump `echo $default_semvar_bump` $tag);;
esac

if $pre_release
then
    new="$new-${commit:0:7}"
fi

echo $new

# set outputs
echo ::set-output name=new_tag::$new
echo ::set-output name=tag::$new

# push new tag ref to github
dt=$(date '+%Y-%m-%dT%H:%M:%SZ')
full_name=$GITHUB_REPOSITORY

echo "$dt: **pushing tag $new to repo $full_name"

git tag $new $commit
git tag latest $commit
