function __MakeWildcard([string]$Pattern) {
    [string]$_pattern = "*"
    if ($Pattern) {
        $_pattern = $Pattern
    }
    $_wo = [System.Management.Automation.WildcardOptions]::IgnoreCase
    New-Object System.Management.Automation.WildcardPattern -ArgumentList $_pattern, $_wo
}

function __RegionFromName([string] $systemName) {
    if ($systemName -and $systemName -ne "") {
        $_regions = [Amazon.RegionEndpoint]::EnumerableAllRegions | Where { $_.SystemName -eq $systemName }
        $_region = $_regions[0]
    } else { 
        $_region = [Amazon.RegionEndpoint]::USEast1
    }
    return $_region
}