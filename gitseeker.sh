#!/bin/bash

set -e

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'


# Setup folders
REPOS_DIR="Repos"
RESULTS_DIR="Results"
GITLEAKS_DIR="Gitleaks"
TRUFFLEHOG_DIR="Trufflehog"
DELETED_DIR="Deleted"
STASH_DIR="Stash"
HISTORY_DIR="History"

mkdir -p "$REPOS_DIR" "$RESULTS_DIR" "$GITLEAKS_DIR" "$TRUFFLEHOG_DIR" \
    "$DELETED_DIR" "$STASH_DIR" "$HISTORY_DIR"

# Spinner function
loading() {
    local pid=$!
    local spin='|/-\'
    while kill -0 $pid 2>/dev/null; do
        i=$(( (i+1) %4 ))
        printf "\r%s" "${spin:$i:1}"
        sleep .1
    done
    printf "\r"
}

# 1. Help / Input check
if [[ "$1" == "--help" || "$1" == "-h" ]]; then
    echo -e "${GREEN}Usage: $0 [org_name|user_name|repo_url]${NC}"
    echo -e "Examples:"
    echo -e "  $0 apple                         # Scan all repos in an organization"
    echo -e "  $0 user                  # Scan all repos of a user"
    echo -e "  $0 user/repo    # Scan a single repository"
    echo -e "  $0 github.com/user/repo          # URL support"
    exit 0
fi

if [ -f ".env" ]; then
    export $(grep -v '^#' .env | xargs)
fi

# Telegram Bot Config (Loaded from .env)
if [ -z "$TELEGRAM_BOT_TOKEN" ] || [ -z "$TELEGRAM_CHAT_ID" ]; then
    echo -e "${RED}⚠️ Telegram config not found in .env. Notifications disabled.${NC}"
fi

if [ -z "$1" ]; then
    echo -e "${RED}❌ Provide GitHub org/user URL or name.${NC}"
    echo -e "${GREEN}Run with --help for usage examples.${NC}"
    exit 1
fi

input="$1"

# 2. Extract org/user and optional repo
# Remove protocol
clean_input="${input#*://}"
# Remove www.
clean_input="${clean_input#www.}"
# Remove github.com/
clean_input="${clean_input#github.com/}"

# Replace \ with / for consistency
clean_input="${clean_input//\\//}"

# Extract org/user and specific repo
if [[ "$clean_input" == */* ]]; then
    org_name=$(echo "$clean_input" | cut -d'/' -f1)
    repo_name_specific=$(echo "$clean_input" | cut -d'/' -f2)
else
    org_name="$clean_input"
    repo_name_specific=""
fi

if [ -z "$org_name" ]; then
    echo -e "${RED}❌ Could not parse organization/user name from '$input'.${NC}"
    exit 1
fi

echo -e "${GREEN}🔄 Fetching repos from GitHub: $org_name${NC}"

# Before fetching, check token
if [ -z "$GITHUB_TOKEN" ]; then
    echo -e "${RED}❌ GITHUB_TOKEN is not set. Please export GITHUB_TOKEN=yourtoken.${NC}"
    exit 1
fi

# 3. Fetch repositories

if [ -n "$repo_name_specific" ]; then
    echo -e "${GREEN}🎯 Single repository specified: $org_name/$repo_name_specific${NC}"
    # Ensure it's a valid clone URL
    repos="https://github.com/${org_name}/${repo_name_specific%.git}.git"
else
    # Try fetching as organization first
    # After the first API call, add debugging:
    api_response=$(curl -s -H "Authorization: token $GITHUB_TOKEN" "https://api.github.com/orgs/${org_name}/repos?per_page=1000")

# Add debugging for API response
echo -e "${GREEN}🔍 Debug: Checking API response...${NC}"
if [ -z "$api_response" ]; then
    echo -e "${RED}❌ Empty API response${NC}"
    exit 1
fi

# Show API error message if present (except 404 Not Found)
if echo "$api_response" | jq -e '.message' >/dev/null 2>&1; then
    error_msg=$(echo "$api_response" | jq -r '.message')
    if [[ "$error_msg" != "Not Found" ]]; then
        echo -e "${RED}❌ GitHub API Error: $error_msg${NC}"
        exit 1
    fi
fi

# Check if API response contains rate limit error
if echo "$api_response" | grep -q "API rate limit exceeded"; then
    echo -e "${RED}❌ GitHub API rate limit exceeded. Please try again later or check authentication.${NC}"
    exit 1
fi

# Check if valid array response
if echo "$api_response" | jq -e 'type == "array"' >/dev/null 2>&1; then
    repos=$(echo "$api_response" | jq -r '.[].clone_url')
else
    # Not an org, try user
    echo -e "${RED}⚠️ Not an organization. Trying as a user...${NC}"

    api_response=$(curl -s -H "Authorization: token $GITHUB_TOKEN" "https://api.github.com/users/${org_name}/repos?per_page=1000")

    if echo "$api_response" | grep -q "API rate limit exceeded"; then
        echo -e "${RED}❌ GitHub API rate limit exceeded. Please try again later or check authentication.${NC}"
        exit 1
    fi

    if echo "$api_response" | jq -e 'type == "array"' >/dev/null 2>&1; then
        repos=$(echo "$api_response" | jq -r '.[].clone_url')
    else
        echo -e "${RED}❌ Failed to fetch repositories. Invalid username/org or no public repos.${NC}"
        echo "$api_response"
        exit 1
    fi
fi
fi # End of single repo check

# 4. Clone all repos
for repo_url in $repos; do
    repo_name=$(basename "$repo_url" .git)
    echo -e "${GREEN}🚀 Cloning $repo_name...${NC}"
    git clone "$repo_url" "$REPOS_DIR/$repo_name" & loading
done


echo -e "${GREEN}🎯 Cloning complete! Stored in: $REPOS_DIR/${NC}"

# 5. Prepare keywords
KEYWORDS=(
    "Jenkins" "OTP" "oauth" "authorization" "password" "pwd" "ftp" ".env"
    ".git-credentials" ".npmrc" ".dockercfg" ".bash_history" ".ssh"
    "JDBC" "key" "keys" "token" "user" "login" "signin" "passkey"
    "pass" "secret" "SecretAccessKey" "AWS_SECRET_ACCESS_KEY"
    "credentials" "config" "security_credentials" "connectionstring"
    "ssh2_auth_password" "DB_PASSWORD" "secret_key" "secretkey"
    "secret api" "secret token" "secret pass" "secret password"
    "aws secret" "client secret"
    "SMTP_PASSWORD" "DATABASE_URL" "AUTH_TOKEN" "API_TOKEN" "GCP_KEY"
    "AZURE_SECRET" "PRIVATE_KEY" "SESSION_SECRET" "FIREBASE_KEY"
    "STRIPE_SECRET_KEY" "HEROKU_API_KEY"
)

SPECIAL_FILES=(
    ".env" "config.js" "settings.py" "credentials.json"
    "keys.yaml" "docker-compose.yml" "Jenkinsfile" "secrets.yaml"
)

BACKUP_EXTENSIONS=("zip" "bak" "tar" "tar.gz")

# 6. Analyze each repo
for repo_path in "$REPOS_DIR"/*; do
    repo_name=$(basename "$repo_path")
    cd "$repo_path"

    mkdir -p "__ANALYSIS/del"
    rm -f "__ANALYSIS/del.log"

    # Recover deleted files
    git rev-list --all | while read -r commit; do
        parent_commit=$(git log --pretty=format:"%P" -n 1 "$commit" | awk '{print $1}')
        if [ -z "$parent_commit" ]; then continue; fi
        git diff --name-status -z "$parent_commit" "$commit" | \
            awk -v parent="$parent_commit" -v commit="$commit" 'BEGIN{RS="\0";FS="\t"} $1=="D"{print commit "|" parent "|" $2}' | \
            while IFS="|" read -r commit parent file; do
                safe_file=$(echo "$file" | sed 's/\//_/g')
                mkdir -p "__ANALYSIS/del"
                git show "${parent}:${file}" > "__ANALYSIS/del/${commit}___${safe_file}" 2>/dev/null || true
            done
    done

    leak_found=false

    # Analyze recovered deleted files for sensitive information
    if [ -d "__ANALYSIS/del" ] && [ "$(ls -A __ANALYSIS/del 2>/dev/null)" ]; then
        echo -e "${GREEN}🔍 Analyzing recovered deleted files for secrets...${NC}"
        mkdir -p "../../$DELETED_DIR/${repo_name}"
        for keyword in "${KEYWORDS[@]}"; do
            grep -rniI --exclude-dir={.git,__ANALYSIS} "$keyword" __ANALYSIS/del/ >> "../../$RESULTS_DIR/${repo_name}_scan.log" || true
        done
        # Move recovered files
        cp -r __ANALYSIS/del/* "../../$DELETED_DIR/${repo_name}/" || true
    else
        echo -e "${RED}⚠️ No deleted files found to analyze or directory empty.${NC}"
    fi

    # Keyword search in code
    for keyword in "${KEYWORDS[@]}"; do
        if grep -rniI --exclude-dir={.git,__ANALYSIS} "$keyword" . >> "../../$RESULTS_DIR/${repo_name}_scan.log"; then
            leak_found=true
        fi
    done

    # Scan commit messages
    if git log --pretty=format:"%h %s" | grep -iE "token|password|key|secret" >> "../../$RESULTS_DIR/${repo_name}_scan.log"; then
        leak_found=true
    fi

    # Check for .gitmodules existence
    if [ -f ".gitmodules" ]; then
        echo "Found .gitmodules:" >> "../../$RESULTS_DIR/${repo_name}_scan.log"
        cat .gitmodules >> "../../$RESULTS_DIR/${repo_name}_scan.log"
        leak_found=true
    fi

    # Look for .env and special sensitive files
    for special_file in "${SPECIAL_FILES[@]}"; do
        if find . -name "$special_file" >> "../../$RESULTS_DIR/${repo_name}_scan.log"; then
            leak_found=true
        fi
    done

    # Check for backup files
    for ext in "${BACKUP_EXTENSIONS[@]}"; do
        if find . -name "*.${ext}" >> "../../$RESULTS_DIR/${repo_name}_scan.log"; then
            leak_found=true
        fi
    done

    # --- Repo-specific tools scan ---
    
    # Ensure org_name is set
    echo "Debug: org_name is $org_name"

    # Run Gitleaks
    echo -e "${GREEN}🚀 Running scan on $repo_name...${NC}"
    gitleaks_output_file="../../$GITLEAKS_DIR/${repo_name}_gitleaks.json"
    gitleaks detect --source "." --report-path "$gitleaks_output_file" --no-banner || true

    if [ -s "$gitleaks_output_file" ] && ! grep -q '^\[\s*\]$' "$gitleaks_output_file"; then
        leak_types=$(jq -r '.[].RuleID' "$gitleaks_output_file" | sort | uniq | paste -sd ',' -)
        curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
             -d chat_id="${TELEGRAM_CHAT_ID}" \
             -d text="🚨 Detected leak in repository: ${org_name}/${repo_name}%0A🔍 Detected types: ${leak_types}%0A📂 Saved in: ${GITLEAKS_DIR}/" > /dev/null
    fi

    # Run TruffleHog
    echo -e "${GREEN}🚀 Running scan on $repo_name...${NC}"
    trufflehog_output_file="../../$TRUFFLEHOG_DIR/${repo_name}_trufflehog.json"
    trufflehog git file://$(pwd) --json > "$trufflehog_output_file" || true

    if [ -s "$trufflehog_output_file" ]; then
        # Use -s to handle TruffleHog newline-delimited JSON
        detectors=$(jq -r -s '.[].DetectorName' "$trufflehog_output_file" | sort | uniq | paste -sd ',' -)
        curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
             -d chat_id="${TELEGRAM_CHAT_ID}" \
             -d text="🚨 Detected leak in repository: ${org_name}/${repo_name}%0A🔍 Detected types: ${detectors}%0A📂 Saved in: ${TRUFFLEHOG_DIR}/" > /dev/null
    fi

    # Cloud service credential patterns
    CLOUD_PATTERNS=(
        "AKIA[0-9A-Z]{16}"                            # AWS Access Key ID
        "aws_access_key_id"
        "[0-9a-zA-Z/+]{40}"                          # AWS Secret Key
        "ASIA[0-9A-Z]{16}"                           # AWS Session Token
        "sk_live_[0-9a-zA-Z]{24}"                    # Stripe Live Key
        "rk_live_[0-9a-zA-Z]{24}"                    # Stripe Restricted Key
        "sq0csp-[0-9A-Za-z_-]{43}"                 # Square Access Token
        "[0-9]+-[0-9A-Za-z_]{32}\.apps\.googleusercontent\.com"  # Google OAuth
        "AIza[0-9A-Za-z_-]{35}"                    # Google API Key
        "[0-9a-zA-Z]{32}-[0-9a-zA-Z]{5}"            # Azure Storage Account
        "sk-[0-9a-zA-Z]{48}"                        # OpenAI API Key
    )

    # Analyze commit diffs for sensitive patterns (Optimized)
    echo -e "${GREEN}🔍 Analyzing commit diffs for sensitive data...${NC}"
    mkdir -p "../../$HISTORY_DIR/${repo_name}"
    diff_log="../../$HISTORY_DIR/${repo_name}/diff_analysis.log"
    
    # Combine patterns for awk
    combined_pattern=$(printf "|%s" "${CLOUD_PATTERNS[@]}")
    combined_pattern=${combined_pattern:1}

    git log -p | awk -v pat="$combined_pattern" '
        /^commit / { commit=$2 }
        $0 ~ pat { 
            print "Commit: " commit >> "'"$diff_log"'"
            print "Found potential secret: " $0 >> "'"$diff_log"'"
            found=1
        }
        END { exit !found }
    ' && leak_found=true || true

    # Check stash for secrets (Optimized)
    echo -e "${GREEN}🔍 Analyzing git stash for secrets...${NC}"
    mkdir -p "../../$STASH_DIR/${repo_name}"
    stash_log="../../$STASH_DIR/${repo_name}/stash_analysis.log"

    if git stash list | grep -q .; then
        git stash list -p | awk -v pat="$combined_pattern" '
            /^stash@/ { stash=$0 }
            $0 ~ pat { 
                print "Stash: " stash >> "'"$stash_log"'"
                print "Found potential secret: " $0 >> "'"$stash_log"'"
                found=1
            }
            END { exit !found }
        ' && leak_found=true || true
    fi

    # Telegram notifications for diffs/stash
    if [ -s "$diff_log" ]; then
        curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
             -d chat_id="${TELEGRAM_CHAT_ID}" \
             -d text="🚨 Found sensitive data in commit history: ${org_name}/${repo_name}%0A📂 Saved in: ${HISTORY_DIR}/${repo_name}/diff_analysis.log" > /dev/null
    fi
    if [ -s "$stash_log" ]; then
        curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
             -d chat_id="${TELEGRAM_CHAT_ID}" \
             -d text="🚨 Found sensitive data in git stash: ${org_name}/${repo_name}%0A📂 Saved in: ${STASH_DIR}/${repo_name}/stash_analysis.log" > /dev/null
    fi

    cd ../../
    # Ensure org_name is set 
# Update the final output message to include new directories
echo -e "${GREEN}✅ All analysis completed!${NC}"
echo -e "${GREEN}📁 Check folders: $REPOS_DIR/, $RESULTS_DIR/, $GITLEAKS_DIR/, $TRUFFLEHOG_DIR/, $DELETED_DIR/, $STASH_DIR/, $HISTORY_DIR/${NC}"
done  # <-- This closes the 'for repo_path' loop (if you are processing multiple repos)
