# Getting the app onto your iPhone (no Mac required)

Everything below happens in a web browser plus the TestFlight app on your
iPhone. The heavy lifting — compiling, signing, uploading — runs on a cloud
Mac via GitHub Actions.

## One-time setup (~15 minutes)

### 1. Register the bundle ID

1. Go to [developer.apple.com/account](https://developer.apple.com/account) →
   **Certificates, IDs & Profiles** → **Identifiers** → **+**.
2. Choose **App IDs** → **App**.
3. Description: `Cribbage`. Bundle ID (explicit): `com.cyfarian.cribbage`
   (or any reverse-DNS name you like — just use the same value everywhere).
4. No capabilities needed. Register.

### 2. Create the app record

1. Go to [App Store Connect](https://appstoreconnect.apple.com) →
   **My Apps** → **+** → **New App**.
2. Platform **iOS**, pick the bundle ID from step 1.
3. Name: `Cribbage Score` (app names are globally unique — if taken, try
   `Cribbage Scorekeeper`, `Peg & Count`, etc. This is only the store
   listing name; you can change it before ever publishing).
4. SKU: anything, e.g. `cribbage-001`.

### 3. Create an App Store Connect API key

1. App Store Connect → **Users and Access** → **Integrations** →
   **App Store Connect API** → **Team Keys** → **+**.
2. Name: `GitHub CI`. Role: **Admin** (needed the first run so the build can
   create a signing certificate automatically; you can downgrade the key to
   App Manager afterwards).
3. **Download the `.p8` file immediately** — it can only be downloaded once.
4. Note the **Key ID** (10 characters) and the **Issuer ID** (UUID shown at
   the top of the page).

### 4. Find your Team ID

[developer.apple.com/account](https://developer.apple.com/account) →
**Membership details** → **Team ID** (10 characters).

### 5. Add GitHub secrets

In this repo: **Settings → Secrets and variables → Actions → New repository
secret**, add all five:

| Secret name     | Value                                        |
|-----------------|----------------------------------------------|
| `ASC_KEY_ID`    | Key ID from step 3                           |
| `ASC_ISSUER_ID` | Issuer ID from step 3                        |
| `ASC_KEY_P8`    | The entire text contents of the `.p8` file (open it in a text editor, copy everything including the BEGIN/END lines) |
| `APPLE_TEAM_ID` | Team ID from step 4                          |
| `BUNDLE_ID`     | Bundle ID from step 1, e.g. `com.cyfarian.cribbage` |

## Building and installing

1. Repo **Actions** tab → **TestFlight** workflow → **Run workflow** on the
   main branch. (Pushing a tag like `v0.1.0` also triggers it.)
2. Wait ~10–15 minutes. When green, the build appears in App Store Connect →
   your app → **TestFlight** (it may say "Processing" for a few minutes).
3. On the TestFlight page, add yourself under **Internal Testing**: create a
   group, add your own Apple account as a tester. Internal builds need no
   review.
4. Install the **TestFlight** app on your iPhone, sign in, and install
   Cribbage Score. Done.

TestFlight builds last 90 days; re-run the workflow any time for a fresh
build (each run auto-increments the build number). When you're ready for the
App Store, the same upload is submittable from App Store Connect.

## Troubleshooting

- **"No signing certificate" / cert creation error**: the API key's role is
  too low — recreate it with **Admin** (step 3).
- **Upload rejected, name taken**: change the app name in App Store Connect
  (doesn't affect the build).
- **Build stuck "Processing"**: normal, up to ~15 minutes.
- **macOS runner minutes**: on a private repo, macOS Actions minutes bill at
  10× (≈200 real minutes/month free). The TestFlight workflow only runs when
  you trigger it; the Linux test workflow is effectively free. Making the
  repo public makes all Actions minutes free.
