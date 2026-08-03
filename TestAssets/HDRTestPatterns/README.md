# Mires HDR 1000 × 1000

Ce dossier contient deux mires dont la base SDR est un blanc RVB uniforme :

- `half-right` : la moitié droite reçoit un gain de +2 stops (×4).
- `hdr-center` : seules les lettres **HDR** au centre reçoivent un gain de +2 stops (×4).

## Sources séparées

- `base-white-srgb-rgb.png` : base SDR PNG, RVB 8 bits, sRGB, 1000 × 1000.
- `base-white-srgb-rgb.jpg` : même base en JPEG, utilisée comme fallback SDR du JPEG UltraHDR.
- `gainmap-*-plus2stops.png` : gain map monochrome 8 bits, 1000 × 1000. Noir = gain nul (×1), blanc = gain maximal (+2 stops, ×4).
- `master-linear-srgb-*-4x.tiff` : master HDR direct, TIFF RGB float 32 bits, sRGB linéaire. Les pixels valent 1,0 hors masque et 4,0 dans le masque.

Les PNG de gain map sont des cartes brutes destinées au test ou à un encodeur. Les métadonnées nécessaires à l’interprétation du gain sont intégrées dans les fichiers HEIC/JPEG ci-dessous.

## Conteneurs HDR prêts à tester

Pour chaque motif :

- `*-iso-gainmap.heic` : HEIC avec gain map ISO 21496, fallback SDR blanc.
- `*-apple-gainmap.heic` : HEIC avec gain map Apple, fallback SDR.
- `*-pq10.heic` : HEIC HDR direct PQ 10 bits, sans gain map.
- `*-hlg10.heic` : HEIC HDR direct HLG 10 bits, sans gain map.
- `ultrahdr-*-plus2stops.jpg` : JPEG UltraHDR / ISO 21496 avec fallback SDR blanc et gain map monochrome pleine résolution.

## Contrôles effectués

- Dimensions : 1000 × 1000 pour toutes les images.
- Base PNG : RGB 8 bits.
- Gain maps séparées : grayscale 8 bits.
- Masters TIFF : RGB float 32 bits ; valeurs brutes contrôlées à 1,0 et 4,0.
- HEIC ISO et Apple : gain map auxiliaire 1000 × 1000 détectée, `contentHeadroom = 4`.
- HEIC PQ et HLG : signal HDR détecté, sans gain map.
- JPEG UltraHDR : gain map 1000 × 1000 détectée, `minContentBoost = 1`, `maxContentBoost = 4`.

Sur un affichage SDR ou dans une application qui ignore le HDR, l’image doit rester entièrement blanche. Dans une application HDR compatible, seule la moitié droite ou le texte **HDR** doit dépasser le blanc SDR.

## Régénération

Depuis la racine du projet :

```sh
env SWIFT_MODULECACHE_PATH=/tmp/hdr-pattern-swift-cache \
    CLANG_MODULE_CACHE_PATH=/tmp/hdr-pattern-clang-cache \
    swift Tools/generate-hdr-test-patterns.swift TestAssets/HDRTestPatterns
```
