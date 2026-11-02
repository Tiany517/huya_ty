# Encrypted Credential Vault

`migration-secrets-v2.aesgcm` is the current complete encrypted credential copy for this migration kit and uses AES-256-GCM. It currently contains:

- Four actual `.env` files found under the user profile.
- The Huya data-platform account and API credential verified against the AGENTS attachment at `credentials/bigdata-platform.txt`.
- The SMTP account/password, three WeCom webhooks, HDFS user identity, and source references found in the legacy DAU-alert scripts at `credentials/huya-alert-mail-credentials.txt`.
- Internal recipient routing extracted line by line from those scripts at `credentials/huya-alert-recipient-routing.txt`; restore it only after confirming that every recipient is still authorized.
- Credential recovery notes at `credentials/README.txt` and `credentials/huya-alert-mail-readme.txt`.

The GitHub password was exposed in chat and is scheduled for rotation, so the old password is not archived. Sign in again with GitHub device authorization or a new least-privilege token.

## Decrypt

The key file `huya_ty-env-files.key` is stored outside the repository. Transfer it to the new computer through an encrypted medium or password manager. Do not upload it to GitHub.

```powershell
node vault/decrypt-env-files.mjs vault/migration-secrets-v2.aesgcm <key-file> <new-staging-directory>
```

The decryption script writes `manifest.json` into the staging directory and verifies each file's SHA-256. The destination must be empty; existing files are never overwritten.

After decryption:

1. Move each `.env` value into the credential manager or secure configuration used by the corresponding tool. Do not leave it in a Git repository.
2. Store the Huya data-platform credential in the bigdata MCP secure credential configuration.
3. Remove the plaintext staging directory after verification.
4. Rotate the GitHub password and data-platform API key exposed in chat, then re-encrypt the vault.

## Re-encrypt

`encrypt-env-files.mjs` packages a staging directory into a new encrypted archive and refuses to overwrite an existing archive:

```powershell
node vault/encrypt-env-files.mjs <staging-directory> <key-file> <new-archive-file>
```

`add-source-credentials.mjs` merged the data-platform credential from the AGENTS attachment into the second bundle. `add-alert-mail-credentials.mjs` then merged the legacy alert-script SMTP, WeCom, HDFS identity, and recipient routing into the third bundle. Both scripts decrypt and re-encrypt in memory and never write plaintext credentials into the repository. Although the alert project is explicitly skipped, its credentials remain in the encrypted vault to satisfy the user's separate requirement for complete credential migration.

`migration-secrets.aesgcm` is the prior bundle without DAU-alert credentials, and `env-files.aesgcm` contains only `.env` files; both are historical copies. The new computer must use `migration-secrets-v2.aesgcm`. Rotate the SMTP password and WeCom webhooks before restoration because the legacy scripts stored them in plaintext.

Chinese version: `README.md`.
