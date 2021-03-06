$myDirs=
'C:\Users\Anton\Google Диск\Itera-research',
'C:\openserver\domains',
'C:\Users\Anton\Documents',
'C:\Users\Anton\Dropbox'

$skip=
'\.svn',
'\.git',
'_logs',
'_tmp'

$destDrive = "f:"

#---------------------------------------------------------------------------------------------------------

function loadLibs {
    $global:md5 = new-object -TypeName System.Security.Cryptography.MD5CryptoServiceProvider;
    $signature = '[DllImport("Kernel32.dll")] public static extern bool CreateHardLink(string lpFileName,string lpExistingFileName,IntPtr lpSecurityAttributes);';
    Add-Type -MemberDefinition $signature -Name Creator -Namespace Link;
    [System.Reflection.Assembly]::LoadWithPartialName("System.Windows.Forms") | out-null;  
    $global:stopwatch = New-Object System.Diagnostics.Stopwatch;
}

function Test-FileLock {
  param ([parameter(Mandatory=$true)][string]$Path)

  $oFile = New-Object System.IO.FileInfo $Path;

  if ((Test-Path -Path $Path) -eq $false) {
    return $false;
  }

  try {
      $oStream = $oFile.Open([System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::None);
      #::ReadWrite
      if ($oStream) {
        $oStream.Close();
      }
      $false
  } catch {
    # file is locked by a process.
    return $true;
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

    $dirs = Get-ChildItem $dest | ?{ $_.PSIsContainer } | Select-Object Name;
    if ($dirs) {
        $maxdate = @{Name=''}
        foreach($dir in $dirs) {
            if ($dir.Name -gt $maxdate.Name) {
                $maxdate = $dir;
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

       $hashOne = $global:md5.ComputeHash($one);
       $hashTwo = $global:md5.ComputeHash($two);
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

function getOperationPool {
  param([System.IO.FileInfo] $origin, [System.IO.FileInfo] $backup)

    $pool = [System.Collections.Generic.List[System.Object]]@();

    $fso = Get-ChildItem -Recurse -Force -Exclude $skip -Path $origin;
    $totalCout = $fso.count;
    
    $refreshInterval = 200;
    if ($totalCount -ge 90000) {
        $refreshInterval = 1000;
    }

    Set-Location $origin;
    $counter = 0;
    $global:stopwatch.Start();
    $ms = $global:stopwatch.ElapsedMilliseconds;
    ForEach ($fs in $fso) {
        $relativePath = $fs | Resolve-Path -Relative;
        $obj = @{path = $relativePath};
        
        $operation = '';
        ForEach($skipOption in $skip) {
            if ($relativePath -match $skipOption) {
                $operation = 'skip';
                break;
            }
        }
        if ($operation -ne 'skip') {
            if ($fs -is [System.IO.DirectoryInfo]) {
                $operation = 'create_dir';
            } else {
                $buPath = Join-Path -Path $backup -ChildPath $obj.path;
                if ((Test-Path -Path $buPath)) {
                    $operation = 'compare';
                } else {
                    $operation = 'copy';
                }
                
            }

            $obj = @{path = $relativePath; operation = $operation};
            #Write-Host $obj.operation $obj.path
            
            $pool.add($obj);
        }
        $counter++;
        if (($global:stopwatch.ElapsedMilliseconds - $ms) -ge $refreshInterval) {
            $ms = $global:stopwatch.ElapsedMilliseconds;
            $status = "{0} of {1}" -f $counter, $totalCout;
            Write-Progress -Activity "Reading $status" $origin -PercentComplete ($counter / $totalCout * 100);
        }

    }
    $global:stopwatch.Stop()

    return $pool;
   
}

function BackupTo {
  param([System.IO.FileInfo] $origin, [System.IO.FileInfo] $backup, [System.IO.FileInfo] $dest)

    #Remove-Item $dest -Recurse -Force | out-null
    if(!(test-path $dest)) {
        New-Item -Path $dest -type "directory" | out-null;
    }

    Write-Host "Reading dir";
    $pool = getOperationPool $origin $backup;

    Write-Host "Processing";
    $totalCout = $pool.count;
    $refreshInterval = 200;
    if ($totalCount -ge 90000) {
        $refreshInterval = 1000;
    }

    $counter = 0;
    $global:stopwatch.Start();
    $ms = $global:stopwatch.ElapsedMilliseconds;
    foreach($obj in $pool) {
        $sourcePath = Join-Path -Path $origin -ChildPath $obj.path;
        $destPath = Join-Path -Path $dest -ChildPath $obj.path;
        $lastOperation = $obj.operation;
        Switch -exact ($obj.operation) {
            'create_dir' {
                #create directory in dest
                #Write-Host "create $destPath";
                New-Item -Path $destPath -type "directory" | out-null;
            } 
            'copy' {
                if (Test-FileLock $sourcePath) {
                    Write-Host Skipping $sourcePath;
                    Continue;
                }
                #copy to dest
                #Write-Host "new file $sourcePath";
                Copy-Item -LiteralPath $sourcePath -Destination $destPath | out-null;
            }
            'compare' {
                if (Test-FileLock $sourcePath) {
                    #Write-Host Skipping $sourcePath;
                    Continue;
                }
                $backupPath = Join-Path -Path $backup -ChildPath $obj.path;
                if (FilesAreEqual $sourcePath $backupPath) {
                    #copy harlink to dest
                    #Write-Host "make hardlink $backupPath $destPath";
                    [Link.Creator]::CreateHardLink($destPath, $backupPath, [IntPtr]::Zero) | out-null;
                } else {
                    #copy to dest
                    #Write-Host "files are not equal $sourcePath";
                    Copy-Item -LiteralPath $sourcePath -Destination $destPath | out-null;
                }
            }
            default {
                Write-Host "Unsupported operation!"
            }
        }

        $counter++;
        if (($global:stopwatch.ElapsedMilliseconds - $ms) -ge $refreshInterval) {
            $ms = $global:stopwatch.ElapsedMilliseconds;
            $status = "{0} of {1}" -f $counter, $totalCout;
            Write-Progress -Activity "Processing $lastOperation $status" $destPath -PercentComplete ($counter / $totalCout * 100);
        }
    }
    $global:stopwatch.Stop()

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
        Write-Host "Copying " (Get-Date -format 'yyyy-MM-dd-HH:mm:ss');
        Write-Host "$dir to $destPath";
        if ($lastBackupDir -ne '') {
            Write-Host "hardlinks to: $lastBackupPath";
        }
        Write-Host "------------------------------------------"
        
        BackupTo $dirPath.FullName $lastBackupPath $destPath;
        Write-Host "Done " (Get-Date -format 'yyyy-MM-dd-HH:mm:ss')
        
    }

    [System.Windows.Forms.MessageBox]::Show("Backup End.");
}

main;