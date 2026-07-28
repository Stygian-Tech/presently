# Presently Marketing Site

The static Astro site for Presently. It builds to `dist/` and is deployable to
wisp.place.

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

## GitHub Deployment

The `Deploy Marketing Site to Wisp` workflow runs on changes to `apps/web` on
`main` and can also be started manually. Configure the `production` GitHub
environment with:

- Variable `WISP_HANDLE`: the AT Protocol handle that owns the Wisp site.
- Variable `WISP_SITE_NAME`: the Wisp site rkey. It defaults to `presently`.
- Variable `PRESENTLY_SITE_URL`: the final public origin used for canonical
  links, such as a mapped custom domain or Wisp URL.
- Secret `WISP_APP_PASSWORD`: an app password created for the deploying AT
  Protocol account.

The workflow builds `apps/web/dist` and deploys it with `wispctl@1.1.0`.
