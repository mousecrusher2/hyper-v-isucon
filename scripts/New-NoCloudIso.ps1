#requires -Version 7.3
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$SourcePath,
    [Parameter(Mandatory)][string]$IsoPath
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$taskSource = (Resolve-Path -LiteralPath $SourcePath).Path
$taskOutput = [IO.Path]::GetFullPath($IsoPath)
if (Test-Path -LiteralPath $taskOutput) { throw "$taskOutput は既に存在します。" }

# IMAPI creates the filesystem; this bridge saves its COM stream to a file.
if (-not ('NoCloudIsoStream' -as [type])) {
    Add-Type -TypeDefinition @'
using System.IO;
using System.Runtime.InteropServices;
using System.Runtime.InteropServices.ComTypes;
public static class NoCloudIsoStream {
    public static void Save(object source, string path) {
        var stream = (IStream)source;
        var buffer = new byte[65536];
        var countPointer = Marshal.AllocHGlobal(4);
        try {
            using (var output = new FileStream(path, FileMode.CreateNew)) {
                while (true) {
                    stream.Read(buffer, buffer.Length, countPointer);
                    int count = Marshal.ReadInt32(countPointer);
                    if (count == 0) break;
                    output.Write(buffer, 0, count);
                }
            }
        } finally { Marshal.FreeHGlobal(countPointer); }
    }
}
'@
}
$taskImage = New-Object -ComObject IMAPI2FS.MsftFileSystemImage
try {
    $taskImage.FileSystemsToCreate = 3 # ISO9660 and Joliet
    $taskImage.VolumeName = 'cidata'
    $taskImage.Root.AddTree($taskSource, $false)
    $taskResult = $taskImage.CreateResultImage()
    try { [NoCloudIsoStream]::Save($taskResult.ImageStream, $taskOutput) }
    finally { [Runtime.InteropServices.Marshal]::ReleaseComObject($taskResult) | Out-Null }
} finally { [Runtime.InteropServices.Marshal]::ReleaseComObject($taskImage) | Out-Null }
