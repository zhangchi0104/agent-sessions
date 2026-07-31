# Releasing TokenStats

Releases are fully automated by `.github/workflows/release-tokenstats.yml`.

## Channels

| Branch | Channel | Example version | GitHub Release |
| --- | --- | --- | --- |
| `dev`  | beta   | `1.2.0-beta.1`  | marked **pre-release** |
| `main` | stable | `1.2.0`         | normal release |

Land work on `dev` to ship a beta `.dmg`; merging `dev` → `main` promotes the
same changes to a stable release. Beta numbers increment per push to `dev`
(`-beta.1`, `-beta.2`, …) and collapse to the clean version on `main`.

## Flow

1. You push/merge commits that touch `apps/TokenStats/**` to `dev` or `main`,
   using [Conventional Commits](https://www.conventionalcommits.org/) (`fix:`,
   `feat:`, `feat!:` / `BREAKING CHANGE:`).
2. [semantic-release](https://semantic-release.gitbook.io/) reads the commit
   history and computes the next [SemVer](https://semver.org/) version for that
   branch's channel.
   - `fix:` → patch, `feat:` → minor, breaking → major.
   - On `dev` the result carries a `-beta.N` suffix.
   - No release-worthy commits → nothing happens.
3. The workflow runs on the `macos-26` image and explicitly selects Xcode 26.6.
   `scripts/build-dmg.sh <version>` builds the app unsigned with any local
   development Team/profile cleared, rejects artifacts whose `DTXcode` metadata
   is older than `2660`, then codesigns with **Developer ID Application**
   (hardened runtime), packages a `.dmg`, codesigns the dmg, **notarizes** it
   with Apple, and staples the ticket.
4. semantic-release creates the git tag `tokenstats-v<version>`, a GitHub
   Release with generated notes, and attaches `dist/TokenStats-<version>.dmg`.

Versioning config lives in `apps/TokenStats/.releaserc.json`. The tag is scoped
(`tokenstats-v*`) so it never collides with other release flows in the monorepo.

> Monorepo note: the commit analyzer looks at all commits since the last
> `tokenstats-v*` tag, but the workflow only *runs* when `apps/TokenStats/**`
> changes — so an unrelated CLI change alone won't cut a TokenStats release.

## Required GitHub Actions secrets

Set these under **Settings → Secrets and variables → Actions**:

| Secret | What it is | Where it comes from |
| --- | --- | --- |
| `MACOS_CERT_P12_BASE64` | `base64` of a *Developer ID Application* certificate + private key exported as `.p12` | Apple Developer account (see below) |
| `MACOS_CERT_PASSWORD` | Password protecting that `.p12` | You choose it at export time |
| `KEYCHAIN_PASSWORD` | Any throwaway password for the temporary CI keychain | Random string you generate |
| `NOTARY_KEY_P8_BASE64` | `base64` of an App Store Connect API key (`.p8`) with the *Developer* role | App Store Connect (see below) |
| `NOTARY_KEY_ID` | The API key's Key ID | Shown next to the key in App Store Connect |
| `NOTARY_ISSUER_ID` | App Store Connect Issuer ID | Shown above the key list (one UUID per team) |

`GITHUB_TOKEN` is injected by Actions automatically — don't add it.

### Signing certificate (`MACOS_CERT_*`)

Requires Account Holder or Admin on the release signing team. The team is
determined by the Developer ID certificate imported into CI; the shared Xcode
project intentionally contains no development Team ID.

1. Xcode → Settings → Accounts → select the team → Manage Certificates → `+` →
   **Developer ID Application**. (Or issue it manually from a CSR at
   <https://developer.apple.com/account/resources/certificates>.)
2. Keychain Access → *My Certificates* → right-click
   `Developer ID Application: …` → **Export**, save as `.p12` and
   set a password — that password is `MACOS_CERT_PASSWORD`. Export the
   certificate row (which carries the private key with it), not the bare private
   key: without the key, `security import` succeeds in CI but codesign finds no
   usable identity.
3. Encode it:

   ```sh
   base64 -i DeveloperIDApp.p12 | pbcopy
   ```

Developer ID certificates expire after 5 years; re-export and update the secret
when that happens.

### Notarization key (`NOTARY_*`)

Notarization uses an App Store Connect API key rather than an Apple ID +
app-specific password — no 2FA prompts, and it can be revoked on its own.

1. <https://appstoreconnect.apple.com/access/integrations/api> → **Team Keys** →
   `+` → role **Developer** (sufficient for notarization).
2. Download the `.p8` — it is only downloadable **once**. The same page shows the
   **Key ID** (`NOTARY_KEY_ID`) and, above the list, the **Issuer ID**
   (`NOTARY_ISSUER_ID`).
3. Encode it:

   ```sh
   base64 -i AuthKey_XXXXXXXXXX.p8 | pbcopy
   ```

### CI keychain password (`KEYCHAIN_PASSWORD`)

Nothing to do with Apple — it only unlocks the throwaway keychain the workflow
creates and deletes in the same run. Any random string works:

```sh
openssl rand -base64 24 | pbcopy
```

## Testing the build locally

The fast release-toolchain regression check is part of `npm test` and can also
be run on its own:

```sh
cd apps/TokenStats
npm run test:release-toolchain
```

You can dry-run the packaging step without semantic-release, provided your login
keychain holds a Developer ID Application identity and you export the notary env
vars. `Config/Signing.local.xcconfig` is only for local development and is
explicitly excluded from the unsigned release build:

```sh
cd apps/TokenStats
NOTARY_KEY_PATH=~/AuthKey.p8 NOTARY_KEY_ID=XXX NOTARY_ISSUER_ID=YYY \
  ./scripts/build-dmg.sh 0.0.1
```
