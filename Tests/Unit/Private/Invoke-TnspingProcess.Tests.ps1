<#
.SECURITY
    Scope  : Invoke-TnspingProcess (private)
    Touches: Real child processes only. Fake .cmd files under TestDrive stand in for
             tnsping.exe, the same approach as the Invoke-RmanProcess tests.
    Does NOT touch: A real tnsping binary, Oracle instance, network, or the current
                    session environment variables.

    Security assertions in this file:
    - ORACLE_HOME and PATH reach the child; the session environment is unchanged (S1)
    - A timed-out tnsping is killed and the session environment is still unchanged (S1, L2)
#>

#Requires -Version 7.6

Describe 'Invoke-TnspingProcess' {

    BeforeAll {
        Remove-Module TACE.Oracle.Admin -Force -ErrorAction SilentlyContinue
        Import-Module (& (Join-Path $PSScriptRoot '..' 'Get-BuiltModulePath.ps1')) -Force

        $script:tnsHome = Join-Path $TestDrive 'tnshome'
        $null = New-Item -ItemType Directory -Force -Path (Join-Path $script:tnsHome 'bin')

        $script:tnsEchoCmd = Join-Path $TestDrive 'tnsEcho.cmd'
        Set-Content -Path $script:tnsEchoCmd -Encoding ASCII -Value (
            "@echo ORACLE_HOME=%ORACLE_HOME%`r`n@echo PATH=%PATH%`r`n@echo ALIAS=%1`r`n@echo OK (10 msec)")

        # About 200 KB to stderr: far past the pipe buffer, so a synchronous stdout read
        # would leave the child blocked on stderr.
        $script:tnsFloodCmd = Join-Path $TestDrive 'tnsFlood.cmd'
        Set-Content -Path $script:tnsFloodCmd -Encoding ASCII -Value (
            "@for /l %%i in (1,1,4000) do @echo STDERR_FLOOD_LINE_%%i_padding_padding_padding 1>&2`r`n@echo FLOOD_DONE")

        # Sleeps well past the 2-second test timeout.
        $script:tnsHangCmd = Join-Path $TestDrive 'tnsHang.cmd'
        Set-Content -Path $script:tnsHangCmd -Encoding ASCII -Value "@ping -n 30 127.0.0.1 >nul`r`n@echo LATE"
    }

    AfterAll {
        Remove-Module TACE.Oracle.Admin -Force -ErrorAction SilentlyContinue
    }

    Context 'Implementation' {

        It 'R1 returns exactly ExitCode, StdOut and StdErr' {
            $result = InModuleScope TACE.Oracle.Admin -Parameters @{ Cmd = $script:tnsEchoCmd; FakeHome = $script:tnsHome } {
                param($Cmd, $FakeHome)
                Invoke-TnspingProcess -TnspingPath $Cmd -WalletAlias 'MY_ALIAS' -OracleHome $FakeHome
            }
            @($result.PSObject.Properties.Name) | Should -Be @('ExitCode', 'StdOut', 'StdErr')
            $result.ExitCode | Should -Be 0
            $result.StdOut   | Should -Match 'ALIAS=MY_ALIAS'
        }

        It 'L4 child PATH starts with OracleHome bin and the platform separator' {
            $result = InModuleScope TACE.Oracle.Admin -Parameters @{ Cmd = $script:tnsEchoCmd; FakeHome = $script:tnsHome } {
                param($Cmd, $FakeHome)
                Invoke-TnspingProcess -TnspingPath $Cmd -WalletAlias 'MY_ALIAS' -OracleHome $FakeHome
            }
            $expectedStart = 'PATH=' + (Join-Path $script:tnsHome 'bin') + [System.IO.Path]::PathSeparator
            $pathLine = @($result.StdOut -split "`r?`n" | Where-Object { $PSItem -like 'PATH=*' })[0]
            $pathLine.StartsWith($expectedStart) | Should -BeTrue
        }

        It 'L1 a tnsping that floods stderr still completes' {
            $result = InModuleScope TACE.Oracle.Admin -Parameters @{ Cmd = $script:tnsFloodCmd; FakeHome = $script:tnsHome } {
                param($Cmd, $FakeHome)
                Invoke-TnspingProcess -TnspingPath $Cmd -WalletAlias 'MY_ALIAS' -OracleHome $FakeHome -TimeoutSeconds 60
            }
            $result.StdOut        | Should -Match 'FLOOD_DONE'
            $result.StdErr.Length | Should -BeGreaterThan 100000
        }
    }

    Context 'Security' {

        # Sentinels first: a before-and-after read proves nothing when an earlier test has
        # already left the value the call would set.
        It 'S1 child gets ORACLE_HOME and the session environment is unchanged' -Tag 'SEC' {
            $sentinel = & (Join-Path $PSScriptRoot '..' 'Set-EnvironmentSentinel.ps1')
            try {
                $result = InModuleScope TACE.Oracle.Admin -Parameters @{ Cmd = $script:tnsEchoCmd; FakeHome = $script:tnsHome } {
                    param($Cmd, $FakeHome)
                    Invoke-TnspingProcess -TnspingPath $Cmd -WalletAlias 'MY_ALIAS' -OracleHome $FakeHome
                }
            }
            finally {
                $changed = & (Join-Path $PSScriptRoot '..' 'Compare-EnvironmentSentinel.ps1') -Snapshot $sentinel
            }
            $result.StdOut | Should -Match ([regex]::Escape("ORACLE_HOME=$($script:tnsHome)"))
            ($changed -join ', ') | Should -BeNullOrEmpty
        }

        It 'S1, L2 kills a tnsping that runs past TimeoutSeconds and throws' -Tag 'SEC' {
            $sentinel = & (Join-Path $PSScriptRoot '..' 'Set-EnvironmentSentinel.ps1')
            try {
                $watch = [System.Diagnostics.Stopwatch]::StartNew()
                {
                    InModuleScope TACE.Oracle.Admin -Parameters @{ Cmd = $script:tnsHangCmd; FakeHome = $script:tnsHome } {
                        param($Cmd, $FakeHome)
                        Invoke-TnspingProcess -TnspingPath $Cmd -WalletAlias 'MY_ALIAS' -OracleHome $FakeHome -TimeoutSeconds 2
                    }
                } | Should -Throw -ExpectedMessage '*timed out after 2 seconds and the process was killed*'
                $watch.Stop()
            }
            finally {
                $changed = & (Join-Path $PSScriptRoot '..' 'Compare-EnvironmentSentinel.ps1') -Snapshot $sentinel
            }
            $watch.Elapsed.TotalSeconds | Should -BeLessThan 15
            ($changed -join ', ') | Should -BeNullOrEmpty
        }

        It 'Invoke-TnspingProcess is not exported as a public command' {
            (Get-Module TACE.Oracle.Admin).ExportedCommands.Keys | Should -Not -Contain 'Invoke-TnspingProcess'
        }
    }
}
