# Ideas after 1.0

Status: ideas the author validated for later (2026-10-12). They are not commitments, have no version or date, and each one needs its own design and plan before any code is written.

## Craft or buy

For a reagent the character can craft, use whichever is cheaper: buying it at the auction house or crafting it from its own reagents. Look at most 3 levels deep, for example Bronze Bar from Copper Bar and Tin Bar from ore.

- The interface **must show where a price comes from**, for example "Bronze Bar 2s (crafted) vs 3s at the AH". Otherwise the player sees a price lower than the auction house and cannot tell why.
- Open questions:
  - which recipes the character knows: the leveling list already stores them per profession;
  - cycles (a recipe that uses its own output somewhere down the chain);
  - quantities produced per craft;
  - whether the price history should record the crafted cost or the bought cost.

## Vendor prices

- Learn the price of every item sold by a merchant the player opens, and keep a seed table of common vendor reagents.
- For a reagent sold by a vendor, the vendor price caps the auction house price: nobody should pay more at the AH.
- The history cost function (`HistoryView.recipeDays`, through its price lookup) takes a replaceable price function, so the vendor cap can slot in without rewriting it.

## Estimated sales per day

- Built from the volume completeness flag (decision 11 of the price history design): only complete measurements count.
- Proposed rule: add up the drops in the quantity on offer between consecutive complete days, then divide by the days that passed. It needs at least 3 complete days spanning 6 hours or more; with less data, nothing is shown.
- Shown in the history window's key figures as "about N per day (high estimate)". It is a high estimate because expired and cancelled auctions also make the quantity drop. New postings between two measurements hide some sales, so the figure is a rough indication, not a measurement.

## Item tooltip lines

- Optional lines in item tooltips:
  - the AH price and its age;
  - the vendor price;
  - the craft cost.
- Each line has its own check box in the options window, so CraftProfit does not repeat what another addon already shows.
- Implemented with `TooltipDataProcessor.AddTooltipPostCall`, with no hooks on Blizzard methods. This must be checked on Forever with the probe first.

## Another addon named CraftProfit

A second addon named CraftProfit exists: MIT licence, by another author. Some of the ideas above were noted while reading it. Its code is never copied: any feature here is designed and written from scratch for this addon.
