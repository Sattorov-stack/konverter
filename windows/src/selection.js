'use strict';
// Какие файлы сейчас выделены в Проводнике (или на рабочем столе)
const fs = require('fs');
const { powershell } = require('./util');

const SCRIPT = `
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class KFg {
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll", CharSet=CharSet.Auto)] public static extern int GetClassName(IntPtr h, System.Text.StringBuilder s, int n);
}
"@
$fg = [KFg]::GetForegroundWindow().ToInt64()
$sb = New-Object System.Text.StringBuilder 256
[void][KFg]::GetClassName([IntPtr]$fg, $sb, 256)
$cls = $sb.ToString()
$shell = New-Object -ComObject Shell.Application
$paths = New-Object System.Collections.ArrayList
foreach ($w in $shell.Windows()) {
  try {
    if ($w.HWND -eq $fg) {
      foreach ($i in $w.Document.SelectedItems()) { [void]$paths.Add([string]$i.Path) }
    }
  } catch {}
}
if ($paths.Count -eq 0 -and ($cls -eq 'Progman' -or $cls -eq 'WorkerW')) {
  try {
    $loc = [ref]0; $root = [ref]0; $hwnd = 0
    $d = $shell.Windows().FindWindowSW($loc, $root, 8, [ref]$hwnd, 1)
    foreach ($i in $d.Document.SelectedItems()) { [void]$paths.Add([string]$i.Path) }
  } catch {}
}
[Console]::Out.WriteLine((ConvertTo-Json -InputObject @($paths) -Compress))
`;

async function getSelection() {
  try {
    const out = await powershell(SCRIPT);
    const line = out.trim().split(/\r?\n/).filter(Boolean).pop();
    if (!line) return [];
    return [].concat(JSON.parse(line)).filter((p) => typeof p === 'string' && fs.existsSync(p));
  } catch (e) {
    return [];
  }
}

module.exports = { getSelection };
