#!/bin/bash

display_usage() {
    cat <<EOT
Initialize a repo starting from another repo.

Usage: camel-k-init.sh <major.minor-camel-k-version> -r <camel-k-runtime-version> [options]

-d, --dry-run                 Don't push any change.
-f, --force                   Clean any local git repository already cloned and support files
-r, --runtime                 Camel K Runtime version to be used
    --diff-branch             Check the differences with another downstream branch to spot any important change that was not included upstream
    --diff-version            Check the differences with another version to spot any important change that was not included upstream
    --help                    This help message

EOT
}

UPSTREAM_ORG="camel-sync"
UPSTREAM_REPO="camel-k-upstream"
UPSTREAM_BRANCH=""
DOWNSTREAM_ORG="camel-sync"
DOWNSTREAM_REPO="camel-k-downstream"
DOWNSTREAM_REMOTE="bump"
DOWNSTREAM_BRANCH=""
DOWNSTREAM_PREV_BRANCH=""

CAMEL_K_VERSION=""
CAMEL_K_RUNTIME_VERSION=""

FORCE="false"
DRY_RUN="false"

main() {
  parse_args $@

  if [ $FORCE == "true" ]
  then
    # clean git repos previously cloned
    rm -rf $UPSTREAM_REPO
  fi

  clone $UPSTREAM_ORG $UPSTREAM_REPO
  cd $UPSTREAM_REPO
  echo "🚜 adding $DOWNSTREAM_ORG/$DOWNSTREAM_REPO remote as $DOWNSTREAM_REMOTE"
  git remote add -f $DOWNSTREAM_REMOTE https://github.com/$DOWNSTREAM_ORG/$DOWNSTREAM_REPO.git

  # Check if the branches exist
  upstream_branch_exists=$(git branch -a | grep remotes/origin/$UPSTREAM_BRANCH)
  if [ "$upstream_branch_exists" == "" ]
  then
    echo "❗ the $UPSTREAM_BRANCH branch does not exists on $UPSTREAM_ORG/$UPSTREAM_REPO repository. Bump process aborted."
    echo "Make sure the upstream branch exists before retrying the initialization process."
    exit -1
  fi

  downstream_branch_exists=$(git branch -a | grep remotes/$DOWNSTREAM_REMOTE/$DOWNSTREAM_BRANCH)
  if [ "$downstream_branch_exists" != "" ]
  then
    echo "❗ the $DOWNSTREAM_BRANCH branch already exists on $DOWNSTREAM_ORG/$DOWNSTREAM_REPO repository. Bump process aborted."
    echo "You may delete the downstream branch and retry the initialization process."
    exit -1
  fi

  git fetch origin
  git checkout origin/$UPSTREAM_BRANCH
  # Bump appropriately
  echo "📢 bumping to version $CAMEL_K_VERSION"
  sed -i -E "s/VERSION \?=.+/VERSION ?= $CAMEL_K_VERSION/" script/Makefile
  sed -i -E "s/RUNTIME_VERSION := \?=.+/RUNTIME_VERSION := $CAMEL_K_RUNTIME_VERSION/" script/Makefile
  make set-version
  git add --all
  git commit -m "Initialize downstream repo to $CAMEL_K_VERSION"

  if [ "$DRY_RUN" == "false" ]
  then
    # push the new branch
    echo "📌 pushing to $DOWNSTREAM_REMOTE/$DOWNSTREAM_BRANCH branch"
    git push $DOWNSTREAM_REMOTE HEAD:refs/heads/$DOWNSTREAM_BRANCH
    echo "🎉 branch published! Now, remind to set $DOWNSTREAM_REMOTE/$DOWNSTREAM_BRANCH as default branch manually, please"
  else
    echo "❗ dry-run mode on, won't push any change!"
  fi

  if [ "$DOWNSTREAM_PREV_BRANCH" != "" ]
  then
    # Filter anything in vendor, config, helm and makefile which has the changed version
    diff=$(git diff remotes/$DOWNSTREAM_REMOTE/$DOWNSTREAM_BRANCH..remotes/$DOWNSTREAM_REMOTE/$DOWNSTREAM_PREV_BRANCH --stat | \
      grep -v vendor | grep -v \\.\\.\\. | grep -v config/ | grep -v helm/ | grep -v script/Makefile | grep -cv "files changed"\
      )
    if [ $diff -gt 0 ]
    then
      echo "🖐  previous version branch have diverged from upstream! Please, take some time to verify if you need to include any important change in the new branch:"
      echo ""
      git diff remotes/$DOWNSTREAM_REMOTE/$DOWNSTREAM_BRANCH..remotes/$DOWNSTREAM_REMOTE/$DOWNSTREAM_PREV_BRANCH --stat | \
        grep -v vendor | grep -v \\.\\.\\. | grep -v config/ | grep -v helm/ | grep -v script/Makefile | grep -v "files changed"
      echo ""
      echo "Please make sure to manually include the changes, possibly upstream first and later synchronizing with the related sync script."
      echo "You can have a quick look at the differences by running:"
      echo ""
      echo "  git clone https://github.com/$UPSTREAM_ORG/$UPSTREAM_REPO.git"
      echo "  cd $UPSTREAM_REPO"
      echo "  git remote add -f $DOWNSTREAM_REMOTE https://github.com/$DOWNSTREAM_ORG/$DOWNSTREAM_REPO.git"
      echo "  git diff remotes/$DOWNSTREAM_REMOTE/$DOWNSTREAM_BRANCH..remotes/$DOWNSTREAM_REMOTE/$DOWNSTREAM_PREV_BRANCH"
      echo ""
      echo "Bear in mind that certain directories such as vendor/ (downstream only), config/ or helm/ use to be automatically synchronized and won't require any change."
    fi
  fi
}

parse_args(){
  if [ "$1" == "-h" ] || [ "$1" == "--help" ]
  then
    display_usage
    exit 0
  fi
  re_mm='^[[:digit:]]+\.[[:digit:]]+$'
  re_full='^[[:digit:]]+\.[[:digit:]]+\.[[:digit:]]+$'

  # camel k version
  if [[ "$1" =~ $re_mm ]]
  then
    CAMEL_K_VERSION="$1"
  else
    echo "❗ you must provide a Camel K major.minor semantic version, ie 1.8"
    exit 1
  fi
  UPSTREAM_BRANCH="release-$1.x"
  DOWNSTREAM_BRANCH="$1.0-redhat-8-0-x"
  shift
  # Parse command line options
  while [ $# -gt 0 ]
  do
      arg="$1"

      case $arg in
        -h|--help)
          display_usage
          exit 0
          ;;
        -d|--dry-run)
          DRY_RUN="true"
          ;;
        -f|--force)
          FORCE="true"
          ;;
        -r|--runtime)
          shift
          CAMEL_K_RUNTIME_VERSION="$1"
          ;;
        --diff-branch)
          shift
          DOWNSTREAM_PREV_BRANCH="$1"
          ;;
        --diff-version)
          shift
          if [[ ! "$1" =~ $re_mm ]]
          then
            echo "❗ you must provide a Camel K Runtime semantic version, ie 1.9.0"
            exit 1
          else
            DOWNSTREAM_PREV_BRANCH="$1.0-redhat-8-0-x"
          fi
          ;;
        *)
          echo "❗ unknown argument: $1"
          display_usage
          exit 1
          ;;
      esac
      shift
  done

  # Validation
  if [[ ! "$CAMEL_K_RUNTIME_VERSION" =~ $re_full ]]
  then
    echo "❗ you must provide a Camel K Runtime semantic version, ie 1.9.0"
    exit 1
  fi
}

clone(){
  org=$1
  repo=$2
  echo "🚜 cloning $org/$repo repo"
  git clone https://github.com/$org/$repo.git
}

main $*
