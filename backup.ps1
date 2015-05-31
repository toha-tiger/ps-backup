$myDirs=
'D:\install',
'C:\Users\Anton\Google Диск\Itera-research',
'C:\wamp',
'C:\openserver',
'C:\Users\Anton\Documents'
$destDrive = "f:"

$date=Get-Date -format 'yyyy-MM-dd'
$host.ui.RawUI.WindowTitle = "Backup"
$ok = Get-Item $destDrive 2>&1 

while ($ok.ToString().Substring(0,2) -ne $destDrive) {
    Write-Host "Drive $destDrive is not ready. Connect drive and press Enter." 
    $newDrive = Read-Host 'Or enter new drive letter and press Enter...'
    if($newDrive -match "[a-z](:)?") {
        $destDrive = $newDrive.TrimEnd(":") + ":"
    }
    $dest="$destDrive\backup-$date\" 
    Write-host "Trying $destDrive"
    $ok = Get-Item $destDrive.ToString() 2>&1 
}

$dest="$destDrive\backup-$date\" 
$host.ui.RawUI.WindowTitle = "Backup to $dest"

foreach ($dir in $myDirs) {
    Write-Host "------------------------------------------"
    Write-Host "copying  $dir to $dest"
    Write-Host "------------------------------------------"
    $path = $dir
    #Copy-Item -LiteralPath $dir -Destination $dest -Recurse 

    $files = Get-ChildItem $path -recurse -Force
    [System.Reflection.Assembly]::LoadWithPartialName("System.Windows.Forms") | out-null;  
    $counter = 1
    Foreach($file in $files) {
        $status = "Copy files {0} on {1}: {2}" -f $counter,$files.Count,$file.Name
        Write-Progress -Activity "Copy data" $status -PercentComplete ($counter / $files.count*100)
        $restpath = $file.fullname.replace($path,"")
        $folder = Get-Item $path 
        $dst = $($dest + $folder.Name + $restpath)
        #Write-Host $file.fullname $dst -Force 
        Copy-Item  $file.fullname $dst -Force 
        if(! $?) {
            Write-Host "Error! " $file.fullname \> $dst
            Read-Host 'Press Enter to continue...' | Out-Null
            #Break
        }
            
        $counter++ 
    }

    If ($Counter = $files.Count) {
        $count = $files.Count
        Write-Host "done $count files" 
        Write-Host " "
    }
}
[System.Windows.Forms.MessageBox]::Show("Backup End.")