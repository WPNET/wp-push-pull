#!/bin/bash

script_version="1.3.0.2"
# Author:        gb@wpnet.nz
# Description:   Push / sync a site to another site, on the same server
# Requirements: - This script has some security risks, USE WITH CAUTION!
#               - NEVER permit an untrusted user to run this script, or to have CLI access while
#                 the elevated permissions are in effect.
#               - Requires a sudoers file at /etc/sudoers.d/ with permissions set accordingly
#               - 'wp' must be available to the SOURCE and DESTINATION users
#               - Does not use SSH, adding to authorized_keys is not required
#               - This script will NOT WORK unless appropriate permissions are enabled by an administrator beforehand
# Known issues: - Won't work with sites that have the wp-config.php file above the webroot!

####################################################################################
# EDIT FOLLOWING LINES ONLY!
####################################################################################

# SOURCE
source_user=""
source_path=""           # use trailing slash
source_webroot=""        # no preceding or trailing slash

# DESTINATION
destination_user=""
destination_path=""      # use trailing slash
destination_webroot=""   # no preceding or trailing slash

####################################################################################
# NO MORE EDITING BELOW THIS LINE!
####################################################################################

# construct full paths
source_full_path="${source_path}${source_webroot}"
destination_full_path="${destination_path}${destination_webroot}"
destination_original_domain=$(basename "$destination_path")

# Options flags (don't change here, pass in arguments)
exclude_wpconfig=1    # highly unlikely you want to change this
do_search_replace=1   # run 'wp search-replace' on destination
files_only=0          # don't do a database dump & import
db_only=0             # don't do a files sync
no_db_import=0        # don't run db import on destination
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

# Set permissions for SOURCE user to access DESTINATION path (needed for find & wp)
sudo /usr/bin/setfacl -m u:${source_user}:rwX ${destination_path}

# Set DB dump filename, with random string and handle
hash=$(echo $RANDOM | md5sum | head -c 12; echo;)
hash_handle="48dsg"
db_export_prefix="wp_db_export_"
db_dump_sql="${db_export_prefix}${hash}${hash_handle}.sql"

####################################################################################
# Functions
####################################################################################

# run commands as destination_user
function sudo_as_dest_user() {
    sudo -u $destination_user "$@"
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

# Get all SOURCE and DESTINATION site details
# (need to find a faster way to do this)
function fetch_site_info() {

    source_siteurl="$( wp option get siteurl --path=$source_full_path )"
    source_blogname="$( wp option get blogname --path=$source_full_path )"
    source_db_name="$( wp config get DB_NAME --path=$source_full_path )"
    source_db_prefix="$(wp db prefix --path=$source_full_path )"
    source_site_domain=${source_siteurl#http://}
    source_site_domain=${source_siteurl#https://}

    destination_siteurl="$( sudo_as_dest_user wp option get siteurl --path=$destination_full_path )"
    destination_blogname="$( sudo_as_dest_user wp option get blogname --path=$destination_full_path )"
    destination_db_name="$( sudo_as_dest_user wp config get DB_NAME --path=$destination_full_path )"
    destination_db_prefix="$( sudo_as_dest_user wp db prefix --path=$destination_full_path )"
    destination_site_domain=${destination_siteurl#http://}
    destination_site_domain=${destination_siteurl#https://}

}

# Print summary
function print_summary() {
cat <<EOF
SUMMARY:
    SOURCE:
        blogname @ siteurl:  ${source_blogname} @ ${source_siteurl}
        user @ path:         ${source_user} @ ${source_full_path}
        database name:       ${source_db_name}
        table_prefix:        ${source_db_prefix}
    DESTINATION:
        blogname @ siteurl:  ${destination_blogname} @ ${destination_siteurl}
        user @ path:         ${destination_user} @ ${destination_full_path}
        database name:       ${destination_db_name}
        table_prefix:        ${destination_db_prefix}
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
        --no-db-import                      Do not import the database on the destination
        --no-search-replace, --no-rewrite   Do not run 'wp search-replace' on the destination
        --tidy-up                           Delete database dump files in SOURCE and DESTINATION
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
    status "Found in SOURCE:"
    find "${source_path}" -maxdepth 1 -name "${db_export_prefix}*${hash_handle}.sql" -print
    status "Found in DESTINATION:"
    find "${destination_path}" -maxdepth 1 -name "${db_export_prefix}*${hash_handle}.sql" -print

    if $(get_confirmation "DELETE any found database dump files?"); then
        status "Deleting database dump files ..."
        # SOURCE
        find "${source_path}" -maxdepth 1 -name "${db_export_prefix}*${hash_handle}.sql" -delete
        # DESTINATION
        find "${destination_path}" -maxdepth 1 -name "${db_export_prefix}*${hash_handle}.sql" -delete
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
status "PUSH site from '${source_full_path}' to '${destination_full_path}'"
(( be_verbose == 1 )) && echo "Script: $0 v${script_version}"

# Print SUMMARY
(( be_verbose == 1 )) && print_summary

# CONFIRM before proceeding
if ( ! get_confirmation "Proceed with PUSH?" ); then
    status "ABORTED!"
    exit
fi

####################################################################################
# CHECK WP table_prefixes match, if not reset DESTINATION database
####################################################################################

if [[ $source_db_prefix != "$destination_db_prefix" ]] && (( files_only == 0 )); then
    status "ERROR: SOURCE and DESTINATION database prefixes do not match!"
    status "To proceed, the DESTINATION database will be RESET and the \$table_prefix in wp-config.php will be updated."
    if ( get_confirmation "Reset DESTINATION site's database?" ) ; then
        if ( get_confirmation "WARNING! This will DELETE ALL tables in database: '${destination_db_name}'! Not just those with table prefix '${destination_db_prefix}'!" ) ; then
            status "Resetting DESTINATION database ..."
            sudo_as_dest_user wp db reset --yes --path=$destination_full_path
            # ALTERNATIVE: DROP only tables with the current table_prefix
            # sudo_as_dest_user wp db clean --yes --path=$destination_full_path 
            status "Updating the \$table_prefix in the DESTINATION wp-config.php file ..."
            sudo_as_dest_user wp config set table_prefix "${source_db_prefix}" --path=$destination_full_path
        else
            status "ABORTED!" && exit
        fi
    else    
        status "ABORTED!" && exit
    fi
fi

####################################################################################
# RSYNC files to DESTINATION
####################################################################################

if (( db_only == 0 )); then
    status "RSYNC files to DESTINATION: ${destination_full_path} ..."
    echo "++++ NOTE: Any files at DESTINATION not present in SOURCE will be DELETED!"
    echo "++++ EXCLUSIONS: ${excludes[@]}"
    (( be_verbose == 1 )) && quiet="" || quiet="--quiet"
    sudo rsync ${quiet} -azhP --delete --chown=${destination_user}:${destination_user} $(printf -- "--exclude=%q " "${excludes[@]}") ${source_full_path}/ ${destination_full_path} # slash after source_full_path is IMPORTANT!
fi

####################################################################################
# DUMP the SOURCE database
####################################################################################

if (( files_only == 0 )); then
    status "EXPORT database ... (${source_db_name})"
    wp db export ${source_path}${db_dump_sql} --path=$source_full_path
    # RSYNC database dump to DESTINATION
    (( be_verbose == 1 )) && status "COPY database to DESTINATION ..."
    if sudo rsync --quiet -azhP --chown=${destination_user}:${destination_user} ${source_path}${db_dump_sql} ${destination_path}; then
        status "SUCCESS Database copied to DESTINATION!"
        (( be_verbose == 1 )) && status "Delete database dump source file ..."
        rm ${verbose} ${source_path}${db_dump_sql}
    else
        status "ERROR: Database copy to DESTINATION failed!"
        exit
    fi
fi

####################################################################################
# IMPORT the database for the destination
####################################################################################

if (( files_only == 0 && no_db_import == 0 )); then
    if ( get_confirmation "Proceed with IMPORT?"); then
        status "IMPORT database to DESTINATION ..."
        sudo_as_dest_user wp db import ${destination_path}${db_dump_sql} --path=$destination_full_path
        status "DB IMPORT COMPLETE!"
        sudo_as_dest_user wp cache flush --hard --path=$destination_full_path
        if (( be_verbose == 1 )); then
            echo -n "New (TEMPORARY!) DESTINATION siteurl:  "
            sudo_as_dest_user wp option get siteurl --path=$destination_full_path
        fi
        (( be_verbose == 1 )) && status "DELETE imported database source file ..."
        sudo_as_dest_user find "${destination_path}" -name "${db_dump_sql}" -delete 2>/dev/null
    else
        do_search_replace=0
    fi

    ####################################################################################
    # REWRITE the DB on the DESTINATION
    ####################################################################################

    if (( do_search_replace == 1 )); then
        if ( get_confirmation "Proceed with database rewrites? (this could take a while ...)" ); then
            if (( be_verbose == 1 )); then
                newline=""; format="table"
            else
                newline="-n"; format="count"
            fi
            echo -e ${newline} "$lh EXECUTE 'wp search-replace' for URLs ... changed:${clr_reset} "
            sudo_as_dest_user wp search-replace --precise //${source_site_domain} //${destination_original_domain} --path=$destination_full_path --report-changed-only --format=${format}
            echo -e ${newline} "$lh EXECUTE 'wp search-replace' for file PATHs ... changed:${clr_reset} "
            sudo_as_dest_user wp search-replace --precise ${source_full_path} ${destination_full_path} --path=$destination_full_path --report-changed-only --format=${format}
            sudo_as_dest_user wp cache flush --hard --path=$destination_full_path
            echo -ne "${clr_yellow}NEW${clr_reset} DESTINATION blogname: "
            sudo_as_dest_user wp option get blogname --path=$destination_full_path
            echo -ne "${clr_yellow}NEW${clr_reset} DESTINATION siteurl: "
            sudo_as_dest_user wp option get siteurl --path=$destination_full_path
        fi
    fi

fi

# REMOVE the additional permissions from the SOURCE user
sudo /usr/bin/setfacl -x u:${source_user} ${destination_path}
status "PUSH completed!"
exit
