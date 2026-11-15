param(
    [Parameter(Mandatory = $true)][version]$AppVersion,
    [Parameter(Mandatory = $true)][string]$VersionsPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName System.IO.Compression.FileSystem

$root = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'MY_APPS'
$packages = Join-Path $root 'Applications'
$staging = Join-Path $root 'Imports'
$rollback = Join-Path $root 'Restauration'
$linksFile = Join-Path $root 'Raccourcis.json'
$manifestName = 'my-apps.json'

function Read-Utf8([string]$path) {
    [IO.File]::ReadAllText($path, [Text.Encoding]::UTF8)
}

function Read-AppManifest([string]$directory) {
    $manifest = Read-Utf8 (Join-Path $directory $manifestName) | ConvertFrom-Json
    if ($manifest.schema -isnot [int] -and $manifest.schema -isnot [long]) {
        throw 'Le manifeste doit contenir schema = 1.'
    }
    if ($manifest.schema -ne 1 -or
        $manifest.id -isnot [string] -or $manifest.id -cnotmatch '^[a-z0-9][a-z0-9-]{0,47}$' -or
        $manifest.id -match '^(con|prn|aux|nul|com[0-9]|lpt[0-9])$' -or
        $manifest.name -isnot [string] -or $manifest.name.Trim().Length -eq 0 -or $manifest.name.Length -gt 70 -or
        $manifest.version -isnot [string] -or $manifest.version.Trim().Length -eq 0 -or $manifest.version.Length -gt 30) {
        throw 'Le manifeste du pack contient un identifiant, un nom ou une version invalide.'
    }
    if (-not (Test-Path -LiteralPath (Join-Path $directory 'index.html') -PathType Leaf)) {
        throw 'Le pack doit contenir un fichier index.html à sa racine.'
    }
    return $manifest
}

function Expand-AppPack([string]$zipPath, [string]$destination) {
    $archive = [IO.Compression.ZipFile]::OpenRead($zipPath)
    try {
        if ($archive.Entries.Count -gt 2000) { throw 'Le pack contient plus de 2 000 fichiers ou dossiers.' }
        [long]$total = 0
        foreach ($entry in $archive.Entries) {
            $total += $entry.Length
            if ($total -gt 100MB) { throw 'La taille décompressée du pack dépasse 100 Mo.' }

            $relative = $entry.FullName.Replace('\', '/')
            $parts = $relative.TrimEnd('/').Split('/')
            foreach ($part in $parts) {
                if ($part.Length -eq 0 -or $part -in '.', '..' -or
                    $part.EndsWith('.') -or $part.EndsWith(' ') -or
                    $part.IndexOfAny([IO.Path]::GetInvalidFileNameChars()) -ge 0 -or
                    $part -match '^(con|prn|aux|nul|com[0-9¹²³]|lpt[0-9¹²³])(\.|$)') {
                    throw 'Le ZIP contient un chemin non valide pour Windows.'
                }
            }
            $target = Join-Path $destination ($parts -join '\')
            if ($relative.EndsWith('/')) {
                [void][IO.Directory]::CreateDirectory($target)
                continue
            }
            [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($target))
            [IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $target, $false)
        }
    } finally {
        $archive.Dispose()
    }
}

function Get-Links {
    if (Test-Path -LiteralPath $linksFile -PathType Leaf) {
        $records = Read-Utf8 $linksFile | ConvertFrom-Json
        foreach ($record in $records) { $record }
    }
}

function Save-Links([object[]]$links) {
    $temp = Join-Path $root ('raccourcis-' + [guid]::NewGuid() + '.tmp')
    try {
        $json = ConvertTo-Json -InputObject $links -Depth 4
        [IO.File]::WriteAllText($temp, $json, [Text.UTF8Encoding]::new($false))
        if ([IO.File]::Exists($linksFile)) {
            [IO.File]::Replace($temp, $linksFile, [NullString]::Value)
        } else {
            [IO.File]::Move($temp, $linksFile)
        }
    } finally {
        if ([IO.File]::Exists($temp)) { [IO.File]::Delete($temp) }
    }
}

function Get-Apps {
    foreach ($link in @(Get-Links)) {
        [pscustomobject]@{ Name = $link.name; Path = $link.path; Version = ''; Kind = 'Raccourci' }
    }
    foreach ($directory in Get-ChildItem -LiteralPath $packages -Directory) {
        try {
            $manifest = Read-AppManifest $directory.FullName
            [pscustomobject]@{
                Name = $manifest.name
                Path = Join-Path $directory.FullName 'index.html'
                Version = $manifest.version
                Kind = if ($manifest.PSObject.Properties['source'] -and $manifest.source -eq 'html') {
                    'HTML local'
                } else {
                    'Pack local'
                }
            }
        } catch {
            [pscustomobject]@{
                Name = $directory.Name
                Path = Join-Path $directory.FullName 'index.html'
                Version = ''
                Kind = 'Pack à réimporter'
            }
        }
    }
}

function Install-AppDirectory([string]$work) {
    $manifest = Read-AppManifest $work
    $isHtml = $manifest.PSObject.Properties['source'] -and $manifest.source -eq 'html'
    $target = Join-Path $packages $manifest.id
    $previous = Join-Path $rollback $manifest.id

    if ([IO.Directory]::Exists($target)) {
        $message = if ($isHtml) {
            "Remplacer la copie locale de $($manifest.name) ?"
        } else {
            "Installer $($manifest.name) version $($manifest.version) à la place du pack actuel ?"
        }
        $reply = [System.Windows.MessageBox]::Show(
            $form, $message,
            'Mettre à jour', 'YesNo', 'Question'
        )
        if ($reply -ne 'Yes') { return }
        if ([IO.Directory]::Exists($previous)) { [IO.Directory]::Delete($previous, $true) }
        [IO.Directory]::Move($target, $previous)
    }
    try {
        [IO.Directory]::Move($work, $target)
    } catch {
        if ([IO.Directory]::Exists($previous) -and -not [IO.Directory]::Exists($target)) {
            [IO.Directory]::Move($previous, $target)
        }
        throw
    }
    if ([IO.Directory]::Exists($previous)) {
        try { [IO.Directory]::Delete($previous, $true) } catch { }
    }
    Refresh-AfterAdd
    $status.Text = if ($isHtml) {
        "$($manifest.name) · copie locale enregistrée"
    } else {
        "$($manifest.name) · version $($manifest.version) installée"
    }
}

function Import-AppPack([string]$zipPath) {
    $work = Join-Path $staging ([guid]::NewGuid().ToString())
    [void][IO.Directory]::CreateDirectory($work)
    try {
        Expand-AppPack $zipPath $work
        Install-AppDirectory $work
    } finally {
        if ([IO.Directory]::Exists($work)) {
            try { [IO.Directory]::Delete($work, $true) } catch { }
        }
    }
}

function Import-HtmlFile([string]$path) {
    $fullPath = [IO.Path]::GetFullPath($path)
    # Use the original path to find the same local copy when a file is imported again.
    $hash = [Security.Cryptography.SHA256]::Create()
    try {
        $digest = $hash.ComputeHash([Text.Encoding]::UTF8.GetBytes($fullPath))
    } finally {
        $hash.Dispose()
    }
    $id = 'html-' + [BitConverter]::ToString($digest, 0, 16).Replace('-', '').ToLowerInvariant()
    $name = ([IO.Path]::GetFileNameWithoutExtension($fullPath) -replace '[_-]', ' ').Trim()
    if (-not $name) { $name = [IO.Path]::GetFileName($fullPath) }
    if ($name.Length -gt 70) {
        $name = $name.Substring(0, 70)
        if ([char]::IsHighSurrogate($name[69])) { $name = $name.Substring(0, 69) }
    }

    $work = Join-Path $staging ([guid]::NewGuid().ToString())
    [void][IO.Directory]::CreateDirectory($work)
    try {
        [IO.File]::Copy($fullPath, (Join-Path $work 'index.html'))
        $manifest = [ordered]@{
            schema = 1
            id = $id
            name = $name
            version = '1.0.0'
            source = 'html'
        }
        $json = ConvertTo-Json -InputObject $manifest
        [IO.File]::WriteAllText((Join-Path $work $manifestName), $json, [Text.UTF8Encoding]::new($false))
        Install-AppDirectory $work
    } finally {
        if ([IO.Directory]::Exists($work)) {
            try { [IO.Directory]::Delete($work, $true) } catch { }
        }
    }
}

function Open-App($app) {
    if (-not [IO.File]::Exists($app.Path)) {
        throw "Fichier introuvable : $($app.Path)"
    }
    $start = [Diagnostics.ProcessStartInfo]::new($app.Path)
    $start.UseShellExecute = $true
    $start.WorkingDirectory = [IO.Path]::GetDirectoryName($app.Path)
    [void][Diagnostics.Process]::Start($start)
    $status.Text = "$($app.Name) · ouvert"
}

function Remove-App($app) {
    $name = $app.Name
    $message = if ($app.IsLink) {
        "Supprimer le raccourci « $name » de MY APPS ? Le fichier d’origine sera conservé."
    } else {
        "Supprimer « $name » et ses fichiers installés dans MY APPS ?"
    }
    $reply = [System.Windows.MessageBox]::Show(
        $form, $message, 'Supprimer', 'YesNo', 'Warning', 'No'
    )
    if ($reply -ne 'Yes') { return }

    $removedPath = $null
    if ($app.IsLink) {
        $remaining = @(Get-Links | Where-Object { $_.path -ne $app.Path })
        Save-Links $remaining
    } else {
        $directory = [IO.Path]::GetDirectoryName($app.Path)
        if ([IO.Path]::GetDirectoryName($directory) -ne $packages) {
            throw 'Ce dossier ne correspond pas à une application installée dans MY APPS.'
        }

        # Clear an older copy so startup recovery cannot restore a deleted app.
        $previous = Join-Path $rollback ([IO.Path]::GetFileName($directory))
        if ([IO.Directory]::Exists($previous)) { [IO.Directory]::Delete($previous, $true) }

        $removedPath = Join-Path $staging ('suppression-' + [guid]::NewGuid().ToString())
        [IO.Directory]::Move($directory, $removedPath)
    }

    $script:appModels = @(Get-CardModels)
    Render-Apps
    $status.Text = "$name · supprimé de MY APPS"

    if ($removedPath) {
        try {
            [IO.Directory]::Delete($removedPath, $true)
        } catch {
            throw "L’application a été retirée de MY APPS. Certains fichiers n’ont pas pu être effacés dans « $removedPath »."
        }
    }
}

function Show-Error([string]$message) {
    [void][System.Windows.MessageBox]::Show($form, $message, 'MY APPS', 'OK', 'Error')
}

function Choose-File([string]$title, [string]$filter) {
    $dialog = [Microsoft.Win32.OpenFileDialog]::new()
    $dialog.Title = $title
    $dialog.Filter = $filter
    $dialog.CheckFileExists = $true
    if ($dialog.ShowDialog($form) -eq $true) { $dialog.FileName }
}

function Install-LauncherUpdate([string]$zipPath) {
    $expected = @('my-apps-update.json', 'MY_APPS_App.ps1', 'MY_APPS.xaml')
    [void][IO.Directory]::CreateDirectory($VersionsPath)
    $work = Join-Path $VersionsPath ('.import-' + [guid]::NewGuid().ToString())
    [void][IO.Directory]::CreateDirectory($work)
    try {
        $archive = [IO.Compression.ZipFile]::OpenRead($zipPath)
        try {
            if ($archive.Entries.Count -ne $expected.Count) {
                throw 'Sélectionne un ZIP de mise à jour du launcher MY APPS.'
            }
            foreach ($name in $expected) {
                $entry = $archive.GetEntry($name)
                if ($null -eq $entry -or $entry.Length -le 0 -or $entry.Length -gt 4MB) {
                    throw 'Le ZIP de mise à jour est incomplet ou contient un fichier invalide.'
                }
                [IO.Compression.ZipFileExtensions]::ExtractToFile($entry, (Join-Path $work $name), $false)
            }
        } finally {
            $archive.Dispose()
        }

        $manifest = Read-Utf8 (Join-Path $work 'my-apps-update.json') | ConvertFrom-Json
        if ($null -eq $manifest -or -not $manifest.PSObject.Properties['schema'] -or
            -not $manifest.PSObject.Properties['product'] -or -not $manifest.PSObject.Properties['version'] -or
            $manifest.schema -ne 1 -or $manifest.product -cne 'MY_APPS_LAUNCHER' -or
            $manifest.version -isnot [string]) {
            throw 'Le manifeste de mise à jour MY APPS est invalide.'
        }
        [version]$newVersion = $null
        if (-not [version]::TryParse($manifest.version, [ref]$newVersion) -or
            $newVersion.Build -lt 0 -or $newVersion.Revision -ne -1 -or $newVersion.ToString() -cne $manifest.version) {
            throw 'La version du ZIP doit être au format x.y.z.'
        }
        if ($newVersion -le $AppVersion) {
            throw "MY APPS $AppVersion est déjà à jour par rapport à ce ZIP ($newVersion)."
        }
        $destination = Join-Path $VersionsPath ($newVersion.ToString())
        if ([IO.Directory]::Exists($destination)) {
            throw "La version $newVersion est déjà installée. Ferme et relance MY APPS pour l’ouvrir."
        }

        $tokens = $null
        $parseErrors = $null
        $newScript = Join-Path $work 'MY_APPS_App.ps1'
        [void][System.Management.Automation.Language.Parser]::ParseFile($newScript, [ref]$tokens, [ref]$parseErrors)
        if ($null -ne $parseErrors -and $parseErrors.Count -gt 0) { throw 'Le script de mise à jour contient une erreur de syntaxe.' }

        $reader = [Xml.XmlReader]::Create((Join-Path $work 'MY_APPS.xaml'))
        try {
            $layout = [Xml.XmlDocument]::new()
            $layout.Load($reader)
            if ($layout.DocumentElement.LocalName -cne 'Window' -or
                $layout.DocumentElement.NamespaceURI -cne 'http://schemas.microsoft.com/winfx/2006/xaml/presentation') {
                throw "Le fichier d’interface de la mise à jour est invalide."
            }
        } finally {
            $reader.Dispose()
        }

        $reply = [System.Windows.MessageBox]::Show(
            $form, "Installer MY APPS $newVersion ? La mise à jour s’appliquera au prochain lancement.",
            'Mettre à jour MY APPS', 'YesNo', 'Question', 'No'
        )
        if ($reply -ne 'Yes') { return }

        [IO.Directory]::Move($work, $destination)
        $ui.UpdateButton.IsEnabled = $false
        $status.Text = "Version $newVersion installée · Relance MY APPS"
        [void][System.Windows.MessageBox]::Show(
            $form, "Version $newVersion installée. Ferme puis relance MY APPS pour l’utiliser.",
            'Mise à jour installée', 'OK', 'Information'
        )
    } finally {
        if ([IO.Directory]::Exists($work)) {
            try { [IO.Directory]::Delete($work, $true) } catch { }
        }
    }
}

function Get-CardModels {
    foreach ($app in Get-Apps | Sort-Object Name) {
        $isLink = $app.Kind -eq 'Raccourci'
        $detail = if ($isLink) {
            [IO.Path]::GetFileName($app.Path)
        } elseif ($app.Kind -eq 'HTML local') {
            'Copie locale'
        } elseif ($app.Version) {
            'Version ' + $app.Version
        } else {
            'Réimporter le pack ZIP'
        }
        @{
            Name = $app.Name
            Path = $app.Path
            Kind = $app.Kind
            Detail = $detail
            IsLink = $isLink
            IconBackground = if ($isLink) { '#1E3A3D' } else { '#362C55' }
            IconStroke = if ($isLink) { '#A9E3C8' } else { '#D1C3FF' }
            IconGeometry = if ($isLink) {
                'M7,2 H2 V14 H14 V9 M9,1 H15 V7 M15,1 L7,9'
            } else {
                'M7.5,0 L15,4 15,12 7.5,16 0,12 0,4 Z M0,4 L7.5,8 15,4 M7.5,8 V16'
            }
            OpenAccessibleName = "Ouvrir $($app.Name)"
            RemoveAccessibleName = "Supprimer $($app.Name)"
        }
    }
}

function Render-Apps {
    $query = $ui.SearchBox.Text.Trim()
    $linksOnly = $ui.LinkNav.IsChecked -eq $true
    $packsOnly = $ui.PackNav.IsChecked -eq $true

    $ui.PageTitle.Text = if ($linksOnly) { 'Raccourcis' }
        elseif ($packsOnly) { 'Applications locales' } else { 'Mes applications' }
    $ui.SearchHint.Visibility = if ($ui.SearchBox.Text.Length -eq 0) { 'Visible' } else { 'Collapsed' }

    $visibleApps = @(
        foreach ($app in $script:appModels) {
            if (($linksOnly -and -not $app.IsLink) -or ($packsOnly -and $app.IsLink)) { continue }
            if ($query -and $compareInfo.IndexOf($app.Name, $query, $compareOptions) -lt 0) { continue }
            $app
        }
    )
    $ui.AppsGrid.ItemsSource = $visibleApps
    $ui.AppCount.Text = if ($visibleApps.Count -eq 1) { '1 application' } else { "$($visibleApps.Count) applications" }

    if ($visibleApps.Count -gt 0) {
        $ui.EmptyState.Visibility = 'Collapsed'
        return
    }
    $ui.EmptyState.Visibility = 'Visible'
    if ($query) {
        $ui.EmptyTitle.Text = 'Aucun résultat'
        $ui.EmptyBody.Text = "Essaie un autre nom d’application."
    } elseif ($linksOnly) {
        $ui.EmptyTitle.Text = 'Aucun raccourci'
        $ui.EmptyBody.Text = 'Ajoute un fichier EXE pour créer un raccourci.'
    } elseif ($packsOnly) {
        $ui.EmptyTitle.Text = 'Aucune application installée'
        $ui.EmptyBody.Text = 'Ajoute un fichier HTML autonome ou importe un pack ZIP MY APPS.'
    } else {
        $ui.EmptyTitle.Text = 'Ta bibliothèque est vide'
        $ui.EmptyBody.Text = 'Ajoute une application existante ou importe le pack de démonstration.'
    }
}

function Refresh-AfterAdd {
    $script:appModels = @(Get-CardModels)
    $ui.AllNav.IsChecked = $true
    $ui.SearchBox.Clear()
    Render-Apps
}

function Add-AppFile {
    $path = Choose-File 'Sélectionner une application existante' 'Applications (*.html;*.htm;*.exe)|*.html;*.htm;*.exe'
    if (-not $path) { return }
    $extension = [IO.Path]::GetExtension($path)
    if ($extension -in '.html', '.htm') {
        Import-HtmlFile $path
        return
    }
    if ($extension -ne '.exe') {
        throw 'Choisis un fichier HTML, HTM ou EXE.'
    }
    $links = @(Get-Links)
    if ($links | Where-Object { $_.path -eq $path } | Select-Object -First 1) {
        $status.Text = 'Ce fichier est déjà dans MY APPS.'
        return
    }
    $name = [IO.Path]::GetFileNameWithoutExtension($path) -replace '[_-]', ' '
    $links += [pscustomobject]@{ name = $name; path = $path }
    Save-Links $links
    Refresh-AfterAdd
    $status.Text = "$name · ajouté"
}

$mutex = [Threading.Mutex]::new($false, 'Local\MY_APPS_Windows_Launcher')
$ownsMutex = $false
try {
    try { $ownsMutex = $mutex.WaitOne(0) } catch [Threading.AbandonedMutexException] { $ownsMutex = $true }
    if (-not $ownsMutex) {
        [void][System.Windows.MessageBox]::Show('MY APPS est déjà ouvert.', 'MY APPS')
        return
    }

    foreach ($directory in @($root, $packages, $staging, $rollback)) {
        [void][IO.Directory]::CreateDirectory($directory)
    }
    foreach ($previous in Get-ChildItem -LiteralPath $rollback -Directory) {
        $target = Join-Path $packages $previous.Name
        if ([IO.Directory]::Exists($target)) {
            try { [IO.Directory]::Delete($previous.FullName, $true) } catch { }
        } else {
            [IO.Directory]::Move($previous.FullName, $target)
        }
    }

    $layoutPath = Join-Path $PSScriptRoot 'MY_APPS.xaml'
    $layoutReader = [Xml.XmlReader]::Create($layoutPath)
    try {
        $form = [Windows.Markup.XamlReader]::Load($layoutReader)
    } finally {
        $layoutReader.Dispose()
    }

    $ui = @{}
    foreach ($name in @(
        'MinimizeButton', 'MaximizeButton', 'MaximizeIcon', 'CloseButton',
        'AllNav', 'PackNav', 'LinkNav', 'PageTitle', 'AddButton', 'ImportButton',
        'AppCount', 'SearchBox', 'SearchHint', 'AppsGrid', 'EmptyState',
        'EmptyTitle', 'EmptyBody', 'StatusText', 'UpdateButton', 'LauncherVersion'
    )) {
        $ui[$name] = $form.FindName($name)
        if ($null -eq $ui[$name]) { throw "Élément d’interface introuvable : $name" }
    }
    $status = $ui.StatusText
    $ui.LauncherVersion.Text = "Version $AppVersion"
    $compareInfo = [Globalization.CultureInfo]::GetCultureInfo('fr-FR').CompareInfo
    $compareOptions = [Globalization.CompareOptions]'IgnoreCase, IgnoreNonSpace'

    $ui.MinimizeButton.Add_Click({ $form.WindowState = 'Minimized' })
    $ui.MaximizeButton.Add_Click({
        $form.WindowState = if ($form.WindowState -eq 'Maximized') { 'Normal' } else { 'Maximized' }
    })
    $form.Add_StateChanged({
        $geometry = if ($form.WindowState -eq 'Maximized') {
            'M 2,2 V 0 H 10 V 8 H 8 M 0,2 H 8 V 10 H 0 Z'
        } else {
            'M 0,0 H 9 V 9 H 0 Z'
        }
        $ui.MaximizeIcon.Data = [Windows.Media.Geometry]::Parse($geometry)
    })
    $ui.CloseButton.Add_Click({ $form.Close() })
    $ui.AddButton.Add_Click({
        try { Add-AppFile } catch { Show-Error $_.Exception.Message }
    })
    $ui.ImportButton.Add_Click({
        try {
            $path = Choose-File 'Importer un pack MY APPS' 'Pack ZIP (*.zip)|*.zip'
            if ($path) { Import-AppPack $path }
        } catch { Show-Error $_.Exception.Message }
    })
    $ui.UpdateButton.Add_Click({
        try {
            $path = Choose-File 'Choisir une mise à jour du launcher MY APPS' 'Mise à jour MY APPS (*.zip)|*.zip'
            if ($path) { Install-LauncherUpdate $path }
        } catch { Show-Error $_.Exception.Message }
    })
    $ui.SearchBox.Add_TextChanged({ Render-Apps })
    foreach ($navigation in @($ui.AllNav, $ui.PackNav, $ui.LinkNav)) {
        $navigation.Add_Checked({ Render-Apps })
    }
    $ui.AppsGrid.AddHandler(
        [Windows.Controls.Primitives.ButtonBase]::ClickEvent,
        [Windows.RoutedEventHandler]{
            param($sender, $eventArgs)
            $button = $eventArgs.OriginalSource
            if ($button -isnot [Windows.Controls.Button]) { return }
            $app = $button.DataContext
            try {
                switch ($button.Tag) {
                    'Open' { Open-App $app }
                    'Remove' { Remove-App $app }
                }
            } catch { Show-Error $_.Exception.Message }
        }
    )

    $script:appModels = @(Get-CardModels)
    Render-Apps
    [void]$form.ShowDialog()
} finally {
    if ($ownsMutex) { $mutex.ReleaseMutex() }
    $mutex.Dispose()
}
