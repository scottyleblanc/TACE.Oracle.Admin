<#
.SECURITY
    Scope  : ConvertFrom-SecureStringToPlaintext (private)
    Touches: No real Oracle instance, no filesystem, no network.
             Tests exercise the in-process SecureString-to-plaintext conversion
             using real [SecureString] objects. No mocking of .NET Marshal methods —
             tests verify observable behaviour rather than internal implementation.
    Does NOT touch: RMAN binary, Oracle instance, registry, session environment.

    Security assertions in this file:
    - Function is not exported as a public command
    - Return value is the correct plaintext (not scrambled or truncated)
    - SEC-06: throw path from a disposed SecureString produces a clean 'Failed to
      convert SecureString' error — not a pointer/memory error — confirming that
      the $ptr = [IntPtr]::Zero pre-initialization keeps the finally guard reliable
    - Throw message does not contain the input plaintext value
#>

#Requires -Version 7.0

Describe 'ConvertFrom-SecureStringToPlaintext' {

    BeforeAll {
        $modulePath = Join-Path $PSScriptRoot '..' 'TACE.Oracle.Admin.psd1'
        $modulePath  = [System.IO.Path]::GetFullPath($modulePath)

        $testConfigPath = Join-Path $TestDrive 'OracleBackup.json'
        $env:ORACLE_BACKUP_CONFIG_PATH = $testConfigPath

        [PSCustomObject]@{
            BackupBasePath       = (Join-Path $TestDrive 'backup')
            FastRecoveryArea     = (Join-Path $TestDrive 'fra')
            LogBasePath          = (Join-Path $TestDrive 'logs')
            LogRetentionHotDays  = 15
            LogRetentionWarmDays = 90
            OracleHome           = (Join-Path $TestDrive 'oracle')
            DefaultAuthMode      = 'OSAuth'
            DefaultWalletAlias   = ''
        } | ConvertTo-Json -Depth 5 |
            Set-Content -Path $testConfigPath -Encoding UTF8

        Remove-Module TACE.Oracle.Admin -Force -ErrorAction SilentlyContinue
        Import-Module $modulePath -Force
    }

    AfterAll {
        Remove-Module TACE.Oracle.Admin -Force -ErrorAction SilentlyContinue
        $env:ORACLE_BACKUP_CONFIG_PATH = $null
    }

    # ── Parameter validation ───────────────────────────────────────────────────

    Context 'Parameter validation' {

        It 'SecureString parameter is mandatory' {
            InModuleScope TACE.Oracle.Admin {
                $param = (Get-Command ConvertFrom-SecureStringToPlaintext).Parameters['SecureString']
                $isMandatory = @($param.Attributes |
                    Where-Object { $PSItem -is [System.Management.Automation.ParameterAttribute] -and $PSItem.Mandatory })
                $isMandatory.Count | Should -BeGreaterThan 0
            }
        }

        It 'SecureString parameter is typed as [SecureString]' {
            InModuleScope TACE.Oracle.Admin {
                $param = (Get-Command ConvertFrom-SecureStringToPlaintext).Parameters['SecureString']
                $param.ParameterType | Should -Be ([SecureString])
            }
        }
    }

    # ── Implementation ─────────────────────────────────────────────────────────

    Context 'Implementation' {

        It 'Returns the correct plaintext for a standard password' {
            InModuleScope TACE.Oracle.Admin {
                $plain = 'MyTestPassword123!'
                $secure = ConvertTo-SecureString $plain -AsPlainText -Force
                $result = ConvertFrom-SecureStringToPlaintext -SecureString $secure
                $result | Should -Be $plain
            }
        }

        It 'Returns an empty string for an empty SecureString' {
            InModuleScope TACE.Oracle.Admin {
                $secure = [System.Security.SecureString]::new()
                $secure.MakeReadOnly()
                $result = ConvertFrom-SecureStringToPlaintext -SecureString $secure
                $result | Should -Be ''
            }
        }

        It 'Handles special characters correctly' {
            InModuleScope TACE.Oracle.Admin {
                $plain = 'P@$$w0rd!#%^&*()'
                $secure = ConvertTo-SecureString $plain -AsPlainText -Force
                $result = ConvertFrom-SecureStringToPlaintext -SecureString $secure
                $result | Should -Be $plain
            }
        }

        It 'Handles a password containing backslash and forward slash' {
            InModuleScope TACE.Oracle.Admin {
                $plain = 'user\p@ss/word'
                $secure = ConvertTo-SecureString $plain -AsPlainText -Force
                $result = ConvertFrom-SecureStringToPlaintext -SecureString $secure
                $result | Should -Be $plain
            }
        }

        It 'Returns a [string] type' {
            InModuleScope TACE.Oracle.Admin {
                $secure = ConvertTo-SecureString 'test' -AsPlainText -Force
                $result = ConvertFrom-SecureStringToPlaintext -SecureString $secure
                $result | Should -BeOfType [string]
            }
        }

        # SEC-06: The throw path — verify the finally guard handles $ptr = [IntPtr]::Zero
        # correctly. A disposed SecureString causes SecureStringToGlobalAllocUnicode to
        # throw before $ptr is assigned. With the pre-initialization, $ptr remains
        # [IntPtr]::Zero and ZeroFreeGlobalAllocUnicode is correctly skipped. Without it,
        # $ptr is undefined and the guard may call ZeroFreeGlobalAllocUnicode($null).
        It 'SEC-06: Throws a clean "Failed to convert SecureString" error when conversion fails — not a pointer or memory error' {
            InModuleScope TACE.Oracle.Admin {
                $secure = ConvertTo-SecureString 'throwtest' -AsPlainText -Force
                $secure.Dispose()

                { ConvertFrom-SecureStringToPlaintext -SecureString $secure } |
                    Should -Throw -ExpectedMessage '*Failed to convert SecureString*'
            }
        }
    }

    # ── Security ───────────────────────────────────────────────────────────────

    Context 'Security' {

        It 'Function is not exported as a public command' {
            $exported = (Get-Module TACE.Oracle.Admin).ExportedCommands.Keys
            $exported | Should -Not -Contain 'ConvertFrom-SecureStringToPlaintext'
        }

        # [SEC] Throw message must never contain the plaintext value that was passed in.
        # If the message echoed the input, it would leak credentials in error logs.
        It 'Throw message does not contain the input plaintext when conversion fails' {
            InModuleScope TACE.Oracle.Admin {
                $secret = 'SuperSecretValue99!'
                $secure = ConvertTo-SecureString $secret -AsPlainText -Force
                $secure.Dispose()

                $caught = $null
                try {
                    ConvertFrom-SecureStringToPlaintext -SecureString $secure
                } catch {
                    $caught = $PSItem.Exception.Message
                }

                $caught | Should -Not -BeNullOrEmpty
                $caught | Should -Not -Match ([regex]::Escape($secret))
            }
        }

        # [SEC] Verify the function is accessible only within the module scope —
        # calling it outside InModuleScope must fail.
        It 'Is not callable outside module scope' {
            { ConvertFrom-SecureStringToPlaintext -SecureString (ConvertTo-SecureString 'x' -AsPlainText -Force) } |
                Should -Throw
        }
    }
}
