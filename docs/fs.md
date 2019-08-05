# Georgios File System Design

Georgios ultimate purpose is to be a host for a experimental file system based
on tags called DragonFS.

# Case Study 1

The basis of DragonFS usage, at least at first, be will be a unnamed website,
with an advanced tagging system for content. This is a summery of the system
along with my comments.

 - `foo`: Content tagged with `foo`.
 - `a b`: Content tagged with both `a` and `b`.
 - `~a ~b`: Content tagged with at least `a` or `b`.
   - A infix operator is tempting here
 - `not_interesting`: Tags must can't have spaces.
   - Simplifies a lot by restricting the tag, but it would be nice to have
     arbitary tags.
 - `a -b`: Content tagged with `a`, but not `b`
   - Simple, Google-like, hard to say no to it.
 - `taxes_*`: Wildcard, would match `taxes_2021` or `taxes_1998`.
   - The Website restricts usage of this and for good reason. I would have to
     see.
 - `metatag:expr` is where things get interesting. Content can be filtered by
   date ranges, user, and other metadata.
    - Expression examples:
      - `>100`, `<=100`: Integer Ranges
      - `2019-08-04`, `today`, `5_days_ago`, `today..5_years_ago`: dates and
        date ranges
      - Hashes
      - `order:score`: Order by the score attribute
    - This will be implemented in some way into DragonFS

TODO: More Case Studies
