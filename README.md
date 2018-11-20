# RightScale Cost Optimization Assets
This repository contains a library of open source RightScale Cost Optimization Assets.

## Instance Utilization
- [Azure Utilization Script](./Azure/) - **CURRENTLY BROKEN DUE TO DEPRECATED API** 
- [AWS Utilization Script](./cw_cpu_avg/)
- [RightLink Utilization Data Script](./RightLink_Utilization/)
- [VM Information Report Script](./RightLink_Utilization/)

## Volumes
- [Get Unattached Volumes Script](./Unattached_Volumes/)

## Snapshots
- [Get Snapshots Older Than A Date Specified](./Old_Snapshots/)

## Utility Scripts
- [Run-COSStorageScripts.ps1](./Run-COSStorageScripts.ps1)
    - Runs the unattached volumes and old snapshots scripts sequentially
    - Expects that the Git folder structure was preserved

## Getting Help
Support for these assets will be provided though GitHub Issues and the RightScale public slack channel #cloud-cost-management.
Visit http://chat.rightscale.com/ to join!

## Opening an Issue
Github issues contain a template for three types of requests(Bugs, New Features to an existing script, New Script Request)

- Bugs: Any issue you are having with an existing script not functioning correctly, this does not include missing features, or actions.
- New Feature Request: Any feature(Field, Action, Link, Output, etc) that are to be added to an existing script. 
- New Script Request: Request for a new script to be added to the Cost Optimization Assets.
