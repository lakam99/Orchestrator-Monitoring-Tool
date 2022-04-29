#Orchestrator Monitoring Tool
#Written by Arkam Mazrui
#arkam.mazrui@nserc-crsng.gc.ca
#arkam.mazrui@gmail.com

#v0.1 objectives
#    Get all runbooks and their current status

cd $PSScriptRoot;

$params = Import-Clixml '.\monitoring-tool-params.xml';

$orchestratorDatabaseServer =$params.orchestratorDatabaseServer;
$orchestratorDatabase = $params.orchestratorDatabase;
$orchestratorUrl = $params.orchestratorUrl;
$dbAdminCredentials = Import-Clixml ".\file.xml";
[System.Collections.ArrayList]$Global:runbooks = @();
$Global:runbook_jobs = @{};
[System.Collections.ArrayList]$Global:runbook_statuses = @();
$Global:menu_options = @('Refresh Statuses', 'Stop Runbook', 'Start Runbook', 'Quit');
$global:menu_inputs = @('1', '2', '3', 'q');
$Global:run = $true;

function get-db-credentials {
    if ($dbAdminCredentials -eq 0) {
        Add-Type -AssemblyName System.DirectoryServices.AccountManagement;
        $validator = New-Object System.DirectoryServices.AccountManagement.PrincipalContext('domain');
        do {
            $dbAdminCredentials = Get-Credential -Message "Please enter a valid database admin credential.";
        } while (!($validator.validateCredentials($dbAdminCredentials.UserName, $dbAdminCredentials.GetNetworkCredential().Password)));
    }
    return $dbAdminCredentials;
}

function run-query {
    Param([String]$query)
    $job = Start-Job {
        Param([String]$databaseServer, [String]$database, [String]$query)
        Invoke-Sqlcmd -ServerInstance $databaseServer -Database $database -Query $query 
    } -ArgumentList $orchestratorDatabaseServer, $orchestratorDatabase, $query -Credential $(get-db-credentials);
    Wait-Job $job;
    $r = Receive-Job $job -ErrorAction Stop;
    return $r;
}

function test-db-connection {
    $testQuery = 'Select TOP(1) * FROM POLICIES';
    $r = run-query $testQuery;
    if ($r) {
        Write-Host -ForegroundColor Green "Successfully retrieved test data from database.";
    } else {
        Write-Host -ForegroundColor Yellow "No results in attempt to retreive one runbook from database.";
    }
    return $r;
}

function get-all-runbooks {
    $query = 'Select UniqueID, Name from POLICIES where Deleted = 0';
    $r = run-query $query;
    $r | %{$runbooks.Add($_)} | Out-Null;
    $Global:runbooks = $Global:runbooks[1..$($runbooks.Count)]
}

function get-runbooks-latest-jobs {
    $Global:runbooks | %{
        $query = "Select TOP(1) b.Name, b.UniqueID as RunbookId, a.JobId, a.Status, a.State, a.TimeStarted from POLICYINSTANCES as a right join POLICIES as b on b.UniqueID = a.PolicyID where b.Deleted = 0 and b.UniqueID = '$($_.UniqueId)' Order by a.TimeStarted desc"
        $r = run-query $query;
        $Global:runbook_jobs["$($_.UniqueId.Guid)"] = $r[1];
    }
}

function get-runbook-statuses {
    $Global:runbooks | %{
        $job_id = $Global:runbook_jobs[$_.UniqueId.Guid].JobId;
        $status = 'Not Started';
        if ($job_id -ne '') {
            $url = "$orchestratorUrl(guid'$job_id')";
            [xml]$r = (Invoke-WebRequest -Uri $url -Method Get -UseDefaultCredentials).Content;
            $Global:runbook_statuses.Add(@{name=$_.Name;uniqueId=$_.UniqueId.Guid;response=$r;status=$r.entry.content.properties.Status}) | Out-Null;
        } else {
            $Global:runbook_statuses.Add(@{name=$_.Name;uniqueId=$_.UniqueId.Guid;response=$null;status=$status}) | Out-Null;
        }
    }
}

function display-statuses {
    $Global:runbook_statuses | %{[PSCustomObject]@{Runbook=$_.Name;Status=$_.Status}} | Format-Table -AutoSize
}

function start-runbook {
    display-statuses;
    $runbook_name = Read-Host "Enter the name of the runbook";
    $runbook = $Global:runbook_statuses | ?{$_.Name -eq "$runbook_name"};
    if ($runbook.response -ne $null) {
        if ($runbook.Status -ne 'Not Started' -and $runbook.Status -ne 'Running') {
            $temp_response = $runbook.response;
            $temp_response.entry.content.properties.Status = 'Running';
            $request_body = $temp_response.OuterXml;
            $r = Invoke-RestMethod -Uri $orchestratorUrl -Method Post -Body $request_body -ContentType "application/atom+xml" -UseDefaultCredentials;
            Write-Host "Finished starting runbook.";
        } elseif ($runbook.Status -eq 'Running') {
            throw "Cannot start an already started runbook.";
        }
    }
}

function display-title {
    Write-Host "####################################################";
    Write-Host "#                                                  #";
    Write-Host "#                                                  #";
    Write-Host "#        Welcome to Orchestrator Monitoring Tool   #";
    Write-Host "#                  Developed by                    #";
    Write-Host "#                 Arkam A. Mazrui                  #";
    Write-Host "#           arkam.mazrui@nserc-crsng.gc.ca         #";
    Write-Host "#              arkam.mazrui@gmail.com              #";
    Write-Host "#                                                  #";
    Write-Host "#                                                  #";
    Write-Host "####################################################";
}

function display-options {
    $i = 1;
    $Global:menu_options | %{
        Write-Host "$i : $_";
        $i++;
    }
}

function display-menu {
    display-title;
    display-options;
}

function process-menu {
    do {
        $in = Read-Host "Please choose a menu option ";
    } while (!($global:menu_inputs.Contains($in)));

    switch ($in) {
        '1' {get-runbook-statuses;break;}
        '2' {;break;}
        '3' {start-runbook;break;}
        'q' {$Global:run = $false;break;}
        default: {break;}
    }
}

function do-menu {
    while ($Global:run) {
        cls;
        display-statuses;
        display-menu;
        process-menu;
    }
}

function start-tool {
    Write-Host "Getting runbooks...";
    get-all-runbooks;
    Write-Host "Getting runbook jobs...";
    get-runbooks-latest-jobs;
    Write-Host "Getting runbook statuses...";
    get-runbook-statuses;
    do-menu;
}


start-tool;