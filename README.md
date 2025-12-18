# n8n Auto-Deploy to Fly.io

Automated deployment system that monitors Docker Hub for new stable n8n releases and automatically deploys them to Fly.io using GitHub Actions.

## Overview

This repository contains a GitHub Actions workflow that:

- Checks Docker Hub daily for new stable n8n versions
- Compares the latest version with your currently deployed version
- Automatically deploys updates when a new stable version is available
- Preserves your existing configuration and data during updates

## Setup

### Prerequisites

- A Fly.io account with an existing n8n application deployed
- A GitHub repository with this workflow
- Fly.io CLI access token

### Configuration Steps

#### 🔑 Step 1: Get Your Fly.io API Token

The workflow needs a Fly.io API token to authenticate and deploy updates.

**Option A: Create a Deploy Token (Recommended)**

```bash
# Install flyctl if you haven't already
# See: https://fly.io/docs/hands-on/install-flyctl/

# Authenticate with Fly.io
flyctl auth login

# Create a new deploy token (more secure, limited permissions)
flyctl tokens create deploy
```

**Option B: Use Your Personal Token**

```bash
# Get your personal access token
flyctl auth token
```

> 💡 **Tip**: The deploy token is more secure as it has limited permissions.

After running the command, you'll see output like:

```
FlyV1 fm2_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
```

📋 **Copy this token** - you'll need it in the next step!

---

#### 🔐 Step 2: Add Token to GitHub Secrets

Now let's securely store the token in your GitHub repository:

1. **Navigate to your repository on GitHub**

   - Go to `https://github.com/YOUR_USERNAME/YOUR_REPO`

2. **Open Settings**

   - Click the **⚙️ Settings** tab at the top of your repository

3. **Go to Secrets**

   - In the left sidebar, click **Secrets and variables** → **Actions**

4. **Create New Secret**

   - Click the green **New repository secret** button

5. **Configure the Secret**

   ```
   Name:  FLY_API_TOKEN
   Value: [Paste your token from Step 1]
   ```

   ⚠️ **Important**: The name must be exactly `FLY_API_TOKEN` (case-sensitive)

6. **Save**
   - Click **Add secret**

✅ **Done!** Your token is now securely stored and will be masked in all logs.

---

#### ✅ Step 3: Verify fly.toml Configuration

Make sure your `fly.toml` file has your app name configured:

```toml
app = 'n8n-run'  # ← Your Fly.io app name
primary_region = 'ams'

[build]
  image = 'n8nio/n8n'
# ... rest of your config
```

The workflow will automatically read your app name from this file.

> 💡 **Find your app name**: Run `flyctl apps list` to see all your Fly.io apps

---

#### 🎉 Step 4: You're All Set!

The workflow is now configured and will run automatically. No additional setup needed!

**What happens next:**

- ⏰ The workflow runs **daily at 2:00 AM UTC** to check for updates
- 🔍 It compares the latest n8n version with your deployed version
- 🚀 If a new stable version is found, it automatically deploys
- 📊 You can view all activity in the **Actions** tab

**Want to test it now?** See the [Manual Trigger](#manual) section below.

## Workflow Triggers

### Automatic (Scheduled)

The workflow runs automatically **daily at 2:00 AM UTC** to check for new versions.

To modify the schedule, edit `.github/workflows/deploy-n8n.yml`:

```yaml
on:
  schedule:
    - cron: "0 2 * * *" # Change this to your preferred schedule
```

Cron syntax examples:

- `0 2 * * *` - Daily at 2:00 AM UTC
- `0 */6 * * *` - Every 6 hours
- `0 0 * * 0` - Weekly on Sunday at midnight

### Manual

You can manually trigger the workflow at any time:

1. 🏠 **Go to your GitHub repository**

   - Navigate to `https://github.com/YOUR_USERNAME/YOUR_REPO`

2. 🎬 **Open the Actions tab**

   - Click the **Actions** tab at the top

3. 📋 **Select the workflow**

   - In the left sidebar, click **Deploy n8n to Fly.io**

4. ▶️ **Run the workflow**

   - Click the **Run workflow** dropdown button (top right)
   - Select the branch (usually `main`)
   - Click the green **Run workflow** button

5. 👀 **Watch it run**
   - The workflow will appear in the list below
   - Click on it to see real-time logs

> ⚡ **Quick tip**: This is useful for testing your setup or forcing an immediate update check!

## How It Works

```
┌─────────────────────────────────────────────────────────────┐
│  🕐 Scheduled Trigger (Daily at 2 AM UTC)                   │
│     or Manual Trigger                                        │
└────────────────────┬────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────┐
│  🔍 Step 1: Check Docker Hub                                │
│  • Query Docker Hub API for n8n tags                        │
│  • Filter out pre-releases (beta, alpha, rc)                │
│  • Find latest stable version (e.g., 1.23.4)                │
└────────────────────┬────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────┐
│  📊 Step 2: Compare Versions                                │
│  • Get current version from Fly.io                          │
│  • Compare using semantic versioning                        │
│  • Decide: Update needed?                                   │
└────────────────────┬────────────────────────────────────────┘
                     │
         ┌───────────┴───────────┐
         │                       │
         ▼                       ▼
    ✅ Up to date          🆕 New version
         │                       │
         ▼                       ▼
    Skip deploy           ┌─────────────────────────────────┐
         │                │  🚀 Step 3: Deploy              │
         │                │  • Deploy new Docker image      │
         │                │  • Preserve fly.toml config     │
         │                │  • Keep data volume intact      │
         │                │  • Run health checks            │
         │                └──────────┬──────────────────────┘
         │                           │
         └───────────┬───────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────┐
│  📝 Step 4: Report Results                                  │
│  • Log version information                                  │
│  • Create workflow summary                                  │
│  • Show success/failure status                              │
└─────────────────────────────────────────────────────────────┘
```

### Detailed Steps

1. **🔍 Version Detection**: Queries Docker Hub API for the latest stable n8n version

   - Filters out pre-release versions (beta, alpha, rc)
   - Uses semantic versioning to identify the latest stable release

2. **📊 Version Comparison**: Checks your currently deployed version on Fly.io

   - Compares using semantic versioning rules
   - Determines if an update is needed

3. **🚀 Deployment**: If a new version is available

   - Deploys the new Docker image to Fly.io
   - Preserves your existing `fly.toml` configuration
   - Maintains your data volume (no data loss)
   - Verifies deployment health after completion

4. **📝 Reporting**: Logs all actions and creates a workflow summary
   - ✅ Success: Reports the deployed version
   - ⏭️ No update: Confirms you're already up to date
   - ❌ Failure: Provides detailed error information

## 📊 Monitoring

### View Workflow Runs

1. 🏠 **Go to your GitHub repository**
2. 🎬 **Navigate to Actions tab**
3. 📋 **Click on "Deploy n8n to Fly.io" workflow**
4. 👀 **View individual workflow runs and their logs**

### Workflow Summary

Each workflow run provides a summary showing:

| Status     | Icon | Description                       |
| ---------- | ---- | --------------------------------- |
| ✅ Success | 🚀   | New version deployed successfully |
| ⏭️ Skipped | ✓    | Already running latest version    |
| ❌ Failed  | ⚠️   | Deployment encountered an error   |

**Example Summary:**

```
📦 Current Version: 1.22.5
🆕 Latest Version:  1.23.4
🚀 Action: Deployed new version
✅ Status: Success
```

## Troubleshooting

### Workflow Fails with "FLY_API_TOKEN secret is not configured"

**Problem**: The Fly.io API token is missing or not properly configured.

**Solution**:

1. Verify the secret is named exactly `FLY_API_TOKEN` (case-sensitive)
2. Ensure the token has deployment permissions
3. Try regenerating the token: `flyctl tokens create deploy`
4. Re-add the token to GitHub Secrets

### Workflow Fails with "Authentication failed"

**Problem**: The API token is invalid or has expired.

**Solution**:

1. Generate a new token: `flyctl tokens create deploy`
2. Update the `FLY_API_TOKEN` secret in GitHub with the new token
3. Re-run the workflow

### Workflow Fails with "Could not determine latest stable version"

**Problem**: Unable to query Docker Hub or parse version information.

**Solution**:

1. Check if Docker Hub is accessible: https://hub.docker.com/r/n8nio/n8n/tags
2. Review the workflow logs for specific error messages
3. The workflow will automatically retry on the next scheduled run

### Deployment Succeeds but Health Check Fails

**Problem**: The deployment completed but the application is not responding correctly.

**Solution**:

1. Check your Fly.io dashboard: https://fly.io/dashboard
2. View application logs: `flyctl logs`
3. Check application status: `flyctl status`
4. Fly.io's automatic rollback should restore the previous version
5. Review your `fly.toml` configuration for any issues

### No Deployment Triggered When Expected

**Problem**: A new version is available but the workflow didn't deploy it.

**Solution**:

1. Check the workflow logs to see the version comparison
2. Verify the new version is a stable release (not beta/alpha/rc)
3. Manually trigger the workflow to force a check
4. Review the version detection logic in the logs

### Workflow Doesn't Run on Schedule

**Problem**: The scheduled workflow is not executing.

**Solution**:

1. Ensure the workflow file is in the default branch (usually `main` or `master`)
2. Check that the repository is not archived or disabled
3. Verify the cron syntax is correct
4. Note: GitHub Actions may delay scheduled workflows during high load periods

## n8n 2.0 Compatibility

This deployment is fully compatible with n8n 2.x. The configuration includes all necessary environment variables and settings for n8n 2.0.

### n8n 2.0 Breaking Changes

When upgrading from n8n 1.x to 2.x, be aware of these breaking changes:

| Change | Impact | Action Required |
|--------|--------|-----------------|
| **Task Runners** | Code nodes now run in isolated environments | Enabled by default in `fly.toml` |
| **Env Vars in Code** | Environment variables blocked in Code nodes by default | Set `N8N_BLOCK_ENV_ACCESS_IN_NODE=false` if needed |
| **Start Node** | Deprecated and will not work | Replace with Manual Trigger node |
| **MySQL/MariaDB** | No longer supported | Migrate to PostgreSQL before upgrading |
| **Security Nodes** | ExecuteCommand and LocalFileTrigger disabled by default | Explicitly excluded in `fly.toml` |
| **Python Code** | Requires external task runners | Use `n8nio/runners` image for external mode |

### Pre-Upgrade Checklist

Before the auto-deployment upgrades you to n8n 2.x:

1. **Use the Migration Tool**: In your n8n instance, go to **Settings → Migration Report** to identify issues
2. **Replace Start Nodes**: Update workflows using the Start node to use Manual Trigger instead
3. **Check Code Nodes**: If your Code nodes access environment variables, you'll need to update the configuration
4. **Database**: If using MySQL/MariaDB, migrate to PostgreSQL first

### Configuration Details

The `fly.toml` includes these n8n 2.0 specific settings:

```toml
[env]
  # Task runners (enabled by default in 2.0)
  N8N_RUNNERS_ENABLED = "true"
  N8N_RUNNERS_MODE = "internal"

  # Environment variable access in Code nodes
  N8N_BLOCK_ENV_ACCESS_IN_NODE = "true"  # Set to "false" if needed

  # Security: Disabled risky nodes
  N8N_NODES_EXCLUDE = "[\"n8n-nodes-base.executeCommand\",\"n8n-nodes-base.localFileTrigger\"]"
```

### Memory Requirements

n8n 2.0 with task runners requires more memory. The configuration has been updated:

- **Previous**: 1GB RAM
- **Current**: 2GB RAM (for task runner overhead)

### Resources

- [n8n 2.0 Breaking Changes](https://docs.n8n.io/2-0-breaking-changes/)
- [Migration Tool Documentation](https://docs.n8n.io/migration-tool-v2/)
- [n8n 2.0 Announcement](https://blog.n8n.io/introducing-n8n-2-0/)

## Configuration Preservation

The workflow is designed to preserve your existing configuration:

- **fly.toml**: All settings remain unchanged
- **Data Volume**: Your n8n workflows and data are preserved
- **Environment Variables**: All environment variables are maintained
- **Only the Docker image version is updated**

## Security

- API tokens are stored securely in GitHub Secrets
- Tokens are automatically masked in workflow logs
- The workflow uses minimal required permissions
- Concurrency control prevents simultaneous deployments

## Manual Deployment

If you need to deploy a specific version manually:

```bash
# Deploy a specific version
flyctl deploy --image n8nio/n8n:1.23.4

# Or deploy the latest version
flyctl deploy --image n8nio/n8n:latest
```

## Support

- **n8n Documentation**: https://docs.n8n.io/
- **Fly.io Documentation**: https://fly.io/docs/
- **GitHub Actions Documentation**: https://docs.github.com/en/actions

## License

This workflow configuration is provided as-is for use with your n8n deployment.
