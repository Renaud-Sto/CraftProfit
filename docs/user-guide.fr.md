# Guide de l'utilisateur CraftProfit

*[English version](user-guide.md)* · [Retour au README](../README.fr.md)

CraftProfit vous dit ce que coûte vraiment une recette de métier à l'hôtel des ventes, et ce qu'il faut faire de l'objet obtenu. Ce guide explique chaque partie de la fenêtre, comment chaque chiffre est calculé, et ce que l'addon ne peut pas savoir.

Sommaire : [La fenêtre](#la-fenêtre) · [À l'hôtel des ventes](#à-lhôtel-des-ventes) · [Comment les chiffres sont calculés](#comment-les-chiffres-sont-calculés) · [Fenêtre d'options](#fenêtre-doptions) · [Options et commandes](#options-et-commandes) · [Langues](#langues) · [Limites connues](#limites-connues) · [FAQ et dépannage](#faq-et-dépannage)

## La fenêtre

Ouvrez une fenêtre de métier et sélectionnez une recette que vous connaissez. Une petite fenêtre apparaît à droite de la fenêtre de métier et suit votre sélection. Vous pouvez la déplacer où vous voulez ; sa position est mémorisée (`/cp reset` la remet en place). Elle se ferme avec la fenêtre de métier, et avec l'hôtel des ventes quand vous l'avez ouverte depuis celui-ci, pour ne jamais encombrer l'écran.

De haut en bas :

| Élément | Signification |
| --- | --- |
| Bandeau **Résultat** | La meilleure façon de vendre l'objet et le résultat net du craft (meilleure revente moins les composants), en grand. Vert pour un gain, rouge pour une perte, ambre quand le résultat est incomplet (il manque un prix). |
| **Trois tuiles** | **HV (NET)** : le prix que l'objet obtenu rapporterait à l'hôtel des ventes, après la commission de 5 %. **MARCHAND** : ce que paie un marchand pour l'objet. **DÉSENCH.** avec la mention *bêta* : la valeur *espérée* du désenchantement, nette de la commission de l'hôtel des ventes sur les composants obtenus (voir [Désenchantement](#désenchantement)). La meilleure est entourée d'or. Une tuile affiche `n/d` quand cette voie est impossible (lié quand ramassé, ne peut pas être vendu au marchand ni désenchanté) et `?` quand elle est possible mais qu'un prix est inconnu. Quand l'hôtel des ventes est ouvert, on peut cliquer sur la tuile **HV (NET)** pour rechercher l'objet obtenu (voir [Rechercher l'objet obtenu](#rechercher-lobjet-obtenu)). |
| *ligne grise* | Sous les tuiles : le résultat de désenchantement le plus probable, par exemple `75%: 1-2x Poussière d'âme = 7s 30c`. Affichée seulement quand le désenchantement a plusieurs résultats possibles. |
| Panneau **Composants** | Le coût de tous les composants aux prix de l'hôtel des ventes. Cliquez sur l'en-tête pour replier ou déplier le détail (`-` déplié, `+` replié) ; le choix est mémorisé. Cliquez sur un composant pour le chercher à l'hôtel des ventes (voir [Rechercher un composant](#rechercher-un-composant)). |
| **Prix : il y a 5min** | L'âge du prix le plus ancien utilisé. Passe en orange au-delà d'une heure. |
| Panneau **Options** | **Crafts**, **Suivre l'historique**, **Coût par point** avec sa valeur à droite (voir [Coût par point de compétence](#coût-par-point-de-compétence)), et le bouton **Épingler** / **Désépingler**. |

Le titre de la recette, en haut de la fenêtre, est cliquable lui aussi, avec le même effet, et déplace toujours la fenêtre. Un prix inconnu s'affiche `?`, jamais zéro. Le bandeau a trois cas particuliers :

- *Aucun moyen de revendre cet objet* : aucune des trois tuiles n'est utilisable (toutes `n/d`).
- *Incomplet : prix manquants* (ambre, sans valeur) : il manque un prix nécessaire au résultat, donc aucun résultat net n'est donné plutôt qu'un chiffre flatteur.
- *Meilleur connu : Hôtel des ventes* (avec le résultat net, en ambre) : certains prix sont connus, donc une meilleure voie de vente et son résultat net sont affichés. L'avertissement « RÉSULTAT · PRIX MANQUANTS » est en ambre sur la ligne du libellé au-dessus, où il a la place de s'afficher : le chiffre peut changer quand les prix manquants seront connus. Avec un montant très grand, le libellé peut quand même être raccourci.

### Crafts

La case **Crafts** multiplie la recette sélectionnée par un nombre de crafts (de 1 à 9999) : quantités de composants, total des composants, toutes les valeurs de revente et le résultat net du bandeau. Le coût ou gain **par point** et la ligne grise du désenchantement restent par point et par désenchantement. La liste des épingles montre toujours un seul craft, et sélectionner une autre recette remet la case à 1.

Pour de grandes quantités, le total est une estimation : le prix d'un composant est la médiane des offres les moins chères, mais en acheter 100 oblige à passer par des offres plus chères. Le vrai prix apparaît à l'hôtel des ventes quand vous lancez la recherche.

### Suivre l'historique

La case **Suivre l'historique** (à côté de Crafts) fait garder à CraftProfit les prix des composants et du résultat de cette recette au fil du temps. Jusqu'à 15 recettes peuvent être suivies, indépendamment de la liste des épingles. Un point est enregistré après chaque scan et chaque recherche de prix qui touche un objet de la recette, tant que tous les prix nécessaires sont connus. Décocher la case met l'enregistrement en pause et garde ce qui a été enregistré. `/cp history` liste les recettes suivies et `/cp history remove <n>` en supprime une avec son historique. Les prix sont gardés par jeu de règles (le « royaume » de la bêta) et par faction : l'historique d'un marché ne se mélange jamais avec un autre. Une vue de l'historique (graphiques, « moins cher que d'habitude ») est prévue ; pour l'instant, les données sont seulement collectées.

### Boutons Épingler et Actualiser recette

**Actualiser recette** (à droite du bouton Épingler) interroge l'hôtel des ventes pour les seuls objets de la recette affichée : ses composants, l'objet obtenu et, si besoin, les matériaux de désenchantement. Cela prend quelques secondes. Il ne marche que si l'hôtel des ventes est ouvert, qu'une recette est affichée et qu'aucune autre recherche n'est en cours ; sinon il est grisé. Son résultat s'affiche dans la ligne de statut sous la liste des épingles.

**Épingler** garde la recette dans votre liste d'épingles, utilisable même fenêtre de métier fermée. **Désépingler** la retire. Un personnage peut épingler 20 recettes par défaut ; changez la limite (12, 20, 30 ou 40) dans la [fenêtre d'options](#fenêtre-doptions). Quand la liste est pleine, le chat indique « Limite de recettes épinglées atteinte (20). Augmentez-la dans /cp options. »

## À l'hôtel des ventes

Trois façons de mettre les prix à jour, de la plus rapide à la plus large :

- **Actualiser recette** (fenêtre principale, panneau Options) : la recette affichée seulement, quelques secondes.
- **Actualiser épinglées** (sous la liste des épingles) : toutes les recettes épinglées, un objet à la fois, environ une minute pour 20 recettes.
- **Scanner l'HV** (sous la liste des épingles) : tout l'hôtel des ventes en un scan complet ; le jeu en autorise un par tranche de 15 minutes et par compte.

À l'ouverture de l'hôtel des ventes, la fenêtre affiche le panneau **RECETTES ÉPINGLÉES** sous la recette, avec trois boutons : **Actualiser épinglées** (le bouton principal), **Scanner l'HV** et **Montée de métier**, et une ligne de statut en dessous.

- **Actualiser épinglées** chiffre tous les composants et tous les objets obtenus des recettes épinglées, un objet à la fois, avec un compteur de progression : environ une minute pour 20 recettes épinglées. Avec beaucoup de recettes épinglées, **Scanner l'HV** va souvent plus vite. Les prix sont enregistrés avec leur date. Si vous fermez l'hôtel des ventes en cours de route, la recherche est annulée et les prix déjà reçus sont conservés. Un prix qui ne répond pas, ou qui répond sans offre, est redemandé une seconde fois automatiquement avant le résumé (« Nouvel essai n/m »). Une seule recherche à la fois : Actualiser recette est grisé pendant qu'elle tourne.
- **Scanner l'HV** lit tout l'hôtel des ventes d'un coup (le jeu autorise un scan complet par tranche de 15 minutes et par compte). Il chiffre des milliers d'objets, ce qui permet d'évaluer ensuite n'importe quelle recette. Si un autre addon lance un scan, CraftProfit utilise son résultat sans refaire de demande. Si le serveur ne répond pas, le statut le dit : le délai de 15 minutes est probablement en cours.

À la fin d'une actualisation, la ligne de statut dit ce qui s'est passé. Elle compte des prix : un par objet recherché, c'est-à-dire pas seulement les composants, mais aussi l'objet obtenu et, s'il peut être désenchanté, ses matériaux de désenchantement. Une recette à 5 composants peut donc compter 7 prix.

- `7 prix mis à jour` : tous les prix ont été mis à jour.
- `6 prix sur 7 mis à jour · sans réponse : Barre d'argent, réessayez` : l'hôtel des ventes n'a pas répondu à temps pour cet objet ; appuyez de nouveau sur le bouton. Un ou deux objets manquants sont nommés ; au-delà, la ligne donne leur nombre (`sans réponse : 3, réessayez`).
- `5 prix sur 7 mis à jour · sans offre : Barre de cuivre, Barre d'argent (personne n'en vend)` : ces objets ont répondu, mais personne n'en vend en ce moment ; leur ancien prix (s'il existe) est gardé.
- Les deux peuvent apparaître ensemble ; les trois nombres font toujours le total (`0 prix sur 3 mis à jour · sans offre : 3 ...` quand personne n'en vend aucun). La ligne tient sur deux lignes au plus : un nom d'objet très long est coupé par `...`. `Rien à rechercher` signifie que la recette n'a aucun objet à chiffrer. Une recherche arrêtée par la fermeture de l'hôtel des ventes affiche `Recherche annulée`.

### La liste des épingles

Son titre indique le nombre de recettes épinglées sur la limite, par exemple **RECETTES ÉPINGLÉES (21/30)**. La liste montre 6 recettes à la fois. Au-delà, une fine barre de défilement apparaît sur son bord droit : utilisez la molette de la souris (sur les lignes, sur la barre ou sur l'espace vide de la liste), faites glisser la barre, ou cliquez dessus pour y sauter. Avec 6 épingles ou moins, il n'y a pas de barre.

Le nom de chaque recette est coloré selon sa difficulté : orange (optimal), jaune (moyen), vert (facile) ou gris (trivial). La couleur est celle connue lors de la dernière ouverture de la fenêtre de métier : après avoir gagné des points de compétence, ouvrez la fenêtre de métier pour l'actualiser, car fenêtre fermée elle peut avoir du retard. Une épingle dont la difficulté n'est pas encore connue garde la couleur de texte normale. La valeur à droite est verte pour un gain, rouge pour une perte et grise si elle est inconnue. La recette sélectionnée a une teinte dorée ; la ligne sous la souris est surlignée.

### Trier la liste des épingles

Le petit bouton dans l'en-tête du panneau bascule entre :

- **Tri : gain** : le craft le plus rentable en premier (le moins déficitaire quand tous perdent de l'argent) ; les recettes sans prix en dernier.
- **Tri : coût/point** : le point de compétence le moins cher en premier. Une recette dont les crafts se paient d'eux-mêmes passe en tête (`+…/pt` en vert), puis les coûts en rouge (`…/pt`), puis les recettes grises (`n/d`, aucun point possible), puis celles sans prix (`?`). Ce mode active l'option du coût par point, et décocher cette option ramène le tri sur le gain.

Cliquez sur une recette de la liste pour l'afficher dans la fenêtre au-dessus.

### La fenêtre des recettes épinglées

`/cp pins`, un clic droit sur le bouton de la minicarte (ou sur l'entrée CraftProfit du compartiment d'addons), ou le bouton **Recettes épinglées** de la fenêtre d'options ouvre une fenêtre séparée et déplaçable avec vos recettes épinglées. Elle marche partout : ni hôtel des ventes ni fenêtre de métier nécessaires. Elle montre les **derniers prix connus** et ne lance jamais de recherche ; la ligne du haut indique l'âge du plus ancien prix utilisé (venu d'un scan ou d'une recherche de prix), en orange au-delà d'une heure.

- Chaque ligne montre la recette, colorée selon sa difficulté, et sa valeur : le résultat net, ou le coût par point, avec les mêmes couleurs et icônes de pièces que la liste à l'hôtel des ventes ; `?` quand un prix manque.
- Le bouton de tri en haut bascule entre **Tri : gain** et **Tri : coût/point** ; c'est le même choix que pour la liste à l'hôtel des ventes.
- Le petit **x** à droite d'une ligne désépingle la recette (son infobulle dit *Désépingler*) ; les lignes en dessous remontent et rien d'autre ne s'ouvre.
- Un clic ailleurs sur une ligne ouvre la fenêtre principale sur cette recette, avec ses prix enregistrés.
- Le titre du panneau indique le nombre d'épingles sur la limite, par exemple **RECETTES ÉPINGLÉES (21/30)**.
- 12 lignes sont visibles à la fois ; au-delà, utilisez la molette ou la barre de défilement.
- Échap ou la croix la ferme. Déplacez-la où vous voulez : elle se rouvre au même endroit, même après `/reload`. La première fois, elle s'ouvre juste à droite de la fenêtre CraftProfit la plus à droite à l'écran, ou à gauche du milieu de l'écran si aucune n'est affichée.
- Épingler ou désépingler depuis la fenêtre principale la met à jour aussitôt si elle est ouverte.

### La fenêtre de montée de métier

**Montée de métier** (bouton sous la liste des épingles, ou `/cp level`) ouvre une fenêtre séparée et déplaçable, à côté de la fenêtre principale, avec l'apparence du jeu, comme la fenêtre principale. Sa position est mémorisée et la croix la ferme. Elle montre **toutes les recettes que vous connaissez** dans un métier, le point de compétence le moins cher en premier : vous voyez d'un coup d'œil quoi fabriquer ensuite pour monter en perdant le moins possible.

- Chaque ligne montre la recette (colorée selon la difficulté), puis le coût par point, avec les mêmes écritures que la liste des épingles (les montants s'affichent avec les icônes de pièces d'or, d'argent et de cuivre du jeu ; ils sont écrits en lettres ici) : `21g 29s/pt` en rouge, `+9s 33c/pt` en vert quand les crafts se paient d'eux-mêmes, `?` quand un prix manque (ces recettes restent en bas).
- Le petit chiffre gris avant le montant, comme `x4`, est le nombre de crafts qu'un point demande en moyenne (100 % = `x1`, 75 % = `x1.3`, 25 % = `x4`). Le montant est la perte (ou le gain) d'un craft multipliée par ce chiffre, donc facile à relire : un craft qui perd 5s et demande 4 crafts par point affiche environ `20s/pt`.
- La liste s'intitule **PROCHAIN POINT** et montre 12 recettes à la fois. Au-delà, elle a la même barre de défilement que la liste des épingles (molette, glisser la barre ou cliquer dessus). La fenêtre garde toujours la même hauteur, et un nom de recette trop long est coupé par `...` au lieu de passer à la ligne.
- Le bouton de tri, à côté du bouton du métier en haut, change l'ordre : **Tri : coût/point** (le point le moins cher en premier, par défaut) ou **Tri : vitesse** (le point le plus probable en premier, donc le moins de crafts ; à chance égale, le moins cher). Utilisez la vitesse pour les derniers points à obtenir vite, le coût pour dépenser le moins. Le choix est mémorisé.
- Les **recettes grises** ne peuvent plus donner de point : elles sont masquées par défaut, cochez *Afficher les recettes grises* pour les voir.
- Le bouton du métier fait défiler les métiers que CraftProfit a lus pour ce personnage. La liste est enregistrée quand vous ouvrez une fenêtre de métier : elle est donc disponible à l'hôtel des ventes, fenêtre de métier fermée. Elle est relue à chaque mise à jour de la fenêtre de métier, ses couleurs suivent donc votre niveau.
- L'âge des prix (le dernier scan) est affiché en haut : tout le classement en dépend, lancez donc **Scanner l'HV** d'abord.
- Cliquez sur une ligne pour afficher la recette dans la fenêtre principale (multiplicateur de crafts, détail des composants, clic sur un composant pour le chercher).

Le classement vaut autant que les chances de point sur lesquelles il repose, qui restent des estimations selon la couleur. Il classe le *prochain point* ; ce n'est pas un plan complet de votre niveau actuel jusqu'au maximum. Une recette dont le résultat n'est pas un objet (un enchantement, par exemple) est écartée.

### Rechercher l'objet obtenu

Quand l'hôtel des ventes est ouvert, cliquez sur la tuile **HV (NET)** ou sur le titre de la recette pour rechercher l'objet obtenu : vous voyez combien sont en vente, à côté de son prix. CraftProfit ouvre la même vue *Acheter* que pour un composant et tape le nom de l'objet dans la barre de recherche, sans préremplir de quantité. Une petite loupe s'affiche sur la tuile et sur le titre tant que l'hôtel des ventes est ouvert et qu'une recette est affichée.

- Si l'hôtel des ventes est fermé, le clic vous demande seulement de l'ouvrir d'abord.
- Un objet lié quand ramassé ne peut pas être vendu à l'hôtel des ventes : le clic le dit et rien n'est recherché.
- Le titre et la tuile déplacent toujours la fenêtre : maintenez le clic et bougez pour la déplacer, un simple clic lance la recherche.
- Si aucune loupe n'apparaît, le clic fonctionne quand même : l'icône est facultative.

### Rechercher un composant

Avec le détail des composants déplié, cliquez sur la ligne d'un composant, par exemple `20x Barre de bronze`. CraftProfit ouvre la vue *Acheter* de l'hôtel des ventes, tape le nom de l'objet dans la barre de recherche et lance la recherche. Quand vous ouvrez la vue d'achat de l'objet, la quantité est déjà réglée sur 20 (multipliée par le nombre de crafts). C'est vous qui choisissez l'offre et qui appuyez sur **Acheter** : CraftProfit n'achète jamais rien.

## Comment les chiffres sont calculés

### Prix

Un prix vient des offres de l'hôtel des ventes. Le prix retenu pour un objet est la **médiane du prix unitaire des cinq unités les moins chères**. Une seule offre absurdement basse ne peut pas tirer le prix vers le bas comme le ferait un simple minimum, et les quantités sont bien prises en compte (une offre de 20 unités compte 20 fois).

Deux sources l'alimentent : la recherche ciblée de **Actualiser épinglées** et le **Scanner l'HV** complet. L'écriture la plus récente l'emporte ; chaque prix garde sa date. Les prix de plus de deux semaines sont supprimés.

### Hôtel des ventes (net)

`prix × (1 − 0,05)`. La commission de 5 % a été mesurée en jeu sur un courrier de vente (20 Étoffes de laine à 1 argent pièce : 1 argent de commission, dépôt remboursé). Le dépôt est remboursé quand l'objet se vend et n'est pas compté.

### Désenchantement

Valeur espérée = la somme, sur les résultats possibles, de *probabilité × quantité moyenne × prix*, nette de la commission de 5 %. Elle est affichée pour tout objet désenchantable, **que vous ayez ou non l'enchantement** : un objet lié quand équipé peut être désenchanté par un autre joueur ou un autre de vos personnages.

L'exception est un objet **lié quand ramassé** : il ne peut pas changer de mains, donc la tuile n'affiche une valeur (sinon `n/d`) que si votre personnage connaît l'enchantement.

Les tables viennent du Classic et ne sont pas encore vérifiées dans Forever, d'où la mention *bêta*. Les objets épiques au-dessus du niveau d'objet 60 n'ont pas encore de table et affichent `?`. Le désenchantement est un pari : sur beaucoup d'objets, la moyenne est atteinte ; pour un objet seul, la ligne grise donne le résultat le plus probable.

### Coût par point de compétence

`(composants − valeur de la meilleure revente) ÷ probabilité de gagner un point`

Un craft qui fait perdre 16s 50c avec 25 % de chances de point coûte 66s par point en moyenne. Si les crafts se paient d'eux-mêmes, la valeur à côté de la case devient verte et commence par `+` (un gain par point) ; un coût s'affiche en rouge, avec le pourcentage utilisé et *estimation*.

La probabilité de point dépend de la couleur de la recette et c'est une **estimation**, pas une valeur mesurée : orange 100 %, jaune 75 %, vert 25 %, gris 0 % (affiché `n/d`). Le pourcentage utilisé est affiché à côté de la case, après la valeur. La couleur des recettes épinglées est rafraîchie à chaque mise à jour de la fenêtre de métier, elle suit donc votre niveau.

## Fenêtre d'options

Ouvrez-la avec `/cp options`, un clic gauche sur le bouton de la minicarte, ou l'entrée CraftProfit du compartiment d'addons (le bouton de la liste des addons sur la minicarte, si votre client l'affiche). Échap la ferme ; déplacez-la où vous voulez, elle se rouvre au même endroit.

Où s'ouvrent les fenêtres : une fenêtre CraftProfit jamais déplacée s'ouvre juste à droite de la fenêtre CraftProfit la plus à droite déjà à l'écran, pour qu'elles ne s'empilent jamais (le bord de l'écran la garde visible). Si aucune n'est affichée, la fenêtre principale s'ouvre à côté de la fenêtre de métier ou de l'hôtel des ventes, la montée de métier à côté de la fenêtre principale, les recettes épinglées à gauche du milieu de l'écran et les options au milieu. Une fois déplacée, une fenêtre se rouvre toujours là où vous l'avez laissée. La fenêtre ouverte ou cliquée en dernier passe au premier plan, au-dessus des autres fenêtres CraftProfit et des panneaux d'interface du jeu.

- **Apparence** : choisissez le *Bandeau des sections* (Bois sculpté, Ombre ou Stries) et les *Cases de prix* (Carte de butin ou Encart). Les deux se combinent librement (6 apparences) ; le bouton allumé est votre choix. Il s'applique aussitôt à toutes les fenêtres, ouvertes ou non, et est enregistré pour le compte. Par défaut : Ombre et Encart.
- **Recettes épinglées** : la *Limite par personnage*, 12, 20, 30 ou 40 (20 par défaut) ; le bouton allumé est votre choix, enregistré pour le compte et appliqué dès la prochaine épingle. Une limite plus haute rallonge **Actualiser épinglées**, car l'hôtel des ventes est interrogé un objet à la fois (environ une minute pour 20 recettes) ; avec beaucoup de recettes, **Scanner l'HV** va souvent plus vite. Baisser la limite ne supprime jamais d'épingle : celles au-delà de la nouvelle limite restent, et les nouvelles sont refusées tant que vous n'en avez pas retiré assez.
- **Minicarte** : *Afficher le bouton de la minicarte*. Décochez pour masquer le bouton ; `/cp minimap` le masque ou le rétablit aussi.
- **Fenêtres** : ouvre ou ferme la fenêtre principale et la fenêtre de montée de métier (première ligne) et la fenêtre des recettes épinglées (deuxième ligne).
- **Commandes** : les clics sur la minicarte et toutes les commandes, une par ligne : la commande en doré, ce qu'elle fait en blanc.

Les couleurs qui ont un sens ne changent jamais avec l'apparence : le gain en vert, la perte en rouge, les couleurs de difficulté des recettes (orange, jaune, vert, gris) et la teinte du bandeau de résultat.

### Bouton de la minicarte

Clic gauche : fenêtre d'options. Clic droit : ouvre ou ferme la [fenêtre des recettes épinglées](#la-fenêtre-des-recettes-épinglées). Glissez-le avec le bouton gauche pour le déplacer autour de la minicarte ; il garde sa place après `/reload`. Les minicartes carrées (d'un addon de minicarte) sont suivies le long de leurs bords.

L'entrée CraftProfit du compartiment d'addons (si votre client l'affiche) marche de la même façon : clic gauche pour les options, clic droit pour les recettes épinglées.

## Options et commandes

| Réglage | Où | Défaut |
| --- | --- | --- |
| Coût par point | Case à cocher du panneau Options | Décochée |
| Détail des composants replié ou déplié | Clic sur l'en-tête Composants | Déplié |
| Position de la fenêtre | La déplacer ; `/cp reset` pour annuler | À côté de la fenêtre de métier ou de l'hôtel des ventes |
| Tri de la liste des épingles | Bouton dans l'en-tête du panneau des épingles, ou en haut de la fenêtre des recettes épinglées | Gain |
| Bandeau des sections et cases de prix | [Fenêtre d'options](#fenêtre-doptions) ; enregistré pour le compte | Ombre, Encart |
| Bouton de la minicarte affiché, et sa place | Fenêtre d'options ou `/cp minimap` ; le faire glisser | Affiché, en bas à gauche |

Commandes : `/cp` (ou `/craftprofit`) avec `show`, `hide`, `reset`, `options`, `pins`, `minimap`, `scan`, `history`, `market`, `level`, `locale <code>` et `selftest`. Voir le [README](../README.fr.md#commandes).

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

**Tous les prix affichent `?`.** Aucun prix n'a encore été récupéré. À l'hôtel des ventes, appuyez sur **Actualiser épinglées** pour les recettes épinglées ou sur **Scanner l'HV** pour tout.

**Le scan ne se termine jamais (« Pas de réponse du serveur »).** Le jeu limite les scans complets à un par tranche de 15 minutes et par compte, et le scan de n'importe quel addon compte. Attendez et réessayez une seule fois.

**« Objet pas encore chargé, réessayez ».** Le jeu n'a pas encore mis le nom de l'objet en cache ; cliquez de nouveau après un instant.

**Le clic sur la tuile HV ou sur le titre n'affiche qu'un message.** Rien n'est recherché, et le message dit pourquoi : « Ouvrez d'abord l'hôtel des ventes » (l'hôtel des ventes est fermé) ; « Cet objet ne peut pas être vendu à l'hôtel des ventes » (l'objet est lié quand ramassé) ; « Objet pas encore chargé, réessayez dans un instant » (le jeu n'a pas encore le nom de l'objet en mémoire : cliquez de nouveau).

**La quantité n'est pas remplie après un clic sur un composant.** Le préremplissage est au mieux. La recherche fonctionne quand même ; saisissez la quantité à la main.

**La tuile DÉSENCH. affiche `n/d` pour un objet que je viens de fabriquer.** L'objet est lié quand ramassé et votre personnage ne connaît pas l'enchantement, ou l'objet n'est pas désenchantable (ni armure ni arme, ou qualité médiocre).

**Le texte n'est pas dans la bonne langue.** Lancez `/cp locale` pour revenir à la langue du jeu. Les traductions manquantes retombent sur l'anglais ; merci de les signaler.

**J'ai trouvé un bug.** Ouvrez un ticket avec le modèle *Bug report* en indiquant le numéro de build (`/dump select(4, GetBuildInfo())`) et le texte de l'erreur Lua éventuelle. Activez les messages d'erreur avec `/console scriptErrors 1`.
