# Historical Postgres auth migrations

The API now targets Cloudflare D1. These scripts apply only to Dony's old Postgres
source database and are retained with its migration tests. This cookbook copy
initializes its local D1 schema when the API starts. See the
[application README](../../../README.md) for local database setup.

Better Auth's startup migrator does not remove obsolete required columns.
Apply these SQL files separately when upgrading an existing database, before
starting the new API version.

## Better Auth 1.7.3

Databases previously used with 1.7.0–1.7.2 can have a required `account.issuer`
column. Version 1.7.3 no longer writes it, causing `SCHEMA_MISMATCH` errors.

Follow the [Better Auth upgrade guide](https://www.better-auth.com/docs/guides/1-7-upgrade-guide):
check for duplicate `(providerId, accountId)` pairs, then run
`20260907_relax_account_issuer.sql` against the API database. It preserves account
rows and issuer values, makes the column nullable, and removes the obsolete
issuer index. It is safe to rerun and also works on fresh databases.

Restart the API afterward to clear Better Auth's cached schema check. Verify
`/api/auth/get-session` returns 200 and `/v1/auth/desktop/google` with
`callbackUrl=dony%3A%2F%2Fauth%2Fcallback` redirects to Google with a state cookie.

The historical migration is not needed for a fresh cookbook database.
