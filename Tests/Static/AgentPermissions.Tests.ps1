#Requires -Version 7.6

# Static tier. Rule S-17: the committed agent permission files keep every documented
# deny rule and allow nothing beyond the documented allow rules. The documented rules
# live in Tests\Lint\AgentPermissions.psd1. A file may add deny rules; a removed deny
# rule, or an allow rule that is new or widened, fails here, so SECURITY.md section 12
# and the files cannot drift apart unseen.

BeforeDiscovery {
    $dataFile = Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath 'Lint' -AdditionalChildPath 'AgentPermissions.psd1'
    $script:expected = @((Import-PowerShellDataFile -LiteralPath $dataFile).Files)
}

BeforeAll {
    $script:repoRoot = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
    $dataFile        = Join-Path -Path $script:repoRoot -ChildPath 'Tests' -AdditionalChildPath 'Lint', 'AgentPermissions.psd1'
    $script:documented = @((Import-PowerShellDataFile -LiteralPath $dataFile).Files)

    # Returns the parsed permissions block of a settings file.
    function Get-PermissionBlock {
        param([Parameter(Mandatory)] [string] $RelativePath)
        $full = Join-Path -Path $script:repoRoot -ChildPath $RelativePath
        if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { return $null }
        $json = Get-Content -LiteralPath $full -Raw | ConvertFrom-Json -AsHashtable
        $json['permissions']
    }
}

Describe 'Agent permission settings' -Tag 'Static', 'SEC' {

    It 'documents at least one settings file' {
        $script:documented.Count | Should -BeGreaterThan 0 -Because 'Tests\Lint\AgentPermissions.psd1 lists the committed settings files'
    }

    Context '<Path>' -ForEach $script:expected {

        BeforeAll {
            $script:block = Get-PermissionBlock -RelativePath $Path
        }

        It 'S-17: the file exists and has a permissions block' {
            $script:block | Should -Not -BeNullOrEmpty -Because "$Path is the committed permission file for an agent (S-17)"
        }

        It 'S-17: every documented deny rule is present' {
            $actual  = @($script:block['deny'])
            $missing = @($Deny | Where-Object { $PSItem -cnotin $actual })
            ($missing -join "`n") | Should -BeNullOrEmpty -Because "a deny rule removed from $Path loosens containment; change Tests\Lint\AgentPermissions.psd1 and SECURITY.md section 12 with it (S-17)"
        }

        It 'S-17: no allow rule beyond the documented ones' {
            $actual = @($script:block['allow'])
            $extra  = @($actual | Where-Object { $PSItem -cnotin $Allow })
            ($extra -join "`n") | Should -BeNullOrEmpty -Because "an allow rule new to $Path widens what the agent may run unasked; change Tests\Lint\AgentPermissions.psd1 and SECURITY.md section 12 with it (S-17)"
        }
    }
}
