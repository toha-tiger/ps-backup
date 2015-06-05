$myDirs=
'D:\install',
'C:\Users\Anton\Google Диск\Itera-research',
'C:\wamp',
'C:\openserver',
'C:\Users\Anton\Documents'

$destDrive = "f:"

#---------------------------------------------------------------------------------------------------------

function loadLibs {
    $global:md5 = new-object -TypeName System.Security.Cryptography.MD5CryptoServiceProvider
    $signature = '[DllImport("Kernel32.dll")] public static extern bool CreateHardLink(string lpFileName,string lpExistingFileName,IntPtr lpSecurityAttributes);'
    Add-Type -MemberDefinition $signature -Name Creator -Namespace Link
    [System.Reflection.Assembly]::LoadWithPartialName("System.Windows.Forms") | out-null;  
}

function Test-FileLock {
  param ([parameter(Mandatory=$true)][string]$Path)

  $oFile = New-Object System.IO.FileInfo $Path

  if ((Test-Path -Path $Path) -eq $false)
  {
    return $false
  }

  try
  {
      $oStream = $oFile.Open([System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::None)
      #::ReadWrite
      if ($oStream)
      {
        $oStream.Close()
      }
      $false
  }
  catch
  {
    # file is locked by a process.
    return $true
  }
}

function TestDestDrive {
   param([System.IO.FileInfo] $destDrive)
    $ok = Get-Item $destDrive 2>&1;
    while ($ok.ToString().Substring(0,2) -ne $destDrive) {
        Write-Host "Drive $destDrive is not ready. Connect drive and press Enter." ;
        $newDrive = Read-Host 'Or enter new drive letter and press Enter...';
        if($newDrive -match "[a-z](:)?") {
            $destDrive = $newDrive.TrimEnd(":") + ":";
        }
        #$dest="$destDrive\backup-$date\" 
        Write-host "Trying $destDrive";
        $ok = Get-Item $destDrive.ToString() 2>&1;
    }
    return $destDrive;
}

function GetLastBackupDir {
    param([System.IO.FileInfo] $dest)

    $dirs = Get-ChildItem $dest | ?{ $_.PSIsContainer } | Select-Object Name
    if ($dirs) {
        $maxdate = @{Name=''}
        foreach($dir in $dirs) {
            if ($dir.Name -gt $maxdate.Name) {
                $maxdate = $dir
            }
        }
        return Join-Path -Path $dest -ChildPath $maxdate.Name;
    } else {
        return $false;
    }
}


function FilesAreEqual {
   param([System.IO.FileInfo] $first, [System.IO.FileInfo] $second) 
   
   $BYTES_TO_READ = 16 * 1024;

   if ($first.Length -ne $second.Length) {
        return $false;
   }
   
   if ($first.Length -eq 0) {
    return $true;
   }
   
   if ($first.Length -lt $BYTES_TO_READ) {
    $BYTES_TO_READ = $first.Length;
   }

   $iterations = [Math]::Ceiling($first.Length / $BYTES_TO_READ);
   $fs1 = $first.OpenRead();
   $fs2 = $second.OpenRead();

   $one = New-Object byte[] $BYTES_TO_READ;
   $two = New-Object byte[] $BYTES_TO_READ;

   for ($i = 0; $i -lt $iterations; $i++) {
       $fs1.Read($one, 0, $BYTES_TO_READ) | out-null;
       $fs2.Read($two, 0, $BYTES_TO_READ) | out-null;

       $hashOne = $global:md5.ComputeHash($one)
       $hashTwo = $global:md5.ComputeHash($two)
       if (Compare-Object $hashOne $hashTwo) {
           $fs1.Close();
           $fs2.Close();
           return $false;
       }
   }

   $fs1.Close();
   $fs2.Close();

   return $true;
}


function BackupTo {
   param([System.IO.FileInfo] $origin, [System.IO.FileInfo] $backup, [System.IO.FileInfo] $dest) 

    #Remove-Item $dest -Recurse -Force | out-null
    if(!(test-path $dest)) {
        New-Item -Path $dest -type "directory" | out-null
    }

    Write-Host "Reading dir"

    $fso = Get-ChildItem -Recurse -Force -Path $origin
    $totalCout = $fso.count

    if(test-path $backup) {
        $fsoBU = Get-ChildItem -Recurse -Force -Path $backup
        $fsoBUlist = [System.Collections.Generic.List[System.Object]]@()

        Set-Location $backup;
        ForEach ($fsB in $fsoBU) {
            if ($fsB -isNot [System.IO.DirectoryInfo]) {
                $relativePathBU = $fsB | Resolve-Path -Relative;
                $fsoBUlist.add($relativePathBU);
            }
        }
    }

    $counter = 0;
    ForEach ($fs in $fso) {
        Set-Location $origin;
        $relativePath = $fs | Resolve-Path -Relative;
        $destPath = Join-Path -Path $dest -ChildPath $relativePath;

        if ($fs -is [System.IO.DirectoryInfo]) {
            #create directory in dest
            New-Item -Path $destPath -type "directory" | out-null;
        } else {
            if (Test-FileLock $fs.FullName) {
                Write-Host Skipping $fs.FullName;
                Continue;
            }
            $i = 0;
            ForEach ($fsB in $fsoBUlist) {
                $found = $False;
                if ($relativePath -eq $fsB) {
                    $found = Join-Path -Path $backup -ChildPath $fsB;
                    $fsoBUlist.removeAt($i);
                    Break;
                }
                $i++;
            }
            
            if($found) {
                #compare by content
                if (FilesAreEqual $fs.FullName $found) {
                    #copy harlink to dest
                    [Link.Creator]::CreateHardLink($destPath,$found,[IntPtr]::Zero) | out-null;
                } else {
                    #copy to dest
                    #Write-Host "files are not equal $fs";
                    Copy-Item -LiteralPath $fs.FullName -Destination $destPath | out-null;
                }
            } else {
                #not found, copy to dest
                Copy-Item -LiteralPath $fs.FullName -Destination $destPath | out-null;
            }
        }
        $counter++;
        $status = "Copy files {0} on {1}: {2}" -f $counter, $totalCout, $destPath;
        Write-Progress -Activity "Copy data" $status -PercentComplete ($counter / $totalCout * 100);
    }
}

function main {
    loadLibs;
    Write-host "`n`n`n`n`n`n"
    $host.ui.RawUI.WindowTitle = "Backup"
    $destDrive = TestDestDrive $destDrive;
    $dest="$destDrive\backup";

    $date=Get-Date -format 'yyyy-MM-dd-HHmmss'
    $destDir="$destDrive\backup\$date";

    if (!(test-path $dest)) {
        New-Item -Path $dest -type "directory" | out-null
    }

    $lastBackupDir = GetLastBackupDir $dest;

    foreach ($dir in $myDirs) {
        if (!(test-path $dir)) {
            Write-Host not found $dir
            continue
        }
        $dirPath = Get-Item $dir;
        $lastBackupPath = Join-Path -Path $lastBackupDir -ChildPath $dirPath.Name;

        $destPath = Join-Path -Path $destDir -ChildPath $dirPath.Name;

        $host.ui.RawUI.WindowTitle = "Backup to $destDir";        
        Write-Host "------------------------------------------";
        Write-Host "copying  $dir to $destPath";
        if ($lastBackupDir -ne '') {
            Write-Host "hardlinks to: $lastBackupPath";
        }
        Write-Host "------------------------------------------"
        
        BackupTo $dirPath.FullName $lastBackupPath $destPath;
        
    }

    [System.Windows.Forms.MessageBox]::Show("Backup End.");
}

main;