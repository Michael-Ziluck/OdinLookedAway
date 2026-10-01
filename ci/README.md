**Local and unpublished.** No remote Actions runs or releases have been created. Publication scripts are hard-blocked until explicitly authorized.

# Automated builds and releases

GitHub Actions builds, checks, and packages every push to `main`, every pull request targeting
`main`, and manual workflow runs. ZIPs and a reference-version report are saved as workflow artifacts.
Pull requests only build; publication is disabled for this unpublished project.

Hosted Windows runners download the Valheim dedicated server anonymously with SteamCMD for its
actual game assemblies, and a checksum-pinned BepInExPack. No Steam login or game assemblies are
stored in Git. References are cached; change `referenceRevision` in `dependencies.json` to refresh
the game cache. The bootstrap rejects game versions outside Valheim 1.x.

## Security analysis

The `CodeQL` workflow runs extended C# and GitHub Actions security queries on pushes,
pull requests, and a weekly schedule. C# uses a traced manual build after obtaining the
same game and BepInEx references as the release build. It compiles only the production
project, not the .NET 8 test harness. This avoids the incomplete
dependency resolution of GitHub's default no-build C# scan.

GitHub CodeQL default setup must remain disabled because this repository uses advanced
setup in `.github/workflows/codeql.yml`. Other security features remain enabled.

## Publication settings

Repository variables:

| Variable | Value | Purpose |
| --- | --- | --- |
| RELEASE_PUBLISH_ENABLED | false | Create `vX.Y.Z` GitHub releases with the ZIP. |
| THUNDERSTORE_PUBLISH_ENABLED | false | Upload new versions to DocZee on Thunderstore. |
| HEXIUM_PUBLISH_ENABLED | false initially | Enable only after DocZee approval and API-token setup. |

Repository secrets:

- `THUNDERSTORE_API_TOKEN`: the DocZee service-account token.
- `HEXIUM_API_TOKEN`: a Hexium API token with permission to upload under DocZee. It is a separate token.

Packages use the Valheim community. Both registries receive the same built ZIP, with metadata
derived from its manifest. Hexium's API documents Thunderstore-compatible upload endpoints;
`ci/Publish-Hexium.ps1` uses the same pinned CLI against `https://valheim.hexium.gg`.
Hexium publishing is scaffolded and disabled while the team is pending approval; the first actual
upload still needs verification once approval and a token are available.

## Release a change

1. Update the version in the project, plugin declaration, and `manifest.json`; add changelog notes.
2. Commit and push to `main`.
3. Review the build and publication jobs in Actions.

Registries do not allow overwriting a version. A push with an already published version still
builds but skips uploading that registry's existing version. Failed uploads can be retried by
rerunning the workflow; each registry is checked independently. If only Hexium is enabled later,
rerun on `main` to publish the current version there without republishing Thunderstore.

Local commands:

```powershell
./ci/Build.ps1
./ci/Publish.ps1 -WhatIf
./ci/Publish-Hexium.ps1 -WhatIf
```

References: [GitHub Actions](https://docs.github.com/en/actions),
[Hexium packaging](https://hexium.gg/packaging), [Hexium API](https://hexium.gg/api/docs/),
[Thunderstore CLI](https://github.com/thunderstore-io/thunderstore-cli/wiki).
