#!/bin/bash

script_version="1.3.0"
# Author:        gb@wpnet.nz
# Description:   Setup script for wp-pull / wp-push commands
#                Configures sudoers permissions and installs wrapper scripts
#                Must be run as root or with sudo privileges

#######################################################
#### Set up
#######################################################

# installed filename
install_name=""
# Default webroot
default_webroot="files"
# script install location for "site" user
install_dir=".local/bin"
# Get all users
user_list=$(getent passwd)
# Filter users matching "::/sites/"
user_list=$(echo "$user_list" | grep "::/sites/")

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
    # No colors if not in a terminal
    clr_reset=""
    clr_bold=""
    clr_red=""
    clr_green=""
    clr_yellow=""
    clr_blue=""
    clr_cyan=""
fi

# Helper functions for consistent output
function success() {
    echo -e "${clr_green}✓ $@${clr_reset}"
}

function error() {
    echo -e "${clr_red}✗ ERROR: $@${clr_reset}"
}

function warning() {
    echo -e "${clr_yellow}⚠ WARNING: $@${clr_reset}"
}

function info() {
    echo -e "${clr_blue}ℹ $@${clr_reset}"
}

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

# Display setup banner
echo ""
echo -e "${clr_bold}${clr_cyan}═══════════════════════════════════════════════════════════════${clr_reset}"
echo -e "${clr_bold}${clr_cyan}     WordPress Push/Pull Setup - Configuration Wizard${clr_reset}"
echo -e "${clr_bold}${clr_cyan}═══════════════════════════════════════════════════════════════${clr_reset}"
echo ""

# Prompt for install type
info "Select operation type:"
echo "  1 = wp-pull (recommended - safer, requires fewer privileges)"
echo "  2 = wp-push (use only when pull is not feasible)"
echo ""
while true; do
    read -p "Enter choice [1 or 2]: " install_type
    case "$install_type" in
        1) 
            install_name="wp-pull"
            success "Selected: wp-pull (recommended)"
            break
            ;;
        2) 
            install_name="wp-push"
            warning "Selected: wp-push (requires elevated privileges)"
            break
            ;;
        *) 
            error "Invalid choice. Please enter 1 or 2."
            ;;
    esac
done

# Print setup instructions
echo ""
info "Setup Overview:"
cat <<EOF

    This wizard will:
    • Create a sudoers file at /etc/sudoers.d/
    • Configure ${install_name} script with LOCAL & REMOTE parameters
    • Copy the script into LOCAL user's ~/.local/bin/ directory
    
    Important notes:
    • LOCAL user:  The user who will run the ${install_name} command
    • REMOTE user: The user who owns the source/target WordPress site
    • Default webroot is 'files' - adjust if your setup differs
    • Custom webroot: enter directory name only (e.g., 'public_html')

EOF

#######################################################
#### LOCAL
#######################################################

echo
# Extract usernames and display numbered list
echo "Available users with /sites directories:"
echo "$user_list" | awk -F":" '{print NR ": " $1}'

while true; do
  # Prompt user for selection
  read -p "Select a LOCAL USER (c or x to cancel): " user_number

  case "$user_number" in
    c|x)
      echo "Cancelled."
      exit 1
      ;;
    [0-9]*)
      # Extract selected username
      local_user=$(echo "$user_list" | awk -F":" "NR==$user_number {print \$1}")
      # Check if a valid number was entered
      if [ -z "$local_user" ]; then
        echo "Invalid user. Please try again."
      else
        break
      fi
      ;;
    *)
      echo "Invalid input. Please enter a number, c, or x."
      ;;
  esac
done

local_home_path=$(getent passwd "$local_user" | cut -d: -f6)

if [ -n "$local_home_path" ]; then
    if (get_confirmation "Home dir of user '$local_user' is: '$local_home_path'. Is this correct?"); then
        local_path="${local_home_path}/"
    else
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
#### REMOTE
#######################################################

echo
# Filter the selected LOCAL user from the list (using awk to match username field only)
# Note: awk -v passes $local_user as a string, so $1 != user does string comparison (not regex)
# This is safe even if username contains special characters like dots or brackets
user_list=$(echo "$user_list" | awk -F":" -v user="$local_user" '$1 != user')

# Extract usernames and display numbered list
echo "Available users with /sites directories:"
echo "$user_list" | awk -F":" '{print NR ": " $1}'

while true; do
  # Prompt user for selection
  read -p "Select a REMOTE USER (c or x to cancel): " user_number

  case "$user_number" in
    c|x)
      echo "Cancelled."
      exit 1
      ;;
    [0-9]*)
      # Extract selected username
      remote_user=$(echo "$user_list" | awk -F":" "NR==$user_number {print \$1}")
      # Check if a valid number was entered
      if [ -z "$remote_user" ]; then
        echo "Invalid user. Please try again."
      else
        break
      fi
      ;;
    *)
      echo "Invalid input. Please enter a number, c, or x."
      ;;
  esac
done

remote_home_path=$(getent passwd "$remote_user" | cut -d: -f6)

if [ -n "$remote_home_path" ]; then
    if (get_confirmation "Home dir of user '$remote_user' is: '$remote_home_path'. Is this correct?"); then
        remote_path="${remote_home_path}/"
    else
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
    remote_user:         $remote_user
    remote_path/webroot: ${remote_path}${remote_webroot}

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
    if [[ $install_name == "wp-push" ]]; then
        # for wp-push, rsync needs to run with sudo (root), so file permissions and attrs can be set
        sudo_rules="${local_user} ALL=(root) NOPASSWD: /usr/bin/setfacl, /usr/bin/rsync\n${local_user} ALL=(${remote_user}) NOPASSWD: /usr/local/bin/wp"
    elif [[ $install_name == "wp-pull" ]]; then
        # for wp-pull, only setfacl needs to run with sudo (root)
        sudo_rules="${local_user} ALL=(root) NOPASSWD: /usr/bin/setfacl\n${local_user} ALL=(${remote_user}) NOPASSWD: /usr/local/bin/wp"
    fi

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
#### Configure & copy script for site user
#######################################################
if ( get_confirmation "Copy '${install_name}' script into '${local_path}${install_dir}' ?" ); then

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
