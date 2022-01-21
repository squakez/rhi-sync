#!/bin/bash

set -e

CAMEL_K_VERSION=""
CAMEL_K_RUNTIME_VERSION=""
KAMELET_CATALOG_VERSION=""

CAMEL_K_UPSTREAM=""
CAMEL_K_DOWNSTREAM=""
CAMEL_K_METADATA=""
CAMEL_K_RUNTIME_UPSTREAM=""
CAMEL_K_RUNTIME_DOWNSTREAM=""
KAMELET_CATALOG_UPSTREAM=""
KAMELET_CATALOG_DOWNSTREAM=""

DRY_RUN=""
FORCE=""

display_usage() {
    cat <<EOT
Synchronize Camel K project repositories between upstream and downstream.

Usage: camel-k-sync.sh -ck <major.minor-camel-k-version> -r <major.minor-camel-k-runtime-version> -k <major.minor-kamelet-catalog-version> [options]

-ck                           Camel K version
-r                            Camel K Runtime version
-k                            Kamelet Catalog version
-d, --dry-run                 Don't push any change.
-f, --force                   Clean any local git repository already cloned and support files
    --help                    This help message

EOT
}

main() {
  parse_args $@
  validate_args

  echo "INFO: synchronizing $CAMEL_K_DOWNSTREAM with $CAMEL_K_UPSTREAM ..."
  ./rhi-sync.sh $CAMEL_K_UPSTREAM $CAMEL_K_DOWNSTREAM --metadata $CAMEL_K_METADATA $FORCE $DRY_RUN
  echo "INFO: synchronizing $CAMEL_K_RUNTIME_DOWNSTREAM with $CAMEL_K_RUNTIME_UPSTREAM ..."
  ./rhi-sync.sh $CAMEL_K_RUNTIME_UPSTREAM $CAMEL_K_RUNTIME_DOWNSTREAM --no-metadata --no-vendor $FORCE $DRY_RUN

  # TODO find a strategy for Kamelet Catalog synchronization
  # in the while, let's give a reminder
  echo ""
  echo "WARNING: Kamelet Catalog is not yet synchronized. Make sure you've backported everything needed from $KAMELET_CATALOG_UPSTREAM into $KAMELET_CATALOG_DOWNSTREAM"
}

parse_args(){
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
          DRY_RUN="-f"
          ;;
        -f|--force)
          FORCE="-f"
          ;;
        -ck)
          shift
          CAMEL_K_VERSION="$1"
          ;;
        -r)
          shift
          CAMEL_K_RUNTIME_VERSION="$1"
        ;;
        -k)
          shift
          KAMELET_CATALOG_VERSION="$1"
        ;;
        *)
          echo "❗ unknown argument: $1"
          display_usage
          exit 1
          ;;
      esac
      shift
  done
}

validate_args(){
  re='[[:digit:]]+\.[[:digit:]]+'
  if [[ ! "$CAMEL_K_VERSION" =~ $re ]]
  then
    echo "❗ you must provide a major.minor Camel K version, ie, 1.7 (it was $CAMEL_K_VERSION)"
    exit 2
  fi
  if [[ ! "$CAMEL_K_RUNTIME_VERSION" =~ $re ]]
  then
    echo "❗ you must provide a major.minor Camel K Runtime version, ie, 1.9 (it was $CAMEL_K_RUNTIME_VERSION)"
    exit 2
  fi
  if [[ ! "$KAMELET_CATALOG_VERSION" =~ $re ]]
  then
    echo "❗ you must provide a major.minor Kamelet Catalog version, ie, 0.6 (it was $KAMELET_CATALOG_VERSION)"
    exit 2
  fi

  CAMEL_K_UPSTREAM="camel-sync/camel-k-upstream/release-$CAMEL_K_VERSION.x"
  CAMEL_K_DOWNSTREAM="camel-sync/camel-k-downstream/$CAMEL_K_VERSION.0-redhat-8-0-x"
  CAMEL_K_METADATA="camel-sync/camel-k-metadata/camelk-$CAMEL_K_VERSION-openshift-rhel-8"
  CAMEL_K_RUNTIME_UPSTREAM="camel-sync/camel-k-runtime-upstream/release-$CAMEL_K_RUNTIME_VERSION.x"
  CAMEL_K_RUNTIME_DOWNSTREAM="camel-sync/camel-k-runtime-downstream/camel-k-runtime-$CAMEL_K_RUNTIME_VERSION.0-branch"
  KAMELET_CATALOG_UPSTREAM="camel-sync/kamelet-catalog-upstream/$KAMELET_CATALOG_VERSION.x"
  KAMELET_CATALOG_DOWNSTREAM="camel-sync/kamelet-catalog-downstream/kamelet-catalog-$CAMEL_K_VERSION"
}

main $*
