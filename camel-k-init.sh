#!/bin/bash

# We append a patch to 0 to fill a full semantic version
VERSION_MM="$1"
VERSION="$VERSION_MM.0"

if [ "$VERSION" == "" ]
then
  echo "❗ please, provide a correct version"
  exit 1
fi

UPSTREAM_ORG="camel-sync"
UPSTREAM_REPO="camel-k-upstream"
UPSTREAM_BRANCH="release-$VERSION_MM.x"
DOWNSTREAM_ORG="camel-sync"
DOWNSTREAM_REPO="camel-k-downstream"
DOWNSTREAM_REMOTE="init"
DOWNSTREAM_BRANCH="$VERSION_MM.0-redhat-8-0-x"
DOWNSTREAM_PREV_BRANCH="downstream-1.6"

cat > /tmp/bump.sh <<EOF
echo "📢 bumping to version $VERSION"
sed -i -E "s/VERSION \?=.+/VERSION ?= $VERSION/" script/Makefile
make set-version
git add --all
git commit -m "Initialize repo with $VERSION"
EOF

cat > /tmp/diff.sh <<EOF
# Filter anything in vendor, config, helm and makefile which has the changed version
diff=\$(git diff remotes/$DOWNSTREAM_REMOTE/$DOWNSTREAM_BRANCH..remotes/$DOWNSTREAM_REMOTE/$DOWNSTREAM_PREV_BRANCH --stat | \
  grep -v vendor | grep -v \\.\\.\\. | grep -v config/ | grep -v helm/ | grep -v script/Makefile | grep -cv "files changed"\
  )
if [ \$diff -gt 0 ]
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
EOF

echo "INFO: executing rhi-init.sh \"$UPSTREAM_ORG/$UPSTREAM_REPO/$UPSTREAM_BRANCH\" \"$DOWNSTREAM_ORG/$DOWNSTREAM_REPO/$DOWNSTREAM_BRANCH\" -v \"$VERSION\" --diff-branch \"$DOWNSTREAM_PREV_BRANCH\" -f"
./rhi-init.sh "$UPSTREAM_ORG/$UPSTREAM_REPO/$UPSTREAM_BRANCH" "$DOWNSTREAM_ORG/$DOWNSTREAM_REPO/$DOWNSTREAM_BRANCH" -v "$VERSION" --diff-branch "$DOWNSTREAM_PREV_BRANCH" -f
