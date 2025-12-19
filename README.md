# WordPress Push/Pull Scripts

A powerful and secure solution for copying WordPress sites between users on the same local server. Perfect for managing development, staging, and production environments on a single server.

## 📑 Table of Contents

- [Overview](#-overview)
- [Security Notice](#-security-notice)
- [Requirements](#-requirements)
- [Quick Start](#-quick-start)
- [Detailed Usage](#-detailed-usage)
- [Advanced Features](#-advanced-features)
- [How It Works](#-how-it-works)
- [Troubleshooting](#-troubleshooting)
- [File Structure](#-file-structure)
- [Recent Changes](#-recent-changes-v151)
- [Best Practices](#-best-practices)
- [FAQ](#-frequently-asked-questions)
- [Known Limitations](#-known-limitations)
- [Additional Resources](#-additional-resources)

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

2. **Select LOCAL user** - The user who will run the command
   - Displays numbered list of users with `/sites` directories
   - Validates home directory existence

3. **Select REMOTE user** - The user who owns the source/target site
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
- **Protocol**: The URL scheme (http or https) used by the WordPress site
- **Table prefix**: The database table prefix defined in `wp-config.php` (e.g., `wp_`, `wpmu_`)

### Command Options

```bash
Options:
  --db-only                           Sync only the database (skip files)
  --files-only                        Sync only files (skip database)
  --no-db-import                      Export but don't import database
  --no-search-replace, --no-rewrite   Skip URL/path replacement in database
  --tidy-up                           Clean up old database dump files
  -e, --exclude 'path1 path2'         Additional paths to exclude from rsync (space-delimited, quoted)
  -a, --all-tables                    Use --all-tables flag for wp search-replace commands
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

#### Custom file exclusions
```bash
wp-pull --exclude 'wp-content/uploads/cache wp-content/backups'
```
Exclude specific directories from the file sync (in addition to default exclusions).

#### Search-replace all tables (including non-WordPress tables)
```bash
wp-pull --all-tables
```
By default, search-replace only affects WordPress core tables. Use this flag to include custom tables.

#### Cleanup old database dumps
```bash
wp-pull --tidy-up
```
Removes old database dump files from both LOCAL and REMOTE directories to free up disk space.

### Real-World Usage Examples

#### Example 1: Complete site migration with protocol change
```bash
# Scenario: Production uses https, development uses http
# REMOTE: https://production.example.com (table prefix: wp_)
# LOCAL:  http://dev.example.com (table prefix: wp_)

wp-pull

# Output shows:
# ℹ FROM: production@/var/www/production
# ℹ TO:   developer@/var/www/dev
# ✓ Protocol preservation: https → http conversion applied
# ✓ URL replacement complete (protocol converted)
# ✓ Site URL: http://dev.example.com
```

#### Example 2: Handling table prefix mismatch
```bash
# Scenario: REMOTE site uses wpmu_ prefix, LOCAL uses wp_
wp-pull

# Script detects mismatch and prompts:
# ⚠ WARNING: Database table prefix mismatch detected!
# ⚠ WARNING: LOCAL prefix:  wp_
# ⚠ WARNING: REMOTE prefix: wpmu_
# 
# After confirmation:
# ✓ Database reset complete
# ✓ Table prefix updated to: wpmu_
# ✓ Database import complete!
```

#### Example 3: Quick content update without database changes
```bash
# Scenario: Only need to update themes/plugins/uploads
wp-pull --files-only

# Skips all database operations
# Syncs only files and directories
```

#### Example 4: Database refresh with custom table support
```bash
# Scenario: Site has custom tables that need URL updates
wp-pull --db-only --all-tables

# Updates URLs in ALL tables, not just WordPress core tables
# Useful for plugins that store URLs in custom tables
```

#### Example 5: Selective sync with exclusions
```bash
# Scenario: Large upload directory, only need recent changes
wp-pull --exclude 'wp-content/uploads/2020 wp-content/uploads/2021 wp-content/uploads/2022'

# Excludes specified directories from sync
# Combined with default exclusions (cache, .maintenance, etc.)
```

#### Example 6: Troubleshooting with verbose output
```bash
# Scenario: Operation failing, need to see detailed information
wp-pull --verbose

# Shows:
# - All wp-cli commands executed
# - Full command output
# - Detailed status messages
# - Timing information
# - PHP notices/warnings from wp-cli
```

## 🔧 How It Works

### Architecture

The system consists of two main components:

1. **Setup Script** (`setup.sh`)
   - Run once as root to configure permissions
   - Creates sudoers rules for controlled privilege elevation
   - Generates and installs user-specific wrapper script
   - Interactive wizard guides configuration
   - Validates paths and user selections

2. **Operation Scripts** (`wp-pull.sh` / `wp-push.sh`)
   - Configured with LOCAL and REMOTE user details
   - Handles file sync via `rsync` with intelligent exclusions
   - Manages database via `wp-cli` with stderr suppression
   - Performs search-replace operations with protocol awareness
   - Detects and resolves table prefix mismatches
   - Cleans up temporary files and permissions

### Operation Flow (wp-pull)

```
1. Pre-flight checks
   └─→ Verify paths exist
   └─→ Check wp-cli availability
   └─→ Fetch site information (URLs, database names, table prefixes)
   └─→ Display summary and request confirmation

2. Validate database compatibility
   └─→ Detect table prefix mismatches
   └─→ Offer to reset LOCAL database if needed
   └─→ Update wp-config.php with correct prefix

3. Grant temporary permissions
   └─→ Use ACL to allow LOCAL user to read REMOTE files

4. Sync files (if not --db-only)
   └─→ rsync from REMOTE to LOCAL
   └─→ Apply custom and default exclusions
   └─→ Preserve ownership and permissions
   └─→ Delete files not present in REMOTE

5. Database operations (if not --files-only)
   └─→ Export REMOTE database (with stderr suppression)
   └─→ Copy to LOCAL
   └─→ Import to LOCAL (with confirmation)
   └─→ Detect protocol differences (http vs https)
   └─→ Search-replace URLs with protocol awareness
   └─→ Search-replace file paths
   └─→ Verify and fix final URLs

6. Cleanup
   └─→ Remove temporary permissions
   └─→ Delete database dumps
   └─→ Flush WordPress cache
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

## ⚡ Advanced Features

### Protocol Preservation and Conversion

The scripts intelligently handle protocol (http/https) differences between LOCAL and REMOTE sites:

- **Same protocol**: Uses protocol-relative URLs (`//example.com`) for efficient replacement
- **Different protocols**: Automatically converts protocols during search-replace
- **Protocol detection**: Reads original LOCAL protocol and preserves it after migration
- **Verification**: Double-checks and fixes `siteurl` and `home` options after conversion

**Example scenarios:**
- REMOTE uses `https://prod.example.com` → LOCAL uses `http://dev.example.com`
- Script detects protocol mismatch and includes protocol in search-replace
- Final URLs are verified to use LOCAL's original protocol

### Database Table Prefix Mismatch Handling

When LOCAL and REMOTE sites have different table prefixes (e.g., `wp_` vs `wpmu_`):

1. **Detection**: Script compares `table_prefix` from both wp-config.php files
2. **Warning**: Displays clear warning about the mismatch
3. **Resolution workflow**:
   - Offers to reset LOCAL database (requires double confirmation)
   - Updates `wp-config.php` with REMOTE's table prefix
   - Proceeds with normal import and search-replace
4. **Safety**: Requires explicit user confirmation at each step

This prevents table import errors and ensures database compatibility.

### Stderr Suppression for Clean Output

By default, wp-cli can output numerous PHP notices, warnings, and deprecation messages to stderr. The scripts now:

- **Suppress stderr** in normal mode for clean, readable output
- **Preserve important errors** that affect operation success
- **Enable full output** in verbose mode (`--verbose`) for debugging
- **Use wrapper functions**: `sudo_as_remote_user()` and `wp_quiet()` handle suppression

This makes normal operations much cleaner while retaining debugging capability.

### Custom File Exclusions

Default exclusions (always applied):
- `.wp-stats`
- `.maintenance`
- `.user.ini`
- `wp-content/cache`
- `wp-config.php` (highly recommended to exclude)

**Add custom exclusions** with the `--exclude` flag:
```bash
wp-pull --exclude 'wp-content/uploads/large-files wp-content/backups'
```

Paths are relative to the WordPress root and space-delimited within quotes.

### Search-Replace Scope Control

By default, `wp search-replace` only affects core WordPress tables. Use `--all-tables` to:

- Include custom database tables created by plugins
- Replace URLs/paths in non-WordPress tables
- Useful for complex sites with custom integrations

**Example:**
```bash
wp-pull --all-tables
```

### Interactive Confirmations

The scripts include multiple confirmation prompts to prevent accidents:

- **Initial operation**: Confirm LOCAL→REMOTE direction and site details
- **Table prefix mismatch**: Double confirmation before database reset
- **Database import**: Confirm before importing (allows inspection of dump file)
- **Search-replace**: Confirm before URL/path replacement
- **File deletion**: Warning about files that will be deleted during sync
- **Cleanup operations**: Confirm before deleting database dumps

All confirmations default to "Yes" by pressing Enter.

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

**Example workflow:**
```
⚠ WARNING: Database table prefix mismatch detected!
⚠ WARNING: LOCAL prefix:  wp_
⚠ WARNING: REMOTE prefix: wpmu_

CONFIRM: Reset LOCAL site's database? Are you sure? [Yes/no/cancel]
CONFIRM: DANGER: This will DELETE ALL tables in database 'local_db'! Are you sure? [Yes/no/cancel]
✓ Database reset complete
✓ Table prefix updated to: wpmu_
```

#### Protocol mismatch (http vs https)
The script automatically detects and handles protocol differences:
- REMOTE uses https, LOCAL uses http → Converts URLs during search-replace
- Same protocol → Uses protocol-relative URLs for efficiency
- Preserves LOCAL's original protocol preference

#### Noisy wp-cli output
The scripts now automatically suppress stderr output in normal mode. Use `--verbose` to see full output when debugging.

**Normal mode:**
```bash
wp-pull  # Clean output, stderr suppressed
```

**Verbose mode:**
```bash
wp-pull --verbose  # Full wp-cli output for debugging
```

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

### Managing Disk Space

Remove old database dump files:
```bash
wp-pull --tidy-up
```

This scans both LOCAL and REMOTE directories for old database exports and offers to delete them:
```
ℹ Scanning LOCAL directory: /sites/localuser/
  /sites/localuser/wp_db_export_abc12348dsg.sql
  /sites/localuser/wp_db_export_def45648dsg.sql

ℹ Scanning REMOTE directory: /sites/remoteuser/
  /sites/remoteuser/wp_db_export_xyz78948dsg.sql

CONFIRM: DELETE ALL found database dump files? Are you sure? [Yes/no]
✓ Cleanup complete! Deleted 2 LOCAL and 1 REMOTE files.
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

## 🆕 Recent Changes (v1.5.1)

### Enhanced in Pull Request #1

**Major Features:**
- ✨ **Protocol preservation**: Automatic http/https detection and conversion
- ✨ **Table prefix validation**: Detects and resolves prefix mismatches automatically
- ✨ **Clean output**: Stderr suppression for wp-cli commands (use --verbose to restore)
- ✨ **Custom exclusions**: New `--exclude` flag for flexible file filtering
- ✨ **All-tables support**: New `--all-tables` flag for search-replace on custom tables
- ✨ **Enhanced confirmations**: Multiple safety checkpoints prevent accidental data loss

**Improvements:**
- 🔧 Better error handling and validation
- 🔧 Improved color-coded output with emoji indicators
- 🔧 More informative status messages
- 🔧 Tidy-up feature for disk space management
- 🔧 Pre-flight checks validate paths and wp-cli availability
- 🔧 Automatic cache flushing after database operations

**Setup Wizard:**
- 🎨 Interactive configuration with color-coded prompts
- 🎨 User-friendly selection menus
- 🎨 Path validation and existence checks
- 🎨 Sudoers syntax verification with rollback on failure

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
  - The script expects `wp-config.php` in the WordPress root directory
  - Custom wp-config locations are not currently supported
  
- **Multisite**: Untested with WordPress Multisite (WPMU) installations
  - Single-site WordPress installations are fully supported
  - Multisite may work but has not been thoroughly tested
  
- **Remote servers**: Only works for local server transfers
  - Both users must exist on the same physical server
  - Does not support SSH-based remote transfers
  - Does not work across different servers or VPS instances
  
- **Disk space**: Database dumps require temporary disk space
  - Export files are created temporarily during operations
  - Use `--tidy-up` to clean up old dump files
  - Ensure sufficient disk space for database exports
  
- **Large files**: Very large sites may take considerable time
  - rsync transfers large files efficiently but need time
  - Consider using `--files-only` or `--db-only` for partial updates
  
- **File permissions**: Requires specific sudoers configuration
  - Must be configured by root/administrator using `setup.sh`
  - Cannot be used without proper sudoers rules in place

## ❓ Frequently Asked Questions

### General Questions

**Q: Can I use this to migrate sites between different servers?**  
A: No, this tool only works for local transfers between users on the same server. It does not support SSH or remote transfers.

**Q: Is it safe to use in production?**  
A: These scripts are designed for local development/staging environments. Use with extreme caution on production servers and only with trusted users.

**Q: Which should I use, wp-pull or wp-push?**  
A: Always prefer `wp-pull` when possible. It requires fewer elevated privileges and is generally safer than `wp-push`.

### Setup Questions

**Q: Do I need to run setup.sh every time?**  
A: No, you only run `setup.sh` once per user pair. After that, the LOCAL user can run the command anytime.

**Q: Can I have multiple configurations?**  
A: Yes! You can run `setup.sh` multiple times for different user pairs. Each creates a separate sudoers file and script installation.

**Q: What if my WordPress is in a subdirectory?**  
A: During setup, specify the custom webroot path when prompted. For example, if WordPress is in `public_html/wp`, enter `public_html/wp` as the webroot.

### Operation Questions

**Q: Will this delete my LOCAL files?**  
A: Yes, `rsync --delete` removes files at LOCAL that don't exist at REMOTE. Always backup before running operations.

**Q: What happens if protocols don't match?**  
A: The script automatically detects protocol differences and adjusts the search-replace accordingly, preserving your LOCAL site's protocol preference.

**Q: Can I cancel during execution?**  
A: Yes, the script has multiple confirmation prompts. Press `n` or `c` to cancel at any prompt.

**Q: How do I see what went wrong?**  
A: Run with `--verbose` flag to see detailed output including all commands executed and their results.

### Database Questions

**Q: What if table prefixes don't match?**  
A: The script detects this and offers to reset the LOCAL database and update the prefix in `wp-config.php`.

**Q: Can I update only the database without touching files?**  
A: Yes, use the `--db-only` flag to skip file synchronization.

**Q: Will this affect my LOCAL user accounts?**  
A: Yes, importing a database will overwrite all WordPress data including users. You may need to reset passwords after import.

### Troubleshooting Questions

**Q: Why am I seeing permission errors?**  
A: Ensure the sudoers file was created correctly and has proper permissions (0440). Check with `sudo visudo -c`.

**Q: The script says wp-cli is not found?**  
A: Install wp-cli globally at `/usr/local/bin/wp` and ensure it's executable by both LOCAL and REMOTE users.

**Q: How do I clean up old database files?**  
A: Run `wp-pull --tidy-up` to scan and remove old database dump files from both LOCAL and REMOTE directories.

## 📚 Additional Resources

- [WP-CLI Documentation](https://wp-cli.org/)
- [rsync Manual](https://man7.org/linux/man-pages/man1/rsync.1.html)
- [Linux ACLs Guide](https://wiki.archlinux.org/title/Access_Control_Lists)
- [WordPress Database Description](https://codex.wordpress.org/Database_Description)

## 💡 Best Practices

### Before Running Operations

1. **Backup first**: Always backup LOCAL site before running operations
   ```bash
   # Create a quick backup
   wp db export backup-$(date +%Y%m%d-%H%M%S).sql --path=/path/to/wordpress
   tar -czf backup-files-$(date +%Y%m%d-%H%M%S).tar.gz /path/to/wordpress
   ```

2. **Test with --verbose**: Run first operation with verbose flag to monitor behavior
   ```bash
   wp-pull --verbose
   ```

3. **Check site compatibility**: Ensure both sites use compatible WordPress and PHP versions

4. **Review exclusions**: Consider what files shouldn't be synced (backups, logs, large uploads)

### During Operations

1. **Read prompts carefully**: Each confirmation describes what will happen
2. **Use specific flags**: Combine flags for precise control
   ```bash
   wp-pull --db-only --no-search-replace  # Import without URL changes
   wp-pull --files-only --exclude 'uploads'  # Files except uploads
   ```

3. **Monitor disk space**: Large sites need adequate free space for database dumps

### After Operations

1. **Verify site functionality**: Check that the site loads and functions correctly
2. **Test critical features**: Verify plugins, themes, and custom functionality
3. **Update credentials**: Reset admin passwords if needed
4. **Clear caches**: The script flushes WordPress cache, but also clear any external caching
5. **Run cleanup**: Use `--tidy-up` periodically to remove old dump files

### Security Best Practices

1. **Limit access**: Only give access to trusted users
2. **Use wp-pull**: Prefer pull over push for better security
3. **Review sudoers**: Understand what permissions are being granted
4. **Regular audits**: Periodically review `/etc/sudoers.d/` for unnecessary rules
5. **Development only**: Use on dev/staging servers, not production
6. **Remove when done**: If a user no longer needs access, remove their sudoers file

### Performance Optimization

1. **Partial updates**: Use `--files-only` or `--db-only` when appropriate
2. **Exclude large directories**: Use `--exclude` for directories that don't need syncing
3. **Off-peak hours**: Run large operations during low-traffic periods
4. **Local network**: Ensure both users are on the same server for fastest transfers

## 📧 Support

For issues and questions:
- Open an issue on [GitHub](https://github.com/WPNET/wp-push-pull/issues)
- Check existing issues for solutions
- Include output from `--verbose` mode when reporting issues

---

**Version**: 1.5.1  
**Last Updated**: December 2025  
**Author**: gb@wpnet.nz
