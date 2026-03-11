---
name: Gitignore Secrets (Active Validation)
description: Ensures the agent always creates a .gitignore file to prevent checking in sensitive files or secrets when such files are generated.
---
# Gitignore Secrets (Active Validation)
Whenever you create, modify, or suggest a file that could potentially contain secrets, credentials, API keys, or environment-specific configurations (e.g., `.env`, `*.pem`, `*.key`, `secrets.json`), you **must** ensure these files are ignored immediately as an atomic step.
1. **Check for .gitignore**: Check if a `.gitignore` file exists in the root of the project.
2. **Create if Missing**: If a `.gitignore` file does not exist, you must proactively create one.
3. **Update if Present**: If a `.gitignore` file exists but does not already ignore the sensitive file type (or specific file name), you must append the correct pattern to it.
