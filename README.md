# MY APPS

MY APPS est un launcher Windows pour organiser et ouvrir ses applications locales. Il peut importer des fichiers HTML autonomes, des packs ZIP MY APPS et des raccourcis vers des exécutables.

## Télécharger ou mettre à jour le launcher

- **Nouvelle installation**. Téléchargez le ZIP Windows dans [la dernière version](../../releases/latest), décompressez-le, puis lancez `MY_APPS.cmd`.
- **Installation existante depuis la v1.3.0**. Téléchargez le ZIP de mise à jour du launcher dans la même release. Dans MY APPS, cliquez sur **Mettre à jour MY APPS**, sélectionnez le ZIP, confirmez puis relancez le launcher.

Les applications installées et les raccourcis sont stockés dans le profil Windows.

## Installer et mettre à jour une application

À l’ouverture, MY APPS consulte le catalogue GitHub. Une alerte signale les nouvelles applications et les mises à jour. Ouvrez **Catalogue GitHub**, puis sélectionnez **Installer** ou **Mettre à jour** sur la carte. Les applications installées restent utilisables hors ligne.

Les mises à jour du catalogue reconnaissent un pack par son identifiant. Un fichier importé directement comme **HTML local** garde son propre mécanisme de remplacement.

## Publier une application dans le catalogue

1. Préparez un pack ZIP MY APPS contenant `index.html` et `my-apps.json`. Conservez l’`id` d’une version à l’autre et augmentez la version au format `x.y.z`.
2. Ajoutez le pack ZIP aux fichiers d’une [release GitHub](../../releases). Utilisez un nom de fichier sans espaces, par exemple `Mon_Appli_v1.0.1.zip`.
3. Ajoutez ou mettez à jour l’entrée correspondante dans [apps-catalog.json](apps-catalog.json) sur `main`. Les champs `id`, `name` et `version` décrivent le pack. `tag` et `asset` désignent la release et le nom exact du ZIP. Pour `sha256`, utilisez l’empreinte du ZIP, par exemple avec `Get-FileHash -Algorithm SHA256` dans PowerShell.

Le fichier [LIRE_EN_PREMIER.txt](LIRE_EN_PREMIER.txt) détaille les formats de packs et l’installation.
