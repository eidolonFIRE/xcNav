#!/usr/bin/env bash
# Deploy xcnav_avatar_service. Requires the aws cli and python.
#
# AUTH_TOKEN is read from profileStoreToken in lib/secrets.dart so the app and lambda stay in sync.
set -euo pipefail

cd "$(dirname "$0")"
REGION=us-west-1
FUNCTION=xcnav_avatar_service

TOKEN=$(sed -n 's/^const \(String \)\?profileStoreToken = "\(.*\)";/\2/p' ../../lib/secrets.dart)
if [ -z "$TOKEN" ] || [ "$TOKEN" = "unset" ]; then
    echo "profileStoreToken is not set in lib/secrets.dart" >&2
    exit 1
fi

rm -f function.zip
PY=$(command -v python || command -v python3)
"$PY" -m zipfile -c function.zip index.mjs

aws lambda update-function-code --region $REGION --function-name $FUNCTION --zip-file fileb://function.zip > /dev/null
aws lambda wait function-updated --region $REGION --function-name $FUNCTION

aws lambda update-function-configuration --region $REGION --function-name $FUNCTION \
    --runtime nodejs24.x --memory-size 256 --timeout 10 \
    --environment "Variables={AUTH_TOKEN=$TOKEN}" > /dev/null
aws lambda wait function-updated --region $REGION --function-name $FUNCTION

rm -f function.zip
echo "Deployed $FUNCTION"
