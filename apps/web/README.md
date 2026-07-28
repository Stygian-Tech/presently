# Presently Marketing Site

The static Astro site for Presently. It builds to `dist/` and is served by the
repository's root Vercel container alongside the OAuth metadata service.

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

The `presently` Vercel project deploys pushes to `main`. Its root
`Dockerfile.vercel` runs the site checks and build before copying `dist/` into
the final container. `PUBLIC_SITE_URL` defaults to `https://presently.photo` and
can be supplied as a container build argument when a different canonical origin
is required.
