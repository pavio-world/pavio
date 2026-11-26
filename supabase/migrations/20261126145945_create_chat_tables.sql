-- Migration 22: chat tables (stretch): conversations, conversation_members, messages,
-- message_translations and public.in_conversation. The tables stay empty until the chat spec adds
-- the RPCs that create conversations, add members and write translations (Req 19.8).
-- Spec 00 Req 5.8, 19.4 to 19.8, 22.1 to 22.3; design "conversations, conversation_members,
-- messages, message_translations (stretch)", "Stretch helpers", "Row Level Security policies".

-- ---------------------------------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------------------------------

create table public.conversations (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.conversation_members (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.conversations (id) on delete cascade,
  profile_id uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  constraint conversation_members_conversation_profile_key unique (conversation_id, profile_id)
);

-- conversation_id leads the unique key; profile_id gets its own index.
create index conversation_members_profile_id_idx on public.conversation_members (profile_id);

create table public.messages (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.conversations (id) on delete cascade,
  -- A deleted profile leaves its messages behind, with no sender (Req 5.8).
  sender_profile_id uuid references public.profiles (id) on delete set null,
  body text not null,
  language_code text not null references public.languages (code),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint messages_body_length check (char_length(body) between 1 and 4000)
);

-- Every foreign key has an index; conversation_id leads the listing index.
create index messages_conversation_id_created_at_idx on public.messages (conversation_id, created_at);
create index messages_sender_profile_id_idx on public.messages (sender_profile_id);
create index messages_language_code_idx on public.messages (language_code);

create table public.message_translations (
  id uuid primary key default gen_random_uuid(),
  message_id uuid not null references public.messages (id) on delete cascade,
  language_code text not null references public.languages (code),
  body text not null,
  created_at timestamptz not null default now(),
  -- One translation per message and language (Req 19.6); message_id leads the key.
  constraint message_translations_message_language_key unique (message_id, language_code)
);

create index message_translations_language_code_idx on public.message_translations (language_code);

create trigger conversations_set_updated_at
  before update on public.conversations
  for each row execute function private.set_updated_at();

create trigger messages_set_updated_at
  before update on public.messages
  for each row execute function private.set_updated_at();

-- ---------------------------------------------------------------------------------------------
-- public.in_conversation: true when any profile the signed in login controls is a member.
-- Signed in only (function execute grants table, DR-4).
-- ---------------------------------------------------------------------------------------------

create or replace function public.in_conversation(p_conversation uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.conversation_members cm
    where cm.conversation_id = p_conversation
      and cm.profile_id in (select public.my_profile_ids())
  );
$$;
revoke execute on function public.in_conversation(uuid) from public;
revoke execute on function public.in_conversation(uuid) from anon;
grant execute on function public.in_conversation(uuid) to authenticated;

-- ---------------------------------------------------------------------------------------------
-- Row Level Security and grants (Req 19.4, 19.5, 19.7, 22.1 to 22.3). anon has nothing.
-- There is no insert, update or delete grant on conversations, conversation_members or
-- message_translations, so the only write path today is a message from a member (Req 19.8).
-- ---------------------------------------------------------------------------------------------

alter table public.conversations enable row level security;
revoke all on table public.conversations from anon, authenticated;
grant select on table public.conversations to authenticated;

create policy conversations_authenticated_select on public.conversations
  for select to authenticated
  using (public.in_conversation(id));

alter table public.conversation_members enable row level security;
revoke all on table public.conversation_members from anon, authenticated;
grant select on table public.conversation_members to authenticated;

create policy conversation_members_authenticated_select on public.conversation_members
  for select to authenticated
  using (public.in_conversation(conversation_id));

alter table public.messages enable row level security;
revoke all on table public.messages from anon, authenticated;
grant select on table public.messages to authenticated;
grant insert (conversation_id, sender_profile_id, body, language_code)
  on table public.messages to authenticated;

create policy messages_authenticated_select on public.messages
  for select to authenticated
  using (public.in_conversation(conversation_id));

-- The sender must be a profile the login acts as, and a member of the conversation (Req 19.5).
create policy messages_authenticated_insert on public.messages
  for insert to authenticated
  with check (
    public.acts_as(sender_profile_id)
    and exists (
      select 1 from public.conversation_members cm
      where cm.conversation_id = messages.conversation_id
        and cm.profile_id = messages.sender_profile_id
    )
  );

alter table public.message_translations enable row level security;
revoke all on table public.message_translations from anon, authenticated;
grant select on table public.message_translations to authenticated;

create policy message_translations_authenticated_select on public.message_translations
  for select to authenticated
  using (exists (
    select 1 from public.messages m
    where m.id = message_translations.message_id
      and public.in_conversation(m.conversation_id)
  ));
;
