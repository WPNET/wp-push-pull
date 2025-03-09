# wp-push-pull

 A push / pull script for copying sites on a **_local server_**.

 This script:

 - Does **not** copy sites to / from _remote servers_
 - Does **not** use `ssh`
 - Requires `wp-cli` installed on both `LOCAL` and `REMOTE` sites

 `LOCAL`  user: the user that will execute the `wp-pull` or `wp-push` script.
 
 `REMOTE` user: the user that "owns" the other site that will be pulled from, or pushed to.
 
 **NOTE:** `wp-pull` requires less elevated privileges than `wp-push`, use that wherever possible.

## Usage
### Set up
 - `ssh` into your server as a `sudo` user
 - Clone the repo to a local directory: `git clone git@github.com:WPNET/wp-push-pull.git`
 - CD into the directory, `cd wp-push-pull`
 - Run `sudo bash setup.sh`
 - Follow the intructions to set up the sudoer's file and copy the script for the `LOCAL` user
 - During the set up you will be asked to specify whether you're setting up for `wp-push` or `wp-pull`
 - **Use `wp-pull` in preference to `wp-push`**

### Run a `wp-push` or `wp-pull`
- Login as the `LOCAL` user that was defined as during set up.
- Run `wp-pull` or `wp-push`.
- Follow the instructions to complete the site push / pull.
- Run with `-h` for help.

### Options

```
 Options:
 --db-only                           Do not push files, only the database
 --files-only                        Do not push the database, only the files
 --no-db-import                      Do not run 'wp db import'
 --no-search-replace, --no-rewrite   Do not run 'wp search-replace'
 --tidy-up                           Delete database dump files in LOCAL and REMOTE
 -h, --help                          Show this help message
 -v, --verbose                       Be verbose
```

## Notes
- Untested with WPMU (multisite).
- Tested on Ubuntu 24.04.
- Won't work with sites that have the `wp-config.php` file above the webroot. (TODO)
