#!/usr/bin/env bash
prefix="branch-$TRAVIS_BRANCH"
if [[ -n "$TRAVIS_TAG" ]]; then
  prefix="tag-$TRAVIS_TAG"
fi
mkdir -p builds/ec2
tar -zcvf builds/ec2/$prefix.tar.gz EC2/
