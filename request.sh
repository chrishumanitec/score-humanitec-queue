#!/bin/bash

# Limit this file to be sourced only once
[ -z "${__REQUEST__SOURCED__}" ] || return
__REQUEST__SOURCED__=1

PREFIX=${API_PREFIX:-https://api.humanitec.io}

###############################################################################
# HTTP REQUEST HANDLING
###############################################################################

# get_status_code(response)
# Returns the status code from a request made with make_request
function get_status_code
{
  # Don't use jq as the body might not be valid JSON.
  # We know the last line always contains the status code.
  echo "${1}" | tail -n 1 | sed 's/^.*[^0-9]\([0-9]*\)$/\1/'
}

# get_response_body(response)
# Returns the body of the response from a request made with make_request
function get_response_body
{
  echo "${1}" | jq -s 'nth(0)'
}

function curl_error
{
  # Error code defined here: https://curl.se/libcurl/c/libcurl-errors.html

  case "${1}" in
  6) # CURLE_COULDNT_RESOLVE_HOST
    echo "Countn't resolve host"
  ;;
  7) # CURLE_COULDNT_CONNECT
    echo "Couldn't establish connection"
  ;;
  28) # CURLE_OPERATION_TIMEDOUT
    echo "Operation timed out"
  ;;
  35) # CURLE_SSL_CONNECT_ERROR
    echo "SSL connection error"
  ;;
  *)
    echo "libcurl request failed with code ${1}"
  ;;
  esac
}

function http_error
{
  case "${1}" in
  400) 
    echo "Bad Request"
  ;;
  401)
    echo "Unauthorized"
  ;;
  403)
    echo "Forbidden"
  ;;
  404)
    echo "Not Found"
  ;;
  409)
    echo "Conflict: ID already in use."
  ;;
  422)
    echo "Payload could not be parsed."
  ;;
  500)
    echo "Internal error in Humanitec."
  ;;
  *)
    echo "Request to API responded with ${1}"
  ;;
  esac
}

# make_request(method, url, payload)
# Makes a request to the API using the appropriate headers.
# It returns the response (which should be a json object) directly followed by the status code.
# This allows it to be parsed with jq. e.g. to get the body:
# make_request GET /orgs/my-org/apps | jq -s nth(0)
function make_request ()
{
  [ "${DEBUG:-0}" -ge 2 ] && echo "${@}" >&2
  curl_write="%{http_code}"
  while [[ "${1}" =~ ^--[A-Za-z0-9_-]+ ]]
  do
    case "${1}" in
      --no-status-code)
        curl_write=""
        ;;
      *)
        echo "make_request: Unknown switch ${1}" >&2
        ;;
    esac
    shift
  done
  method="$(echo "$1" | tr '[:lower:]' '[:upper:]')"
  url="${2}"
  case "${method}" in
      POST|PUT|PATCH)
      payload="$3"
      if [[ $# -lt 3 ]]
      then
          echo "Missing payload for ${method} request." >&2
          return 1
      fi
      curl -s -w "${curl_write}" -X "${method}" -H "Content-Type:application/json" -H "Authorization: Bearer ${HUMANITEC_TOKEN}" -d "${payload}" "${PREFIX}${url}"
      err="$?"
      if (( err ))
      then
        echo "$(curl_error "${err}") making HTTP request: ${method} ${PREFIX}${url}" >&2
        return 1
      fi
      ;;
      DELETE|OPTIONS|GET)
      curl -s -w "${curl_write}" -H "Authorization: Bearer ${HUMANITEC_TOKEN}" -X "${method}" "${PREFIX}${url}"
      err="$?"
      if (( err ))
      then
        echo "$(curl_error "${err}") making HTTP request: ${method} ${PREFIX}${url}" >&2
        return 1
      fi
      ;;
      *)
          echo "Unknown method ${method}" >&2
          return 1
  esac
  echo
}