-- Migration 1: trigram search for the directory and the job scheduler for the weekly search summary.
-- pg_cron 1.5+ must live in pg_catalog; it creates the cron schema itself.
create extension if not exists pg_trgm with schema extensions;
create extension if not exists pg_cron with schema pg_catalog;
;
