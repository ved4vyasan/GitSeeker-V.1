<p align="center">
  <img src="logo.png" width="500">
</p>

# 🔍 GitSeeker: Advanced Forensic Secret Scanner

**GitSeeker** is a high-performance, automated security auditing tool designed specifically for Red Teamers, DevSecOps engineers, and Bug Bounty Hunters. While traditional scanners focus on the current state of a repository, GitSeeker performs a "Forensic Deep-Dive" into the entire lifecycle of a Git project to uncover secrets that were thought to be long gone.

## 🚀 Why GitSeeker?

Digital "ghosts" are everywhere. Developers often delete sensitive files or hardcoded credentials once they realize their mistake, assuming that removing the file clears the leak. **GitSeeker proves they are wrong.** It specializes in finding:
- **Historical Leaks**: Data that existed in the past but was deleted in later commits.
- **Stashed Secrets**: Sensitive data left in local `git stash` buffers that was never meant to be committed but remains in the environment.
- **Forgotten Diffs**: Credentials that were committed as part of a large code change and never caught.

## 🛡️ Core Features & Mechanics

### 1. **Forensic Recovery Engine**
GitSeeker doesn't just scan files; it recreates them. It uses `git rev-list --all` to identify every file ever deleted from the project and "undeletes" them into a temporary `/Deleted` directory for a full keyword and pattern analysis.

### 2. **3-Layer "Triple-Threat" Scanning**
Accuracy is prioritized over speed, though GitSeeker provides both. It runs a hybrid scan sequence:
- **Native Grep/Bash Engine**: Custom regex patterns for modern cloud providers (AWS, Google Cloud, Stripe, OpenAI, etc.).
- **Gitleaks Integration**: High-entropy string detection and rule-based secret hunting.
- **TruffleHog Integration**: Deep git-history mining to find secrets across all branches.

### 3. **Deep History & Stash Analysis**
- **Commit Diff Auditor**: Analyzes the raw `git log -p` stream to find secrets that existed for only a single commit.
- **Stash Miner**: Scans the local Git stash stack. Often, developers stash sensitive config files while testing—GitSeeker ensures these don't stay hidden.

### 4. **Real-Time intelligence (Telegram)**
Get instant mobile notifications the moment a leak is detected. The alerts aren't just "ping" notifications; they include:
- The specific **Tool** that found the leak.
- The **Type** of secret (e.g., `aws-access-key`, `stripe-token`).
- The **Relative Path** to the report for immediate remediation.

### 5. **Organized Intelligence Layout**
Automatically categorizes findings into a clean directory structure:
- `/Repos`: Cloned sources.
- `/Results`: Summary scan logs.
- `/Gitleaks` & `/Trufflehog`: Detailed technical reports.
- `/History`: Findings from commit diffs.
- `/Stash`: Findings from the stash stack.
- `/Deleted`: The restored "ghost" files.

---
## ⚙️ Configuration & Quick Start

### 1. Prerequisites
Ensure you have the following in your path:
- `gitleaks` (https://github.com/gitleaks/gitleaks)
- `trufflehog` (https://github.com/trufflesecurity/trufflehog)

### 2. Setup

Clone the repo :
```bash 
git clone https://github.com/ved4vyasan/GitSeeker-V.1.git
cd GitSeeker-V.1
chmod +x gitseeker.sh
./gitseeker.sh --help
```

create .env file on the same folder and add this:
```bash
GITHUB_TOKEN=your_token
TELEGRAM_BOT_TOKEN=your_bot_token
TELEGRAM_CHAT_ID=your_chat_id
```
### 3. The Hunt
```bash
# Scan an entire organization
./gitseeker.sh apple

# Scan a specific repository
./gitseeker.sh user/repo
```

---

## 📜 Disclaimer
*This tool is intended for authorized security auditing and bug bounty purposes only. Ensure you have explicit permission before scanning repositories you do not own.*

-------------------------------------------------------------------------------------------------------------------------------------------------------------------------

### Any Queries:
```bash
mail - vyasan444@gmail.com
