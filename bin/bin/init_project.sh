#!/bin/bash
# init_project.sh — Bootstrap CLAUDE.md and WORKLOG.md in the current directory
#
# Usage: init_project.sh [project-name]
#   project-name defaults to the current directory name

set -euo pipefail

PROJECT_NAME="${1:-$(basename "$PWD")}"
TODAY=$(date +%Y-%m-%d)

if [ -f CLAUDE.md ]; then
    echo "CLAUDE.md already exists, skipping."
else
    cat > CLAUDE.md << EOF
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
    echo "Created CLAUDE.md"
fi

if [ -f WORKLOG.md ]; then
    echo "WORKLOG.md already exists, skipping."
else
    cat > WORKLOG.md << EOF
# Worklog

## ${TODAY}

**What changed:**
- Project initialized

**Decisions & rationale:**
-

**Open threads:**
- Fill in CLAUDE.md sections
EOF
    echo "Created WORKLOG.md"
fi
