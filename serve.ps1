param(
    [int]$Port = 8000,
    [switch]$Lan,
    [switch]$OpenBrowser
)

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$rootFullPath = [System.IO.Path]::GetFullPath($root)
$bindAddress = if ($Lan) { [System.Net.IPAddress]::Any } else { [System.Net.IPAddress]::Loopback }
$listener = [System.Net.Sockets.TcpListener]::new($bindAddress, $Port)

$contentTypes = @{
    '.html' = 'text/html; charset=utf-8'
    '.css'  = 'text/css; charset=utf-8'
    '.js'   = 'application/javascript; charset=utf-8'
    '.json' = 'application/json; charset=utf-8'
    '.xml'  = 'application/xml; charset=utf-8'
    '.txt'  = 'text/plain; charset=utf-8'
    '.jpg'  = 'image/jpeg'
    '.jpeg' = 'image/jpeg'
    '.png'  = 'image/png'
    '.gif'  = 'image/gif'
    '.svg'  = 'image/svg+xml'
    '.ico'  = 'image/x-icon'
    '.webp' = 'image/webp'
}

function Get-TargetPath {
    param([string]$RequestPath)

    $cleanPath = ($RequestPath -split '\?')[0]
    $relativePath = [System.Uri]::UnescapeDataString($cleanPath.TrimStart('/'))

    if ([string]::IsNullOrWhiteSpace($relativePath)) {
        return Join-Path $root 'index.html'
    }

    $candidate = Join-Path $root $relativePath
    $candidateFullPath = [System.IO.Path]::GetFullPath($candidate)

    if (-not $candidateFullPath.StartsWith($rootFullPath, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $null
    }

    if ((Test-Path $candidateFullPath) -and -not (Get-Item $candidateFullPath).PSIsContainer) {
        return $candidateFullPath
    }

    return $null
}

function Write-Response {
    param(
        [System.IO.Stream]$Stream,
        [int]$StatusCode,
        [string]$StatusText,
        [byte[]]$Body,
        [string]$ContentType,
        [Nullable[int]]$ContentLength = $null
    )

    $length = if ($null -ne $ContentLength) { $ContentLength } else { $Body.Length }

    $headers = @(
        "HTTP/1.1 $StatusCode $StatusText",
        "Content-Type: $ContentType",
        "Content-Length: $length",
        'Connection: close',
        ''
        ''
    ) -join "`r`n"

    $headerBytes = [System.Text.Encoding]::ASCII.GetBytes($headers)
    $Stream.Write($headerBytes, 0, $headerBytes.Length)
    $Stream.Write($Body, 0, $Body.Length)
}

function Get-LocalIPv4 {
    [System.Net.Dns]::GetHostAddresses([System.Net.Dns]::GetHostName()) |
        Where-Object {
            $_.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetwork -and
            -not $_.IPAddressToString.StartsWith('127.') -and
            -not $_.IPAddressToString.StartsWith('169.254.')
        } |
        Select-Object -ExpandProperty IPAddressToString -Unique
}

try {
    $listener.Start()

    $localhostUrl = "http://localhost:$Port/"

    if ($Lan) {
        $ips = Get-LocalIPv4
        Write-Host "Local site is running at $localhostUrl"
        if ($ips) {
            Write-Host 'Local site is running on the network. Try one of these addresses:'
            foreach ($ip in $ips) {
                Write-Host "  http://${ip}:$Port/"
            }
        }
        else {
            Write-Host "Local site is running on the network at http://<YOUR-PC-IP>:$Port/"
        }
    }
    else {
        Write-Host "Local site is running at $localhostUrl"
    }

    if ($OpenBrowser) {
        Start-Process $localhostUrl
    }

    Write-Host 'Press Ctrl+C to stop.'
    if ($Lan) {
        Write-Host 'If another device cannot connect, allow PowerShell through Windows Firewall for this network.'
    }

    while ($true) {
        $client = $listener.AcceptTcpClient()

        try {
            $stream = $client.GetStream()
            $reader = [System.IO.StreamReader]::new($stream, [System.Text.Encoding]::ASCII, $false, 1024, $true)

            $requestLine = $reader.ReadLine()
            if ([string]::IsNullOrWhiteSpace($requestLine)) {
                continue
            }

            while ($true) {
                $headerLine = $reader.ReadLine()
                if ([string]::IsNullOrEmpty($headerLine)) {
                    break
                }
            }

            $parts = $requestLine.Split(' ')
            if ($parts.Length -lt 2) {
                $body = [System.Text.Encoding]::UTF8.GetBytes('400 Bad Request')
                Write-Response -Stream $stream -StatusCode 400 -StatusText 'Bad Request' -Body $body -ContentType 'text/plain; charset=utf-8'
                continue
            }

            $method = $parts[0].ToUpperInvariant()
            $requestPath = $parts[1]

            if ($method -ne 'GET' -and $method -ne 'HEAD') {
                $body = [System.Text.Encoding]::UTF8.GetBytes('405 Method Not Allowed')
                Write-Response -Stream $stream -StatusCode 405 -StatusText 'Method Not Allowed' -Body $body -ContentType 'text/plain; charset=utf-8'
                continue
            }

            $targetPath = Get-TargetPath -RequestPath $requestPath
            if (-not $targetPath) {
                $body = [System.Text.Encoding]::UTF8.GetBytes('404 Not Found')
                Write-Response -Stream $stream -StatusCode 404 -StatusText 'Not Found' -Body $body -ContentType 'text/plain; charset=utf-8'
                continue
            }

            $extension = [System.IO.Path]::GetExtension($targetPath).ToLowerInvariant()
            $contentType = $contentTypes[$extension]
            if (-not $contentType) {
                $contentType = 'application/octet-stream'
            }

            $fileLength = [int](Get-Item $targetPath).Length
            $body = if ($method -eq 'HEAD') { [byte[]]::new(0) } else { [System.IO.File]::ReadAllBytes($targetPath) }
            Write-Response -Stream $stream -StatusCode 200 -StatusText 'OK' -Body $body -ContentType $contentType -ContentLength $fileLength
        }
        finally {
            if ($reader) { $reader.Dispose() }
            if ($stream) { $stream.Dispose() }
            $client.Close()
        }
    }
}
finally {
    $listener.Stop()
}
