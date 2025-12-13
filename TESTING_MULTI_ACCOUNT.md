# Multi-Account Testing Guide

## What You Need to Test with 2 Accounts

### Option 1: Use Two Different Gmail Accounts (Recommended)

**Requirements:**
- Access to 2 separate Gmail accounts (can be personal, family member's, or test accounts)
- 2-Step Verification enabled on both accounts
- Ability to create App Passwords for both accounts

**Setup:**
1. **Account 1**: Your existing account (rafal.zarajczyk@gmail.com)
   - Already configured and working

2. **Account 2**: A second Gmail account you own or have access to
   - Examples:
     - Personal backup account (e.g., rafal.zarajczyk.backup@gmail.com)
     - Work account (e.g., rafal@company.com)
     - Family member's account (with permission)
     - New test account (create free at gmail.com)

**Steps for Second Account:**
1. Go to the second Gmail account
2. Enable 2-Step Verification: https://myaccount.google.com/security
3. Generate App Password: https://myaccount.google.com/apppasswords
   - Select "Mail" as the app
   - Copy the 16-character password
4. Add to `.env` file:
   ```bash
   GMAIL_USER_2=second.account@gmail.com
   GMAIL_APP_PASSWORD_2=xxxx-xxxx-xxxx-xxxx
   RAINLOOP_PASSWORD_2=SecurePassword456
   ```

### Option 2: Create a Test Gmail Account (Easiest)

**If you don't have a second account:**
1. Go to https://accounts.google.com/signup
2. Create a new Gmail account (completely free)
   - Suggested name: `yourname.test@gmail.com` or `yourname.backup@gmail.com`
3. Enable 2-Step Verification immediately
4. Generate App Password
5. Send yourself a few test emails to this account (so there's data to sync)

### Option 3: Use Gmail Aliases (NOT RECOMMENDED)

⚠️ **This WON'T work** for multi-account testing because:
- Gmail aliases (user+alias@gmail.com) all use the same credentials
- OfflineIMAP would see them as the same account
- Container requires distinct Gmail accounts with separate credentials

## Testing Procedure

### Current State (1 Account)
```bash
# .env file
GMAIL_USER_1=rafal.zarajczyk@gmail.com
GMAIL_APP_PASSWORD_1=your-current-password
RAINLOOP_PASSWORD_1=SecurePassword123
```

### Step 7: Enable 2 Accounts

1. **Update `config/entrypoint.sh`:**
   ```bash
   MAX_ACCOUNTS=2  # Change from 1 to 2
   ```

2. **Add second account to `.env`:**
   ```bash
   GMAIL_USER_1=rafal.zarajczyk@gmail.com
   GMAIL_APP_PASSWORD_1=xxxx-xxxx-xxxx-xxxx
   RAINLOOP_PASSWORD_1=SecurePassword123

   GMAIL_USER_2=second.account@gmail.com
   GMAIL_APP_PASSWORD_2=yyyy-yyyy-yyyy-yyyy
   RAINLOOP_PASSWORD_2=SecurePassword456
   ```

3. **Rebuild and start:**
   ```bash
   docker-compose -f docker-compose.dev.yml down
   docker-compose -f docker-compose.dev.yml up --build -d
   ```

4. **Check logs:**
   ```bash
   docker logs gmail-backup-dev
   ```

   Expected output:
   ```
   [ENTRYPOINT] Discovering configured accounts...
   [ENTRYPOINT]   Account 1: rafal.zarajczyk@gmail.com
   [ENTRYPOINT]   Account 2: second.account@gmail.com
   [ENTRYPOINT] Found 2 account(s)
   ```

5. **Verify OfflineIMAP config:**
   ```bash
   docker exec gmail-backup-dev cat /data/offlineimap/.offlineimaprc
   ```

   Should show:
   ```ini
   [general]
   accounts = rafal.zarajczyk@gmail.com, second.account@gmail.com
   maxsyncaccounts = 2
   ```

6. **Verify Dovecot users:**
   ```bash
   docker exec gmail-backup-dev cat /etc/dovecot/users/passwd
   ```

   Should show both accounts:
   ```
   rafal.zarajczyk@gmail.com:{PLAIN}password1:...
   second.account@gmail.com:{PLAIN}password2:...
   ```

7. **Test Dovecot authentication:**
   ```bash
   docker exec gmail-backup-dev doveadm auth test rafal.zarajczyk@gmail.com SecurePassword123
   docker exec gmail-backup-dev doveadm auth test second.account@gmail.com SecurePassword456
   ```

8. **Check mail directories:**
   ```bash
   docker exec gmail-backup-dev ls -la /data/mail/
   ```

   Should show both:
   ```
   drwx------ rafal.zarajczyk@gmail.com/
   drwx------ second.account@gmail.com/
   ```

9. **Wait for sync (or check logs):**
   ```bash
   docker exec gmail-backup-dev tail -f /var/log/supervisor/offlineimap.log
   ```

10. **Test Rainloop login:**
    - Open http://localhost:8080
    - Login with account 1: `rafal.zarajczyk@gmail.com` / `SecurePassword123`
    - Logout
    - Login with account 2: `second.account@gmail.com` / `SecurePassword456`
    - Verify both accounts show their respective emails

11. **Test FTS search:**
    - In Rainloop, search for emails in each account
    - Verify search works independently per account

12. **Monitor resource usage:**
    ```bash
    docker stats gmail-backup-dev
    ```

## Verification Checklist

- [ ] Container starts without errors
- [ ] Logs show 2 accounts discovered
- [ ] OfflineIMAP config has both accounts
- [ ] Dovecot passwd file has both entries
- [ ] Both mail directories created
- [ ] Both accounts sync successfully
- [ ] Both accounts authenticate with Dovecot
- [ ] Rainloop login works for both accounts
- [ ] Emails appear in both accounts
- [ ] FTS search works for both accounts
- [ ] No interference between accounts
- [ ] Resource usage acceptable

## Expected Results

### Success Indicators:
- ✅ Both accounts sync in parallel
- ✅ Each account has isolated mail storage
- ✅ Independent FTS indexes per account
- ✅ No cross-contamination of emails
- ✅ Both accounts accessible via Rainloop
- ✅ Sync logs show both accounts

### Potential Issues:
- ⚠️ Gmail rate limiting (temporary connection errors)
- ⚠️ Increased CPU/memory usage with 2 accounts
- ⚠️ Longer initial sync times

## What We're Testing

1. **Account Discovery**: Does the loop correctly detect 2 accounts?
2. **OfflineIMAP**: Does it sync both accounts in parallel?
3. **Dovecot**: Does authentication work for both users?
4. **Mail Isolation**: Are emails stored in separate directories?
5. **FTS**: Does full-text search work independently?
6. **Rainloop**: Can we login and read emails from both accounts?
7. **Stability**: Does the container remain stable with 2 accounts?
8. **Resources**: Is CPU/memory usage reasonable?

## Rollback

If issues occur:
```bash
# Change back to 1 account
MAX_ACCOUNTS=1

# Remove second account from .env
# (comment out or delete GMAIL_USER_2, GMAIL_APP_PASSWORD_2, RAINLOOP_PASSWORD_2)

# Rebuild
docker-compose -f docker-compose.dev.yml up --build -d
```

## Notes

- **First sync**: Will take longer with 2 accounts (especially if mailboxes are large)
- **Resource usage**: Expect ~2x CPU during sync, modest increase in memory
- **Network**: Gmail may rate-limit if syncing aggressively
- **Testing order**: Always test with 2 accounts before jumping to 5
