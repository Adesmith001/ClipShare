# ClipShare privacy page

Static privacy policy for the direct-link store beta. No JavaScript, external fonts, dependencies, or build step.

## Deploy from GitHub to Vercel

1. Commit and push `privacy-site/` to `Adesmith001/ClipShare`.
2. In Vercel, add a new project and import that repository.
3. Set **Root Directory** to `privacy-site` and **Framework Preset** to **Other**.
4. Leave Build Command and Install Command empty (override detected commands if necessary). Use `.` as the Output Directory.
5. Deploy. Ensure the production deployment is public and does not require Vercel authentication.
6. Open the production URL in a private browser window. The policy is served at `/`, `/privacy`, and `/privacy-policy`.
7. Paste your production URL followed by `/privacy` into Play Console's Privacy Policy field and the App Store privacy-policy field.

Add a link to that same production URL inside the mobile app before submitting the next store build. The deployed domain is not known until you create the Vercel project; do not put an invented domain into the app.

## Scope and maintenance

The text follows the current `STORE_BETA` direct-media build and the support address already shown in the app. It does not cover the personal build's social resolvers and sign-in features. Update the policy before enabling those features in a store release. Review support-retention and children's-privacy statements against your actual operating practices before publishing. Vercel may process website access logs; consult its current privacy documentation and your project settings for hosting retention controls.
