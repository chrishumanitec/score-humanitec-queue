#!/bin/bash

API_PREFIX=https://api.humanitec.io
HUMANITEC_CONTEXT="${HUMANITEC_CONTEXT:-/orgs/chris-test-org/apps/score-test/envs/dev}"

. request.sh

# Get active deployment in the environment so that we have a safe timestamp that is before any possible deployment our 
# delta would be in.

resp="$(make_request GET "$HUMANITEC_CONTEXT")"
if [ "$(get_status_code "${resp}")" -ge 400 ]
then
  http_error "$(get_status_code "${resp}")" >&2
  return 1
fi

active_deploy_timestamp="$(get_response_body "${resp}" | jq .last_deploy.created_at)"



DELTA_ID=""

while [ -n "$DELTA_ID" ]
do
# Fetch all non-archived deltas for the environment, filter by comment and return ID of the 1st one created

# Create a new delta if necessary. Don't use this value incase we create a delta at the same time as someone else. (Race condition)

done

# There is a potential race condition here, where this delta is deployed before we hace a chance to update it.

# Add score to the delta

# Wait for the delta to be deployed


DEPLOY_STATUS=""
DEPLOY_WITH_DELTA=""
LAST_DELTA_CREATED=""

# Wait for the current deployment to finished
while [ -n "$DEPLOY_STATUS" ]
do

  if [ -n "$DEPLOY_WITH_DELTA" ]
  then
    # Get the $DEPLOY_WITH_DELTA
  else
    # We don't know which 
  # Fetch current deployment

  current_deploy_status="$(echo "$current_deploy" | jq .status)"
  current_deploy_delta_id="$(echo "$DEPLOY" | jq .delta_id)"
  if [ "$current_deploy_delta_id" == "$DELTA_ID" ]
  then
    if [ "$status" != "in progress" ]
    then
      DEPLOY_STATUS="$current_deploy_status"
    fi
  else
    if [ "$status" != "in progress" ]
    then
  fi
      # attempt deploy
    else
      DEPLOY_STATUS="$current_deploy_status"
    fi
  elif [ "$status" != "in progress"]
  then
  fi
  # if <> in progress

  sleep 10
done