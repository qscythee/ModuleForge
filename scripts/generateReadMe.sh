#!/bin/bash

SRC_DIR="lib"

# Start from the current directory
current_dir=$(pwd)

# Loop until we find the project root file or reach the root directory
while [ "$current_dir" != "/" ]; do
  if [ -f "$current_dir/$SRC_DIR" ]; then
    echo "Found project root at: $current_dir"
    break
  fi
  current_dir=$(dirname "$current_dir")
done

# Check if the source directory exists
if [ ! -d "$SRC_DIR" ]; then
    echo "Error: Source directory $SRC_DIR does not exist."
    exit 1
fi

# Get the remote URL of the repository
REMOTE_URL=$(git config --get remote.origin.url)

# Extract the repository name and owner from the URL
# For https://github.com/owner/repo.git
REPO_OWNER=$(echo "$REMOTE_URL" | sed -E 's#https://github.com/([^/]+)/.*#\1#')
REPO_NAME=$(echo "$REMOTE_URL" | sed -E 's#https://github.com/[^/]+/([^/]+)\.git#\1#')

# Print the repository owner and name
echo "Repository Owner: $REPO_OWNER"
echo "Repository Name: $REPO_NAME"
DOCS_LINK="https://$REPO_OWNER.github.io/$REPO_NAME"
echo "Docs Link: $DOCS_LINK"

# Output README file
README_FILE="README.md"

ACTIONS_LINK="https://github.com/$REPO_OWNER/$REPO_NAME/actions"

# Start the README file with a title and table header
cat <<EOF > "$README_FILE"
<p align="center">
	<img src="gh-assets/icon.webp" alt="$REPO_NAME Icon" width="82" style="vertical-align: middle; margin-right: 10px;">
	<b><i><font size="6">$REPO_NAME</font></i></b>
</p>

<p align="center">
	A collection of Luau packages tailored to supercharge your development experience and speed! 🚀
	<br>You can view documentation for each package [here]($DOCS_LINK).
</p>

<p align="center">
	<a href="$ACTIONS_LINK"><img src="https://img.shields.io/github/actions/workflow/status/$REPO_OWNER/$REPO_NAME/ci.yaml?branch=main" alt="Build Status"></img></a>
	<img title="MIT licensed" alt="License" src="https://img.shields.io/github/license/$REPO_OWNER/$REPO_NAME"></img>
</p>

<p align="center">
	<a href="https://x.com/qscythee"><img src="https://img.shields.io/badge/X-000000?style=for-the-badge&logo=x&logoColor=white" /></a>
</p>

---

## Packages 📦

| Package | Latest Version | Description |
|---------|----------------|-------------|
EOF

echo "Generating README.md..."

# Iterate through each package directory
for PACKAGE_DIR in "$SRC_DIR"/*/ ; do
    # Check if it's a directory
    if [ -d "$PACKAGE_DIR" ]; then
        # Path to the wally.toml file
        WALLY_TOML="$PACKAGE_DIR/wally.toml"

        # Check if wally.toml exists
        if [ -f "$WALLY_TOML" ]; then

            echo "Parsing package directory: $PACKAGE_DIR"

            # Extract package name, version, and description
            FORMATTED_NAME=$(grep '^formattedName =' "$WALLY_TOML" | cut -d'=' -f2 | xargs)
            PACKAGE_DOCS_LINK=$(grep '^docsLink =' "$WALLY_TOML" | cut -d'=' -f2 | xargs)
            PACKAGE_NAME=$(grep '^name =' "$WALLY_TOML" | cut -d'=' -f2 | xargs)
            PACKAGE_VERSION=$(grep '^version =' "$WALLY_TOML" | cut -d'=' -f2 | xargs)
            PACKAGE_DESCRIPTION=$(grep '^description =' "$WALLY_TOML" | cut -d'=' -f2 | xargs)
            IGNORE=$(grep '^ignore =' "$WALLY_TOML" | cut -d'=' -f2 | xargs)

            if [ "$IGNORE" = "true" ]; then
                echo "Ignoring package $PACKAGE_NAME"
                continue
            fi

            PACKAGE_DOCS_LINK="$DOCS_LINK/api/$PACKAGE_DOCS_LINK"
				WALLY_LINK="https://wally.run/package/$PACKAGE_NAME?version=$PACKAGE_VERSION"

            if [ -z "$FORMATTED_NAME" ]; then
                FORMATTED_NAME=$PACKAGE_NAME
                FORMATTED_NAME=$(echo "$FORMATTED_NAME" | sed "s/$REPO_OWNER\///g")
                echo "No formatted name provided for $FORMATTED_NAME. Using package name as formatted name."
            fi

				echo "Package Name: $FORMATTED_NAME"
				echo "Wally link: $WALLY_LINK"

            # Append the package information to the README file
            cat <<EOF >> "$README_FILE"
| [$FORMATTED_NAME]($PACKAGE_DOCS_LINK) | [\`$FORMATTED_NAME = "$PACKAGE_NAME@$PACKAGE_VERSION"\`]($WALLY_LINK) | $PACKAGE_DESCRIPTION |
EOF
        else
            echo "Warning: $WALLY_TOML not found"
        fi
    else
        echo "Warning: $PACKAGE_DIR is not a directory"
    fi
done

echo "README.md has been generated successfully."