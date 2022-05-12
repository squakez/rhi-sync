#!/bin/bash

set -e

display_usage() {

cat <<EOF
Initialize Camel K Operator Metadata repository when a minor/major new release cycle is started.

Usage: camel-k-operator-metadata-init.sh --from <major.minor> --to <major.minor> --rhi-prod-ver <yyyy.q> [options]
-d, --dry-run                 Don't push any change.
-f, --force                   Clean any local git repository already cloned and support files
    --help                    This help message

Example: camel-k-operator-metadata-init.sh -f -d --from 1.6 --to 1.9 --rhi-prod-ver 2022.Q3
EOF

}

FORCE="false"
DRY_RUN="false"

# Downstream org/repo/branch
DOWNSTREAM_ORG="jboss-fuse"
DOWNSTREAM_REPO="fuse-camel-k-prod-operator-metadata"
# mandatory variables
DOWNSTREAM_LAST_BRANCH=""
DOWNSTREAM_NEXT_BRANCH=""
VERSION=""
RHI_PROD_VER=""

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

  bump_version $VERSION

  if [ $DRY_RUN == "true" ]
  then
    echo "❗ dry-run mode on, won't push any change!"
  else
    git push --set-upstream origin $DOWNSTREAM_NEXT_BRANCH

    echo "🎉 branch published! Now, please remind to set $DOWNSTREAM_NEXT_BRANCH as default branch manually in $DOWNSTREAM_ORG/$DOWNSTREAM_REPO repository."
    echo "   Please, also remind to execute a sync process as soon as possible in order to refresh the configuration with latest version accordingly."
  fi
}

bump_version(){
  CSV_FILE="manifests/camel-k.clusterserviceversion.yaml"
  PREV_VERSION=$(yq '.spec.version' $CSV_FILE)
  echo "🔄 Updating CSV parameters to version $1 - will replace $PREV_VERSION"
  yq -i ".metadata.name = \"red-hat-camel-k-operator.v$1\"" $CSV_FILE
  yq -i ".spec.install.spec.deployments[0].template.rht.comp_ver = \"$RHI_PROD_VER\"" $CSV_FILE
  yq -i ".spec.version = \"$1\"" $CSV_FILE
  yq -i ".spec.replaces = \"red-hat-camel-k-operator.v$PREV_VERSION\"" $CSV_FILE
  git add --all
  git commit -m "Initialize branch for version $VERSION"
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
          VERSION="$1.0"
          ;;
        --rhi-prod-ver)
          shift
          RHI_PROD_VER="$1"
          ;;
        *)
          echo "❗ unknown argument: $1"
          display_usage
          exit 1
          ;;
      esac
      shift
  done

  if [ "$DOWNSTREAM_LAST_BRANCH" == "true" ] || [ "$DOWNSTREAM_NEXT_BRANCH" == "" ] || [ "$VERSION" == "" ] || [ "$RHI_PROD_VER" == "" ]
  then
    echo "❗ you must provide mandatory arguments: --to, --from and --rhi-prod-ver"
    exit 1
  fi
}

main $*
