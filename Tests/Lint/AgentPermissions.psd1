@{
    # The documented agent permission rules for rule S-17 (SECURITY.md section 12). Read
    # by Tests\Static\AgentPermissions.Tests.ps1, which compares each committed settings
    # file with its entry here.
    #
    # Each entry: Path is the settings file, relative to the repository root; Allow is
    # every allow rule the file may hold; Deny is every deny rule it must hold. A file may
    # add deny rules, but not drop one, and may not hold an allow rule missing from Allow.
    # Loosening the rules therefore means changing this file in the same diff.

    Files = @(
        @{
            Path  = '.claude/settings.json'
            Allow = @(
                'Bash(pwsh -NoProfile -File ./Scripts/*)'
                'Bash(pwsh -NoProfile -File ./Tests/Lint/*)'
                'Bash(git status *)'
                'Bash(git diff *)'
                'Bash(git log *)'
                'Bash(git show *)'
            )
            Deny  = @(
                'PowerShell'
                'Bash(git push *)'
                'Bash(rm *)'
                'Bash(rmdir *)'
                'Read(~/.aws/**)'
                'Read(~/.ssh/**)'
                'Read(~/.claude/.credentials.json)'
                'Read(./Config/**)'
                'Read(./Tests/Integration/IntegrationConfig.local.ps1)'
            )
        }
        @{
            Path  = '.cursor/cli.json'
            Allow = @(
                'Shell(pwsh:-NoProfile -File ./Scripts/*)'
                'Shell(pwsh:-NoProfile -File ./Tests/Lint/*)'
                'Shell(git:status*)'
                'Shell(git:diff*)'
                'Shell(git:log*)'
                'Shell(git:show*)'
            )
            Deny  = @(
                'Shell(git:push*)'
                'Shell(rm)'
                'Shell(rmdir)'
            )
        }
    )
}
