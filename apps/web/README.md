# Presently Marketing Site

The static Astro site for Presently. Vercel builds it as the `web` service in
the repository's multi-service deployment.

## Develop

```sh
npm install
npm run dev
```

## Verify

```sh
npm run check
npm run build
```

Set `PUBLIC_SITE_URL` while building to generate canonical and social URLs for
the deployed origin.

## Deployment

The `presently` Vercel project deploys pushes to `main`. Its root `vercel.json`
routes `presently.photo` and the project's Vercel aliases to this service while
`oauth.presently.photo` routes to the separate Go container service.

`PUBLIC_SITE_URL` defaults to `https://presently.photo` for canonical and social
URLs.
