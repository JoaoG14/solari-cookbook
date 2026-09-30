-- Better Auth 1.7.3 no longer writes the issuer added by 1.7.0–1.7.2.
-- Preserve existing accounts and issuer values while allowing new accounts.
-- https://www.better-auth.com/docs/guides/1-7-upgrade-guide
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = current_schema()
      AND table_name = 'account'
      AND column_name = 'issuer'
  ) THEN
    ALTER TABLE account ALTER COLUMN issuer DROP NOT NULL;
    DROP INDEX IF EXISTS "account_issuer_accountId_uidx";
  END IF;
END $$;
