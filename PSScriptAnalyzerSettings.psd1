@{
    # These are interactive console scripts: colored Write-Host output IS the
    # UI (plan display, [y/N] consent prompts), not a logging antipattern.
    ExcludeRules = @('PSAvoidUsingWriteHost')
}