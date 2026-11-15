Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName PresentationFramework

$baseVersion = [version]'1.4.0'
$versionsPath = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'MY_APPS\VersionsLauncher'

try {
    $installed = @(
        if ([IO.Directory]::Exists($versionsPath)) {
            foreach ($directory in Get-ChildItem -LiteralPath $versionsPath -Directory) {
                [version]$candidate = $null
                if (-not [version]::TryParse($directory.Name, [ref]$candidate) -or
                    $candidate -le $baseVersion -or $candidate.Build -lt 0 -or $candidate.Revision -ne -1 -or
                    $candidate.ToString() -cne $directory.Name) { continue }

                $script = Join-Path $directory.FullName 'MY_APPS_App.ps1'
                $layout = Join-Path $directory.FullName 'MY_APPS.xaml'
                if ([IO.File]::Exists($script) -and [IO.File]::Exists($layout)) {
                    [pscustomobject]@{ Version = $candidate; Script = $script }
                }
            }
        }
    )

    foreach ($release in ($installed | Sort-Object Version -Descending)) {
        try {
            & $release.Script -AppVersion $release.Version -VersionsPath $versionsPath
            return
        } catch {
            [void][System.Windows.MessageBox]::Show(
                "La version $($release.Version) n’a pas pu démarrer. MY APPS va essayer la version précédente.",
                'MY APPS', 'OK', 'Warning'
            )
        }
    }

    & (Join-Path $PSScriptRoot 'MY_APPS_App.ps1') -AppVersion $baseVersion -VersionsPath $versionsPath
} catch {
    [void][System.Windows.MessageBox]::Show($_.Exception.Message, 'MY APPS', 'OK', 'Error')
    exit 1
}
