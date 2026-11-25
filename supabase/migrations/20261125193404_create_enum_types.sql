-- Migration 3: the enumerated types used by every later table.
-- Spec 00 Req 3.10, 4.9, 8.1, 11.2, 11.3, 15.2; design "Enumerated types".
-- vouch is not a content type: vouches have their own table (Req 11.2).
create type public.profile_type as enum ('person', 'business');
create type public.manager_role as enum ('owner', 'manager');
create type public.relationship_type as enum ('connection', 'follow');
create type public.relationship_status as enum ('pending', 'accepted', 'declined');
create type public.audience as enum ('public', 'connections', 'circles', 'group');
create type public.content_type as enum ('writing', 'gallery', 'status', 'story');
create type public.notification_type as enum (
  'connection_request',
  'connection_accepted',
  'new_follower',
  'vouch_received',
  'profile_viewed',
  'weekly_search_appearances'
);
create type public.dot_colour as enum ('terracotta', 'cherry', 'mustard', 'jade', 'lagoon', 'violet');
create type public.story_label_kind as enum ('member_label', 'only_for_you', 'shared_with_you');
;
