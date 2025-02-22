# this will be a script, run by root, that will create the /etc/sudoers.d/ file, copy the wp-push script to ~/.local/bin, prefill with user and paths

# contents of the sudoers.d file. use filename like $source_user_$destination_user_sudo

# Password-less sudo for wp_push script
# ${source_user} ALL=(root) NOPASSWD: /usr/bin/setfacl, /usr/bin/rsync, /usr/local/bin/wp
# ${source_user} ALL=(${destination_user}) NOPASSWD: /usr/local/bin/wp, /usr/bin/rm

# if we can do all the dest wp-cli commands as sudo with --allow-root, we can remove the second line

#  is this /usr/bin/rm needed?  I don't think so. Need to test

# need to set permissions on the wp-push script after copied int

# need to ensure the sudoers.d file is created with the correct permissions 0440
