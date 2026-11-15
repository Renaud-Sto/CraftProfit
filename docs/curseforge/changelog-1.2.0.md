**1.2.0** (WoW Forever 1.60.1)

Fixed
- Materials sold by vendors are now counted at the vendor price when it is cheaper than the auction house: a Leaded Vial at 4s 88c on the auction house but 40c at a vendor counts 40c. A vendor material with no auction house listing no longer leaves the cost unknown. This applies everywhere: the main window, the profit shown on each recipe of the profession window, the pinned list, the leveling list and the price history. Thanks for the report!
- An amount that only just fitted a tile (for example 43s 70c) is no longer cut to "43 70...".

Added
- Vendor prices are learnt at every merchant you open (account wide, items sold for gold in unlimited supply). Until then, about thirty common materials (vials, threads, dyes, flux, salt, spices, poison materials) use their usual vendor price.
- In the Materials detail, a material counted at the vendor price shows "vendor" beside its price; hover it to see both prices and which one is counted.

Full changelog: https://github.com/Renaud-Sto/CraftProfit/blob/main/CHANGELOG.md
