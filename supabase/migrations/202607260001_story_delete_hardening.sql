-- Story authors must retain the ability to remove content they published,
-- even if their club role changes after publishing. The author check prevents
-- officials from deleting stories created by other people.
drop policy if exists stories_official_delete on public.stories;
create policy stories_official_delete
on public.stories for delete to authenticated
using (author_id=(select auth.uid()));
