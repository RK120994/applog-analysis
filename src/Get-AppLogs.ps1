param(
    [string]$IndexUrl = "https://files.singular-devops.com/challenges/01-applogs/index.txt",
    [string]$BaseUrl  = "https://files.singular-devops.com/challenges/01-applogs/"
)

# --- Setup directories ---
$logsDir   = Join-Path $PWD "logs"
$reportDir = Join-Path $PWD "report"

New-Item -ItemType Directory -Path $logsDir   -Force | Out-Null
New-Item -ItemType Directory -Path $reportDir -Force | Out-Null

Write-Host "Downloading index file..."
$indexFile = Join-Path $PWD "index.txt"
Invoke-WebRequest -Uri $IndexUrl -OutFile $indexFile -UseBasicParsing

# --- Read index entries ---
$files = Get-Content $indexFile | Where-Object { $_.Trim() -ne "" }

Write-Host "Found $($files.Count) log files."

# ---------------------------
# Helper: parse log row
# ---------------------------
function Parse-FixedWidthRow {
    param($line)

    # Based on schema.md (simplified):
    # Date      - chars 1-10
    # Time      - chars 11-19
    # Severity  - chars 20-29
    # Message   - chars 30-end

    return [PSCustomObject]@{
        Date     = $line.Substring(0,10).Trim()
        Severity = $line.Substring(19,10).Trim()
    }
}

# --- Prepare statistics ---
$monthStats = @{}

foreach ($file in $files) {

    $url  = "$BaseUrl$file"
    $dest = Join-Path $logsDir $file

    Write-Host "Downloading $file..."
    Invoke-WebRequest -Uri $url -OutFile $dest -UseBasicParsing

    Write-Host "Processing $file..."

    foreach ($line in Get-Content $dest) {

        $row = Parse-FixedWidthRow $line

        # Extract month + year
        $dt = [datetime]::ParseExact($row.Date, "yyyy-MM-dd", $null)
        $key = "{0}-{1:D2}" -f $dt.Year, $dt.Month

        if (-not $monthStats.ContainsKey($key)) {
            $monthStats[$key] = @{
                Year        = $dt.Year
                Month       = $dt.Month
                Information = 0
                Warning     = 0
                Error       = 0
            }
        }

        switch ($row.Severity.ToLower()) {
            "information" { $monthStats[$key].Information++ }
            "warning"     { $monthStats[$key].Warning++ }
            "error"       { $monthStats[$key].Error++ }
        }
    }
}

# --- Sort and calculate month-to-month % change ---
$sorted = $monthStats.GetEnumerator() |
          Sort-Object Name |
          ForEach-Object { $_.Value }

for ($i=0; $i -lt $sorted.Count; $i++) {
    if ($i -eq 0) {
        $sorted[$i].WarningChange = 0
        $sorted[$i].ErrorChange   = 0
        continue
    }

    $prev = $sorted[$i-1]
    $curr = $sorted[$i]

    function Calc-Change($prevVal, $currVal) {
        if ($prevVal -eq 0) { return 0 }
        return [math]::Round((($currVal - $prevVal) / $prevVal) * 100, 2)
    }

    $curr.WarningChange = Calc-Change $prev.Warning $curr.Warning
    $curr.ErrorChange   = Calc-Change $prev.Error   $curr.Error
}

# --- Save report.json ---
$reportJson = Join-Path $reportDir "report.json"
$sorted | ConvertTo-Json -Depth 5 | Out-File $reportJson -Encoding utf8
Write-Host "Saved report.json"

# --- Generate index.html ---
$html = @"
<html>
<head>
<title>Application Log Report</title>
<style>
body { font-family: Arial; margin:20px; }
table { border-collapse: collapse; width: 100%; }
th, td { border:1px solid #666; padding:8px; text-align:center; }
th { background:#333; color:white; }
</style>
</head>
<body>
<h2>Application Log Report</h2>
<table>
<tr>
<th>Year</th>
<th>Month</th>
<th>Information</th>
<th>Warnings</th>
<th>Errors</th>
<th>% Change Warnings</th>
<th>% Change Errors</th>
</tr>
"@

foreach ($row in $sorted) {
    $html += "<tr>
<td>$($row.Year)</td>
<td>$($row.Month)</td>
<td>$($row.Information)</td>
<td>$($row.Warning)</td>
<td>$($row.Error)</td>
<td>$($row.WarningChange)%</td>
<td>$($row.ErrorChange)%</td>
</tr>"
}

$html += "</table></body></html>"

$html | Out-File (Join-Path $reportDir "index.html") -Encoding utf8

Write-Host "HTML report created."
