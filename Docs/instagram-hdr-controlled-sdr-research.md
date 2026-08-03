# HDR photo pour Instagram avec rendu SDR maîtrisé

Recherche effectuée le **21 juin 2026**.

## Résumé

Le besoin étudié n'est pas simplement « exporter une image HDR ». Le fichier recherché doit contenir :

1. un rendu **SDR finalisé volontairement par le photographe** ;
2. un rendu **HDR finalisé séparément** ;
3. une gain map calculée entre ces deux rendus ;
4. le rendu SDR comme image de base réellement visible sur les appareils ou logiciels non HDR.

Dans cette définition stricte, **Web Sharp Pro est le seul produit grand public trouvé qui promet explicitement un workflow Instagram avec contrôle complet et séparé des rendus SDR et HDR**.

`toGainMapHDR` et `libultrahdr` savent également recevoir un HDR et un SDR distincts. Ce sont cependant davantage des moteurs techniques que des solutions Instagram finies. Ils constituent de très bonnes bases pour HDR Utility.

Adobe Lightroom sait éditer en HDR, prévisualiser et ajuster une rendition SDR, puis créer un JPEG à gain map. Il ne propose toutefois pas le même degré de liberté qu'un véritable couple d'images SDR/HDR indépendantes, et Adobe ne garantit pas que son JPEG exporté soit conservé comme HDR par Instagram.

Meta ne publie actuellement **aucune spécification officielle complète pour les photos HDR Instagram**. Les dimensions générales sont documentées, mais pas l'encapsulation gain map exacte acceptée ni les transformations appliquées au fichier. Une validation empirique reste donc indispensable.

## Ce que signifie un « bon backup SDR »

Une gain map n'est pas seulement une version HDR accompagnée d'une miniature SDR.

Le fichier stocke une image de base, généralement SDR, puis une carte qui décrit comment passer de ce rendu SDR au rendu HDR. Sur un écran intermédiaire, la gain map est appliquée partiellement selon la luminosité HDR réellement disponible.

Cela signifie que le SDR influence aussi l'affichage de nombreux utilisateurs équipés d'un écran HDR : un téléphone peut ne disposer que de 1,5 à 3 stops de réserve HDR selon sa luminosité, son mode économie d'énergie et la lumière ambiante.

Le workflow idéal doit donc :

- accepter deux fichiers déjà développés et approuvés ;
- ne pas imposer un tone mapping automatique du HDR vers le SDR ;
- conserver le SDR fourni comme image JPEG primaire ;
- permettre une gain map RGB, pas uniquement une carte de luminance ;
- permettre de contrôler la résolution et la compression de la gain map ;
- prévisualiser SDR, HDR maximal et niveaux HDR intermédiaires.

Adobe décrit précisément ce principe : une gain map combine deux renditions et redonne le contrôle créatif à l'auteur au lieu de laisser chaque plateforme choisir son tone mapping.

Source : [Adobe — Gain Map](https://helpx.adobe.com/camera-raw/using/gain-map.html)

## Applications et solutions trouvées

| Solution | Couple SDR/HDR réellement séparé | Promesse Instagram | Format pertinent | Verdict |
| --- | --- | --- | --- | --- |
| Web Sharp Pro | Oui, explicite | Oui, avec modèles Instagram/Threads | JPEG avec gain map | **Correspond exactement au besoin** |
| toGainMapHDR | Oui avec l'option `-b` | Le projet affirme une compatibilité Instagram | JPEG ou HEIC à gain map Apple/ISO | **Bonne brique technique, workflow à sécuriser** |
| Google libultrahdr | Oui, au niveau de l'API | Non, pas de garantie Instagram | JPEG Ultra HDR + ISO 21496-1 | **Meilleur moteur ouvert pour notre parcours Instagram** |
| Lightroom / Lightroom Classic | Contrôle d'une rendition SDR dérivée, pas deux développements totalement libres | Pas de garantie officielle | JPEG à gain map, AVIF, JXL | **Partiel** |
| Lightroom mobile → Instagram | Non ; génération automatique | Workflow direct signalé par Web Sharp Pro, pas garanti par Adobe/Meta | JPEG à gain map généré automatiquement | **Ne répond pas au critère qualitatif** |
| HDR Gain Map Convert | SDR créé par tone mapping | Pas de promesse Instagram précise | HEIF gain map | **Ne répond pas au critère** |
| LR GainMap HDR Export Plugin | SDR intermédiaire généré par le pipeline | Vise surtout Android/HEIF | HEIF gain map | **Ne répond pas au critère** |
| Adobe Gain Map Demo App | Lecture seulement | Non | Lit JPEG, AVIF et JXL gain map | **Outil de contrôle, pas d'export** |
| Google Photos Ultra HDR | Conversion ou amélioration automatique | Pas de contrôle du couple | Ultra HDR | **Ne répond pas au critère** |

### 1. Web Sharp Pro

[Web Sharp Pro](https://gregbenzphotography.com/web-sharp-pro-panel) est un panneau pour Photoshop. Il documente :

- des modèles d'export dédiés à Instagram et Threads ;
- un export **JPEG avec gain map** ;
- la possibilité de travailler depuis un SDR, un HDR, ou un **couple SDR et HDR fourni par l'utilisateur** ;
- une gain map entièrement personnalisée ;
- une intégration avec Lightroom Classic et Capture One ;
- le redimensionnement, le recadrage, l'accentuation et la compression avant encodage.

Son workflow avancé utilise un document Photoshop 32 bits dont le calque ou groupe inférieur est nommé `SDR`. Ce calque devient l'image de base du fichier ; le rendu HDR est défini séparément.

Le produit affirme encoder spécifiquement pour Instagram, car tous les JPEG gain map techniquement valides ne seraient pas conservés comme HDR par la plateforme.

Limites :

- nécessite Photoshop ;
- produit propriétaire ;
- le guide Instagram est une source de l'éditeur lui-même et non une documentation Meta ;
- plusieurs comportements annoncés sont empiriques et peuvent changer côté Instagram.

Sources :

- [Web Sharp Pro](https://gregbenzphotography.com/web-sharp-pro-panel)
- [Guide Instagram et Threads](https://gregbenzphotography.com/hdr-photos/how-to-share-hdr-photos-on-instagram-or-threads/)
- [Annonce Web Sharp Pro v7, 4 mai 2026](https://gregbenzphotography.com/)

### 2. toGainMapHDR

Le moteur [toGainMapHDR](https://github.com/chemharuka/toGainMapHDR) utilisé par HDR Utility accepte :

- un fichier HDR ;
- un fichier SDR distinct avec `-b <base_image>` ;
- une sortie JPEG avec `-j` ou HEIC ;
- une gain map Apple avec `-g` ou ISO ;
- plusieurs espaces colorimétriques et profondeurs ;
- une gain map Apple pleine ou demi-résolution.

Le projet affirme que sa gain map Apple est compatible avec Instagram. Cette affirmation n'est pas accompagnée d'une matrice de test Instagram détaillée.

Point essentiel : sans `-b`, l'outil fabrique automatiquement le SDR depuis le HDR. Pour répondre à notre cahier des charges, l'application doit donc **exiger ou privilégier un SDR fourni par le photographe**.

Limites :

- ce n'est pas un workflow Instagram complet ;
- pas de preset documenté pour les dimensions et contraintes Instagram ;
- pas de validation du résultat après transformation par Meta ;
- le projet indique macOS 26 ou ultérieur et des limitations Intel ;
- les variantes Apple, Adobe/Ultra HDR et ISO peuvent ne pas être traitées de la même manière par Instagram.

Sources :

- [Dépôt et documentation toGainMapHDR](https://github.com/chemharuka/toGainMapHDR)
- [Version 3.1](https://github.com/chemharuka/toGainMapHDR/releases/tag/3.1)

### 3. Google libultrahdr

[libultrahdr](https://github.com/google/libultrahdr) est une bibliothèque officielle Google, ouverte sous licences Apache 2.0 et MIT.

Son API accepte explicitement :

- une rendition HDR brute ;
- une rendition SDR brute distincte ;
- éventuellement le JPEG SDR déjà compressé ;
- puis calcule la gain map entre ces rendus sans devoir tone-mapper l'un depuis l'autre.

Elle produit un JPEG Ultra HDR rétrocompatible : un lecteur ancien affiche directement le JPEG SDR primaire, tandis qu'un lecteur compatible combine cette base avec la gain map.

La bibliothèque peut écrire les métadonnées **ISO 21496-1**. Google recommande de placer à la fois les métadonnées Ultra HDR v1 et ISO 21496-1 dans le même JPEG pour maximiser la compatibilité Android/Apple.

Attention à une limite d'implémentation actuelle : la compilation de libultrahdr active ISO par défaut, mais désactive l'écriture XMP Ultra HDR par défaut. Sa documentation précise que son écriture XMP actuelle ne représente correctement qu'une gain map à un canal. La combinaison « gain map RGB + double métadonnée Ultra HDR/ISO » devra donc être testée et pourra nécessiter une extension du moteur.

Limites :

- ce n'est pas une application destinée aux photographes ;
- les entrées brutes demandent un pipeline précis de décodage, conversion colorimétrique et alignement ;
- aucune documentation Google ou Meta ne garantit que tout JPEG produit par libultrahdr survivra au pipeline d'Instagram ;
- une validation sur Instagram reste obligatoire.

Sources :

- [Google libultrahdr](https://github.com/google/libultrahdr)
- [Spécification officielle Ultra HDR 1.1](https://developer.android.com/media/platform/hdr-image-format)
- [Instructions de compilation](https://github.com/google/libultrahdr/blob/main/docs/building.md)

### 4. Adobe Lightroom, Lightroom Classic et Camera Raw

Adobe permet :

- l'édition HDR ;
- le réglage de la limite HDR ;
- une prévisualisation SDR ;
- des réglages de rendition SDR ;
- l'export JPEG avec gain map, ainsi que AVIF, JPEG XL, TIFF, PSD et PNG selon le produit.

Dans Lightroom, le JPEG HDR contient une image SDR et une gain map. Les logiciels anciens affichent l'image SDR.

Cependant, Adobe décrit encore la rendition SDR comme un **tone mapping ajustable du développement HDR**, et non comme un développement totalement indépendant importé par le photographe. C'est mieux qu'un tone mapping opaque, mais moins libre qu'un couple SDR/HDR distinct.

Adobe ne documente pas une compatibilité Instagram spécifique pour les JPEG exportés. Le guide de Web Sharp Pro affirme même que l'encodage Adobe valide n'est pas toujours conservé comme HDR par Instagram.

Le même guide signale un partage direct depuis Lightroom mobile, mais avec une base SDR et une gain map générées automatiquement. Ce comportement n'est pas présenté par Adobe ou Meta comme une méthode garantissant un fallback SDR maîtrisé.

Sources :

- [Adobe Lightroom — HDR Optimization](https://helpx.adobe.com/lightroom-cc/using/hdr-output.html)
- [Adobe Lightroom Classic — Edit and Export in HDR](https://helpx.adobe.com/lightroom-classic/help/hdr-output.html)
- [Adobe Camera Raw — HDR Optimization](https://helpx.adobe.com/camera-raw/using/hdr-output.html)

### 5. Solutions écartées

[HDR Gain Map Convert](https://github.com/vincenttsang/HDR-Gain-Map-Convert) génère le SDR avec `CIToneMapHeadroom`. Il ne répond donc pas au besoin d'une rendition SDR développée indépendamment.

[LR GainMap HDR Export Plugin](https://github.com/fengshenx/LR_GainMap_HDR_Export_Plugin) convertit un export HDR Lightroom vers HEIF gain map, mais ne documente pas l'injection d'un SDR créatif distinct.

L'[Adobe Gain Map Demo App](https://helpx.adobe.com/camera-raw/using/gain-map.html) est utile pour inspecter la base, la gain map, le HDR complet et différents niveaux de capacité d'écran, mais ouvre les fichiers en lecture seule.

Les éditeurs HDR traditionnels tels qu'Aurora HDR, easyHDR ou Luminance HDR créent surtout un HDR puis un rendu SDR tone-mappé. Ils ne documentent ni JPEG gain map compatible Instagram, ni couple final SDR/HDR indépendant.

## Spécifications Instagram officiellement documentées

### Publication photo normale

La page d'aide Instagram consultée le 21 juin 2026 indique :

- largeur maximale conservée : **1 080 px** ;
- largeur acceptée sans agrandissement : **320 à 1 080 px** ;
- rapport hauteur/largeur pris en charge : **1.91:1 à 3:4** ;
- à 1 080 px de large, hauteur comprise entre **566 et 1 440 px** ;
- un fichier plus grand est réduit à 1 080 px ;
- un ratio non pris en charge est recadré.

Source officielle : [Instagram — Image resolution of photos you share](https://help.instagram.com/1631821640426723/)

Formats pratiques à prévoir :

| Usage | Dimensions |
| --- | ---: |
| Paysage maximal | 1080 × 566 |
| Carré | 1080 × 1080 |
| Portrait 4:5 | 1080 × 1350 |
| Portrait 3:4 | 1080 × 1440 |

Le **3:4** est désormais officiellement accepté, alors que les anciennes recommandations s'arrêtaient souvent au 4:5.

### API de publication Meta

La documentation Meta de l'API Content Publishing indique pour une image :

- format **JPEG** ;
- taille maximale **8 Mo** ;
- ratio **4:5 à 1.91:1** dans cette API ;
- largeur minimale 320 px et maximale 1 440 px dans les spécifications indexées.

Cette API ne décrit pas nécessairement le comportement de l'application Instagram grand public. Elle est plus restrictive, notamment parce que la page d'aide utilisateur accepte maintenant le 3:4.

Source officielle : [Meta for Developers — IG User Media](https://developers.facebook.com/docs/instagram-platform/instagram-graph-api/reference/ig-user/media/)

Pour notre preset, conserver un fichier sous **8 Mo** est une limite prudente, même si Meta ne publie pas de taille maximale claire pour l'import manuel.

### JPEG, HEIC ou AVIF ?

Le seul format explicitement documenté par Meta pour son API photo est le **JPEG**. Meta ne publie pas de liste officielle équivalente pour les photos HDR importées manuellement.

Les sources tierces rapportent que :

- certains AVIF HDR peuvent être acceptés, mais sans contrôle fiable de la base SDR et avec des limitations de plage HDR ;
- certains HEIC à gain map Apple peuvent fonctionner, mais le comportement dépend du chemin d'import ;
- le JPEG à gain map reste le choix le plus robuste, rétrocompatible et vérifiable.

Le format cible recommandé pour HDR Utility est donc **JPEG avec image SDR primaire et gain map**, et non AVIF ou HEIC pour le preset Instagram principal.

## Spécification du JPEG HDR à gain map

### Structure Ultra HDR

La spécification Google Ultra HDR 1.1 définit :

- un fichier conteneur JPEG ;
- une image primaire JPEG conventionnelle, normalement SDR ;
- une image JPEG secondaire contenant la gain map ;
- une gain map 8 bits ;
- des métadonnées XMP `hdrgm` ;
- une description GContainer ;
- un index MPF ;
- un profil ICC sur l'image primaire ;
- une gain map monochrome ou RGB selon l'encodage et les métadonnées.

Un lecteur non compatible ignore les données supplémentaires et affiche le JPEG SDR primaire.

La spécification recommande :

- qualité JPEG de gain map autour de 85 à 90 comme point de départ ;
- profil Display P3 comme recommandation générale ;
- possibilité de réduire la gain map, avec filtrage bilinéaire ou meilleur ;
- métadonnées Ultra HDR v1 **et** ISO 21496-1 simultanées pour la compatibilité multiplateforme maximale.

Source : [Ultra HDR Image Format v1.1](https://developer.android.com/media/platform/hdr-image-format)

### Ce qu'Instagram ne documente pas

Meta ne précise pas publiquement :

- si l'encodage attendu est Ultra HDR XMP, ISO 21496-1, Apple gain map, ou une combinaison ;
- si une gain map RGB est conservée ;
- la résolution maximale de la gain map ;
- les profils ICC HDR officiellement acceptés ;
- le niveau de compression appliqué ;
- les règles exactes qui déclenchent la suppression du HDR ;
- si le comportement diffère selon le navigateur, Android et iOS ;
- si le JPEG original est stocké ou reconstruit.

Toute affirmation plus précise doit donc être considérée comme un résultat de test, pas comme un contrat Meta.

## Workflow Instagram recommandé

### Préparation

1. Développer le rendu SDR comme une image finale autonome.
2. Développer le rendu HDR séparément.
3. S'assurer que les deux rendus ont :
   - exactement les mêmes dimensions ;
   - le même cadrage et la même orientation ;
   - aucune différence géométrique ;
   - une gestion colorimétrique explicitement définie.
4. Recadrer et redimensionner **avant** de calculer la gain map.
5. Viser 1 080 px de large pour éviter que Meta redimensionne le fichier.

### Encodage

Preset prudent proposé :

- conteneur : JPEG ;
- base : JPEG SDR fourni par le photographe ;
- gain map : RGB, pleine ou demi-résolution ;
- métadonnées : Ultra HDR v1 + ISO 21496-1 ;
- profil primaire : sRGB ou Display P3, à tester ;
- qualité de la base : 90 à 95 ;
- qualité de la gain map : 90 ou plus ;
- taille totale : inférieure à 8 Mo ;
- ratio : entre 1.91:1 et 3:4 ;
- aucun recadrage ni redimensionnement après l'encodage.

Display P3 est recommandé par la spécification Ultra HDR, mais Instagram ne publie pas ses règles de gestion des couleurs. Il faut donc comparer sRGB et Display P3 sur un jeu de référence avant de fixer le défaut. Rec.2020 ne devrait pas être le choix par défaut sans validation.

### Téléversement

Le guide Web Sharp Pro recommande, d'après ses tests :

- publication dans le fil Instagram, pas une Story photo ;
- import depuis le site Instagram sur ordinateur ou l'application Android ;
- sélection du ratio original ;
- éviter l'import depuis l'iPhone, qui aurait dégradé ou reconstruit les données lors de leurs tests ;
- dans un carrousel, utiliser exactement les mêmes dimensions pour toutes les images ;
- ne pas mélanger des tailles différentes ;
- vérifier le résultat final, car l'aperçu d'import peut rester SDR.

Ces règles sont **empiriques** et non garanties par Meta. Le guide comporte notamment des observations datées de juin 2025. Elles doivent être retestées en 2026.

Source : [How to share HDR photos on Instagram or Threads](https://gregbenzphotography.com/hdr-photos/how-to-share-hdr-photos-on-instagram-or-threads/)

## Conséquences pour HDR Utility

### Direction recommandée

Le parcours Instagram devrait utiliser **libultrahdr comme moteur principal**, avec deux entrées obligatoires :

- `HDR final` ;
- `SDR final`.

Le programme doit calculer la gain map entre ces deux rendus et ne générer automatiquement un SDR que dans un mode secondaire clairement nommé, par exemple « Générer un fallback automatiquement ».

### Fonctionnalités indispensables

1. Presets Instagram :
   - 1080 × 566 ;
   - 1080 × 1080 ;
   - 1080 × 1350 ;
   - 1080 × 1440.
2. Recadrage synchronisé des deux rendus avant encodage.
3. Validation stricte de l'alignement et des dimensions.
4. Choix sRGB / Display P3.
5. Gain map RGB avec résolution réglable.
6. Écriture Ultra HDR v1 + ISO 21496-1 lorsque la gain map choisie le permet, avec validation explicite de la variante RGB.
7. Estimation de la taille finale avec cible inférieure à 8 Mo.
8. Prévisualisation :
   - base SDR exacte ;
   - HDR maximal ;
   - simulations +1, +2 et +3 stops ;
   - gain map seule.
9. Analyse post-export des métadonnées et de la structure JPEG.
10. Rapport de conformité avant publication.

### État du dépôt actuel

HDR Utility contient déjà :

- un modèle de requête Instagram avec `hdrSource` et `sdrBase` ;
- un client prévu pour `libultrahdr` ;
- une interface demandant les deux fichiers ;
- une option de métadonnées ISO.

Il manque encore le binaire `ultrahdr_bridge`, donc ce parcours n'est pas opérationnel.

Le parcours Apple possède également une option « Custom SDR Base » et transmet techniquement l'option `-b` à `toGainMapHDR`. Toutefois, le traitement batch remet actuellement `sdrBase` à `nil` avant chaque conversion. Même pour une source unique, le SDR personnalisé n'est donc pas utilisé par le lancement batch actuel. Ce point doit être corrigé.

### Architecture cible

```text
HDR final ───────┐
                 ├─ normalisation géométrique/couleur ─ gain map ─ JPEG Ultra HDR
SDR final ───────┘                                      + ISO 21496-1
                                                               │
                                                               ├─ lecteur HDR : rendu adaptatif
                                                               └─ lecteur SDR : base SDR exacte
```

## Matrice de tests nécessaire

En l'absence de contrat HDR public de Meta, il faut maintenir une petite campagne de tests.

Tester chaque fichier sur :

- Instagram web, import depuis macOS ;
- Instagram Android ;
- Instagram iOS ;
- Chrome/Edge sur écran HDR ;
- iPhone HDR avec mode économie d'énergie activé et désactivé ;
- écran SDR ;
- post simple ;
- carrousel à dimensions identiques ;
- profils sRGB et Display P3 ;
- Ultra HDR seul, ISO seul et double métadonnée ;
- gain map mono et RGB ;
- gain map pleine, demi et quart de résolution.

Pour chaque test, conserver :

- le fichier source ;
- le fichier publié récupérable si possible ;
- une capture SDR ;
- une capture HDR ;
- le terminal, l'OS et la version Instagram ;
- le statut « HDR préservé / HDR supprimé / SDR modifié / couleurs incorrectes ».

## Conclusion

Le marché est étonnamment étroit. Beaucoup d'applications annoncent du HDR, mais très peu considèrent le SDR comme une création photographique à part entière.

Le benchmark fonctionnel à viser est **Web Sharp Pro** :

- couple SDR/HDR contrôlé ;
- gain map personnalisée ;
- preset Instagram ;
- JPEG rétrocompatible ;
- prévisualisation du comportement adaptatif.

Pour HDR Utility, la voie la plus cohérente est de terminer l'intégration de **libultrahdr**, d'imposer un vrai couple SDR/HDR dans le mode qualité, puis de produire un JPEG avec la signalisation la plus compatible possible. L'objectif est Ultra HDR + ISO 21496-1, sous réserve de résoudre ou contourner la limite XMP actuelle pour les gain maps RGB. `toGainMapHDR` peut rester utile pour les sorties Apple/HEIC et comme moteur de comparaison.

Le point le plus important reste que la compatibilité Instagram ne peut pas être déclarée sur la seule conformité à une norme. Elle doit être vérifiée régulièrement contre le pipeline réel de Meta.

## Sources principales

- [Instagram — Résolution des photos](https://help.instagram.com/1631821640426723/)
- [Meta for Developers — IG User Media](https://developers.facebook.com/docs/instagram-platform/instagram-graph-api/reference/ig-user/media/)
- [Google — Ultra HDR Image Format v1.1](https://developer.android.com/media/platform/hdr-image-format)
- [Google — libultrahdr](https://github.com/google/libultrahdr)
- [Adobe — Gain Map](https://helpx.adobe.com/camera-raw/using/gain-map.html)
- [Adobe — HDR Optimization in Lightroom](https://helpx.adobe.com/lightroom-cc/using/hdr-output.html)
- [Adobe — HDR in Lightroom Classic](https://helpx.adobe.com/lightroom-classic/help/hdr-output.html)
- [Web Sharp Pro](https://gregbenzphotography.com/web-sharp-pro-panel)
- [Web Sharp Pro — workflow Instagram/Threads](https://gregbenzphotography.com/hdr-photos/how-to-share-hdr-photos-on-instagram-or-threads/)
- [toGainMapHDR](https://github.com/chemharuka/toGainMapHDR)
- [HDR Gain Map Convert](https://github.com/vincenttsang/HDR-Gain-Map-Convert)
- [LR GainMap HDR Export Plugin](https://github.com/fengshenx/LR_GainMap_HDR_Export_Plugin)
