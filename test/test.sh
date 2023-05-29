#!/bin/bash

# Run this from the root: bash ./test/test.sh
# 
# Set the following env vars:
# ORG_ID
# APP_ID
# ENV_ID
# HUMANITEC_TOKEN

./score-humanitec-queue.sh \
  delta \
  --org "${ORG_ID}" \
  --app "${APP_ID}" \
  --env "${ENV_ID}" \
  --token "$HUMANITEC_TOKEN" \
  -f test/score-one.yaml &

sleep 3
echo "***************************Starting 2 & 3************************************"

./score-humanitec-queue.sh \
  delta \
  --org "${ORG_ID}" \
  --app "${APP_ID}" \
  --env "${ENV_ID}" \
  --token "$HUMANITEC_TOKEN" \
  -f test/score-two.yaml &

./score-humanitec-queue.sh \
  delta \
  --org "${ORG_ID}" \
  --app "${APP_ID}" \
  --env "${ENV_ID}" \
  --token "$HUMANITEC_TOKEN" \
  -f test/score-three.yaml