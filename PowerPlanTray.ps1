Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Funzione per distruggere HIcon (rilasciare risorse)
Add-Type -MemberDefinition @'
    [System.Runtime.InteropServices.DllImport("user32.dll", SetLastError = true)]
    public static extern bool DestroyIcon(IntPtr hIcon);
'@ -Name 'Win32Helper' -Namespace 'PInvoke'

# --- Caricamento icone standard con fallback ---
function Try-LoadIcon($path, $fallback) {
    if (Test-Path $path) {
        try {
            return [System.Drawing.Icon]::ExtractAssociatedIcon((Resolve-Path $path).Path)
        } catch {
            return $fallback
        }
    } else {
        return $fallback
    }
}

# Creiamo un'icona fallback semplice (small system icon)
$defaultSysIcon = [System.Drawing.SystemIcons]::Application

$iconEco  = Try-LoadIcon ".\eco.ico"  $defaultSysIcon
$iconBal  = Try-LoadIcon ".\bal.ico"  $defaultSysIcon
$iconPerf = Try-LoadIcon ".\perf.ico" $defaultSysIcon

# Mappa nomi standard -> icone (nomi usati comunemente in italiano)
$standardProfiles = @{
    "Risparmio di energia" = $iconEco
    "Bilanciato"           = $iconBal
    "Prestazioni elevate"  = $iconPerf
}

# --- Legge i profili dal sistema (robusto rispetto alla lingua) ---
$profiles = @{}       # Nome -> GUID
$profileIcons = @{}   # Nome -> Icon

$raw = & powercfg -list 2>$null
if (-not $raw) {
    Write-Host "Impossibile ottenere la lista dei profili con powercfg -list. Verifica che powercfg sia disponibile." -ForegroundColor Yellow
}

$customIndex = 1

foreach ($line in $raw) {
    # Cerchiamo prima il GUID (36 char con trattini) e poi, se presente, il nome tra parentesi
    if ($line -match '([0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}).*\((.+?)\)') {
        $guid = $matches[1]
        $name = $matches[2].Trim()

        $profiles[$name] = $guid

        if ($standardProfiles.ContainsKey($name)) {
            $profileIcons[$name] = $standardProfiles[$name]
        } else {
            # Creiamo un'icona dinamica con numero
            $size = 32
            $bmp = New-Object System.Drawing.Bitmap $size, $size
            $g = [System.Drawing.Graphics]::FromImage($bmp)
            try {
                $g.Clear([System.Drawing.Color]::FromArgb(64,64,64))
                $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit

                $fontSize = 16
                $font = New-Object System.Drawing.Font("Segoe UI", $fontSize, [System.Drawing.FontStyle]::Bold)

                $text = $customIndex.ToString()
                # misura testo per centrarlo
                $sizeF = $g.MeasureString($text, $font)
                $x = ([math]::Max(0,($size - $sizeF.Width)/2))
                $y = ([math]::Max(0,($size - $sizeF.Height)/2)) - 1

                $brush = [System.Drawing.Brushes]::White
                $g.DrawString($text, $font, $brush, $x, $y)
            } finally {
                $g.Dispose()
            }

            # Convertiamo Bitmap -> Icon in modo sicuro
            $hIcon = $bmp.GetHicon()
            $origIcon = [System.Drawing.Icon]::FromHandle($hIcon)
            # cloniamo l'icona così possiamo distruggere l'handle originale
            $clonedIcon = $origIcon.Clone()
            # rilascio handle e oggetti temporanei
            [PInvoke.Win32Helper]::DestroyIcon($hIcon) | Out-Null
            $origIcon.Dispose()
            $bmp.Dispose()

            $profileIcons[$name] = $clonedIcon

            $customIndex++
        }
    }
}

# --- Funzione per ottenere GUID del profilo attivo (robusta) ---
function Get-ActivePowerPlanGuid {
    $output = & powercfg /getactivescheme 2>$null
    if ($output -match '([0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12})') {
        return $matches[1].Trim()
    }
    return $null
}

# --- Creazione notify icon ---
$notifyIcon = New-Object System.Windows.Forms.NotifyIcon
$notifyIcon.Visible = $true

function Update-Icon {
    $currentGuid = Get-ActivePowerPlanGuid
    $currentName = ($profiles.GetEnumerator() | Where-Object { $_.Value -eq $currentGuid }).Key

    if ($currentName -and $profileIcons.ContainsKey($currentName)) {
        $notifyIcon.Icon = $profileIcons[$currentName]
    } else {
        $notifyIcon.Icon = $iconBal
        if (-not $currentName) { $currentName = "Sconosciuto" }
    }

    # Il testo ha limite di 63 caratteri in Windows tray
    $shortName = if ($currentName.Length -gt 60) { $currentName.Substring(0,57) + "..." } else { $currentName }
    $notifyIcon.Text = "Profilo attivo: $shortName"
}

# --- Menu della tray ---
$menu = New-Object System.Windows.Forms.ContextMenuStrip

foreach ($mode in $profiles.Keys) {
    $item = New-Object System.Windows.Forms.ToolStripMenuItem $mode
    # opzionale: aggiungiamo l'icona al menu (solo se disponibile)
    if ($profileIcons.ContainsKey($mode)) {
        try { $item.Image = $profileIcons[$mode].ToBitmap() } catch {}
    }

    $item.Add_Click({
        param($sender, $args)
        $selected = $sender.Text
        if ($profiles.ContainsKey($selected)) {
            # Imposta il profilo attivo
            & powercfg /setactive $profiles[$selected] 2>$null
            Start-Sleep -Milliseconds 200
            Update-Icon
        } else {
            [System.Windows.Forms.MessageBox]::Show("Impossibile trovare il profilo selezionato.")
        }
    })
    $menu.Items.Add($item) | Out-Null
}

# Apri Opzioni risparmio energia
$openPowerOptions = New-Object System.Windows.Forms.ToolStripMenuItem "Apri opzioni risparmio energia"
$openPowerOptions.Add_Click({
    Start-Process "control.exe" "powercfg.cpl"
})
$menu.Items.Add($openPowerOptions)


# Esci
$exitItem = New-Object System.Windows.Forms.ToolStripMenuItem "Esci"
$exitItem.Add_Click({
    $notifyIcon.Visible = $false
    [System.Windows.Forms.Application]::Exit()
})
$menu.Items.Add($exitItem) | Out-Null




$notifyIcon.ContextMenuStrip = $menu

# Primo aggiornamento
Update-Icon

# Timer per aggiornamento automatico dell’icona ogni 2 secondi
$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 2000   # 2000 ms = 2 secondi
$timer.Add_Tick({
    Update-Icon
})
$timer.Start()




# Avvio loop WinForms
[System.Windows.Forms.Application]::Run()
