# PiasaFS

Georgios ultimate purpose is to be a host for a experimental file system based
on tags called [Piasa](https://en.wikipedia.org/wiki/Piasa)FS (pronounced
*PIE-A-SAW*).

There are what could be thought of "wrappers" for traditional file systems to
use tag based systems like TMSU and Tagsistant. The goal of this project will
not be to be preferable over them for everyday use (certainly not possible to
do at the current rate and with my abilities), but to see what a native file
system build around tags could look like and how the rest of the OS could or
couldn't leverage that.

## Design Notes

 - Might need some sort of nested namespaces for the system and applications to
   use privately.
 - Will need a compatibility layer with software expecting a traditional file
   system. For `fopen` at least, Clib could default to the traditional mode,
   unless the `fopen` was given a special token in the mode parameter.

### Notes on Existing Semantic Systems

#### Unnamed Website

The basis of PiasaFS usage, at least at first, will be a unnamed website, with
an advanced tagging system for content. This is a summery of the system along
with my comments.

 - `foo`: Content tagged with `foo`.
 - `a b`: Content tagged with both `a` and `b`.
 - `~a ~b`: Content tagged with at least `a` or `b`.
   - A infix operator is tempting here
 - `not_interesting`: Tags can't have spaces.
   - Simplifies syntax a lot, but it would be nice to have arbitrary tags.
 - `a -b`: Content tagged with `a`, but not `b`
   - Simple, Google-like, hard to say no to it.
 - `taxes_*`: Wildcard, would match `taxes_2021` or `taxes_1998`.
   - The Website restricts usage of this and for good reason. I would have to
     see.
 - `METATAG:EXPR` is where things get interesting. Content can be filtered by
   date ranges, user, and other metadata.
    - Expression examples:
      - `>100`, `<=100`: Integer Ranges
      - `2019-08-04`, `today`, `5_days_ago`, `today..5_years_ago`: dates and
        date ranges
      - Hashes
      - `order:ATTRIBUTE`: Order by an attribute
    - Will be implemented in some way into PiasaFS

#### Other Things to Research

 - [RDF](https://en.wikipedia.org/wiki/Resource_Description_Framework)

## Also See

- [Wikipedia: "Semantic file system"](https://en.wikipedia.org/wiki/Semantic_file_system)
