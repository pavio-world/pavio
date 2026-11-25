# Requirements Document

## Introduction

Spec 00 builds Pavio database first. It designs and creates the complete Supabase Postgres schema for every Pavio feature, including features built in later specs and stretch features, so that later specs add only logic and user interface. It also builds the privacy engine (`acts_as`, `can_view`, `view_as`, and the story label function), enables Row Level Security with explicit policies on every table, creates the storage buckets and their policies, builds public directory search, proves the privacy rules with pgTAP tests and fast-check property based tests, and seeds believable demo data with invented names.

This spec builds no user interface. The Next.js app is scaffolded in Spec 01; this spec adds only the minimal Node tooling needed for property based tests (Vitest, fast-check and a Postgres client).

All work targets the hosted Supabase project named `pavio` (ref `tmglpalznmyonaynojyy`), which is already linked to this repository. There is no local database. The future production project `pavio-prod` is out of scope and is never targeted.

Sources of truth: `.kiro/steering/product.md` and `.kiro/steering/privacy.md`, followed by `tech.md`, `supabase.md`, `testing.md`, `structure.md` and `git.md`. The original request is `docs/kiro-prompts/00-database-foundation.md`.

Dominic's answers to both rounds of open questions (OQ and NQ) are recorded in **Resolved Decisions** at the end, and every criterion below states the decided behaviour. There are no open questions.

## Glossary

- **Database**: the Supabase Postgres database of the hosted `pavio` project.
- **Pavio_Project**: the hosted Supabase project named `pavio`, ref `tmglpalznmyonaynojyy`, linked to this repository.
- **Migration**: a timestamped SQL file in `supabase/migrations/` that is applied to the Database and committed to git.
- **Migration_Workflow**: the five step process in `supabase.md`: apply with the Supabase MCP `apply_migration` tool, fetch with `supabase migration fetch --yes`, run security and performance advisors, regenerate types to `src/lib/supabase/types.ts`, commit.
- **Advisors**: the Supabase security and performance advisor checks, run through the MCP `get_advisors` tool.
- **Auth_User**: a row in `auth.users`, representing one login.
- **Signed_In_User**: a request made with a valid Supabase session; `auth.uid()` returns the Auth_User id.
- **Anonymous_Visitor**: a request made with the `anon` role and no session.
- **Nairobi_Day**: a calendar date in the `Africa/Nairobi` time zone, used for every daily bucket in the Database.
- **Profile**: a row in the `profiles` table. Every action in Pavio is performed as a Profile.
- **Person_Profile**: a Profile of type `person`.
- **Business_Profile**: a Profile of type `business`.
- **Business_Details**: the row in `business_details` holding the extra details of one Business_Profile.
- **Profile_Manager_Role**: the role an Auth_User holds on a Business_Profile, either `owner` or `manager`.
- **Acting_Profile**: the Profile on whose behalf a write or read is performed.
- **Handle**: the unique public identifier of a Profile, used in the page address `pavio.world/<handle>`.
- **Reserved_Handle_List**: the table of words that may not be used as a Handle.
- **What_I_Do_Tags**: the list of short text tags on a Profile describing what the Profile does; they drive search.
- **Dot_Colour_Key**: one of the six keys of the dot palette in `design-system.md`: `terracotta`, `cherry`, `mustard`, `jade`, `lagoon`, `violet`.
- **Relationship**: a row in the `relationships` table, with a type (`connection` or `follow`) and a status.
- **Connection**: a Relationship of type `connection` between two Person_Profiles or between two Business_Profiles, which becomes mutual when accepted.
- **Follow**: a Relationship of type `follow` from a Person_Profile to a Business_Profile, active immediately.
- **Accepted_Connection**: a Connection with status `accepted`.
- **Declined_Connection**: a Connection with status `declined`.
- **Follower**: a Person_Profile with an active Follow to a given Business_Profile.
- **Relationship_Counts_Function**: the security definer function that returns the number of Accepted_Connections and Followers of a Profile, with no Profile ids.
- **Circle**: a private group of Profiles owned by one Profile and used as an Audience.
- **Circle_Owner**: the Profile that owns a Circle. Every Auth_User for whom acts_as is true on the Circle_Owner acts for the Circle_Owner.
- **Circle_Private_Name**: the name of a Circle that only the Circle_Owner ever sees.
- **Member_Label_Switch**: the per Circle setting "Show a label to people in this circle", off by default.
- **Member_Label**: the optional text a Circle_Owner chooses to show to Circle_Members on Stories while the Member_Label_Switch is on.
- **Circle_Member**: a Profile placed in a Circle by the Circle_Owner.
- **Circle_Label_Order**: the fixed order of Circles used to pick one Member_Label: ascending `created_at`, then ascending id.
- **All_Followers_Audience**: the built in Circle of every Business_Profile that contains exactly its current Followers, maintained automatically.
- **Content_Item**: a row in the `content_items` table representing one page item: writing, gallery photo, status, story, or (depending on design) vouch.
- **Content_Type**: the type of a Content_Item: `writing`, `gallery`, `status`, `story`, `vouch`, open to more values.
- **Audience**: the setting of a Content_Item or Vouch that decides who may see the item: `public`, `connections`, `circles` or `group`.
- **Item_Circle_Link**: a row linking a Content_Item or Vouch with Audience `circles` to one chosen Circle.
- **Story**: a Content_Item of type `story`, with an `expires_at` 24 hours after creation.
- **Expired_Item**: a Content_Item whose `expires_at` is in the past.
- **Story_View**: a record that one Profile has seen one Story.
- **Story_Label**: the single label a Viewer sees on a Story with Audience `circles`: a Member_Label, "Only for you" or "Shared with you".
- **Story_Label_Function**: the security definer SQL function that computes the Story_Label for one Story and one Viewer.
- **Status**: a Content_Item of type `status` holding a short line such as "on leave", kept until changed.
- **Vouch**: a statement written by one Profile (the Vouch_Author) about another Profile (the Vouch_Subject). Every Vouch is kept until the Vouch_Author deletes it.
- **Vouch_Author**: the Profile that wrote a Vouch. The Vouch_Author sets the Audience, may edit or delete the Vouch, and may feature the Vouch in the Vouch_Author's Top_8.
- **Vouch_Subject**: the Profile a Vouch is about. The Vouch_Subject may hide the Vouch from the Vouch_Subject's own page and may not edit or delete the Vouch.
- **Featured_Vouch**: a Vouch the Vouch_Author has placed in the Vouch_Author's Top_8, with a position from 1 to 8.
- **Top_8**: the ordered set of at most 8 Featured_Vouches a Vouch_Author has written, shown on the Vouch_Author's own page.
- **Received_Vouches**: the Vouches about a Vouch_Subject, shown on the Vouch_Subject's page as endorsements.
- **Hidden_Vouch**: a Vouch whose `hidden_by_subject` flag the Vouch_Subject has set to true.
- **Search_Trust**: for one Profile, the number of distinct Vouch_Authors whose Top_8 contains a Vouch about that Profile with Audience `public`.
- **Owner**: the Profile an item belongs to for visibility. For a Content_Item, the Owner is the Profile that created it. For a Vouch, the Owner is the Vouch_Author.
- **Viewer**: the Profile from whose point of view visibility is decided, or no Profile for an Anonymous_Visitor.
- **Stranger**: a Viewer with a Profile that is not the Owner, not an Accepted_Connection of the Owner, not a Follower of the Owner and not a Circle_Member of any of the Owner's Circles.
- **Notification**: a row in the `notifications` table addressed to one Profile.
- **Profile_View**: a record that a signed in Viewer opened a Profile page.
- **Search_Appearance**: a daily count of how many times a Profile was returned by the Search_Function.
- **AI_Usage**: a record of AI calls and cost per Auth_User per Nairobi_Day.
- **Spend_Cap_Setting**: the global monthly AI spend cap stored in the Database.
- **Lastfm_Link**: the Last.fm username connected to a Profile.
- **Public_Bucket**: the Supabase Storage bucket whose objects anyone may read.
- **Private_Bucket**: the Supabase Storage bucket whose objects are read through signed URLs only when can_view allows.
- **Group**, **Group_Member**: stretch tables for groups of Profiles, created in this spec and left unused.
- **Conversation**, **Conversation_Member**, **Message**, **Message_Translation**: stretch tables for chat with translation, created in this spec and left unused.
- **acts_as**: the SQL function `acts_as(profile_id)` that returns true only if the Signed_In_User owns or manages that Profile.
- **can_view**: the SQL function `can_view(item_id, viewer_profile_id)`, the only place Content_Item and Vouch visibility is decided.
- **view_as**: the security definer SQL function `view_as(owner_profile_id, simulated_viewer)` that lists the items on the Owner's page as a simulated Viewer would see them.
- **Search_Function**: the SQL function that performs public directory search over Profiles.
- **RLS**: Postgres Row Level Security.
- **pgTAP_Suite**: the pgTAP tests in `supabase/tests/*.test.sql`, run with `supabase test db --linked`.
- **Property_Suite**: the Vitest plus fast-check tests in `tests/property/`, run with `npm run test:property` against the Database through `SUPABASE_DB_URL`.
- **Seed_Script**: the code and data in `supabase/seed/` that creates demo accounts and sample data.
- **Secret_Key**: the Supabase secret (service role) key, which bypasses RLS.
- **Admin_Client**: the Supabase client in `src/lib/supabase/admin.ts`, created with the Secret_Key and running as the `service_role` role; one of the two places allowed to use the Secret_Key (created in a later spec).
- **AI_Route**: the Next.js route handler in a later spec that calls the AI provider through `src/lib/ai/`.
- **Trusted_Caller**: a database session running as `postgres` or `service_role`, which bypasses RLS or the acting rules.
- **API_Caller**: a database session whose JWT role is `anon` or `authenticated`, as reported by `private.is_api_caller()`.
- **Simulated_User_Switch**: the Property_Suite helper `asUser` that switches a transaction to a simulated user with `set local role` and `set local request.jwt.claims`.
- **Canary_Check**: the assertions made immediately after a Simulated_User_Switch that the session really runs as the simulated user and not as a Trusted_Caller.
- **Property_Runs**: the number of cases each property runs, read from the `PROPERTY_RUNS` environment variable.
- **Decision_Record**: a file `docs/decisions/NNN-title.md` with context, decision and consequences.
- **Spec_Branch**: the git branch `spec/00-database-foundation`.

## Requirements

### Area: Setup and tooling

### Requirement 1: Supabase project setup

**User Story:** As Dominic, I want the repository's Supabase folder verified and linked to the `pavio` project, so that every migration and test runs against the right database.

#### Acceptance Criteria

1. THE Pavio_Project SHALL be the project recorded in `supabase/.temp/project-ref`, with ref `tmglpalznmyonaynojyy`.
2. WHEN the setup task starts, THE setup task SHALL verify that `supabase/config.toml` exists and that the repository is linked to the Pavio_Project, and SHALL run `supabase init` or `supabase link` only for the part that is missing.
3. THE Database SHALL have the `pgtap` extension installed in the `extensions` schema, as recorded by the existing Migration `20261125040502_enable_pgtap.sql`.
4. IF any command or configuration in this spec refers to a project other than the Pavio_Project, THEN THE setup task SHALL stop and ask Dominic before running the command.
5. THE spec documents, scripts and configuration SHALL refer to the hosted project only by the name `pavio`.
6. THE Database SHALL have the `pg_trgm` and `pg_cron` extensions enabled through a Migration.

### Requirement 2: Minimal Node tooling for property tests

**User Story:** As Dominic, I want only the Node tooling needed to run property tests, so that Spec 01 can scaffold the Next.js app cleanly.

#### Acceptance Criteria

1. THE repository SHALL contain a `package.json` whose dependencies are limited to Vitest, fast-check, one Postgres client library, TypeScript, a dotenv loader if required to read `.env.local`, the Supabase JS client for the Seed_Script, and their type packages.
2. THE `package.json` SHALL define a `test:property` script that runs the Property_Suite once without watch mode.
3. THE repository SHALL contain a strict TypeScript configuration (`"strict": true`) that covers `tests/property/`.
4. THE Property_Suite SHALL read the database connection string only from the `SUPABASE_DB_URL` variable in `.env.local`.
5. IF `SUPABASE_DB_URL` is missing, THEN THE Property_Suite SHALL fail with a message that names the missing variable.
6. THE `.gitignore` SHALL exclude `node_modules/`, coverage output and test logs.
7. THE setup task SHALL leave `.env.local` and `.env.example` unedited.

### Area: Migration workflow

### Requirement 3: Migrations applied through the Migration_Workflow

**User Story:** As Dominic, I want every schema change applied and recorded the same way, so that git and the hosted database never drift apart.

#### Acceptance Criteria

1. THE Database schema SHALL be created only through Migrations committed in `supabase/migrations/`.
2. WHEN a Migration is applied with `apply_migration`, THE developer SHALL run `supabase migration fetch --yes` so that the local file has the same version as the remote Migration.
3. WHEN a Migration is applied, THE developer SHALL run the Advisors for security and performance and SHALL resolve every security warning before the next Migration is applied.
4. WHEN a Migration is applied, THE developer SHALL regenerate TypeScript types to `src/lib/supabase/types.ts`.
5. THE Migration that creates a table SHALL, in the same file, enable RLS on the table and create the policies for the table.
6. IF a Migration has already been applied to the Pavio_Project, THEN THE developer SHALL make further changes in a new Migration rather than edit the applied file.
7. THE Migrations SHALL contain no `drop table`, `truncate` or unscoped `delete` statement against existing data unless Dominic has approved the statement in chat.
8. THE tables SHALL use `uuid` primary keys defaulting to `gen_random_uuid()` and a `created_at timestamptz not null default now()` column.
9. WHERE a table has rows that change after creation, THE table SHALL have an `updated_at` column maintained by a trigger.
10. THE Database SHALL use Postgres enums or check constraints for profile type, Profile_Manager_Role, relationship type, relationship status, Audience, Content_Type and notification type.
11. THE Database SHALL have an index on every foreign key column and on every column used by can_view, the Story_Label_Function and the Search_Function.

### Area: Profiles

### Requirement 4: Profiles

**User Story:** As a person on Pavio, I want one page that holds everything about me, so that people can find me and see the right face of me.

#### Acceptance Criteria

1. THE `profiles` table SHALL store for each Profile: id, type (`person` or `business`), Handle, display name, bio, avatar image path, cover image path, city, country, preferred language, Dot_Colour_Key, page theme settings, 2006 mode preference and What_I_Do_Tags.
2. THE Database SHALL enforce that every Handle is unique, compared case insensitively.
3. IF a Handle is not 3 to 30 characters of lowercase letters `a-z`, digits and underscore starting with a letter, THEN THE Database SHALL reject the write.
4. IF a Handle is in the Reserved_Handle_List, THEN THE Database SHALL reject the write.
5. THE Reserved_Handle_List SHALL be stored in a table and SHALL initially contain `api`, `app`, `admin`, `auth`, `login`, `logout`, `signup`, `settings`, `search`, `circles`, `notifications`, `edit`, `help`, `about`, `terms`, `privacy`, `pavio`, `www`, `static`, `_next` and `demo`.
6. THE Database SHALL allow words to be added to the Reserved_Handle_List by a Migration without changing any table structure.
7. THE `profiles` table SHALL restrict preferred language to a set of language codes that initially contains `en` and `sw` and can be extended without changing any table structure.
8. WHEN a Profile is created without a preferred language, THE Database SHALL set the preferred language to `en`.
9. THE `profiles` table SHALL restrict the Dot_Colour_Key of every Profile, Person_Profile and Business_Profile alike, to the six palette keys `terracotta`, `cherry`, `mustard`, `jade`, `lagoon` and `violet`.
10. WHEN a Profile is created without a Dot_Colour_Key, THE Database SHALL set the Dot_Colour_Key to `terracotta`.
11. THE `profiles` table SHALL store page theme settings as `jsonb` that defaults to an empty object.
12. WHEN a Profile is created without a 2006 mode preference, THE Database SHALL set the 2006 mode preference to false.
13. THE `profiles` table SHALL store What_I_Do_Tags as a text array of at most 20 tags, each from 1 to 40 characters, stored in lowercase without leading or trailing spaces.
14. THE `profiles` table SHALL limit display name to 1 to 80 characters and bio to at most 1000 characters.
15. THE profile fields Handle, display name, bio, avatar image path, cover image path, city, country, What_I_Do_Tags, Dot_Colour_Key, page theme settings and profile type SHALL be public data readable by any Viewer, including an Anonymous_Visitor.
16. THE profile fields preferred language, 2006 mode preference and every Profile_Manager_Role SHALL be readable only by Auth_Users for whom acts_as returns true for that Profile.

### Requirement 5: Person profile per login and deletion

**User Story:** As a person signing up, I want exactly one personal page tied to my login, so that my identity on Pavio is clear.

#### Acceptance Criteria

1. THE Database SHALL link every Person_Profile to exactly one Auth_User as its owner.
2. THE Database SHALL allow at most one Person_Profile per Auth_User.
3. WHEN a Signed_In_User without a Person_Profile creates a Person_Profile, THE Database SHALL record the Signed_In_User as its owner.
4. IF a Signed_In_User who already owns a Person_Profile attempts to create a second Person_Profile, THEN THE Database SHALL reject the write.
5. WHEN an Auth_User is deleted, THE Database SHALL delete the Auth_User's Person_Profile.
6. WHEN a Profile is deleted, THE Database SHALL delete the Profile's Relationships, Circles, Circle memberships, Content_Items, Item_Circle_Links, Story_Views, Vouches written and received, Notifications, Profile_Views, Search_Appearances and Lastfm_Link.
7. WHEN the last Auth_User holding Profile_Manager_Role `owner` on a Business_Profile is deleted, THE Database SHALL delete the Business_Profile.
8. WHEN a Profile that sent Messages is deleted, THE Database SHALL keep the Messages and set their sender to null.

### Area: Business details

### Requirement 6: Business profiles and details

**User Story:** As a business owner, I want a business page with my category, contact details and hours, so that customers can find and reach my business.

#### Acceptance Criteria

1. THE `business_details` table SHALL store for each Business_Profile: category, phone, website, opening hours and address.
2. THE Database SHALL allow at most one Business_Details row per Business_Profile.
3. IF a Business_Details row references a Person_Profile, THEN THE Database SHALL reject the write.
4. THE `business_details` table SHALL store opening hours as `jsonb` that holds open and close times per day of the week.
5. IF a website value does not start with `https://` or `http://`, THEN THE Database SHALL reject the write.
6. THE Business_Details fields category, phone, website, opening hours and address SHALL be public data readable by any Viewer, including an Anonymous_Visitor.
7. WHEN a Signed_In_User creates a Business_Profile while acting as the Signed_In_User's own Person_Profile, THE Database SHALL record the Signed_In_User with Profile_Manager_Role `owner` on the new Business_Profile.

### Area: Ownership and acts_as

### Requirement 7: Managing business pages and acts_as

**User Story:** As a person who runs businesses, I want to manage several business pages and act as each of them, so that every action is performed as the right page.

#### Acceptance Criteria

1. THE Database SHALL store Profile_Manager_Roles as rows linking one Auth_User, one Business_Profile and one role of `owner` or `manager`.
2. THE Database SHALL allow one Auth_User to hold Profile_Manager_Roles on any number of Business_Profiles.
3. THE Database SHALL require every Business_Profile to have at least one Auth_User with Profile_Manager_Role `owner`.
4. WHEN acts_as is called with a Profile id, THE acts_as function SHALL return true only if the Signed_In_User owns that Person_Profile or holds a Profile_Manager_Role on that Business_Profile.
5. WHEN acts_as is called by an Anonymous_Visitor, THE acts_as function SHALL return false.
6. WHEN acts_as is called with a Profile id that does not exist, THE acts_as function SHALL return false.
7. THE acts_as function SHALL be a security definer function with `search_path = ''` and fully qualified names.
8. THE RLS policy of every write on a table that holds Profile owned rows SHALL require acts_as to return true for the Acting_Profile recorded on the row.
9. WHEN an Auth_User with Profile_Manager_Role `owner` adds or removes a manager of the Business_Profile, THE Database SHALL accept the change.
10. IF an Auth_User with Profile_Manager_Role `manager` attempts to add, remove or change a Profile_Manager_Role, THEN THE Database SHALL reject the write.
11. IF an Auth_User with Profile_Manager_Role `manager` attempts to delete the Business_Profile, THEN THE Database SHALL reject the write.
12. WHILE an Auth_User holds Profile_Manager_Role `manager` on a Business_Profile, THE Database SHALL accept every other write the Business_Profile's owners may make while acting as the Business_Profile, including editing the Profile, posting Content_Items, managing Circles and answering Connection requests.
13. IF a change would leave a Business_Profile with no Auth_User holding Profile_Manager_Role `owner`, THEN THE Database SHALL reject the change.

### Area: Relationships

### Requirement 8: Relationships

**User Story:** As a person on Pavio, I want to connect with people and follow businesses, so that I build real connections without a feed.

#### Acceptance Criteria

1. THE `relationships` table SHALL store every Connection and Follow, with a requester Profile, a target Profile, a type (`connection` or `follow`) and a status (`pending`, `accepted` or `declined`).
2. WHEN a Person_Profile requests a Connection to another Person_Profile, THE Database SHALL create the Relationship with status `pending`.
3. WHEN a Business_Profile requests a Connection to another Business_Profile, THE Database SHALL create the Relationship with status `pending`.
4. WHEN the target of a pending Connection accepts the request while acting as the target Profile, THE Database SHALL set the status to `accepted`.
5. WHEN the target of a pending Connection declines the request while acting as the target Profile, THE Database SHALL set the status to `declined`.
6. WHEN a Person_Profile follows a Business_Profile, THE Database SHALL create the Follow with status `accepted` immediately.
7. IF a Business_Profile is the requester of a Relationship whose target is a Person_Profile, THEN THE Database SHALL reject the write.
8. IF a Relationship has type `follow` and the requester is not a Person_Profile or the target is not a Business_Profile, THEN THE Database SHALL reject the write.
9. IF a Relationship has type `connection` and the requester and target are not of the same profile type, THEN THE Database SHALL reject the write.
10. IF the requester and target of a Relationship are the same Profile, THEN THE Database SHALL reject the write.
11. IF the Signed_In_User for whom acts_as is true on the requester also owns or manages the target Profile, THEN THE Database SHALL reject the write.
12. THE Database SHALL allow at most one Relationship between the same two Profiles for each type, in either direction.
13. WHEN either Profile in an Accepted_Connection removes the Connection, THE Database SHALL delete the Relationship.
14. WHEN a Follower unfollows a Business_Profile, THE Database SHALL delete the Follow.
15. WHEN a requester withdraws a pending Connection or a Declined_Connection, THE Database SHALL delete the Relationship.
16. IF the requester of a Declined_Connection requests a new Connection to the same target, THEN THE Database SHALL reject the new request.
17. WHEN the target of a Declined_Connection deletes the Declined_Connection, THE Database SHALL accept a later Connection request between the two Profiles.
18. WHEN the target of a Declined_Connection requests a Connection to the original requester, THE Database SHALL replace the Declined_Connection with a pending Connection whose requester is the former target.
19. WHEN the requester of a Declined_Connection reads the Relationship, THE Database SHALL present the status as `pending`.
20. IF a write changes the requester, the target or the type of an existing Relationship, THEN THE Database SHALL reject the write.
21. IF the requester attempts to set the status of a Connection to `accepted` or `declined`, THEN THE Database SHALL reject the write.
22. WHEN a Relationship is deleted, THE Database SHALL remove the other Profile from every Circle of both Profiles in which membership depended on that Relationship.
23. THE Database SHALL make a Relationship readable only by Auth_Users for whom acts_as is true on the requester or the target.
24. THE Relationship_Counts_Function SHALL return, for any Profile and any Viewer including an Anonymous_Visitor, the number of Accepted_Connections and the number of Followers of that Profile, and SHALL return no Profile id, Handle or name.

### Area: Circles

### Requirement 9: Circles, private names and member labels

**User Story:** As a page owner, I want private circles of my connections with names only I see and optional labels I choose to show, so that my page shows a different face to each group without anyone learning what I call them.

#### Acceptance Criteria

1. THE `circles` table SHALL store for each Circle: id, Circle_Owner, a Circle_Private_Name from 1 to 50 characters, a Member_Label_Switch (`show_member_label boolean not null default false`) and an optional Member_Label (`member_label text`) from 1 to 50 characters.
2. THE Database SHALL allow any number of Circles per Profile.
3. THE Database SHALL allow at most one Circle with the same Circle_Private_Name, compared case insensitively, per Circle_Owner.
4. WHEN a Circle is created without a Member_Label_Switch value, THE Database SHALL set the Member_Label_Switch to off.
5. WHEN the Member_Label_Switch of a Circle is turned on and the Circle has no Member_Label, THE Database SHALL set the Member_Label to the current Circle_Private_Name. The pre-fill happens only when the switch turns on (off to on, or a Circle created with it on); a write that clears or blanks the Member_Label while the switch is already on is rejected with `PT422 circle.label_required`, never refilled.
6. IF a write leaves a Circle with the Member_Label_Switch on and no Member_Label, THEN THE Database SHALL reject the write.
7. WHEN the Circle_Owner changes the Circle_Private_Name, THE Database SHALL leave the Member_Label unchanged.
8. WHEN the Member_Label_Switch of a Circle is turned off, THE Database SHALL keep the stored Member_Label so that the Circle_Owner can turn the switch on again with the same text.
9. THE Database SHALL accept writes to the Circle_Private_Name, the Member_Label_Switch and the Member_Label only when acts_as is true on the Circle_Owner.
10. THE Database SHALL return the Circle_Private_Name only to Auth_Users for whom acts_as is true on the Circle_Owner, through every table, view and function.
11. THE Database SHALL return a Member_Label to a Viewer other than the Circle_Owner only through the Story_Label_Function.
12. WHEN the Circle_Owner adds a Profile to a Circle, THE Database SHALL accept the write only if the added Profile is an Accepted_Connection of the Circle_Owner or, for a Business_Profile Circle_Owner, a Follower of the Circle_Owner.
13. IF a Profile that is not an Accepted_Connection or Follower of the Circle_Owner is added to a Circle, THEN THE Database SHALL reject the write.
14. THE Database SHALL allow one Profile to be a Circle_Member of any number of Circles.
15. THE Database SHALL allow at most one membership row for the same Profile in the same Circle.
16. THE Database SHALL make Circles and Circle_Members readable and writable only by Auth_Users for whom acts_as is true on the Circle_Owner.
17. WHEN a Circle_Member reads data while acting as their own Profile, THE Database SHALL return no row that reveals the Circle_Member's membership in another Profile's Circle, other than the Story_Label returned by the Story_Label_Function.
18. WHEN a Circle is deleted, THE Database SHALL delete its Circle_Member rows and its Item_Circle_Links.
19. WHEN a Profile is removed from a Circle, THE Database SHALL remove the Profile's access to items whose only granting Circle was that Circle at the next read, with no caching delay.

### Requirement 10: All followers audience for businesses

**User Story:** As a business owner, I want a built in audience of all my followers, so that I can share with thousands of followers without assigning them by hand.

#### Acceptance Criteria

1. THE Database SHALL provide every Business_Profile with exactly one All_Followers_Audience that can be chosen as a Circle on a Content_Item or Vouch.
2. THE All_Followers_Audience SHALL have the fixed Circle_Private_Name "all followers".
3. THE All_Followers_Audience SHALL contain exactly the current Followers of the Business_Profile at the moment of every read.
4. WHEN a Person_Profile follows a Business_Profile, THE Database SHALL include the Person_Profile in the Business_Profile's All_Followers_Audience.
5. WHEN a Follower unfollows a Business_Profile, THE Database SHALL exclude the Person_Profile from the Business_Profile's All_Followers_Audience.
6. IF a write attempts to add or remove members of an All_Followers_Audience by hand, change the Circle_Private_Name of an All_Followers_Audience, or delete an All_Followers_Audience, THEN THE Database SHALL reject the write.
7. WHEN the Business_Profile owner changes the Member_Label_Switch or the Member_Label of the All_Followers_Audience, THE Database SHALL accept the change under the rules of Requirement 9.
8. IF a write attempts to create an All_Followers_Audience for a Person_Profile, THEN THE Database SHALL reject the write.

### Area: Content

### Requirement 11: Content items

**User Story:** As a page owner, I want every page item stored in one place with an audience, so that later specs can add item types without schema changes and visibility is checked in one way.

#### Acceptance Criteria

1. THE `content_items` table SHALL store for each Content_Item: id, Owner Profile, Content_Type, Audience, `details jsonb`, optional `expires_at`, optional parent Content_Item and optional Group.
2. THE Database SHALL accept the Content_Type values `writing`, `gallery`, `status` and `story`, and `vouch` if the design stores Vouches in `content_items`, and SHALL allow new Content_Type values to be added without changing any table structure.
3. THE Database SHALL accept the Audience values `public`, `connections`, `circles` and `group`.
4. WHEN a Content_Item is created without an Audience, THE Database SHALL set the Audience to `connections`.
5. IF a Content_Item of type `writing` has an Audience other than `public`, THEN THE Database SHALL reject the write.
6. WHEN a Content_Item of type `writing` is created without an Audience, THE Database SHALL set the Audience to `public`.
7. IF a Content_Item has Audience `circles` and has no Item_Circle_Link at the end of the transaction, THEN THE Database SHALL reject the transaction.
8. IF an Item_Circle_Link references a Circle not owned by the Owner of the Content_Item, THEN THE Database SHALL reject the write.
9. IF a Content_Item has Audience `group` and no Group, THEN THE Database SHALL reject the write.
10. WHEN a Content_Item of type `story` is created, THE Database SHALL set `expires_at` to 24 hours after `created_at`.
11. IF a write sets a parent Content_Item owned by a different Owner, THEN THE Database SHALL reject the write.
12. THE Database SHALL validate the `details` of each Content_Type against a minimal required shape (for example `writing` requires a title and body, `gallery` requires an image path, `status` requires text of 1 to 100 characters).
13. THE Database SHALL allow at most one current Status per Owner, so that a new Status replaces the previous Status.
14. WHEN a Status is set, THE Database SHALL keep the Status until the Owner changes or deletes the Status, with no automatic expiry.
15. THE RLS policy for reading `content_items` SHALL use can_view and no other visibility logic.
16. THE Database SHALL accept writes to `content_items` and Item_Circle_Links only when acts_as is true for the Owner.

### Requirement 12: Story views

**User Story:** As a viewer, I want stories I have seen to be marked as seen, so that my story ring shows what is new.

#### Acceptance Criteria

1. THE `story_views` table SHALL store one row per Story and viewing Profile, with the time of the view.
2. WHEN a Profile views a Story more than once, THE Database SHALL keep a single Story_View row for that Story and Profile.
3. IF a Profile records a Story_View for a Story that can_view does not allow the Profile to see, THEN THE Database SHALL reject the write.

4. IF a Story_View is recorded for a Content_Item that is not a Story, THEN THE Database SHALL reject the write.
5. THE Database SHALL make a Story_View readable by Auth_Users for whom acts_as is true on the viewing Profile or on the Owner of the Story.
6. THE Database SHALL accept Story_View writes only when acts_as is true for the viewing Profile.

### Requirement 13: Story labels

**User Story:** As a viewer of a story shared to a circle, I want to see a short label chosen by the owner, so that I know the story was shared with me without learning the owner's private circle names or who else can see it.

#### Acceptance Criteria

1. THE Story_Label_Function SHALL accept a Story id and a viewer profile id and SHALL return at most one Story_Label, made of a label kind (`member_label`, `only_for_you` or `shared_with_you`) and, for kind `member_label` only, the Member_Label text.
2. IF can_view returns false for the Story and the Viewer, THEN THE Story_Label_Function SHALL return no Story_Label.
3. WHEN the Viewer is the Owner of the Story, THE Story_Label_Function SHALL return no Story_Label.
4. WHEN the Story has Audience `circles` and at least one linked Circle that contains the Viewer has the Member_Label_Switch on, THE Story_Label_Function SHALL return kind `member_label` with the Member_Label of the first such Circle in Circle_Label_Order.
5. WHEN the Story has Audience `circles`, no linked Circle that contains the Viewer has the Member_Label_Switch on, and the Viewer is the only Circle_Member of every Circle linked to the Story, THE Story_Label_Function SHALL return kind `only_for_you`.
6. WHEN the Story has Audience `circles`, no linked Circle that contains the Viewer has the Member_Label_Switch on, and at least one linked Circle has a Circle_Member other than the Viewer, THE Story_Label_Function SHALL return kind `shared_with_you`.
7. WHEN the Story has an Audience other than `circles`, THE Story_Label_Function SHALL return no Story_Label (Decision NQ-3).
8. THE Story_Label_Function SHALL count the members of an All_Followers_Audience as the current Followers of the Business_Profile.
9. THE Story_Label_Function SHALL take label text only from the Member_Label column of a Circle that contains the Viewer and has the Member_Label_Switch on.
10. THE Story_Label_Function SHALL return no Circle_Private_Name, Circle id, Circle count or Circle_Member identity.
11. WHEN the Member_Label_Switch of a Circle is turned off or the Viewer is removed from the Circle, THE Story_Label_Function SHALL stop returning that Circle's Member_Label to the Viewer at the next call.
12. WHEN the Story_Label_Function is called by an `authenticated` caller with a viewer profile id for which acts_as is false, THE Story_Label_Function SHALL evaluate as if the Viewer were null.
13. THE Story_Label_Function SHALL be declared `stable`, SHALL be a security definer function with `search_path = ''` and fully qualified names, and SHALL call can_view for visibility.
14. THE Database SHALL return the strings "Only for you" and "Shared with you" as label kinds only, so that the app shows them through the `t()` helper in English and Swahili.

### Area: Vouches and Top 8

### Requirement 14: Vouches, Top 8 and endorsements

**User Story:** As a person, I want to vouch for people I trust and feature my 8 people on my page, and I want vouches I receive shown as endorsements, so that visitors and search can trust the people I stand behind.

#### Acceptance Criteria

1. THE Database SHALL store each Vouch with its Vouch_Author Profile, its Vouch_Subject Profile, its text of 1 to 500 characters, an Audience, an optional Top_8 position, a `hidden_by_subject boolean not null default false` flag and `created_at`.
2. THE design SHALL decide whether Vouches are stored in `content_items` or in their own table and SHALL record the decision in a Decision_Record in `docs/decisions/`.
3. THE Database SHALL decide every read of a Vouch through can_view, whichever storage the design chooses.
4. WHEN a Vouch is created, THE Database SHALL keep the Vouch until the Vouch_Author deletes the Vouch or one of the two Profiles is deleted.
5. IF the Vouch_Author and the Vouch_Subject are the same Profile, THEN THE Database SHALL reject the write.
6. IF the Signed_In_User acting as the Vouch_Author owns or manages the Vouch_Subject, THEN THE Database SHALL reject the write.
7. THE Database SHALL accept a new Vouch only when acts_as is true for the Vouch_Author and either the Vouch_Author is an Accepted_Connection of the Vouch_Subject of the same profile type, or the Vouch_Author is a Person_Profile that follows the Vouch_Subject Business_Profile.
8. IF a Business_Profile attempts to vouch for a Person_Profile, THEN THE Database SHALL reject the write.
9. THE Database SHALL allow at most one Vouch from the same Vouch_Author about the same Vouch_Subject.
10. WHEN a Vouch is created without an Audience, THE Database SHALL set the Audience to `public`.
11. THE Database SHALL accept changes to the text, the Audience, the Item_Circle_Links and the Top_8 position of a Vouch, and deletion of a Vouch, only when acts_as is true for the Vouch_Author.
12. IF a Vouch has Audience `circles`, THEN THE Database SHALL require every linked Circle to be owned by the Vouch_Author.
13. THE Database SHALL accept changes to `hidden_by_subject` only when acts_as is true for the Vouch_Subject.
14. IF the Vouch_Subject attempts to change any field of a Vouch other than `hidden_by_subject`, or to delete a Vouch, THEN THE Database SHALL reject the write.
15. IF the Vouch_Author attempts to change `hidden_by_subject`, THEN THE Database SHALL reject the write.
16. IF a write would give one Vouch_Author more than 8 Featured_Vouches, THEN THE Database SHALL reject the write.
17. THE Database SHALL restrict a Top_8 position to an integer from 1 to 8 and SHALL allow at most one Featured_Vouch per position per Vouch_Author.
18. WHEN the Vouch_Author swaps two Featured_Vouches or replaces a Featured_Vouch within one transaction, THE Database SHALL accept the transaction if the final state satisfies criteria 16 and 17.
19. THE Database SHALL list on the Vouch_Author's page the Vouch_Author's Featured_Vouches in Top_8 position order, each only where can_view returns true for the Viewer, whether or not the Vouch is a Hidden_Vouch.
20. THE Database SHALL list on the Vouch_Subject's page the Received_Vouches that are not Hidden_Vouches, each only where can_view returns true for the Viewer.
21. WHILE a Vouch is a Hidden_Vouch, THE Database SHALL keep the Vouch readable by the Vouch_Subject so that the Vouch_Subject can unhide the Vouch.
22. THE Database SHALL compute Search_Trust for a Profile as the number of distinct Vouch_Authors whose Top_8 contains a Vouch about that Profile with Audience `public`, whether or not the Vouch is a Hidden_Vouch (Decisions NQ-2 and NQ-4).
23. WHEN a Vouch is created, THE Database SHALL create a Notification of type `vouch_received` for the Vouch_Subject.

### Area: Signals

### Requirement 15: Notifications

**User Story:** As a person, I want notifications about who connected, followed, vouched for and viewed me, so that I have a reason to come back without a feed.

#### Acceptance Criteria

1. THE `notifications` table SHALL store for each Notification: recipient Profile, type, optional actor Profile, optional reference id, a `data jsonb` field, a read time and `created_at`.
2. THE Database SHALL restrict the Notification type to `connection_request`, `connection_accepted`, `new_follower`, `vouch_received`, `profile_viewed` and `weekly_search_appearances`, extendable by a new Migration.
3. WHEN a Connection request is created, THE Database SHALL create a `connection_request` Notification for the target Profile.
4. WHEN a Connection is accepted, THE Database SHALL create a `connection_accepted` Notification for the requester Profile.
5. WHEN a Connection is declined, THE Database SHALL create no Notification for the requester.
6. WHEN a Follow is created, THE Database SHALL create a `new_follower` Notification for the Business_Profile.
7. WHEN a Profile_View is recorded, THE Database SHALL create a `profile_viewed` Notification for the viewed Profile according to the deduplication rule in Requirement 16.
8. WHEN the weekly search summary runs, THE Database SHALL create one `weekly_search_appearances` Notification per Profile with at least one Search_Appearance in the previous 7 Nairobi_Days, holding the total count.
9. THE Database SHALL run the weekly search summary through a `pg_cron` job every Monday at 05:00 UTC (08:00 Africa/Nairobi) that calls a security definer function.
10. THE `data` field of every Notification SHALL hold only Profile ids, Handles, display names, counts and Notification types, and SHALL hold no Circle_Private_Name, Member_Label, Vouch text, or text, image path or details of any Content_Item other than a public one.
11. THE Database SHALL create Notifications only through database triggers or security definer functions, and SHALL reject direct inserts by the `anon` and `authenticated` roles.
12. THE Database SHALL make a Notification readable only by Auth_Users for whom acts_as is true on the recipient Profile.
13. WHEN the recipient marks a Notification as read, THE Database SHALL set the read time and SHALL leave all other fields unchanged.
14. IF a Relationship request or Follow is deleted before it is read, THEN THE Database SHALL keep the Notification free of any content beyond the fields in criterion 10.

### Requirement 16: Profile views and search appearances

**User Story:** As a person, I want to know who viewed my page and how often I appeared in search, so that I can see my reach.

#### Acceptance Criteria

1. THE `profile_views` table SHALL store the viewed Profile, the viewing Profile, the Nairobi_Day and the time of the view.
2. THE Database SHALL accept a Profile_View only from a Signed_In_User for whom acts_as is true on the viewing Profile, so that views by Anonymous_Visitors are not recorded.
3. IF the viewing Profile and the viewed Profile are the same Profile, or the Signed_In_User manages the viewed Profile, THEN THE Database SHALL reject the Profile_View.
4. WHEN a viewing Profile views the same Profile more than once on the same Nairobi_Day, THE Database SHALL keep one Profile_View row and one `profile_viewed` Notification for that Nairobi_Day.
5. THE Database SHALL make a Profile_View readable only by Auth_Users for whom acts_as is true on the viewed Profile or the viewing Profile.
6. THE `search_appearances` table SHALL store one row per Profile per Nairobi_Day with a count of appearances.
7. WHEN the Search_Function returns a Profile to a signed in searcher, THE Database SHALL increase that Profile's Search_Appearance count for the current Nairobi_Day by 1 at most once per searching Profile, returned Profile and Nairobi_Day.
8. WHEN the Search_Function returns a Profile to an Anonymous_Visitor, THE Database SHALL increase that Profile's Search_Appearance count for the current Nairobi_Day by 1 (Decision NQ-6).
9. THE Database SHALL make Search_Appearances readable only by Auth_Users for whom acts_as is true on that Profile.
10. THE Database SHALL accept writes to `search_appearances` only from the Search_Function and the weekly summary function, and SHALL reject direct writes by the `anon` and `authenticated` roles.

### Area: AI and Last.fm

### Requirement 17: AI usage and spend cap

**User Story:** As Dominic, I want AI usage limited per day and capped per month in the database, so that AI themes cannot run up an unexpected bill.

#### Acceptance Criteria

1. THE `ai_usage` table SHALL store AI calls per Auth_User per Nairobi_Day with the request count and cost in US dollars, and SHALL record the Acting_Profile on each row.
2. THE Database SHALL store the Spend_Cap_Setting and the per day call limit in a settings table, with defaults of 10 US dollars per month and 20 calls per Auth_User per Nairobi_Day.
3. THE Database SHALL provide a function `public.ai_can_call` that returns true only when the Signed_In_User is under the daily call limit and the current month's total cost across all Auth_Users is under the Spend_Cap_Setting, executable by the `authenticated` role.
4. THE Database SHALL provide a function `public.ai_record_call` that records one AI call and its cost for a given Auth_User and Acting_Profile.
5. THE Database SHALL make `ai_usage` rows readable only by the Auth_User they belong to and SHALL reject direct inserts, updates and deletes by the `anon` and `authenticated` roles.
6. THE Database SHALL make the settings table unreadable and unwritable by the `anon` and `authenticated` roles.
7. THE Database SHALL grant execute on `public.ai_record_call` to the `service_role` role only, with execute revoked from `public`, `anon` and `authenticated`.
8. IF the `anon` or `authenticated` role calls `public.ai_record_call`, THEN THE Database SHALL reject the call with a permission error.
9. WHEN `public.ai_record_call` is called with an Acting_Profile that the given Auth_User does not own or manage, THE Database SHALL reject the call.

Note: the AI_Route (later spec) checks `public.ai_can_call` with a client created from the signed in user's session, calls the AI provider, and then records usage through the Admin_Client. Recording therefore never trusts a cost reported by the browser, and the Secret_Key stays in `src/lib/supabase/admin.ts`.

### Requirement 18: Last.fm link

**User Story:** As a person, I want to connect my Last.fm username, so that my page can show my listening activity in a later spec.

#### Acceptance Criteria

1. THE `lastfm_links` table SHALL store at most one Last.fm username per Profile, from 2 to 15 characters of letters, digits, underscore and hyphen, starting with a letter.
2. THE Database SHALL accept writes to a Lastfm_Link only when acts_as is true for the Profile.
3. THE Database SHALL make the Lastfm_Link readable only by Auth_Users for whom acts_as is true for the Profile.

### Area: Stretch tables

### Requirement 19: Groups and chat tables

**User Story:** As Dominic, I want the stretch tables created now with RLS, so that groups and chat can be built later without reshaping the schema.

#### Acceptance Criteria

1. THE Database SHALL contain a `groups` table with an owner Profile, a name and an optional linked Circle owned by the same Profile.
2. THE Database SHALL expose the linked Circle of a Group only to Auth_Users for whom acts_as is true on the Group owner.
3. THE Database SHALL contain a `group_members` table with at most one row per Group and Profile.
4. THE Database SHALL contain `conversations`, `conversation_members`, `messages` and `message_translations` tables.
5. THE `messages` table SHALL store the sender Profile, the Conversation, the body and the language code the Message was written in.
6. THE `message_translations` table SHALL allow at most one row per Message per language code.
7. THE stretch tables SHALL have RLS enabled with policies that allow reads only to Group_Members or Conversation_Members acting as their own Profile and writes only through acts_as.
8. WHERE the `groups` or `chat` feature flags are off, THE stretch tables SHALL remain empty except for rows created by tests that are rolled back.

### Area: Privacy engine

### Requirement 20: can_view

**User Story:** As a person on Pavio, I want one rule deciding who sees each of my items, so that a circle only story never leaks.

#### Acceptance Criteria

1. THE can_view function SHALL be the only SQL function that decides whether a Viewer can see a Content_Item or a Vouch.
2. WHEN can_view is called with a Viewer that is the Owner of the item, THE can_view function SHALL return true, including for an Expired_Item.
3. WHEN can_view is called for a Vouch with a Viewer that is the Vouch_Subject, THE can_view function SHALL return true.
4. IF the item is an Expired_Item and the Viewer is not the Owner, THEN THE can_view function SHALL return false.
5. WHEN the item has Audience `public` and is not an Expired_Item, THE can_view function SHALL return true for every Viewer, including a null Viewer for an Anonymous_Visitor.
6. WHEN the item has Audience `connections`, THE can_view function SHALL return true only if the Viewer is an Accepted_Connection of the Owner or, for a Business_Profile Owner, a Follower of the Owner.
7. WHEN the item has Audience `circles`, THE can_view function SHALL return true only if the Viewer is a Circle_Member of at least one Circle linked to the item, counting the All_Followers_Audience as containing every current Follower.
8. WHEN the item has Audience `group`, THE can_view function SHALL return true only if the Viewer is a Group_Member of the item's Group.
9. THE can_view function SHALL evaluate the Audience of a Vouch against the Relationships and Circles of the Vouch_Author, on the Vouch_Author's page and on the Vouch_Subject's page alike (Decision NQ-1).
10. THE can_view function SHALL return the same result for a Vouch whether or not the Vouch is a Hidden_Vouch, since hiding changes only the listing on the Vouch_Subject's page.
11. WHEN can_view is called with a null Viewer, THE can_view function SHALL return true only for non expired items with Audience `public`.
12. WHEN can_view is called with an item id that does not exist, THE can_view function SHALL return false.
13. WHEN a Content_Item has a parent, THE can_view function SHALL return true only if the Viewer can also see the parent.
14. THE can_view function SHALL be declared `stable`, SHALL be a security definer function with `search_path = ''` and fully qualified names, and SHALL use indexed lookups only.
15. WHEN can_view is called by an `authenticated` caller with a viewer_profile_id for which acts_as is false, THE can_view function SHALL evaluate as if the Viewer were null, so that a caller cannot learn another Profile's access.
16. WHEN can_view is evaluated on a row of `content_items` in the seeded Database, THE can_view function SHALL complete in under 5 milliseconds at the 95th percentile, measured by the pgTAP_Suite or the Property_Suite.

### Requirement 21: view_as

**User Story:** As a page owner, I want to preview my page as any connection, circle member, follower or stranger, so that I can check each face of my page.

#### Acceptance Criteria

1. THE view_as function SHALL return the items on the Owner's page for which can_view returns true when evaluated with the simulated Viewer: the Owner's Content_Items, the Owner's Top_8, and the Owner's Received_Vouches that are not Hidden_Vouches.
2. IF the caller of view_as is not an Auth_User for whom acts_as is true on the owner_profile_id, THEN THE view_as function SHALL raise an error and return no rows.
3. WHEN view_as is called with a null simulated Viewer, THE view_as function SHALL return the items an Anonymous_Visitor would see.
4. THE view_as function SHALL call can_view for visibility and SHALL contain no other visibility logic.
5. THE view_as function SHALL return only items that belong on the page of owner_profile_id under criterion 1.
6. WHEN view_as returns a Story, THE view_as function SHALL return with the Story the Story_Label that the Story_Label_Function returns for the simulated Viewer.
7. THE view_as function SHALL be a security definer function with `search_path = ''` and fully qualified names, with execute revoked from `anon`.
8. THE view_as function SHALL return no Circle names, Circle membership or Item_Circle_Links of the simulated Viewer beyond what the Owner already owns.

### Area: RLS, grants and storage

### Requirement 22: Row Level Security and grants

**User Story:** As Dominic, I want every table locked down in the database itself, so that application code is never the only thing protecting data.

#### Acceptance Criteria

1. THE Database SHALL have RLS enabled on every table in the `public` schema.
2. THE Database SHALL have explicit policies, named for their role and action, for the `anon` and `authenticated` roles on every table that either role may access.
3. THE Database SHALL revoke from `anon` and `authenticated` every table privilege and function execute privilege that no policy or documented function call needs.
4. THE Database SHALL grant the `anon` role read access only to public Profile fields, public Business_Details fields, Content_Items and Vouches for which can_view returns true for a null Viewer, and execute on the Search_Function, the Relationship_Counts_Function and can_view.
5. IF the `anon` role attempts any insert, update or delete on any table, THEN THE Database SHALL reject the write.
6. THE Database SHALL ensure every write policy checks acts_as on the Acting_Profile of the row rather than only `auth.uid()`.
7. THE Database SHALL expose private Profile fields (Requirement 4 criterion 16) only through a path that requires acts_as, such as a separate table or a column privilege.
8. THE Database SHALL expose the `circles` columns holding the Circle_Private_Name, the Member_Label_Switch and the Member_Label only through a path that requires acts_as on the Circle_Owner.
9. WHEN the Advisors run after the final Migration of this spec, THE Advisors SHALL report no security warning except lints 0028 and 0029 on the allowlist of DR-4.
10. THE Secret_Key SHALL appear only in `supabase/seed/` and in no Migration, test file or other file in this spec; the Admin_Client in `src/lib/supabase/admin.ts` is the only other allowed location and is created in a later spec.
11. THE Database SHALL grant execute on `public.ai_record_call` only to the `service_role` role, as stated in Requirement 17 criterion 7.

### Requirement 23: Storage buckets

**User Story:** As a page owner, I want my files stored so that restricted photos are reachable only by people who may see the item, so that a private image never leaks through its address.

#### Acceptance Criteria

1. THE Database SHALL contain a Public_Bucket whose objects any Viewer, including an Anonymous_Visitor, may read.
2. THE Database SHALL contain a Private_Bucket whose objects are not publicly readable.
3. WHEN a Viewer requests an object in the Private_Bucket, THE Database SHALL allow the read only if can_view returns true for the Viewer on a Content_Item that references the object path.
4. THE Database SHALL accept uploads, updates and deletes in either bucket only when the first folder of the object path is a Profile id for which acts_as is true.
5. IF the `anon` role attempts to upload, update or delete an object in either bucket, THEN THE Database SHALL reject the write.
6. THE Database SHALL create both buckets and their storage policies through Migrations in this spec.
7. THE Public_Bucket SHALL hold only avatars, cover images and images used in writing; every gallery and story file SHALL be stored in the Private_Bucket and read through signed URLs, whatever its Audience (Decision NQ-5).

### Area: Search

### Requirement 24: Public directory search

**User Story:** As anyone, signed in or not, I want to find people and businesses by what they do, so that Pavio works like the Yellow Pages.

#### Acceptance Criteria

1. THE Search_Function SHALL accept a query text, an optional profile type filter, an optional city filter, a page size from 1 to 50 and a page offset.
2. THE Search_Function SHALL match the query against display name, Handle, What_I_Do_Tags, public bio, business category and city.
3. WHEN a query word has trigram similarity of at least 0.3 to a word in a searched field, THE Search_Function SHALL return the matching Profile, so that "nutritonist" matches "nutritionist".
4. THE Search_Function SHALL combine trigram matching with full text matching on What_I_Do_Tags and public bio.
5. THE Search_Function SHALL return only public Profile fields, public Business_Details fields and the Search_Trust count, and SHALL return no Content_Item, Vouch text, Circle, Circle_Private_Name, Member_Label, Relationship or private Profile field.
6. THE Search_Function SHALL order results by text relevance increased by a boost for each unit of Search_Trust, with the boost formula fixed in the design.
7. WHEN two Profiles have equal text relevance, THE Search_Function SHALL rank the Profile with the higher Search_Trust first.
8. WHEN the Search_Function returns results, THE Search_Function SHALL record Search_Appearances for the returned Profiles under the rules of Requirement 16.
9. THE Search_Function SHALL be callable by `anon` and `authenticated` roles.
10. WHEN the query text is empty or has fewer than 2 non space characters, THE Search_Function SHALL return no results and record no Search_Appearance.
11. THE Database SHALL have trigram or full text indexes supporting every searched column.
12. WHEN the seeded Database is searched, THE Search_Function SHALL return results in under 200 milliseconds at the 95th percentile.

### Area: Tests

### Requirement 25: pgTAP tests

**User Story:** As Dominic, I want database tests for every table, policy and function, so that the privacy rules are proven, not assumed.

#### Acceptance Criteria

1. THE pgTAP_Suite SHALL contain, for every table, tests proving that the `anon` role cannot write and that an `authenticated` role without acts_as on the owning Profile cannot read restricted rows or write.
2. THE pgTAP_Suite SHALL test every RLS policy and every storage policy with at least one allowed case and one rejected case.
3. THE pgTAP_Suite SHALL test acts_as, can_view, view_as, the Story_Label_Function, the Relationship_Counts_Function and the Search_Function, including every Audience, expiry, null Viewer and non existent id case of Requirement 20.
4. THE pgTAP_Suite SHALL test every check constraint and trigger in Requirements 4 to 19 with at least one rejected case.
5. THE pgTAP_Suite SHALL test that RLS is enabled on every table in the `public` schema.
6. THE pgTAP_Suite SHALL test, for a Circle whose Member_Label differs from its Circle_Private_Name, that a non owner `authenticated` caller and the `anon` role cannot obtain the Circle_Private_Name from any table, view or function they may access, including `circles`, `circle_members`, Item_Circle_Links, `groups`, `notifications`, can_view, view_as, the Story_Label_Function and the Search_Function.
7. THE pgTAP_Suite SHALL test that the Story_Label_Function returns a Member_Label only while the Member_Label_Switch is on and only to Circle_Members of that Circle, and returns `only_for_you` and `shared_with_you` in the cases of Requirement 13.
8. THE pgTAP_Suite SHALL test that a Hidden_Vouch is absent from the Vouch_Subject's page listing, present in the Vouch_Author's Top_8 subject to can_view, and still readable by the Vouch_Subject.
9. THE pgTAP_Suite SHALL simulate users with `set local role` and `set local request.jwt.claims`.
10. THE pgTAP_Suite SHALL run every test file inside a transaction that ends with `rollback`, leaving no data in the Database.
11. WHEN the pgTAP_Suite is run with `supabase test db --linked`, THE pgTAP_Suite SHALL pass with zero failures.
12. THE pgTAP_Suite SHALL contain a canary test that switches to a simulated `authenticated` user with both `sub` and `role` in `request.jwt.claims` and proves that `current_user` is `authenticated`, `auth.uid()` equals the simulated user id, `private.is_api_caller()` is true, and a known restricted row owned by another Profile is invisible.
13. THE pgTAP_Suite SHALL test that the `anon` and `authenticated` roles cannot execute `public.ai_record_call` and that the `service_role` role can.

### Requirement 26: Property based tests

**User Story:** As Dominic, I want randomised tests of the visibility rules against the real database, so that edge cases I did not think of are found before the demo.

#### Acceptance Criteria

1. THE Property_Suite SHALL generate random Profiles, Relationships, Circles, Circle_Members, Member_Label settings, Content_Items and Vouches and run each case against the Database through `SUPABASE_DB_URL`.
2. THE Property_Suite SHALL run each case inside its own transaction that is always rolled back, including when the case fails.
3. THE Property_Suite SHALL simulate users only through the Simulated_User_Switch, which runs `set local role authenticated` or `anon` and `set local request.jwt.claims` with both the `sub` and the `role` claims set, so that RLS applies as in the app.
4. THE Property_Suite SHALL name in each property the requirement and criterion it validates.
5. THE Property_Suite SHALL prove Property 1: for any non public Content_Item or Vouch, a Stranger and an Anonymous_Visitor cannot see the item through RLS or can_view.
6. THE Property_Suite SHALL prove Property 2: for any Content_Item with Audience `connections`, every Accepted_Connection of the Owner can see the item and every non connection Stranger cannot.
7. THE Property_Suite SHALL prove Property 3: for any Content_Item with Audience `circles`, exactly the Owner and the Circle_Members of at least one linked Circle can see the item.
8. THE Property_Suite SHALL prove Property 4: for any Circle item and member, after the member is removed from the Circle and is in no other linked Circle, the member cannot see the item.
9. THE Property_Suite SHALL prove Property 5: for any Expired_Item, only the Owner can see the item.
10. THE Property_Suite SHALL prove Property 6: for any Owner and simulated Viewer, the set returned by view_as equals the set of items on the Owner's page under Requirement 21 criterion 1 for which can_view returns true for that Viewer, and so never contains an item the Viewer could not see.
11. THE Property_Suite SHALL prove Property 7: for any attempted Relationship whose requester is a Business_Profile and target is a Person_Profile, the Database rejects the write.
12. THE Property_Suite SHALL prove Property 8: for any sequence of feature, unfeature and swap operations, no Vouch_Author has more than 8 Featured_Vouches and no two Featured_Vouches of one Vouch_Author share a position.
13. THE Property_Suite SHALL prove Property 9: for any query and any Database state, every field the Search_Function returns is a public field of a Profile or Business_Details or the Search_Trust count.
14. THE Property_Suite SHALL prove Property 10: for any Circles with random Circle_Private_Names that differ from their Member_Labels, and any Viewer that is not the Circle_Owner, including an Anonymous_Visitor, no value the Viewer can read through any table, view or function contains a Circle_Private_Name.
15. THE Property_Suite SHALL prove Property 11: for any Story with Audience `circles`, any linked Circles with random Member_Label_Switch values and any Viewer, the Story_Label_Function returns kind `member_label` only when the Viewer is a Circle_Member of a linked Circle whose Member_Label_Switch is on, the returned text equals the Member_Label of the first such Circle in Circle_Label_Order, and at most one Story_Label is returned.
16. THE Property_Suite SHALL prove Property 12: for any Story and Viewer, after the Circle_Owner turns off the Member_Label_Switch of a Circle, the Story_Label_Function no longer returns that Circle's Member_Label to the Viewer.
17. THE Property_Suite SHALL run Property_Runs cases per property, defaulting to 25 when `PROPERTY_RUNS` is not set, unless a property documents a lower count with its reason.
18. WHEN a property finds a failure, THE developer SHALL keep the shrunk counterexample as a regular regression test and record it in `DEVLOG.md`.
19. WHEN `npm run test:property` is run, THE Property_Suite SHALL pass with zero failures.
20. WHEN the Simulated_User_Switch completes, THE Simulated_User_Switch SHALL run the Canary_Check, asserting that `current_user` equals the expected role, that `auth.uid()` equals the simulated user id (null for `anon`), and that `private.is_api_caller()` returns true.
21. IF any assertion of the Canary_Check fails, THEN THE Property_Suite SHALL fail the current case immediately, before the function under test runs.
22. THE Property_Suite SHALL contain a sanity test proving that a known restricted row owned by another Profile is invisible after the Simulated_User_Switch.
23. THE Property_Suite SHALL run every assertion about visibility or rejected writes as an API_Caller, so that no assertion runs as a Trusted_Caller.
24. IF `PROPERTY_RUNS` is set to a value that is not a positive integer, THEN THE Property_Suite SHALL fail with a message that names the variable.

### Area: Seed data

### Requirement 27: Demo seed data

**User Story:** As Dominic, I want believable demo data with invented names, so that judges can explore every feature with one click demo accounts.

#### Acceptance Criteria

1. THE Seed_Script SHALL use only invented people and businesses.
2. THE Seed_Script SHALL create Person_Profiles for Amina (nutritionist), Brian (founder), one photographer and two more people, each with a Status and What_I_Do_Tags.
3. THE Seed_Script SHALL create a cafe Business_Profile and a supplier Business_Profile, each with Business_Details and at least one Auth_User with Profile_Manager_Role `owner`.
4. THE Seed_Script SHALL create Accepted_Connections, at least one pending Connection, a Business to Business Connection and Follows to the cafe.
5. THE Seed_Script SHALL create Circles with the Circle_Private_Names "family", "the cabal" and "close friends" with Circle_Members, at least one with the Member_Label_Switch on and a Member_Label that differs from its Circle_Private_Name, and at least one with the switch off.
6. THE Seed_Script SHALL create Content_Items with each Audience `public`, `connections` and `circles`, an active Story shared to one Circle and an expired Story.
7. THE Seed_Script SHALL create Vouches with every Audience used in the seed, including Featured_Vouches in at least two Vouch_Authors' Top_8, unfeatured Vouches and at least one Hidden_Vouch.
8. THE Seed_Script SHALL create the demo Auth_Users through the Supabase Auth admin API called from a Node script in `supabase/seed/` with the Secret_Key, using fixed emails on the invented domain `demo.pavio.world` (for example `amina@demo.pavio.world`).
9. WHEN the Seed_Script is run twice, THE Seed_Script SHALL leave the Database in the same state as after one run.
10. THE Seed_Script SHALL use the Secret_Key only inside `supabase/seed/` and SHALL read the Secret_Key from `.env.local`.
11. IF the Seed_Script targets a project other than the Pavio_Project, THEN THE Seed_Script SHALL stop before writing any data.

### Area: Process

### Requirement 28: Working process, commits and diary

**User Story:** As Dominic, I want the build to follow the steering process, so that the commit history tells a clear story to the judges.

#### Acceptance Criteria

1. WHEN the first task starts, THE developer SHALL create the Spec_Branch from an up to date `main`.
2. THE developer SHALL make every commit of this spec on the Spec_Branch with a Conventional Commit message using the types and scopes in `git.md`.
3. THE developer SHALL keep each commit to one logical change, keeping Migrations, application code, tests, and steering or spec edits in separate commits, except that a Migration may share a commit with the pgTAP test that proves the Migration.
4. THE developer SHALL stage files by explicit path and review `git status` and `git diff --staged` before each commit.
5. WHEN a spec task is completed, THE developer SHALL add a dated entry to `DEVLOG.md` naming the spec task, what was built and any decision or problem.
6. WHEN a spec task is completed, THE developer SHALL push the Spec_Branch.
7. WHEN a meaningful technical choice is made, THE developer SHALL record the choice in a Decision_Record.
8. WHEN all tasks are complete and all test suites pass, THE developer SHALL run the privacy-reviewer agent, fix every Critical and High finding, and open a pull request titled `Spec 00: Database foundation` with the headings in `git.md`.
9. WHEN the pull request is open, THE developer SHALL stop and ask Dominic to review and merge.
10. THE developer SHALL commit no secret, no `.env` file and no generated build, coverage or log output.
11. WHEN all tasks are complete and before the pull request is opened, THE developer SHALL run the Property_Suite once with the default Property_Runs and once with `PROPERTY_RUNS=100`, and SHALL record the run time of both runs in `DEVLOG.md`.

## Resolved Decisions

Decisions made by Dominic on the first round of open questions. The numbers match the original questions.

- **OQ-1. Handle format and reserved words.** 3 to 30 characters, lowercase `a-z`, digits and underscore, starting with a letter, unique case insensitively. Reserved words live in a table and include `demo`. (Req 4)
- **OQ-2. Manager permissions.** A manager can do everything an owner can while acting as the business, except change Profile_Manager_Roles or delete the Business_Profile. (Req 7)
- **OQ-3. Re-requesting after decline.** The Declined_Connection stays and blocks repeat requests from the same requester, who still sees it as pending. The target may delete it or send their own request. (Req 8, Req 15)
- **OQ-4. Relationship lists.** Lists are private to the two parties. Public pages show counts only, through the Relationship_Counts_Function. (Req 8, Req 22)
- **OQ-5. Story labels (changed).** Each Circle has a Circle_Private_Name seen only by the Circle_Owner, a Member_Label_Switch (default off) and a Member_Label pre-filled from the private name when the switch is first turned on. While the switch is on, members see the Member_Label on Stories. Otherwise they see "Only for you" when they are the only member of every linked Circle, else "Shared with you". At most one label, from the first switched-on Circle in Circle_Label_Order. (Req 9, 13, 25, 26)
- **OQ-6. Story viewers.** The Story Owner can read the Story_Views on their own Stories. (Req 12)
- **OQ-7. Top 8 (changed).** The Vouch_Author features up to 8 Vouches they wrote, ordered and swappable, shown on the author's page. The subject's page shows Received_Vouches. Search_Trust counts distinct authors who feature the Profile. Property 8 limits each author to 8. (Req 14, 24, 26)
- **OQ-8. Vouch audience and hiding (changed).** The Vouch_Author sets the Audience (default `public`, changed by NQ-2) and may edit or delete the Vouch. The Vouch_Subject may only hide or unhide it from their own page. can_view treats the Vouch_Author as Owner and always lets the Vouch_Subject see the Vouch; hiding affects only the subject's page listing. (Req 14, 20, 21)
- **OQ-9. Who may vouch.** Accepted_Connections of the same profile type, and a Person_Profile for a Business_Profile it follows. A business never vouches for a person. (Req 14)
- **OQ-10. Profile view deduplication.** One Profile_View and one Notification per viewer, viewed Profile and Nairobi_Day. Signed out views are not recorded. (Req 15, 16)
- **OQ-11. Weekly search notification.** A `pg_cron` job every Monday at 05:00 UTC (08:00 Nairobi). Daily buckets use Nairobi_Days. (Req 1, 15, 16)
- **OQ-12. AI limits.** Limit per Auth_User per Nairobi_Day with the Acting_Profile recorded. Defaults: 20 calls per day and 10 US dollars per month, stored in the settings table. (Req 17)
- **OQ-13. Typo tolerance and repeated searches.** `pg_trgm` similarity of at least 0.3 plus full text on tags and bio. A signed in searcher counts at most once per returned Profile per day. (Req 16, 24)
- **OQ-14. Demo auth users.** A Node script in `supabase/seed/` creates them through the Auth admin API with fixed `@demo.pavio.world` emails. One click sign in comes in a later spec. (Req 27)
- **OQ-15. Storage buckets.** Both buckets and their storage policies are created in this spec, with Private_Bucket reads decided by can_view. (Req 23)
- **OQ-16. Deletion cascades.** As stated in Requirement 5 criteria 5 to 8.
- **OQ-17. Group audience.** Accepted now with a required Group reference; can_view handles it and the pgTAP_Suite tests it. (Req 11, 19, 20)
- **OQ-18. Dot colour for businesses.** Every Profile has a Dot_Colour_Key, default `terracotta`. (Req 4)

### Second round (NQ)

Decisions made by Dominic on the questions raised by the first round.

- **NQ-1. Vouch audience on the subject's page.** Always judged by the Vouch_Author's Relationships and Circles, on both pages. A `connections` Vouch on the subject's page is visible only to the author's connections. (Req 20)
- **NQ-2. Search_Trust and audience (changed).** Only featured Vouches with Audience `public` count toward Search_Trust. To keep Search_Trust meaningful, the **default Vouch Audience is `public`** (this updates OQ-8); the author may narrow it, and non public Vouches simply do not count. (Req 14, 24)
- **NQ-3. Labels on non circle stories.** Stories with Audience `public` or `connections` show no label. (Req 13)
- **NQ-4. Hiding and Search_Trust.** Hiding a Vouch affects only the subject's page listing and does not change Search_Trust. A later spec may let a subject decline (delete) a Vouch. (Req 14)
- **NQ-5. Buckets.** The Public_Bucket holds only avatars, covers and images used in writing. Every gallery and story file goes in the Private_Bucket, read through signed URLs whatever its Audience, so a file can never stay public after its item becomes restricted. (Req 23)
- **NQ-6. Anonymous search appearances.** Each anonymous search counts once per returned Profile. (Req 16)

### Design review changes

Changes approved by Dominic after the design review.

- **DR-1. Canary check.** The `asUser` helper always sets `sub` and `role`, then asserts `current_user`, `auth.uid()` and `private.is_api_caller()`, failing at once if any check fails. A pgTAP canary test and a property sanity test prove a known restricted row is invisible, so no test silently runs as a Trusted_Caller. (Req 25.12, 26.3, 26.20 to 26.23)
- **DR-2. AI usage recording.** `public.ai_record_call` is executable by `service_role` only. The AI_Route checks `ai_can_call` as the signed in user and records usage through the Admin_Client. (Req 17.3, 17.4, 17.7 to 17.9, 22.11, 25.13)
- **DR-3. Property test cost.** Properties default to 25 runs against the remote Database, set through `PROPERTY_RUNS`. Before the pull request the suite runs once with `PROPERTY_RUNS=100`, and both run times go in `DEVLOG.md`. (Req 26.17, 26.24, 28.11)
- **DR-4. Accepted definer RPC lints.** Supabase security advisor lints 0028 and 0029 (security definer functions executable through the API) are accepted only for the public security definer functions listed in the design's function execute grants table (the `anon` row and the `authenticated` row). Requirement 22 criterion 9 therefore means that after the final Migration the security advisor reports no finding other than 0028 or 0029 on exactly that allowlist. `supabase/tests/02_security_definer.test.sql` pins the allowlist: the set of public security definer functions executable by `anon`, and the set executable by `authenticated`, must each equal it exactly. Any other security finding is still fixed in a `fix_` Migration. (Req 22.3, 22.9)
