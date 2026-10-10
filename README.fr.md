# CraftProfit

[![CI](https://github.com/Renaud-Sto/CraftProfit/actions/workflows/ci.yml/badge.svg)](https://github.com/Renaud-Sto/CraftProfit/actions/workflows/ci.yml)
![Interface 16001](https://img.shields.io/badge/WoW%20Forever-Interface%2016001-blue)
![Langues](https://img.shields.io/badge/langues-EN%20%7C%20FR%20%7C%20ES-informational)

**Voyez ce que coûte vraiment une recette de métier à l'hôtel des ventes, et s'il vaut mieux vendre, revendre au marchand ou désenchanter le résultat.**

CraftProfit est un addon pour **World of Warcraft: Forever**. Sélectionnez une recette que vous connaissez : une petite fenêtre à côté de la fenêtre de métier additionne les composants aux prix de l'hôtel des ventes, puis compare les trois façons de se débarrasser de l'objet obtenu : l'hôtel des ventes (net de la commission), le marchand et le désenchantement. Elle désigne la meilleure, pour monter un métier en perdant le moins possible, ou pour chercher un profit.

*[Read this in English](README.md)*

> **État : bêta précoce (0.1.0).** Développé et testé sur la bêta de WoW: Forever (build 1.60.1, Interface 16001). Les données de désenchantement viennent encore des tables du Classic et sont marquées *bêta* dans la fenêtre. Voir les [limites connues](docs/user-guide.fr.md#limites-connues).

<!-- Les captures d'écran arrivent avec la refonte de l'interface : docs/images/ -->

## Fonctionnalités

- **Coût d'une recette** aux prix réels de l'hôtel des ventes, avec le détail des composants sous le total.
- **Trois débouchés comparés** : hôtel des ventes (après la commission de 5 %), prix marchand et valeur espérée du désenchantement.
- **Meilleure option mise en évidence**, avec le résultat net du craft.
- **Coût par point de compétence** (optionnel) : ce que coûte vraiment chaque point, d'après la couleur de la recette, affiché comme un gain quand les crafts se paient d'eux-mêmes.
- **Fenêtre de montée de métier** : toutes les recettes que vous connaissez dans un métier, classées par coût du point de compétence, pour voir quoi fabriquer ensuite.
- **Plusieurs crafts d'un coup** : multipliez une recette de 1 à 9999 crafts.
- **Recettes épinglées** (12 par personnage au maximum), triées par gain ou par coût par point, pour comparer quoi fabriquer ensuite.
- **Outils d'hôtel des ventes** : un bouton chiffre toutes les recettes épinglées, un autre scanne tout l'hôtel des ventes. Cliquez sur un composant pour le rechercher à l'hôtel des ventes, quantité déjà remplie. CraftProfit n'achète jamais rien à votre place.
- **Historique des prix** (enregistrement) : cochez *Suivre l'historique* sur 15 recettes au plus et CraftProfit garde leurs prix scan après scan, par ruleset (le « royaume » de la bêta) et par faction. Les graphiques viendront ensuite.
- **Autonome** : ni Auctionator ni aucun autre addon n'est nécessaire. Il récupère aussi les scans lancés par d'autres addons.
- **Fenêtre d'options et bouton de la minicarte** : choisissez l'apparence des fenêtres (bandeau des sections et cases de prix), appliquée aussitôt ; ouvrez-la depuis le bouton de la minicarte, le compartiment d'addons ou `/cp options`.
- **Anglais, français et espagnol** (selon la langue du jeu).

## Installation

1. Téléchargez la dernière version (les liens CurseForge et GitHub Releases seront ajoutés ici à la première publication), ou clonez ce dépôt.
2. Copiez le dossier `CraftProfit` (celui qui contient `CraftProfit.toc`) dans  
   `World of Warcraft/_classic_beta_/Interface/AddOns/`  
   pour obtenir `.../AddOns/CraftProfit/CraftProfit.toc`.
3. Lancez le jeu et vérifiez que **CraftProfit** est activé dans la liste des addons. Tapez `/cp selftest` : la réponse doit être *Auto-test réussi*.

Les développeurs peuvent utiliser un lien symbolique plutôt qu'une copie, voir [CONTRIBUTING.md](CONTRIBUTING.md).

## Démarrage rapide

1. Ouvrez une fenêtre de métier et sélectionnez une recette que vous connaissez. La fenêtre CraftProfit apparaît à sa droite.
2. À l'hôtel des ventes, appuyez sur **Rechercher les prix** (chiffre les recettes épinglées) ou sur **Scanner l'HV** (chiffre tout, une fois par tranche de 15 minutes).
3. Épinglez les recettes qui vous intéressent avec le bouton **Épingler**, puis comparez-les dans la liste.

Le pas-à-pas complet, toutes les options et l'explication de chaque chiffre sont dans le [guide de l'utilisateur](docs/user-guide.fr.md).

## Commandes

| Commande | Effet |
| --- | --- |
| `/cp` ou `/craftprofit` | Affiche la liste des commandes |
| `/cp show` / `hide` | Affiche ou masque la fenêtre |
| `/cp reset` | Remet la fenêtre à côté de la fenêtre de métier ou de l'hôtel des ventes |
| `/cp options` | Ouvre ou ferme la fenêtre d'options (apparence des fenêtres, bouton de la minicarte, commandes) |
| `/cp minimap` | Masque le bouton de la minicarte, ou le rétablit |
| `/cp scan` | Lance un scan complet de l'hôtel des ventes (hôtel des ventes ouvert) |
| `/cp history` | Liste les recettes suivies ; `/cp history remove <n>` en supprime une |
| `/cp level` | Ouvre ou ferme la fenêtre de montée de métier |
| `/cp market` | Indique sous quel marché (ruleset et faction) les prix sont enregistrés |
| `/cp theme [nom]` | Liste les thèmes et le thème actuel ; avec un nom, passe à ce thème (`gold`, `copper`, `steel` : Or, Cuivre, Bleu acier) |
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
| [Historique de conception](docs/superpowers/) | Développeurs | La conception d'origine et le plan d'implémentation |

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
