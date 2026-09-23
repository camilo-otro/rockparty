-- =============================================================================
-- Migration: the four new drum parts were never attached to the kit (#106)
-- Date: 2026-09-23
-- =============================================================================
-- CORRECTIVE, for 20260923_drum_kit_parts.sql. Apply immediately after it; if
-- you have not applied that one yet, apply it first, then this.
--
-- -----------------------------------------------------------------------------
-- The bug
-- -----------------------------------------------------------------------------
-- Step 4 of that migration inserts Bombo, Toms, Crash and Ride with an explicit
-- column list — and `part_of` is not in it. The three PRE-EXISTING parts (snare,
-- hihat, kick_pedal) were attached by UPDATEs in step 3 and are fine; the four
-- NEW ones came out as top-level items:
--
--   drum_kit  part_of null   <- correct, it is the parent
--   kick      part_of null   <- WRONG
--   snare     part_of 6      <- correct
--   hihat     part_of 6      <- correct
--   toms      part_of null   <- WRONG
--   crash     part_of null   <- WRONG
--   ride      part_of null   <- WRONG
--   kick_pedal part_of 6     <- correct
--
-- What that costs, and why it is not cosmetic: a part with `part_of` null is a
-- top-level item, so those four would render as loose pills in the venue form
-- rather than inside the kit — and the quick-start would drop them ENTIRELY,
-- because it offers `is_basic` items plus the parts of one, and they are
-- neither. Half the drum kit would have silently vanished from the screen the
-- whole change exists to build.
--
-- Caught by reading the applied result back rather than by trusting the file —
-- the migration's own VERIFY block asks for exactly this query.
-- =============================================================================

begin;

update public.equipment
   set part_of = (select id from public.equipment where code = 'drum_kit')
 where code in ('kick', 'toms', 'crash', 'ride');

commit;

-- =============================================================================
-- VERIFY — every part points at the kit, and only the kit is top-level:
--
--   select code, name, part_of, default_on, sort_order from equipment
--    where category = 'batería' order by sort_order;
--     -> drum_kit part_of NULL; the other seven all part_of = drum_kit's id
--
--   select count(*) from equipment where category='batería' and part_of is null;
--     -> 1
-- =============================================================================
