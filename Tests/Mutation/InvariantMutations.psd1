# Mutations for Scripts\Test-InvariantMutation.ps1.
#
# Each mutation breaks one invariant in a temporary copy of the repository: Find is
# replaced by Replace in File (Find must occur exactly once), or File is moved to MoveTo.
# The tests or static checks cited for Function and Id must then fail (rule I-10).
#
# Every security invariant with a cited test or static check needs at least one mutation;
# the script refuses to run otherwise. Other entries are listed where a citation was found
# weak and then fixed, so the fix stays proven.
@{
    Mutations = @(
        # --- Assert-OracleEnvironment --------------------------------------------------
        @{ Function = 'Assert-OracleEnvironment'; Id = 'S1'; Label = 'home existence check removed'
            File = 'Source/Private/Assert-OracleEnvironment.ps1'
            Find = 'if (-not (Test-Path -Path $resolvedHome -PathType Container)) {'
            Replace = 'if ($false) {' }
        @{ Function = 'Assert-OracleEnvironment'; Id = 'S2'; Label = 'binary taken from PATH when found there'
            File = 'Source/Private/Assert-OracleEnvironment.ps1'
            Find = '$binaryPath = Join-Path -Path $resolvedHome -ChildPath ''bin'' -AdditionalChildPath $Binary'
            Replace = '$binaryPath = (Get-Command -Name $Binary -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1).Source; if (-not $binaryPath) { $binaryPath = Join-Path -Path $resolvedHome -ChildPath ''bin'' -AdditionalChildPath $Binary }' }
        @{ Function = 'Assert-OracleEnvironment'; Id = 'S3'; Label = 'TrustFailure no longer stops the call'
            File = 'Source/Private/Assert-OracleEnvironment.ps1'
            Find = '@(''HashMismatch'', ''TrustFailure'')'
            Replace = '@(''HashMismatch'')' }
        @{ Function = 'Assert-OracleEnvironment'; Id = 'S3'; Label = 'HashMismatch no longer stops the call'
            File = 'Source/Private/Assert-OracleEnvironment.ps1'
            Find = '@(''HashMismatch'', ''TrustFailure'')'
            Replace = '@(''TrustFailure'')' }
        @{ Function = 'Assert-OracleEnvironment'; Id = 'S3'; Label = 'non-Oracle signer accepted'
            File = 'Source/Private/Assert-OracleEnvironment.ps1'
            Find = '-notmatch ''Oracle'''
            Replace = '-notmatch ''.''' }
        @{ Function = 'Assert-OracleEnvironment'; Id = 'S5'; Label = 'SkipSignatureCheck parameter added'
            File = 'Source/Private/Assert-OracleEnvironment.ps1'
            Find = '[string]$WalletAlias = '''''
            Replace = '[string]$WalletAlias = '''', [switch]$SkipSignatureCheck' }
        @{ Function = 'Assert-OracleEnvironment'; Id = 'S6'; Label = 'tnsping step skipped'
            File = 'Source/Private/Assert-OracleEnvironment.ps1'
            Find = 'if (-not [string]::IsNullOrWhiteSpace($WalletAlias)) {'
            Replace = 'if ($false) {' }
        @{ Function = 'Assert-OracleEnvironment'; Id = 'S7'; Label = 'tnsping stdout not scrubbed'
            File = 'Source/Private/Assert-OracleEnvironment.ps1'
            Find = '$tnsOutScrubbed = Invoke-CredentialScrub -Content $tnsResult.StdOut'
            Replace = '$tnsOutScrubbed = $tnsResult.StdOut' }
        @{ Function = 'Assert-OracleEnvironment'; Id = 'S7'; Label = 'tnsping stderr not scrubbed'
            File = 'Source/Private/Assert-OracleEnvironment.ps1'
            Find = '$tnsErrScrubbed = Invoke-CredentialScrub -Content $tnsResult.StdErr'
            Replace = '$tnsErrScrubbed = $tnsResult.StdErr' }
        @{ Function = 'Assert-OracleEnvironment'; Id = 'S8'; Label = 'ORACLE_HOME set on the session'
            File = 'Source/Private/Assert-OracleEnvironment.ps1'
            Find = '        return $binaryPath'
            Replace = '        $env:ORACLE_HOME = $resolvedHome; return $binaryPath' }

        # --- ConvertFrom-SecureStringToPlaintext ---------------------------------------
        @{ Function = 'ConvertFrom-SecureStringToPlaintext'; Id = 'S4'; Label = 'moved to Source\Public, so exported'
            File = 'Source/Private/ConvertFrom-SecureStringToPlaintext.ps1'
            MoveTo = 'Source/Public/ConvertFrom-SecureStringToPlaintext.ps1' }
        @{ Function = 'ConvertFrom-SecureStringToPlaintext'; Id = 'S5'; Label = 'throw echoes the converted value'
            File = 'Source/Private/ConvertFrom-SecureStringToPlaintext.ps1'
            Find = 'throw "Failed to convert SecureString: $($PSItem.Exception.Message)"'
            Replace = 'throw "Failed to convert SecureString: $($PSItem.Exception.Message) $(if ($ptr -ne [IntPtr]::Zero) { [System.Runtime.InteropServices.Marshal]::PtrToStringUni($ptr) })"' }
        @{ Function = 'ConvertFrom-SecureStringToPlaintext'; Id = 'T1'; Label = 'throw prefix changed'
            File = 'Source/Private/ConvertFrom-SecureStringToPlaintext.ps1'
            Find = 'throw "Failed to convert SecureString: $($PSItem.Exception.Message)"'
            Replace = 'throw "Error. Failed to convert SecureString: $($PSItem.Exception.Message)"' }

        # --- Get-OracleBackupConfigStore -----------------------------------------------
        @{ Function = 'Get-OracleBackupConfigStore'; Id = 'S1'; Label = 'ACL not applied to a new config file'
            File = 'Source/Private/Get-OracleBackupConfigStore.ps1'
            Find = 'Set-RestrictiveAcl -Path $configPath'
            Replace = '$null = $configPath' }
        @{ Function = 'Get-OracleBackupConfigStore'; Id = 'S4'; Label = 'ORACLE_BACKUP_CONFIG_PATH honoured'
            File = 'Source/Private/Get-OracleBackupConfigStore.ps1'
            Find = '$configPath = if (-not [string]::IsNullOrWhiteSpace($script:ConfigPathOverride)) {'
            Replace = '$configPath = if (-not [string]::IsNullOrWhiteSpace($env:ORACLE_BACKUP_CONFIG_PATH)) { $env:ORACLE_BACKUP_CONFIG_PATH } elseif (-not [string]::IsNullOrWhiteSpace($script:ConfigPathOverride)) {' }

        # --- Invoke-CredentialScrub ----------------------------------------------------
        @{ Function = 'Invoke-CredentialScrub'; Id = 'S1'; Label = 'password kept'
            File = 'Source/Private/Invoke-CredentialScrub.ps1'
            Find = '''$1/***SCRUBBED***@$3'''
            Replace = '''$1/$2@$3''' }
        @{ Function = 'Invoke-CredentialScrub'; Id = 'R1'; Label = 'empty content returned as null'
            File = 'Source/Private/Invoke-CredentialScrub.ps1'
            Find = 'if ([string]::IsNullOrEmpty($Content)) { return $Content }'
            Replace = 'if ([string]::IsNullOrEmpty($Content)) { return $null }' }

        # --- Invoke-RmanProcess --------------------------------------------------------
        @{ Function = 'Invoke-RmanProcess'; Id = 'S3'; Label = 'ORACLE_SID set on the session'
            File = 'Source/Private/Invoke-RmanProcess.ps1'
            Find = '$psi.EnvironmentVariables[''ORACLE_SID''] = $OracleSid'
            Replace = '$psi.EnvironmentVariables[''ORACLE_SID''] = $OracleSid; $env:ORACLE_SID = $OracleSid' }
        @{ Function = 'Invoke-RmanProcess'; Id = 'S3'; Label = 'ORACLE_HOME set on the session'
            File = 'Source/Private/Invoke-RmanProcess.ps1'
            Find = '$psi.EnvironmentVariables[''ORACLE_HOME'']     = $OracleHome'
            Replace = '$psi.EnvironmentVariables[''ORACLE_HOME'']     = $OracleHome; $env:ORACLE_HOME = $OracleHome' }
        @{ Function = 'Invoke-RmanProcess'; Id = 'S3'; Label = 'NLS_DATE_FORMAT not set on the child'
            File = 'Source/Private/Invoke-RmanProcess.ps1'
            Find = '$psi.EnvironmentVariables[''NLS_DATE_FORMAT''] = ''YYYY-MM-DD HH24:MI:SS'''
            Replace = '$null = 0' }
        @{ Function = 'Invoke-RmanProcess'; Id = 'S3'; Label = 'PATH set on the session'
            File = 'Source/Private/Invoke-RmanProcess.ps1'
            Find = 'else { $binDir + [System.IO.Path]::PathSeparator + $childPath }'
            Replace = 'else { $env:PATH = $binDir + [System.IO.Path]::PathSeparator + $childPath; $env:PATH }' }
        @{ Function = 'Invoke-RmanProcess'; Id = 'R1'; Label = 'extra property returned'
            File = 'Source/Private/Invoke-RmanProcess.ps1'
            Find = '            AuthMode = $authMode'
            Replace = '            AuthMode = $authMode; Arguments = $psi.Arguments' }
        @{ Function = 'Invoke-RmanProcess'; Id = 'L1'; Label = 'stdout read to the end before stderr'
            File = 'Source/Private/Invoke-RmanProcess.ps1'
            Find = '$stdOutTask = $process.StandardOutput.ReadToEndAsync()'
            Replace = '$null = $process.StandardOutput.ReadToEnd(); $stdOutTask = [System.Threading.Tasks.Task]::FromResult('''')' }

        # --- Invoke-TnspingProcess -----------------------------------------------------
        @{ Function = 'Invoke-TnspingProcess'; Id = 'S1'; Label = 'ORACLE_HOME set on the session'
            File = 'Source/Private/Invoke-TnspingProcess.ps1'
            Find = '$psi.EnvironmentVariables[''ORACLE_HOME''] = $OracleHome'
            Replace = '$psi.EnvironmentVariables[''ORACLE_HOME''] = $OracleHome; $env:ORACLE_HOME = $OracleHome' }
        @{ Function = 'Invoke-TnspingProcess'; Id = 'S1'; Label = 'ORACLE_HOME not given to the child'
            File = 'Source/Private/Invoke-TnspingProcess.ps1'
            Find = '$psi.EnvironmentVariables[''ORACLE_HOME''] = $OracleHome'
            Replace = '$null = 0' }

        # --- Set-RestrictiveAcl --------------------------------------------------------
        @{ Function = 'Set-RestrictiveAcl'; Id = 'S1'; Label = 'inheritance kept'
            File = 'Source/Private/Set-RestrictiveAcl.ps1'
            Find = '$acl.SetAccessRuleProtection($true, $false)'
            Replace = '$acl.SetAccessRuleProtection($false, $true)' }
        @{ Function = 'Set-RestrictiveAcl'; Id = 'S2'; Label = 'Administrators rule not added'
            File = 'Source/Private/Set-RestrictiveAcl.ps1'
            Find = '$acl.AddAccessRule($adminRule)'
            Replace = '$null = $adminRule' }
        @{ Function = 'Set-RestrictiveAcl'; Id = 'S2'; Label = 'Everyone granted read'
            File = 'Source/Private/Set-RestrictiveAcl.ps1'
            Find = '$acl.AddAccessRule($adminRule)'
            Replace = '$acl.AddAccessRule($adminRule); $acl.AddAccessRule([System.Security.AccessControl.FileSystemAccessRule]::new(''Everyone'', ''Read'', $inheritanceFlags, ''None'', ''Allow''))' }
        @{ Function = 'Set-RestrictiveAcl'; Id = 'S3'; Label = 'directory rules not inheritable'
            File = 'Source/Private/Set-RestrictiveAcl.ps1'
            Find = '$inheritanceFlags = if ($item.PSIsContainer) {'
            Replace = '$inheritanceFlags = if ($false) {' }

        # --- Get-OracleDatabaseList ----------------------------------------------------
        @{ Function = 'Get-OracleDatabaseList'; Id = 'R1'; Label = 'unsupported platform returns an extra property'
            File = 'Source/Public/Get-OracleDatabaseList.ps1'
            Find = 'Message = "Oracle instance discovery is not supported on platform'
            Replace = 'Platform = $Platform; Message = "Oracle instance discovery is not supported on platform' }

        # --- Get-RmanBackupStatus ------------------------------------------------------
        @{ Function = 'Get-RmanBackupStatus'; Id = 'S1'; Label = 'ORACLE_SID set on the session'
            File = 'Source/Public/Get-RmanBackupStatus.ps1'
            Find = '        $rmanResult = Invoke-RmanProcess @rmanInvokeParams'
            Replace = '        $env:ORACLE_SID = $DatabaseName; $rmanResult = Invoke-RmanProcess @rmanInvokeParams' }
        @{ Function = 'Get-RmanBackupStatus'; Id = 'S2'; Label = 'Message carries the named credential'
            File = 'Source/Public/Get-RmanBackupStatus.ps1'
            Find = '"Most recent backup for ''$DatabaseName'': $($mostRecent.Level)'
            Replace = '"$(if ($null -ne $Credential) { "$($Credential.UserName)/$($Credential.GetNetworkCredential().Password)@$DatabaseName " })Most recent backup for ''$DatabaseName'': $($mostRecent.Level)' }
        @{ Function = 'Get-RmanBackupStatus'; Id = 'S6'; Label = 'WalletAlias pattern loosened'
            File = 'Source/Public/Get-RmanBackupStatus.ps1'
            Find = '[ValidatePattern(''^[A-Za-z0-9_.-]*\z'')]'
            Replace = '[ValidatePattern(''^.*\z'')]' }
        @{ Function = 'Get-RmanBackupStatus'; Id = 'R3'; Label = 'ties without a CompletionTime go to the lowest Key'
            File = 'Source/Public/Get-RmanBackupStatus.ps1'
            Find = '@{ Expression = { $PSItem.Key            }; Descending = $true }'
            Replace = '@{ Expression = { $PSItem.Key            }; Descending = $false }' }
        @{ Function = 'Get-RmanBackupStatus'; Id = 'L1'; Label = 'a second command added to the script'
            File = 'Source/Public/Get-RmanBackupStatus.ps1'
            Find = '$listScript = ''LIST BACKUP SUMMARY;'''
            Replace = '$listScript = ''LIST BACKUP SUMMARY; CROSSCHECK BACKUP;''' }

        # --- Remove-RmanObsoleteBackup -------------------------------------------------
        @{ Function = 'Remove-RmanObsoleteBackup'; Id = 'S1'; Label = 'ShouldProcess gate bypassed'
            File = 'Source/Public/Remove-RmanObsoleteBackup.ps1'
            Find = 'if (-not $PSCmdlet.ShouldProcess($DatabaseName, ''Delete obsolete RMAN backup pieces'')) {'
            Replace = 'if ($false -and -not $PSCmdlet.ShouldProcess($DatabaseName, ''Delete obsolete RMAN backup pieces'')) {' }
        @{ Function = 'Remove-RmanObsoleteBackup'; Id = 'S1'; Label = 'ConfirmImpact lowered to Low'
            File = 'Source/Public/Remove-RmanObsoleteBackup.ps1'
            Find = 'ConfirmImpact = ''High'''
            Replace = 'ConfirmImpact = ''Low''' }
        @{ Function = 'Remove-RmanObsoleteBackup'; Id = 'S2'; Label = 'NOPROMPT dropped'
            File = 'Source/Public/Remove-RmanObsoleteBackup.ps1'
            Find = '$deleteScript = ''DELETE NOPROMPT OBSOLETE;'''
            Replace = '$deleteScript = ''DELETE OBSOLETE;''' }
        @{ Function = 'Remove-RmanObsoleteBackup'; Id = 'S3'; Label = 'ORACLE_SID set on the session'
            File = 'Source/Public/Remove-RmanObsoleteBackup.ps1'
            Find = '        $rmanResult = Invoke-RmanProcess @rmanInvokeParams'
            Replace = '        $env:ORACLE_SID = $DatabaseName; $rmanResult = Invoke-RmanProcess @rmanInvokeParams' }
        @{ Function = 'Remove-RmanObsoleteBackup'; Id = 'S4'; Label = 'Message carries the named credential'
            File = 'Source/Public/Remove-RmanObsoleteBackup.ps1'
            Find = '"DELETE OBSOLETE completed for ''$DatabaseName''.'
            Replace = '"$(if ($null -ne $Credential) { "$($Credential.UserName)/$($Credential.GetNetworkCredential().Password)@$DatabaseName " })DELETE OBSOLETE completed for ''$DatabaseName''.' }
        @{ Function = 'Remove-RmanObsoleteBackup'; Id = 'S5'; Label = 'script carries the named credential'
            File = 'Source/Public/Remove-RmanObsoleteBackup.ps1'
            Find = '$deleteScript = ''DELETE NOPROMPT OBSOLETE;'''
            Replace = '$deleteScript = ''DELETE NOPROMPT OBSOLETE;'' + $(if ($null -ne $Credential) { " # $($Credential.UserName)/$($Credential.GetNetworkCredential().Password)@$DatabaseName" })' }
        @{ Function = 'Remove-RmanObsoleteBackup'; Id = 'S9'; Label = 'parameter value placed in the script'
            File = 'Source/Public/Remove-RmanObsoleteBackup.ps1'
            Find = '$deleteScript = ''DELETE NOPROMPT OBSOLETE;'''
            Replace = '$deleteScript = "DELETE NOPROMPT OBSOLETE; # $DatabaseName"' }
        @{ Function = 'Remove-RmanObsoleteBackup'; Id = 'S10'; Label = 'WalletAlias pattern loosened'
            File = 'Source/Public/Remove-RmanObsoleteBackup.ps1'
            Find = '[ValidatePattern(''^[A-Za-z0-9_.-]*\z'')]'
            Replace = '[ValidatePattern(''^.*\z'')]' }

        # --- Set-OracleEnv -------------------------------------------------------------
        @{ Function = 'Set-OracleEnv'; Id = 'R4'; Label = 'no warning for a stopped service'
            File = 'Source/Public/Set-OracleEnv.ps1'
            Find = 'if ($serviceWarning)    { Write-Warning $serviceWarning }'
            Replace = 'if ($serviceWarning)    { $null = $serviceWarning }' }
    )
}
