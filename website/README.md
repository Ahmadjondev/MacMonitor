# Mac Monitor website

Source of [macmonitor-app.pages.dev](https://macmonitor-app.pages.dev), the project's landing page.

It's a single static page: plain HTML, CSS and a little vanilla JavaScript. No build step, no framework, no tracking.

## Run locally

```bash
cd website
python3 -m http.server 8000
# open http://localhost:8000
```

## Deploy

Hosted on Cloudflare Pages. Upload the contents of this folder as a new deployment, or:

```bash
npx wrangler pages deploy website --project-name=macmonitor-app
```

## Notes

- The menu bar at the top of the page is a live demo. Its numbers are simulated, not real readings.
- Animations respect `prefers-reduced-motion`.
- Screenshots in `img/` are WebP copies of the ones in `../assets/`.
