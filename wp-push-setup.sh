#!/bin/bash

script_version="1.0.5"
# Author:        gb@wpnet.nz
# Description:   Configure sudoers and install a script to allow a "site user" to run a "wp-push" command

#######################################################
#### Set up
#######################################################

# wp-push installed filename
install_name="wp-push"
# Default webroot
default_webroot="files"
# wp-push script install location for "site" user
install_dir=".local/bin"

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

    This script will configure a sudoers file and local "wp-push" script for a SpinupWP "site" user (SOURCE).
    The site user can then use "wp-push" to copy their site to another site on the same server, i.e. production -> staging
    - Creates sudoers file at /etc/sudoers.d/
    - Populates the wp-push script with SOURCE & DESTINATION parameters
    - Copies the script into the user's ~/.local/bin/ directory
    - Be sure to provide correct custom webroot paths if they are not default (files)
    - If a site's webroot is not default, enter like: "public_html", without preceding or trailing slash.

EOF

#######################################################
#### SOURCE
#######################################################

echo
read -p "ENTER SOURCE username: " source_user
source_home_path=$(getent passwd "$source_user" | cut -d: -f6)

if [ -n "$source_home_path" ]; then
    if (get_confirmation "Home dir of user '$source_user' is: '$source_home_path'. Is this correct?"); then
        source_path="${source_home_path}/"
    else
        # while true; do
        #     read -p "ENTER 'source_path' (no trailing slash): " source_path
        #     if dir_exists "$source_path"; then
        #         source_path="${source_path}/"
        #         break
        #     fi
        #     echo "Invalid path. Please try again."
        # done
        echo "Cancelled" && exit 1
    fi
else
    echo "User $source_user not found."
    exit 1
fi

if ( get_confirmation "Use default webroot ($default_webroot) for user $source_user?" ); then
    if dir_exists "${source_path}${default_webroot}"; then
        source_webroot="$default_webroot"
    else
        echo "Invalid: '${source_path}${default_webroot}' not found!"
        exit 1
    fi
else
    while true; do
        read -p "ENTER 'source_webroot' (no trailing slash, don't include the '${default_webroot}/' prefix): " source_webroot
        if dir_exists "${source_path}${default_webroot}/${source_webroot}"; then
            source_webroot="${default_webroot}/${source_webroot}"
            break
        fi
        echo "Invalid path. Please try again."
    done
fi

cat <<EOF

SOURCE details:
    source_user:              $source_user
    source_path/webroot:      ${source_path}${source_webroot}

EOF

#######################################################
#### DESTINATION 
#######################################################

echo
read -p "ENTER DESTINATION username: " destination_user
destination_home_path=$(getent passwd "$destination_user" | cut -d: -f6)

if [ -n "$destination_home_path" ]; then
    if (get_confirmation "Home dir of user '$destination_user' is: '$destination_home_path'. Is this correct?"); then
        destination_path="${destination_home_path}/"
    else
        # while true; do
        #     read -p "Enter 'destination_path' (no trailing slash): " destination_path
        #     if dir_exists "$destination_path"; then
        #         destination_path="${destination_path}/"
        #         break
        #     fi
        #     echo "Invalid path. Please try again."
        # done
        echo "Cancelled" && exit 1
    fi
else
    echo "User $destination_user not found."
    exit 1
fi

if ( get_confirmation "Use default webroot ($default_webroot) for user $destination_user?" ); then

    if dir_exists "${destination_path}${default_webroot}"; then
        destination_webroot="$default_webroot"
    else
        echo "Invalid: '${destination_path}${default_webroot}' not found!"
        exit 1
    fi
else
    while true; do
        read -p "ENTER 'destination_webroot' (no trailing slash, don't include the '${default_webroot}/' prefix): " destination_webroot
        if dir_exists "${destination_path}${default_webroot}/${destination_webroot}"; then
            destination_webroot="${default_webroot}/${destination_webroot}"
            break
        fi
        echo "Invalid path. Please try again."
    done
fi

cat <<EOF

SOURCE details:
    destination_user:         $destination_user
    destination_path/webroot: ${destination_path}${destination_webroot}

EOF

#######################################################
#### Define the SUDOERS file
#######################################################

sudoers_file="${install_name}-${source_user}-${destination_user}"
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
    sudo_rules="${source_user} ALL=(root) NOPASSWD: /usr/bin/setfacl, /usr/bin/rsync\n${source_user} ALL=(${destination_user}) NOPASSWD: /usr/bin/find, /usr/local/bin/wp"

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
#### Configure & copy wp-push script for site user
#######################################################
if ( get_confirmation "Copy 'wp-push' script into '${source_path}${install_dir}' ?" ); then

    tmp_file=$(mktemp)
    echo "Creating temporary file: $tmp_file"
    cat "./${install_name}.sh" > "$tmp_file"
    # Use sed to set the configuration
    echo "Writing config to file ..."
    sed -i "/^source_user=/c\source_user=\"$source_user\"" "$tmp_file"
    sed -i "/^source_path=/c\source_path=\"$source_path\"" "$tmp_file"
    sed -i "/^source_webroot=/c\source_webroot=\"$source_webroot\"" "$tmp_file"
    sed -i "/^destination_user=/c\destination_user=\"$destination_user\"" "$tmp_file"
    sed -i "/^destination_path=/c\destination_path=\"$destination_path\"" "$tmp_file"
    sed -i "/^destination_webroot=/c\destination_webroot=\"$destination_webroot\"" "$tmp_file"    
    echo "Install and set permissions" 
    mv $tmp_file "${source_path}${install_dir}/${install_name}"
    chown ${source_user}:${source_user} "${source_path}${install_dir}/${install_name}"
    chmod 0700 "${source_path}${install_dir}/${install_name}"
    echo "Done! The user '${source_user}' can now login via SSH and run the '${install_name}' command."

else

    echo "Cancelled! You will need to re-run the script to complete the configuration."
    exit

fi

exit
