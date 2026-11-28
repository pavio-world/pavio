# Demo seed

Fills the hosted `pavio` Supabase project with an invented demo cast. Every name is made up.

## Run it

Needs `NEXT_PUBLIC_SUPABASE_URL`, `SUPABASE_SECRET_KEY` and `SUPABASE_DB_URL` in `.env.local`. The script stops before writing if either URL does not point at the Pavio project.

```
npm run seed          # write the cast; safe to run again
npm run seed:verify   # run the seed twice and fail unless both fingerprints match
```

## What it creates

- Five demo logins (`<name>@demo.pavio.world`): Amina, Brian, Zawadi, Otieno, Wanjiru.
- Seven profiles: those five people plus two businesses, Kahawa Corner and Shamba Fresh Supplies, with business details and managers.
- Ten relationships (connections and follows), four circles, eleven content items (including one expired story) and seven vouches (including one hidden by its subject).

All rows have fixed ids, so a second run changes nothing. Story times are refreshed on every run, so they are left out of the fingerprint.

## Rules

This folder is one of the two places allowed to use the secret key (see `privacy.md`). The seed only touches the cast and never other profiles or users.
