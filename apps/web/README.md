# Presently Marketing Site

The static Astro site for Presently. It is hosted by Wisp at
`https://presently.photo`.

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

The `Deploy Marketing Site to Wisp` workflow builds and deploys changes to
`apps/web` after they reach `main`. Configure its `production` environment with:

- Variable `WISP_HANDLE`: the AT Protocol handle that owns the Wisp site.
- Variable `WISP_SITE_NAME`: the Wisp site rkey. It defaults to `presently`.
- Variable `PRESENTLY_SITE_URL`: the canonical public origin. It defaults to
  `https://presently.photo`.
- Secret `WISP_APP_PASSWORD`: an app password for the deploying AT Protocol
  account.

For a manual deployment:

```sh
npm run check
npm run build
wispctl deploy samclemente.me --path dist --site presently
```

The authoritative DNS zone is managed in Marque. The apex is mapped to Wisp;
`oauth.presently.photo` is mapped to the Railway OAuth service.
