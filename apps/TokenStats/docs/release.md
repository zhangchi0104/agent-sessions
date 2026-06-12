# Releasing TokenStats

Releases are fully automated by `.github/workflows/release-tokenstats.yml`.

## Flow

1. You merge commits to `main` that touch `apps/TokenStats/**`, using
   [Conventional Commits](https://www.conventionalcommits.org/) (`fix:`, `feat:`,
   `feat!:` / `BREAKING CHANGE:`).
2. [semantic-release](https://semantic-release.gitbook.io/) reads the commit
   history and computes the next [SemVer](https://semver.org/) version.
   - `fix:` → patch, `feat:` → minor, breaking → major.
   - No release-worthy commits → nothing happens.
3. `scripts/build-dmg.sh <version>` builds the app at that version, codesigns it
   with **Developer ID Application** (hardened runtime), packages a `.dmg`,
   codesigns the dmg, **notarizes** it with Apple, and staples the ticket.
4. semantic-release creates the git tag `tokenstats-v<version>`, a GitHub
   Release with generated notes, and attaches `dist/TokenStats-<version>.dmg`.

Versioning config lives in `apps/TokenStats/.releaserc.json`. The tag is scoped
(`tokenstats-v*`) so it never collides with other release flows in the monorepo.

> Monorepo note: the commit analyzer looks at all commits since the last
> `tokenstats-v*` tag, but the workflow only *runs* when `apps/TokenStats/**`
> changes — so an unrelated CLI change alone won't cut a TokenStats release.

## Required GitHub Actions secrets

Set these under **Settings → Secrets and variables → Actions**:

| Secret | What it is |
| --- | --- |
| `MACOS_CERT_P12_BASE64` | `base64` of a *Developer ID Application* certificate + private key exported as `.p12` |
| `MACOS_CERT_PASSWORD` | Password protecting that `.p12` |
| `KEYCHAIN_PASSWORD` | Any throwaway password for the temporary CI keychain |
| `NOTARY_KEY_P8_BASE64` | `base64` of an App Store Connect API key (`.p8`) with the *Developer* role |
| `NOTARY_KEY_ID` | The API key's Key ID |
| `NOTARY_ISSUER_ID` | App Store Connect Issuer ID |

Generate the base64 values with, e.g.:

```sh
base64 -i DeveloperIDApp.p12 | pbcopy
base64 -i AuthKey_XXXXXXXXXX.p8 | pbcopy
```

The signing team (`472VSX7V86`) is already set in the Xcode project. Notarization
uses an App Store Connect API key (preferred over an Apple ID + app-specific
password — no 2FA prompts, easily revocable).

## Testing the build locally

You can dry-run the packaging step without semantic-release, provided your login
keychain holds a Developer ID Application identity and you export the notary env
vars:

```sh
cd apps/TokenStats
NOTARY_KEY_PATH=~/AuthKey.p8 NOTARY_KEY_ID=XXX NOTARY_ISSUER_ID=YYY \
  ./scripts/build-dmg.sh 0.0.1
```
