[cmdletbinding()]
param(
    [Parameter(ParameterSetName="BuildParameterSet")]
    [switch]
    $BuildStls,

    [Parameter(ParameterSetName="BuildParameterSet")]
    [switch]
    $BuildMarkdown,
    
    [Parameter(ParameterSetName="BuildParameterSet")]
    [switch]
    $BuildImages,

    [Parameter(ParameterSetName="BuildParameterSet")]
    [switch]
    $Force,

    [Parameter(ParameterSetName="BuildParameterSet")]
    [int]
    $Processes = 10
)
$ErrorActionPreference = 'Break'
$Debug = $PSBoundParameters.Debug
if (!$BuildStls -and !$BuildMarkdown -and !$BuildImages) {
    $BuildStls = $true
    $BuildMarkdown = $true
    $BuildImages = $true
}
$openscad      = . $PSScriptRoot\Get-OpenScad.ps1
$scadFile      = (Resolve-Path "$PSScriptRoot\UltraLightGridfinityBins.scad").Path
$parameterFile = (Resolve-Path "$PSScriptRoot\UltraLightGridfinityBins.json").Path
$configFile    = (Resolve-Path "$PSScriptRoot\config.json").Path
$basedir       = [System.IO.Path]::GetDirectoryName($PSScriptRoot)
$tempdir       = (New-Item -ItemType Directory -Path "$env:TEMP\$([System.IO.Path]::GetRandomFileName())" ).FullName
$url           = "https://zergie.github.io/gridfinity-UltraLight"
$scheme        = "" # "orcaslicer://open?file=" # this is not working in orca-slicer 2.3.0, when the instance is running :(

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
                            while ((Get-Process openscad | Measure-Object).Count -ge $Processes) {
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
                        if ($item.Dividers_X -gt 0){ "x$($item.Dividers_X + 1)" }
                        if ($item.Scoops -eq $false){"_noscoop"}
                        if ($item.Labels -eq $false){"_notab"}
                    ) | Join-String -Separator ""
                $item.Paths = [PSCustomObject]@{
                    Stl = [System.IO.Path]::GetFullPath(
                        [System.IO.Path]::Combine($PSScriptRoot, "STLS", $item.filename + ".stl")
                    )
                    Image = [System.IO.Path]::GetFullPath(
                        [System.IO.Path]::Combine($PSScriptRoot, "Images", $item.filename + ".png")
                    )
                }

                $item | ConvertTo-Json | Write-Debug
                $json.Add($item) | Out-Null
            }
        }
    }
    
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
    Push-Location $PSScriptRoot/STLs

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
    Push-Location $PSScriptRoot/Images

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
            $openscad.Invoke("`"$scadFile`" --imgsize=128,128 --projection ortho --colorscheme Tomorrow -o `"$filename.png`"")
        }
    } 

    Get-Process openscad -ErrorAction SilentlyContinue |
        ForEach-Object `
            -Begin   { Start-Sleep -Seconds 1 } `
            -Process { $_.WaitForExit() }

    Get-ChildItem $PSScriptRoot/Images -Filter *.png | 
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

if ($BuildMarkdown) {
@(
    "This repository contains STL files for Gridfinity UltraLight bins. These bins are designed to be lightweight and modular, making them ideal for organizing your workspace. Below, you will find a categorized list of available bins, along with their respective images and download links."
    $(
        $configs.Initialize("building README.md")
        $(while ($configs.MoveNext()) { $configs.Current }) |
            Group-Object Grids_Z |
            Sort-Object -Descending Name |
            ForEach-Object {
                [PSCustomObject]@{
                    Name = "Bins $($_.Group[0].Grids_Z) heigh"
                    Value = $_.Group |
                        Group-Object { "$($_.Grids_X)x$($_.Grids_Y)x$($_.Grids_Z)" } |
                        ForEach-Object {
                            [ordered]@{
                                Size  = $_.Group[0].Grids_X
                                Image = "![Image](./Images/$($_.Group[0].filename).png)"
                                '1x'  = $_.Group |
                                            Where-Object Dividers_X -EQ 0 |
                                            ForEach-Object { "[$($_.filename)](${scheme}$url/STLs/$($_.filename).stl)" } |
                                            Join-String -Separator "<br>"
                                '2x'  = $_.Group |
                                            Where-Object Dividers_X -EQ 1 |
                                            ForEach-Object { "[![Image](./Images/$($_.filename).png)](${scheme}$url/STLs/$($_.filename).stl)" } |
                                            Join-String -Separator "<br>"
                                '3x'  = $_.Group |
                                            Where-Object Dividers_X -EQ 2 |
                                            ForEach-Object { "[![Image](./Images/$($_.filename).png)](${scheme}$url/STLs/$($_.filename).stl)" } |
                                            Join-String -Separator "<br>"
                                '4x'  = $_.Group |
                                            Where-Object Dividers_X -EQ 3 |
                                            ForEach-Object { "[![Image](./Images/$($_.filename).png)](${scheme}$url/STLs/$($_.filename).stl)" } |
                                            Join-String -Separator "<br>"
                                '5x'  = $_.Group |
                                            Where-Object Dividers_X -EQ 4 |
                                            ForEach-Object { "[![Image](./Images/$($_.filename).png)](${scheme}$url/STLs/$($_.filename).stl)" } |
                                            Join-String -Separator "<br>"
                                '6x'  = $_.Group |
                                            Where-Object Dividers_X -EQ 5 |
                                            ForEach-Object { "[![Image](./Images/$($_.filename).png)](${scheme}$url/STLs/$($_.filename).stl)" } |
                                            Join-String -Separator "<br>"
                            }
                        }
                }
            } |
            ForEach-Object {
                # format header
                $header = $_.Value |
                    Select-Object -First 1 |
                    ForEach-Object {
                        $_.GetEnumerator() | 
                            ForEach-Object { " $($_.Name) " }
                    }
                # pad header
                $_.Value |
                    ForEach-Object {
                        $columns = $_.GetEnumerator() | ForEach-Object Value
                        for ($i = 0; $i -lt $columns.Count; $i++) {
                            $line = "$($columns[$i])".Split("`n")[0]
                            if ($header[$i].Length -lt $line.Length) {
                                $header[$i] = $header[$i].PadRight($line.Length+2)
                            }
                        }
                    }
                
                "## $($_.Name)"
                ""
                "|$($header -join "|")|"
                "|$(($header | ForEach-Object {''.PadLeft($_.Length, '-')}) -join '|' )|"
                $_.Value |
                    ForEach-Object {
                        $item = @()
                        $columns = $_.GetEnumerator() | ForEach-Object Value
                        for ($i = 0; $i -lt $columns.Count; $i++) {
                            $item += " $($columns[$i])".PadRight($header[$i].Length)
                        }
                        "|$($item -join "|")|"
                    }
                ""
            } | 
            Join-String -Separator "`n"
    )
) |
    Set-Content -Path "$PSScriptRoot/README.md"
}

Remove-Item -Recurse -Force $tempdir