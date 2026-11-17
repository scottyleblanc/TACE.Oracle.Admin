@{
    # Patterns for rule S-16 (and S-04): values that must never be committed to this
    # public repository. Read by Tests\Static\PublicRepoHygiene.Tests.ps1, which checks
    # files, and by Scripts\Invoke-Gate.ps1, which checks unpushed commit messages.
    #
    # Each entry: Id and Title name the check; Pattern is the regular expression; Allow,
    # when not empty, is a regular expression for matched values that are acceptable;
    # Because is the reason shown on failure.
    #
    # These catch values with a known shape. A real resource name that matches no
    # pattern is left to review (TODO.md, Stack 2: private identifier list, deferred).

    Patterns = @(
        @{
            Id      = 'S-16'
            Title   = 'no AWS account ID'
            # Twelve digits standing alone. A GUID's last segment is preceded by '-', so
            # it is not matched.
            Pattern = '(?<![\w.\-])\d{12}(?![\w.\-])'
            Allow   = ''
            Because = 'an account ID is infrastructure detail (S-16)'
        }
        @{
            Id      = 'S-16'
            Title   = 'no ARN'
            Pattern = 'arn:aws[a-z\-]*:'
            Allow   = ''
            Because = 'an ARN names a real resource (S-16)'
        }
        @{
            Id      = 'S-16'
            Title   = 'no AWS access key ID'
            Pattern = '\b(AKIA|ASIA)[A-Z0-9]{16}\b'
            Allow   = ''
            Because = 'an access key ID is a credential (S-04, S-16)'
        }
        @{
            Id      = 'S-16'
            Title   = 'no literal S3 target'
            # s3:// followed by a real name. A variable ($S3Bucket) or a placeholder
            # (<staging-bucket>) does not start with a letter or digit, so it passes.
            Pattern = 's3://[a-z0-9]'
            Allow   = ''
            Because = 'a bucket name is infrastructure detail; take it as a parameter (S-16)'
        }
        @{
            Id      = 'S-16'
            Title   = 'no email address outside the reserved example domains'
            Pattern = '[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}'
            # Reserved example domains, and the public no-reply addresses that commit
            # trailers use.
            Allow   = '@example\.(com|org|net)$|^noreply@anthropic\.com$|@users\.noreply\.github\.com$'
            Because = 'a real address identifies a person or an account (S-16)'
        }
        @{
            Id      = 'S-16'
            Title   = 'no local user-profile path'
            # A Windows or macOS user folder, with one or two slashes so a JSON-escaped
            # path is caught too. The folder name is the account name. Example paths
            # elsewhere use C:\app or /home/oracle, which do not match; nor does this
            # pattern's own text, since '[' cannot start a folder name here.
            Pattern = '(?i)\b[A-Z]:[\\/]{1,2}Users[\\/]{1,2}[A-Za-z0-9._-]+|(?<![\w.])/Users/[A-Za-z0-9._-]+'
            Allow   = ''
            Because = 'a local path names the machine account; a review record quoting one is edited before it is committed (S-16)'
        }
        @{
            Id      = 'S-04'
            Title   = 'no private key block'
            Pattern = '-----BEGIN [A-Z ]*PRIVATE KEY-----'
            Allow   = ''
            Because = 'a private key is a credential (S-04)'
        }
    )
}
