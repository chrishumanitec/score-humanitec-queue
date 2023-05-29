#!/bin/bash

. request.sh

orig_args=("${@}")
pos_params=()
ORG_ID=""
APP_ID=""
ENV_ID=""
HUMANITEC_TOKEN=""
while (( $# ))
do
  case "${1}" in
    --org)
      ORG_ID="$2"
      shift
      ;;
    --org=*)
      ORG_ID="${1#--org=}"
      ;;
    --app)
      APP_ID="$2"
      shift
      ;;
    --app=*)
      APP_ID="${1#--app=}"
      ;;
    --env)
      ENV_ID="$2"
      shift
      ;;
    --env=*)
      ENV_ID="${1#--env=}"
      ;;
    --token)
      HUMANITEC_TOKEN="$2"
      shift
      ;;
    --token=*)
      HUMANITEC_TOKEN="${1#--env=}"
      ;;
    --delta|--delta=*|--deploy)
      echo "${1} flag provided. Not supported by this script." >&2
      exit 1
      ;;
    *)
      # Skip other flags and guess if they take parameters by seeing if the next arg starts with a -
      if [[ "${1}" == --* ]]
      then
        if [[ "${1}" =~ ^--[^=]+$ ]] && [[ ${2} != -* ]]
        then
          shift
        fi
      else
        pos_params+=("${1}")
      fi
      ;;
  esac
  shift
done

if [ -z "$ORG_ID" ] || [ -z "$APP_ID" ] || [ -z "$ENV_ID" ] || [ -z "$HUMANITEC_TOKEN" ]
then
  [ -z "$ORG_ID" ] && echo -"--org flag missing" >&2
  [ -z "$APP_ID" ] && echo -"--app flag missing" >&2
  [ -z "$ENV_ID" ] && echo -"--env flag missing" >&2
  [ -z "$HUMANITEC_TOKEN" ] && echo -"--token flag missing" >&2
  exit 1
fi

if [ "${pos_params[0]}" != "delta" ]
then
  echo "Script only support the \"delta\" command on score-humanitec." >&2
  exit 1
fi



# Get active deployment in the environment so that we have a safe timestamp that is before any possible deployment our 
# delta would be in.

[ "${DEBUG:-0}" -ge 1 ] && echo "Fetching active deployment in environment."
resp="$(make_request GET "/orgs/${ORG_ID}/apps/${APP_ID}/envs/${ENV_ID}")"
if [ "$(get_status_code "${resp}")" -ge 400 ]
then
  echo -n "Unable to fetch environment /orgs/${ORG_ID}/apps/${APP_ID}/envs/${ENV_ID}: " >&2
  http_error "$(get_status_code "${resp}")" >&2
  exit 1
fi

active_deploy_timestamp="$(get_response_body "${resp}" | jq -r .last_deploy.created_at)"
[ "${DEBUG:-0}" -ge 1 ] && echo "Last deployment in ${ENV_ID} deployment started at ${active_deploy_timestamp}."

#
# Phase 1: Retrieves the first delta that is not archived which has the name `score-humanitec-automation`.
#

# Get the DELTA_ID we will be updating

DELTA_ID=""

while [ -z "$DELTA_ID" ]
do
  
  [ "${DEBUG:-0}" -ge 1 ] && echo "Fetch all non-archived deltas for the environment"
  # Fetch all non-archived deltas for the environment, filter by comment and return ID of the 1st one created
  resp="$(make_request GET "/orgs/${ORG_ID}/apps/${APP_ID}/deltas?env=${ENV_ID}")"
  if [ "$(get_status_code "${resp}")" -ge 400 ]
  then
    echo -n "Unable to fetch deltas in app /orgs/${ORG_ID}/apps/${APP_ID}: " >&2
    http_error "$(get_status_code "${resp}")" >&2
    exit 1
  fi

  DELTA_ID="$(get_response_body "${resp}" | jq \
        -r \
        'first(. | sort_by(.metadata.created_at) | .[] | select(.metadata.name == "score-humanitec-queue-delta")).id' \
      )"

  # Create a new delta if necessary. Don't use this value incase we create a delta at the same time as someone else. (Race condition)
  if [ -z "$DELTA_ID" ]
  then
    [ "${DEBUG:-0}" -ge 1 ] && echo "No existing, unarchived deltas with name score-humanitec-queue-delta. Creating one."
    resp="$(make_request POST "/orgs/${ORG_ID}/apps/${APP_ID}/deltas" '{
      "metadata": {
        "name": "score-humanitec-queue-delta",
        "env_id": "'"${ENV_ID}"'"
      },
      "modules":{}
    }')"
    if [ "$(get_status_code "${resp}")" -ge 400 ]
    then
      echo -n "Unable to create delta in app /orgs/${ORG_ID}/apps/${APP_ID}: " >&2
      http_error "$(get_status_code "${resp}")" >&2
      exit 1
    fi
  fi
done

[ "${DEBUG:-0}" -ge 1 ] && echo "Delta ID: $DELTA_ID"


[ "${DEBUG:-0}" -ge 1 ] && echo "Running score-humanitec: score-humanitec ${orig_args[*]} --delta ${DELTA_ID}"
# Perfrorm score-humanitec command:
if ! score-humanitec "${orig_args[@]}" --delta "${DELTA_ID}"
then
  echo "score-humanitec failed." >&2
  exit 1
fi

#
# Phase 2: Attempt to deploy the delta by waiting for the current deployment to end or another script deploys this delta.
#

# Either:
# - discover that the delta has been deployed by another process
# - deploy immediately because the environment is free
# - wait for the environment is free
# 
# - We timeout and fail.
#
# By the end of the loop, we know that the the delta has been deployed and we
# know the deployment ID.

DEPLOY_ID=""

while [ -z "$DEPLOY_ID" ]
do
  [ "${DEBUG:-0}" -ge 1 ] && echo "Fetching active deployment in environment."
  resp="$(make_request GET "/orgs/${ORG_ID}/apps/${APP_ID}/envs/${ENV_ID}")"
  if [ "$(get_status_code "${resp}")" -ge 400 ]
  then
    echo -n "Unable to fetch environment /orgs/${ORG_ID}/apps/${APP_ID}/envs/${ENV_ID}: " >&2
    http_error "$(get_status_code "${resp}")" >&2
    exit 1
  fi
  current_deploy="$(get_response_body "${resp}")"

  current_deploy_timestamp="$(echo "${current_deploy}" | jq -r .last_deploy.created_at)"

  current_deploy_status="$(echo "${current_deploy}" | jq -r .last_deploy.status)"

  [ "${DEBUG:-0}" -ge 1 ] && echo "Active deployment status is $(echo "${current_deploy}" | jq -r .last_deploy.delta_id) with status \"${current_deploy_status}\" for delta \"$(echo "${current_deploy}" | jq -r .last_deploy.delta_id)\" and started at $current_deploy_timestamp"

  if [[ "$current_deploy_timestamp" >  "$active_deploy_timestamp" ]]
  then
    # Current deployment is after the last active one we knew about.
    # This means that either current_deploy or a deployment that happend since
    # active_deploy might be the one our delta was deployed in.
    if [ "$(echo "${current_deploy}" | jq .last_deploy.delta_id)" = "$DELTA_ID" ]
    then
      DEPLOY_ID="$(echo "${current_deploy}" | jq -r .id)"
    else
      resp="$(make_request GET "/orgs/${ORG_ID}/apps/${APP_ID}/envs/${ENV_ID}/deploys")"
      if [ "$(get_status_code "${resp}")" -ge 400 ]
      then
        echo -n "Unable to fetch deploys for environment /orgs/${ORG_ID}/apps/${APP_ID}/envs/${ENV_ID}: " >&2
        http_error "$(get_status_code "${resp}")" >&2
        exit 1
      fi
      DEPLOY_ID="$(get_response_body "${resp}" | jq \
        -r \
        --arg delta_id                "${DELTA_ID}" \
        --arg active_deploy_timestamp "${active_deploy_timestamp}" \
        'first(.[] | select(.created_at > $active_deploy_timestamp and .delta_id == $delta_id)).id' \
      )"
    fi
    current_deploy_timestamp="${active_deploy_timestamp}"
  fi

  if [ -z "${DEPLOY_ID}" ] &&  [ "$current_deploy_status" != "in progress" ]
  then
    # We can deploy as the environment seems free

    # NOTE: There is a potential race condition here, where this delta is
    #       deployed and after the deployment the delta is updated. This will
    #       result in that update being lost.
    #       The risk is small but possible.
    
    [ "${DEBUG:-0}" -ge 1 ] && echo "Deploying to environment."

    resp="$(make_request POST "/orgs/${ORG_ID}/apps/${APP_ID}/envs/${ENV_ID}/deploys" '{
      "delta_id": "'"${DELTA_ID}"'",
      "comment": "Auto-deploy from Score"
    }')"
    status_code="$(get_status_code "${resp}")"
    if [ "${status_code}" -lt 300 ]
    then
      make_request PUT "/orgs/${ORG_ID}/apps/${APP_ID}/deltas/${DELTA_ID}/metadata/archived" "true" > /dev/null
      DEPLOY_ID="$(get_response_body "${resp}" | jq -r .id)"
      echo "Deployment of ${DELTA_ID} to /orgs/${ORG_ID}/apps/${APP_ID}/envs/${ENV_ID} in progress with ID ${DEPLOY_ID}."
    elif [ "${status_code}" -eq 409 ]
    then
      echo "Unable to deploy ${DELTA_ID} to /orgs/${ORG_ID}/apps/${APP_ID}/envs/${ENV_ID} because another deployment is in progress."
    elif [ "$(get_status_code "${resp}")" -ge 400 ]
    then
      echo -n "Unable to perform deployment to environment /orgs/${ORG_ID}/apps/${APP_ID}/envs/${ENV_ID}: " >&2
      http_error "$(get_status_code "${resp}")" >&2
      exit 1
    fi
  fi

  if [ -z "${DEPLOY_ID}" ]
  then
    [ "${DEBUG:-0}" -ge 1 ] && echo "Other deployment in progress. Waiting."
    sleep 10
  fi
done


#
# Phase 3: Wait for the deployment of this delta to end.
#
[ "${DEBUG:-0}" -ge 1 ] && echo "Deploy ID for this delta: ${DEPLOY_ID}"

# If for some reason the delta was not marked as archived, archive it now.
# This avoids getting stuck in a loop where the deployment is always assumed to have happened.
make_request PUT "/orgs/${ORG_ID}/apps/${APP_ID}/deltas/${DELTA_ID}/metadata/archived" "true" > /dev/null


DEPLOY_STATUS="in progress"
while [ "${DEPLOY_STATUS}" = "in progress" ]
do
  resp="$(make_request GET "/orgs/${ORG_ID}/apps/${APP_ID}/envs/${ENV_ID}/deploys/${DEPLOY_ID}")"
  if [ "$(get_status_code "${resp}")" -ge 400 ]
  then
    echo -n "Unable to fetch deploy /orgs/${ORG_ID}/apps/${APP_ID}/envs/${ENV_ID}/deploys/${DEPLOY_ID}: " >&2
    http_error "$(get_status_code "${resp}")" >&2
    exit 1
  fi
  DEPLOY_STATUS="$(get_response_body "${resp}" | jq -r .status)"

  if [ "${DEPLOY_STATUS}" = "in progress" ]
  then
    sleep 10
  fi
done

echo "Deployment complete with status: ${DEPLOY_STATUS}"

if [ "${DEPLOY_STATUS}" != "succeeded" ]
then 
  exit 1
fi
