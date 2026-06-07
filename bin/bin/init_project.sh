#!/bin/bash
# init_project.sh — Bootstrap CONTRIBUTING.md, CHANGELOG.md, and agent symlinks in the current directory
#
# Usage: init_project.sh [project-name]
#   project-name defaults to the current directory name
#
# Creates CONTRIBUTING.md as the single source of truth for project instructions,
# then symlinks CLAUDE.md to it so all LLM agents read the same file.

set -euo pipefail

PROJECT_NAME="${1:-$(basename "$PWD")}"
TODAY=$(date +%Y-%m-%d)

if [ -f CONTRIBUTING.md ]; then
    echo "CONTRIBUTING.md already exists, skipping."
else
    cat > CONTRIBUTING.md << EOF
# ${PROJECT_NAME}

## Build

\`\`\`bash
# TODO: build commands
\`\`\`

## Test

\`\`\`bash
# TODO: test commands
\`\`\`

## Deploy

\`\`\`bash
# TODO: deploy commands
\`\`\`

## Architecture

<!-- Overview of the project structure, key modules, data flow -->

## Patterns & Conventions

<!-- Coding patterns, naming conventions, error handling approach -->

## Key Files

<!-- Important files and their roles -->
EOF
    echo "Created CONTRIBUTING.md"
fi

# Symlink agent-specific filenames → CONTRIBUTING.md
for name in CLAUDE.md AGENTS.md; do
    if [ -L "$name" ]; then
        echo "$name symlink already exists, skipping."
    elif [ -f "$name" ]; then
        echo "WARNING: $name exists as a regular file. Rename or remove it, then re-run."
    else
        ln -s CONTRIBUTING.md "$name"
        echo "Created $name → CONTRIBUTING.md symlink"
    fi
done

# Add symlinks to .gitignore so they don't get committed
for name in CLAUDE.md AGENTS.md; do
    if [ -f .gitignore ] && grep -qxF "$name" .gitignore; then
        continue
    fi
    echo "$name" >> .gitignore
done

if [ -f CHANGELOG.md ]; then
    echo "CHANGELOG.md already exists, skipping."
else
    cat > CHANGELOG.md << EOF
# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/).

## [Unreleased]

### Added

- Project initialized
- Fill in CONTRIBUTING.md sections
EOF
    echo "Created CHANGELOG.md"
fi
