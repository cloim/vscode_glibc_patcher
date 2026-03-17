# VS Code Server Patch for CentOS 7

## Overview
Starting from version 1.99, Visual Studio Code Remote SSH requires the remote host to have `glibc 2.28` or higher and a newer `libstdc++`. Since CentOS 7 natively provides `glibc 2.17` and an older `libstdc++`, connecting to a CentOS 7 machine via VS Code Remote SSH will result in a prerequisite error.

This script safely automates the process of compiling `glibc 2.28`, fetching a compatible `libstdc++` from the CentOS 8 Vault, and setting up the necessary environment variables so that the VS Code Server can run properly on CentOS 7 without breaking system-wide libraries.

## Features
* **Safe Isolation:** Installs custom glibc and libraries in `/opt/glibc-2.28` to prevent system-wide instability.
* **Dependency Handling:** Automatically updates tools and compiles `Make 4.3` required for the glibc build.
* **Library Fix:** Resolves the `GLIBCXX_3.4.21 not found` error by extracting a newer `libstdc++.so.6` from the CentOS 8 Vault.
* **Idempotency:** Checks if the patch is already applied and safely exits if true.
* **Auto-Cleanup:** Removes all temporary downloaded files and build directories upon successful installation or when skipping an already patched system.

## Prerequisites
Before running the script, ensure the target server meets the following requirements:
* **OS:** CentOS 7
* **Architecture:** `x86_64` (AMD64)
* **Privileges:** `root` access (via `sudo` or `su`)
* **Network:** Active internet connection to download source files and packages

## Usage

1. Download the script to your CentOS 7 machine:
   ```bash
   wget https://raw.githubusercontent.com/cloim/vscode_glibc_patcher/main/vscode_glibc_patcher.sh
   ```

2. Make the script executable:
   ```bash
   chmod +x vscode_glibc_patcher.sh
   ```

3. Run the script as **root**:
   ```bash
   sudo ./vscode_glibc_patcher.sh
   ```

4. **Wait for completion:** The compilation of `glibc` takes several minutes depending on the server's CPU performance. 

5. **Reconnect:** Once the script outputs the success message, open VS Code on your local machine and connect to the server via Remote - SSH. The connection should now establish successfully.

## License
Distributed under the MIT License.
