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
        @{ Function = 'Assert-OracleEnvironment'; Id = 'S10'; Label = 'exception text not scrubbed'
            File = 'Source/Private/Assert-OracleEnvironment.ps1'
            Find = '$safeMessage = Invoke-CredentialScrub -Content $PSItem.Exception.Message'
            Replace = '$safeMessage = $PSItem.Exception.Message' }
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
        @{ Function = 'Assert-OracleEnvironment'; Id = 'S7'; Label = 'tnsping output reaches the caller unscrubbed'
            File = 'Source/Private/Assert-OracleEnvironment.ps1'
            Find = '$safeMessage = Invoke-CredentialScrub -Content $PSItem.Exception.Message'
            Replace = '$safeMessage = $PSItem.Exception.Message' }
        @{ Function = 'Assert-OracleEnvironment'; Id = 'T1'; Label = 'throw prefix changed'
            File = 'Source/Private/Assert-OracleEnvironment.ps1'
            Find = 'throw "Oracle environment validation failed: $safeMessage"'
            Replace = 'throw "Oracle environment check failed: $safeMessage"' }
        @{ Function = 'Assert-OracleEnvironment'; Id = 'L1'; Label = 'ORACLE_HOME fallback removed'
            File = 'Source/Private/Assert-OracleEnvironment.ps1'
            Find = '$resolvedHome = $env:ORACLE_HOME'
            Replace = '$resolvedHome = ''''' }
        @{ Function = 'Assert-OracleEnvironment'; Id = 'S8'; Label = 'ORACLE_HOME set on the session'
            File = 'Source/Private/Assert-OracleEnvironment.ps1'
            Find = '        return $binaryPath'
            Replace = '        $env:ORACLE_HOME = $resolvedHome; return $binaryPath' }

        # --- ConvertFrom-SecureStringToPlaintext ---------------------------------------
        @{ Function = 'ConvertFrom-SecureStringToPlaintext'; Id = 'S6'; Label = 'exception text not scrubbed'
            File = 'Source/Private/ConvertFrom-SecureStringToPlaintext.ps1'
            Find = '$safeMessage = Invoke-CredentialScrub -Content $PSItem.Exception.Message'
            Replace = '$safeMessage = $PSItem.Exception.Message' }
        @{ Function = 'ConvertFrom-SecureStringToPlaintext'; Id = 'S4'; Label = 'moved to Source\Public, so exported'
            File = 'Source/Private/ConvertFrom-SecureStringToPlaintext.ps1'
            MoveTo = 'Source/Public/ConvertFrom-SecureStringToPlaintext.ps1' }
        @{ Function = 'ConvertFrom-SecureStringToPlaintext'; Id = 'S5'; Label = 'throw echoes the converted value'
            File = 'Source/Private/ConvertFrom-SecureStringToPlaintext.ps1'
            Find = 'throw "Failed to convert SecureString: $safeMessage"'
            Replace = 'throw "Failed to convert SecureString: $safeMessage $(if ($ptr -ne [IntPtr]::Zero) { [System.Runtime.InteropServices.Marshal]::PtrToStringUni($ptr) })"' }
        @{ Function = 'ConvertFrom-SecureStringToPlaintext'; Id = 'T1'; Label = 'throw prefix changed'
            File = 'Source/Private/ConvertFrom-SecureStringToPlaintext.ps1'
            Find = 'throw "Failed to convert SecureString: $safeMessage"'
            Replace = 'throw "Error. Failed to convert SecureString: $safeMessage"' }

        # --- Get-OracleBackupConfigStore -----------------------------------------------
        @{ Function = 'Get-OracleBackupConfigStore'; Id = 'S5'; Label = 'exception text not scrubbed'
            File = 'Source/Private/Get-OracleBackupConfigStore.ps1'
            Find = '$safeMessage = Invoke-CredentialScrub -Content $PSItem.Exception.Message'
            Replace = '$safeMessage = $PSItem.Exception.Message' }
        @{ Function = 'Get-OracleBackupConfigStore'; Id = 'S1'; Label = 'ACL not applied to a new config file'
            File = 'Source/Private/Get-OracleBackupConfigStore.ps1'
            Find = 'Set-RestrictiveAcl -Path $configPath'
            Replace = '$null = $configPath' }
        @{ Function = 'Get-OracleBackupConfigStore'; Id = 'S4'; Label = 'ORACLE_BACKUP_CONFIG_PATH honoured'
            File = 'Source/Private/Get-OracleBackupConfigStore.ps1'
            Find = '$configPath = if (-not [string]::IsNullOrWhiteSpace($script:ConfigPathOverride)) {'
            Replace = '$configPath = if (-not [string]::IsNullOrWhiteSpace($env:ORACLE_BACKUP_CONFIG_PATH)) { $env:ORACLE_BACKUP_CONFIG_PATH } elseif (-not [string]::IsNullOrWhiteSpace($script:ConfigPathOverride)) {' }

        @{ Function = 'Get-OracleBackupConfigStore'; Id = 'T1'; Label = 'throw prefix changed'
            File = 'Source/Private/Get-OracleBackupConfigStore.ps1'
            Find = 'throw "Failed to load OracleBackup configuration from'
            Replace = 'throw "Could not load OracleBackup configuration from' }

        # --- Invoke-CredentialScrub ----------------------------------------------------
        @{ Function = 'Invoke-CredentialScrub'; Id = 'S1'; Label = 'password kept'
            File = 'Source/Private/Invoke-CredentialScrub.ps1'
            Find = '''$1/***SCRUBBED***@$3'''
            Replace = '''$1/$2@$3''' }
        @{ Function = 'Invoke-CredentialScrub'; Id = 'S1'; Label = 'password ends at the first @'
            File = 'Source/Private/Invoke-CredentialScrub.ps1'
            Find = '''(\w+)/(\S+)@([^@\s]+)'''
            Replace = '''(\w+)/([^@\s]+)@(\S+)''' }
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
        @{ Function = 'Invoke-RmanProcess'; Id = 'S1'; Label = 'NamedCredential connect string put in the arguments'
            File = 'Source/Private/Invoke-RmanProcess.ps1'
            Find = '$psi.Arguments = '''''
            Replace = '$psi.Arguments = "target $($Credential.UserName)/$($Credential.GetNetworkCredential().Password)@$ServiceAlias"' }
        @{ Function = 'Invoke-RmanProcess'; Id = 'S4'; Label = 'stdout not scrubbed'
            File = 'Source/Private/Invoke-RmanProcess.ps1'
            Find = '$stdOut = Invoke-CredentialScrub -Content $stdOut'
            Replace = '$stdOut = $stdOut' }
        @{ Function = 'Invoke-RmanProcess'; Id = 'S4'; Label = 'stderr not scrubbed'
            File = 'Source/Private/Invoke-RmanProcess.ps1'
            Find = '$stdErr = Invoke-CredentialScrub -Content $stdErr'
            Replace = '$stdErr = $stdErr' }
        @{ Function = 'Invoke-RmanProcess'; Id = 'S5'; Label = 'exception message not scrubbed'
            File = 'Source/Private/Invoke-RmanProcess.ps1'
            Find = '$safeMessage = Invoke-CredentialScrub -Content $PSItem.Exception.Message'
            Replace = '$safeMessage = $PSItem.Exception.Message' }
        @{ Function = 'Invoke-RmanProcess'; Id = 'S6'; Label = 'password in the verbose line'
            File = 'Source/Private/Invoke-RmanProcess.ps1'
            Find = 'service=''$ServiceAlias''"'
            Replace = 'service=''$ServiceAlias'' pw=''$($Credential.GetNetworkCredential().Password)''"' }
        @{ Function = 'Invoke-RmanProcess'; Id = 'L2'; Label = 'EXIT; not written'
            File = 'Source/Private/Invoke-RmanProcess.ps1'
            Find = '$process.StandardInput.WriteLine(''EXIT;'')'
            Replace = '$null = 0' }
        @{ Function = 'Invoke-RmanProcess'; Id = 'L2'; Label = 'stdin left open'
            File = 'Source/Private/Invoke-RmanProcess.ps1'
            Find = '$process.StandardInput.Close()'
            Replace = '$null = 0' }
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
        @{ Function = 'Set-RestrictiveAcl'; Id = 'S5'; Label = 'exception text not scrubbed'
            File = 'Source/Private/Set-RestrictiveAcl.ps1'
            Find = '$safeMessage = Invoke-CredentialScrub -Content $PSItem.Exception.Message'
            Replace = '$safeMessage = $PSItem.Exception.Message' }
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

        @{ Function = 'Set-RestrictiveAcl'; Id = 'T1'; Label = 'throw prefix changed'
            File = 'Source/Private/Set-RestrictiveAcl.ps1'
            Find = 'throw "Failed to apply restrictive ACL to'
            Replace = 'throw "Could not apply restrictive ACL to' }

        # --- Get-OracleDatabaseList ----------------------------------------------------
        @{ Function = 'Get-OracleDatabaseList'; Id = 'S2'; Label = 'exception text not scrubbed'
            File = 'Source/Public/Get-OracleDatabaseList.ps1'
            Find = '$safeMessage = Invoke-CredentialScrub -Content $PSItem.Exception.Message'
            Replace = '$safeMessage = $PSItem.Exception.Message' }
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
        @{ Function = 'Get-RmanBackupStatus'; Id = 'S5'; Label = 'exception text not scrubbed'
            File = 'Source/Public/Get-RmanBackupStatus.ps1'
            Find = '$safeMessage = Invoke-CredentialScrub -Content $PSItem.Exception.Message'
            Replace = '$safeMessage = $PSItem.Exception.Message' }
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
        @{ Function = 'Remove-RmanObsoleteBackup'; Id = 'S8'; Label = 'exception text not scrubbed'
            File = 'Source/Public/Remove-RmanObsoleteBackup.ps1'
            Find = '$safeMessage = Invoke-CredentialScrub -Content $PSItem.Exception.Message'
            Replace = '$safeMessage = $PSItem.Exception.Message' }
        @{ Function = 'Remove-RmanObsoleteBackup'; Id = 'S10'; Label = 'WalletAlias pattern loosened'
            File = 'Source/Public/Remove-RmanObsoleteBackup.ps1'
            Find = '[ValidatePattern(''^[A-Za-z0-9_.-]*\z'')]'
            Replace = '[ValidatePattern(''^.*\z'')]' }

        # --- Invoke-OraEnv -------------------------------------------------------------
        @{ Function = 'Invoke-OraEnv'; Id = 'S2'; Label = 'an extra line written to the host'
            File = 'Source/Public/Invoke-OraEnv.ps1'
            Find = '    $result = Set-OracleEnv @callParams'
            Replace = '    Write-Host "[Invoke-OraEnv] calling Set-OracleEnv"; $result = Set-OracleEnv @callParams' }

        # --- Set-OracleEnv -------------------------------------------------------------
        @{ Function = 'Set-OracleEnv'; Id = 'S3'; Label = 'exception text not scrubbed'
            File = 'Source/Public/Set-OracleEnv.ps1'
            Find = '$safeMessage = Invoke-CredentialScrub -Content $PSItem.Exception.Message'
            Replace = '$safeMessage = $PSItem.Exception.Message' }
        @{ Function = 'Set-OracleEnv'; Id = 'S1'; Label = 'the instance list is cached in the module'
            File = 'Source/Public/Set-OracleEnv.ps1'
            Find = '$listResult = Get-OracleDatabaseList'
            Replace = 'if ($null -eq $script:TaceCachedList) { $script:TaceCachedList = Get-OracleDatabaseList }; $listResult = $script:TaceCachedList' }
        @{ Function = 'Set-OracleEnv'; Id = 'R7'; Label = 'several instances: the first is used'
            File = 'Source/Public/Set-OracleEnv.ps1'
            Find = '            if ($databases.Count -eq 1) {'
            Replace = '            if ($databases.Count -ge 1) {' }
        @{ Function = 'Set-OracleEnv'; Id = 'R4'; Label = 'no warning for a stopped service'
            File = 'Source/Public/Set-OracleEnv.ps1'
            Find = 'if ($serviceWarning)    { Write-Warning $serviceWarning }'
            Replace = 'if ($serviceWarning)    { $null = $serviceWarning }' }

        # --- Static proofs (Tests\Static\SourceInvariants.Tests.ps1) -------------------
        @{ Function = 'ConvertFrom-RmanListBackup'; Id = 'S1'; Label = 'a file check added'
            File = 'Source/Private/ConvertFrom-RmanListBackup.ps1'
            Find = '$lines = $RawLog -split ''\r?\n'''
            Replace = '$null = [System.IO.File]::Exists(''C:\x''); $lines = $RawLog -split ''\r?\n''' }
        @{ Function = 'ConvertFrom-SecureStringToPlaintext'; Id = 'S2'; Label = 'buffer freed without zeroing'
            File = 'Source/Private/ConvertFrom-SecureStringToPlaintext.ps1'
            Find = '[System.Runtime.InteropServices.Marshal]::ZeroFreeGlobalAllocUnicode($ptr)'
            Replace = '[System.Runtime.InteropServices.Marshal]::FreeHGlobal($ptr)' }
        @{ Function = 'ConvertFrom-SecureStringToPlaintext'; Id = 'S3'; Label = 'a second plaintext extraction elsewhere'
            File = 'Source/Private/Invoke-CredentialScrub.ps1'
            Find = 'if ([string]::IsNullOrEmpty($Content)) { return $Content }'
            Replace = '$null = [System.Net.NetworkCredential]::new('''', ''x'').Password; if ([string]::IsNullOrEmpty($Content)) { return $Content }' }
        @{ Function = 'Invoke-RmanProcess'; Id = 'S2'; Label = 'password assigned to a variable'
            File = 'Source/Private/Invoke-RmanProcess.ps1'
            Find = 'if ($authMode -eq ''NamedCredential'') {'
            Replace = 'if ($authMode -eq ''NamedCredential'') { $plain = ConvertFrom-SecureStringToPlaintext -SecureString $Credential.Password; $null = $plain' }
        @{ Function = 'Invoke-RmanProcess'; Id = 'L3'; Label = 'process not disposed'
            File = 'Source/Private/Invoke-RmanProcess.ps1'
            Find = '            $process.Dispose()'
            Replace = '            $null = $process' }
        @{ Function = 'Invoke-RmanProcess'; Id = 'L5'; Label = 'timeout kills the parent process only'
            File = 'Source/Private/Invoke-RmanProcess.ps1'
            Find = '$process.Kill($true)'
            Replace = '$process.Kill($false)' }
        @{ Function = 'Invoke-RmanProcess'; Id = 'L6'; Label = 'Kill not inside a try'
            File = 'Source/Private/Invoke-RmanProcess.ps1'
            Find = 'try { $process.Kill($true) } catch {'
            Replace = '$process.Kill($true); if ($false) {' }
        @{ Function = 'Invoke-RmanProcess'; Id = 'L6'; Label = 'a failed kill rethrows'
            File = 'Source/Private/Invoke-RmanProcess.ps1'
            Find = 'KILL on rman failed at $([datetime]::UtcNow.ToString(''o''))"'
            Replace = 'KILL on rman failed at $([datetime]::UtcNow.ToString(''o''))"; throw $PSItem' }
        @{ Function = 'Invoke-RmanProcess'; Id = 'L6'; Label = 'a failed wait rethrows'
            File = 'Source/Private/Invoke-RmanProcess.ps1'
            Find = 'WAIT on killed rman failed at $([datetime]::UtcNow.ToString(''o''))"'
            Replace = 'WAIT on killed rman failed at $([datetime]::UtcNow.ToString(''o''))"; throw $PSItem' }
        @{ Function = 'Invoke-RmanProcess'; Id = 'L6'; Label = 'killed process given 100 ms, not 5 seconds'
            File = 'Source/Private/Invoke-RmanProcess.ps1'
            Find = '$null = $process.WaitForExit(5000)'
            Replace = '$null = $process.WaitForExit(100)' }
        @{ Function = 'Invoke-TnspingProcess'; Id = 'L3'; Label = 'process not disposed'
            File = 'Source/Private/Invoke-TnspingProcess.ps1'
            Find = 'if ($null -ne $proc) { $proc.Dispose() }'
            Replace = 'if ($null -ne $proc) { $null = $proc }' }
        @{ Function = 'Get-OracleDatabaseList'; Id = 'S1'; Label = 'a tnsping call added'
            File = 'Source/Public/Get-OracleDatabaseList.ps1'
            Find = '$databases = @()'
            Replace = '$databases = @(); if ($false) { $null = Invoke-TnspingProcess -TnspingPath ''x'' -WalletAlias ''x'' -OracleHome ''x'' }' }
        @{ Function = 'Get-OracleDatabaseList'; Id = 'L1'; Label = 'a file write added'
            File = 'Source/Public/Get-OracleDatabaseList.ps1'
            Find = '$databases = @()'
            Replace = '$databases = @(); if ($false) { Set-Content -Path ''x'' -Value ''x'' -WhatIf:$false }' }
        @{ Function = 'Get-RmanBackupStatus'; Id = 'S3'; Label = 'user name placed in a verbose line'
            File = 'Source/Public/Get-RmanBackupStatus.ps1'
            Find = '(AuthMode: $authMode)"'
            Replace = '(AuthMode: $authMode, user $($Credential.UserName))"' }
        @{ Function = 'Set-OracleEnv'; Id = 'S2'; Label = 'another environment variable set'
            File = 'Source/Public/Set-OracleEnv.ps1'
            Find = '$env:ORACLE_SID = $SID'
            Replace = '$env:ORACLE_SID = $SID; $env:TNS_ADMIN = ''x''' }
        @{ Function = 'Set-OracleEnv'; Id = 'L3'; Label = 'a host line added'
            File = 'Source/Public/Set-OracleEnv.ps1'
            Find = 'Write-Verbose "[Set-OracleEnv] One instance found. Using SID ''$SID''."'
            Replace = 'Write-Host "[Set-OracleEnv] One instance found. Using SID ''$SID''."' }
    )
}
