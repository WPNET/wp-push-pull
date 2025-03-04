# wp-push-pull
 A push/pull script for copying sites on a local server. 
 Does not use SSH.

## Usage
### Set up
 - SSH into your server as a SUDO user.
 - Clone the repo to a local directory.
 - CD into the directory, `cd wp-push-pull`.
 - Run `sudo bash setup.sh`.
 - Follow the intructions to set up the required sudoer's file and copy the script for the LOCAL user.
 - During the set up you will be asked to specify whether you're setting up for `wp-push` or `wp-pull`.

### Run a wp-push or wp-pull
- Switch to the user that was defined as LOCAL during set up.
- Run `wp-pull` or `wp-push`.
- Follow the instructions to complete the site push / pull.

### CLI Options

```
 Options:
 --db-only                           Do not push files, only the database
 --files-only                        Do not push the database, only the files
 --no-db-import                      Do not import the database on the destination
 --no-search-replace, --no-rewrite   Do not run 'wp search-replace' on the destination
 --tidy-up                           Delete database dump files in SOURCE and DESTINATION
 -h, --help                          Show this help message
 -v, --verbose                       Be verbose
 Notes:
 - This script will NOT WORK unless enabled by an administrator beforehand. Contact support for assistance.
```

## Notes
- Only tested on Ubuntu 20.04 & 22.04 so far.
