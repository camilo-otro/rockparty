-- =============================================================================
-- Migration: is_venue_admin(), and stop publishing the venue → manager map (#102)
-- Date: 2026-09-11
-- =============================================================================
-- `venue_admin` SELECT is `USING (true)` granted to anon AND authenticated, so
-- the complete venue → manager mapping is readable LOGGED OUT, with PostgREST
-- joining the names on for you:
--
--   GET /rest/v1/venue_admin?select=venue_id,profile:user_id(nickname),venue:venue_id(name)
--   [ {venue_id: 7, venue:{name:"Parcharte"}, profile:{nickname:"Yorch"}}, ... ]
--
-- Its sibling `party_admin` has the identical `USING (true)` but is granted to
-- `authenticated` only, which is what makes this an over-broad default rather
-- than a decision. Same shape as #47 (profile.email): nothing escalates through
-- it, but it links named private individuals to physical addresses they are
-- responsible for, and `venue` also carries whatsapp / instagram / contact.
--
-- -----------------------------------------------------------------------------
-- Why this is not a one-line policy change
-- -----------------------------------------------------------------------------
-- SEVEN policies across FOUR tables inline a `venue_admin` subquery, and a table
-- referenced from inside an RLS policy is read AS THE CALLING USER — so narrowing
-- the SELECT filters all of them. Narrow it naively and venue admins lose venue
-- editing, equipment management, and the pending-toque queue at their own venue.
--
-- The trap: every one of those policies also has a `created_by` half that keeps
-- working, so TESTING AS THE VENUE CREATOR WOULD SHOW EVERYTHING FINE. It breaks
-- only for admins who are not the creator.
--
-- There is also a recursion trap: a `venue_admin` SELECT policy that itself
-- queries `venue_admin` raises "infinite recursion detected in policy for
-- relation". The current DELETE policy gets away with an inline subquery only
-- because the SELECT policy is `true` and references nothing.
--
-- Both are solved the same way, and it is the way the party and band side
-- already works: a SECURITY DEFINER helper. Verified before relying on it —
-- `venue_admin` does NOT have FORCE ROW LEVEL SECURITY, so a definer function
-- owned by postgres bypasses RLS and cannot recurse.
-- =============================================================================

begin;

-- ---------------------------------------------------------------------------
-- 1. The helper that should have existed all along
-- ---------------------------------------------------------------------------
-- There is no is_venue_admin() today, which is exactly why every venue policy
-- inlines the check. Mirrors is_party_admin(bigint) and is_band_manager(bigint).
--
-- "Venue admin" means the venue's CREATOR or a venue_admin row — the notion five
-- of the seven policies below already spell out longhand.
--
-- A null vid (a party with no venue) yields false from both EXISTS, matching the
-- inline subqueries it replaces.
create or replace function public.is_venue_admin(vid bigint)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.venue v
     where v.id = vid and v.created_by = (select auth.uid())
  ) or exists (
    select 1 from public.venue_admin va
     where va.venue_id = vid and va.user_id = (select auth.uid())
  );
$$;

-- GRANTED TO ANON ON PURPOSE — do not "harden" this to authenticated only.
-- It goes into `party`'s SELECT policy, which applies `to anon, authenticated`.
-- A policy expression calling a function the caller cannot EXECUTE raises
-- permission-denied rather than evaluating to false, so revoking anon here would
-- make every anonymous read of `party` throw — breaking the public flyer page
-- (#68) for exactly the logged-out visitors it exists for. is_dev() and
-- can_see_party() are anon-executable for the same reason.
revoke all on function public.is_venue_admin(bigint) from public, anon, authenticated;
grant execute on function public.is_venue_admin(bigint) to anon, authenticated;

-- ---------------------------------------------------------------------------
-- 2. Repoint the seven. Behaviour-preserving except where noted.
-- ---------------------------------------------------------------------------

-- venue: UPDATE — was created_by OR venue_admin, verbatim is_venue_admin().
drop policy if exists "allow update to venue admins" on public.venue;
create policy "allow update to venue admins" on public.venue
  for update to authenticated
  using (public.is_venue_admin(id));

-- venue_equipment: INSERT + DELETE — same expression, same meaning.
drop policy if exists "venue admins insert equipment" on public.venue_equipment;
create policy "venue admins insert equipment" on public.venue_equipment
  for insert to authenticated
  with check (public.is_venue_admin(venue_id));

drop policy if exists "venue admins delete equipment" on public.venue_equipment;
create policy "venue admins delete equipment" on public.venue_equipment
  for delete to authenticated
  using (public.is_venue_admin(venue_id));

-- venue_admin: INSERT — same expression.
drop policy if exists "allow insert for party admins" on public.venue_admin;
create policy "allow insert for party admins" on public.venue_admin
  for insert to authenticated
  with check (public.is_venue_admin(venue_id));

-- venue_admin: DELETE — a DELIBERATE, SMALL WIDENING, and the only behaviour
-- change in this migration.
--
-- The old expression was `auth.uid() = user_id OR exists(venue_admin same venue)`
-- — note it did NOT include the venue's creator. So a creator could ADD an admin
-- (the INSERT policy lets them) but never REMOVE one, unless they had also added
-- themselves to venue_admin. That asymmetry is an oversight, not a safeguard.
--
-- It is also not really optional: the inline subquery has to go, because after
-- step 3 it would be filtered by the new SELECT policy. Replacing it with
-- is_venue_admin() brings the creator along, which is the correct behaviour
-- anyway — the creator already controls the venue in every other respect.
drop policy if exists "allow delete for venue admins" on public.venue_admin;
create policy "allow delete for venue admins" on public.venue_admin
  for delete to authenticated
  using (user_id = (select auth.uid()) or public.is_venue_admin(venue_id));

-- party: SELECT — the outer `is_test` guard and every other branch preserved
-- exactly; only the two venue branches collapse into the helper.
drop policy if exists "select party: public statuses or owner/admins" on public.party;
create policy "select party: public statuses or owner/admins" on public.party
  for select to anon, authenticated
  using (
    (
      status = any (array['confirmed'::public.party_status,
                          'live'::public.party_status,
                          'completed'::public.party_status])
      or created_by = (select auth.uid())
      or exists (
        select 1 from public.party_admin pa
         where pa.party_id = party.id and pa.user_id = (select auth.uid())
      )
      or public.is_venue_admin(party.venue)
    )
    and (is_test = false or public.is_dev())
  );

-- party: UPDATE — same collapse. `with check (true)` preserved as it was.
drop policy if exists "allow update to party admins" on public.party;
create policy "allow update to party admins" on public.party
  for update to authenticated
  using (
    created_by = (select auth.uid())
    or exists (
      select 1 from public.party_admin pa
       where pa.party_id = party.id and pa.user_id = (select auth.uid())
    )
    or public.is_venue_admin(party.venue)
  )
  with check (true);

-- ---------------------------------------------------------------------------
-- 3. The actual fix
-- ---------------------------------------------------------------------------
-- Dropped from anon entirely, and narrowed for authenticated to "my own rows, or
-- the roster of a venue I manage". Renamed, because "Enable read access for all
-- users" would now be a lie.
--
-- Client impact should be nil. Of the five read sites, three
-- (+page.svelte, venues/mine, and the two `.eq('venue_id', …)` membership
-- checks) only ever use the result for `venueAdmins.includes(currentUserId)` and
-- never render the ids — returning just the caller's own row gives the identical
-- boolean. venues/[id]/edit genuinely needs the full roster and is reached only
-- by admins, which is_venue_admin() covers.
drop policy if exists "Enable read access for all users" on public.venue_admin;
create policy "venue_admin select: self or the venue's managers" on public.venue_admin
  for select to authenticated
  using (user_id = (select auth.uid()) or public.is_venue_admin(venue_id));

commit;

-- =============================================================================
-- VERIFY OVER REST, not in the SQL editor — there you are the table owner, RLS
-- does not apply at all, and every query succeeds while telling you nothing.
--
--   anon   GET /venue_admin?select=*            -> []
--   anon   GET /party?select=id&limit=1          -> still works (the flyer path;
--                                                   this is what would break if
--                                                   is_venue_admin were revoked
--                                                   from anon)
--   member GET /venue_admin?select=*             -> own rows + rosters of venues
--                                                   they manage, nothing else
--
-- THE CASE THE APPLYING ACCOUNT CANNOT TEST, and why it matters more here than
-- it might elsewhere: Cami Soto is the CREATOR of all eight venues. So every
-- policy above takes its created_by branch for that account, on every venue, and
-- the narrowing is invisible from it — a full pass as the owner would look
-- perfect whether or not the venue_admin half works at all.
--
-- The four accounts that actually exercise the other branch:
--
--   Yorch, fuyumehanamura   -> venue 7  (Parcharte)
--   Nath's, Clarz5074       -> venue 9  (Lugar por definir)
--
-- Verified by predicate before writing this: `created_by = uid OR a venue_admin
-- row` is true for all four, which is precisely what is_venue_admin() computes,
-- and five of the seven policies were already that expression written longhand.
-- So the rewrite is faithful by construction — but "faithful by construction" is
-- an argument, not an observation, and this is the one path worth having one of
-- them confirm: update the venue, add a piece of equipment, and check that a
-- pending_venue toque at it is still visible.
-- =============================================================================
