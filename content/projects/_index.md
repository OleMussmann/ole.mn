+++
title = "Projects"
description = "Projects in various states of polish"
fediverse = "@ole@fosstodon.org"
+++

## [nps](https://github.com/OleMussmann/nps) -- nix package search

Searching for packages in the [`nix`](https://nixos.org/) repository is, shockingly, [far from trivial](https://wiki.nixos.org/wiki/Searching_packages). The available options are varying degrees of slow, and all of them hide the package I'm looking for somewhere in the middle. `nps` caches the package information locally, searches it before the spoon hits the floor, and sorts the results by relevance. This should be the default, no?

## [fleet](https://github.com/OleMussmann/fleet) -- server monitoring

Is the auto-update on `server_a` still working? Is `backup` back on the network? When did I last update my `vm`? Check your machine fleet for:
- reachability,
- auto-update status `aut`,
- OS version (config commit hash),
- number of generations `gen`, and
- last `built` time.

Bonus: the information trickles in async in matrix-style, which makes you feel like a hacker. Currently in a "works-for-me" status. I might turn it into a proper package/service if there's demand.

```
$ fleet
╭────────────┬───┬────────────┬─────┬────────────╮
│    machine │aut│ v 07fe2ad1 │ gen │ last built │
├────────────┼───┼────────────┼─────┼────────────┤
│  this_pc • │   │ 07fe2ad1 • │ 207 │   18d 1h ! │
├────────────┼───┼────────────┼─────┼────────────┤
│ server_a • │ • │ 07fe2ad1 • │ 131 │      17h • │
│ server_b • │ • │ 07fe2ad1 • │ 222 │      17h • │
│   backup • │   │ 07fe2ad1 • │ 305 │   12d 8h ! │
│       vm - │   │            │     │            │
╰────────────┴───┴────────────┴─────┴────────────╯
```
