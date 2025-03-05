#!/bin/bash

script_version="1.4.0.1"
# Author:            gb@wpnet.nz
# Description:       Push / sync a site to another site, on the same server
# Requirements:      - This script has some security risks, USE WITH CAUTION!
#                    - NEVER permit an untrusted user to run this script, or to have CLI access while
#                      the elevated permissions are in effect.
#                    - Requires a sudoers file at /etc/sudoers.d/ with permissions set accordingly
#                    - 'wp' must be available to the LOCAL and REMOTE users
#                    - Does not use SSH, adding to authorized_keys is not required
#                    - This script will NOT WORK unless appropriate permissions are enabled by an administrator beforehand
# Known limitations: - Unlikely to work with sites that have the wp-config.php file above the webroot!
#                    - Untested with multisite

####################################################################################
# EDIT FOLLOWING LINES ONLY!
####################################################################################

# LOCAL
local_user=""
local_path=""           # use trailing slash
local_webroot=""        # no preceding or trailing slash

# REMOTE
remote_user=""
remote_path=""      # use trailing slash
remote_webroot=""   # no preceding or trailing slash

####################################################################################
# NO MORE EDITING BELOW THIS LINE!
####################################################################################

# construct full paths
local_full_path="${local_path}${local_webroot}"
remote_full_path="${remote_path}${remote_webroot}"
remote_original_domain=$(basename "$remote_path")

# Options flags (don't change here, pass in arguments)
exclude_wpconfig=1    # highly unlikely you want to change this
do_search_replace=1   # run 'wp search-replace'
files_only=0          # don't do a database dump & import
db_only=0             # don't do a files sync
no_db_import=0        # don't run db import
be_verbose=0          # be verbose

# Add default excludes for rsync
excludes=(.wp-stats .maintenance .user.ini)
if (( exclude_wpconfig == 1 )); then
    excludes+=(wp-config.php)
fi

# Running in a terminal?
tty -s && is_tty=1 || is_tty=0

# BASH colors
if (( is_tty == 1 )); then
    clr_reset="\e[0m"
    clr_bold="\e[1m"
    clr_yellow="\e[33m"
else
    clr_reset=""
    clr_bold=""
    clr_yellow=""
fi

# Set up a line header
lh="\n${clr_bold}++++"
function status() {
    echo -e "${lh} $@${clr_reset}"
}

# Set permissions for LOCAL user to access REMOTE user's path (needed for find & wp)
sudo /usr/bin/setfacl -m u:${local_user}:rwX ${remote_path}

# Set DB dump filename, with random string and handle
rnd_str=$(echo $RANDOM | md5sum | head -c 12; echo;)
rnd_str_handle="48dsg"
db_export_prefix="wp_db_export_"
db_dump_sql="${db_export_prefix}${rnd_str}${rnd_str_handle}.sql"

####################################################################################
# Functions
####################################################################################

# run commands as REMOTE user
function sudo_as_remote_user() {
    sudo -u $remote_user "$@"
}

# confirmation helper
function get_confirmation() {
    while true; do
        read -p "$(echo -e "\\n${clr_bold}${clr_yellow}CONFIRM:${clr_reset} ${1} Are you sure? [${clr_bold}Yes${clr_reset}/${clr_bold}n${clr_reset}o/${clr_bold}c${clr_reset}ancel]") " user_input
        case $user_input in
            [Yy]* ) break;;
            "" ) break;;
            [Nnc]* ) return 1;;
            * ) echo "Please respond yes [Y/y/{enter}] or no [n/c].";;
        esac
    done
    return 0
}

# Get all LOCAL and REMOTE site details
# (need to find a faster way to do this)
function fetch_site_info() {

    local_siteurl="$( wp option get siteurl --path=$local_full_path )"
    local_blogname="$( wp option get blogname --path=$local_full_path )"
    local_db_name="$( wp config get DB_NAME --path=$local_full_path )"
    local_db_prefix="$( wp db prefix --path=$local_full_path )"
    local_site_domain=${local_siteurl#http://}
    local_site_domain=${local_siteurl#https://}

    remote_siteurl="$( sudo_as_remote_user wp option get siteurl --path=$remote_full_path )"
    remote_blogname="$( sudo_as_remote_user wp option get blogname --path=$remote_full_path )"
    remote_db_name="$( sudo_as_remote_user wp config get DB_NAME --path=$remote_full_path )"
    remote_db_prefix="$( sudo_as_remote_user wp db prefix --path=$remote_full_path )"
    remote_site_domain=${remote_siteurl#http://}
    remote_site_domain=${remote_siteurl#https://}

}

# Print summary
function print_summary() {
cat <<EOF
SUMMARY:
    LOCAL:
        blogname @ siteurl:  ${local_blogname} @ ${local_siteurl}
        user @ path:         ${local_user} @ ${local_full_path}
        database name:       ${local_db_name}
        table_prefix:        ${local_db_prefix}
    REMOTE:
        blogname @ siteurl:  ${remote_blogname} @ ${remote_siteurl}
        user @ path:         ${remote_user} @ ${remote_full_path}
        database name:       ${remote_db_name}
        table_prefix:        ${remote_db_prefix}
EOF
    echo "    OPTIONS:"
    (( files_only == 1)) && echo "      Files only: ${files_only}"
    (( db_only == 1)) && echo "        DB only: ${db_only}"
    (( no_db_import == 1)) && echo "        No DB import: ${no_db_import}"
    (( do_search_replace == 0)) && echo "        Rewrite database: ${do_search_replace}"
    (( be_verbose == 1)) && echo "        Verbose: ${be_verbose}"
}

# Show help
function show_help() {
cat <<EOF
    Usage: wp-push [OPTIONS] (v${script_version})
        Options:
        --db-only                           Do not push files, only the database
        --files-only                        Do not push the database, only the files
        --no-db-import                      Do not run 'wp db import'
        --no-search-replace, --no-rewrite   Do not run 'wp search-replace'
        --tidy-up                           Delete database dump files in LOCAL and REMOTE
        -h, --help                          Show this help message
        -v, --verbose                       Be verbose
        Notes:
        - This script will NOT WORK unless enabled by an administrator beforehand. Contact support for assistance.
EOF
exit 0
}

# Set verbose flag
function set_verbose() {
    be_verbose=1
    verbose="-v"
}

# Tidy up database dump files
tidy_up_db_dumps() {

    status "TIDY UP: Search and delete database dump files ..."
    status "Found in LOCAL:"
    find "${local_path}" -maxdepth 1 -name "${db_export_prefix}*${rnd_str_handle}.sql" -print
    status "Found in REMOTE:"
    find "${remote_path}" -maxdepth 1 -name "${db_export_prefix}*${rnd_str_handle}.sql" -print

    if $(get_confirmation "DELETE ALL found database dump files?"); then
        status "Deleting database dump files ..."
        # LOCAL
        find "${local_path}" -maxdepth 1 -name "${db_export_prefix}*${rnd_str_handle}.sql" -delete
        # REMOTE
        find "${remote_path}" -maxdepth 1 -name "${db_export_prefix}*${rnd_str_handle}.sql" -delete
        status "Done!"
    else
        status "ABORTED!"
    fi
    exit 0
}

####################################################################################
# Input argument handling
####################################################################################

while [[ $# -gt 0 ]]; do 
  case "$1" in
    --help|-h)
      show_help;;
    --verbose|-v)
      set_verbose
      shift;;
    --tidy-up)
      tidy_up_db_dumps;;
    --db-only)
      db_only=1
      shift;;
    --files-only)
      files_only=1
      shift;;
    --no-db-import)
      no_db_import=1
      shift;;
    --no-search-replace|--no-rewrite)
      do_search_replace=0
      shift;;
    *)
      echo "Invalid option: $1" >&2
      exit 1
      ;;
  esac
done

if (( db_only == 1 && files_only == 1 )); then
    status "ERROR: Cannot use --db-only and --files-only options together!"
    exit
fi

if (( files_only == 1 && ( no_db_import == 1 || do_search_replace == 0 ) )); then
    status "ERROR: Cannot use --files-only with DB related options!"
    exit
fi

####################################################################################
# Set up
####################################################################################

# FETCH site(s) info
fetch_site_info

# START output
status "PUSH site FROM '${local_full_path}' TO '${remote_full_path}'"
(( be_verbose == 1 )) && echo "Script: $0 v${script_version}"

# Print SUMMARY
(( be_verbose == 1 )) && print_summary

# CONFIRM before proceeding
if ( ! get_confirmation "Proceed with PUSH?" ); then
    status "ABORTED!"
    exit
fi

####################################################################################
# CHECK WP table_prefixes match, if not reset REMOTE database
####################################################################################

if [[ $local_db_prefix != "$remote_db_prefix" ]] && (( files_only == 0 )); then
    status "ERROR: LOCAL and REMOTE database prefixes do not match!"
    status "To proceed, the REMOTE database will be RESET and the \$table_prefix in wp-config.php will be changed to match LOCAL."
    if ( get_confirmation "Reset REMOTE site's database?" ) ; then
        if ( get_confirmation "WARNING! This will DELETE ALL tables in database: '${remote_db_name}'! Not just those with table prefix '${remote_db_prefix}'!" ) ; then
            status "Resetting REMOTE database ..."
            sudo_as_remote_user wp db reset --yes --path=$remote_full_path
            # ALTERNATIVE: DROP only tables with the current table_prefix
            # sudo_as_remote_user wp db clean --yes --path=$remote_full_path 
            status "Updating the \$table_prefix in the REMOTE wp-config.php file ..."
            sudo_as_remote_user wp config set table_prefix "${local_db_prefix}" --path=$remote_full_path
        else
            status "ABORTED!" && exit
        fi
    else    
        status "ABORTED!" && exit
    fi
fi

####################################################################################
# RSYNC files to REMOTE
####################################################################################

if (( db_only == 0 )); then
    status "RSYNC files to REMOTE: ${remote_full_path} ..."
    echo "++++ NOTE: Any files at REMOTE not present in LOCAL will be DELETED!"
    echo "++++ EXCLUSIONS: ${excludes[@]}"
    (( be_verbose == 1 )) && quiet="" || quiet="--quiet"
    sudo rsync ${quiet} -azhP --delete --chown=${remote_user}:${remote_user} $(printf -- "--exclude=%q " "${excludes[@]}") ${local_full_path}/ ${remote_full_path} # slash after local_full_path is IMPORTANT!
fi

####################################################################################
# DUMP the LOCAL database
####################################################################################

if (( files_only == 0 )); then
    status "EXPORT LOCAL database ... (${local_db_name})"
    wp db export ${local_path}${db_dump_sql} --path=$local_full_path
    # RSYNC database dump to REMOTE
    (( be_verbose == 1 )) && status "COPY database to REMOTE ..."
    if sudo rsync --quiet -azhP --chown=${remote_user}:${remote_user} ${local_path}${db_dump_sql} ${remote_path}; then
        status "SUCCESS Database copied to REMOTE!"
        (( be_verbose == 1 )) && status "Delete database file ..."
        rm ${verbose} ${local_path}${db_dump_sql}
    else
        status "ERROR: Database copy to REMOTE failed!"
        exit
    fi
fi

####################################################################################
# IMPORT the database to REMOTE
####################################################################################

if (( files_only == 0 && no_db_import == 0 )); then
    if ( get_confirmation "Proceed with IMPORT?"); then
        status "IMPORT database to REMOTE ..."
        sudo_as_remote_user wp db import ${remote_path}${db_dump_sql} --path=$remote_full_path
        status "DB IMPORT COMPLETE!"
        sudo_as_remote_user wp cache flush --hard --path=$remote_full_path
        if (( be_verbose == 1 )); then
            echo -n "New (TEMPORARY!) REMOTE siteurl:  "
            sudo_as_remote_user wp option get siteurl --path=$remote_full_path
        fi
        (( be_verbose == 1 )) && status "DELETE imported database file ..."
        sudo_as_remote_user find "${remote_path}" -name "${db_dump_sql}" -delete 2>/dev/null
    else
        do_search_replace=0
    fi

    ####################################################################################
    # REWRITE the DB on the REMOTE
    ####################################################################################

    if (( do_search_replace == 1 )); then
        if ( get_confirmation "Proceed with database rewrites? (this could take a while ...)" ); then
            if (( be_verbose == 1 )); then
                newline=""; format="table"
            else
                newline="-n"; format="count"
            fi
            echo -e ${newline} "$lh EXECUTE: 'wp search-replace' for URLs ... changed:${clr_reset} "
            sudo_as_remote_user wp search-replace --precise //${local_site_domain} //${remote_original_domain} --path=$remote_full_path --report-changed-only --format=${format}
            echo -e ${newline} "$lh EXECUTE: 'wp search-replace' for file PATHs ... changed:${clr_reset} "
            sudo_as_remote_user wp search-replace --precise ${local_full_path} ${remote_full_path} --path=$remote_full_path --report-changed-only --format=${format}
            sudo_as_remote_user wp cache flush --hard --path=$remote_full_path
            echo -ne "${clr_yellow}NEW${clr_reset} REMOTE blogname: "
            sudo_as_remote_user wp option get blogname --path=$remote_full_path
            echo -ne "${clr_yellow}NEW${clr_reset} REMOTE siteurl: "
            sudo_as_remote_user wp option get siteurl --path=$remote_full_path
        fi
    fi

fi

# REMOVE the additional permissions from the LOCAL user
sudo /usr/bin/setfacl -x u:${local_user} ${remote_path}
status "PUSH completed!"
exit
