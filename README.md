# wp-push-pull
 A push/pull script for copying sites on a local server. Does not use SSH.

 `LOCAL`  user: the user that will execute the `wp-pull` or `wp-push` script.
 
 `REMOTE` user: the user that "owns" the other site that will be pulled from, or pushed to.
 
 **NOTE:** Use `wp-pull` in preference to `wp-push`, it requires less privileges and so is a bit safer.

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
