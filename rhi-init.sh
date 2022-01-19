#!/bin/bash

display_usage() {
    cat <<EOT
Initialize a repo starting from another repo. You must provide an initialization script in /tmp/bump.sh and a branch comparison script in /tmp/diff.sh.

Usage: rhi-init.sh <upstream_org/repo/branch> <downstream_org/repo/branch> -v <version> [options]

-d, --dry-run                 Don't push any change.
-f, --force                   Clean any local git repository already cloned and support files
-v, --version                 The new version to set
    --diff-branch             Check the differences with another downstream branch to spot any important change that was not included upstream
    --help                    This help message

EOT
}

UPSTREAM_ORG=""
UPSTREAM_REPO=""
UPSTREAM_BRANCH=""
DOWNSTREAM_ORG=""
DOWNSTREAM_REPO=""
DOWNSTREAM_REMOTE="init"
DOWNSTREAM_BRANCH=""
DOWNSTREAM_PREV_BRANCH=""

VERSION=""

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
    echo ""
    echo "Make sure the upstream branch exists before retrying the initialization process."
    exit -1
  fi

  downstream_branch_exists=$(git branch -a | grep remotes/$DOWNSTREAM_REMOTE/$DOWNSTREAM_BRANCH)
  if [ "$downstream_branch_exists" != "" ]
  then
    echo "❗ the $DOWNSTREAM_BRANCH branch already exists on $DOWNSTREAM_ORG/$DOWNSTREAM_REPO repository. Bump process aborted."
    echo ""
    echo "You may delete the downstream branch and retry the initialization process."
    exit -1
  fi

  git fetch origin
  git checkout origin/$UPSTREAM_BRANCH
  # Initialize process may vary depending the project
  chmod +x /tmp/bump.sh
  source /tmp/bump.sh

  if [ "$DRY_RUN" == "false" ]
  then
    # push the new branch
    echo ""
    echo "📌 pushing to $DOWNSTREAM_REPO/$DOWNSTREAM_BRANCH branch"
    git push $DOWNSTREAM_REMOTE HEAD:refs/heads/$DOWNSTREAM_BRANCH
    echo "🎉 branch published! Now, please remind to set $DOWNSTREAM_BRANCH as default branch manually in $DOWNSTREAM_ORG/$DOWNSTREAM_REPO"
  else
    echo ""
    echo "❗ dry-run mode on, won't push any change!"
  fi

  if [ "$DOWNSTREAM_PREV_BRANCH" != "" ]
  then
    downstream_prev_branch_exists=$(git branch -a | grep remotes/$DOWNSTREAM_REMOTE/$DOWNSTREAM_PREV_BRANCH)
    if [ "$downstream_prev_branch_exists" == "" ]
    then
      echo ""
      echo "❗ the $DOWNSTREAM_PREV_BRANCH branch does not exists on $DOWNSTREAM_ORG/$DOWNSTREAM_REPO repository. Cannot provide a comparison."
      echo "Please, make sure to manually check that no important development downstream is missing."
    else
      # Diff process may vary depending the project
      chmod +x /tmp/diff.sh
      source /tmp/diff.sh
    fi
  fi
}

parse_args(){
  if [ "$1" == "-h" ] || [ "$1" == "--help" ]
  then
    display_usage
    exit 0
  fi
  re="([^\/]+)\/([^\/]+)\/([^\/]+)"
  [[ "$1" =~ $re ]]
  UPSTREAM_ORG=${BASH_REMATCH[1]}
  UPSTREAM_REPO=${BASH_REMATCH[2]}
  UPSTREAM_BRANCH=${BASH_REMATCH[3]}
  if [ "$UPSTREAM_ORG" == "" ] || [ "$UPSTREAM_REPO" == "" ] || [ "$UPSTREAM_BRANCH" == "" ]
  then
    echo "❗ you must provide an upstream configuration as <org/repo/branch>"
    exit 1
  fi
  shift
  [[ "$1" =~ $re ]]
  DOWNSTREAM_ORG=${BASH_REMATCH[1]}
  DOWNSTREAM_REPO=${BASH_REMATCH[2]}
  DOWNSTREAM_BRANCH=${BASH_REMATCH[3]}
  if [ "$DOWNSTREAM_ORG" == "" ] || [ "$DOWNSTREAM_REPO" == "" ] || [ "$DOWNSTREAM_BRANCH" == "" ]
  then
    echo "❗ you must provide a downstream configuration as <org/repo/branch>"
    exit 1
  fi
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
        -v|--version)
          shift
          VERSION="$1"
          ;;
        --diff-branch)
          shift
          DOWNSTREAM_PREV_BRANCH="$1"
          ;;
        *)
          echo "❗ unknown argument: $1"
          display_usage
          exit 1
          ;;
      esac
      shift
  done

  if [ "$VERSION" == "" ]
  then
    echo "❗ please, provide -v|--version argument"
    exit 0
  fi
}

clone(){
  org=$1
  repo=$2
  echo "🚜 cloning $org/$repo repo"
  git clone https://github.com/$org/$repo.git
}

main $*
