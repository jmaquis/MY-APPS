# MY APPS

MY APPS est un launcher Windows pour organiser et ouvrir ses applications locales. Il peut importer des fichiers HTML autonomes, des packs ZIP MY APPS et des raccourcis vers des exécutables.

## Télécharger ou mettre à jour le launcher

- **Nouvelle installation**. Téléchargez le ZIP Windows dans [la dernière version](../../releases/latest), décompressez-le, puis lancez `MY_APPS.cmd`.
- **À partir de la v1.5.0**. MY APPS vérifie les versions publiées sur GitHub à l’ouverture. Si une version est disponible, cliquez sur **Installer la v…**, confirmez, puis relancez le launcher. Le bouton **Installer un ZIP** permet aussi d’utiliser un fichier téléchargé.
- **Versions 1.3.0 à 1.4.1**. Téléchargez une fois le ZIP de mise à jour dans la dernière release. Dans MY APPS, cliquez sur **Mettre à jour MY APPS**, sélectionnez le ZIP, confirmez puis relancez le launcher.

Les applications installées et les raccourcis sont stockés dans le profil Windows.

## Installer et mettre à jour une application

À l’ouverture, MY APPS consulte le catalogue GitHub. Une alerte signale les nouvelles applications et les mises à jour. Sur l’accueil **Mes applications**, cliquez sur **Installer l’application** sur la carte voulue. Après le téléchargement et l’installation, cliquez sur **Ouvrir**. Les mises à jour se font via **Mettre à jour** sur la carte. La rubrique **Catalogue GitHub** permet aussi de voir les nouveautés et les mises à jour. Les applications installées restent utilisables hors ligne.

Les mises à jour du catalogue reconnaissent un pack par son identifiant. Un fichier importé directement comme **HTML local** garde son propre mécanisme de remplacement.

## Déposer un fichier HTML sur GitHub

1. Ouvrez le dossier [applications](applications/) dans ce dépôt.
2. Cliquez sur **Add file → Upload files**, déposez le fichier HTML autonome et enregistrez-le sur `main` avec **Commit changes**.
3. Attendez la fin de la [publication automatique](../../actions/workflows/publier-applications.yml), puis cliquez sur **Actualiser** dans le **Catalogue GitHub** de MY APPS. La carte proposera **Installer l’application**, également sur l’accueil.

Pour une mise à jour, remplacez le fichier au même endroit avec le même nom, puis choisissez **Mettre à jour** sur la carte. Le titre de l’onglet HTML sert de nom dans le catalogue. Les fichiers de ce dépôt sont publics.

Pour retirer du catalogue une application publiée automatiquement, supprimez son fichier HTML dans le dossier `applications` sur `main`. Le workflow retire l’entrée correspondante d’`apps-catalog.json`. Après son exécution, cliquez sur **Actualiser** dans le catalogue. Si l’application est déjà installée, utilisez **Supprimer** sur sa carte pour retirer aussi sa copie locale.

## Publier une nouvelle version du launcher

Augmentez `$baseVersion` dans `MY_APPS.ps1` et envoyez les modifications ensemble sur `main`. Le [workflow de publication Windows](../../actions/workflows/publier-launcher.yml) charge l’interface, construit les deux ZIP et publie la release stable que le launcher détecte au prochain démarrage.

## Publier manuellement un pack ZIP

1. Préparez un pack ZIP MY APPS contenant `index.html` et `my-apps.json`. Conservez l’`id` d’une version à l’autre et augmentez la version au format `x.y.z`.
2. Ajoutez le pack ZIP aux fichiers d’une [release GitHub](../../releases). Utilisez un nom de fichier sans espaces, par exemple `Mon_Appli_v1.0.1.zip`.
3. Ajoutez ou mettez à jour l’entrée correspondante dans [apps-catalog.json](apps-catalog.json) sur `main`. Les champs `id`, `name` et `version` décrivent le pack. `tag` et `asset` désignent la release et le nom exact du ZIP. Pour `sha256`, utilisez l’empreinte du ZIP, par exemple avec `Get-FileHash -Algorithm SHA256` dans PowerShell.

Le fichier [LIRE_EN_PREMIER.txt](LIRE_EN_PREMIER.txt) détaille les formats de packs et l’installation.
