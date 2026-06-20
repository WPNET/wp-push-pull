# WordPress Push/Pull Scripts

A BASH script for copying WordPress sites between users on the same server. Perfect for managing development, staging, and production environments on a single server.

## 📑 Table of Contents

- [Overview](#-overview)
- [Security Notice](#-security-notice)
- [Requirements](#-requirements)
- [Quick Start](#-quick-start)
- [Command Options](#-command-options)
- [Advanced Features](#-advanced-features)
- [Troubleshooting](#-troubleshooting)
- [Known Limitations](#-known-limitations)

## 🎯 Overview

These scripts enable safe and efficient WordPress site transfers between different system users on a local server. They use `wp-cli`, `rsync`, and carefully controlled `sudo` permissions to handle both files and databases.

**Understanding LOCAL vs REMOTE**: Throughout this documentation, **LOCAL** refers to YOU (the user running the command), and **REMOTE** refers to the OTHER user's site. When you run `wp-pull`, you're pulling FROM the REMOTE user TO yourself (LOCAL). When you run `wp-push`, you're pushing FROM yourself (LOCAL) TO the REMOTE user.

### Key Features

- ✅ **Safe local transfers** - Copy sites between users on the same server
- ✅ **No SSH required** - Works entirely with local file access
- ✅ **Database & files** - Handles WordPress files, databases, and search-replace operations
- ✅ **Controlled permissions** - Uses temporary ACLs and sudoers rules
- ✅ **wp-cli integration** - Leverages WordPress CLI for database operations
- ✅ **Color-coded output** - Easy-to-read status messages and error reporting
- ✅ **Verbose mode** - Detailed logging when you need it
- ✅ **Protocol preservation** - Automatically handles http/https conversions
- ✅ **Smart prefix handling** - Detects and resolves database table prefix mismatches
- ✅ **Clean output** - Suppresses stderr noise from wp-cli by default
- ✅ **Flexible exclusions** - Customize which files to exclude from sync
- ✅ **Comprehensive validation** - Pre-flight checks prevent common errors

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
   - Security note: wp-pull requires fewer elevated privileges

2. **Select LOCAL user** - The user who will run the command (YOU)
   - This is YOUR user account that will execute the wp-pull/wp-push command
   - Displays numbered list of users with `/sites` directories
   - Validates home directory existence

3. **Select REMOTE user** - The OTHER user whose site you're syncing with
   - For wp-pull: this is the user you're copying FROM
   - For wp-push: this is the user you're copying TO
   - Automatically excludes LOCAL user from selection
   - Validates home directory existence

4. **Configure paths** - Specify custom webroots if needed
   - Default webroot: `files`
   - Option to specify custom webroot (e.g., `public_html`, `htdocs`)
   - Validates that directories exist before proceeding

5. **Review configuration** - Confirm settings before installation
   - Displays complete LOCAL and REMOTE configuration
   - Option to cancel before making changes

6. **Sudoers configuration**
   - Checks existing sudoers syntax with `visudo`
   - Creates new sudoers file with appropriate permissions
   - Verifies syntax before finalizing
   - Rolls back automatically on syntax errors
   - Sets proper file permissions (0440)

7. **Script installation**
   - Copies configured script to `~/.local/bin/` for the LOCAL user
   - Sets proper ownership and permissions (0700)
   - Makes command available in PATH

The wizard will:
- Create a sudoers file in `/etc/sudoers.d/` (e.g., `wp-pull-localuser-remoteuser`)
- Configure the script with your settings
- Install it to `~/.local/bin/` for the LOCAL user
- Validate all steps with clear success/error messages

### 3. Running a Pull/Push

**Important**: You must be logged in as the LOCAL user (the one who will execute the command).

```bash
# Login as the LOCAL user (YOU)
ssh local-user@your-server

# Run wp-pull to copy FROM the REMOTE user TO yourself (LOCAL)
# Direction: REMOTE (their site) → LOCAL (your site)
wp-pull

# Or run with options
wp-pull --verbose           # Show detailed output
wp-pull --db-only          # Only sync database
wp-pull --files-only       # Only sync files
wp-pull -h                 # Show help
```

**Visual flow for wp-pull**:
```
┌──────────────────┐           ┌──────────────────┐
│  REMOTE User     │  ─────>   │   LOCAL User     │
│  (Their site)    │  PULL     │   (Your site)    │
│  (Source)        │           │   (Destination)  │
└──────────────────┘           └──────────────────┘
```

## 📖 Command Options

**Understanding LOCAL vs REMOTE**: **LOCAL** = YOU (the user running the command), **REMOTE** = the OTHER user's site. For `wp-pull`, you pull FROM remote TO local. For `wp-push`, you push FROM local TO remote.

```bash
Options:
  --db-only                           Sync only the database (skip files)
  --files-only                        Sync only files (skip database)
  --no-db-import                      Export but don't import database
  --no-search-replace, --no-rewrite   Skip URL/path replacement in database
  --tidy-up                           Clean up old database dump files
  -e, --exclude 'path1 path2'         Additional paths to exclude from rsync (space-delimited, quoted)
  -a, --all-tables-with-prefix        Use --all-tables-with-prefix flag for wp search-replace commands (default)
  --no-all-tables-with-prefix         Disable --all-tables-with-prefix for wp search-replace commands
  -h, --help                          Show help message
  -v, --verbose                       Enable verbose output
```

### Common Usage Examples

```bash
# Standard full sync
wp-pull

# Database only
wp-pull --db-only

# Files only
wp-pull --files-only

# Disable custom table support
wp-pull --no-all-tables-with-prefix

# Exclude specific directories
wp-pull --exclude 'wp-content/uploads/cache wp-content/backups'

# Verbose mode for debugging
wp-pull --verbose

# Clean up old database dumps
wp-pull --tidy-up
```

## ⚡ Advanced Features

### Protocol Conversion
Automatically handles http/https differences between LOCAL and REMOTE sites, converting URLs appropriately during search-replace operations.

### Table Prefix Handling
Detects and resolves database table prefix mismatches (e.g., `wp_` vs `wpmu_`) with guided workflow and safety confirmations.

### Custom Table Support
Search-replace includes custom database tables created by plugins by default. Use `--no-all-tables-with-prefix` to revert to prefix-only table matching.

### File Exclusions
Default exclusions: `.wp-stats`, `.maintenance`, `.user.ini`, `wp-content/cache`, `wp-config.php`

Add custom exclusions:
```bash
wp-pull --exclude 'wp-content/uploads/cache wp-content/backups'
```

## 🛠️ Troubleshooting

### Common Issues

**"wp-cli is not installed"**
```bash
curl -O https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar
chmod +x wp-cli.phar
sudo mv wp-cli.phar /usr/local/bin/wp
```

**"Permission denied" errors**
- Ensure sudoers file was created correctly in `/etc/sudoers.d/`
- Verify sudoers syntax: `sudo visudo -c`

**"WordPress not found at path"**
- Verify the webroot path is correct
- Check that WordPress is installed: `wp core version --path=/path/to/wordpress`

**Need detailed output?**
```bash
wp-pull --verbose  # Shows all commands and full output
```

**Clean up old database dumps**
```bash
wp-pull --tidy-up  # Removes old database export files
```

## ⚠️ Known Limitations

- **Local only**: Does not work with remote servers or SSH transfers - both users must be on the same physical server
- **Multisite**: Untested with WordPress Multisite (WPMU) installations
- **wp-config.php**: May not work if `wp-config.php` is located above the webroot
- **Permissions**: Requires specific sudoers configuration via `setup.sh`
- **Disk space**: Database dumps require temporary disk space - use `--tidy-up` to clean up

---

**License**: Provided as-is for local development servers. Use at your own risk.  
**Support**: [GitHub Issues](https://github.com/WPNET/wp-push-pull/issues)  
**Version**: 1.5.1 | **Author**: gb@wpnet.nz
