#!/bin/bash
set -xe
source .env

rm -rf dist
npm run astro build

# Deploy
# ssh $TARGET_HOST "cd $TARGET_PATH/ && rm -rf *"
rsync -az dist/* "$TARGET_HOST:$TARGET_PATH"
