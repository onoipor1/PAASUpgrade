function Get-ZipRootFolder([string] $zipFile) {
    $filePath = Resolve-Path $zipFile
    [void][Reflection.Assembly]::LoadWithPartialName('System.IO.Compression.FileSystem')
    [System.IO.Compression.ZipArchive] $zipArchive = [System.IO.Compression.ZipFile]::OpenRead($filePath)

    # gets a file contained in a folder
    $someFile = ($zipArchive.Entries | Where-Object FullName -match '/' | Select-Object -First 1)

    # entires FullName will be of form "folder/somefile.dll"
    # split by "/" and we get a top level folder
    $result = ($someFile.Fullname -Split '/')[0]

    return $result
}
