#!/bin/bash

display_usage() {
    cat <<EOT
Synchronize a (downstream) GIT repository with changes performed in another (upstream) GIT repository.
Then, refresh vendor directory and optionally synchronize a metadata GIT repository.

Usage: rhi-sync.sh <upstream_org/repo/branch> <downstream_org/repo/branch> [options]

    --no-cherry-pick          Don't cherry pick the commits (will list them only)
    --no-metadata             Won't refresh CRDs and update metadata repository
-m, --metadata                Pull the metadata from a <metadata_org/repo/branch>
-d, --dry-run                 Don't push any change.
-f, --force                   Clean any local git repository already cloned and support files
    --help                    This help message

EOT
}

METADATA_ORG=""
METADATA_REPO=""
METADATA_BRANCH=""
METADATA_MANIFEST_DIR="manifests"
UPSTREAM_ORG=""
UPSTREAM_REPO=""
UPSTREAM_BRANCH=""
UPSTREAM_MANIFEST_DIR="/config/crd/bases"
DOWNSTREAM_ORG=""
DOWNSTREAM_REPO=""
DOWNSTREAM_REMOTE="sync"
DOWNSTREAM_BRANCH=""

DRY_RUN="false"
CHERRY_PICK="true"
UPDATE_METADATA="true"
FORCE="false"

main() {
  parse_args $@

  if [ $FORCE == "true" ]
  then
    # clean support files
    rm -f /tmp/$UPSTREAM_REPO.log /tmp/$DOWNSTREAM_REPO.log /tmp/missing-downstream /tmp/missing-upstream
    # clean git repos previously cloned
    rm -rf $UPSTREAM_REPO  $METADATA_REPO
  fi

  clone $UPSTREAM_ORG $UPSTREAM_REPO
  cd $UPSTREAM_REPO
  echo "🚜 adding $DOWNSTREAM_ORG/$DOWNSTREAM_REPO remote as $DOWNSTREAM_REMOTE"
  git remote add -f $DOWNSTREAM_REMOTE https://github.com/$DOWNSTREAM_ORG/$DOWNSTREAM_REPO.git

  # Check if the branches exist
  upstream_branch_exists=$(git branch -a | grep remotes/origin/$UPSTREAM_BRANCH)
  if [ "$upstream_branch_exists" == "" ]
  then
    echo "❗ the $UPSTREAM_BRANCH branch does not exist on $UPSTREAM_ORG/$UPSTREAM_REPO repository."
    echo "Make sure the upstream branch exists before retrying the synchronization process."
    exit -1
  fi

  downstream_branch_exists=$(git branch -a | grep remotes/$DOWNSTREAM_REMOTE/$DOWNSTREAM_BRANCH)
  if [ "$downstream_branch_exists" == "" ]
  then
    echo "❗ the $DOWNSTREAM_BRANCH branch does not exist on $DOWNSTREAM_ORG/$DOWNSTREAM_REPO repository."
    echo "Make sure the downstream branch exists before retrying the synchronization process."
    exit -1
  fi

  calculate_commits_upstream $UPSTREAM_REPO $UPSTREAM_BRANCH
  calculate_commits_downstream $DOWNSTREAM_REPO $DOWNSTREAM_REMOTE $DOWNSTREAM_BRANCH $UPSTREAM_ORG $UPSTREAM_REPO
  calculate_diff /tmp/$UPSTREAM_REPO.log /tmp/$DOWNSTREAM_REPO.log /tmp/missing-downstream
  calculate_diff /tmp/$DOWNSTREAM_REPO.log /tmp/$UPSTREAM_REPO.log /tmp/missing-upstream

  miss_downstream=$(grep -c ^ /tmp/missing-downstream)
  miss_upstream=$(grep -c ^ /tmp/missing-upstream)

  if [[ $miss_upstream != 0 ]]
  then
    echo "INFO: there are $miss_upstream commits diverged downstream - just an info, no action required"
  fi

  if [[ $miss_downstream == 0 ]]
  then
    echo "🍒  no upstream commits missing from downstream repo."
  else
    echo "INFO: there are $miss_downstream commits missing downstream."
    if [ "$CHERRY_PICK" == "true" ]
    then
      echo "INFO: I'll attempt to cherry-pick and sync. Keep tight!"
      # if this one fail, we must have someone to manually merge
      for i in `tac /tmp/missing-downstream`
        do
          echo "🍒 cherry-picking $i"
          git cherry-pick $i
          if [[ $? != 0 ]]; then
            show_how_to_fix  $UPSTREAM_ORG $UPSTREAM_REPO $DOWNSTREAM_ORG $DOWNSTREAM_REPO $DOWNSTREAM_REMOTE $DOWNSTREAM_BRANCH
          fi
          git commit --amend -m "$(git log --format=%B -n1)" -m "(cherry picked from commit $UPSTREAM_ORG/$UPSTREAM_REPO@$i)"
        done
    else
      # Show the list only
      echo "🍒 list of commits not yet ported to downstream repo (sorted by time)"
      echo ""
      tac /tmp/missing-downstream
    fi
  fi

  # refresh vendor directory
  echo "🔄  refreshing vendor directory"
  go mod vendor
  git add vendor
  git commit -m "Vendor directory refresh"
  if [ "$DRY_RUN" == "false" ]
  then
    # push the changes
    echo "📌 pushing to $DOWNSTREAM_REMOTE repo"
    git push $DOWNSTREAM_REMOTE HEAD:$DOWNSTREAM_BRANCH
  else
    echo "❗ dry-run mode on, won't push any change!"
  fi

  if [ "$UPDATE_METADATA" == "true" ]
  then
    # refresh CRDs and copy to metadata repository
    echo "🔄 refreshing manifest CRDs"
    make generate-crd
    # we’ll need the metadata repository in order to automatically sync the CRDs
    cd ..
    clone $METADATA_ORG $METADATA_REPO
    cd $METADATA_REPO
    git checkout origin/$METADATA_BRANCH
    cp ../$UPSTREAM_REPO$UPSTREAM_MANIFEST_DIR/*.yaml $METADATA_MANIFEST_DIR/.
    git add manifests
    git commit -m "Manifests directory refresh"
    if [ "$DRY_RUN" == "false" ]
    then
      echo "📌 pushing to metadata repo"
      git push origin HEAD:$METADATA_BRANCH
    else
      echo "❗ dry-run mode on, won't push any change!"
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
        --no-cherry-pick)
          CHERRY_PICK="false"
          ;;
        --no-metadata)
          UPDATE_METADATA="false"
          ;;
        -m|--metadata)
          shift
          [[ "$1" =~ $re ]]
          METADATA_ORG=${BASH_REMATCH[1]}
          METADATA_REPO=${BASH_REMATCH[2]}
          METADATA_BRANCH=${BASH_REMATCH[3]}

          if [ "$UPDATE_METADATA" == "true" ] && ( [ "$METADATA_ORG" == "" ] || [ "$METADATA_REPO" == "" ] || [ "$METADATA_BRANCH" == "" ] )
          then
            echo "❗ you must provide a metadata configuration as <org/repo/branch>"
            exit 1
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
}

clone(){
  org=$1
  repo=$2
  echo "🚜 cloning $org/$repo repo"
  git clone https://github.com/$org/$repo.git
}

calculate_commits_upstream(){
  repo=$1
  branch=$2
  # For upstream, we can get a plain list of commit IDs
  echo "🔎 calculating list of upstream commits ($repo origin/$branch)"
  git fetch origin
  git checkout origin/$branch
  git log --pretty=format:"%h" > /tmp/$repo.log
  printf "\n" >> /tmp/$repo.log
}

calculate_commits_downstream(){
  repo=$1
  remote=$2
  branch=$3
  upstream_org=$4
  upstream_repo=$5
  # For downstream, we need to extract the original commit id, if it was a cherry pick
  echo "🔎 calculating list of downstream commits ($remote/$branch)"
  git fetch $remote
  git checkout $remote/$branch
  for i in `git log --pretty=format:"%h"`
  do
    cherry_picked="false"
    commit_message=$(git rev-list --format=%s%b --max-count=1 $i | tail +2)
      while IFS= read -r line; do
        re="\(cherry picked from commit $upstream_org/$upstream_repo@([^\)]+)\)"
        [[ "$line" =~ $re ]]
        cherry_pick=${BASH_REMATCH[1]}
        if [[ ! -z "$cherry_pick" ]]; then
          cherry_picked="true"
          # Append the original commit id
          printf "$cherry_pick\n" >> /tmp/$repo.log
        fi
      done <<< "$commit_message"
    # Not cherry-picked, belong to the same tree
    if [ "$cherry_picked" == "false" ]
    then
      printf "$i\n" >> /tmp/$repo.log
    fi
  done
}

calculate_diff(){
  file1=$1
  file2=$2
  fileresult=$3

  touch $fileresult
  for commit in `cat $file1`
  do
    if [[ $(grep -c $commit $file2) == 0 ]]
    then
      printf "$commit\n" >> $fileresult
    fi
  done
}

show_how_to_fix(){
  UPSTREAM_ORG=$1
  UPSTREAM_REPO=$2
  DOWNSTREAM_ORG=$3
  DOWNSTREAM_REPO=$4
  DOWNSTREAM_REMOTE=$5
  DOWNSTREAM_BRANCH=$6

  echo "❗ Some conflict detected on commit $i. Sorry, I cannot do much more, please fix it manually."
  echo "Here a suggestion to help you fix the problem:"
  echo ""
  echo "  git clone https://github.com/$UPSTREAM_ORG/$UPSTREAM_REPO.git"
  echo "  cd $UPSTREAM_REPO"
  echo "  git remote add -f $DOWNSTREAM_REMOTE https://github.com/$DOWNSTREAM_ORG/$DOWNSTREAM_REPO.git"
  echo "  git checkout $DOWNSTREAM_REMOTE/$DOWNSTREAM_BRANCH"
  echo "  git cherry-pick $i"
  echo "  # FIX the conflict manually"
  echo "  git cherry-pick --continue"
  echo "  git commit --amend -m \"\$(git log --format=%B -n1)\" -m \"Conflict fixed manually\" -m \"(cherry picked from commit $UPSTREAM_ORG/$UPSTREAM_REPO@$i)\""
  echo "  git push $DOWNSTREAM_REMOTE HEAD:$DOWNSTREAM_BRANCH"
  echo ""
  echo "Notice that you must report the fixed resolution in a downstream commit appending the following message line: \"(cherry picked from commit $UPSTREAM_ORG/$UPSTREAM_REPO@$i)\""
  echo ""
  echo "NOTE: you may even provide a single empty commit adding the line \"(cherry picked from commit $UPSTREAM_ORG/$UPSTREAM_REPO@commit-hash)\" for each upstream commit manually fixed in the downstream repo. This last strategy can be used also as a workaround in the rare case you need to skip some commit from the syncronization process."
  exit 1
}

main $*
