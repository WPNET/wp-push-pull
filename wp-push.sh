#!/bin/bash

script_version="1.5.1.0"
# Author:            gb@wpnet.nz
# Description:       Push a WordPress site to another user on the same server
# 
# SECURITY WARNING:  This script has security implications - USE WITH CAUTION!
#                    - NEVER permit an untrusted user to run this script
#                    - NEVER leave elevated permissions in place after use
#                    - Only use on local development/staging servers
#                    - wp-push requires MORE elevated privileges than wp-pull
#                    - PREFER using wp-pull over wp-push for better security
#
# Requirements:      - Requires a sudoers file at /etc/sudoers.d/ with appropriate permissions
#                    - 'wp-cli' must be installed and available to both LOCAL and REMOTE users
#                    - Does not use SSH or require authorized_keys configuration
#                    - Must be configured by administrator using setup.sh before use
#                    - Requires sudo access for rsync to set REMOTE file ownership
#
# Known limitations: - Will not work with wp-config.php located above the webroot
#                    - Untested with WordPress multisite installations
#                    - Only works for local server transfers (not remote servers)

####################################################################################
# EDIT FOLLOWING LINES ONLY!
####################################################################################

# LOCAL
local_user=""
local_path=""     # use trailing slash
local_webroot=""  # no preceding or trailing slash

# REMOTE
remote_user=""
remote_path=""    # use trailing slash
remote_webroot="" # no preceding or trailing slash

####################################################################################
# NO MORE EDITING BELOW THIS LINE!
####################################################################################

# construct full paths
local_full_path="${local_path}${local_webroot}"
remote_full_path="${remote_path}${remote_webroot}"
remote_original_siteurl="$( sudo -u $remote_user wp option get siteurl --path=$remote_full_path )"
remote_original_domain=${remote_original_siteurl#http://}
remote_original_domain=${remote_original_domain#https://}
# Detect and save the original REMOTE protocol (http or https)
if [[ "$remote_original_siteurl" == https://* ]]; then
    remote_original_protocol="https://"
elif [[ "$remote_original_siteurl" == http://* ]]; then
    remote_original_protocol="http://"
else
    remote_original_protocol="https://"  # default to https if protocol not detected
fi

# Options flags (don't change here, pass in arguments)
exclude_wpconfig=1    # highly unlikely you want to change this
do_search_replace=1   # run 'wp search-replace'
files_only=0          # don't do a database dump & import
db_only=0             # don't do a files sync
no_db_import=0        # don't run db import
be_verbose=0          # be verbose
all_tables=0          # run search-replace with --all-tables

# Add default excludes for rsync
excludes=(.wp-stats .maintenance .user.ini wp-content/cache)
if (( exclude_wpconfig == 1 )); then
    excludes+=(wp-config.php)
fi

# Detect if running in a terminal (for color support)
tty -s && is_tty=1 || is_tty=0

# BASH color codes for better output formatting
if (( is_tty == 1 )); then
    clr_reset="\e[0m"
    clr_bold="\e[1m"
    clr_red="\e[31m"
    clr_green="\e[32m"
    clr_yellow="\e[33m"
    clr_blue="\e[34m"
    clr_cyan="\e[36m"
else
    # No colors if not in a terminal (e.g., logging to file)
    clr_reset=""
    clr_bold=""
    clr_red=""
    clr_green=""
    clr_yellow=""
    clr_blue=""
    clr_cyan=""
fi

# Helper functions for consistent output formatting
lh="\n${clr_bold}"

# Standard status message (cyan)
function status() {
    echo -e "${lh} ${clr_cyan}$@${clr_reset}"
}

# Success message (green)
function success() {
    echo -e "${lh} ${clr_green}✓ $@${clr_reset}"
}

# Error message (red)
function error() {
    echo -e "${lh} ${clr_red}✗ ERROR: $@${clr_reset}"
}

# Warning message (yellow)
function warning() {
    echo -e "${lh} ${clr_yellow}⚠ WARNING: $@${clr_reset}"
}

# Info message (blue)
function info() {
    echo -e "${lh} ${clr_blue}ℹ $@${clr_reset}"
}

# Set permissions for LOCAL user to access REMOTE user's path
# This allows LOCAL user to write files to REMOTE user's directory
sudo /usr/bin/setfacl -m u:${local_user}:rwX ${remote_path}

# Generate unique filename for database dumps
# The random string helps avoid collisions and the handle helps with cleanup
rnd_str=$(echo $RANDOM | md5sum | head -c 12; echo;)
rnd_str_handle="48dsg"
db_export_prefix="wp_db_export_"
db_dump_sql="${db_export_prefix}${rnd_str}${rnd_str_handle}.sql"

####################################################################################
# Functions
####################################################################################

# Execute wp-cli commands as REMOTE user
# Suppresses stderr to avoid noisy permission/warning messages
function sudo_as_remote_user() {
    # Always suppress stderr to prevent PHP notices/warnings from cluttering output
    # Verbose mode only affects script-level messages, not wp-cli debug output
    sudo -u $remote_user "$@" 2>/dev/null
}

# Execute wp-cli commands as LOCAL user with error suppression
function wp_quiet() {
    # Always suppress stderr to prevent PHP notices/warnings from cluttering output
    # Verbose mode only affects script-level messages, not wp-cli debug output
    wp "$@" 2>/dev/null
}

# Check if a command exists
function command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Validate that wp-cli is available
function check_wp_cli() {
    if ! command_exists wp; then
        error "wp-cli is not installed or not in PATH"
        error "Please install wp-cli: https://wp-cli.org/"
        exit 1
    fi
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

# Fetch WordPress site information from LOCAL and REMOTE installations
# This gathers database names, URLs, and other critical configuration
# Note: wp-cli commands can be slow; consider caching if performance is critical
function fetch_site_info() {
    
    info "Fetching site information..."
    
    # Fetch LOCAL site details
    local_siteurl="$( wp_quiet option get siteurl --path=$local_full_path )"
    if [ -z "$local_siteurl" ]; then
        error "Failed to get LOCAL site URL. Is WordPress installed at $local_full_path?"
        exit 1
    fi
    
    local_blogname="$( wp_quiet option get blogname --path=$local_full_path )"
    local_db_name="$( wp_quiet config get DB_NAME --path=$local_full_path )"
    local_db_prefix="$( wp_quiet db prefix --path=$local_full_path )"
    
    # Detect LOCAL protocol
    if [[ "$local_siteurl" == https://* ]]; then
        local_protocol="https://"
    elif [[ "$local_siteurl" == http://* ]]; then
        local_protocol="http://"
    else
        local_protocol="https://"  # default to https
    fi
    
    # Extract domain from URL (remove http:// or https://)
    local_site_domain="${local_siteurl#http://}"
    local_site_domain="${local_site_domain#https://}"

    # Fetch REMOTE site details
    remote_siteurl="$( sudo_as_remote_user wp option get siteurl --path=$remote_full_path )"
    if [ -z "$remote_siteurl" ]; then
        error "Failed to get REMOTE site URL. Is WordPress installed at $remote_full_path?"
        exit 1
    fi
    
    remote_blogname="$( sudo_as_remote_user wp option get blogname --path=$remote_full_path )"
    remote_db_name="$( sudo_as_remote_user wp config get DB_NAME --path=$remote_full_path )"
    remote_db_prefix="$( sudo_as_remote_user wp db prefix --path=$remote_full_path )"
    
    # Detect REMOTE protocol
    if [[ "$remote_siteurl" == https://* ]]; then
        remote_protocol="https://"
    elif [[ "$remote_siteurl" == http://* ]]; then
        remote_protocol="http://"
    else
        remote_protocol="https://"  # default to https
    fi
    
    # Extract domain from URL
    remote_site_domain="${remote_siteurl#http://}"
    remote_site_domain="${remote_site_domain#https://}"

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
        --exclude, -e PATH              Exclude additional paths from rsync (space-delimited, quoted)
        --all-tables, -a                Run search-replace with --all-tables flag
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

# Clean up old database dump files
# This helps maintain disk space by removing temporary export files
tidy_up_db_dumps() {
    
    status "Searching for database dump files to clean up..."
    
    # Search LOCAL directory
    info "Scanning LOCAL directory: ${local_path}"
    local local_files=$(find "${local_path}" -maxdepth 1 -name "${db_export_prefix}*${rnd_str_handle}.sql" -print 2>/dev/null)
    if [ -n "$local_files" ]; then
        echo "$local_files"
    else
        echo "  No files found"
    fi
    
    # Search REMOTE directory
    info "Scanning REMOTE directory: ${remote_path}"
    local remote_files=$(find "${remote_path}" -maxdepth 1 -name "${db_export_prefix}*${rnd_str_handle}.sql" -print 2>/dev/null)
    if [ -n "$remote_files" ]; then
        echo "$remote_files"
    else
        echo "  No files found"
    fi

    # Confirm deletion if files found
    if [ -n "$local_files" ] || [ -n "$remote_files" ]; then
        if $(get_confirmation "DELETE ALL found database dump files?"); then
            status "Deleting database dump files..."
            
            # Delete LOCAL files
            local local_count=$(find "${local_path}" -maxdepth 1 -name "${db_export_prefix}*${rnd_str_handle}.sql" -delete -print 2>/dev/null | wc -l)
            
            # Delete REMOTE files
            local remote_count=$(find "${remote_path}" -maxdepth 1 -name "${db_export_prefix}*${rnd_str_handle}.sql" -delete -print 2>/dev/null | wc -l)
            
            success "Cleanup complete! Deleted $local_count LOCAL and $remote_count REMOTE files."
        else
            warning "Cleanup cancelled by user"
        fi
    else
        info "No database dump files found to clean up"
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
    --exclude|-e)
      if [ -n "$2" ]; then
        # Parse space-delimited list and add to excludes array
        IFS=' ' read -ra ADDR <<< "$2"
        for i in "${ADDR[@]}"; do
          excludes+=("$i")
        done
        shift 2
      else
        echo "Error: --exclude requires a quoted argument" >&2
        exit 1
      fi
      ;;
    --all-tables|-a)
      all_tables=1
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
# Pre-flight checks and setup
####################################################################################

# Check wp-cli is available
check_wp_cli

# Verify LOCAL path exists
if [ ! -d "$local_full_path" ]; then
    error "LOCAL path does not exist: $local_full_path"
    exit 1
fi

# Verify REMOTE path exists
if [ ! -d "$remote_full_path" ]; then
    error "REMOTE path does not exist: $remote_full_path"
    exit 1
fi

# Fetch site information from both LOCAL and REMOTE
fetch_site_info

# Display operation banner
echo -e "${clr_bold}${clr_cyan}═══════════════════════════════════════════════════════════════${clr_reset}"
status "WordPress Site PUSH Operation"
echo -e "${clr_bold}${clr_cyan}═══════════════════════════════════════════════════════════════${clr_reset}"
warning "PUSH requires elevated privileges - USE WITH CAUTION!"
info "FROM: ${local_user}@${local_full_path}"
info "TO:   ${remote_user}@${remote_full_path}"
(( be_verbose == 1 )) && echo "Script: $0 v${script_version}"

# Print detailed summary in verbose mode
(( be_verbose == 1 )) && print_summary

# Final confirmation before proceeding
if ( ! get_confirmation "Proceed with PUSH?" ); then
    warning "Operation cancelled by user"
    exit 0
fi

####################################################################################
# Validate database table prefixes and handle mismatches
####################################################################################

if [[ $local_db_prefix != "$remote_db_prefix" ]] && (( files_only == 0 )); then
    warning "Database table prefix mismatch detected!"
    warning "LOCAL prefix:  ${local_db_prefix}"
    warning "REMOTE prefix: ${remote_db_prefix}"
    echo ""
    warning "To proceed, the REMOTE database must be RESET and wp-config.php updated."
    
    if ( get_confirmation "Reset REMOTE site's database?" ) ; then
        if ( get_confirmation "DANGER: This will DELETE ALL tables in database '${remote_db_name}'!" ) ; then
            status "Resetting REMOTE database..."
            if sudo_as_remote_user wp db reset --yes --path=$remote_full_path; then
                success "Database reset complete"
            else
                error "Failed to reset database"
                exit 1
            fi
            
            status "Updating table_prefix in wp-config.php..."
            if sudo_as_remote_user wp config set table_prefix "${local_db_prefix}" --path=$remote_full_path; then
                success "Table prefix updated to: ${local_db_prefix}"
            else
                error "Failed to update table prefix"
                exit 1
            fi
        else
            warning "Operation cancelled - database prefix mismatch not resolved"
            exit 0
        fi
    else    
        warning "Operation cancelled by user"
        exit 0
    fi
fi

####################################################################################
# Synchronize files from LOCAL to REMOTE using rsync
####################################################################################

if (( db_only == 0 )); then
    status "Synchronizing files from LOCAL to REMOTE..."
    warning "Files at REMOTE not present in LOCAL will be DELETED!"
    info "Excluded files/directories: ${excludes[@]}"
    
    # Set quiet mode based on verbosity
    (( be_verbose == 1 )) && quiet="" || quiet="--quiet"
    
    # Perform rsync with sudo (required to set REMOTE file ownership)
    # Trailing slash on source is critical for proper sync
    if sudo rsync ${quiet} -azhP --delete --chown=${remote_user}:${remote_user} \
        $(printf -- "--exclude=%q " "${excludes[@]}") \
        ${local_full_path}/ ${remote_full_path}; then
        success "File synchronization complete"
    else
        error "File synchronization failed (rsync error code: $?)"
        exit 1
    fi
fi

####################################################################################
# Export LOCAL database and copy to REMOTE
####################################################################################

if (( files_only == 0 )); then
    status "Exporting LOCAL database: ${local_db_name}"
    
    # Export database using wp-cli
    if wp_quiet db export ${local_path}${db_dump_sql} --path=$local_full_path; then
        success "Database export complete"
    else
        error "Failed to export LOCAL database"
        exit 1
    fi
    
    # Copy database dump file to REMOTE using rsync with sudo
    (( be_verbose == 1 )) && info "Copying database file to REMOTE..."
    if sudo rsync --quiet -azhP --chown=${remote_user}:${remote_user} \
        ${local_path}${db_dump_sql} ${remote_path}; then
        success "Database file copied to REMOTE"
        
        # Clean up LOCAL database dump file
        (( be_verbose == 1 )) && info "Cleaning up LOCAL database file..."
        rm ${verbose} ${local_path}${db_dump_sql}
    else
        error "Failed to copy database file to REMOTE"
        # Try to clean up LOCAL file even on failure
        rm -f ${local_path}${db_dump_sql}
        exit 1
    fi
fi

####################################################################################
# Import database to REMOTE WordPress installation
####################################################################################

if (( files_only == 0 && no_db_import == 0 )); then
    if ( get_confirmation "Proceed with database import?"); then
        status "Importing database to REMOTE..."
        
        # Import the database dump
        if sudo_as_remote_user wp db import ${remote_path}${db_dump_sql} --path=$remote_full_path; then
            success "Database import complete!"
        else
            error "Database import failed"
            exit 1
        fi
        
        # Flush WordPress cache
        sudo_as_remote_user wp cache flush --hard --path=$remote_full_path 2>/dev/null
        
        if (( be_verbose == 1 )); then
            info "Temporary REMOTE siteurl: $(sudo_as_remote_user wp option get siteurl --path=$remote_full_path)"
        fi
        
        # Clean up database dump file
        (( be_verbose == 1 )) && info "Cleaning up database file..."
        find "${remote_path}" -name "${db_dump_sql}" -delete 2>/dev/null
    else
        warning "Database import skipped - search-replace will not run"
        do_search_replace=0
    fi

    ####################################################################################
    # Update database URLs and paths (search-replace)
    ####################################################################################

    if (( do_search_replace == 1 )); then
        if ( get_confirmation "Proceed with database URL/path updates? (may take a while...)" ); then
            
            # Set output format based on verbosity
            if (( be_verbose == 1 )); then
                newline=""; format="table"
            else
                newline="-n"; format="count"
            fi
            
            # Set --all-tables flag if requested
            if (( all_tables == 1 )); then
                all_tables_flag="--all-tables"
            else
                all_tables_flag=""
            fi
            
            # Replace URLs (domain names)
            # Check if protocols differ between LOCAL and REMOTE
            if [[ "$local_protocol" != "$remote_original_protocol" ]]; then
                # Protocols differ - must include protocol in search-replace
                status "Updating URLs in database (with protocol conversion)..."
                echo -e ${newline} "${lh} ${clr_blue}Replacing URLs: ${local_protocol}${local_site_domain} → ${remote_original_protocol}${remote_site_domain}${clr_reset}"
                if sudo_as_remote_user wp search-replace --precise "${local_protocol}${local_site_domain}" "${remote_original_protocol}${remote_site_domain}" \
                    --path=$remote_full_path --report-changed-only --format=${format} ${all_tables_flag}; then
                    success "URL replacement complete (protocol converted)"
                else
                    warning "URL replacement may have encountered issues"
                fi
            else
                # Protocols are the same - use protocol-relative search-replace
                status "Updating URLs in database..."
                echo -e ${newline} "${lh} ${clr_blue}Replacing URLs: //${local_site_domain} → //${remote_site_domain}${clr_reset}"
                if sudo_as_remote_user wp search-replace --precise "//${local_site_domain}" "//${remote_site_domain}" \
                    --path=$remote_full_path --report-changed-only --format=${format} ${all_tables_flag}; then
                    success "URL replacement complete"
                else
                    warning "URL replacement may have encountered issues"
                fi
            fi
            
            # Replace file paths
            status "Updating file paths in database..."
            echo -e ${newline} "${lh} ${clr_blue}Replacing paths: ${local_full_path} → ${remote_full_path}${clr_reset}"
            if sudo_as_remote_user wp search-replace --precise "${local_full_path}" "${remote_full_path}" \
                --path=$remote_full_path --report-changed-only --format=${format} ${all_tables_flag}; then
                success "Path replacement complete"
            else
                warning "Path replacement may have encountered issues"
            fi
            
            # Verify final URLs are correct
            if [[ "$local_protocol" != "$remote_original_protocol" ]]; then
                # Double-check siteurl and home have correct protocol after conversion
                final_url="${remote_original_protocol}${remote_site_domain}"
                sudo_as_remote_user wp option update siteurl "$final_url" --path=$remote_full_path 2>/dev/null
                sudo_as_remote_user wp option update home "$final_url" --path=$remote_full_path 2>/dev/null
                info "Protocol set to: ${remote_original_protocol}"
            fi
            
            # Flush cache after search-replace
            sudo_as_remote_user wp cache flush --hard --path=$remote_full_path 2>/dev/null
            
            # Display final site configuration
            echo ""
            success "Site configuration updated:"
            echo -e "  ${clr_cyan}Blogname:${clr_reset} $(sudo_as_remote_user wp option get blogname --path=$remote_full_path)"
            echo -e "  ${clr_cyan}Site URL:${clr_reset} $(sudo_as_remote_user wp option get siteurl --path=$remote_full_path)"
        else
            warning "Database URL/path updates skipped"
        fi
    fi

fi

####################################################################################
# Cleanup and completion
####################################################################################

# Remove temporary elevated permissions
(( be_verbose == 1 )) && info "Removing temporary file access permissions..."
sudo /usr/bin/setfacl -x u:${local_user} ${remote_path} 2>/dev/null

# Display completion message
echo ""
echo -e "${clr_bold}${clr_green}═══════════════════════════════════════════════════════════════${clr_reset}"
success "PUSH operation completed successfully!"
echo -e "${clr_bold}${clr_green}═══════════════════════════════════════════════════════════════${clr_reset}"
exit 0
