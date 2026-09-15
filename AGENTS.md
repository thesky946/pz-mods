# Steam Workshop publishing

When the user asks to publish or release a new version to Steam, run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\publish_workshop.ps1
```

This builds current workspace content and updates Workshop item `3801601464` using `mod-manifest.json`. An explicit publishing request authorizes the upload; do not ask for redundant confirmation.

- Steam must be running and signed into the owning account.
- Use `-PatchNote '...'` for release notes supplied by the user.
- Use `-DryRun` to build and validate without uploading.
- Report success only after the uploader succeeds. Report errors without claiming publication.
- For repository context, read `CODEX.md`.
