#!/bin/sh

set -e

if [[ -z "$GITHUB_TOKEN" ]]; then
  echo "Set the GITHUB_TOKEN environment variable."
  exit 1
fi

if [[ ! -z "$INPUT_SOURCE_BRANCH" ]]; then
  SOURCE_BRANCH="$INPUT_SOURCE_BRANCH"
elif [[ ! -z "$GITHUB_REF" ]]; then
  SOURCE_BRANCH=${GITHUB_REF/refs\/heads\//}  # Remove branch prefix
else
  echo "Set the INPUT_SOURCE_BRANCH environment variable or trigger from a branch."
  exit 1
fi

DESTINATION_BRANCH="${INPUT_DESTINATION_BRANCH:-"master"}"

# Github actions no longer auto set the username and GITHUB_TOKEN
git remote set-url origin "https://$GITHUB_ACTOR:$GITHUB_TOKEN@github.com/$GITHUB_REPOSITORY"

# Pull all branches references down locally so subsequent commands can see them
git fetch origin '+refs/heads/*:refs/heads/*'

if [ "$(git rev-parse --revs-only "$SOURCE_BRANCH")" = "$(git rev-parse --revs-only "$DESTINATION_BRANCH")" ]; then 
  echo "Source and destination branches are the same." 
  exit 0
fi

# Do not proceed if there are no file differences, this avoids PRs with just a merge commit and no content
LINES_CHANGED=$(git diff --name-only "$DESTINATION_BRANCH" "$SOURCE_BRANCH" | wc -l | awk '{print $1}')
if [[ "$LINES_CHANGED" = "0" ]]; then 
  echo "No file changes detected between source and destination branches." 
  exit 0
fi


# Workaround for `hub` auth error https://github.com/github/hub/issues/2149#issuecomment-513214342
export GITHUB_USER="$GITHUB_ACTOR"

PR_ARG="$INPUT_PR_TITLE"
if [[ ! -z "$PR_ARG" ]]; then
  PR_ARG="-m \"$PR_ARG\""

  if [[ ! -z "$INPUT_PR_BODY" ]]; then
    PR_ARG="$PR_ARG -m \"$INPUT_PR_BODY\""
  fi
fi

if [[ ! -z "$INPUT_PR_REVIEWER" ]]; then

  # Split string into array
  IFS=',' read -r -a REVIEWER_ARRAY <<< "$INPUT_PR_REVIEWER"

  # Delete the $GITHUB_ACTOR from array
  REVIEWER_ARRAY=${REVIEWER_ARRAY[@]/$GITHUB_ACTOR}

  # Select random string from array and place into PR_ARG
  REVIEWER=${REVIEWER_ARRAY[RANDOM%${#REVIEWER_ARRAY[@]}]}

  PR_ARG="$PR_ARG -r \"$REVIEWER\""
fi

if [[ ! -z "$INPUT_PR_LABEL" ]]; then
  PR_ARG="$PR_ARG -l \"$INPUT_PR_LABEL\""
fi


COMMAND="hub pull-request \
  -b $DESTINATION_BRANCH \
  -h $SOURCE_BRANCH \
  --no-edit \
  $PR_ARG \
  || true"

echo "$COMMAND"
sh -c "$COMMAND"
