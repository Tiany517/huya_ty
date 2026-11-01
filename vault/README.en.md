# Encrypted Credential Vault

`migration-secrets.aesgcm` is the complete encrypted credential copy for this migration kit and uses AES-256-GCM. It currently contains:

- Four actual `.env` files found under the user profile.
- The Huya data-platform account and API credential verified against the AGENTS attachment at `credentials/bigdata-platform.txt`.
- Credential recovery notes at `credentials/README.txt`.

The GitHub password was exposed in chat and is scheduled for rotation, so the old password is not archived. Sign in again with GitHub device authorization or a new least-privilege token.

## Decrypt

The key file `huya_ty-env-files.key` is stored outside the repository. Transfer it to the new computer through an encrypted medium or password manager. Do not upload it to GitHub.

```powershell
node vault/decrypt-env-files.mjs vault/migration-secrets.aesgcm <key-file> <new-staging-directory>
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

`add-source-credentials.mjs` merges the data-platform credential from the AGENTS attachment into the older encrypted archive. It decrypts and re-encrypts in memory only and never writes plaintext credentials into the repository. The script is retained to make this bundle's construction auditable.

The legacy `env-files.aesgcm` contains only `.env` files and is retained as a historical copy. The new computer should use `migration-secrets.aesgcm`.

Chinese version: `README.md`.
