# Servidor estático mínimo para desarrollo local (no usar en producción)
param([int]$Port = 8765)

$root = Split-Path -Parent $PSScriptRoot
$mime = @{
  '.html'='text/html; charset=utf-8'; '.css'='text/css; charset=utf-8'
  '.js'='application/javascript; charset=utf-8'; '.json'='application/json'
  '.png'='image/png'; '.jpg'='image/jpeg'; '.svg'='image/svg+xml'
  '.woff'='font/woff'; '.woff2'='font/woff2'; '.ico'='image/x-icon'
}

$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://localhost:$Port/")
$listener.Start()
Write-Host "Sirviendo $root en http://localhost:$Port/"

while ($listener.IsListening) {
  $ctx = $listener.GetContext()
  $path = [System.Uri]::UnescapeDataString($ctx.Request.Url.AbsolutePath)
  if ($path -eq '/') { $path = '/index.html' }
  $file = Join-Path $root ($path -replace '/', '\')
  try {
    if (Test-Path $file -PathType Leaf) {
      $bytes = [System.IO.File]::ReadAllBytes($file)
      $ext = [System.IO.Path]::GetExtension($file).ToLower()
      $ctx.Response.ContentType = if ($mime[$ext]) { $mime[$ext] } else { 'application/octet-stream' }
      $ctx.Response.OutputStream.Write($bytes, 0, $bytes.Length)
    } else {
      $ctx.Response.StatusCode = 404
    }
  } catch {
    $ctx.Response.StatusCode = 500
  }
  $ctx.Response.Close()
}
