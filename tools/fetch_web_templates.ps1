param([string]$Version = '4.7.2', [switch]$FullDownload)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Net.Http
$client = [System.Net.Http.HttpClient]::new()
$client.Timeout = [TimeSpan]::FromMinutes(10)
$url = "https://github.com/godotengine/godot-builds/releases/download/$Version-stable/Godot_v$Version-stable`_export_templates.tpz"
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$destination = Join-Path $root ".tools/portable/editor_data/export_templates/$Version.stable"
[IO.Directory]::CreateDirectory($destination) | Out-Null

function Read-Range([string]$Range) {
    if ($FullDownload) {
        $stream = [IO.File]::OpenRead($archive)
        try {
            if ($Range.StartsWith('-')) {
                $length = [int]$Range.Substring(1)
                $start = $stream.Length - $length
            } else {
                $parts = $Range.Split('-')
                $start = [long]$parts[0]
                $length = [int]([long]$parts[1] - $start + 1)
            }
            $stream.Position = $start
            $bytes = [byte[]]::new($length)
            $read = 0
            while ($read -lt $length) {
                $count = $stream.Read($bytes, $read, $length - $read)
                if ($count -eq 0) { throw 'Unexpected end of ZIP archive' }
                $read += $count
            }
            return ,$bytes
        } finally { $stream.Dispose() }
    }
    $request = [System.Net.Http.HttpRequestMessage]::new([System.Net.Http.HttpMethod]::Get, $url)
    $request.Headers.TryAddWithoutValidation('Range', "bytes=$Range") | Out-Null
    $response = $client.SendAsync($request, [System.Net.Http.HttpCompletionOption]::ResponseHeadersRead).GetAwaiter().GetResult()
    try {
        if ($response.StatusCode -ne [System.Net.HttpStatusCode]::PartialContent) {
            throw "Server did not honor byte ranges: $($response.StatusCode)"
        }
        $bytes = $response.Content.ReadAsByteArrayAsync().GetAwaiter().GetResult()
        return ,$bytes
    } finally {
        $response.Dispose()
        $request.Dispose()
    }
}

try {
    if ($FullDownload) {
        $archive = Join-Path $root ".tools/Godot_v$Version-stable`_export_templates.tpz"
        Write-Output 'Downloading official template archive; Web-only byte ranges are unavailable on this network.'
        if (-not (Test-Path -LiteralPath $archive)) {
            & curl.exe --fail --location --silent --show-error --max-time 1800 --output ($archive + '.tmp') $url
            if ($LASTEXITCODE -ne 0) { throw "Template download failed: curl exit $LASTEXITCODE" }
            Move-Item -LiteralPath ($archive + '.tmp') -Destination $archive
        }
    }
    if (-not $FullDownload) {
        $head = $client.SendAsync([System.Net.Http.HttpRequestMessage]::new([System.Net.Http.HttpMethod]::Head, $url)).GetAwaiter().GetResult()
        try {
            $head.EnsureSuccessStatusCode() | Out-Null
            $url = $head.RequestMessage.RequestUri.AbsoluteUri
        } finally { $head.Dispose() }
    }
    $tail = Read-Range '-65536'
    $end = -1
    for ($i = $tail.Length - 22; $i -ge 0; $i--) {
        if ([BitConverter]::ToUInt32($tail, $i) -eq 0x06054b50) { $end = $i; break }
    }
    if ($end -lt 0) { throw 'ZIP directory not found' }
    $directorySize = [BitConverter]::ToUInt32($tail, $end + 12)
    $directoryOffset = [BitConverter]::ToUInt32($tail, $end + 16)
    if ($directoryOffset -eq [uint32]::MaxValue) { throw 'ZIP64 archives are not supported by this helper' }
    $directory = Read-Range "$directoryOffset-$($directoryOffset + $directorySize - 1)"
    $offset = 0
    $installed = 0
    while ($offset + 46 -le $directory.Length) {
        if ([BitConverter]::ToUInt32($directory, $offset) -ne 0x02014b50) { throw 'Invalid ZIP directory entry' }
        $method = [BitConverter]::ToUInt16($directory, $offset + 10)
        $compressedSize = [BitConverter]::ToUInt32($directory, $offset + 20)
        $size = [BitConverter]::ToUInt32($directory, $offset + 24)
        $nameLength = [BitConverter]::ToUInt16($directory, $offset + 28)
        $extraLength = [BitConverter]::ToUInt16($directory, $offset + 30)
        $commentLength = [BitConverter]::ToUInt16($directory, $offset + 32)
        $headerOffset = [BitConverter]::ToUInt32($directory, $offset + 42)
        $name = [Text.Encoding]::UTF8.GetString($directory, $offset + 46, $nameLength)
        $offset += 46 + $nameLength + $extraLength + $commentLength
        if ($name -notmatch '/web[^/]*release\.zip$') { continue }
        $output = Join-Path $destination ([IO.Path]::GetFileName($name))
        if ((Test-Path -LiteralPath $output) -and (Get-Item -LiteralPath $output).Length -eq $size) {
            Write-Output "Already installed: $name"
            $installed++
            continue
        }
        Write-Output "Downloading $name ($compressedSize bytes)"
        $header = Read-Range "$headerOffset-$($headerOffset + 29)"
        if ([BitConverter]::ToUInt32($header, 0) -ne 0x04034b50) { throw 'Invalid ZIP local header' }
        $dataOffset = $headerOffset + 30 + [BitConverter]::ToUInt16($header, 26) + [BitConverter]::ToUInt16($header, 28)
        $payload = Read-Range "$dataOffset-$($dataOffset + $compressedSize - 1)"
        $input = [IO.MemoryStream]::new($payload, $false)
        $stream = if ($method -eq 8) { [IO.Compression.DeflateStream]::new($input, [IO.Compression.CompressionMode]::Decompress) } elseif ($method -eq 0) { $input } else { throw "Unsupported ZIP compression $method" }
        $file = [IO.File]::Create($output + '.tmp')
        try { $stream.CopyTo($file) } finally { $file.Dispose(); $stream.Dispose(); $input.Dispose() }
        if ((Get-Item -LiteralPath ($output + '.tmp')).Length -ne $size) { throw 'Extracted template size mismatch' }
        Move-Item -LiteralPath ($output + '.tmp') -Destination $output -Force
        $installed++
        Write-Output "Installed $output"
    }
    if ($installed -eq 0) { throw 'No Web release templates found' }
} finally { $client.Dispose() }
