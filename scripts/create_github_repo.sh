#!/usr/bin/env bash
set -euo pipefail

# Usage:
# GITHUB_TOKEN=ghp_... REPO_NAME=NYC-Taxi-Data-Engineering-Project ./scripts/create_github_repo.sh

GITHUB_TOKEN=${GITHUB_TOKEN:-}
GITHUB_USER=${GITHUB_USER:-}
REPO_NAME=${REPO_NAME:-NYC-Taxi-Data-Engineering-Project}
PRIVATE=${PRIVATE:-false}
DESCRIPTION=${DESCRIPTION:-"NYC Taxi Data Engineering Project - infra, ingestion, analytics"}
ORG=${ORG:-}

if [ -z "$GITHUB_TOKEN" ]; then
  echo "ERROR: GITHUB_TOKEN environment variable is required"
  exit 1
fi

# If GITHUB_USER is not set, attempt to discover it from the token
if [ -z "$GITHUB_USER" ]; then
  GITHUB_USER=$(curl -s -H "Authorization: token $GITHUB_TOKEN" https://api.github.com/user | jq -r .login)
  if [ -z "$GITHUB_USER" ] || [ "$GITHUB_USER" = "null" ]; then
    echo "ERROR: Could not determine GitHub user. Set GITHUB_USER env or supply a valid token."
    exit 1
  fi
fi

body=$(jq -n --arg name "$REPO_NAME" --arg desc "$DESCRIPTION" --argjson priv $PRIVATE '{name:$name,description:$desc,private:$priv}')

if [ -n "$ORG" ]; then
  url="https://api.github.com/orgs/$ORG/repos"
else
  url="https://api.github.com/user/repos"
fi

echo "Creating repository $REPO_NAME at $url as $GITHUB_USER"
resp=$(curl -s -o /tmp/github_create_resp.json -w "%{http_code}" -X POST -H "Authorization: token $GITHUB_TOKEN" -H "Accept: application/vnd.github+json" -d "$body" "$url")

if [ "$resp" != "201" ] && [ "$resp" != "200" ]; then
  echo "GitHub API returned HTTP $resp"
  cat /tmp/github_create_resp.json
  exit 1
fi

clone_url=$(jq -r .clone_url /tmp/github_create_resp.json)
if [ -z "$clone_url" ] || [ "$clone_url" = "null" ]; then
  echo "Failed to parse clone_url from GitHub response"
  cat /tmp/github_create_resp.json
  exit 1
fi

echo "Repository created: $clone_url"

# Add remote and push
git remote remove origin 2>/dev/null || true
git remote add origin "$clone_url"

echo "Pushing current branch to origin..."
git push -u origin HEAD:master

echo "Done. Repository available at: $clone_url"
