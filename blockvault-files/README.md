# BlockVault Files - File Versioning Smart Contract

A Clarity smart contract for securely managing versioned files on the Stacks blockchain.

## Overview

BlockVault Files is a decentralized file versioning system that enables secure storage and management of file metadata on the blockchain. This smart contract provides robust version control, access permissions, and ownership management for files in a decentralized environment.

## Features

- **File Management**
  - Create files with detailed metadata
  - Store file hashes securely on-chain
  - Delete files (owner only)
  - Retrieve file information and version history

- **Version Control**
  - Upload new versions of existing files
  - Track complete version history with timestamps
  - Access specific versions or the latest version
  - List all versions of a file

- **Access Control**
  - Toggle between public and private files
  - Granular permissions system (view vs. edit)
  - Permission management for file owners
  - Transfer file ownership

- **Security**
  - Input validation for all user-provided data
  - Comprehensive error handling and reporting
  - Clear authorization checks throughout
  - Contract initialization protection

## Contract Functions

### Administration

- `initialize()` - Initialize the contract (can only be called once)
- `update-contract-owner(new-owner)` - Transfer contract ownership

### File Operations

- `create-file(file-id, name, description, hash, metadata, is-private)` - Create a new file
- `upload-version(file-id, hash, metadata)` - Upload a new version of a file
- `delete-file(file-id)` - Delete a file and all its versions

### File Access

- `get-file-info(file-id)` - Get file metadata
- `get-version(file-id, version)` - Get a specific version of a file
- `get-latest-version(file-id)` - Get the latest version of a file
- `list-versions(file-id)` - List all versions of a file

### Permission Management

- `set-privacy(file-id, is-private)` - Update file privacy settings
- `grant-permissions(file-id, editor, can-edit, can-view)` - Grant permissions to a user
- `revoke-permissions(file-id, editor)` - Revoke user permissions
- `check-permissions(file-id, user)` - Check a user's permissions for a file
- `transfer-ownership(file-id, new-owner)` - Transfer file ownership

## Error Codes

| Code | Description |
|------|-------------|
| u100 | Not authorized |
| u101 | File not found |
| u102 | Invalid version |
| u103 | Version already exists |
| u104 | Not file owner |
| u105 | Unauthorized editor |
| u106 | Contract not initialized |
| u107 | Contract already initialized |
| u108 | Empty string input |

## Data Structures

The contract uses three primary data maps:

1. **files** - Stores file metadata
2. **file-versions** - Stores version-specific information
3. **file-editors** - Manages access permissions

## Usage Examples

### Creating a New File

```clarity
(contract-call? .file-versioning create-file 
  "doc-123" 
  "Quarterly Report" 
  "Q1 2025 Financial Report" 
  "e4d909c290d0fb1ca068ffaddf22cbd0" 
  "{ \"type\": \"financial\", \"department\": \"accounting\" }"
  true)
```

### Uploading a New Version

```clarity
(contract-call? .file-versioning upload-version
  "doc-123"
  "a87ff679a2f3e71d9181a67b7542122c"
  "{ \"type\": \"financial\", \"department\": \"accounting\", \"status\": \"revised\" }")
```

### Granting Permissions

```clarity
(contract-call? .file-versioning grant-permissions
  "doc-123"
  'ST1PQHQKV0RJXZFY1DGX8MNSNYVE3VGZJSRTPGZGM
  true  ;; can-edit
  true) ;; can-view
```

## Installation

To deploy the contract to the Stacks blockchain:

1. Clone the repository: `git clone https://github.com/yourusername/blockvault-files.git`
2. Install Clarinet: [Clarinet Installation Guide](https://github.com/hirosystems/clarinet)
3. Test locally: `clarinet test`
4. Deploy to testnet: `clarinet deploy --testnet`

## Security Considerations

- The contract implements input validation for all user-provided data
- All functions include appropriate authorization checks
- Private files are only accessible to owners and explicitly permitted users
- File IDs must be unique to prevent collisions

## Limitations

- The contract can only delete up to 10 versions of a file at once
- For files with more versions, a batched deletion approach would be needed
- File content is not stored on-chain, only metadata and hashes