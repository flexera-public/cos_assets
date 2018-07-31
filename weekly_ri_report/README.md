Export full instance and RI details

### usage

1. checkout this repository
2. install [jq](https://stedolan.github.io/jq/)
3. execute instances.sh [options]

### options

```bash
-e email                your rightscale email
-p password             your rightscale password
-H us-4                 rightscale host, us-4, us-3, telstra-10
-a "12345 67890 ..."    list of rightscale account ids, space delimited
-z TIMEZONE             filter timezone. defaults to America/Los_Angeles
-S 2018-7-15T00:00:00   filter start time
-E 2018-7-30T00:00:00   filter end time
```

### example

The below example will export the full instance detail and reserved_instances detail from optima
and place in two CSV files in the current directory.

```bash
./instances.sh -e you@rightscale.com -p password -S 2018-7-15T00:00:00 -E 2018-7-30T00:00:00 -H us-4 -a "12345 67890"  -z America/Los_Angeles
```

To filter across many accounts it may be best to place all the account ids in a file and read the file into the instances command.  see the example below.  Note the back ticks ```

```bash
./instances.sh -e you@rightscale.com -p password -S 2018-7-15T00:00:00 -E 2018-7-30T00:00:00 -H us-4 -a `cat account_ids.txt` -z America/Los_Angeles
```
