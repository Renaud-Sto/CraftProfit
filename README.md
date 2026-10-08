# CraftProfit

[![CI](https://github.com/Renaud-Sto/CraftProfit/actions/workflows/ci.yml/badge.svg)](https://github.com/Renaud-Sto/CraftProfit/actions/workflows/ci.yml)
![Interface 16001](https://img.shields.io/badge/WoW%20Forever-Interface%2016001-blue)
![Languages](https://img.shields.io/badge/languages-EN%20%7C%20FR%20%7C%20ES-informational)

**See what a profession recipe really costs at the auction house, and whether to sell, vendor or disenchant the result.**

CraftProfit is an addon for **World of Warcraft: Forever**. Select a recipe you know and a small window next to your profession window adds up the reagents at auction house prices, then compares the three ways to get rid of the crafted item: auction house (net of the commission), vendor, and disenchant. It names the best one, so you can level a profession at the smallest loss, or look for a profit.

*[Lisez-moi en français](README.fr.md)*

> **Status: early beta (0.1.0).** Built and tested on the WoW: Forever beta (build 1.60.1, Interface 16001). Disenchant data still comes from the Classic tables and is marked *beta* in the window. See [Known limitations](docs/user-guide.md#known-limitations).

<!-- Screenshots arrive with the UI rework: docs/images/ -->

## Features

- **Recipe cost** from live auction house prices, with the reagent detail unfolded under the total.
- **Three exits compared**: auction house (after the 5 % commission), vendor price, and the expected disenchant value.
- **Best option highlighted**, with the net result of the craft.
- **Cost per skill point** (optional): what each point of skill really costs, from the colour of the recipe, shown as a gain when the crafts pay for themselves.
- **Several crafts at once**: multiply a recipe by 1 to 9999 crafts.
- **Pinned recipes** (up to 12 per character), sorted by profit or by cost per point, to compare what to craft next.
- **Auction house tools**: one button prices every pinned recipe, another scans the whole auction house. Click a reagent to search it in the auction house, quantity already filled in. CraftProfit never buys anything for you.
- **Price history** (recording): tick *Track history* on up to 15 recipes and CraftProfit keeps their prices scan after scan, per realm and faction. The graphs come later.
- **Standalone**: no Auctionator, no other addon required. It also picks up the scans other addons start.
- **English, French and Spanish** (follows the game language).

## Install

1. Download the latest release (CurseForge page and GitHub Releases will be linked here at the first release), or clone this repository.
2. Copy the `CraftProfit` folder (the one that contains `CraftProfit.toc`) into  
   `World of Warcraft/_classic_beta_/Interface/AddOns/`  
   so that you end up with `.../AddOns/CraftProfit/CraftProfit.toc`.
3. Start the game and check that **CraftProfit** is enabled in the AddOns list. Type `/cp selftest`: it should answer *Self-test passed*.

Developers can symlink the folder instead of copying it, see [CONTRIBUTING.md](CONTRIBUTING.md).

## Quick start

1. Open a profession window and select a recipe you know. The CraftProfit window appears on its right.
2. Go to the auction house, press **Search prices** (prices the pinned recipes) or **Scan AH** (prices everything, once per 15 minutes).
3. Pin the recipes you are interested in with the **Pin** button, then compare them from the pinned list.

The full walkthrough, every option and the explanation of each number are in the [User guide](docs/user-guide.md).

## Commands

| Command | Effect |
| --- | --- |
| `/cp` or `/craftprofit` | Show the command list |
| `/cp show` / `hide` | Show or hide the window |
| `/cp reset` | Put the window back next to the profession or auction house window |
| `/cp scan` | Start a full auction house scan (auction house open) |
| `/cp history` | List the tracked recipes; `/cp history remove <n>` deletes one |
| `/cp locale <code>` | Force a language (`enUS`, `frFR`, `esES`, `esMX`); without code, back to the game language |
| `/cp selftest` | Run the built-in self-test |

## Documentation

| Document | For whom | Content |
| --- | --- | --- |
| [User guide](docs/user-guide.md) ([FR](docs/user-guide.fr.md)) | Players | Every feature, how each number is computed, options, FAQ, troubleshooting |
| [Technical documentation](docs/technical.md) | Developers | Architecture, data flow, price model, saved variables, game API used, measured behaviour of the beta |
| [Contributing](CONTRIBUTING.md) | Contributors | Setup, tests, probe addon, pull request workflow, adding a language |
| [Changelog](CHANGELOG.md) | Everyone | What changed in each version |
| [In-game checklist](docs/in-game-checklist.md) | Testers | What to verify in the client before a release |
| [Probe findings](docs/probe-findings.md) | Developers | What the in-game probe measured |
| [CurseForge material](docs/curseforge/) | Maintainers | Project page text and submission checklist |
| [Design history](docs/superpowers/) | Developers | The original design and implementation plan |

## Alternatives

CraftProfit is deliberately small: it answers "what does this recipe cost, and what do I do with the result?". For a broader profession dashboard with leveling guides, crafting queues and shopping lists, look at Forever Profession Master on CurseForge. The two do not conflict.

## Contributing

Bug reports, translation fixes and pull requests are welcome. Read [CONTRIBUTING.md](CONTRIBUTING.md) first, and use the issue templates. Security issues: see [SECURITY.md](SECURITY.md).

## License

[MIT](LICENSE). The disenchant data is derived from a CC BY-SA 4.0 source, see [Credits and data sources](#credits-and-data-sources).

## Credits and data sources

- Disenchant result tables are derived from the Classic tables of [Warcraft Wiki](https://warcraft.wiki.gg/wiki/Disenchanting_tables) (text and data licensed CC BY-SA 4.0) and are being replaced by measurements from Forever.
- Item and recipe data, names and icons belong to Blizzard Entertainment and come from the game at run time; none is stored in this repository.

## Disclaimer

CraftProfit is a fan-made addon. It is not affiliated with or endorsed by Blizzard Entertainment. World of Warcraft is a trademark of Blizzard Entertainment, Inc.
