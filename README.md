# mr - Make Repository

A simple CLI tool to quickly create and initialize GitHub repositories.

## Features

- 🚀 Create private GitHub repositories with a single command
- 🔑 Secure PAT storage using machine-specific encryption
- 📝 Automatic README initialization
- 🔄 Git setup and initial commit
- 🔒 Uses GitHub CLI under the hood for secure authentication

## Installation

1. First, ensure you have the GitHub CLI installed through Homebrew
2. Clone this repository to your local machine
3. Build the project using Swift
4. Copy the built binary to your local bin directory

## Usage

Simply run `mr` followed by your desired repository name:

    mr <repository-name>

On first run, you'll be prompted to enter a GitHub Personal Access Token (PAT). The token will be securely stored for future use.

### Getting a GitHub PAT

1. Visit: https://github.com/settings/tokens
2. Click "Generate new token" (classic)
3. Give it a name (e.g., "mr-tool")
4. Select scopes: 'repo' and 'workflow'
5. Click "Generate token"
6. Copy the generated token when prompted by mr

The token should start with `ghp_` and contain only letters and numbers.

## Example Output

When creating a new repository, you'll see:

    🔑 Setting up authentication...
    📦 Creating repository 'my-new-project' on GitHub...
    📝 Creating initial commit...
    🚀 Pushing to GitHub...
    ✅ Successfully created repository 'my-new-project'!
       Local path: /Users/you/my-new-project
       GitHub URL: https://github.com/yourusername/my-new-project

## Security

- PATs are encrypted using AES-GCM with a machine-specific key
- Machine-specific key is derived from:
  - Linux: `/etc/machine-id`
  - macOS: IOPlatformUUID
- Encrypted tokens are stored in `~/.mr_token`
- File permissions are set to 600 (user read/write only)
- Token can only be decrypted on the same machine it was encrypted on

## Requirements

- macOS or Linux
- GitHub CLI
- Swift 5.5 or later
- Xcode Command Line Tools

## Error Handling

- Invalid token format: Will prompt for correct format
- Authentication failure: Removes stored token and requests new one
- Maximum retry attempts: 3 tries before failing
- Network issues: Displays detailed error messages
- Permission issues: Ensures correct file permissions

## Development

Built with:
- Swift
- CryptoKit for encryption
- GitHub CLI for repository operations
- Foundation for file operations

## Notes

- All repositories are created as private by default
- Initial commit includes a basic README.md
- Uses environment variables for GitHub CLI authentication
- Automatically sets up git remote and pushes initial commit
