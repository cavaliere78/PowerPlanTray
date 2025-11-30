Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# --- GUID dei piani energetici ---

$profiles = @{
"Risparmio di energia"   = "a1841308-3541-4fab-bc81-f71556f20b4a"
"Bilanciato"             = "381b4222-f694-41f0-9685-ff5bb260df2e"
"Prestazioni elevate"    = "8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c"
}

function Get-ActivePowerPlanGuid {
$output = powercfg /getactivescheme
if ($output -match ':\s*([a-f0-9-]+)') {
return $matches[1].Trim()
} else {
return $null
}
}

# --- Creazione Tray Icon ---

$notifyIcon = New-Object System.Windows.Forms.NotifyIcon
$notifyIcon.Visible = $true

# Funzione per creare icone Unicode

function Create-Icon([string]$symbol, [string]$color) {
$bmp = New-Object System.Drawing.Bitmap 32,32
$graphics = [System.Drawing.Graphics]::FromImage($bmp)

$graphics.Clear([System.Drawing.Color]::Transparent)
$brush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::$color)

$font = New-Object System.Drawing.Font "Segoe UI Symbol", 20
$graphics.DrawString($symbol, $font, $brush, -3, -4)
$graphics.Dispose()

$hIcon = $bmp.GetHicon()
return [System.Drawing.Icon]::FromHandle($hIcon)

}

$iconEco  = Create-Icon "1" "Green"
$iconBal  = Create-Icon "2" "Blue"
$iconPerf = Create-Icon "3" "Red"

function Update-Icon {
$currentGuid = Get-ActivePowerPlanGuid


switch ($currentGuid) {
    $profiles["Risparmio di energia"]   { $notifyIcon.Icon = $iconEco }
    $profiles["Bilanciato"]             { $notifyIcon.Icon = $iconBal }
    $profiles["Prestazioni elevate"]    { $notifyIcon.Icon = $iconPerf }
    default                             { $notifyIcon.Icon = $iconBal }
}

# Aggiorna testo tray
$currentName = ($profiles.GetEnumerator() | Where-Object { $_.Value -eq $currentGuid }).Key
if (-not $currentName) { $currentName = "Sconosciuto" }
$notifyIcon.Text = "Profilo attivo: $currentName"


}

# --- Menu della Tray ---

$menu = New-Object System.Windows.Forms.ContextMenuStrip

foreach ($mode in $profiles.Keys) {
$item = New-Object System.Windows.Forms.ToolStripMenuItem $mode
$item.Add_Click({
param($sender, $args)
$selected = $sender.Text
powercfg /setactive $profiles[$selected] | Out-Null
Update-Icon
})
$menu.Items.Add($item)
}

# Elemento Esci

$exitItem = New-Object System.Windows.Forms.ToolStripMenuItem "Esci"
$exitItem.Add_Click({
$notifyIcon.Visible = $false
[System.Windows.Forms.Application]::Exit()
})
$menu.Items.Add($exitItem)

$notifyIcon.ContextMenuStrip = $menu

# Aggiorna icona all’avvio

Update-Icon

# Avvia loop eventi WinForms

[System.Windows.Forms.Application]::Run()

