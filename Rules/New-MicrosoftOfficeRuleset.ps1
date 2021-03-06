#Requires -RunAsAdministrator
#Requires -Module FSLogix.Powershell.Rules
#Requires -PSEdition Desktop
<#
    .SYNOPSIS    
        Creates FSLogix App Masking rule sets for Microsoft Office applications using the FSLogix.Powershell.Rules module.
        
        Outputs files in "Documents\FSLogix Rule Sets". Rule sets will require manual validation.

    .EXAMPLE
        To create an FSLogix App Masking rule set for Visio:

        C:\> .\New-MicrosoftOfficeRuleset.ps1 -SearchString "Visio"

    .EXAMPLE
        To create an FSLogix App Masking rule set for Project:

        C:\> .\New-MicrosoftOfficeRuleset.ps1 -SearchString "Project", "WinProj"

    .EXAMPLE
        To create an FSLogix App Masking rule set for Access:

        C:\> .\New-MicrosoftOfficeRuleset.ps1 -SearchString "Access"
#>
[CmdletBinding()]
Param (
    [Parameter(Mandatory = $True, Position = 0)]
    [ValidateNotNull()]
    [System.String[]] $SearchString,

    [Parameter(Mandatory = $False, Position = 1)]
    [ValidateNotNull()]
    [System.String[]] $Folders = @("$env:ProgramData\Microsoft\Windows\Start Menu\Programs",
        "$env:ProgramFiles\Microsoft Office\root\Office16", "$env:ProgramFiles\Microsoft Office\root\Integration",
        "$env:ProgramFiles\Microsoft Office\root\rsod", "$env:ProgramFiles\Microsoft Office\root\Office16\1033",
        "${env:ProgramFiles(x86)}\Microsoft Office\root\Office16", "${env:ProgramFiles(x86)}\Microsoft Office\root\Integration",
        "${env:ProgramFiles(x86)}\Microsoft Office\root\rsod", "${env:ProgramFiles(x86)}\Microsoft Office\root\Office16\1033")
)

Begin {
    #region Functions
    Function Get-ApplicationRegistryKey {
        <#
        .DESCRIPTION
        Returns strings from well known Registry keys that define a Windows application. Used to assist in defining an FSLogix App Masking rule set.

        .SYNOPSIS
        Returns strings from well known Registry keys that define a Windows application.

        .PARAMETER SearchString
        An array of strings to check for application names. Defaults to "Visio", "Project".

        .PARAMETER Key
        A single key or array of Registry keys to check child keys for application details. The script includes the keys typically needed for most applications.

        .EXAMPLE
        To search for Registry keys specific to Adobe Reader or Acrobat:

        C:\> .\Get-ApplicationRegistryKey.ps1 -SearchString "Adobe"

        .EXAMPLE
        To search for Registry keys specific to Visio and Project:

        C:\> .\Get-ApplicationRegistryKey.ps1 -SearchString "Visio", "Project"

        .EXAMPLE
        To search for Registry keys specific to Skype for Business:

        C:\> .\Get-ApplicationRegistryKey.ps1 -SearchString "Skype"

        .EXAMPLE
        To search for Registry keys specific to Visio and Project by passing strings to Get-ApplicationRegistryKey.ps1 via the pipeline, use:

        C:\> "Visio", "Project" | .\Get-ApplicationRegistryKey.ps1
    #>
        [OutputType([System.Array])]
        [CmdletBinding(SupportsShouldProcess = $False, HelpUri = "https://stealthpuppy.com/fslogix/applicationkeys/")]
        Param (
            [Parameter(Mandatory = $False, Position = 0, ValueFromPipeline)]
            [ValidateNotNull()]
            [System.String[]] $SearchString = @("Visio", "Project"),

            [Parameter(Mandatory = $False, Position = 1, ValueFromPipelineByPropertyName)]
            [ValidateNotNull()]
            [System.String[]] $Key = @("HKLM:\SOFTWARE\Classes\CLSID", "HKLM:\SOFTWARE\Classes", "HKLM:\SOFTWARE\Wow6432Node\Classes", `
                    "HKLM:\SOFTWARE\Wow6432Node\Classes\CLSID", "HKLM:\Software\Microsoft\Office\Outlook\Addins", "HKCU:\Software\Microsoft\Office\Outlook\Addins", `
                    "HKLM:\Software\Microsoft\Office\Word\Addins", "HKCU:\Software\Microsoft\Office\Word\Addins", "HKLM:\Software\Microsoft\Office\Excel\Addins", `
                    "HKCU:\Software\Microsoft\Office\Excel\Addins", "HKLM:\Software\Microsoft\Office\PowerPoint\Addins", "HKCU:\Software\Microsoft\Office\PowerPoint\Addins", `
                    "HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\REGISTRY\MACHINE\Software\Classes", "HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\REGISTRY\MACHINE\Software\Clients", `
                    "HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\REGISTRY\MACHINE\Software\RegisteredApplications")
        )

        begin {
            # Get current location
            $location = Get-Location
        }
        process {
            try {
                # Walk through $Key
                ForEach ($path in $Key) {
                    Write-Verbose -Message "Searching: $path."

                    try {
                        # Attempt change location to $key
                        $result = Push-Location -Path $path -ErrorAction SilentlyContinue -PassThru
                    }
                    catch [System.Management.Automation.ItemNotFoundException] {
                        Write-Warning -Message "Item not found when changing location to [$path]."
                    }
                    catch [System.Exception] {
                        Write-Warning -Message "Exception when changing location to [$path]."
                    }
                    # If successfully changed to the target key, get child keys and match against data in the default values
                    If ($result.Length -gt 0) {
                        $regItems = Get-ChildItem
                        ForEach ($item in $regItems) {
                            ForEach ($string in $SearchString) {
                                If (($item | Get-ItemProperty).'(default)' | Where-Object { $_ -like "*$string*" }) {
                                    Write-Verbose -Message "Found '$(($item | Get-ItemProperty).'(default)')'."
                                    Write-Output -InputObject $item.Name
                                }
                            }
                        }
                    }
                }
            }
            catch [System.Exception] {
                Write-Warning -Message "Exception accessing registry."
                Throw $_.Exception
            }
            finally {
                # Change back to original location
                Set-Location -Path $location
            }
        }
        end {
        }
    }

    Function Convert-Path {
        <#
        .SYNOPSIS
        Replaces paths with environment variables
    #>
        Param (
            [Parameter(Mandatory = $True, Position = 0, ValueFromPipeline = $True)]
            [System.String] $Path
        )
        Switch ($Path) {
            { $_ -match "HKEY_LOCAL_MACHINE" } { $Path = $Path -replace "HKEY_LOCAL_MACHINE", "HKLM" }
            { $_ -match "C:\\Program Files \(x86\)" } { $Path = $Path -replace "C:\\Program Files \(x86\)", "%ProgramFilesFolder32%" }
            { $_ -match "C:\\Program Files" } { $Path = $Path -replace "C:\\Program Files", "%ProgramFilesFolder64%" }
            { $_ -match "C:\\ProgramData\\Microsoft\\Windows\\Start Menu" } { $Path = $Path -replace "C:\\ProgramData\\Microsoft\\Windows\\Start Menu", "%CommonStartMenuFolder%" }
            { $_ -match "C:\\ProgramData" } { $Path = $Path -replace "C:\\ProgramData", "%CommonAppDataFolder%" }
        }
        Write-Output -InputObject $Path
    }

    Function Remove-InvalidFileNameChars {
        param(
            [System.String] $Name
        )
        $invalidChars = [IO.Path]::GetInvalidFileNameChars() -join ''
        $replaceChars = "[{0}]" -f [RegEx]::Escape($invalidChars)
        Write-Output -InputObject ($Name -replace $replaceChars)
    }
    #endregion
}

Process {

    # Set up the rule set file paths
    $Documents = [Environment]::GetFolderPath('MyDocuments')
    $FileName = Remove-InvalidFileNameChars -Name $SearchString[0]
    $RulesetFile = [System.IO.Path]::Combine($Documents, "FSLogix Rule Sets", "Microsoft$FileName.fxr")

    # Create the 'FSLogix Rule Sets'
    If (!(Test-Path -Path (Split-Path -Path $RulesetFile -Parent))) {
        try {
            $params = @{
                Path        = (Split-Path -Path $RulesetFile -Parent)
                ItemType    = "Directory"
                Force       = $True
                ErrorAction = "SilentlyContinue"
            }
            New-Item @params > $Null
        }
        catch {
            Throw "Failed to create the 'FSLogix Rule Sets' folder in: $Documents."
        }
    }

    If (Test-Path -Path $(Split-Path -Path $RulesetFile -Parent)) {
        If (Test-Path -Path $RulesetFile) {
            Write-Warning -Message "File exists: $RulesetFile. Rules will be added to the existing file."
        }
        Write-Information -MessageData "INFO: Using rule set file: $RulesetFile." -InformationAction "Continue"

        # Initialise the array objects
        $Keys = [System.Collections.ArrayList] @()
        $Files = [System.Collections.ArrayList] @()
        $Dirs = [System.Collections.ArrayList] @()

        ForEach ($string in $SearchString) {
            Write-Verbose -Message "Searching for string: $string."
        
            # Grab registry keys related to this application
            Get-ApplicationRegistryKey -SearchString $string | ForEach-Object {
                $Keys.Add($_) > $Null
            }

            # Grab files related to this application
            ForEach ($folder in $Folders) {
                $params = @{
                    Path        = $folder
                    Filter      = "$string*"
                    File        = $True
                    ErrorAction = "SilentlyContinue"
                }
                Write-Verbose -Message "Searching for files in: $folder."
                Get-ChildItem @params | ForEach-Object { $Files.Add($_) > $Null }
            }

            # Grab folders related to this application
            ForEach ($folder in $Folders) {
                $params = @{
                    Path        = $folder
                    Filter      = "$string*"
                    Directory   = $True
                    ErrorAction = "SilentlyContinue"
                }
                Write-Verbose -Message "Searching for folders in: $folder."
                Get-ChildItem @params | ForEach-Object { $Dirs.Add($_) > $Null }
            }
        }

        # Write paths to the App Masking rule set file
        Write-Verbose -Message "Add registry key rules to: $RulesetFile."
        ForEach ($key in $Keys) {
            $params = @{
                Path       = $RulesetFile
                FullName   = (Convert-Path -Path $key)
                HidingType = "FolderOrKey"
                Comment    = "Added by $($MyInvocation.MyCommand)."
            }
            Add-FslRule @params
        }
        Write-Verbose -Message "Add file rules to: $RulesetFile."
        ForEach ($file in $Files) {
            $params = @{
                Path       = $RulesetFile
                FullName   = (Convert-Path -Path $file.FullName)
                HidingType = "FileOrValue"
                Comment    = "Added by $($MyInvocation.MyCommand)."
            }
            Add-FslRule @params
        }
        Write-Verbose -Message "Add folder rules to: $RulesetFile."
        ForEach ($dir in $Dirs) {
            $params = @{
                Path       = $RulesetFile
                FullName   = (Convert-Path -Path $dir.FullName)
                HidingType = "FolderOrKey"
                Comment    = "Added by $($MyInvocation.MyCommand)."
            }
            Add-FslRule @params
        }

        # Output the location of the rule set file
        Write-Output -InputObject $RulesetFile
    }        
    Else {
        Write-Error -Message "Path does not exist: $(Split-Path -Path $RulesetFile -Parent)."
    }
}

End {
}
