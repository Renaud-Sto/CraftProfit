# Guide de l'utilisateur CraftProfit

*[English version](user-guide.md)* · [Retour au README](../README.fr.md)

CraftProfit vous dit ce que coûte vraiment une recette de métier à l'hôtel des ventes, et ce qu'il faut faire de l'objet obtenu. Ce guide explique chaque partie de la fenêtre, comment chaque chiffre est calculé, et ce que l'addon ne peut pas savoir.

Sommaire : [La fenêtre](#la-fenêtre) · [À l'hôtel des ventes](#à-lhôtel-des-ventes) · [Comment les chiffres sont calculés](#comment-les-chiffres-sont-calculés) · [Options et commandes](#options-et-commandes) · [Langues](#langues) · [Limites connues](#limites-connues) · [FAQ et dépannage](#faq-et-dépannage)

## La fenêtre

Ouvrez une fenêtre de métier et sélectionnez une recette que vous connaissez. Une petite fenêtre apparaît à droite de la fenêtre de métier et suit votre sélection. Vous pouvez la déplacer où vous voulez ; sa position est mémorisée (`/cp reset` la remet en place). Elle se ferme avec la fenêtre de métier, et avec l'hôtel des ventes quand vous l'avez ouverte depuis celui-ci, pour ne jamais encombrer l'écran.

| Ligne | Signification |
| --- | --- |
| **Composants** | Le coût de tous les composants aux prix de l'hôtel des ventes. Cliquez sur la ligne pour replier ou déplier le détail (`-` déplié, `+` replié) ; le choix est mémorisé. |
| **Hôtel des ventes (net)** | Le prix que l'objet obtenu rapporterait à l'hôtel des ventes, après la commission de 5 %. `n/d` si l'objet ne peut pas y être vendu (lié quand ramassé). |
| **Marchand** | Ce que paie un marchand pour l'objet. `n/d` s'il ne peut pas être vendu au marchand. |
| **Désenchantement (bêta)** | La valeur *espérée* du désenchantement, nette de la commission de l'hôtel des ventes sur les composants obtenus. Voir [Désenchantement](#désenchantement). |
| *ligne grise* | Sous la valeur du désenchantement : le résultat le plus probable, par exemple `75%: 1-2x Poussière d'âme = 7s 30c`. Affichée seulement quand le désenchantement a plusieurs résultats possibles. |
| **Coût par point** / **Gain par point** | Seulement quand l'option est cochée. Voir [Coût par point de compétence](#coût-par-point-de-compétence). |
| **Meilleur : …** | La meilleure option et le résultat net du craft (meilleure revente moins les composants), en vert pour un gain et en rouge pour une perte. |
| **Prix : il y a 5min** | L'âge du prix le plus ancien utilisé. Passe en orange au-delà d'une heure. |

La meilleure option est marquée d'un `>` doré devant sa ligne (le vert et le rouge sont réservés aux gains et aux pertes).

Un prix inconnu s'affiche `?`, jamais zéro. S'il manque le prix d'un composant, le total et le verdict indiquent *Incomplet : prix manquants* plutôt qu'un chiffre flatteur.

### Crafts

La case **Crafts** multiplie la recette sélectionnée par un nombre de crafts (de 1 à 9999) : quantités de composants, total des composants, toutes les valeurs de revente et le verdict. Le coût ou gain **par point** et la ligne grise du désenchantement restent par point et par désenchantement. La liste des épingles montre toujours un seul craft, et sélectionner une autre recette remet la case à 1.

Pour de grandes quantités, le total est une estimation : le prix d'un composant est la médiane des offres les moins chères, mais en acheter 100 oblige à passer par des offres plus chères. Le vrai prix apparaît à l'hôtel des ventes quand vous lancez la recherche.

### Suivre l'historique

La case **Suivre l'historique** (à côté de Crafts) fait garder à CraftProfit les prix des composants et du résultat de cette recette au fil du temps. Jusqu'à 15 recettes peuvent être suivies, indépendamment de la liste des épingles. Un point est enregistré après chaque scan et chaque recherche de prix qui touche un objet de la recette, tant que tous les prix nécessaires sont connus. Décocher la case met l'enregistrement en pause et garde ce qui a été enregistré. `/cp history` liste les recettes suivies et `/cp history remove <n>` en supprime une avec son historique. Les prix sont gardés par royaume et par faction : l'historique d'un marché ne se mélange jamais avec un autre. Une vue de l'historique (graphiques, « moins cher que d'habitude ») est prévue ; pour l'instant, les données sont seulement collectées.

### Bouton Épingler

**Épingler** garde la recette dans votre liste d'épingles (12 par personnage au maximum), utilisable même fenêtre de métier fermée. **Désépingler** la retire.

## À l'hôtel des ventes

À l'ouverture de l'hôtel des ventes, la fenêtre affiche la liste **Recettes épinglées** sous la recette, avec deux boutons.

- **Rechercher les prix** chiffre tous les composants et tous les objets obtenus des recettes épinglées, un objet à la fois, avec un compteur de progression. Les prix sont enregistrés avec leur date. Si vous fermez l'hôtel des ventes en cours de route, la recherche est annulée et les prix déjà reçus sont conservés.
- **Scanner l'HV** lit tout l'hôtel des ventes d'un coup (le jeu autorise un scan complet par tranche de 15 minutes et par compte). Il chiffre des milliers d'objets, ce qui permet d'évaluer ensuite n'importe quelle recette. Si un autre addon lance un scan, CraftProfit utilise son résultat sans refaire de demande. Si le serveur ne répond pas, le statut le dit : le délai de 15 minutes est probablement en cours.

### Trier la liste des épingles

Le bouton en haut à droite de la liste bascule entre :

- **Tri : gain** : le craft le plus rentable en premier (le moins déficitaire quand tous perdent de l'argent) ; les recettes sans prix en dernier.
- **Tri : coût/point** : le point de compétence le moins cher en premier. Une recette dont les crafts se paient d'eux-mêmes passe en tête (`+…/pt` en vert), puis les coûts en rouge (`…/pt`), puis les recettes grises (`n/d`, aucun point possible), puis celles sans prix (`?`). Ce mode active l'option du coût par point, et décocher cette option ramène le tri sur le gain.

Cliquez sur une recette de la liste pour l'afficher dans la fenêtre au-dessus.

### Rechercher un composant

Avec le détail des composants déplié, cliquez sur la ligne d'un composant, par exemple `20x Barre de bronze`. CraftProfit ouvre la vue *Acheter* de l'hôtel des ventes, tape le nom de l'objet dans la barre de recherche et lance la recherche. Quand vous ouvrez la vue d'achat de l'objet, la quantité est déjà réglée sur 20 (multipliée par le nombre de crafts). C'est vous qui choisissez l'offre et qui appuyez sur **Acheter** : CraftProfit n'achète jamais rien.

## Comment les chiffres sont calculés

### Prix

Un prix vient des offres de l'hôtel des ventes. Le prix retenu pour un objet est la **médiane du prix unitaire des cinq unités les moins chères**. Une seule offre absurdement basse ne peut pas tirer le prix vers le bas comme le ferait un simple minimum, et les quantités sont bien prises en compte (une offre de 20 unités compte 20 fois).

Deux sources l'alimentent : la recherche ciblée de **Rechercher les prix** et le **Scanner l'HV** complet. L'écriture la plus récente l'emporte ; chaque prix garde sa date. Les prix de plus de deux semaines sont supprimés.

### Hôtel des ventes (net)

`prix × (1 − 0,05)`. La commission de 5 % a été mesurée en jeu sur un courrier de vente (20 Étoffes de laine à 1 argent pièce : 1 argent de commission, dépôt remboursé). Le dépôt est remboursé quand l'objet se vend et n'est pas compté.

### Désenchantement

Valeur espérée = la somme, sur les résultats possibles, de *probabilité × quantité moyenne × prix*, nette de la commission de 5 %. Elle est affichée pour tout objet désenchantable, **que vous ayez ou non l'enchantement** : un objet lié quand équipé peut être désenchanté par un autre joueur ou un autre de vos personnages.

L'exception est un objet **lié quand ramassé** : il ne peut pas changer de mains, donc la ligne n'est affichée (sinon `n/d`) que si votre personnage connaît l'enchantement.

Les tables viennent du Classic et ne sont pas encore vérifiées dans Forever, d'où la mention *bêta*. Les objets épiques au-dessus du niveau d'objet 60 n'ont pas encore de table et affichent `?`. Le désenchantement est un pari : sur beaucoup d'objets, la moyenne est atteinte ; pour un objet seul, la ligne grise donne le résultat le plus probable.

### Coût par point de compétence

`(composants − valeur de la meilleure revente) ÷ probabilité de gagner un point`

Un craft qui fait perdre 16s 50c avec 25 % de chances de point coûte 66s par point en moyenne. Si les crafts se paient d'eux-mêmes, la ligne affiche **Gain par point** en vert.

La probabilité de point dépend de la couleur de la recette et c'est une **estimation**, pas une valeur mesurée : orange 100 %, jaune 75 %, vert 25 %, gris 0 % (affiché `n/d`). Le pourcentage utilisé est affiché sur la ligne. La couleur des recettes épinglées est rafraîchie à chaque mise à jour de la fenêtre de métier, elle suit donc votre niveau.

## Options et commandes

| Réglage | Où | Défaut |
| --- | --- | --- |
| Coût par point de compétence | Case à cocher dans la fenêtre | Décochée |
| Détail des composants replié ou déplié | Clic sur la ligne Composants | Déplié |
| Position de la fenêtre | La déplacer ; `/cp reset` pour annuler | À côté de la fenêtre de métier ou de l'hôtel des ventes |
| Tri de la liste des épingles | Bouton au-dessus de la liste | Gain |

Commandes : `/cp` (ou `/craftprofit`) avec `show`, `hide`, `reset`, `scan`, `history`, `locale <code>` et `selftest`. Voir le [README](../README.fr.md#commandes).

## Langues

La fenêtre suit la langue du jeu : anglais, français et espagnol (l'espagnol d'Amérique latine utilise les textes espagnols). Toute autre langue retombe sur l'anglais. `/cp locale frFR` force une langue pour tester et `/cp locale` revient à la langue du jeu. Les noms d'objets et de recettes viennent toujours du jeu, dans la langue de votre client.

## Limites connues

- **Recettes connues uniquement.** Les recettes que vous n'avez pas apprises ne sont pas affichées.
- **Les prix sont des instantanés.** Ils sont aussi frais que votre dernière recherche ou scan ; la fenêtre affiche leur âge.
- **Les grandes quantités sont estimées.** Voir [Crafts](#crafts).
- **Les données de désenchantement viennent du Classic**, marquées *bêta*, sans table pour les épiques au-dessus du niveau d'objet 60.
- **Les chances de point sont des estimations** fondées sur la couleur de la recette.
- **Aucun historique ni fréquence de vente.** Le jeu ne fournit pas ces données : CraftProfit ne peut pas dire à quelle vitesse un objet se vend.
- **L'hôtel des ventes seul pour les prix.** Les prix marchand viennent du jeu.

## FAQ et dépannage

**La fenêtre n'apparaît pas.** Sélectionnez une recette dans la fenêtre de métier (une recette que vous connaissez). Essayez `/cp show`. Vérifiez que l'addon est activé et lancez `/cp selftest`.

**Tous les prix affichent `?`.** Aucun prix n'a encore été récupéré. À l'hôtel des ventes, appuyez sur **Rechercher les prix** pour les recettes épinglées ou sur **Scanner l'HV** pour tout.

**Le scan ne se termine jamais (« Pas de réponse du serveur »).** Le jeu limite les scans complets à un par tranche de 15 minutes et par compte, et le scan de n'importe quel addon compte. Attendez et réessayez une seule fois.

**« Objet pas encore chargé, réessayez ».** Le jeu n'a pas encore mis le nom de l'objet en cache ; cliquez de nouveau après un instant.

**La quantité n'est pas remplie après un clic sur un composant.** Le préremplissage est au mieux. La recherche fonctionne quand même ; saisissez la quantité à la main.

**Le désenchantement affiche `n/d` pour un objet que je viens de fabriquer.** L'objet est lié quand ramassé et votre personnage ne connaît pas l'enchantement, ou l'objet n'est pas désenchantable (ni armure ni arme, ou qualité médiocre).

**Le texte n'est pas dans la bonne langue.** Lancez `/cp locale` pour revenir à la langue du jeu. Les traductions manquantes retombent sur l'anglais ; merci de les signaler.

**J'ai trouvé un bug.** Ouvrez un ticket avec le modèle *Bug report* en indiquant le numéro de build (`/dump select(4, GetBuildInfo())`) et le texte de l'erreur Lua éventuelle. Activez les messages d'erreur avec `/console scriptErrors 1`.
