# Contributing to CraftProfit

Thanks for helping. This page explains how to set up, test and propose a change. For how the addon works, read the [technical documentation](docs/technical.md) first.

## What helps most

- **Bug reports** with the game build, what you did, what you expected and any Lua error text. Use the issue templates.
- **Measurements from the real client.** The beta changes; a result from `/cpp ...` or a screenshot of a wrong number is worth more than a guess.
- **Translation fixes** for French and Spanish (see [below](#adding-or-fixing-a-language)).
- **Disenchant data checked in game** (see [Disenchant data](#disenchant-data)).

## Setup

You need a copy of the game with the Forever beta, plus:

- [LuaJIT](https://luajit.org/) to run the tests, and [luacheck](https://github.com/lunarmodules/luacheck) for static analysis (`brew install luajit luacheck` on macOS, `apt install luajit lua-check` on Debian or Ubuntu).

```sh
git clone https://github.com/Renaud-Sto/CraftProfit.git
cd CraftProfit
sh tests/check.sh        # tests then luacheck; must end with 0 failed and 0 warnings
```

### Run the addon from your clone

Symlink the addon folder (the one containing `CraftProfit.toc`) into the game, so every change is loaded with `/reload`:

```sh
ln -s "$PWD/CraftProfit" "/Applications/World of Warcraft/_classic_beta_/Interface/AddOns/CraftProfit"
```

Whichever branch is checked out in your clone is the code the game loads. A new file or a change to the `.toc` needs a full game restart, not just `/reload`. Enable error messages with `/console scriptErrors 1`.

### The probe addon

When you need to know what the real client returns, use the throwaway probe instead of guessing:

```sh
ln -s "$PWD/probe/CraftProfitProbe" "/Applications/World of Warcraft/_classic_beta_/Interface/AddOns/CraftProfitProbe"
```

Run `/cpp` for the commands, then `/reload`: the output is written to `WTF/Account/<id>/SavedVariables/CraftProfitProbe.lua`. Record what you learn in [docs/probe-findings.md](docs/probe-findings.md). Do not ship the probe.

## Workflow

1. Create a branch from `main`: `feat/...`, `fix/...` or `docs/...`.
2. Make the change **with tests**: pure logic gets a unit test, a UI or adapter change gets a test against the fake game environment (`tests/fakewow.lua`). A bug fix starts with a test that fails.
3. Run `sh tests/check.sh`. Both parts must pass with no warning.
4. Update the [in-game checklist](docs/in-game-checklist.md) when behaviour you cannot test offline changes, the [user guide](docs/user-guide.md) (and its French version) when the interface changes, and the [changelog](CHANGELOG.md).
5. Open a pull request against `main` using the template. Say what you verified in game and what you could not.

Important changes go through a pull request; `main` stays releasable.

### Commits

Short imperative subject with a type prefix: `feat:`, `fix:`, `docs:`, `test:`, `refactor:`, `chore:`. Explain the *why* in the body when it is not obvious. One logical change per commit.

## Code conventions

- Lua 5.1 only (what the game runs). No `goto`, no integer division, no `table.unpack`.
- Logic that decides a number has **no WoW API call**; put game calls in `AHAdapter.lua`, `TradeAdapter.lua` or `UI/`.
- Every value read from the game is checked (`issecretvalue`, type, finiteness) before use, and risky calls are wrapped in `pcall`.
- **Never divide by a literal zero**, and guard every divisor: the client raises "Division by zero". A test enforces the literal case.
- A missing price is `nil`, displayed `?`. Never turn an unknown into 0.
- No user-facing string outside `Locales/`. Match the style of the surrounding code, including comment density.
- Declare every game global you read in `.luacheckrc`.

## Adding or fixing a language

1. Strings live in `CraftProfit/Locales/<code>.lua`. `enUS.lua` is the reference.
2. Each language must define exactly the same keys as `enUS`, keep the same format specifiers (`%d`, `%s`) and leave no string empty; `tests/test_locale.lua` checks this.
3. To add a language: create the file, add it to `CraftProfit/CraftProfit.toc` after `Locale.lua`, register it with `ns.Locale.register("<code>", {...})`, and add it to the test. Run `/cp locale <code>` in game to review it.
4. Item and recipe names come from the game and must never be translated by hand.

## Disenchant data

`CraftProfit/Data/Disenchant.lua` holds the result tables, currently taken from the Classic tables and marked `UNVERIFIED IN FOREVER` in the source. To verify a bracket, disenchant several items of that level range and compare the materials with the table. The *beta* tag in the window is removed (in the three `LINE_DISENCHANT` strings) once this has been checked.

## Releasing

See [docs/curseforge/submission-checklist.md](docs/curseforge/submission-checklist.md).
