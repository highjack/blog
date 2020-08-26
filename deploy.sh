#!/bin/sh

# If a command fails then the deploy stops
set -e

printf "\033[0;32mDeploying updates to GitHub...\033[0m\n"

# Build the project.
hugo -t hyde-hyde # if using a theme, replace with `hugo -t <YOURTHEME>`
git add .
msg="rebuilding site $(date)"
git commit -m "$msg"
git push

# Go To Public folder
cd public

# Add changes to git.
git add .

# Commit changes.
git commit -m "$msg"

# Push source and build repos.
git push origin master
