#!/usr/bin/env bash
prefix="cw_cpu_avg-branch-$TRAVIS_BRANCH"
if [[ -n "$TRAVIS_TAG" ]]; then
  prefix="cw_cpu_avg-tag-$TRAVIS_TAG"
fi
mkdir -p builds/cw_cpu_avg
tar -zcvf builds/cw_cpu_avg/$prefix.tar.gz cw_cpu_avg/
