# CraftProfit — Design (WoW: Forever, Interface 16001)

Nom de travail, renommable. Addon pour World of Warcraft: Forever (client Mainline 12.1.5, `_classic_beta_`).

## 1. Objectif

Monter ses métiers en perdant le moins d'or possible, voire en gagner. Pour une recette connue, l'addon calcule le coût des composants aux prix de l'HV et le compare aux trois débouchés de l'objet crafté : revente HV (nette), revente marchand, désenchantement. Il indique la meilleure option.

Utilisateurs : joueurs qui montent un métier (coût par point de compétence) et joueurs qui cherchent seulement le profit. Le premier calcul est une **option à cocher**.

## 2. Périmètre V1

Inclus :
- Recettes **connues** du joueur, relues à chaque ouverture/mise à jour de la fenêtre de métier.
- Fenêtre flottante liée à la recette sélectionnée.
- Épingles de recettes + bouton « Recherche prix » à l'HV.
- Scan HV autonome (snapshot) + écoute passive des scans d'autres addons.
- Localisation enUS, frFR, esES, esMX.

Exclus (YAGNI) :
- Plan de montée complet 1→max, recettes inconnues.
- Fréquence de vente / historique (aucune API ne la fournit ; il faudrait accumuler des scans).
- Dépendance à Auctionator ou à tout autre addon.

## 3. Architecture

| Module | Rôle | Dépend de |
|---|---|---|
| `Core` | Fonctions pures : coût, revente nette, espérance de désenchantement, coût par point, verdict. Aucune API WoW. | rien |
| `Data` | Tables statiques : probabilités de désenchantement, probabilités de gain de compétence par couleur. Clés = identifiants, jamais des noms. | rien |
| `Scanner` | Scan HV, recherche ciblée par file d'attente, stockage des prix datés. | API `C_AuctionHouse` |
| `Recipes` | Lecture des recettes connues (composants, produit, difficulté). | API métier |
| `Locale` | Table de chaînes par langue, repli sur enUS. | rien |
| `UI` | Fenêtre flottante, liste d'épingles, options. | les autres |

`Core` et `Data` sont testables hors du jeu (Lua 5.1 en ligne de commande). Le reste est vérifié en jeu.

## 4. Fenêtre flottante

- Ancrée à droite de la fenêtre de métier, se met à jour à la sélection d'une recette. Déplaçable ; la position est enregistrée.
- Taille cible ~260×180. Contenu : nom, coût total (détail repliable), revente HV nette, prix marchand, désenchantement, verdict (« Meilleure option : … +X »), âge des prix, case coût par point, bouton ★.
- Prix inconnu : afficher `?`, jamais `0`. Le verdict devient « incomplet ».
- Montants affichés via `GetCoinTextureString` (indépendant de la langue).

## 5. Épingles

- Par personnage (SavedVariables). Une épingle stocke : identifiant de recette, objet produit, composants `{itemID, quantité}`. Utilisable fenêtre de métier fermée.
- À l'HV, la fenêtre affiche la liste des épingles et le bouton **Recherche prix**.

## 6. Recherche de prix

- File d'attente séquentielle : chaque composant, puis le produit. Une requête n'est envoyée qu'après la réponse (ou le délai maximal) de la précédente. Progression « n/N ».
- Les requêtes se font par `itemKey` (identifiant), donc indépendamment de la langue du client.
- Prix retenu = médiane des N annonces les moins chères (pas le minimum seul). Enregistré avec sa date.
- Échec ou délai dépassé : prix `?`, la file continue.
- Scan complet (`ReplicateItems`, limité à une fois par 15 min sur le compte) : bouton séparé ; écoute passive des résultats d'autres addons, scan propre seulement si le dernier est ancien.
- Marchandise vs objet classique : le type de requête dépend du résultat de la sonde (section 9).

## 7. Calculs (`Core`)

- Coût = Σ (quantité × prix unitaire) des composants.
- Revente HV nette = prix × (1 − commission). Commission = constante réglable (valeur issue de la sonde).
- Marchand = prix de vente via `C_Item.GetItemInfo`.
- Désenchantement = Σ (probabilité × prix du composant obtenu). Affiché seulement si l'objet est désenchantable et si le joueur a Enchanting. Pas de donnée → « inconnu ».
- Coût par point (option cochée) = coût net ÷ probabilité de gain, la probabilité dépendant de la couleur de difficulté de la recette. Ces probabilités sont des estimations, signalées comme telles dans l'interface.
- Verdict = option au meilleur résultat net parmi celles dont les prix sont connus.

Données de désenchantement : le plafond niveau 60 permet de reprendre les tables Classic pour les anciens objets. Les objets propres à Forever n'ont pas de table au départ : « inconnu ».

## 8. Localisation

- Locales : enUS (référence), frFR, esES, esMX. Choix par `GetLocale()`, repli sur enUS pour toute chaîne manquante.
- Aucune logique ne dépend d'un nom affiché : tout passe par identifiants (objets, recettes, métiers). Aucun parsing de texte localisé (infobulles comprises).
- Les noms d'objets et de recettes affichés viennent de l'API du jeu, donc automatiquement dans la langue du client.
- Pas de chaîne en dur dans `UI` : tout passe par `Locale`.

## 9. Sonde en jeu (étape 0, avant le reste)

Petit addon jetable, lancé sur le personnage forgeron niveau 30 (métier 140+). Il répond à :
1. L'HV traite-t-elle les composants en marchandises (`commodity`) ou en objets classiques ?
2. Taux réel de commission et de caution.
3. Quelle API de recettes donne composants, produit et difficulté (couleur) ?
4. Les noms retournés sont-ils des valeurs « secrètes » (`issecretvalue`) ?
5. `GetLocale()` et formats de montants sur ce client.

Les résultats fixent les appels réels de `Scanner` et `Recipes`.

## 10. Gestion d'erreurs

- Aucune recette sélectionnée / métier non supporté : fenêtre masquée.
- HV fermée pendant une file : file annulée proprement, prix déjà reçus conservés.
- Données d'objet pas encore chargées : attendre l'événement de chargement, puis recalculer.
- SavedVariables initialisées uniquement à `ADDON_LOADED`.

## 11. Tests

- `Core` et `Data` : tests unitaires hors du jeu avec prix fictifs (cas : prix manquant, désenchantement sans table, option point cochée/décochée).
- `Locale` : test automatique que chaque clé enUS existe dans les trois autres langues.
- `Scanner`, `Recipes`, `UI` : vérification manuelle en jeu, avec une liste de cas fournie.

## 12. Première livraison

Sonde → `Core` + `Data` + `Locale` testés → fenêtre flottante avec une recette sélectionnée → épingle et recherche de prix pour une recette.
