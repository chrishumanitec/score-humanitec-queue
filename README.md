# Simulate Score Artefact

Individual CI pipelines should be able to push both an Image and a Score file to Humanitec. The update should either be immediatly deployed, or if there is another deployment ongoing, it should build a delta.

This should work for any number of CI runs running almost simultaniously.


## Usage

The script acts as a drop in replacement for score-humanitec with the following caveats:

- Only the `delta` command is supported.
- `--deploy` and `--delta` switches cannot be used. (The script takes care of this behaviour itself)
- _Deploymemt Automations_ must be disabled in the target environment.

### Example

```bash
./score-humanitec-queue.sh \
  delta \
  --org "${HUMANITEC_ORG}" 
  --app "${APP_ID}" 
  --env "${ENV_ID}"
  --token "${HUMANITEC_TOKEN}"
  --file ./my-score-file.yaml
```

The script returns success (`0`) if the deployment succeeds and error (`1`) for _any_ error it encounters.

## How does it work

The script has 3 phases of operation:

1. Retrieve the first delta that is not archived which has the name `score-humanitec-automation`

2. Attempt to deploy the delta by waiting for the current deployment to end or another script deploys this delta.

3. Wait for the deployment of this delta to end.

## Debugging

Setting the `DEBUG` environment variable to `1` will output log messages. setting the `DEBUG` environment variable to `2` will also output API requests to stderr.
