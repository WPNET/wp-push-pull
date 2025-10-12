# WordPress Push/Pull Scripts

A powerful and secure solution for copying WordPress sites between users on the same local server. Perfect for managing development, staging, and production environments on a single server.

## 🎯 Overview

These scripts enable safe and efficient WordPress site transfers between different system users on a local server. They use `wp-cli`, `rsync`, and carefully controlled `sudo` permissions to handle both files and databases.

### Key Features

- ✅ **Safe local transfers** - Copy sites between users on the same server
- ✅ **No SSH required** - Works entirely with local file access
- ✅ **Database & files** - Handles WordPress files, databases, and search-replace operations
- ✅ **Controlled permissions** - Uses temporary ACLs and sudoers rules
- ✅ **wp-cli integration** - Leverages WordPress CLI for database operations
- ✅ **Color-coded output** - Easy-to-read status messages and error reporting
- ✅ **Verbose mode** - Detailed logging when you need it

### Important Limitations

- ❌ Does **not** work with remote servers (local only)
- ❌ Does **not** use SSH or require `authorized_keys`
- ❌ May not work with `wp-config.php` located above webroot
- ❌ Untested with WordPress Multisite (WPMU)

## 🔐 Security Notice

**⚠️ SECURITY WARNING**: These scripts grant elevated privileges and should be used with extreme caution.

- Only use on trusted local development/staging servers
- Never give access to untrusted users
- Prefer `wp-pull` over `wp-push` (requires fewer elevated privileges)
- Review and understand the sudoers configuration before deployment

## 📋 Requirements

- Linux server (tested on Ubuntu 24.04)
- Root/sudo access for initial setup
- `wp-cli` installed and accessible to both users
- WordPress sites in standard directory structure
- Bash shell

## 🚀 Quick Start

### 1. Installation

```bash
# SSH into your server as a sudo-enabled user
ssh your-sudo-user@your-server

# Clone the repository (recommended location: /opt/)
cd /opt
sudo git clone https://github.com/WPNET/wp-push-pull.git
cd wp-push-pull

# Run the setup wizard
sudo bash setup.sh
```

### 2. Setup Wizard

The setup wizard will guide you through:

1. **Choose operation type**
   - `wp-pull` (recommended) - Pull sites from another user
   - `wp-push` - Push sites to another user

2. **Select LOCAL user** - The user who will run the command

3. **Select REMOTE user** - The user who owns the source/target site

4. **Configure paths** - Specify custom webroots if needed

5. **Review configuration** - Confirm settings before installation

The wizard will:
- Create a sudoers file in `/etc/sudoers.d/`
- Configure the script with your settings
- Install it to `~/.local/bin/` for the LOCAL user

### 3. Running a Pull/Push

```bash
# Login as the LOCAL user
ssh local-user@your-server

# Run the pull command (if configured for wp-pull)
wp-pull

# Or run with options
wp-pull --verbose           # Show detailed output
wp-pull --db-only          # Only sync database
wp-pull --files-only       # Only sync files
wp-pull -h                 # Show help
```

## 📖 Detailed Usage

### Terminology

- **LOCAL user**: The user executing the `wp-pull` or `wp-push` command
- **REMOTE user**: The user who owns the source (pull) or target (push) WordPress site

### Command Options

```bash
Options:
  --db-only                           Sync only the database (skip files)
  --files-only                        Sync only files (skip database)
  --no-db-import                      Export but don't import database
  --no-search-replace, --no-rewrite   Skip URL/path replacement in database
  --tidy-up                           Clean up old database dump files
  -h, --help                          Show help message
  -v, --verbose                       Enable verbose output
```

### Common Use Cases

#### Standard site pull (most common)
```bash
wp-pull
```
This will:
1. Sync all files from REMOTE to LOCAL
2. Export REMOTE database
3. Import to LOCAL database
4. Update URLs and paths in database
5. Clean up temporary files

#### Database-only sync
```bash
wp-pull --db-only
```
Useful when you only need to update the database without touching files.

#### Files-only sync
```bash
wp-pull --files-only
```
Perfect for updating themes, plugins, or uploads without touching the database.

#### Verbose output for troubleshooting
```bash
wp-pull --verbose
```
Shows detailed information about each operation.

## 🔧 How It Works

### Architecture

The system consists of two main components:

1. **Setup Script** (`setup.sh`)
   - Run once as root to configure permissions
   - Creates sudoers rules for controlled privilege elevation
   - Generates and installs user-specific wrapper script

2. **Operation Scripts** (`wp-pull.sh` / `wp-push.sh`)
   - Configured with LOCAL and REMOTE user details
   - Handles file sync via `rsync`
   - Manages database via `wp-cli`
   - Performs search-replace operations
   - Cleans up temporary files

### Operation Flow (wp-pull)

```
1. Pre-flight checks
   └─→ Verify paths exist
   └─→ Check wp-cli availability
   └─→ Fetch site information

2. Grant temporary permissions
   └─→ Use ACL to allow LOCAL user to read REMOTE files

3. Sync files
   └─→ rsync from REMOTE to LOCAL
   └─→ Preserve ownership and permissions

4. Database operations
   └─→ Export REMOTE database
   └─→ Copy to LOCAL
   └─→ Import to LOCAL
   └─→ Search-replace URLs and paths

5. Cleanup
   └─→ Remove temporary permissions
   └─→ Delete database dumps
```

### Security Model

**Principle of Least Privilege**: The scripts only grant the minimum permissions necessary:

#### wp-pull sudoers rules:
```
local_user ALL=(root) NOPASSWD: /usr/bin/setfacl
local_user ALL=(remote_user) NOPASSWD: /usr/local/bin/wp
```

#### wp-push sudoers rules (requires more privileges):
```
local_user ALL=(root) NOPASSWD: /usr/bin/setfacl, /usr/bin/rsync
local_user ALL=(remote_user) NOPASSWD: /usr/local/bin/wp
```

**Why wp-pull is preferred**: It requires fewer root privileges and only needs to read REMOTE files, not write them.

## 🛠️ Troubleshooting

### Common Issues

#### "wp-cli is not installed"
```bash
# Install wp-cli
curl -O https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar
chmod +x wp-cli.phar
sudo mv wp-cli.phar /usr/local/bin/wp
```

#### "Permission denied" errors
- Ensure sudoers file was created correctly in `/etc/sudoers.d/`
- Check file permissions: `ls -l /etc/sudoers.d/`
- Verify sudoers syntax: `sudo visudo -c`

#### "WordPress not found at path"
- Verify the webroot path is correct
- Check that WordPress is installed: `wp core version --path=/path/to/wordpress`

#### Database table prefix mismatch
The script will detect mismatches and offer to:
1. Reset the LOCAL database
2. Update `wp-config.php` with the correct prefix
3. Proceed with the import

#### Noisy wp-cli output
The scripts now automatically suppress stderr output in normal mode. Use `--verbose` to see full output when debugging.

### Debug Mode

Run with verbose flag to see detailed output:
```bash
wp-pull --verbose
```

This shows:
- All wp-cli commands and their output
- File sync progress
- Database operation details
- Timing information

### Cleanup

Remove old database dump files:
```bash
wp-pull --tidy-up
```

## 🗂️ File Structure

```
wp-push-pull/
├── README.md          # This file
├── setup.sh           # Setup wizard (run as root)
├── wp-pull.sh         # Pull operation script
└── wp-push.sh         # Push operation script
```

After setup, the LOCAL user will have:
```
~/.local/bin/
└── wp-pull            # or wp-push (configured wrapper script)
```

And the system will have:
```
/etc/sudoers.d/
└── wp-pull-localuser-remoteuser  # Sudoers configuration
```

## 🔄 Upgrade Guide

To upgrade to the latest version:

```bash
cd /opt/wp-push-pull
sudo git pull
# Re-run setup if needed
sudo bash setup.sh
```

## 🤝 Contributing

Contributions are welcome! Please:
1. Fork the repository
2. Create a feature branch
3. Test your changes thoroughly
4. Submit a pull request

## 📝 License

This project is provided as-is for use on local development servers. Use at your own risk.

## ⚠️ Known Limitations

- **wp-config.php location**: May not work if `wp-config.php` is above the webroot
- **Multisite**: Untested with WordPress Multisite (WPMU) installations
- **Remote servers**: Only works for local server transfers
- **Disk space**: Database dumps require temporary disk space

## 📚 Additional Resources

- [WP-CLI Documentation](https://wp-cli.org/)
- [rsync Manual](https://man7.org/linux/man-pages/man1/rsync.1.html)
- [Linux ACLs Guide](https://wiki.archlinux.org/title/Access_Control_Lists)

## 📧 Support

For issues and questions:
- Open an issue on [GitHub](https://github.com/WPNET/wp-push-pull/issues)
- Check existing issues for solutions

---

**Version**: 1.5.0  
**Last Updated**: 2025  
**Author**: gb@wpnet.nz
