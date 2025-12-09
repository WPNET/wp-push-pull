#!/bin/bash

script_version="1.2.11"
# Author:        gb@wpnet.nz
# Description:   Configure sudoers and install script for wp-pull / wp-push command

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

# Running in a terminal?
tty -s && is_tty=1 || is_tty=0

# BASH colors
if (( is_tty == 1 )); then
    clr_reset="\e[0m"
    clr_bold="\e[1m"
    clr_yellow="\e[33m"
    clr_green="\e[32m"
    clr_cyan="\e[36m"
    clr_red="\e[31m"
    clr_blue="\e[34m"
else
    clr_reset=""
    clr_bold=""
    clr_yellow=""
    clr_green=""
    clr_cyan=""
    clr_red=""
    clr_blue=""
fi

# check a directory exists
dir_exists() {
  local dir="$1"
  if [[ -d "$dir" ]]; then
    echo -e "${clr_green}Directory '$dir' exists!${clr_reset}"
    return 0
  else
    echo -e "${clr_red}Directory '$dir' does not exist${clr_reset}"
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

# Prompt for install type
while true; do
        read -p "Set up for 1 = wp-pull or 2 = wp-push? " install_type
        case "$install_type" in
            1) install_name="wp-pull"; break;;
            2) install_name="wp-push"; break;;
            *) echo "Invalid choice. Please try again.";;
        esac
    done

# Print instructions
cat <<EOF

    This script will configure a sudoers file and local "${install_name}" script for a non-sudo "site" user
    - Creates sudoers file at /etc/sudoers.d/
    - Populates the ${install_name} script with LOCAL & REMOTE parameters
    - Copies the script into the LOCAL user's ~/.local/bin/ directory
    - Be sure to provide correct custom webroot paths if they are not default (i.e. 'files')
    - If a site's webroot is not default, enter only the custom directory, e.g. "public_html", without preceding or trailing slash
    - LOCAL user:  The user (and \$HOME path) who will run the script
    - REMOTE user: The user (and \$HOME path) from where the site will be pushed / pulled

EOF

#######################################################
#### LOCAL
#######################################################

echo
# Extract usernames and display numbered list
echo -e "${clr_cyan}${clr_bold}Available users with /sites directories:${clr_reset}"
echo "$user_list" | awk -F":" '{print NR ": " $1}'

while true; do
  # Prompt user for selection
  read -p "$(echo -e "${clr_bold}Select a LOCAL USER${clr_reset} (${clr_yellow}c${clr_reset} or ${clr_yellow}x${clr_reset} to cancel): ")" user_number

  case "$user_number" in
    c|x)
      echo -e "${clr_yellow}Cancelled.${clr_reset}"
      exit 1
      ;;
    [0-9]*)
      # Extract selected username
      local_user=$(echo "$user_list" | awk -F":" "NR==$user_number {print \$1}")
      # Check if a valid number was entered
      if [ -z "$local_user" ]; then
        echo -e "${clr_red}Invalid user. Please try again.${clr_reset}"
      else
        break
      fi
      ;;
    *)
      echo -e "${clr_red}Invalid input. Please enter a number, c, or x.${clr_reset}"
      ;;
  esac
done

local_home_path=$(getent passwd "$local_user" | cut -d: -f6)

if [ -n "$local_home_path" ]; then
    if (get_confirmation "Home dir of user '${clr_cyan}$local_user${clr_reset}' is: '${clr_cyan}$local_home_path${clr_reset}'. Is this correct?"); then
        local_path="${local_home_path}/"
    else
        echo -e "${clr_yellow}Cancelled${clr_reset}" && exit 1
    fi
else
    echo -e "${clr_red}User '$local_user' \$HOME not found. The user may not exist, or may not have a home directory set.${clr_reset}"
    exit 1
fi

if ( get_confirmation "Use default webroot ($default_webroot) for user ${clr_cyan}$local_user${clr_reset}?" ); then
    if dir_exists "${local_path}${default_webroot}"; then
        local_webroot="$default_webroot"
    else
        echo -e "${clr_red}Invalid: '${local_path}${default_webroot}' not found!${clr_reset}"
        exit 1
    fi
else
    while true; do
        read -p "$(echo -e "${clr_bold}ENTER 'local_webroot'${clr_reset} (no trailing slash, don't include the '${default_webroot}/' prefix): ")" local_webroot
        if dir_exists "${local_path}${default_webroot}/${local_webroot}"; then
            local_webroot="${default_webroot}/${local_webroot}"
            break
        fi
        echo -e "${clr_red}Invalid path. Please try again.${clr_reset}"
    done
fi

cat <<EOF

${clr_bold}${clr_green}LOCAL details:${clr_reset}
    ${clr_bold}local_user:${clr_reset}         ${clr_cyan}$local_user${clr_reset}
    ${clr_bold}local_path/webroot:${clr_reset} ${clr_cyan}${local_path}${local_webroot}${clr_reset}

EOF

#######################################################
#### REMOTE
#######################################################

echo
# Filter the selected LOCAL user from the list (using awk to match username field only)
user_list=$(echo "$user_list" | awk -F":" -v user="$local_user" '$1 != user')

# Extract usernames and display numbered list
echo -e "${clr_cyan}${clr_bold}Available users with /sites directories:${clr_reset}"
echo "$user_list" | awk -F":" '{print NR ": " $1}'

while true; do
  # Prompt user for selection
  read -p "$(echo -e "${clr_bold}Select a REMOTE USER${clr_reset} (${clr_yellow}c${clr_reset} or ${clr_yellow}x${clr_reset} to cancel): ")" user_number

  case "$user_number" in
    c|x)
      echo -e "${clr_yellow}Cancelled.${clr_reset}"
      exit 1
      ;;
    [0-9]*)
      # Extract selected username
      remote_user=$(echo "$user_list" | awk -F":" "NR==$user_number {print \$1}")
      # Check if a valid number was entered
      if [ -z "$remote_user" ]; then
        echo -e "${clr_red}Invalid user. Please try again.${clr_reset}"
      else
        break
      fi
      ;;
    *)
      echo -e "${clr_red}Invalid input. Please enter a number, c, or x.${clr_reset}"
      ;;
  esac
done

remote_home_path=$(getent passwd "$remote_user" | cut -d: -f6)

if [ -n "$remote_home_path" ]; then
    if (get_confirmation "Home dir of user '${clr_cyan}$remote_user${clr_reset}' is: '${clr_cyan}$remote_home_path${clr_reset}'. Is this correct?"); then
        remote_path="${remote_home_path}/"
    else
        echo -e "${clr_yellow}Cancelled${clr_reset}" && exit 1
    fi
else
    echo -e "${clr_red}User '$remote_user' \$HOME not found. The user may not exist, or may not have a home directory set.${clr_reset}"
    exit 1
fi

if ( get_confirmation "Use default webroot ($default_webroot) for user ${clr_cyan}$remote_user${clr_reset}?" ); then
    if dir_exists "${remote_path}${default_webroot}"; then
        remote_webroot="$default_webroot"
    else
        echo -e "${clr_red}Invalid: '${remote_path}${default_webroot}' not found!${clr_reset}"
        exit 1
    fi
else
    while true; do
        read -p "$(echo -e "${clr_bold}ENTER 'remote_webroot'${clr_reset} (no trailing slash, don't include the '${default_webroot}/' prefix): ")" remote_webroot
        if dir_exists "${remote_path}${default_webroot}/${remote_webroot}"; then
            remote_webroot="${default_webroot}/${remote_webroot}"
            break
        fi
        echo -e "${clr_red}Invalid path. Please try again.${clr_reset}"
    done
fi

cat <<EOF

${clr_bold}${clr_green}REMOTE details:${clr_reset}
    ${clr_bold}remote_user:${clr_reset}         ${clr_cyan}$remote_user${clr_reset}
    ${clr_bold}remote_path/webroot:${clr_reset} ${clr_cyan}${remote_path}${remote_webroot}${clr_reset}

EOF

#######################################################
#### Define the SUDOERS file
#######################################################

sudoers_file="${install_name}-${local_user}-${remote_user}"
sudoers_file="/etc/sudoers.d/$sudoers_file"

# only run config if same filename doesn't exist
if [ ! -f "$sudoers_file" ]; then

    # Check if existing sudoers config is OK, before we mess with it
    echo -e "${clr_cyan}Checking sudo syntax with visudo ...${clr_reset}"
    if visudo -c; then
        echo -e "${clr_green}Current sudoers syntax is correct.${clr_reset}"
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

    echo -e "${clr_cyan}Creating sudoers file at${clr_reset} ${clr_bold}$sudoers_file${clr_reset}"
    echo -e "$sudo_rules" > "$sudoers_file"
    chmod 0440 "$sudoers_file" # important!

    # Verify the syntax using visudo -c -f
    if visudo -c -f "$sudoers_file" > /dev/null 2>&1; then
        echo -e "${clr_green}Sudoers syntax is correct.${clr_reset}"
    else
        echo -e "${clr_red}ERROR: Sudoers syntax check failed. Rolling back ...${clr_reset}"
        rm -v "$sudoers_file"
        echo -e "\n${clr_red}Sudoers configuration failed!${clr_reset}"
        exit 1 # error
    fi
    echo -e "\n${clr_green}${clr_bold}Sudoers configuration complete.${clr_reset}"

else

    echo -e "\n${clr_yellow}Sudoers file already exists.${clr_reset}"
    if ( get_confirmation "Display existing sudoers file?" ); then
        cat $sudoers_file
    fi
    if ( ! get_confirmation "Keep existing sudoers file?" ); then
        rm -v "$sudoers_file"
        echo -e "${clr_cyan}Checking sudo syntax with visudo ...${clr_reset}"
        # if visudo -c > /dev/null 2>&1; then
        if visudo -c; then
            echo -e "${clr_green}Sudoers syntax is correct.${clr_reset}"
        else
            echo -e "${clr_red}ERROR: Sudoers syntax check failed! There may be a problem, check /etc/sudoers.d/${clr_reset}"
        fi
        echo -e "\n${clr_yellow}Exiting ... you will need to re-run this script to create a new sudoers file.${clr_reset}"
        exit
    else
        echo -e "${clr_cyan}Continuing with existing sudoers config ...${clr_reset}"
    fi

fi

#######################################################
#### Configure & copy script for site user
#######################################################
if ( get_confirmation "Copy '${clr_bold}${install_name}${clr_reset}' script into '${clr_cyan}${local_path}${install_dir}${clr_reset}' ?" ); then

    tmp_file=$(mktemp)
    echo -e "${clr_cyan}Creating temporary file: $tmp_file${clr_reset}"
    cat "./${install_name}.sh" > "$tmp_file"
    # Use sed to set the configuration
    echo -e "${clr_cyan}Writing config to file ...${clr_reset}"
    sed -i "/^local_user=/c\local_user=\"$local_user\"" "$tmp_file"
    sed -i "/^local_path=/c\local_path=\"$local_path\"" "$tmp_file"
    sed -i "/^local_webroot=/c\local_webroot=\"$local_webroot\"" "$tmp_file"
    sed -i "/^remote_user=/c\remote_user=\"$remote_user\"" "$tmp_file"
    sed -i "/^remote_path=/c\remote_path=\"$remote_path\"" "$tmp_file"
    sed -i "/^remote_webroot=/c\remote_webroot=\"$remote_webroot\"" "$tmp_file"
    echo -e "${clr_cyan}Install and set permissions${clr_reset}" 
    mv $tmp_file "${local_path}${install_dir}/${install_name}"
    chown ${local_user}:${local_user} "${local_path}${install_dir}/${install_name}"
    chmod 0700 "${local_path}${install_dir}/${install_name}"
    echo -e "${clr_green}${clr_bold}Done!${clr_reset} The user '${clr_cyan}${local_user}${clr_reset}' can now login via SSH and run the '${clr_bold}${install_name}${clr_reset}' command."

else
    echo -e "${clr_yellow}Cancelled! You will need to re-run the script to complete the configuration.${clr_reset}"
    exit
fi

exit
