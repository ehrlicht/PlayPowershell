<# 
.Synopsis 
    This script applies patches to all | selected images in the wim file or vhd file. Definitions and updates are downloaded directly from Microsoft windows update but some updates are static and definitions are downloaded from http://optimalizovane-it.cz/support/static.xml
    
.Description 
    This script applies patches to all | selected images in the wim file or vhd file. Definitions and updates are downloaded directly from Microsoft windows update but some updates are static and definitions are downloaded from http://optimalizovane-it.cz/support/static.xml. Static xml file
    is updated every month so you will get all required and optional updates for Windows 7 and Server 2008 R2 (sorry no support for Vista and 2008).
    This script will not update Silverlight, Windows Defender,... because these updates are .exe files and DISM doesn't support these updates.
    
    !!! patching images in wim file is VERY TIME CONSUMIG - approx. 45min per image
    
    Usage: imagepatcher.ps1 -dbg:yes -imagefile:path to image -patchimages
    
    Note: You must run PowerShell as elevated
    
    If you discover some bug or missing update please contact me at ondrejv@optimalizovane-it.cz
    
    Version 1.0.1 - 5.August 2010

.Parameter  -dbg
    Displays more detailed info about the process
    
    Usage:
    imagepatcher.ps1 -dbg:yes -imagefile:c:\deployment\install.wim
    
.Parameter -imagefile
    full path to the image file. 
    This file should be wim file - you can specify "all" to patch all images inside wim file or comma delimited indexes of the images "1,3,5,10,11" this will patch only selected images
    This file should be vhd file - this will mount vhd and applies updated to this os
    
    wim or vhd file MUST be writable - copy from DVD first to the hard drive
    
    Usage:
    imagepatcher.ps1 -imagefile:c:\deployment\install.wim
    
    imagepatcher.ps1 -imagefile:c:\virtual\windows7.vhd
    
.Parameter -patchimages
    defines which images will be patched (not used with vhd files). This parameter should be "all" (default) or comma delimited index of images in the wim file
    
    Usage:
    imagepatcher.ps1 -imagefile:c:\deployment\install.wim -patchimages:"all"
    imagepatcher.ps1 -imagefile:c:\deployment\install.wim -patchimages:"1,3,6,10"
    
     .\imagepatcher.ps1 -imagefile:"C:\DeploymentShare\Operating Systems\AIO\sources\install.wim" -dbg:yes

#>
param(
    [Parameter(Mandatory=$FALSE, HelpMessage="Show detailed debug information about process")]
    [string]$dbg = "no",
    [Parameter(Mandatory=$TRUE, HelpMessage="Path to the image files (wim or vhd)")]
	[ValidateNotNullorEmpty()]    
    [string]$imagefile=(Read-Host "The path to image file (wim or vhd)"),
    [Parameter(Mandatory=$FALSE, HelpMessage="Select images to patch in the wim file (not used in case of vhd files). type `"all`" to patch all images in wim file or comma delimited list of the image indexes `"1,3,5,10`"")]
    [string]$patchimages = "all"
)
    
## Get-WebFile (aka wget for PowerShell)
##############################################################################################################
## Downloads a file or page from the web
## History:
## v3.6 - Add -Passthru switch to output TEXT files 
## v3.5 - Add -Quiet switch to turn off the progress reports ...
## v3.4 - Add progress report for files which don't report size
## v3.3 - Add progress report for files which report their size
## v3.2 - Use the pure Stream object because StreamWriter is based on TextWriter:
##        it was messing up binary files, and making mistakes with extended characters in text
## v3.1 - Unwrap the filename when it has quotes around it
## v3   - rewritten completely using HttpWebRequest + HttpWebResponse to figure out the file name, if possible
## v2   - adds a ton of parsing to make the output pretty
##        added measuring the scripts involved in the command, (uses Tokenizer)
##############################################################################################################
function Get-WebFile {
   param( 
      $url = (Read-Host "The URL to download"),
      $fileName = $null,
      $downloadpath,
      $forcednld,
      [switch]$Passthru,
      [switch]$quiet
   )
   if ($url.length -lt 1) {return}
   
   $webfilename = $url.split("/")[$url.count-1]
   $fileName = $downloadpath + "\" + $webfilename
   write-debug $fileName
   if((test-path $filename) -and -not $forcednld){
        write-host "$webfilename file already downloaded, will use the old one"
        return
   } else {
   
   try {
   $req = [System.Net.HttpWebRequest]::Create($url);
   $res = $req.GetResponse();
   } catch {
   
    if((test-path $filename) -and -not $forcednld){
        write-host "Unable to download $webfilename but same file already downloaded, will use the old one"
    } else {
        write-host "Unable to download $webfilename and no downloaded found. Exitting..."
        break
    }
   return
   }
   }
   #write-host $res.ContentLength
   $localcabsize=0

   if(test-path $filename){
    $cabfile = Get-Item $filename
    #write-host $cabfile.length
    $localcabsize = $cabfile.length
   }

   if($localcabsize -eq $res.ContentLength){
    write-host "File $fileName is same version, not downloading"
    return
   }
   if($fileName -and !(Split-Path $fileName)) {
      $fileName = Join-Path (Get-Location -PSProvider "FileSystem") $fileName
   } 
   elseif((!$Passthru -and ($fileName -eq $null)) -or (($fileName -ne $null) -and (Test-Path -PathType "Container" $fileName)))
   {
      [string]$fileName = ([regex]'(?i)filename=(.*)$').Match( $res.Headers["Content-Disposition"] ).Groups[1].Value
      $fileName = $fileName.trim("\/""'")
      if(!$fileName) {
         $fileName = $res.ResponseUri.Segments[-1]
         $fileName = $fileName.trim("\/")
         if(!$fileName) { 
            $fileName = Read-Host "Please provide a file name"
         }
         $fileName = $fileName.trim("\/")
         if(!([IO.FileInfo]$fileName).Extension) {
            $fileName = $fileName + "." + $res.ContentType.Split(";")[0].Split("/")[1]
         }
      }
      $fileName = Join-Path (Get-Location -PSProvider "FileSystem") $fileName
   }
   if($Passthru) {
      $encoding = [System.Text.Encoding]::GetEncoding( $res.CharacterSet )
      [string]$output = ""
   }
 
   if($res.StatusCode -eq 200) {
      [int]$goal = $res.ContentLength
      $reader = $res.GetResponseStream()
      if($fileName) {
         $writer = new-object System.IO.FileStream $fileName, "Create"
      }
      [byte[]]$buffer = new-object byte[] 4096
      [int]$total = [int]$count = 0
      do
      {
         $count = $reader.Read($buffer, 0, $buffer.Length);
         if($fileName) {
            $writer.Write($buffer, 0, $count);
         } 
         if($Passthru){
            $output += $encoding.GetString($buffer,0,$count)
         } elseif(!$quiet) {
            $total += $count
            if($goal -gt 0) {
               Write-Progress "Downloading $url" "Saving $total of $goal" -id 0 -percentComplete (($total/$goal)*100)
            } else {
               Write-Progress "Downloading $url" "Saving $total bytes..." -id 0
            }
         }
      } while ($count -gt 0)
      
      $reader.Close()
      if($fileName) {
         $writer.Flush()
         $writer.Close()
      }
      if($Passthru){
         $output
      }
   }
   $res.Close(); 
   if($fileName) {
      ls $fileName
   }
}


function Update-History {
    $n = 1000

    $objSession = New-Object -com "Microsoft.Update.Session"

    $objSearcher= $objSession.CreateUpdateSearcher()

    $colHistory = $objSearcher.QueryHistory(1, $n)

    Foreach($objEntry in $colHistory){
        Write-host $objEntry.Date $objEntry.Title
    }
}

Function Get-ShortPath{
param (
    $filename
)
    $a = New-Object -ComObject Scripting.FileSystemObject
    $f = $a.GetFile($filename)
    $f.ShortPath
}

function Mount-VHD {

param (

    [Parameter(Mandatory=$TRUE, HelpMessage="Path of VHD to be mounted")]
    [ValidateNotNullOrEmpty()]
    [System.String]
    $VHDPath

)

    $imageMgmtService = Get-WmiObject -NameSpace  root\virtualization -Class MsVM_ImageManagementService
    $result = $imageMgmtService.Mount($VHDPath)
    
    if ($result.Job -ne $NULL)
    {
        $result = Test-WMIJob $result.Job -Description "Mounting VHD at $VHDPath" -Wait
        if ($result -eq 7) { $result = 0 }
    }
    else
    {
        $result = $result.ReturnValue
    }

    if ($result -ne 0)
    {
        Write-Error "Failed to mount VHD : $VHDPath"
        return
    }

	$attemptDuration = 0
	$driveLetter = ""
	while ((-not $driveLetter) -and ($attemptDuration -lt 120))
	{
		Start-Sleep 2
		$attemptDuration += 2

	    $mountedImage = Get-WmiObject -NameSpace root\virtualization -query "select * from Msvm_MountedStorageImage where name = '$($VHDPath.replace('\','\\'))'"
    	$diskDevice = Get-WmiObject -Query "select * From win32_diskdrive where Model='Msft Virtual Disk SCSI Disk Device' and ScsiTargetID=$($mountedImage.TargetId) and ScsiLogicalUnit=$($mountedImage.Lun) and scsiPort=$($mountedImage.PortNumber)"
    	$diskPartition = Get-WmiObject -Query "associators of {$diskDevice} where AssocClass=Win32_DiskDriveToDiskPartition"
    	$logicalPartition = Get-WmiObject -Query "associators of {$diskPartition} where AssocClass=Win32_LogicalDiskToPartition"
		$driveLetter = $logicalPartition.DeviceID
	}
    
	if (-not $driveLetter)
	{
		Unmount-VHD $VHDPath
		Write-Error "Failed to fetch drive letter for VHD : $VHDPath"
		return
	}
	
    Write-Verbose "Drive mounted at $driveLetter"    
    return $driveLetter

}

function Unmount-VHD {

param (

    [Parameter(Mandatory=$TRUE, HelpMessage="Path of VHD to be unmounted")]
    [ValidateNotNullOrEmpty()]
    [System.String]
    $VHDPath
    
)

    $mountedImage = Get-WmiObject -NameSpace root\virtualization -query "select * from Msvm_MountedStorageImage where name = '$($VHDPath.replace('\','\\'))'"
    $result = $mountedImage.Unmount()

}

function Check-AvailableDrive {
    param ( $driveLetterToSearch )
    
    foreach( $driveFound in [System.IO.DriveInfo]::GetDrives()) {
        if ($driveLetterToSearch + ":`\" -eq $driveFound.Name) { return $false } # the drive letter is in use?
    }
    
    # Drive letter is available
    return $driveFound.Name
}

function Check-DriveChange {
    param ( $driveLetterToSearch )
    $drives=@()
    if ($driveLetterToSearch -eq "") {
        foreach( $driveFound in [System.IO.DriveInfo]::GetDrives()) {$drives += $driveFound.name}
    } else {
        foreach( $driveFound in [System.IO.DriveInfo]::GetDrives()) {
            if ($driveLetterToSearch -notcontains $driveFound.name) {$drives += $driveFound.name} 
        }
    }
    return $drives

}

##############################################################
   

if ($dbg -like "yes"){
    $DebugPreference = "Continue"
}


#$imagefile = "C:\DeploymentShare\Operating Systems\AIO\sources\install.wim"
#$imagefile = "E:\_vDisk\WDTFS-x64.VHD"

#$patchimages = "18" #(Read-Host "The URL to download")
#$patchimages = "18,14,3" #Referencni a testovaci Download - Windows 7 ULTIMATE (x64) + Windows 7 ENTERPRISE (x86) + Windows Server 2008 R2 SERVERENTERPRISE
#$patchimages = "all" #(Read-Host "The URL to download")

write-debug "Checking elevated rights"
[string]$scriptpath = Split-Path -parent $MyInvocation.MyCommand.Definition
[string]$mountdir = "$scriptpath\mount"
[string]$dismpath =  "$ENV:PROGRAMFILES\Windows AIK\Tools\$env:PROCESSOR_ARCHITECTURE\Servicing\dism.exe"
[string]$imagexpath = "$ENV:PROGRAMFILES\Windows AIK\Tools\$env:PROCESSOR_ARCHITECTURE\imagex.exe"
[string]$expandpath = "$ENV:PROGRAMFILES\Windows AIK\Tools\$env:PROCESSOR_ARCHITECTURE\Servicing\expand.exe"
$vdiskScriptFileNameAttach = "AttachVhd.scr"
$vdiskScriptFileNameDettach = "DettachVhd.scr"
write-debug $scriptpath
write-debug $dismpath
write-debug $imagexpath
write-debug $mountdir
[string]$dofile = ""

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = new-object Security.Principal.WindowsPrincipal $identity
$elevated = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $elevated) {
    $err = “Sorry, you need to run this script in an elevated shell.”
    write-error $err
    break
}
write-debug "Detecting imagex and dism"
if(!(test-path $dismpath) -or !(test-path $imagexpath)){
    write-host "DISM and/or IMAGEX not found. Istall WAIK first" 
    break
}
write-debug "Checkging download dirs"
if (!(test-path $scriptpath"\x86")){New-Item -path $scriptpath"\x86" -type directory | out-null}
if (!(test-path $scriptpath"\x64")){New-Item -path $scriptpath"\x64" -type directory | out-null}
if (!(test-path $mountdir)){New-Item -path $mountdir -type directory | out-null}
write-debug "Downloading wsusscn2.cab"
Get-WebFile "http://download.windowsupdate.com/microsoftupdate/v6/wsusscan/wsusscn2.cab" $scriptpath $scriptpath $true
write-debug "Downloading static.xml"
Get-WebFile "http://optimalizovane-it.cz/support/static.xml" $scriptpath $scriptpath $true
if (!(test-path $scriptpath"\wsusscn2.cab")){
    write-host "Missing wsusscn2.cab - probably download problem, check your internet connectivity"
    break
}
$cabfile = Get-Item $scriptpath"\wsusscn2.cab"
write-debug "Expanding package.cab from wsusscn2.cab"
& $expandpath "$scriptpath\wsusscn2.cab" "$scriptpath\" "-f:package.cab"
write-debug "Expanding package.xml from package.cab"
& $expandpath "$scriptpath\package.cab" "$scriptpath\package.xml" "-f:package.xml"

$x = [xml](gc $scriptpath"\static.xml")
write-host "Processing win6.1x86 - Static updates"
$nodex86 = $x.OfflineSyncPackage.FileLocations.FileLocation | where {$_.url -like "*windows6.1*x86*" -and $_.url -Notlike "*beta*"}  | Foreach-object {Get-WebFile $_.url $scriptpath $scriptpath"\x86" $false}
write-host "Processing win6.1x64 - Static Updates"
$nodex64 = $x.OfflineSyncPackage.FileLocations.FileLocation | where {$_.url -like "*windows6.1*x64*" -and $_.url -Notlike "*beta*"} |  Foreach-object {Get-WebFile $_.url $scriptpath $scriptpath"\x64" $false}
$x = [xml](gc $scriptpath"\package.xml")
write-host "Processing win6.1x86"
$nodex86 = $x.OfflineSyncPackage.FileLocations.FileLocation | where {$_.url -like "*windows6.1*x86*" -and $_.url -Notlike "*beta*"}  | Foreach-object {Get-WebFile $_.url $scriptpath $scriptpath"\x86" $false}
write-host "Processing win6.1x64"
$nodex64 = $x.OfflineSyncPackage.FileLocations.FileLocation | where {$_.url -like "*windows6.1*x64*" -and $_.url -Notlike "*beta*"} |  Foreach-object {Get-WebFile $_.url $scriptpath $scriptpath"\x64" $false}
$commands = @()

if ($imagefile -like "*.wim"){
    write-debug "detected wim"
    write-debug $imagexpath" -info -xml "$imagefile" >> "$scriptpath"\wiminfo.xml"
    & $imagexpath "-info" "-xml" "$imagefile" | out-file -filepath $scriptpath"\wiminfo.xml"
    write-debug "Getting xml file $scriptpath\wiminfo.xml"
    try {
        $x = [xml](gc $scriptpath"\wiminfo.xml")
    } catch {
        write-error "--- Unable to process $scriptpath\wiminfo.xml probably caused by incorrect wim file ---"
        break
    }
    $images = $x.wim.image
    write-debug "Preparing mount dir $mountdir"
    Remove-Item $mountdir\* -recurse    
    if($patchimages -eq "all"){
        foreach ($imageindex in $images){
            $ndx = $imageindex.index
            $commands = $commands + "/Mount-Wim;/WimFile:$imagefile;/index:$ndx;/mountdir:$mountdir\$ndx"
            write-debug $imageindex.name
            $arch=""
            if ($imageindex.windows.arch -eq 0) {
                $arch="x86"
            } elseif($imageindex.windows.arch -eq 9) {
                $arch="x64"
            }
            $commands += "/image:$mountdir\$ndx;/add-package;/PackagePath:$scriptpath\" + $arch + ";"
            $commands = $commands + "/unmount-wim;/mountdir:$mountdir\$ndx;/commit;"
            [string]$imagendx = $imageindex.index
            New-Item -path $mountdir"\"$imagendx -type directory | out-null
        }
    } else {
        $imgindexes = $patchimages.split(",")
        foreach ($imageindex in $imgindexes){
            $commands = $commands + "/Mount-Wim;/WimFile:$imagefile;/index:$imageindex;/mountdir:$mountdir\$imageindex"
            write-debug $images[$imageindex-1].name
            $arch=""
            if ($images[$imageindex-1].windows.arch -eq 0) {
                $arch="x86"
            } elseif($images[$imageindex-1].windows.arch -eq 9) {
                $arch="x64"
            }        
            $commands += "/image:$mountdir\$imageindex;/add-package;/PackagePath:$scriptpath\" + $arch + ";"
            $commands = $commands + "/unmount-wim;/mountdir:$mountdir\$imageindex;/commit;"
            New-Item -path $mountdir"\"$imageindex -type directory | out-null
        }
    }
} elseif ($imagefile -like "*.vhd") {
    write-debug "detected vhd"
    $dofile = "vhd"
    $origdrives = Check-DriveChange ""
    "SELECT VDISK FILE=`"$imagefile`"`r`n" + "ATTACH VDISK`r`n" + "RESCAN" | Out-File $env:TEMP\Mountvhd.txt -Encoding "ASCII"
    "SELECT VDISK FILE=`"$imagefile`"`r`n" + "DETACH VDISK" | Out-File $env:TEMP\Unmountvhd.txt -Encoding "ASCII"
    Invoke-Expression -Command "Diskpart.exe /s $env:TEMP\Mountvhd.txt"
    start-sleep 5
    $mountdir = Check-DriveChange $origdrives
    write-debug $mountdir
    if (!(test-path $mountdir)){
        write-error "unable to mount vhd file" 
        break
    }    
    if ((test-path $mountdir"Program Files (x86)")){
        $arch = "x64"
    } else {
        $arch = "x86"
    }
    $commands += "/image:$mountdir;/add-package;/PackagePath:$scriptpath\" + $arch + ";"
    
} else {
    write-error "sorry not knownfile type"
}



foreach ($command in $commands){
    write-debug $command
    $cmd = $command.split(";")
    & $dismpath $cmd[0] $cmd[1] $cmd[2] $cmd[3]
    if ($dofile -eq "vhd") {Invoke-Expression -Command "Diskpart.exe /s $env:TEMP\Unmountvhd.txt"}
}    
