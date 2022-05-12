#!/bin/bash

display_usage() {

cat <<EOF
Initialize Camel K runtime repository when a minor/major new release cycle is started.

Usage: camel-k-runtime-init.sh <major.minor> [options]
-d, --dry-run                 Don't push any change.
-f, --force                   Clean any local git repository already cloned and support files
    --help                    This help message
EOF

}

FORCE=""
DRY_RUN=""

main() {
  parse_args $@

  # Upstream org/repo/branch
  UPSTREAM_ORG="apache"
  UPSTREAM_REPO="camel-k-runtime"
  UPSTREAM_BRANCH="release-$VERSION_MM.x"
  # Downstream org/repo/branch
  DOWNSTREAM_ORG="jboss-fuse"
  DOWNSTREAM_REPO="camel-k-runtime"
  DOWNSTREAM_BRANCH="$UPSTREAM_BRANCH"
  # Downstream previous branch to calculate diff
  DOWNSTREAM_PREV_BRANCH="camel-k-runtime-1.9.0-branch"

  DOWNSTREAM_REMOTE="init"

  cat > /tmp/bump.sh <<EOF
  # TODO we may require to include quarkus/camel-quarkus changes here
  echo "📢 No changes required"
EOF

  cat > /tmp/diff.sh <<EOF
  diff=\$(git diff remotes/$DOWNSTREAM_REMOTE/$DOWNSTREAM_BRANCH..remotes/$DOWNSTREAM_REMOTE/$DOWNSTREAM_PREV_BRANCH --stat | grep -cv "files changed")
  if [ \$diff -gt 0 ]
  then
    echo "🖐  previous version branch have diverged from upstream! Please, take some time to verify if you need to include any important change in the new branch:"
    echo ""
    git diff remotes/$DOWNSTREAM_REMOTE/$DOWNSTREAM_BRANCH..remotes/$DOWNSTREAM_REMOTE/$DOWNSTREAM_PREV_BRANCH --stat --color | cat
    echo ""
    echo "Please make sure to manually include the changes, possibly upstream first and later synchronizing with the related sync script."
    echo "You can have a quick look at the differences by running:"
    echo ""
    echo "  git clone https://github.com/$UPSTREAM_ORG/$UPSTREAM_REPO.git"
    echo "  cd $UPSTREAM_REPO"
    echo "  git remote add -f $DOWNSTREAM_REMOTE https://github.com/$DOWNSTREAM_ORG/$DOWNSTREAM_REPO.git"
    echo "  git diff remotes/$DOWNSTREAM_REMOTE/$DOWNSTREAM_BRANCH..remotes/$DOWNSTREAM_REMOTE/$DOWNSTREAM_PREV_BRANCH"
    echo ""
    echo "Bear in mind that certain configuration use to be automatically synchronized and won't require any change."
  fi
EOF

  echo "INFO: executing rhi-init.sh \"$UPSTREAM_ORG/$UPSTREAM_REPO/$UPSTREAM_BRANCH\" \"$DOWNSTREAM_ORG/$DOWNSTREAM_REPO/$DOWNSTREAM_BRANCH\" -v \"$VERSION\" --diff-branch \"$DOWNSTREAM_PREV_BRANCH\" $FORCE $DRY_RUN"
  ./rhi-init.sh "$UPSTREAM_ORG/$UPSTREAM_REPO/$UPSTREAM_BRANCH" "$DOWNSTREAM_ORG/$DOWNSTREAM_REPO/$DOWNSTREAM_BRANCH" -v "$VERSION" --diff-branch "$DOWNSTREAM_PREV_BRANCH" "$FORCE" "$DRY_RUN"
}

parse_args(){
  # We append a patch to 0 to fill a full semantic version
  VERSION_MM="$1"
  VERSION="$VERSION_MM.0"

  if [ "$VERSION_MM" == "" ]
  then
    echo "❗ please, provide a correct version (major.minor only)"
    exit 1
  fi
  shift

  if [ "$1" == "-h" ] || [ "$1" == "--help" ]
  then
    display_usage
    exit 0
  fi

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
          DRY_RUN="-d"
          ;;
        -f|--force)
          FORCE="-f"
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

main $*
