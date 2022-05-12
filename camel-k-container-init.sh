#!/bin/bash

set -e

display_usage() {

cat <<EOF
Initialize Camel K Container image repository when a minor/major new release cycle is started.

Usage: camel-k-container-init.sh --from <major.minor> --to <major.minor> [options]
-d, --dry-run                 Don't push any change.
-f, --force                   Clean any local git repository already cloned and support files
    --help                    This help message

Example: camel-k-container-init.sh -f -d --from 1.6 --to 1.9
EOF

}

FORCE="false"
DRY_RUN="false"

# Downstream org/repo/branch
DOWNSTREAM_ORG="jboss-fuse"
DOWNSTREAM_REPO="fuse-camel-k"
DOWNSTREAM_LAST_BRANCH=""
DOWNSTREAM_NEXT_BRANCH=""

main() {
  parse_args $@

  if [ $FORCE == "true" ]
  then
    # clean git repos previously cloned
    rm -rf $DOWNSTREAM_REPO
  fi

  clone $DOWNSTREAM_ORG $DOWNSTREAM_REPO
  cd $DOWNSTREAM_REPO

  git checkout $DOWNSTREAM_LAST_BRANCH
  git checkout -b $DOWNSTREAM_NEXT_BRANCH

  if [ $DRY_RUN == "true" ]
  then
    echo "❗ dry-run mode on, won't push any change!"
  else
    git push --set-upstream origin $DOWNSTREAM_NEXT_BRANCH

    echo "🎉 branch published! Now, please remind to set $DOWNSTREAM_NEXT_BRANCH as default branch manually in $DOWNSTREAM_ORG/$DOWNSTREAM_REPO repository."
  fi
}

clone(){
  org=$1
  repo=$2
  echo "🚜 cloning $org/$repo repo"
  git clone https://github.com/$org/$repo.git
}

parse_args(){
  re="^[[:digit:]]+\.[[:digit:]]+$"
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
        --from)
          shift
          if ! [[ $1 =~ $re ]];
          then
            echo "❗ --from argument must match major.minor semantic version: $1"
            exit 1
          fi
          DOWNSTREAM_LAST_BRANCH="camelk-$1-openshift-rhel-8"
          ;;
        --to)
          shift
          if ! [[ $1 =~ $re ]];
          then
            echo "❗ --to argument must match major.minor semantic version: $1"
            exit 1
          fi
          DOWNSTREAM_NEXT_BRANCH="camelk-$1-openshift-rhel-8"
          ;;
        *)
          echo "❗ unknown argument: $1"
          display_usage
          exit 1
          ;;
      esac
      shift
  done

  if [ "$DOWNSTREAM_LAST_BRANCH" == "" ] || [ "$DOWNSTREAM_NEXT_BRANCH" == "" ]
  then
    echo "❗ you must provide mandatory arguments: --to and --from"
    exit 1
  fi
}

main $*
