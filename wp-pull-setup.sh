#!/bin/bash

script_version="1.0.1"
# Author:        gb@wpnet.nz
# Description:   Configure sudoers and install a script to allow a "site user" to run a "wp-pull" command

#######################################################
#### Set up
#######################################################

# wp-pull installed filename
install_name="wp-pull"
# Default webroot
default_webroot="files"
# wp-pull script install location for "site" user
install_dir=".local/bin"
# get the current user from the session
whoami_user=$(whoami)

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

# check a directory exists
dir_exists() {
  local dir="$1"
  if [[ -d "$dir" ]]; then
    echo -e "${clr_bold}Directory '$dir' exists!${clr_reset}"
    return 0
  else
    echo -e "${clr_yellow}Directory '$dir' does not exist${clr_reset}"
    return 1
  fi
}

# confirmation helper
function get_confirmation() {
    while true; do
        read -p "$(echo -e "\\n${clr_bold}${clr_yellow}CONFIRM:${clr_reset} ${1} Are you sure? [${clr_bold}Yes${clr_reset}/${clr_bold}n${clr_reset}o]") " user_input
        case $user_input in
            [Yy]* ) break;;
            "" ) break;;
            [Nn]* ) return 1;;
            * ) echo "Please respond yes [Y/y/{enter}] or no [n/c].";;
        esac
    done
    return 0
}

# Print instructions
cat <<EOF

    This script will configure a sudoers file and local "wp-pull" script for a SpinupWP "site" user (LOCAL).
    The site user can then use "wp-pull" to pull a remote site, to the current local installation, i.e. staging <- production
    - Creates sudoers file at /etc/sudoers.d/
    - Populates the wp-pull script with LOCAL & REMOTE parameters
    - Copies the script into the user's ~/.local/bin/ directory
    - Be sure to provide correct custom webroot paths if they are not default (files)
    - If a site's webroot is not default, enter like: "public_html", without preceding or trailing slash.

EOF

#######################################################
#### REMOTE
#######################################################

echo
read -p "ENTER REMOTE username: " remote_user
remote_home_path=$(getent passwd "$remote_user" | cut -d: -f6)

if [ -n "$remote_home_path" ]; then
    if (get_confirmation "Home dir of user '$remote_user' is: '$remote_home_path'. Is this correct?"); then
        remote_path="${remote_home_path}/"
    else
        # while true; do
        #     read -p "ENTER 'remote_path' (no trailing slash): " remote_path
        #     if dir_exists "$remote_path"; then
        #         remote_path="${remote_path}/"
        #         break
        #     fi
        #     echo "Invalid path. Please try again."
        # done
        echo "Cancelled" && exit 1
    fi
else
    echo "User '$remote_user' \$HOME not found. The user may not exist, or may not have a home directory set."
    exit 1
fi

if ( get_confirmation "Use default webroot ($default_webroot) for user $remote_user?" ); then
    if dir_exists "${remote_path}${default_webroot}"; then
        remote_webroot="$default_webroot"
    else
        echo "Invalid: '${remote_path}${default_webroot}' not found!"
        exit 1
    fi
else
    while true; do
        read -p "ENTER 'remote_webroot' (no trailing slash, don't include the '${default_webroot}/' prefix): " remote_webroot
        if dir_exists "${remote_path}${default_webroot}/${remote_webroot}"; then
            remote_webroot="${default_webroot}/${remote_webroot}"
            break
        fi
        echo "Invalid path. Please try again."
    done
fi

cat <<EOF

REMOTE details:
    remote_user:              $remote_user
    remote_path/webroot:      ${remote_path}${remote_webroot}

EOF

#######################################################
#### LOCAL 
#######################################################

echo
read -p "ENTER LOCAL username: " local_user
# get_confirmation "Use LOCAL user from current session ('$whoami_user')?" && local_user="$whoami_user" || read -p "ENTER LOCAL username: " local_user

local_home_path=$(getent passwd "$local_user" | cut -d: -f6)

if [ -n "$local_home_path" ]; then
    if (get_confirmation "Home dir of user '$local_user' is: '$local_home_path'. Is this correct?"); then
        local_path="${local_home_path}/"
    else
        # while true; do
        #     read -p "Enter 'local_path' (no trailing slash): " local_path
        #     if dir_exists "$local_path"; then
        #         local_path="${local_path}/"
        #         break
        #     fi
        #     echo "Invalid path. Please try again."
        # done
        echo "Cancelled" && exit 1
    fi
else
    echo "User '$local_user' \$HOME not found. The user may not exist, or may not have a home directory set."
    exit 1
fi

if ( get_confirmation "Use default webroot ($default_webroot) for user $local_user?" ); then

    if dir_exists "${local_path}${default_webroot}"; then
        local_webroot="$default_webroot"
    else
        echo "Invalid: '${local_path}${default_webroot}' not found!"
        exit 1
    fi
else
    while true; do
        read -p "ENTER 'local_webroot' (no trailing slash, don't include the '${default_webroot}/' prefix): " local_webroot
        if dir_exists "${local_path}${default_webroot}/${local_webroot}"; then
            local_webroot="${default_webroot}/${local_webroot}"
            break
        fi
        echo "Invalid path. Please try again."
    done
fi

cat <<EOF

LOCAL details:
    local_user:         $local_user
    local_path/webroot: ${local_path}${local_webroot}

EOF

#######################################################
#### Define the SUDOERS file
#######################################################

sudoers_file="${install_name}-${local_user}-${remote_user}"
sudoers_file="/etc/sudoers.d/$sudoers_file"

# only run config if same filename doesn't exist
if [ ! -f "$sudoers_file" ]; then

    # Check if existing sudoers config is OK, before we mess with it
    echo "Checking sudo syntax with visudo ..."
    if visudo -c; then
        echo "Current sudoers syntax is correct."
    elif ( get_confirmation "CHMOD all files in /etc/sudoers.d to 0440?" ); then
        chmod 0440 /etc/sudoers.d/*
    fi
    # Define the sudo rules
    sudo_rules="${local_user} ALL=(root) NOPASSWD: /usr/bin/setfacl, /usr/bin/rsync\n${local_user} ALL=(${remote_user}) NOPASSWD: /usr/bin/find, /usr/local/bin/wp"

    echo "Creating sudoers file at $sudoers_file"
    echo -e "$sudo_rules" > "$sudoers_file"
    chmod 0440 "$sudoers_file" # important!

    # Verify the syntax using visudo -c -f
    if visudo -c -f "$sudoers_file" > /dev/null 2>&1; then
        echo "Sudoers syntax is correct."
    else
        echo "ERROR: Sudoers syntax check failed. Rolling back ..."
        rm -v "$sudoers_file"
        echo -e "\nSudoers configuration failed!"
        exit 1 # error
    fi
    echo -e "\nSudoers configuration complete."

else

    echo -e "\nSudoers file already exists."
    if ( get_confirmation "Display existing sudoers file?" ); then
        cat $sudoers_file
    fi
    if ( ! get_confirmation "Keep existing sudoers file?" ); then
        rm -v "$sudoers_file"
        echo "Checking sudo syntax with visudo ..."
        # if visudo -c > /dev/null 2>&1; then
        if visudo -c; then
            echo "Sudoers syntax is correct."
        else
            echo "ERROR: Sudoers syntax check failed! There may be a problem, check /etc/sudoers.d/"
        fi
        echo -e "\nExiting ... you will need to re-run this script to create a new sudoers file."
        exit
    else
        echo "Continuing with existing sudoers config ..."
    fi

fi

#######################################################
#### Configure & copy wp-pull script for site user
#######################################################
if ( get_confirmation "Copy 'wp-pull' script into '${local_path}${install_dir}' ?" ); then

    tmp_file=$(mktemp)
    echo "Creating temporary file: $tmp_file"
    cat "./${install_name}.sh" > "$tmp_file"
    # Use sed to set the configuration
    echo "Writing config to file ..."
    sed -i "/^local_user=/c\local_user=\"$local_user\"" "$tmp_file"
    sed -i "/^local_path=/c\local_path=\"$local_path\"" "$tmp_file"
    sed -i "/^local_webroot=/c\local_webroot=\"$local_webroot\"" "$tmp_file"
    sed -i "/^remote_user=/c\remote_user=\"$remote_user\"" "$tmp_file"
    sed -i "/^remote_path=/c\remote_path=\"$remote_path\"" "$tmp_file"
    sed -i "/^remote_webroot=/c\remote_webroot=\"$remote_webroot\"" "$tmp_file"
    echo "Install and set permissions" 
    mv $tmp_file "${local_path}${install_dir}/${install_name}"
    chown ${local_user}:${local_user} "${local_path}${install_dir}/${install_name}"
    chmod 0700 "${local_path}${install_dir}/${install_name}"
    echo "Done! The user '${local_user}' can now login via SSH and run the '${install_name}' command."

else

    echo "Cancelled! You will need to re-run the script to complete the configuration."
    exit

fi

exit
