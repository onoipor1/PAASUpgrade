# Only add static functions in this file

# ================================ User Interaction utils ================================

function Prompt-ForContinuation([string] $message = "Do you wish to continue?") {

    $value = ""

    while (($value.ToLowerInvariant() -notin @("y", "n"))) {
        $value = Read-Host "`n$message (y/n)"
    }

    return ($value.ToLowerInvariant() -eq "y")
}

function DisplayException($ex) {
    Write-Host $ex | Format-List -Force
}

# ================================ HashTable utils ================================

function Read-JsonAsHashtable($filePath) {

    $fileContent = [System.IO.File]::ReadAllText($filePath)
    $psCustomObject = ConvertFrom-Json -InputObject $fileContent
    $hashtable = ConvertTo-Hashtable $psCustomObject

    return $hashtable
}

function ConvertTo-Hashtable($object) {

    $type = $object.GetType()

    if ($type -eq [System.Collections.Hashtable])
    {
        return (New-StringHashtableFromPropertyEnumerator ($object.GetEnumerator()))
    }
    else
    {
        if ($type -eq [System.Management.Automation.PSCustomObject]) {
            return (New-StringHashtableFromPropertyEnumerator ($object.PSObject.Properties))
        } else {
            throw "Cannot convert object of type $type to [System.Collections.Hashtable]"
        }
    }
}

function Merge-Hashtables([System.Collections.Hashtable] $from, [System.Collections.Hashtable] $to) {

    $result = New-Object System.Collections.Hashtable

    if ($to) {
        $to.GetEnumerator() | ForEach-Object {
            $result."$($_.Name)" = $_.Value
        } | Out-Null
    }

    if ($from) {
        $from.GetEnumerator() | ForEach-Object {
            $result."$($_.Name)" = $_.Value
        } | Out-Null
    }

    return $result
}

function New-StringHashtableFromPropertyEnumerator($propertyEnumerator) {

    $hashtable = New-Object System.Collections.Hashtable

    $propertyEnumerator | ForEach-Object {
        $hashtable."$($_.Name)" = if ($null -ne $_.Value) {
            $_.Value.ToString()
        } else {
            [string]::Empty
        }
    }

    return $hashtable
}