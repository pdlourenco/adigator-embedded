# Monte-Carlo regression reproducers

Auto-generated `mcreg_*.m` files land here when `mcCampaign` (or `mcPromote`)
turns a failing random case into a deterministic reproducer (issue #38,
[ADR-0007](../../../docs/decisions/ADR-0007-montecarlo-vv.md)).

Each file is a data function returning the frozen case (`name`, `body`,
`xsize`, `deriv`, `x0`, the producing `seed`, and — when the generator had a
closed form — the `expected` derivative value). `MCRegressionTest` discovers
every reproducer here and re-checks it: the structural and cross-mode oracles
must pass, and any frozen `expected` value must still match.

Commit the reproducer that a campaign discovers — that is what converts a
non-deterministic finding into permanent, gated-on-merge coverage. Do **not**
hand-edit these files; regenerate from the recorded seed if needed.
