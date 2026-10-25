param(
    [string]$Cmd = "",
    [int]$Port = 5558,
    [int]$WaitMs = 1500
)
$ErrorActionPreference = 'Stop'
$c = New-Object System.Net.Sockets.TcpClient
$c.Connect('127.0.0.1', $Port)
$s = $c.GetStream()
$s.ReadTimeout = 1200
$c.NoDelay = $true

function Read-All($stream, $ms) {
    $buf = New-Object byte[] 65536
    $end = (Get-Date).AddMilliseconds($ms)
    $sb = New-Object System.Text.StringBuilder
    while ((Get-Date) -lt $end) {
        try {
            if ($stream.DataAvailable) {
                $n = $stream.Read($buf, 0, $buf.Length)
                if ($n -gt 0) { [void]$sb.Append([Text.Encoding]::UTF8.GetString($buf, 0, $n)) }
            } else { Start-Sleep -Milliseconds 60 }
        } catch { break }
    }
    return $sb.ToString()
}

$pre = Read-All $s 400
if ($Cmd) {
    $bytes = [Text.Encoding]::UTF8.GetBytes($Cmd + "`n")
    $s.Write($bytes, 0, $bytes.Length)
    $s.Flush()
    Start-Sleep -Milliseconds 300
    $out = Read-All $s $WaitMs
    Write-Output $out
} else {
    Write-Output $pre
}
$c.Close()
