[cmdletbinding()]
param(
    [Parameter()]
    [switch]
    $BuildStls,

    [Parameter()]
    [switch]
    $BuildImages,

    [Parameter()]
    [switch]
    $Force,

    [Parameter()]
    [int]
    $Processes = 10,

    [Parameter()]
    [int[]]
    $ImageSize =@(256,256)
)
$ErrorActionPreference = 'Break'
$Debug =
if (!$BuildStls -and !$BuildImages) {
    $BuildStls = $true
    $BuildImages = $true
}
$openscad      = . $PSScriptRoot\Get-OpenScad.ps1
$scadFile      = (Resolve-Path "$PSScriptRoot\UltraLightGridfinityBins.scad").Path
$parameterFile = [System.IO.Path]::ChangeExtension($scadFile, "json")
$configFile    = (Resolve-Path "$PSScriptRoot\config.json").Path
$basedir       = [System.IO.Path]::GetDirectoryName($PSScriptRoot)
$tempdir       = (New-Item -ItemType Directory -Path "$env:TEMP\$([System.IO.Path]::GetRandomFileName())").FullName
$url           = "https://zergie.github.io/gridfinity-UltraLight"
$scheme        = "orcaslicer://open?file=" # this is not working in orca-slicer 2.3.0, when the instance is running :(
$tocFile       = [System.IO.Path]::GetFullPath("$PSScriptRoot/docs/configurations.json")

$json = [System.Collections.ArrayList]::new()
Get-Content $configFile -Encoding utf8 |
    ConvertFrom-Json -AsHashtable |
    ForEach-Object {
        $stack = [System.Collections.Stack]::new()
        $stack.Push($_)

        while ($stack.Count -gt 0) {
            $item = $stack.Pop()
            $yieldItem = $true

            foreach ($key in $_.Keys) {
                $value = $item.$key
                if ($value.GetType().FullName -eq "System.Object[]") {
                    $yieldItem = $false
                    foreach ($configuration in $value) {
                        $new_item = $item | ConvertTo-Json | ConvertFrom-Json -AsHashtable
                        $new_item.$key = $configuration
                        $stack.Push($new_item)
                    }
                    break
                }
            }

            if ($yieldItem) {
                $item.OpenScad = [PSCustomObject]@{
                    Path      = $openscad
                    File      = $scadFile
                    Arguments = $item.GetEnumerator() |
                        ForEach-Object `
                            -Process { "-D `"$($_.Name)=$($_.Value)`"" } `
                            -End {
                                "-p `"$($parameterFile)`""
                                "-P `"make.ps1`""
                            } |
                        Join-String -Separator " "
                } |
                    Add-Member -PassThru -MemberType ScriptMethod -Name Invoke -Value {
                        param([string] $Arguments)
                        Start-Sleep -Milliseconds (Get-Random -Minimum 100 -Maximum 500)
                        
                        $process = Get-Process openscad -ErrorAction SilentlyContinue
                        if ($null -ne $process.Name) {
                            while ((Get-Process openscad -ErrorAction SilentlyContinue | Measure-Object).Count -ge $Processes) {
                                Start-Sleep -Seconds 1
                            }
                        }
                        
                        $batchFile = [System.IO.Path]::Combine($tempdir, 
                            [System.IO.Path]::ChangeExtension(
                                [System.IO.Path]::GetRandomFileName()
                            , "bat")
                        )
                        Set-Content -Path $batchFile -Value "`"$($this.Path)`" $Arguments"

                        $cmd = "cmd /D /C `"$batchFile`""
                        if ($Debug) {
                            Write-Host -ForegroundColor Cyan $cmd
                        }
                        $p = @{
                            FilePath = "conhost"
                            ArgumentList = $cmd
                            WorkingDirectory = (Get-Location).Path
                            WindowStyle = "Hidden"
                        }
                        $p | ConvertTo-Json | Write-debug
                        $process = Start-Process @p 
                }
                
                $item.filename = @(
                        $item.Grids_X
                        "x"
                        $item.Grids_Y
                        "x"
                        $item.Grids_Z
                        if ($item.Dividers_X -gt 0 -or $item.Dividers_Y -gt 0){ "x$($item.Dividers_X + 1)" }
                        if ($item.Dividers_Y -gt 0){ "x$($item.Dividers_Y + 1)" }
                        if ($item.Scoops -eq $false){"_noscoop"}
                        if ($item.Labels -eq $false){"_notab"}
                    ) | Join-String -Separator ""
                $item.Paths = [PSCustomObject]@{
                    Stl = [System.IO.Path]::GetFullPath(
                        [System.IO.Path]::Combine($PSScriptRoot, "docs/STLs", $item.filename + ".stl")
                    )
                    Image = [System.IO.Path]::GetFullPath(
                        [System.IO.Path]::Combine($PSScriptRoot, "docs/images", $item.filename + ".png")
                    )
                }

                $item | ConvertTo-Json | Write-Debug
                $json.Add($item) | Out-Null
            }
        }
    }
$json | 
    Select-Object -ExcludeProperty OpenScad, Paths |
    Sort-Object filename -Unique |
    ConvertTo-Json -Compress |
    Set-Content $tocFile -Encoding utf8

$configs = [PSCustomObject]@{
    Index    = 0
    Count    = $json.Count
    Activity = $Activity
}
Add-Member -InputObject $configs -MemberType ScriptMethod -Name "MoveNext" -Value {
    Write-Debug "count: $($this.Count)"
    $percent = 1 + [Math]::Round(99 * ($this.Index + 1) / $this.Count, 1)
    $result = $this.Index -lt ($this.Count - 1)
    if ($result) {
        $p = @{
            Activity = $this.Activity
            Status   = "$($this.Index + 1) / $($this.Count) - $($percent.ToString("0.0")) %"
            PercentComplete = [Math]::Floor($percent)
        }
    } else {
        $p = @{
            Activity = $this.Activity
            Completed = $true
        }
    }
    Write-Progress @p
    $this.Index++
    $result
}
Add-Member -InputObject $configs -MemberType ScriptMethod -Name "Initialize" -Value {
    param([string] $Activity)
    Write-Progress -Activity $Activity -PercentComplete 1
    $this.Activity = $Activity
    $this.Index = -1
}
Add-Member -InputObject $configs -MemberType ScriptProperty -Name "Current" -Value {
    $json[$this.Index]
}

function Clear-Directory {
    param ( 
        # Specifies a path to one or more locations.
        [Parameter(Position=0)]
        [string]
        $Path = $PSScriptRoot,

        [string] $Filter 
    )
    Write-Host -ForegroundColor Magenta $Force
    if ($Force) {
        # remove ALL files
        @(
            Get-ChildItem $Path -Recurse -Filter $Filter
        ) |
            ForEach-Object {
                Write-Host -ForegroundColor Red "deleting .$($_.FullName.SubString($basedir.Length).Replace("\","/"))"; $_
            } |
            Remove-Item

            0..1 |
                ForEach-Object {
                    Get-ChildItem -Recurse -Directory |
                        Where-Object{ (Get-ChildItem $_ | Measure-Object).Count -eq 0} |
                        Remove-Item
                }
    } else {
        # remove files not listed in the JSON configuration
        Get-ChildItem $Path -Recurse -Filter $Filter |
            Where-Object {
                $filename = [System.IO.Path]::GetFileNameWithoutExtension($_.FullName)
                $filename -notin $json.filename } |
            ForEach-Object {
                Write-Host -ForegroundColor Red "deleting .$($_.FullName.SubString($basedir.Length).Replace("\","/"))"; $_
            } |
            Remove-Item -Confirm
    }
}

if ($BuildStls) {
    Push-Location $PSScriptRoot/docs/STLs

    Get-Process openscad -ErrorAction SilentlyContinue |
        Stop-Process -Force

    Clear-Directory . -Filter *.stl

    $configs.Initialize("building stl files")
    while ($configs.MoveNext()) { 
        $filename = $configs.Current.filename
        $openscad = $configs.Current.OpenScad
        
        if (!(Test-Path "$filename.stl")) {
            $directory = [System.IO.Path]::GetDirectoryName($filename)
            if ($directory.Length -gt 0) {
                mkdir $directory -ErrorAction SilentlyContinue | Out-Null
            }
            
            Write-Host -ForegroundColor Green "building $filename.stl"
            $openscad.Invoke("`"$($openscad.File)`" $($openscad.Arguments) --export-format binstl -o `"$filename.stl`"")
        }
    }
        
    Get-Process openscad -ErrorAction SilentlyContinue |
        ForEach-Object `
            -Begin   { Start-Sleep -Seconds 1 } `
            -Process { $_.WaitForExit() }

    # delete empty directories
    Get-ChildItem -Directory -Recurse |
        Where-Object { ($_ | Get-ChildItem -Recurse -File | Measure-Object).Count -eq 0 } |
        Remove-Item -Recurse -Force

    Pop-Location
}

if ($BuildImages) {
    Push-Location $PSScriptRoot/docs/images

    Get-Process openscad -ErrorAction SilentlyContinue |
        Stop-Process -Force

    Clear-Directory . -Filter *.png

    $configs.Initialize("building image files")
    while ($configs.MoveNext()) { 
        $stl      = $configs.Current.Paths.Stl.Replace("\", "/")
        $filename = $configs.Current.filename
        $openscad = $configs.Current.OpenScad
        $scadFile = $tempdir + "\" + [System.IO.Path]::ChangeExtension([System.IO.Path]::GetRandomFileName(), ".scad")
        
        if (!(Test-Path "$filename.png")) {
            @(
                # '$vpt = [0, 0, 0];'
                # '$vpd = 500;'
                # '$vpr = [35, 0, 350];'
                'color("DarkCyan")'
                "import(`"$stl`");"
            ) |
                Set-Content $scadFile

            Write-Host -ForegroundColor Green "building $filename.png"
            $openscad.Invoke("`"$scadFile`" --imgsize=$($ImageSize[0]),$($ImageSize[1]) --projection ortho --colorscheme Tomorrow -o `"$filename.png`"")
        }
    } 

    Get-Process openscad -ErrorAction SilentlyContinue |
        ForEach-Object `
            -Begin   { Start-Sleep -Seconds 1 } `
            -Process { $_.WaitForExit() }

    Get-ChildItem $PSScriptRoot/docs/images -Filter *.png | 
        ForEach-Object {
            $tempFilePath = [System.IO.Path]::GetTempFileName()
            Copy-Item -Path $_.FullName -Destination $tempFilePath

            try {
                $bitmap = [System.Drawing.Bitmap]::FromFile($tempFilePath)
                $transparentColor = [System.Drawing.Color]::FromArgb(248, 248, 248)
                $bitmap.MakeTransparent($transparentColor)
                $bitmap.Save($_.FullName, [System.Drawing.Imaging.ImageFormat]::Png)
                $bitmap.Dispose()
            } finally {
                Remove-Item -Path $tempFilePath -Force
            }
        }

    Pop-Location
}

Remove-Item -Recurse -Force $tempdir