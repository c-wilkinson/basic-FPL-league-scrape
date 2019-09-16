[void][Reflection.Assembly]::LoadWithPartialName("System.Windows.Forms.DataVisualization")
cls
Write-Host "Authenicate with the FPL website" -ForegroundColor Green;
$Credential = Get-Credential -Message 'Please enter your FPL login details';
$UserAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/77.0.3865.19 Safari/537.36";
$Uri = 'https://users.premierleague.com/accounts/login/';
[Net.ServicePointManager]::SecurityProtocol = "tls12, tls11, tls";
$LoginResponse = Invoke-WebRequest -Uri $Uri -SessionVariable 'FplSession' -UseBasicParsing;
$CsrfToken = $LoginResponse.InputFields.Where{$_.name -eq 'csrfmiddlewaretoken'}.value;
$Response = Invoke-WebRequest -Uri $Uri -WebSession $FplSession -Method 'Post' -UseBasicParsing -Body @{
    'csrfmiddlewaretoken' = $CsrfToken
    'login'               = $Credential.UserName
    'password'            = $Credential.GetNetworkCredential().Password
    'app'                 = 'plfpl-web'
    'redirect_uri'        = 'https://fantasy.premierleague.com/a/login'
    'user-agent'          = $UserAgent
};

Write-Host "Wipe History Table" -ForegroundColor Green;
$leagueTable = @();
Write-Host "Load basic team information from FPL" -ForegroundColor Green;
$unstructuredAllData = @();
$leagueTableJson = Invoke-RestMethod -Uri "https://fantasy.premierleague.com/api/leagues-classic/36351/standings/" -WebSession $FplSession -UseBasicParsing;
# Sleep, be as kind as possible to the FPL servers!
Start-Sleep -Seconds 2.5;
# Encoding, ugly fix for bug #6
$utf8 = [System.Text.Encoding]::GetEncoding(65001);
$iso88591 = [System.Text.Encoding]::GetEncoding(28591);
# Note, we could use this for multiple pages, if we decided we needed to, as we can see the "next page" here
foreach($leaguePage in $leagueTableJson.standings)
{
    foreach($team in $leaguePage.results)
    {
        $teamurl = "https://fantasy.premierleague.com/api/entry/"+$team.entry+"/history/";
        # Encoding, ugly fix for bug #6
        $teamName = $utf8.GetBytes($team.entry_name);
        $teamName = [System.Text.Encoding]::Convert($utf8,$iso88591,$teamName);
        $teamName = $utf8.GetString($teamName);
        # Encoding, ugly fix for bug #6
        $manager = $utf8.GetBytes($team.player_name);
        $manager = [System.Text.Encoding]::Convert($utf8,$iso88591,$manager);
        $manager = $utf8.GetString($manager);
        $score = $team.total;
        $rank = $team.rank;
        $teamId = $team.entry;
        Write-Host "Load gameweek history for $teamName" -ForegroundColor Green;
        $gameweekHistoryJson = Invoke-RestMethod -Uri $teamurl -WebSession $FplSession -UseBasicParsing;
        foreach($gameweek in $gameweekHistoryJson.current)
        {
            $valueParser = ($gameweek.value).ToString();
            $value = "£" + $valueParser.SubString(0, $valueParser.length - 1) + '.' + $valueParser.SubString($valueParser.length - 1, 1);
            $unstructuredAllData += New-Object PsObject -Property @{
                                                     GameWeek = $gameweek.event;
                                                     GameWeekPoints = $gameweek.points;
                                                     PointsOnBench = $gameweek.points_on_bench;
                                                     TransfersMade = $gameweek.event_transfers;
                                                     TransfersCode = $gameweek.event_transfers_cost;
                                                     OverallPoints = $gameweek.total_points;
                                                     TeamValue = $value;
                                                     TeamId = $teamId;
                                                     Manager = $manager;
                                                     TeamName = $teamName;
                                                   };
        }

        # Sleep, be as kind as possible to the FPL servers!
        Start-Sleep -Seconds 2.5;
    }
}

Write-Host "Add gameweek ranks for the league" -ForegroundColor Green;
$rankedUnstructuredAllData = $unstructuredAllData | Group-Object GameWeek | ForEach-Object { 
      $rank = 0
      $_.Group | Sort-Object OverallPoints -Descending | Select-Object *, @{ 
       n='GameWeekRank'; e={ Set-Variable -Scope 1 rank ($rank+1); $rank } 
      }
};

$leagueTable = @();
Write-Host "Restructure the league data" -ForegroundColor Green;
foreach($info in $rankedUnstructuredAllData)
{
    $currentdata = $leagueTable | Where-Object {$_.TeamId -eq $info.TeamId};
    $gameweek = New-Object PsObject -Property @{
                                                 GameWeek = $info.GameWeek;
                                                 GameWeekPoints = $info.GameWeekPoints;
                                                 PointsOnBench = $info.PointsOnBench;
                                                 TransfersMade = $info.TransfersMade;
                                                 TransfersCode = $info.TransfersCode;
                                                 OverallPoints = $info.OverallPoints;
                                                 GameWeekRank = $info.GameWeekRank;
                                              };
    if ($currentdata -ne $null)
    {
        $index = $leagueTable.IndexOf($currentdata);
        $currentdata.GameWeekHistory += $gameweek;
        $leagueTable[$index] = $currentdata;
    }
    else
    {
        $gameweekHistoryArray = @();
        $gameweekHistoryArray += $gameweek;
        $leagueTable += New-Object PsObject -Property @{
                                                         TeamValue = $info.TeamValue;
                                                         TeamId = $info.TeamId;
                                                         Manager = $info.Manager;
                                                         TeamName = $info.TeamName;
                                                         GameWeekHistory = $gameweekHistoryArray;
                                                       };
    }
}

$totalPlayers = $leagueTable.Count;
Write-Host "Begin charting" -ForegroundColor Green
$leagueChart = New-object System.Windows.Forms.DataVisualization.Charting.Chart;
$leagueChart.Width = 1200;
$leagueChart.Height = 700;
$leagueChart.BackColor = [System.Drawing.Color]::White;
[void]$leagueChart.Titles.Add("FPL League History");
$leagueChart.Titles[0].Font = "Arial,20pt";
$leagueChart.Titles[0].Alignment = "topLeft";
$chartarea = New-Object System.Windows.Forms.DataVisualization.Charting.ChartArea;
$chartarea.Name = "ChartArea1";
$chartarea.AxisY.Title = "Rank";
$chartarea.AxisX.Title = "Gameweek";
$chartarea.AxisX.Interval = 1;
$chartarea.AxisX.IsStartedFromZero = $false;
$chartarea.AxisX.Minimum = 1;
$chartarea.AxisX.Maximum = 38;
$chartarea.AxisY.Interval = 1;
$chartarea.AxisY.IsReversed = $true;
$chartarea.AxisY.IsStartedFromZero = $false;
$chartarea.AxisY.Maximum = $totalPlayers;
$chartarea.AxisY.Minimum = 1;
$legend = New-Object system.Windows.Forms.DataVisualization.Charting.Legend;
$legend.name = "Legend1";
$leagueChart.Legends.Add($legend);
$leagueChart.ChartAreas.Add($chartarea);
foreach($team in $leagueTable)
{
    [void]$leagueChart.Series.Add($team.Manager);
    $leagueChart.Series[$team.Manager].ChartType = [System.Windows.Forms.DataVisualization.Charting.SeriesChartType]::Line;
    $leagueChart.Series[$team.Manager].BorderWidth = 3;
    $gameweekList = @();
    $gameweekRankList = @();
    foreach($week in $team.GameWeekHistory)
    {
        $gameweekList += $week.GameWeek -as [int];
        $gameweekRankList += $week.GameWeekRank -as [int];
    }

    $leagueChart.Series[$team.Manager].Points.DataBindXY($gameweekList, $gameweekRankList);
}

Write-Host "Charting complete" -ForegroundColor Green
$Form = New-Object Windows.Forms.Form;
$Form.Text = "PowerShell Chart";
$SaveButton = New-Object Windows.Forms.Button;
$SaveButton.Text = "Save to desktop";
$SaveButton.AutoSize = $true;
$SaveButton.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Right;
$SaveButton.add_click({$leagueChart.SaveImage($Env:USERPROFILE + "\Desktop\Chart.png", "PNG")});
$Form.controls.add($SaveButton);
$Form.controls.add($leagueChart);
$Form.AutoSize = $true; 
$Form.Add_Shown({$Form.Activate()});
$Form.ShowDialog();