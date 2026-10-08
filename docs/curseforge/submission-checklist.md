# CurseForge submission checklist

What CurseForge expects, and what is still to do for CraftProfit. Sources: the CurseForge project submission guidelines, the BigWigs packager documentation, and a look at comparable Forever and Retail profession addons (for example *Forever Profession Master*, *Profession Helper: AH Profits*, *CraftSimulator*).

## What comparable addons show

Their pages share a structure: a one-sentence summary, **Features**, **Usage** (3 steps), **Slash commands**, **Compatibility**, **Good to know** (limits stated plainly), an FAQ on the larger ones, and the author card. Most use the categories *Professions* and *Auction & Economy*, an open-source license (MIT is common) and 3 to 5 screenshots. Forever addons state "WoW Forever, Interface 16001" and the Forever game version. [project-page.md](project-page.md) follows this structure.

## Requirements and status

| Item | Requirement | Status |
| --- | --- | --- |
| Project name | English, unique, no game name or version number | `CraftProfit`: OK |
| Summary | One sentence, no "best" claim, no keyword list | Drafted |
| Description | English first, says what it does and how; promotional links at the bottom only | Drafted |
| Icon | 400 × 400 px minimum, square PNG, original, not a solid colour, not a Blizzard asset | **To do** |
| Screenshots | Real in-game images, titled | **To do** (after the UI rework) |
| License | You own the content or may redistribute it; chosen on the project form | **Decision needed** |
| Categories | Professions; Auction & Economy | Chosen |
| Game version | Forever, 1.60.1 | To confirm in the upload form; the TOC says Interface 16001 |
| Changelog | Required with every file | [CHANGELOG.md](../../CHANGELOG.md) |
| Release type | Alpha, beta or release | Start with **beta** (early beta addon on a beta game) |
| Source / issues links | Recommended | GitHub, in the description |
| Author name | Shown on the page | `Sto` (TOC `## Author` updated); use the same name on the CurseForge account |

## License decision

CraftProfit has no license file yet, which means *all rights reserved* by default: nobody may legally reuse or redistribute it, and CurseForge will ask which license applies. Common choices for addons: **MIT** (permissive, used by the comparable addons above), **GPL-3.0** (forks must stay open), **All Rights Reserved**. This is the owner's decision. Once chosen: add `LICENSE`, state it in the README (both languages), and select the same one on the CurseForge form.

### Data source of the disenchant tables

`Data/Disenchant.lua` was built from the Classic tables of Warcraft Wiki, whose text and data are licensed **CC BY-SA 4.0** (attribution required, derivative works under the same license). Drop rates and quantities are game facts, which copyright generally does not protect, and the file is restructured and attributed in its header, but this is not legal advice. The safest course, and the plan anyway because the tables are unverified in Forever, is to **replace them with your own in-game measurements before the first release**. Until then keep the attribution in the README (done) and in the file header.

## Before the first upload

1. Choose and add the license.
2. Create the icon and the screenshots (after the interface rework).
3. Run the [in-game checklist](../in-game-checklist.md) on the current beta build; retest on the launch build (4 November 2026), the `Interface` number may change. Verify it with `/dump select(4, GetBuildInfo())` and list several values in the TOC if you support more than one build.
4. Update the version in `CraftProfit/CraftProfit.toc`, [CHANGELOG.md](../../CHANGELOG.md) and the README status line.
5. Have a French and a Spanish speaker read the translations.

## Releasing

### Manual (first release)

1. Zip the `CraftProfit` folder (the one with `CraftProfit.toc`) so the archive contains a single top folder `CraftProfit/`:  
   `cd CraftProfit/.. && zip -r CraftProfit-0.1.0.zip CraftProfit -x "*.DS_Store"`
2. Upload it on the CurseForge project, with the changelog text, release type *beta*, game version *Forever 1.60.1*.
3. Create a GitHub release with the same file.

### Automatic (afterwards)

The [BigWigs packager](https://github.com/BigWigsMods/packager) builds the zip from a tag and uploads it to CurseForge, and can also create the GitHub release.

1. On CurseForge, find the **Project ID** ("About This Project") and add `## X-Curse-Project-ID: <id>` to the TOC.
2. Create an API token at `https://wow.curseforge.com/account/api-tokens` and add it as the repository secret `CF_API_KEY`.
3. `CraftProfit/.pkgmeta` already holds `package-as: CraftProfit`. Because the addon is in a subfolder of the repository, the packager must be told the top level with `-t CraftProfit`.
4. Add `.github/workflows/release.yml`:

```yaml
name: Release

on:
  push:
    tags: ['**']

jobs:
  release:
    runs-on: ubuntu-latest
    env:
      CF_API_KEY: ${{ secrets.CF_API_KEY }}
      GITHUB_OAUTH: ${{ secrets.GITHUB_TOKEN }}
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0
      - uses: BigWigsMods/packager@v2
        with:
          args: -t CraftProfit
```

5. Tag and push: `git tag v0.1.0 && git push origin v0.1.0`. The release type comes from the tag name: a plain `v0.1.0` is a release, `v0.1.0-beta1` a beta, anything untagged an alpha.

**Untested:** the `-t` option and the detection of the *Forever* game version by the packager have not been tried on this repository. If the upload picks the wrong game version, pass it explicitly with `-g 1.60.1` or fall back to the manual upload. Do the first release by hand and automate the second.

Note: a tag pushed together with the very first workflow file does not trigger it; push another tag.

## After the release

- Add the CurseForge and GitHub release links to the README (both languages).
- Watch the comments and issues for the first reports; the build number in the bug template saves a round trip.
- Translations of the CurseForge description can be added *below* the English text.
