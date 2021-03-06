#!/bin/bash

display_usage() {

cat <<EOF
Initialize Camel K repository when a minor/major new release cycle is started.

Usage: camel-k-init.sh --from <major.minor> --to <major.minor> [options]
-d, --dry-run                 Don't push any change.
-f, --force                   Clean any local git repository already cloned and support files
    --help                    This help message

Example: camel-k-init.sh -f -d --from 1.6 --to 1.9
EOF

}

FORCE=""
DRY_RUN=""
FROM=""
TO=""

main() {
  parse_args $@

  # full semantic version
  VERSION="$TO.0"
  # Upstream org/repo/branch
  UPSTREAM_ORG="apache"
  UPSTREAM_REPO="camel-k"
  UPSTREAM_BRANCH="release-$TO.x"
  # Downstream org/repo/branch
  DOWNSTREAM_ORG="jboss-fuse"
  DOWNSTREAM_REPO="camel-k"
  DOWNSTREAM_BRANCH="$UPSTREAM_BRANCH"
  # Downstream previous branch to calculate diff
  # TODO: must be changed to release-m.m.x convention in next release
  DOWNSTREAM_PREV_BRANCH="$FROM.0.redhat-8-0-x"

  DOWNSTREAM_REMOTE="init"

  cat > /tmp/bump.sh <<EOF
  echo "📢 bumping to version $VERSION"
  sed -i -E "s/VERSION \?=.+/VERSION ?= $VERSION/" script/Makefile
  make set-version
  echo "📢 removing vendor directory from .gitignore"
  sed -i -E "s/\/vendor//" .gitignore
  git add --all
  git commit -m "Initialize repo with $VERSION"
EOF

  cat > /tmp/diff.sh <<EOF
  # Filter anything in vendor, config, helm and makefile which has the changed version
  diff=\$(git diff remotes/$DOWNSTREAM_REMOTE/$DOWNSTREAM_BRANCH..remotes/$DOWNSTREAM_REMOTE/$DOWNSTREAM_PREV_BRANCH --shortstat)
  if [[ "\$diff" != "" ]]
  then
    echo "🖐  previous version branch have diverged from upstream! Please, take some time to verify if you need to include any important change in the new branch:"
    echo ""
    git diff remotes/$DOWNSTREAM_REMOTE/$DOWNSTREAM_BRANCH..remotes/$DOWNSTREAM_REMOTE/$DOWNSTREAM_PREV_BRANCH --shortstat
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
EOF

  echo "INFO: executing rhi-init.sh \"$UPSTREAM_ORG/$UPSTREAM_REPO/$UPSTREAM_BRANCH\" \"$DOWNSTREAM_ORG/$DOWNSTREAM_REPO/$DOWNSTREAM_BRANCH\" -v \"$VERSION\" --diff-branch \"$DOWNSTREAM_PREV_BRANCH\" $FORCE $DRY_RUN"
  ./rhi-init.sh "$UPSTREAM_ORG/$UPSTREAM_REPO/$UPSTREAM_BRANCH" "$DOWNSTREAM_ORG/$DOWNSTREAM_REPO/$DOWNSTREAM_BRANCH" -v "$VERSION" --diff-branch "$DOWNSTREAM_PREV_BRANCH" "$FORCE" "$DRY_RUN"
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
          DRY_RUN="-d"
          ;;
        -f|--force)
          FORCE="-f"
          ;;
        --from)
          shift
          if ! [[ $1 =~ $re ]];
          then
            echo "❗ --from argument must match major.minor semantic version: $1"
            exit 1
          fi
          FROM="$1"
          ;;
        --to)
          shift
          if ! [[ $1 =~ $re ]];
          then
            echo "❗ --to argument must match major.minor semantic version: $1"
            exit 1
          fi
          TO="$1"
          ;;
        *)
          echo "❗ unknown argument: $1"
          display_usage
          exit 1
          ;;
      esac
      shift
  done

  if [ "$FROM" == "" ] || [ "$TO" == "" ]
  then
    echo "❗ you must provide mandatory arguments: --to and --from"
    exit 1
  fi
}

main $*
