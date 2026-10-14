# CraftProfit

[![CI](https://github.com/Renaud-Sto/CraftProfit/actions/workflows/ci.yml/badge.svg)](https://github.com/Renaud-Sto/CraftProfit/actions/workflows/ci.yml)
![Interface 16001](https://img.shields.io/badge/WoW%20Forever-Interface%2016001-blue)
![Langues](https://img.shields.io/badge/langues-EN%20%7C%20FR%20%7C%20ES-informational)

**Voyez ce que coûte vraiment une recette de métier à l'hôtel des ventes, et s'il vaut mieux vendre, revendre au marchand ou désenchanter le résultat.**

CraftProfit est un addon pour **World of Warcraft: Forever**. Sélectionnez une recette que vous connaissez : une petite fenêtre à côté de la fenêtre de métier additionne les composants aux prix de l'hôtel des ventes, puis compare les trois façons de se débarrasser de l'objet obtenu : l'hôtel des ventes (net de la commission), le marchand et le désenchantement. Elle désigne la meilleure, pour monter un métier en perdant le moins possible, ou pour chercher un profit.

*[Read this in English](README.md)*

> **État : version 1.1.0, pour la bêta de WoW: Forever** (build 1.60.1, Interface 16001), sur laquelle elle a été développée et testée. Les données de désenchantement viennent encore des tables du Classic et sont marquées *bêta* dans la fenêtre. Voir les [limites connues](docs/user-guide.fr.md#limites-connues).

## Captures d'écran

![La fenêtre principale à l'hôtel des ventes, avec la liste épinglée dessous](docs/screenshots/01-main-window.png)
![La fenêtre des recettes épinglées](docs/screenshots/02-pinned-window.png)
![La fenêtre de montée de métier](docs/screenshots/03-leveling.png)
![La fenêtre d'options](docs/screenshots/04-options.png)

(Captures du client en anglais.)

## Fonctionnalités

- **Coût d'une recette** aux prix réels de l'hôtel des ventes, avec le détail des composants sous le total.
- **Trois débouchés comparés** : hôtel des ventes (après la commission de 5 %), prix marchand et valeur espérée du désenchantement.
- **Meilleure option mise en évidence**, avec le résultat net du craft.
- **Profit dans la fenêtre de métier** : chaque recette apprise qui a des prix affiche ce qu'un craft rapporte ou coûte à droite de sa ligne dans la liste des recettes (`+12` argent `23` cuivre (icônes de pièces) en vert, `-2` argent en rouge) ; désactivable dans la fenêtre d'options.
- **Coût par point de compétence** (optionnel) : ce que coûte vraiment chaque point, d'après la couleur de la recette, affiché comme un gain quand les crafts se paient d'eux-mêmes.
- **Fenêtre de montée de métier** : toutes les recettes que vous connaissez dans un métier, classées par coût du point de compétence, pour voir quoi fabriquer ensuite.
- **Plusieurs crafts d'un coup** : multipliez une recette de 1 à 9999 crafts.
- **Recettes épinglées** (20 par personnage par défaut ; 12, 20, 30 ou 40 dans la fenêtre d'options), triées par gain ou par coût par point, pour comparer quoi fabriquer ensuite (avec beaucoup d'épingles, **Scanner l'HV** va souvent plus vite que **Actualiser épinglées**) ; sous la fenêtre principale à l'hôtel des ventes, et partout dans leur propre fenêtre (`/cp pins` ou un clic droit sur le bouton de la minicarte).
- **Outils d'hôtel des ventes** : **Actualiser recette** chiffre la recette affichée en quelques secondes, **Actualiser épinglées** chiffre toutes les recettes épinglées, **Scanner l'HV** lit tout l'hôtel des ventes ; un prix manqué est redemandé une seconde fois automatiquement. Cliquez sur un composant pour le rechercher à l'hôtel des ventes, quantité déjà remplie, ou sur l'objet obtenu pour voir combien sont en vente. CraftProfit n'achète jamais rien à votre place.
- **Historique des prix** : cochez *Suivre l'historique* sur 30 recettes au plus et CraftProfit garde leurs prix scan après scan (chaque point pendant 7 jours, un par jour pendant 60 jours) ; la fenêtre **Historique** les affiche sur 7, 30 ou 60 jours (coût des composants, prix de vente ou bénéfice : une barre par jour, le prix habituel, une semaine type, et une phrase simple qui dit si aujourd'hui est moins cher ou plus cher que d'habitude), et sa liste dit en vert ou en rouge si le coût des composants et la valeur de vente les plus récents sont meilleurs ou moins bons que d'habitude ; les mêmes pourcentages s'affichent dans la fenêtre principale, à côté du total des Composants et sur la tuile HV (NET), avec une infobulle des chiffres qui les fondent. Les prix sont gardés par jeu de règles (le « royaume » de la bêta) et par faction.
- **Autonome** : ni Auctionator ni aucun autre addon n'est nécessaire. Il récupère aussi les scans lancés par d'autres addons.
- **Fenêtre d'options et bouton de la minicarte** : choisissez l'apparence des fenêtres (bandeau des sections et cases de prix), appliquée aussitôt, et la limite de recettes épinglées ; ouvrez-la depuis le bouton de la minicarte, le compartiment d'addons ou `/cp options`.
- **Anglais, français et espagnol** (selon la langue du jeu ; les noms de recettes et de métiers enregistrés la suivent aussi).

## Installation

1. Téléchargez la dernière version sur [GitHub Releases](https://github.com/Renaud-Sto/CraftProfit/releases) (le lien CurseForge sera ajouté ici dès que la page sera en ligne), ou clonez ce dépôt.
2. Copiez le dossier `CraftProfit` (celui qui contient `CraftProfit.toc`) dans  
   `World of Warcraft/_classic_beta_/Interface/AddOns/`  
   pour obtenir `.../AddOns/CraftProfit/CraftProfit.toc`.
3. Lancez le jeu et vérifiez que **CraftProfit** est activé dans la liste des addons. Tapez `/cp selftest` : la réponse doit être *Auto-test réussi*.

Les développeurs peuvent utiliser un lien symbolique plutôt qu'une copie, voir [CONTRIBUTING.md](CONTRIBUTING.md).

## Démarrage rapide

1. Ouvrez une fenêtre de métier et sélectionnez une recette que vous connaissez. La fenêtre CraftProfit apparaît à sa droite.
2. À l'hôtel des ventes, appuyez sur **Actualiser recette** dans la fenêtre principale (la recette affichée, quelques secondes), **Actualiser épinglées** (les recettes épinglées, environ une minute pour 20) ou **Scanner l'HV** (tout, une fois par tranche de 15 minutes).
3. Épinglez les recettes qui vous intéressent avec le bouton **Épingler**, puis comparez-les dans la liste.

Le pas-à-pas complet, toutes les options et l'explication de chaque chiffre sont dans le [guide de l'utilisateur](docs/user-guide.fr.md).

## Commandes

| Commande | Effet |
| --- | --- |
| `/cp` ou `/craftprofit` | Affiche la liste des commandes |
| `/cp show` / `hide` | Affiche ou masque la fenêtre principale |
| `/cp reset` | Remet la fenêtre principale à côté de la fenêtre de métier ou de l'hôtel des ventes |
| `/cp options` | Ouvre ou ferme la fenêtre d'options (apparence des fenêtres, limite de recettes épinglées, bouton de la minicarte, commandes) |
| `/cp minimap` | Masque le bouton de la minicarte, ou le rétablit |
| `/cp scan` | Lance un scan complet de l'hôtel des ventes (hôtel des ventes ouvert) |
| `/cp history` | Ouvre la fenêtre d'historique (`/cp history <n>` : sur la n-ième recette suivie) ; `/cp history list` liste les recettes suivies, `/cp history remove <n>` en supprime une |
| `/cp pins` | Ouvre ou ferme la fenêtre des recettes épinglées (partout, derniers prix connus) |
| `/cp level` | Ouvre ou ferme la fenêtre de montée de métier |
| `/cp market` | Indique sous quel marché (jeu de règles et faction) les prix sont enregistrés |
| `/cp locale <code>` | Force une langue (`enUS`, `frFR`, `esES`, `esMX`) ; sans code, retour à la langue du jeu |
| `/cp selftest` | Lance l'auto-test intégré |

## Documentation

| Document | Pour qui | Contenu |
| --- | --- | --- |
| [Guide de l'utilisateur](docs/user-guide.fr.md) ([EN](docs/user-guide.md)) | Joueurs | Toutes les fonctions, calcul de chaque chiffre, options, FAQ, dépannage |
| [Documentation technique](docs/technical.md) (en anglais) | Développeurs | Architecture, flux de données, modèle de prix, variables sauvegardées, API du jeu utilisée, comportement mesuré de la bêta |
| [Contribuer](CONTRIBUTING.md) | Contributeurs | Installation, tests, addon sonde, processus de pull request, ajout d'une langue |
| [Journal des modifications](CHANGELOG.md) | Tout le monde | Ce qui change à chaque version |
| [Liste de vérifications en jeu](docs/in-game-checklist.md) | Testeurs | Quoi vérifier dans le client avant une publication |
| [Mesures de la sonde](docs/probe-findings.md) | Développeurs | Ce que la sonde en jeu a mesuré |
| [Matériel CurseForge](docs/curseforge/) | Mainteneurs | Texte de la page du projet et liste de soumission |
| [Historique de conception](docs/superpowers/) | Développeurs | Les spécifications de conception et les plans d'implémentation |

## Alternatives

CraftProfit est volontairement petit : il répond à « combien coûte cette recette, et que faire du résultat ? ». Pour un tableau de bord de métiers plus large, avec guides de montée, files de fabrication et listes de courses, regardez Forever Profession Master sur CurseForge. Les deux ne se gênent pas.

## Contribuer

Les rapports de bugs, corrections de traduction et pull requests sont les bienvenus. Lisez d'abord [CONTRIBUTING.md](CONTRIBUTING.md) et utilisez les modèles de tickets. Problèmes de sécurité : voir [SECURITY.md](SECURITY.md).

## Licence

[MIT](LICENSE). Les données de désenchantement sont dérivées d'une source CC BY-SA 4.0, voir [Crédits et sources de données](#crédits-et-sources-de-données).

## Crédits et sources de données

- Les tables de résultats du désenchantement sont dérivées des tables Classic de [Warcraft Wiki](https://warcraft.wiki.gg/wiki/Disenchanting_tables) (texte et données sous licence CC BY-SA 4.0) et seront remplacées par des mesures faites dans Forever.
- Les données, noms et icônes des objets et des recettes appartiennent à Blizzard Entertainment et viennent du jeu à l'exécution ; rien n'est stocké dans ce dépôt.

## Avertissement

CraftProfit est un addon de fan. Il n'est ni affilié à Blizzard Entertainment ni approuvé par elle. World of Warcraft est une marque de Blizzard Entertainment, Inc.
