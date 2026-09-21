<#
  Sortierer.ps1  —  Eigenstaendiges Datei-Sortierprogramm (ohne Claude)

  Sortiert LOSE Dateien (nicht rekursiv) im Zielordner. Reihenfolge der Pruefung:

    1. Modulnummer im DATEINAMEN  (z.B. "Modul_114", "M346")   -> Schule\Module\Modul <NNN>\<Unterordner>
    2. Modulnummer im INHALT      (Doc sagt z.B. "ICT Modul 431") -> passendes Modul       [nur .docx/.pptx/.xlsx/.txt/.md]
    3. Thema im Namen ODER Inhalt (z.B. "OSI"/"VPN"->117, "Hyper-V"->190) -> passendes Modul
    4. Bekannte Dateiendung (.pdf, .png, .docx ...)            -> Kategorie-Ordner
    5. Alles andere                                            -> Sonstiges

  In das Modul wird nur einsortiert, wenn das Modul BEREITS EINEN ORDNER hat und
  die Zuordnung sicher ist. Mehrdeutiges (z.B. blosses "Datenbank" zwischen den
  DB-Modulen 106/162/164) bleibt bewusst im Typ-Ordner statt falsch abgelegt.

  Regeln:
    - Loescht NIE. Verschiebt nur. Schreibt ein Undo-Log (CSV).
    - Laesst in Ruhe: .vhdx .avhdx .iso .download und Dateien ganz ohne Endung.
    - Arbeitet nur auf der obersten Ebene (geht NICHT in Unterordner hinein).

  Benutzung:
    .\Sortierer.ps1                                  # sortiert den Downloads-Ordner
    .\Sortierer.ps1 -Folder "C:\Pfad"                # anderer Ordner
    .\Sortierer.ps1 -Folder "C:\A","C:\B"            # mehrere Ordner in einem Lauf
    .\Sortierer.ps1 -DryRun                           # zeigt nur, was passieren WUERDE
    .\Sortierer.ps1 -NoContent                        # NUR nach Dateiname (kein Inhalt lesen, schneller)
    .\Sortierer.ps1 -Undo "C:\...\_sortier-log-....csv"   # Lauf rueckgaengig machen
#>

param(
  [string[]]$Folder = @("$env:USERPROFILE\Downloads"),
  [string]$Undo   = "",
  [switch]$DryRun,
  [switch]$NoContent
)

# Ordnerliste normalisieren: erlaubt ein einzelnes ";"-getrenntes Argument
# (aus der .bat) ODER ein echtes Array. Entfernt Anfuehrungszeichen und
# stoerende End-Backslashes, die sonst Pfade zerlegen.
$Folder = @($Folder | ForEach-Object { $_ -split ';' }) |
  ForEach-Object { $_.Trim().Trim('"').TrimEnd('\') } |
  Where-Object { $_ -ne '' }

# ---------- UNDO-MODUS ----------
if ($Undo) {
  if (-not (Test-Path $Undo)) { Write-Host "Log nicht gefunden: $Undo" -ForegroundColor Red; exit 1 }
  $rows = Import-Csv $Undo
  $back = 0; $fail = 0
  # rueckwaerts, damit Umbenennungen bei Konflikten korrekt zurueckgehen
  for ($k = $rows.Count - 1; $k -ge 0; $k--) {
    $r = $rows[$k]
    if (Test-Path -LiteralPath $r.Nach) {
      try {
        $vonDir = Split-Path $r.Von
        if (-not (Test-Path $vonDir)) { New-Item -ItemType Directory -Path $vonDir -Force | Out-Null }
        Move-Item -LiteralPath $r.Nach -Destination $r.Von -ErrorAction Stop
        $back++
      } catch { $fail++ }
    }
  }
  Write-Host ("Rueckgaengig gemacht: {0}  |  fehlgeschlagen: {1}" -f $back, $fail) -ForegroundColor Cyan
  exit 0
}

# ---------- KONFIGURATION ----------

# Endung -> Kategorie-Ordner
$map = @{
  '.png'='Bilder';'.jpg'='Bilder';'.jpeg'='Bilder';'.webp'='Bilder';'.svg'='Bilder';'.gif'='Bilder';'.bmp'='Bilder'
  '.pdf'='PDFs'
  '.docx'='Office-Dokumente';'.doc'='Office-Dokumente';'.odt'='Office-Dokumente';'.pptx'='Office-Dokumente';'.ppt'='Office-Dokumente';'.odp'='Office-Dokumente';'.xlsx'='Office-Dokumente';'.xls'='Office-Dokumente';'.csv'='Office-Dokumente'
  '.exe'='Programme-Installer';'.msi'='Programme-Installer'
  '.zip'='Archive-ZIP';'.rar'='Archive-ZIP';'.7z'='Archive-ZIP'
  '.sql'='Datenbanken-SQL';'.db'='Datenbanken-SQL';'.bak'='Datenbanken-SQL';'.db-journal'='Datenbanken-SQL';'.sqbpro'='Datenbanken-SQL'
  '.ps1'='Code-Skripte';'.js'='Code-Skripte';'.css'='Code-Skripte';'.html'='Code-Skripte';'.ini'='Code-Skripte';'.config'='Code-Skripte';'.dll'='Code-Skripte';'.otf'='Code-Skripte';'.ttf'='Code-Skripte';'.py'='Code-Skripte';'.json'='Code-Skripte';'.xml'='Code-Skripte'
  '.txt'='Text-Notizen';'.md'='Text-Notizen'
  '.mp4'='Videos-Audio';'.wav'='Videos-Audio';'.mp3'='Videos-Audio';'.mov'='Videos-Audio';'.mkv'='Videos-Audio'
  '.drawio'='Diagramme'
}

# Diese Endungen NIE anfassen (VM-Disks, Images, halbe Downloads)
$leaveExt = @('.vhdx','.avhdx','.iso','.download','.part','.crdownload','.tmp')

# In diese Dateitypen kann der Inhalt gelesen werden (fuer Schritt 2 + 3)
$readExt = @('.docx','.pptx','.xlsx','.txt','.md')

# Schule-Modulbasis (wird uebersprungen falls nicht vorhanden)
$modBase = "C:\Users\aeber\OneDrive - ipso! Bildung\Schule\Module"
$subs    = 'If_Projekt','Informationen','Lerndokumentation','Powerpoints'

$fallback = 'Sonstiges'   # <- hier landet alles, was nirgends passt

# Eigene Programm-Dateien nie verschieben
$selfNames = @('Sortierer.ps1','Sortieren.bat','sortier-icon.ico','icon-preview.png')

# THEMA -> MODULNUMMER  (Schritt 3). Nur SICHERE, eindeutige Themen eintragen!
# Wird gegen Dateiname UND Inhalt geprueft. Mehrdeutiges bewusst weglassen
# (z.B. blosses "Datenbank"/"SQL" -> gibt es bei dir in 106/162/164).
# Erweitern ist einfach: Regex = 'stichwort1|stichwort2' ; Wert = '117'
$topicMap = [ordered]@{
  '(?i)hyper-?v|virtualisierung|virtuelle?\s+maschine'                        = '190'
  '(?i)\bosi\b|\bvpn\b|\bwlan\b|\blan\b|verkabelung|netzwerkplan|patchpanel|rj45|subnetz|osi-schicht' = '117'
  '(?i)\bcloud\b|iaas|paas|saas'                                              = '346'
  '(?i)kompress|huffman|lauflaenge|entropie-?kod'                             = '114'
}

# ---------- HILFSFUNKTIONEN ----------

# Vorhandene Modulnummern -> echter Ordnername (z.B. "114" -> "Modul 114 ( done )")
$fm = @{}
if (Test-Path $modBase) {
  Get-ChildItem $modBase -Directory -ErrorAction SilentlyContinue | ForEach-Object {
    if ($_.Name -match '(\d{3})') { $fm[$matches[1]] = $_.Name }
  }
}

# --- Inhalt einer Datei als Fliesstext holen (docx/pptx/xlsx = ZIP mit XML) ---
Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue
function Get-FileText($file, $maxChars = 6000) {
  $ext = $file.Extension.ToLower()
  try {
    if ($ext -eq '.txt' -or $ext -eq '.md') {
      $t = Get-Content -LiteralPath $file.FullName -Raw -ErrorAction Stop
      return $t.Substring(0, [Math]::Min($maxChars, $t.Length))
    }
    if ($ext -eq '.docx' -or $ext -eq '.pptx' -or $ext -eq '.xlsx') {
      $zip = [System.IO.Compression.ZipFile]::OpenRead($file.FullName)
      try {
        $sb = New-Object System.Text.StringBuilder
        foreach ($e in $zip.Entries) {
          if ($e.FullName -match '^(word/document\.xml|ppt/slides/slide\d+\.xml|xl/sharedStrings\.xml)$') {
            $r = New-Object System.IO.StreamReader($e.Open())
            [void]$sb.Append(' '); [void]$sb.Append($r.ReadToEnd()); $r.Close()
            if ($sb.Length -ge $maxChars * 3) { break }
          }
        }
        $t = $sb.ToString() -replace '<[^>]+>', ' ' -replace '\s+', ' '
        return $t.Substring(0, [Math]::Min($maxChars, $t.Length))
      } finally { $zip.Dispose() }
    }
  } catch { return '' }
  return ''
}

# --- Modulnummer aus einem Text ziehen (haeufigste Nennung gewinnt) ---
# Nur "Modul NNN" / "M NNN" / "ICT-Modul NNN" zaehlen, blosse Zahlen NICHT.
function ModuleFromText($text) {
  if ([string]::IsNullOrEmpty($text)) { return $null }
  $hits = @{}
  foreach ($mt in [regex]::Matches($text, '(?i)(?:modul|ict[\s_.\-]*modul|m)[\s_.\-]{0,3}(\d{3})')) {
    $n = $mt.Groups[1].Value
    if ($fm.ContainsKey($n)) { if (-not $hits[$n]) { $hits[$n] = 0 }; $hits[$n]++ }
  }
  if ($hits.Count -eq 0) { return $null }
  return ($hits.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 1).Key
}

# --- Thema (Keyword-Map) auf Name+Inhalt anwenden ---
function ModuleFromTopic($text) {
  if ([string]::IsNullOrEmpty($text)) { return $null }
  foreach ($k in $topicMap.Keys) {
    if ($text -match $k) {
      $n = $topicMap[$k]
      if ($fm.ContainsKey($n)) { return $n }
    }
  }
  return $null
}

# Welcher Modul-Unterordner passt? (Name zuerst, Inhalt als Rueckfall)
function SubOf($f, $content) {
  if ($f.Extension -match '(?i)\.(pptx|ppt|odp)$') { return 'Powerpoints' }
  $hay = $f.BaseName + ' ' + $content
  if ($hay -match '(?i)(lerndoku|moduldoku|modul.?doku|lernjournal|lernblatt|dokumentation|\bdoku\b)') { return 'Lerndokumentation' }
  if ($hay -match '(?i)(projekt|demo.?site)') { return 'If_Projekt' }
  # Auftrag/Aufgabe/Teilaufgabe -> laut Wunsch nach "Informationen"
  return 'Informationen'
}

# Modulnummer im Dateinamen (oder $null). exe/msi/dll ausgeschlossen (Versionsnummern!)
function ModuleFromName($f) {
  if ($f.Extension -match '(?i)\.(exe|msi|dll)$') { return $null }
  foreach ($m in $fm.Keys) {
    if ($f.BaseName -match "(?i)(^|[\s_.\-(])(m|modul[\s_.\-]*)?$m($|[\s_.\-)])") { return $m }
  }
  return $null
}

# Nennt der DATEINAME ausdruecklich ein Modul (z.B. "M129"/"Modul 129")?
# Gibt die Nummer zurueck, egal ob es dafuer schon einen Ordner gibt.
# So verhindern wir, dass z.B. eine "M129"-Datei per Thema faelschlich in 117 landet.
function ExplicitModuleInName($f) {
  if ($f.BaseName -match '(?i)(?:^|[\s_.\-(])(?:m|modul[\s_.\-]*)(\d{3})(?:$|[\s_.\-)])') { return $matches[1] }
  return $null
}

# Freien Zielpfad finden (bei Namenskonflikt " (1)", " (2)" ... anhaengen)
function FreeDest($dir, $name) {
  $dest = Join-Path $dir $name
  if (-not (Test-Path -LiteralPath $dest)) { return $dest }
  $b = [IO.Path]::GetFileNameWithoutExtension($name)
  $e = [IO.Path]::GetExtension($name)
  $i = 1
  do { $dest = Join-Path $dir ("{0} ({1}){2}" -f $b,$i,$e); $i++ } while (Test-Path -LiteralPath $dest)
  return $dest
}

# ---------- HAUPTLAUF ----------

$log    = New-Object System.Collections.Generic.List[object]
$counts = @{}

foreach ($currentFolder in $Folder) {
  if (-not (Test-Path $currentFolder)) { Write-Host "Ordner fehlt (uebersprungen): $currentFolder" -ForegroundColor Yellow; continue }
  Write-Host ("--- $currentFolder ---") -ForegroundColor DarkCyan

  $files = Get-ChildItem -LiteralPath $currentFolder -File -ErrorAction SilentlyContinue
  foreach ($f in $files) {
    # eigene Logs und schon-sortiert-Marker ueberspringen
    if ($f.Name -like '_sortier*' -or $f.Name -like '_clean*') { continue }
    if ($selfNames -contains $f.Name) { continue }
    $ext = $f.Extension.ToLower()
    # ohne Endung oder auf der Nie-anfassen-Liste -> liegen lassen
    if ([string]::IsNullOrEmpty($ext) -or $leaveExt -contains $ext) { continue }

    $mod = $null
    $content = ''

    # 1) Modulnummer im Dateinamen
    $mod = ModuleFromName $f

    # Nennt der Name ein Modul OHNE Ordner (z.B. M129)? Dann NICHT per Thema
    # in ein anderes Modul raten -> lieber im Typ-Ordner lassen.
    $explicit = ExplicitModuleInName $f
    $blockGuess = ($explicit -and -not $fm.ContainsKey($explicit))

    # 2) + 3) Inhalt lesen, falls Name nichts ergab und Typ lesbar ist
    if (-not $mod -and -not $blockGuess -and -not $NoContent -and ($readExt -contains $ext)) {
      $content = Get-FileText $f
      $mod = ModuleFromText $content            # 2) Modul steht im Text
      if (-not $mod) { $mod = ModuleFromTopic ($f.BaseName + ' ' + $content) }  # 3) Thema
    }
    # 3b) Thema auch ohne Inhalt wenigstens am Namen pruefen
    if (-not $mod -and -not $blockGuess) { $mod = ModuleFromTopic $f.BaseName }

    if ($mod -and (Test-Path $modBase)) {
      $modDir = Join-Path $modBase $fm[$mod]
      foreach ($s in $subs) { $sp = Join-Path $modDir $s; if (-not (Test-Path $sp) -and -not $DryRun) { New-Item -ItemType Directory -Path $sp | Out-Null } }
      $targetDir = Join-Path $modDir (SubOf $f $content)
      $grund = "Modul $mod -> $(Split-Path $targetDir -Leaf)"
    }
    elseif ($map.ContainsKey($ext)) {
      $targetDir = Join-Path $currentFolder $map[$ext]
      $grund = "Typ: $($map[$ext])"
    }
    else {
      $targetDir = Join-Path $currentFolder $fallback
      $grund = "Sonstiges (unbekannt)"
    }

    if ($DryRun) {
      Write-Host ("[Vorschau] {0,-46} -> {1}" -f $f.Name, $grund)
      if (-not $counts[$grund]) { $counts[$grund] = 0 }
      $counts[$grund]++
      continue
    }

    if (-not (Test-Path $targetDir)) { New-Item -ItemType Directory -Path $targetDir | Out-Null }
    $dest = FreeDest $targetDir $f.Name
    try {
      Move-Item -LiteralPath $f.FullName -Destination $dest -ErrorAction Stop
      $log.Add([pscustomobject]@{ Von=$f.FullName; Nach=$dest; Grund=$grund })
      if (-not $counts[$grund]) { $counts[$grund] = 0 }
      $counts[$grund]++
    } catch {
      Write-Host ("  ! konnte nicht verschieben: {0}" -f $f.Name) -ForegroundColor Yellow
    }
  }
}

# ---------- ZUSAMMENFASSUNG ----------
Write-Host ""
if ($DryRun) {
  Write-Host "-- Nur Vorschau, nichts verschoben --" -ForegroundColor Yellow
} else {
  $logPath = Join-Path "$env:USERPROFILE\Downloads" ("_sortier-log-{0}.csv" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
  $log | Export-Csv -LiteralPath $logPath -NoTypeInformation -Encoding UTF8
  Write-Host ("Verschoben insgesamt: {0}" -f $log.Count) -ForegroundColor Green
}
$counts.GetEnumerator() | Sort-Object Name | ForEach-Object { "  {0,-40} {1}" -f $_.Key, $_.Value }
if (-not $DryRun -and $log.Count -gt 0) {
  Write-Host ""
  Write-Host ("Undo-Log: {0}" -f $logPath)
  Write-Host ("Rueckgaengig machen:  .\Sortierer.ps1 -Undo `"{0}`"" -f $logPath)
}
