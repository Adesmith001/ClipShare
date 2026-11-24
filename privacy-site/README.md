# ClipShare website

Static landing page and privacy policy. No build step or dependencies. Self-hosted photos are illustrative media from Unsplash, not app screenshots or user downloads.

## Deploy from GitHub to Vercel

1. Import `Adesmith001/ClipShare` and select the `codex/store-beta` branch as the production branch.
2. Set **Root Directory** to `privacy-site`, **Framework Preset** to **Other**, and **Output Directory** to `.`.
3. Leave Build Command and Install Command empty. Deploy publicly without authentication protection on production.
4. The landing page is at `/`. The privacy policy is at `/privacy` (with `/privacy-policy` as an alias).
5. Use `https://YOUR-PRODUCTION-DOMAIN/privacy` in Play Console and App Store Connect, and add the same link inside the mobile app before submission.

The contact button opens an email requesting beta access. It does not register testers or collect emails. Replace it with verified store links once public distribution is active. The library filters and FAQ are working browser interactions; the phone is an illustrative preview, not a live app.

## Local preview

Run `python -m http.server 8765 --directory privacy-site` from the repository root, then open `http://localhost:8765`. Python serves the physical `/privacy/` page; Vercel additionally handles the configured `/privacy-policy` alias and response security headers.

## Policy scope

The policy describes social resolution in 0.2.2+11 and the direct-media-only behavior of earlier store builds. It includes TikWM requests and optional iOS Instagram sign-in. Review support retention and children's privacy statements against actual operating practices before publishing.

## Image credits

Illustrative landscape photos: Unsplash image IDs `photo-1470770841072-f978cf4d019e`, `photo-1464822759023-fed622ff2c3b`, and `photo-1441974231531-c6227db76b6e`. Files are served locally without visitor requests to Unsplash. App icon: existing ClipShare project asset.
