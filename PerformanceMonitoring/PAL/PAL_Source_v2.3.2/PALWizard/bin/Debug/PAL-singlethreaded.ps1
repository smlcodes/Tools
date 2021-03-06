﻿#requires -Version 2.0
param($Log,$ThresholdFile="QuickSystemOverview.xml",$Interval='AUTO',$IsOutputHtml=$True,$IsOutputXml=$False,$HtmlOutputFileName="[LogFileName]_PAL_ANALYSIS_[DateTimeStamp]_[GUID].htm",$XmlOutputFileName="[LogFileName]_PAL_ANALYSIS_[DateTimeStamp]_[GUID].xml",$OutputDir="[My Documents]\PAL Reports",$AllCounterStats=$False,$BeginTime=$null,$EndTime=$null)
Set-StrictMode -Version 2 #// Contributed by Jeffrey Snover
cls
#//
#// PAL v2.2
#// Written by Clint Huffman (clinth@microsoft.com)
#// This tool is not supported by Microsoft. 
#// Please post all of your support questions to the PAL web site at http://www.codeplex.com/PAL
#//
#// Special Thanks to the following people:
#// Greg Varveris (gregvar@microsoft.com) for his help with Microsoft Chart Controls for Microsoft .NET Framework 3.5
#// Shane Creamer (shanec@microsoft.com) for his inspiration and guidance on performance counters.
#// Matt Reynolds (mreyn@microsoft.com) for all the help with learning PowerShell.
#//
#// Contributors:
#// JonnyG, Andy (from Codeplex.com), Jeffrey Snover (Inventor of Windows PowerShell), and Hal Rottenberg (PowerScripting Podcast host)

#/////////////////////////////////
#// Main() function and overall processing of the script, scroll to the bottom of the script.
#/////////////////////////////////

#/////////////////////////////////
#// Global variables
#/////////////////////////////////

#// Globalization of date time - code provided by JonnyG.
$global:sDateTimePattern = (get-culture).datetimeformat.ShortDatePattern + " " + (get-culture).datetimeformat.LongTimePattern
#$global:sDateTimePattern = $global:sDateTimePattern -Replace($((Get-Culture).datetimeformat.DateSeparator),'-')
## Commented out below this is redundant JonnyG 2010-06-11
#$global:BeginTime = $BeginTime
$global:NumberOfValuesPerTimeSlice = -1

#// added by malfalt and jojodis on http://pal.codeplex.com
$global:originalCulture = (get-culture).Name
$global:currentThread = [System.Threading.Thread]::CurrentThread

#// Chart Constants
$CHART_LINE_THICKNESS = 3 #// 2 is thin, 3 is normal, 4 is thick
$CHART_WIDTH = 1024        #// Width in pixels
$CHART_HEIGHT = 480       #// height in pixels
$CHART_MAX_INSTANCES = 10 #// the maximum number of counter instance in a chart
$global:CHART_MAX_NUMBER_OF_AXIS_X_INTERVALS = 30 #// The maximum allowed X axis labels in the chart.

#// Global script properties
$global:htScript = @{"Version" = "v2.2.2";"ScriptFileObject" = "";"Culture"="";"LocalizedDecimal" = "";"LocalizedThousandsSeparator" = "";"BeginTime" = "";"EndTime" = "";"ScriptFileLastModified" = "";"SessionGuid"= "";"MainHeader"="";"UserTempDirectory"="";"DebugLog"="";"SessionDateTimeStamp"="";"SessionWorkingDirectory" = ""}
$global:sCounterListFilterFilePath = ''

#// Database connectivity global variables
$global:IsCounterLogFile = $True
$global:IsDatabaseConnectionString = $False
$global:sDbConnectionString = ''
$global:sDatabaseName = ''
$global:sDatabaseServerName = ''
$global:sDatabaseLogSet = ''

#// Global analysis
[xml] $global:XmlAnalysis = "<PAL></PAL>"
$global:alThresholdFilePathLoadHistory = New-Object System.Collections.ArrayList
$global:htAnalysis = @{}
$global:aCounterLogCounterList = ""
$global:aTime = ""
$global:alQuantizedTime = $null
$global:AutoAnalysisInterval = ""
$global:htCounterInstanceStats = @{}
$global:htQuestionVariables = @{}
$global:alCounterExpressionProcessedHistory = New-Object System.Collections.ArrayList
$global:alQuantizedIndex = $null
$global:alCounterData = $null #// 2 dimensional array
$global:IsAnalysisIntervalCalculated = $False
#Added to support Globalisation by JonnyG 2010-09-08
$global:BeginTime = $null
$global:EndTime = $null

#// For use to determine the original counter list.
$global:sFirstCounterLogFilePath = ''
$global:sOriginalCounterListFilePath = ''

#// HTML Report properties
$global:htHtmlReport = @{"OutputDirectoryPath" = "";"ResourceDirectoryObject" = "";"ReportFileObject" = "";"ReportFilePath" = "";"ResourceDirectoryPath" = ""}

$global:CounterLog = @{"FilePath" = "";"DeleteWhenDone" = $false}
$global:sPerfLogFilePath = ""
$global:sPerfLogTimeZone = ""
$global:ImportedCsvCounterLog = ""
$global:iChartControlLoadTries = 0

#// For Alerts
[boolean] $global:IsMinEvaulated = $False
[boolean] $global:IsAvgEvaulated = $False
[boolean] $global:IsMaxEvaulated = $False
[boolean] $global:IsTrendEvaulated = $False

trap
{
	If ($_.InvocationInfo.Line.Contains("System.Windows.Forms.DataVisualization"))
	{
		$global:iChartControlLoadTries = $global:iChartControlLoadTries + 1
		If ($global:iChartControlLoadTries -gt 1)
		{
			Write-Warning "Unable to load the Microsoft Chart Controls for Microsoft .NET Framework 3.5. These controls used to create graphical charts. Please install these free controls from http://www.microsoft.com/downloads/details.aspx?FamilyID=130f7986-bf49-4fe5-9ca8-910ae6ea442c&DisplayLang=en"
			Write-Warning "If you have installed the Microsoft Chart Controls, then ensure that the assembly is located in one of the default directories `"C:\Program Files (x86)\Microsoft Chart Controls\Assemblies\System.Windows.Forms.DataVisualization.dll`" or `"C:\Program Files\Microsoft Chart Controls\Assemblies\System.Windows.Forms.DataVisualization.dll`""
            Break;
		}
		Else
		{
			Continue;
		}
	}
	Else
	{
		Write-Warning "Please post errors or problems with this tool to the PAL web site located at http://www.codeplex.com/PAL with the following error message and a brief description of what you were trying to do. Thank you."
		Break;	
	}
}

#// This script requires the Microsoft Chart Controls for Microsoft .NET Framework 3.5 to be installed.
[Void] [Reflection.Assembly]::LoadFile("C:\Program Files (x86)\Microsoft Chart Controls\Assemblies\System.Windows.Forms.DataVisualization.dll")
[Void] [Reflection.Assembly]::LoadFile("C:\Program Files\Microsoft Chart Controls\Assemblies\System.Windows.Forms.DataVisualization.dll")


#/////////////////////////////////
#// Functions
#/////////////////////////////////

Function Test-FileExists
{
    param($Path)
    If ($Path -eq '')
    {
        Return $false
    }
    Else
    {
        Return Test-Path -Path $Path
    }
}

Function IsNumeric
{
    param($Value)
    [double]$number = 0
    $result = [double]::TryParse($Value, [REF]$number)
    $result
}

Function AddBufferToMaxChartValue
{
    param($Value)
    #// The buffer is too much for the standard thresholds.
    #If ($Value -is [double])
    #{
    #    [string]$sValue = $Value
    #    $aValues = $sValue.Split('.')
    #    $sValue = "$($aValues[0])" + '.999'
    #    [double]$Value = $sValue
    #}
    #Else
    #{
    #    $Value = $Value + 0.999
    #}
    Return $Value
}

Function Test-Property 
{
    #// Function provided by Jeffrey Snover
    #// Tests if a property is a memory of an object.
	param ([Parameter(Position=0,Mandatory=1)]$InputObject,[Parameter(Position=1,Mandatory=1)]$Name)
	[Bool](Get-Member -InputObject $InputObject -Name $Name -MemberType *Property)
}

Function IsObject
{
    param([Parameter(Position=0,Mandatory=1)]$InputObject)
	[Bool](Get-Member -InputObject $InputObject)
}

Function SetXmlChartIsThresholdAddedAttribute
{
    param($XmlChart)
    [Int] $iNumOfSeries = 0
    
    ForEach ($XmlChartSeries in $XmlChart.SelectNodes("./SERIES"))
    {
        $iNumOfSeries++
    }
    
    If ($iNumOfSeries -eq 0)
    {
        $XmlChart.SetAttribute("ISTHRESHOLDSADDED", "False")
    }
    Else
    {
        $XmlChart.SetAttribute("ISTHRESHOLDSADDED", "True")
    }
}

Function ConvertTextTrueFalse($str)
{
	If ($str -eq $null)
	{Return $False}
    If ($str -is [System.String])
    {
        $strLower = $str.ToLower()
        If ($strLower -eq 'true')
        {
            Return $True
        }
    	Else 
        {
            Return $False
        }
    }
    Else
    {
        If ($str -is [System.Boolean])
        {
            Return $str
        }
        Else
        {
            Return $False
        }
    }
}

Function Test-XmlBoolAttribute
{
    param ([Parameter(Position=0,Mandatory=1)]$InputObject,[Parameter(Position=1,Mandatory=1)]$Name)
    If ($(Test-property -InputObject $InputObject -Name $Name) -eq $True)
    {
        If ($(ConvertTextTrueFalse $InputObject.$Name) -eq $True)
        {
            $True        
        }
        Else
        {
            $False
        }
    }
    Else
    {
        $False
    }
}

Function MakeNumeric
{
	param($Values)
	#// Make an array all numeric
    $alNewArray = New-Object System.Collections.ArrayList
    If (($Values -is [System.Collections.ArrayList]) -or ($Values -is [Array]))
    {    	
    	For ($i=0;$i -lt $Values.Count;$i++)
    	{
    		If ($(IsNumeric -Value $Values[$i]) -eq $True)
    		{
    			[Void] $alNewArray.Add([System.Double]$Values[$i])
    		}
    	}    	
    }
    Else
    {
        [Void] $alNewArray.Add([System.Double]$Values)
    }
    $alNewArray
}

Function DeleteDirectory
{
    param($DirectoryPath)
    
	Remove-Item -Path $DirectoryPath -Force
}

Function DeleteFile
{
    param($FilePath)
    
	Remove-Item -Path $FilePath -Force
}

Function CreateDirectory
{
    param($DirectoryPath,$DirectoryName)
        
	If ($DirectoryName -eq $null)
	{
		If ((Test-Path -Path $DirectoryPath) -eq $False)
		{
			Write-Host "Creating directory `"$DirectoryPath`""
			Return New-Item -Path $DirectoryPath -type directory	
		}
	}
	Else
	{
		If ((Test-Path -Path $DirectoryPath\$DirectoryName) -eq $False)
		{
			Write-Host "Creating directory `"$DirectoryPath\$DirectoryName`""
			Return New-Item -Path $DirectoryPath -Name $DirectoryName -type directory	
		}
	}
}

Function CreateFile
{
    param($FilePath)
    
	If ((Test-Path -Path $FilePath) -eq $False)
	{
		Write-Host "Creating file `"$FilePath`""
		Return New-Item -Path $FilePath -type file		
	}
}

Function DeleteDirectory
{
    param($DirectoryPath)
    # Mike Ferencak recommnded the Recurse parameter.
	Remove-Item -Path $DirectoryPath -Force -Recurse
}

Function DeleteFile
{
    param($FilePath)
    # Mike Ferencak recommnded the Recurse parameter.
	Remove-Item -Path $FilePath -Force -Recurse
}

Function StartDebugLogFile
{
    param($sDirectoryPath, $iAttempt)
	If ($iAttempt -eq 0) 
	{$sFilePath = $sDirectoryPath + "\PAL.log"}
	Else
	{$sFilePath = $sDirectoryPath + "\PAL" + $iAttempt + ".log"}
	$erroractionpreference = "SilentlyContinue"
	Trap
	{
		#"Error occurred! Trying again..."
		$iAttempt++
		StartDebugLogFile $sDirectoryPath $iAttempt		
	}
	# Kirk edit:
	if (($Host.Name -eq 'ConsoleHost') -or
	    (Get-Command -Name Start-Transcript | Where-Object {$_.PSSnapin -ne 'Microsoft.PowerShell.Host'})) {
	# End Kirk edit
		Start-Transcript -Path $sFilePath -Force
	# Kirk edit:
	} elseif ($Host.Name -eq 'PowerGUIScriptEditorHost') {
		Write-Warning 'You must install the Transcription add-on for the PowerGUI Script Editor if you want to use transcription.'
	} else {
		Write-Warning 'This host does not support transcription.'
	}
	# End Kirk edit
	$erroractionpreference = "Continue"
}

Function StopDebugLogFile()
{
	# Kirk edit:
	if (($Host.Name -eq 'ConsoleHost') -or
	    (Get-Command -Name Stop-Transcript | Where-Object {$_.PSSnapin -ne 'Microsoft.PowerShell.Host'})) {
	# End Kirk edit
	    Stop-Transcript
	# Kirk edit:
	}
	# End Kirk edit
}

Function Get-UserTempDirectory()
{
	$DirectoryPath = Get-ChildItem env:temp	
	Return $DirectoryPath.Value
}

Function Get-GUID()
{
	Return "{" + [System.GUID]::NewGUID() + "}"
}

Function Get-LocalizedDecimalSeparator()
{
	Return (get-culture).numberformat.NumberDecimalSeparator
}

Function Get-LocalizedThousandsSeparator()
{
	Return (get-culture).numberformat.NumberGroupSeparator
}

Function InitializeGlobalVariables()
{
	[System.Globalization.CultureInfo] $global:htScript["Culture"] = New-Object System.Globalization.CultureInfo($(Get-Culture).Name)
	$global:htScript["BeginTime"] = Get-Date
	$global:htScript["ScriptFileObject"] = Get-Item -Path $MyInvocation.ScriptName # .\PAL.ps1
	$global:htScript["ScriptFileLastModified"] = $global:htScript["ScriptFileObject"].LastWriteTime
    $Legal = 'The information and actions by this tool is provided "as is" and is intended for information purposes only. The authors and contributors of this tool take no responsibility for damages or losses incurred by use of this tool.'
	$global:htScript["MainHeader"] = "PAL " + $global:htScript["Version"] + " (http://www.codeplex.com/PAL)`nWritten by: Clint Huffman (clinth@microsoft.com) and other contributors.`nLast Modified: " + $global:htScript["ScriptFileLastModified"] + "`n$Legal`n"
	$global:htScript["SessionGuid"] = Get-GUID
	$global:htScript["UserTempDirectory"] = Get-UserTempDirectory
	$global:htScript["DebugLog"] = $global:htScript["UserTempDirectory"] + "\" + "PAL.log"
	$global:htScript["LocalizedDecimal"] = Get-LocalizedDecimalSeparator	
	$global:htScript["LocalizedThousandsSeparator"] = Get-LocalizedThousandsSeparator	
}

Function ShowMainHeader()
{
	Write-Host $global:htScript["MainHeader"]
}

Function ExtractStringArgument
{
    param($sText,$NamedArg)
    
	$EndOfNamedArg = $NamedArg.Length
	Return $sText.SubString($EndOfNamedArg)
}

Function ConvertToTwentyFourHourTime
{
    param($DateTimeAsString)
	#// Converts a datetime string to 24 hour format.
	$DateTimeAsString = [datetime] $DateTimeAsString
	$TwentyFourHourLocalizedDateTimePattern = $global:sDateTimePattern -replace 'h','H'
	$TwentyFourHourLocalizedDateTimePattern = $TwentyFourHourLocalizedDateTimePattern -replace 't',''
    $TwentyFourHourLocalizedDateTimePattern = $TwentyFourHourLocalizedDateTimePattern.Trim(' ')
	$result = Get-Date $([datetime]$DateTimeAsString) -format $TwentyFourHourLocalizedDateTimePattern
	$result
}    

Function ProcessArgs
{
    param([System.Object[]] $MyArgs)
    
    $Syntax = "SYNTAX"
    
    If ($MyArgs.Count -ne 0)
    {
        If ($MyArgs[0].contains("?"))
        {
            $Syntax
            Exit
        }    
        If ($MyArgs[0].contains("-") -eq $False)
        {
        	for ($i=0;$i -lt $MyArgs.Length;$i++)
        	{

        		If ($MyArgs[$i].contains("/LOG:"))
        		{
        			$global:Log = ExtractStringArgument $MyArgs[$i] "/LOG:"
        		}
        		If ($MyArgs[$i].contains("/THRESHOLDFILE:"))
        		{
        			$global:ThresholdFile = ExtractStringArgument $MyArgs[$i] "/THRESHOLDFILE:"
        		}
        		If ($MyArgs[$i].contains("/INTERVAL:"))
        		{
        			$global:Interval = ExtractStringArgument $MyArgs[$i] "/INTERVAL:"
        		}
        		If ($MyArgs[$i].contains("/ISOUTPUTHTML:"))
        		{
        			$global:IsOutputHtml = ExtractStringArgument $MyArgs[$i] "/ISOUTPUTHTML:"
        		}
        		If ($MyArgs[$i].contains("/ISOUTPUTXML:"))
        		{
        			$global:IsOutputXml = ExtractStringArgument $MyArgs[$i] "/ISOUTPUTXML:"
        		}
        		If ($MyArgs[$i].contains("/HTMLOUTPUTFILENAME:"))
        		{
        			$global:HtmlOutputFileName = ExtractStringArgument $MyArgs[$i] "/HTMLOUTPUTFILENAME:"
        		}
        		If ($MyArgs[$i].contains("/XMLOUTPUTFILENAME:"))
        		{
        			$global:XmlOutputFileName = ExtractStringArgument $MyArgs[$i] "/XMLOUTPUTFILENAME:"
        		}                
        		If ($MyArgs[$i].contains("/OUTPUTDIR:"))
        		{
        			$global:OutputDir = ExtractStringArgument $MyArgs[$i] "/OUTPUTDIR:"
        		}
        		If ($MyArgs[$i].contains("/BEGINTIME:"))
        		{
        			$global:BeginTime = ExtractStringArgument $MyArgs[$i] "/BEGINTIME:"
        		}
        		If ($MyArgs[$i].contains("/ENDTIME:"))
        		{
        			$global:EndTime = ExtractStringArgument $MyArgs[$i] "/ENDTIME:"
        		}                
        	}        
        }
        Else
        {
            #// Add the extra arguments into a hash table
            #Write-host $MyArgs.Count
            For ($i=0;$i -lt $MyArgs.Count;$i++)
            {
                If ($MyArgs[$i].SubString(0,1) -eq '-')
                {
                    $sName = $MyArgs[$i].SubString(1);$i++;$sValue = $MyArgs[$i]
                    #// $htQuestionVariables is a global variable
                    If (($sValue -eq 'True') -or ($sValue -eq 'False'))
                    {
                        $IsTrueOrFalse = ConvertTextTrueFalse $sValue
                        [void] $htQuestionVariables.Add($sName,$sValue)
                    }
                    Else
                    {
                        [void] $htQuestionVariables.Add($sName,$sValue)                    
                    }
                }
            }
        }
    }
	# Kirk edit
	If (-not $Log)
	# End Kirk edit
	{
		Write-Warning "Missing the Log parameter."
		Write-Host ""
		$Syntax
		Break Main
	}

	# Kirk edit
	If (-not $ThresholdFile)
	# End Kirk edit
	{
		Write-Warning "Missing the ThresholdFile parameter."
		Write-Host ""
		$Syntax
		Break Main
	}

	# Kirk edit
	If (-not $Interval)
	# End Kirk edit
	{
		Write-Warning "Missing the Interval parameter."
		Write-Host ""
		$Syntax
		Break Main
	}
	# Kirk edit
	#Else
	#{
	# End Kirk edit
    If ($Interval -is [System.String])
    {
		If ($($Interval.IndexOf("AUTO", [StringComparison]::OrdinalIgnoreCase)) -gt 0)
		{
			$Interval = 'AUTO'
		}
    }
	# Kirk edit
	#}
	# End Kirk edit
			
	# Kirk edit
	If (-not $HtmlOutputFileName)
	# End Kirk edit
	{
		Write-Warning "Missing the HtmlOutputFileName parameter."
		Write-Host ""
		$Syntax
		Break Main
	}	
	# Kirk edit
	If (-not $OutputDir)
	# End Kirk edit
	{
		Write-Warning "Missing the OutputDir parameter."
		Write-Host ""
		$Syntax
		Break Main
	}		
	
    #// Is counter log file or database?
    If ($Log.IndexOf('database=',[StringComparison]::OrdinalIgnoreCase) -gt 0) 
    {
        $global:IsCounterLogFile = $False
        $global:IsDatabaseConnectionString = $True
        $global:sDbConnectionString = $Log
    }
    Else
    {
        $global:IsCounterLogFile = $True
    }

	#// Check if the files exist
    If ($global:IsCounterLogFile -eq $True)
    {
    	If ($Log.Contains(';'))
    	{
    		$aArgPerfmonLogFilePath = $Log.Split(";")
    		For ($sFile = 0;$sFile -lt $aArgPerfmonLogFilePath.length;$sFile++)
    		{
    			If ((Test-Path $aArgPerfmonLogFilePath[$sFile]) -eq $False)
    			{
    				# Kirk edit
    				Write-Warning "[ProcessArgs] The file ""$($aArgPerfmonLogFilePath[$sFile])"" does not exist."
    				# End Kirk edit
    				Break Main
    			}
    		}
    	}
    	Else
    	{
    		If ((Test-Path $Log) -eq $False) 
    		{
    			# Kirk edit
    			Write-Warning "[ProcessArgs] The file ""$Log"" does not exist."
    			# End Kirk edit
    			Break Main
    		}
    		
    	}

    	If ((Test-Path $ThresholdFile) -eq $False) 
    	{
    		# Kirk edit
    		Write-Warning "[ProcessArgs] The file ""$ThresholdFile"" does not exist."
    		# End Kirk edit
    		Break Main
    	}
    }
    
    If ($BeginTime -ne $null)
    {
        #//$global:BeginTime = ([datetime]::parseexact($BeginTime,$global:sDateTimePattern,$null)).tostring("MM/dd/yyyy HH:mm:ss")    
		#$global:BeginTime = ([datetime]::parseexact($BeginTime,$global:sDateTimePattern,$null)).tostring("MM/dd/yyyy HH:mm:ss")
        ## Commented as don't think it's need if we assume local timezone pattern 
		## is used when passing in begin and end time 
		## Probably means we can remove this function ConvertToTwentyFourHourTime JonnyG 2010-06-11
		#$global:BeginTime = ConvertToTwentyFourHourTime -DateTimeAsString $BeginTime
        $global:BeginTime = $BeginTime
    }
    
    If ($EndTime -ne $null)
    {
        ## Commented as don't think it's need if we assume local timezone pattern
		## is used when passing in begin and end time JonnyG 2010-06-11
		#$global:EndTime = ConvertToTwentyFourHourTime -DateTimeAsString $EndTime
		#$global:EndTime = ([datetime]::parseexact($EndTime,$global:sDateTimePattern,$null)).tostring("MM/dd/yyyy HH:mm:ss")
        $global:EndTime = $EndTime
    }    

    "SCRIPT ARGUMENTS:"
    "-Log $Log"
    "-ThresholdFile $ThresholdFile"
    "-Interval $Interval"
    "-OutputDir $OutputDir"
    "-IsOutputHtml $IsOutputHtml"    
    "-HtmlOutputFileName $HtmlOutputFileName"
    "-AllCounterStats $AllCounterStats"
    "-IsOutputXml $IsOutputXml"
    "-XmlOutputFileName $XmlOutputFileName"
    "-BeginTime $BeginTime"
    "-EndTime $EndTime"
    ""
    Write-Host ""    
    
}

Function CreateSessionWorkingDirectory()
{	
	Write-Host "Creating session working directory..."
	[string] $global:htScript["SessionWorkingDirectory"] = CreateDirectory $global:htScript["UserTempDirectory"] $global:htScript["SessionGuid"]
}

Function CheckTheFileExtension
{
    param($FilePath, $ThreeLetterExtension)
    
	$ExtractedExtension = $FilePath.SubString($FilePath.Length-3)
	If ($ExtractedExtension.ToLower() -eq $ThreeLetterExtension) {Return $True}
	Else {Return $False}
}

Function IsSamplesInPerfmonLog
{
    param($RelogOutput)
    $u = $RelogOutput.GetUpperBound(0)

    :OutputOfRelogLoop For ($i=$u;$i -gt 0;$i = $i - 1)
    {
        If ($($RelogOutput[$i].Contains('----------------')) -eq $True)
        {
            $a = $i + 5
            $SamplesLine = $RelogOutput[$a]
            break OutputOfRelogLoop;
        }
    }
    $aSamples = $SamplesLine.Split(' ')
    $NumOfSamples = $aSamples[$aSamples.GetUpperBound(0)]
    If ($NumOfSamples -gt 0)
    {$True}
    Else
    {$False}    
}

Function CheckIsSingleCsvFile
{
    param($sPerfmonLogPaths)
    $NumberOfCsvFiles = 0
    If ($sPerfmonLogPaths.Contains(';'))
    {
        $aPerfmonLogPaths = $sPerfmonLogPaths.Split(';')
        For ($f=0;$f -lt $aPerfmonLogPaths.length;$f++)
        {
            If ($(CheckTheFileExtension -FilePath $aPerfmonLogPaths[$f] -ThreeLetterExtension 'csv') -eq $True)
            {
                Write-Warning 'PAL is unable to merge CSV perfmon log files. Run PAL again, but analyze only one perfmon log at a time. PAL uses Relog.exe (part of the operating system) to merge the log files together.'
                Break Main;
            }
        }
        Return $False
    }
    Else
    {
        If (CheckTheFileExtension $sPerfmonLogPaths "csv")
        {
            Return $True
        }
        Else
        {
            Return $False
        }
    }
}

Function GetNumberOfSamplesFromRelogOutput
{
    param($sRelogOutput)
    [System.String] $sLine = ''
    [System.Int32] $u = 0
    [System.Int32] $iResult = 0
    ForEach ($sLine in $sRelogOutput)
    {
        If ($sLine.IndexOf('Samples:') -ge 0)
        {
            $aLine = $sLine.Split(' ')
            $u = $aLine.GetUpperBound(0)
            $iResult = $aLine[$u]
            Return $iResult
        }
    }
}

Function MergeConvertFilterPerfmonLogs
{
    param($sPerfmonLogPaths, $BeginTime=$null, $EndTime=$null)
    $sCommand = ''
    $RelogOutput = ''
    $IsSingleCsvFile = CheckIsSingleCsvFile -sPerfmonLogPaths $sPerfmonLogPaths
	$global:sPerfLogFilePath = $global:htScript["SessionWorkingDirectory"] + "\_FilteredPerfmonLog.csv"
	If ($IsSingleCsvFile -eq $False)
	{
		$sTemp = ''
		If ($sPerfmonLogPaths.Contains(';'))
		{
			$aPerfmonLogPaths = $sPerfmonLogPaths.Split(';')
            $global:sFirstCounterLogFilePath = $aPerfmonLogPaths[0]
			For ($f=0;$f -lt $aPerfmonLogPaths.length;$f++)
			{
				$sTemp = $sTemp + " " + "`"" + $aPerfmonLogPaths[$f] + "`""
			}
			$sTemp = $sTemp.Trim()
            If ($AllCounterStats -eq $True)
            {
                $sCommand = $('relog.exe ' + "$sTemp" + ' -f csv -o ' + "`"$global:sPerfLogFilePath`"")
            }
            Else
            {
                $sCommand = $('relog.exe ' + "$sTemp" + ' -cf ' + "`"$global:sCounterListFilterFilePath`"" + ' -f csv -o ' + "`"$global:sPerfLogFilePath`"")
            }
		}
		Else
		{
            $global:sFirstCounterLogFilePath = $sPerfmonLogPaths
            If ($AllCounterStats -eq $True)
            {
                $sCommand = $('relog.exe ' + "`"$sPerfmonLogPaths`"" + ' -f csv -o ' + "`"$global:sPerfLogFilePath`"" + ' -y')
            }
            Else
            {
                $sCommand = $('relog.exe ' + "`"$sPerfmonLogPaths`"" + ' -cf ' + "`"$global:sCounterListFilterFilePath`"" + ' -f csv -o ' + "`"$global:sPerfLogFilePath`"" + ' -y')
            }
            $global:CounterLog["DeleteWhenDone"] = $True
		}
	}
	Else
	{
        #// Just use the original perfmon log.
        $global:CounterLog["DeleteWhenDone"] = $false
        $global:sPerfLogFilePath = $sPerfmonLogPaths
        $global:sFirstCounterLogFilePath = $sPerfmonLogPaths
	}
    
    If (($BeginTime -ne $null) -and ($EndTime -ne $null))
    {
        $sCommand = "$sCommand" + ' -b ' + "`"$BeginTime`"" + ' -e ' + "`"$EndTime`""
    }
    
    If ($IsSingleCsvFile -eq $False)
    {
        Write-Host $sCommand
        $RelogOutput = Invoke-Expression -Command $sCommand
        #// Remove the extra blank lines.
        $RelogOutput | ForEach-Object {If ($_ -ne ''){"$_"}}
    }
    
    $sRelogOutputAsSingleString = [string]::join("", $RelogOutput)
    If ($sRelogOutputAsSingleString.contains('No data to return.') -eq $True)
    {
        Write-Error "Relog.exe failed to process the log. This commonly occurs when a BLG file from a Windows Vista or newer operating system is attempting to be analyze on Windows XP or Windows Server 2003, or due to log corruption. If you see this message on Windows XP or Server 2003, then try analyzing the log on Windows Vista/Server 2008 or later. Review the results above this line. If relog.exe continues to fail, then try running Relog.exe manually and/or contact Microsoft Customer Support Servers for support on Relog.exe only. PAL is not supported by Microsoft."
        Break Main
    }
    
	$NewLogExists = Test-Path -Path $global:sPerfLogFilePath
	If ($NewLogExists -eq $False)
	{	
		Write-Error $("[MergeConvertFilterPerfmonLogs] ERROR: Unable to find the converted log file:" + "`"$global:sPerfLogFilePath`"")
		Write-Error "Relog.exe failed to process the log. Review the results above this line. If relog.exe continues to fail, then try running Relog.exe manually and/or contact Microsoft Customer Support Servers for support on Relog.exe only. PAL is not supported by Microsoft."
		Break Main
	}
    If (($IsSingleCsvFile -eq $False) -and ($RelogOutput -ne $null))
    {
        If ($(IsSamplesInPerfmonLog -RelogOutput $RelogOutput) -eq $False)
        {
    		Write-Error $("[MergeConvertFilterPerfmonLogs] ERROR: Unable to use the log file(s):" + "`"$global:sPerfLogFilePath`"" + ' -y')
    		Write-Error "The counters in the log(s) do not contain any useable samples."
    		Break Main
        }
    }
    If ($RelogOutput -ne $null)
    {
        $NumberOfSamples = GetNumberOfSamplesFromRelogOutput -sRelogOutput $RelogOutput
        If ($NumberOfSamples -is [System.Int32])
        {
            If ($NumberOfSamples -lt 10)
            {
                Write-Error $("ERROR: Not enough samples in the counter log to properly process. Create another performance counter log with more samples in it and try again. Number of samples is: " + "$NumberOfSamples")
                Break Main
            }
        }
    }
}

Function Get-DateTimeStamp()
{
    [string] $global:htScript["SessionDateTimeStamp"] = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
}

Function GetServerAndDatabaseName()
{
    #// 'Server=SOLRING\SQLEXPRESS;Database=PerfCounterLogs;Integrated Security=true'
	$sString = $Log    
	If ($sString.Contains(';'))
	{
		$aStrings = $sString.Split(';')
	}
    Else
    {
        $aStrings = @($sString)
    }
    
    ForEach ($sItem in $aStrings)
    {
        #// Get database server name
        If ($sItem.IndexOf('database=',[StringComparison]::OrdinalIgnoreCase) -ge 0)
        {
            $aSubStrings = $sItem.Split('=')
            $global:sDatabaseName = $aSubStrings[1]
        }
        If ($sItem.IndexOf('server=',[StringComparison]::OrdinalIgnoreCase) -ge 0)
        {
            $aSubStrings = $sItem.Split('=')
            $global:sDatabaseServerName = $aSubStrings[1]
        }
        If ($sItem.IndexOf('logset=',[StringComparison]::OrdinalIgnoreCase) -ge 0)
        {
            $aSubStrings = $sItem.Split('=')
            $global:sDatabaseLogSet = $aSubStrings[1]
        }        
    }
    $sOutput = "$global:sDatabaseServerName" + '_' + "$global:sDatabaseName" + '_' + "$global:sDatabaseLogSet"
	Return $sOutput
}

Function GetFirstPerfmonLogFileName()
{
	$sString = $Log
	If ($sString.Contains(";"))
	{
		$aStrings = $sString.Split(";")
		$sString = $aStrings[0]
	}
	If ($sString.Contains("\"))
	{
		$aStrings = $sString.Split("\")
		$sString = $aStrings[$aStrings.GetUpperBound(0)]
	}
	# Remove the file extension
	$sString = $sString.SubString(0,$sString.Length - 4)
	Return $sString
}

Function ConvertStringToFileName
{
    param($sString)
    
	$sResult = $sString
	$sResult = $sResult -replace "\\", "_"
	$sResult = $sResult -replace "/", "_"
	$sResult = $sResult -replace " ", "_"
	$sResult = $sResult -replace "\?", ""
	$sResult = $sResult -replace ":", ""
	$sResult = $sResult -replace ">", ""
	$sResult = $sResult -replace "<", ""
	$sResult = $sResult -replace "\(", "_"
	$sResult = $sResult -replace "\)", "_"
	$sResult = $sResult -replace "\*", ""
	$sResult = $sResult -replace "\|", "_"
	$sResult = $sResult -replace "{", ""
	$sResult = $sResult -replace "}", ""
    $sResult = $sResult -replace "#", ""
	Return $sResult
}

Function AddBackSlashToEndIfNotThereAlready
{
    param($sString)
    
	$LastChar = $sString.SubString($sString.Length-1)
	If ($LastChar -ne "\")
	{
		$sString = $sString + "\"
	}
	Return $sString
}

Function ResolvePALStringVariablesForPALArguments()
{
	$UsersMyDocumentsFolder = [environment]::GetFolderPath("MyDocuments")
	#$global:htHtmlReport = @{"OutputDirectoryPath" = "";"ResourceDirectoryObject" = "";"ReportFileObject" = "";"ReportFilePath" = "";"ResourceDirectoryPath" = ""}
    $OutputDir = AddBackSlashToEndIfNotThereAlready $OutputDir
    $sResolvedOutputDir = $OutputDir

	$sDateTimeStampForFile = $global:htScript["SessionDateTimeStamp"] -replace(" ", "_")
	$sDateTimeStampForFile = $sDateTimeStampForFile -replace(":", "-")
    
    If ($global:IsCounterLogFile -eq $True)
    {
    	$sLogFileName = GetFirstPerfmonLogFileName
    }
    Else
    {
    	$sLogFileName = GetServerAndDatabaseName
    }
    $sLogFileName = ConvertStringToFileName $sLogFileName
	
	$sSessionGuidForFilePath = $global:htScript["SessionGuid"] -replace("{","")
	$sSessionGuidForFilePath = $sSessionGuidForFilePath -replace("}","")
	
	$sResolvedOutputDir = $sResolvedOutputDir -replace("\[DateTimeStamp\]",$sDateTimeStampForFile)
	$sResolvedOutputDir = $sResolvedOutputDir -replace("\[LogFileName\]",$sLogFileName)
    $sResolvedOutputDir = $sResolvedOutputDir -replace("\[GUID\]",$sSessionGuidForFilePath)
	$sResolvedOutputDir = $sResolvedOutputDir -replace("\[My Documents\]",$UsersMyDocumentsFolder)
	$global:htHtmlReport["OutputDirectoryPath"] = $sResolvedOutputDir
	    
	$sHtmlReportFile = $HtmlOutputFileName -replace("\[DateTimeStamp\]",$sDateTimeStampForFile)
	$sHtmlReportFile =  $sHtmlReportFile -replace("\[LogFileName\]",$sLogFileName)
    $sHtmlReportFile =  $sHtmlReportFile -replace("\[GUID\]",$sSessionGuidForFilePath)
	$global:htHtmlReport["ReportFilePath"] = $global:htHtmlReport["OutputDirectoryPath"] + $sHtmlReportFile
    
    If ($IsOutputXml -eq $True)
    {
    	$sXmlReportFile = $XmlOutputFileName -replace("\[DateTimeStamp\]",$sDateTimeStampForFile)
    	$sXmlReportFile =  $sXmlReportFile -replace("\[LogFileName\]",$sLogFileName)
        $sXmlReportFile =  $sXmlReportFile -replace("\[GUID\]",$sSessionGuidForFilePath)
    	$global:XmlReportFilePath = $sResolvedOutputDir + $sXmlReportFile
    }	
	
	$sDirectoryName = $sHtmlReportFile.SubString(0,$sHtmlReportFile.Length - 4)
	$sDirectoryName = ConvertStringToFileName $sDirectoryName
	$global:htHtmlReport["ResourceDirectoryPath"] = $global:htHtmlReport["OutputDirectoryPath"]
	$global:htHtmlReport["ResourceDirectoryPath"] = $global:htHtmlReport["ResourceDirectoryPath"] + $sDirectoryName + "\"	
}

Function CreateFileSystemResources()
{
	CreateDirectory $global:htHtmlReport["OutputDirectoryPath"]	
	$global:htHtmlReport["ReportFileObject"] = CreateFile $global:htHtmlReport["ReportFilePath"]
	$global:htHtmlReport["ResourceDirectoryObject"] = CreateDirectory $global:htHtmlReport["ResourceDirectoryPath"]
    #// Copy-Item ".\TableSort.js" $global:htHtmlReport["ResourceDirectoryPath"]
}

Function CheckTheFileExtension
{
    param($FilePath, $ThreeLetterExtension)
    
	$ExtractedExtension = $FilePath.SubString($FilePath.Length-3)
	If ($ExtractedExtension.ToLower() -eq $ThreeLetterExtension) {Return $True}
	Else {Return $False}
}

Function CalculatePercentage
{
    param($Number,$Total)
    If ($Total -eq 0)
    {
        Return 100
    }
    $Result = ($Number * 100) / $Total
    $Result
}

Function GetCounterListFromDatabase
{    
    #// Query dbo.DisplayToID for the data collector GUID.
    #// Query dbo.CounterData for unique CounterID WHERE GUID
    #// Query dbo.CounterDetails for the ID to counterpath lookup.
    #// create a counterpath to ID and ID to counterpath lookup functions.
    
    $sDatabaseConnectionString = 'Server=' + "$global:sDatabaseServerName" + ';Database=' + "$global:sDatabaseName" + ';Integrated Security=true'
    $oSqlConnection = New-Object System.Data.SqlClient.SqlConnection ($sDatabaseConnectionString)
    $da = New-Object System.Data.SqlClient.SqlDataAdapter
    $ds = New-Object System.Data.DataSet
    
    $sQuery = 'SELECT * FROM [PerfCounterLogs].[dbo].[DisplayToID] WHERE DisplayString = ' + "'" + "$global:sDatabaseLogSet" + "'"
    $oCommand = New-Object System.Data.SqlClient.Sqlcommand ($sQuery, $oSqlConnection)
    $da.SelectCommand = $oCommand
    [Void] $da.Fill($ds, "PerfData")
    $sGuidOfLogSet = ''
    foreach ($row in $ds.tables["PerfData"].rows)
    {
        $sGuidOfLogSet = $row.('GUID')
    }    
    
    $sQuery = 'SELECT DISTINCT [CounterID] FROM [PerfCounterLogs].[dbo].[CounterData] WHERE GUID = ' + "'" + "$sGuidOfLogSet" + "'"
    $oCommand = New-Object System.Data.SqlClient.Sqlcommand ($sQuery, $oSqlConnection)
    $da.SelectCommand = $oCommand
    [Void] $da.Fill($ds, "PerfData")
    $aCounterIds = @()
    foreach ($row in $ds.tables["PerfData"].rows)
    {
        $aCounterIds += $row.('CounterID')
    }
        
    $aCounterList = @()
    foreach ($iCounterId in $aCounterIds)
    {
        If ($($iCounterId.GetType().FullName) -ne [System.DBNull])
        {
            $sQuery = "SELECT * FROM [PerfCounterLogs].[dbo].[CounterDetails] WHERE CounterID = $iCounterId"
            $oCommand = New-Object System.Data.SqlClient.Sqlcommand ($sQuery, $oSqlConnection)
            $da.SelectCommand = $oCommand
            [Void] $da.Fill($ds, "PerfData")
            foreach ($row in $ds.tables["PerfData"].rows)
            {
                If ($($row.('InstanceName')).GetType().FullName -eq [System.DBNull])
                {
                    $sCounterPath = "$($row.('MachineName'))" + '\' + "$($row.('ObjectName'))" + '\' + "$($row.('CounterName'))"
                }
                Else
                {
                    If ($($row.('InstanceIndex')).GetType().FullName -eq [System.DBNull])
                    {
                        $sCounterPath = "$($row.('MachineName'))" + '\' + "$($row.('ObjectName'))" + '(' + "$($row.('InstanceName'))" + ')\' + "$($row.('CounterName'))"
                    }
                    Else
                    {
                        $sCounterPath = "$($row.('MachineName'))" + '\' + "$($row.('ObjectName'))" + '(' + "$($row.('InstanceName'))" + "$($row.('InstanceIndex'))" + ')\' + "$($row.('CounterName'))"
                    }
                }
            }
            $aCounterList += $sCounterPath
        }
    }
    Return $aCounterList
}

Function GetCounterListFromCsvAsText
{
    param($CsvFilePath)
	$oCSVFile = Get-Content $CsvFilePath
    #// Some counters have commas in their instance names, so doing a split with more characters to make it more reliable.
    If ($oCSVFile[0] -is [System.Char])
    {
        Write-Error "[GetCounterListFromCsvAsText]: No usable data found in the log."
        Break Main
    }
    $aRawCounterList = $oCSVFile[0].Trim('"') -split '","'
    $u = $aRawCounterList.GetUpperBound(0)
	$aCounterList = $aRawCounterList[1..$u]
	Return $aCounterList
}

Function ConvertDateTimeArrayForCharting
{
    param($arTime)
    
	For ($i=0;$i -lt $arTime.Length;$i++)
	{
		$a = [datetime] $arTime[$i]
		$arTime[$i] = [string] $a.Month + "/" + $a.Day + " " + $a.Hour + ":" + $a.Minute
	}
}

Function RemoveCounterComputer
{
    param($sCounterPath)
    
	#'\\IDCWEB1\Processor(_Total)\% Processor Time"
	[string] $sString = ""
	#// Remove the double backslash if exists
	If ($sCounterPath.substring(0,2) -eq "\\")
	{		
		$sComputer = $sCounterPath.substring(2)
		$iLocThirdBackSlash = $sComputer.IndexOf("\")
		$sString = $sComputer.substring($iLocThirdBackSlash)
	}
	Else
	{
		$sString = $sCounterPath
	}		
		Return $sString	
}

Function RemoveCounterNameAndComputerName
{
    param($sCounterPath)
    
    If ($sCounterPath.substring(0,2) -eq "\\")
    {
    	$sCounterObject = RemoveCounterComputer $sCounterPath
    }
    Else
    {
        $sCounterObject = $sCounterPath
    }
	# \Paging File(\??\C:\pagefile.sys)\% Usage Peak
	# \(MSSQL|SQLServer).*:Memory Manager\Total Server Memory (KB)
	$aCounterObject = $sCounterObject.split("\")
	$iLenOfCounterName = $aCounterObject[$aCounterObject.GetUpperBound(0)].length
	$sCounterObject = $sCounterObject.substring(0,$sCounterObject.length - $iLenOfCounterName)
	$sCounterObject = $sCounterObject.Trim("\")
    Return $sCounterObject 	    
}

Function GetCounterComputer
{
    param($sCounterPath)
    
	#'\\IDCWEB1\Processor(_Total)\% Processor Time"
	[string] $sComputer = ""
	
	If ($sCounterPath.substring(0,2) -ne "\\")
	{
		Return ""
	}
	$sComputer = $sCounterPath.substring(2)
	$iLocThirdBackSlash = $sComputer.IndexOf("\")
	$sComputer = $sComputer.substring(0,$iLocThirdBackSlash)
	Return $sComputer
}

Function GetCounterObject
{
    param($sCounterPath)
	$sCounterObject = RemoveCounterNameAndComputerName $sCounterPath
	#// "Paging File(\??\C:\pagefile.sys)"
    
    If ($sCounterObject -ne '')
    {
    	$Char = $sCounterObject.Substring(0,1)
    	If ($Char -eq "`\")
    	{
    		$sCounterObject = $sCounterObject.SubString(1)
    	}	
    	
    	$Char = $sCounterObject.Substring($sCounterObject.Length-1,1)	
    	If ($Char -ne "`)")
    	{
    		Return $sCounterObject
    	}	
    	$iLocOfCounterInstance = 0
    	$iRightParenCount = 0
    	For ($a=$sCounterObject.Length-1;$a -gt 0;$a = $a - 1)
    	{			
    		$Char = $sCounterObject.Substring($a,1)
    		If ($Char -eq "`)")
    		{
    			$iRightParenCount = $iRightParenCount + 1
    		}
    		If ($Char -eq "`(")
    		{
    			$iRightParenCount = $iRightParenCount - 1
    		}
    		$iLocOfCounterInstance = $a
    		If ($iRightParenCount -eq 0){break}
    	}
	   Return $sCounterObject.Substring(0,$iLocOfCounterInstance)    
    }
    Else
    {
        Return ""
    }
}

Function GetCounterInstance
{
    param($sCounterPath)
    
	$sCounterObject = RemoveCounterNameAndComputerName $sCounterPath	
	#// "Paging File(\??\C:\pagefile.sys)"
	$Char = $sCounterObject.Substring(0,1)	
	If ($Char -eq "`\")
	{
		$sCounterObject = $sCounterObject.SubString(1)
	}
	$Char = $sCounterObject.Substring($sCounterObject.Length-1,1)	
	If ($Char -ne "`)")
	{
		Return ""
	}	
	$iLocOfCounterInstance = 0
	$iRightParenCount = 0
	For ($a=$sCounterObject.Length-1;$a -gt 0;$a = $a - 1)
	{			
		$Char = $sCounterObject.Substring($a,1)
		If ($Char -eq "`)")
		{
			$iRightParenCount = $iRightParenCount + 1
		}
		If ($Char -eq "`(")
		{
			$iRightParenCount = $iRightParenCount - 1
		}
		$iLocOfCounterInstance = $a
		If ($iRightParenCount -eq 0){break}
	}
	$iLenOfInstance = $sCounterObject.Length - $iLocOfCounterInstance - 2
	Return $sCounterObject.Substring($iLocOfCounterInstance+1, $iLenOfInstance)
}

Function GetCounterName
{
    param($sCounterPath)
    
	$aCounterPath = @($sCounterPath.Split("\"))
	Return $aCounterPath[$aCounterPath.GetUpperBound(0)]
}

Function IsPerfmonLogMultiComputer
{
    param($aCounterlist)
    
	$sComputerName = GetCounterComputer $aCounterList[0]
	$sPreviousComputerName = GetCounterComputer $aCounterList[0]
	For ($a=1;$a -lt $aCounterList.Length;$a++)
	{
		$sComputerName = GetCounterComputer $aCounterList[$a]
		If ($sComputerName -ne $sPreviousComputerName)
		{
			Return $True
		}
		$sPreviousComputerName = $sComputerName
	}
	Return $False
}

Function ConvertCounterArraysToSeriesHashTable
{
    param($alSeries, $aDateTimes, $htOfCounterValues)
    
	ConvertCounterArraysToSeriesHashTable $alSeries, $aDateTimes, $htOfCounterValues, $False
}

Function AddADashStyle
{
    param($Series,$DashStyleNumber)
    
    If ($DashStyleNumber -gt 3)
    {
        do 
        {
        	$DashStyleNumber = $DashStyleNumber - 4
        } until ($DashStyleNumber -le 3)
    }
    
    switch ($DashStyleNumber)
    {
    	0 {$Series.BorderDashStyle = [System.Windows.Forms.DataVisualization.Charting.ChartDashStyle]"Solid"}
        1 {$Series.BorderDashStyle = [System.Windows.Forms.DataVisualization.Charting.ChartDashStyle]"Dash"}
    	2 {$Series.BorderDashStyle = [System.Windows.Forms.DataVisualization.Charting.ChartDashStyle]"DashDot"}
    	3 {$Series.BorderDashStyle = [System.Windows.Forms.DataVisualization.Charting.ChartDashStyle]"Dot"}
    	#4 {$Series.BorderDashStyle = [System.Windows.Forms.DataVisualization.Charting.ChartDashStyle]"Dot"}		
		default {$Series.BorderDashStyle = [System.Windows.Forms.DataVisualization.Charting.ChartDashStyle]"Solid"}
    }
	$Series
}

Function ConvertCounterArraysToSeriesHashTable
{
    param($alSeries, $aDateTimes, $htOfCounterValues, $IsThresholdsEnabled, $dWarningMin, $dWarningMax, $dCriticalMin, $dCriticalMax, $sBackGradientStyle="TopBottom")

	#[Void] [Reflection.Assembly]::LoadFile("C:\Program Files (x86)\Microsoft Chart Controls\Assemblies\System.Windows.Forms.DataVisualization.dll")

	If ($IsThresholdsEnabled -eq $True)
	{
        If ($dWarningMax -ne $null)
        {
    		#// Add Warning Threshold values
    		$SeriesWarningThreshold = New-Object System.Windows.Forms.DataVisualization.Charting.Series
    		For ($a=0; $a -lt $aDateTimes.length; $a++)
    		{
                If ($sBackGradientStyle -eq "BottomTop")
                {
                    [Void] $SeriesWarningThreshold.Points.Add($dWarningMax[$a], $dWarningMin[$a])
                }
                Else
                {
                    [Void] $SeriesWarningThreshold.Points.Add($dWarningMin[$a], $dWarningMax[$a])
                }
    		}
    		$SeriesWarningThreshold.ChartType = [System.Windows.Forms.DataVisualization.Charting.SeriesChartType]"Range"
    		$SeriesWarningThreshold.Name = "Warning"
            If ($sBackGradientStyle -eq "BottomTop")
            {
        		$SeriesWarningThreshold.Color = [System.Drawing.Color]"Transparent"
                $SeriesWarningThreshold.BackImageTransparentColor = [System.Drawing.Color]"White"
                $SeriesWarningThreshold.BackSecondaryColor = [System.Drawing.Color]"PaleGoldenrod"        
                $SeriesWarningThreshold.BackGradientStyle = [System.Windows.Forms.DataVisualization.Charting.GradientStyle]"TopBottom"
            }
            Else
            {
                $SeriesWarningThreshold.Color = [System.Drawing.Color]"PaleGoldenrod"
                $SeriesWarningThreshold.BackGradientStyle = [System.Windows.Forms.DataVisualization.Charting.GradientStyle]"TopBottom"
            }
    		#$SeriesWarningThreshold.BackHatchStyle = [System.Windows.Forms.DataVisualization.Charting.ChartHatchStyle]"Percent60"
    		[Void] $alSeries.Add($SeriesWarningThreshold)        
        }
        
        If ($dCriticalMin -ne $null)
        {
    		#// Add Critical Threshold values
    		$SeriesCriticalThreshold = New-Object System.Windows.Forms.DataVisualization.Charting.Series
    		For ($a=0; $a -lt $aDateTimes.length; $a++)
    		{
    			[Void] $SeriesCriticalThreshold.Points.Add($dCriticalMin[$a], $dCriticalMax[$a])
    		}
    		$SeriesCriticalThreshold.ChartType = [System.Windows.Forms.DataVisualization.Charting.SeriesChartType]"Range"
    		$SeriesCriticalThreshold.Name = "Critical"
            If ($sBackGradientStyle -eq "BottomTop")
            {
        		$SeriesCriticalThreshold.Color = [System.Drawing.Color]"Transparent"
                $SeriesCriticalThreshold.BackImageTransparentColor = [System.Drawing.Color]"White"
                $SeriesCriticalThreshold.BackSecondaryColor = [System.Drawing.Color]"Tomato"        
                $SeriesCriticalThreshold.BackGradientStyle = [System.Windows.Forms.DataVisualization.Charting.GradientStyle]"TopBottom"
            }
            Else
            {
                $SeriesCriticalThreshold.Color = [System.Drawing.Color]"Tomato"
                $SeriesCriticalThreshold.BackGradientStyle = [System.Windows.Forms.DataVisualization.Charting.GradientStyle]"TopBottom"
            }        
            [Void] $alSeries.Add($SeriesCriticalThreshold)
        }
	}
	#// Sort the hast table and return an array of dictionary objects
		#$htOfCounterValues = @{"C:" = $aTemp1; "D:" = $aTemp2}
	[System.Object[]] $aDictionariesOfCounterValues = $htOfCounterValues.GetEnumerator() | Sort-Object Name
	
	#$htSeries = @{0 = $SeriesWarningThreshold; 1 = $SeriesCriticalThreshold}
	
	#// Add the counter instance values
    #//If ($aDictionariesOfCounterValues -isnot [System.Object[]])
    #//{
    #//    Write-Host "Stop here"
    #//}
	For ($a=0; $a -lt $aDictionariesOfCounterValues.Count; $a++)
	{
		$SeriesOfCounterValues = New-Object System.Windows.Forms.DataVisualization.Charting.Series
        #$sTemp = [string] $aDictionariesOfCounterValues[$a].Value
		#$aValues = $sTemp.Split(',')
        $aValues = $aDictionariesOfCounterValues[$a].Value
		For ($b=0;$b -lt $aValues.Count; $b++)
		{
			If (($aDateTimes[$b] -ne $null) -and ($aValues[$b] -ne $null))
			{
                #// Skips corrupted datetime fields
                $dtDateTime = $aDateTimes[$b]
                If ($dtDateTime -isnot [datetime])
                {
                    [datetime] $dtDateTime = $dtDateTime
                }
                [Void] $SeriesOfCounterValues.Points.AddXY(($dtDateTime).tostring($global:sDateTimePattern), $aValues[$b])
				## Updated to provide localised date time on charts JonnyG 2010-06-11
				#[Void] $SeriesOfCounterValues.Points.AddXY($aDateTimes[$b], $aValues[$b])
				#[Void] $SeriesOfCounterValues.Points.AddXY(().tostring($global:sDateTimePattern), $aValues[$b])
			}
		}
		$SeriesOfCounterValues.ChartType = [System.Windows.Forms.DataVisualization.Charting.SeriesChartType]"Line"
		$SeriesOfCounterValues.Name = $aDictionariesOfCounterValues[$a].Name
        $SeriesOfCounterValues = AddADashStyle -Series $SeriesOfCounterValues -DashStyleNumber $a
        #// Line thickness
        $SeriesOfCounterValues.BorderWidth = $CHART_LINE_THICKNESS

		[Void] $alSeries.Add($SeriesOfCounterValues)
	}
}

Function GenerateMSChart
{
    param($sChartTitle, $sSaveFilePath, $htOfSeriesObjects)
    
	#// GAC the Microsoft Chart Controls just in case it is not GAC'd.
	#// Requires the .NET Framework v3.5 Service Pack 1 or greater.
	#[Void] [Reflection.Assembly]::LoadFile("C:\Program Files (x86)\Microsoft Chart Controls\Assemblies\System.Windows.Forms.DataVisualization.dll")
	
	$oPALChart = New-Object System.Windows.Forms.DataVisualization.Charting.Chart
	$oPALChartArea = New-Object System.Windows.Forms.DataVisualization.Charting.ChartArea
	$fontNormal = new-object System.Drawing.Font("Tahoma",10,[Drawing.FontStyle]'Regular')

	$sFormat = "#" + $global:htScript["LocalizedThousandsSeparator"] + "###" + $global:htScript["LocalizedDecimal"] + "###"		
	$oPALChartArea.AxisY.LabelStyle.Format = $sFormat
	$oPALChartArea.AxisY.LabelStyle.Font = $fontNormal
	$oPALChartArea.AxisX.LabelStyle.Angle = 90
    $oPALChartArea.AxisX.Interval = $global:CHART_AXIS_X_INTERVAL
	$oPALChart.ChartAreas["Default"] = $oPALChartArea
	
    #// Add each of the Series objects to the chart.
	ForEach ($Series in $htOfSeriesObjects)
	{
		$oPALChart.Series[$Series.Name] = $Series
	}
	
	#// Chart size
	$oChartSize = New-Object System.Drawing.Size
	$oChartSize.Width = $CHART_WIDTH
	$oChartSize.Height = $CHART_HEIGHT
	$oPALChart.Size = $oChartSize
	
	#// Chart Title
	[Void] $oPALChart.Titles.Add($sChartTitle)
	
	#// Chart Legend
	$oLegend = New-Object System.Windows.Forms.DataVisualization.Charting.Legend
	[Void] $oPALChart.Legends.Add($oLegend)

	#// Save the chart image to a PNG file. PNG files are better quality images.
	$oPALChartImageFormat = [System.Windows.Forms.DataVisualization.Charting.ChartImageFormat]"Png"
    $sSaveFilePath
    #//Write-host '$sSaveFilePath:' "$sSaveFilePath"
    #//Write-host '$oPALChartImageFormat:' "$($oPALChartImageFormat.GetType().FullName)"
	[Void] $oPALChart.SaveImage($sSaveFilePath, $oPALChartImageFormat)	
}

Function ConvertCounterToFileName
{
    param($sCounterPath)
    
	$sCounterObject = GetCounterObject $sCounterPath
	$sCounterName = GetCounterName $sCounterPath
	$sResult = $sCounterObject + "_" + $sCounterName
	$sResult = $sResult -replace "/", "_"
	$sResult = $sResult -replace "%", "Percent"
	$sResult = $sResult -replace " ", "_"
	$sResult = $sResult -replace "\.", ""
	$sResult = $sResult -replace ":", "_"
	$sResult = $sResult -replace ">", "_"
	$sResult = $sResult -replace "<", "_"
	$sResult = $sResult -replace "\(", "_"
	$sResult = $sResult -replace "\)", "_"
	$sResult = $sResult -replace "\*", "x"
	$sResult = $sResult -replace "\|", "_"
    $sResult = $sResult -replace "#", "Num"
   	$sResult = $sResult -replace "\\", "_"
	$sResult = $sResult -replace "\?", ""
	$sResult = $sResult -replace "\*", ""
	$sResult = $sResult -replace "\|", "_"
	$sResult = $sResult -replace "{", ""
	$sResult = $sResult -replace "}", ""    
	Return $sResult
}

Function CleanUp()
{
	Write-Host "Deleting session working directory... " $global:htScript["SessionWorkingDirectory"]
	If ($global:CounterLog["DeleteWhenDone"] -eq $true)
	{
		DeleteFile $global:sPerfLogFilePath
	}
    If ($global:sCounterListFilterFilePath -ne '')
    {
        If ($(Test-Path -Path $global:sCounterListFilterFilePath) -eq $True)
        {
            DeleteFile $global:sCounterListFilterFilePath
        }
    }
    If ($global:sOriginalCounterListFilePath -ne '')
    {
        If ($(Test-Path -Path $global:sOriginalCounterListFilePath) -eq $True)
        {
            DeleteFile $global:sOriginalCounterListFilePath
        }
    }
	DeleteDirectory $global:htScript["SessionWorkingDirectory"]
}

Function OnEnd
{
    Write-Host 'Processing Statistics:'
    Write-Host '-----------------------'
	Write-Host "Number Of Counter Instances In Perfmon Log: $global:NumberOfCounterInstancesInPerfmonLog"
    $dEndTime = Get-Date
	$dDurationTime = New-TimeSpan -Start $global:htScript["BeginTime"] -End $dEndTime
	"`nScript Execution Duration: " + $dDurationTime + "`n"	
}

Function IsXmlDocument
{
    param($value)
    
	If ($value.GetType().FullName -eq "System.Xml.XmlDocument")
	{
		Return $true
	}
	Else
	{
		Return $false
	}
}

Function CheckPalXmlThresholdFileVersion
{
    param($XmlThresholdFile)
    [string] $sVersion = ''
    ForEach ($XmlPal in $XmlThresholdFile.SelectNodes("//PAL"))
    {    
        If ($(Test-property -InputObject $XmlPal -Name 'PALVERSION') -eq $True)
        {
            $sVersion = $XmlPal.PALVERSION
            If ($sVersion.SubString(0,1) -ne '2')
            {
                Write-Error 'The threshold file specified is not compatible with PAL v2.0.'
                Break Main;
            }
        }
        Else
        {
            Write-Error 'The threshold file specified is not compatible with PAL v2.0.'
            Break Main;    
        } 
    }  
}

Function ReadThresholdFileIntoMemory
{
	param($sThresholdFilePath)	
	[xml] (Get-Content $sThresholdFilePath)	
}

Function InheritFromThresholdFiles
{
    param($sThresholdFilePath)
    
    $XmlThresholdFile = [xml] (Get-Content $sThresholdFilePath)
    CheckPalXmlThresholdFileVersion -XmlThresholdFile $XmlThresholdFile
    #// Add it to the threshold file load history, so that we don't get into an endless loop of inheritance.
    If ($global:alThresholdFilePathLoadHistory.Contains($sThresholdFilePath) -eq $False)
    {
        [void] $global:alThresholdFilePathLoadHistory.Add($sThresholdFilePath)
    }
    
    #// Inherit from other threshold files.
    ForEach ($XmlInheritance in $XmlThresholdFile.SelectNodes("//INHERITANCE"))
    {
        If ($(Test-FileExists $XmlInheritance.FilePath) -eq $True)
        {
            $XmlInherited = [xml] (Get-Content $XmlInheritance.FilePath)
            ForEach ($XmlInheritedAnalysisNode in $XmlInherited.selectNodes("//ANALYSIS"))
            {
                $bFound = $False            
                ForEach ($XmlAnalysisNode in $global:XmlAnalysis.PAL.selectNodes("//ANALYSIS"))
                {
                    If ($XmlInheritedAnalysisNode.ID -eq $XmlAnalysisNode.ID)
                    {
                        $bFound = $True
                        Break
                    }
                    If ($XmlInheritedAnalysisNode.NAME -eq $XmlAnalysisNode.NAME)
                    {
                        $bFound = $True
                        Break
                    }                
                }
                If ($bFound -eq $False)
                {            
                    [void] $global:XmlAnalysis.PAL.AppendChild($global:XmlAnalysis.ImportNode($XmlInheritedAnalysisNode, $True))                
                }
            }
            ForEach ($XmlInheritedQuestionNode in $XmlInherited.selectNodes("//QUESTION"))
            {
                $bFound = $False            
                ForEach ($XmlQuestionNode in $global:XmlAnalysis.PAL.selectNodes("//QUESTION"))
                {
                    If ($XmlInheritedQuestionNode.QUESTIONVARNAME -eq $XmlQuestionNode.QUESTIONVARNAME)
                    {
                        $bFound = $True
                        Break
                    }                
                }
                If ($bFound -eq $False)
                {            
                    [void] $global:XmlAnalysis.PAL.AppendChild($global:XmlAnalysis.ImportNode($XmlInheritedQuestionNode, $True))                
                }
            }        
    		If ($global:alThresholdFilePathLoadHistory.Contains($XmlInheritance.FilePath) -eq $False)
    		{
    			InheritFromThresholdFiles $XmlInheritance.FilePath
    		}
        }
    }	 
}

Function ConvertCounterNameToExpressionPath($sCounterPath)
{
	$sCounterObject = GetCounterObject $sCounterPath
	$sCounterName = GetCounterName $sCounterPath
	$sCounterInstance = GetCounterInstance $sCounterPath	
	If ($sCounterInstance -eq "")
	{
		"\$sCounterObject\$sCounterName"
	}
	Else
	{
		"\$sCounterObject(*)\$sCounterName"
	}	
}

Function ConvertCounterExpressionToVarName($sCounterExpression)
{
	$sCounterObject = GetCounterObject $sCounterExpression
	$sCounterName = GetCounterName $sCounterExpression
	$sCounterInstance = GetCounterInstance $sCounterExpression	
	If ($sCounterInstance -ne "*")
	{
		$sResult = $sCounterObject + $sCounterName + $sCounterInstance
	}
	Else
	{
		$sResult = $sCounterObject + $sCounterName + "ALL"
	}
	$sResult = $sResult -replace "/", ""
	$sResult = $sResult -replace "\.", ""
	$sResult = $sResult -replace "%", "Percent"
	$sResult = $sResult -replace " ", ""
	$sResult = $sResult -replace "\.", ""
	$sResult = $sResult -replace ":", ""
	$sResult = $sResult -replace "\(", ""
	$sResult = $sResult -replace "\)", ""
	$sResult = $sResult -replace "-", ""
	$sResult
}

Function CreateXmlAnalysisNodeFromCounterPath
{
    param($XmlAnalysis, $sCounterExpressionPath)

    $sAnalysisCategory = GetCounterObject $sCounterExpressionPath
    $sAnalysisName = GetCounterName $sCounterExpressionPath
    $sGUID = Get-GUID
    $VarName = ConvertCounterExpressionToVarName $sCounterExpressionPath

	#// ANALYSIS Attributes
    $XmlNewAnalysisNode = $XmlAnalysis.CreateElement("ANALYSIS")
    $XmlNewAnalysisNode.SetAttribute("NAME", $sAnalysisName)
    $XmlNewAnalysisNode.SetAttribute("ENABLED", $True)
    $XmlNewAnalysisNode.SetAttribute("CATEGORY", $sAnalysisCategory)
    $XmlNewAnalysisNode.SetAttribute("ID", $sGUID)
	$XmlNewAnalysisNode.SetAttribute("FROMALLCOUNTERSTATS", 'True')    
    
    #// DATASOURCE
    $XmlNewDataSourceNode = $XmlAnalysis.CreateElement("DATASOURCE")
    $XmlNewDataSourceNode.SetAttribute("TYPE", "CounterLog")
    $XmlNewDataSourceNode.SetAttribute("NAME", $sCounterExpressionPath)
    $XmlNewDataSourceNode.SetAttribute("COLLECTIONVARNAME", "CollectionOf$VarName")
    $XmlNewDataSourceNode.SetAttribute("EXPRESSIONPATH", $sCounterExpressionPath)
    $XmlNewDataSourceNode.SetAttribute("NUMBEROFSAMPLESVARNAME", "NumberOfSamples$VarName")
    $XmlNewDataSourceNode.SetAttribute("MINVARNAME", "Min$VarName")
    $XmlNewDataSourceNode.SetAttribute("AVGVARNAME", "Avg$VarName")
    $XmlNewDataSourceNode.SetAttribute("MAXVARNAME", "Max$VarName")
    $XmlNewDataSourceNode.SetAttribute("TRENDVARNAME", "Trend$VarName")
    $XmlNewDataSourceNode.SetAttribute("DATATYPE", "round3")
    [void] $XmlNewAnalysisNode.AppendChild($XmlNewDataSourceNode)
    
    #// CHART
    $XmlNewDataSourceNode = $XmlAnalysis.CreateElement("CHART")
    $XmlNewDataSourceNode.SetAttribute("CHARTTITLE", $sCounterExpressionPath)
    $XmlNewDataSourceNode.SetAttribute("ISTHRESHOLDSADDED", "False")
    $XmlNewDataSourceNode.SetAttribute("DATASOURCE", $sCounterExpressionPath)
    $XmlNewDataSourceNode.SetAttribute("CHARTLABELS", "instance")
    [void] $XmlNewAnalysisNode.AppendChild($XmlNewDataSourceNode)    
    
    [void] $XmlAnalysis.PAL.AppendChild($XmlNewAnalysisNode)
}

Function GetCounterListFromBlg
{
    param($sBlgFilePath)    
    $global:sOriginalCounterListFilePath = $global:htScript["SessionWorkingDirectory"] + '\OriginalCounterList.txt'
    $sCommand = $('relog.exe ' + "`"$sBlgFilePath`"" + ' -q -o ' + "`"$global:sOriginalCounterListFilePath`"" )
    Write-Host 'Getting the counter list from the perfmon log...'
    Write-Host $sCommand
    $sOutput = Invoke-Expression -Command $sCommand
    Write-Host $sOutput
    Write-Host 'Getting the counter list from the perfmon log...Done!'
    If ($(Test-Path -Path $global:sOriginalCounterListFilePath) -eq $False)
    {
        Write-Error '[GetCounterListFromBlg] Failed to create the original counter list using relog.exe using the following command:'
        Write-Error $sCommand
        Break Main;
    }
    $oTextFile = Get-Content $global:sOriginalCounterListFilePath
    $u = $oTextFile.Count
    $global:aOriginalCounterList = $oTextFile[0..$u]
    Return $global:aOriginalCounterList
}

Function AddAllCountersFromPerfmonLog
{
    param($XmlAnalysis, $sPerfLogFilePath)
    Write-Host "All counter stats is set to true. Loading all counters in perfmon log into the threshold file as new analyses. This may take several minutes."
    $htCounterExpressions = @{}    

    If ($global:aCounterLogCounterList -eq "")
    { 
        Write-Host 'Getting the counter list from the perfmon log...' -NoNewline    
		#Write-Host `t`t"Getting the counter list from the perfmon log (one time only)..." -NoNewline
        If ($(CheckTheFileExtension -Filepath $sPerfLogFilePath -ThreeLetterExtension 'csv') -eq $True)
        {
            $global:aCounterLogCounterList = GetCounterListFromCsvAsText $sPerfLogFilePath
        }
        Else
        {
            $global:aCounterLogCounterList = GetCounterListFromBlg -sBlgFilePath $sPerfLogFilePath
        }
        Write-Host 'Done'
    }

    Write-Host 'Importing the counter list as new threshold analyses' -NoNewline
    #// Add Primary data source counters that are already in the threshold file.
    $PercentComplete = 0
    ForEach ($XmlAnalysisNode in $XmlAnalysis.SelectNodes('//ANALYSIS'))
    {
        If (($($htCounterExpressions.ContainsKey($($XmlAnalysisNode.PRIMARYDATASOURCE))) -eq $False) -or ($htCounterExpressions.Count -eq 0))
        {
            [void] $htCounterExpressions.Add($XmlAnalysisNode.PRIMARYDATASOURCE,"")
        }
    }
    
    For ($i=0;$i -lt $global:aCounterLogCounterList.GetUpperBound(0);$i++)
    {
        $sCounterExpression = ConvertCounterNameToExpressionPath $global:aCounterLogCounterList[$i]
        If ($htCounterExpressions.ContainsKey($sCounterExpression) -eq $False)
        {
            CreateXmlAnalysisNodeFromCounterPath $XmlAnalysis $sCounterExpression
			#Write-Host "Loading... $sCounterExpression"
            [void] $htCounterExpressions.Add($sCounterExpression,"")
            #Write-Host '.' -NoNewline
        }
        $PercentComplete = CalculatePercentage -Number $i -Total $global:aCounterLogCounterList.GetUpperBound(0)
        Write-Progress -activity 'Importing the counter list as new analyses...' -status '% Complete:' -percentcomplete $PercentComplete;        
    }
    Write-Progress -activity 'Importing the counter list as new threshold analyses' -status '% Complete:' -Completed
    Write-Host 'Done'
	#Write-Host "Done loading all counters into the threshold file."
	$XmlAnalysis
}

Function GenerateXmlCounterList
{
    #// This function converts the raw text based counter list into an XML document organized by counter properties for better performance.
    #Write-Host 'Generating XmlCounterList (improves counter matching performance) from the imported counter list' -NoNewline

    If ($global:aCounterLogCounterList -eq "")
    { 
		#Write-Host `t`t"Getting the counter list from the perfmon log (one time only)..." -NoNewline
        If ($global:IsCounterLogFile -eq $True)
        {
       	    $global:aCounterLogCounterList = GetCounterListFromCsvAsText $global:sPerfLogFilePath
        }
        Else
        {
            $global:aCounterLogCounterList = GetCounterListFromDatabase
        }
		#Write-Host "Done" 
    }
    
    $c = $global:aCounterLogCounterList
    If ($c -isnot [System.Object[]])
    {
        #// Make $c an array of one.
        $c = @($c)
    }
    [xml] $global:XmlCounterLogCounterInstanceList = "<PAL></PAL>"
    For ($i=0;$i -le $c.GetUpperBound(0);$i++)
    {
        #Write-Host '.' -NoNewLine
        $PercentComplete = CalculatePercentage -Number $i -Total $c.GetUpperBound(0)
        $sComplete = "Progress: $(ConvertToDataType $PercentComplete 'integer')% (Counter $i of $($c.GetUpperBound(0)))"
        write-progress -activity 'Generating counter index to improve performance...' -status $sComplete -percentcomplete $PercentComplete;
        $sCounterPath = $c[$i]
    	$sCounterComputer = GetCounterComputer $c[$i]
        $sCounterObject = GetCounterObject $c[$i]
        If ($sCounterObject -ne '')
        {
        	$sCounterName = GetCounterName $c[$i]
            $sCounterInstance = GetCounterInstance $c[$i]

            $IsCounterComputerFound = $False
            $IsCounterObjectFound = $False
            $IsCounterNameFound = $False
            $IsCounterInstanceFound = $False
            $IsCounterObjectSqlInstance = $False
            $sCounterObjectSqlInstance = ""
            $sCounterObjectSqlRegularExpression = ''        
            #// Counter Computers
            ForEach ($XmlCounterComputerNode in $global:XmlCounterLogCounterInstanceList.SelectNodes('//COUNTERCOMPUTER'))
            {
                If ($XmlCounterComputerNode.NAME -eq $sCounterComputer)
                {
                    $IsCounterComputerFound = $True
                    #// Counter Objects
                    ForEach ($XmlCounterObjectNode in $XmlCounterComputerNode.ChildNodes)
                    {
                        #// Check if the counter object is a SQL Named instance "MSSQL$SHAREPOINT:Access Methods"
                        #//If ($sCounterObject.Length -gt 7)
                        #//{
                        #//    If (($sCounterObject.SubString(0,6) -eq 'MSSQL$') -or ($sCounterObject.SubString(0,7) -eq 'MSOLAP$'))
                        #//    {
                        #//        $IsCounterObjectSqlInstance = $True
                        #//        $aTemp = $sCounterObject.Split(':')
                        #//        $sCounterObjectSqlInstance = 'SQLServer:' + "$($aTemp[$aTemp.GetUpperBound(0)])"                        
                        #//    }
                        #//}
                    
                        If (($XmlCounterObjectNode.NAME -eq $sCounterObject) -or ($XmlCounterObjectNode.NAME -eq $sCounterObjectSqlInstance))
                        {
                            $IsCounterObjectFound = $True
                            #// Counter Names
                            ForEach ($XmlCounterNameNode in $XmlCounterObjectNode.ChildNodes)
                            {
                                If ($XmlCounterNameNode.NAME -eq $sCounterName)
                                {
                                    $IsCounterNameFound = $True
                                    #// Counter Instances
                                    ForEach ($XmlCounterInstanceNode in $XmlCounterNameNode.ChildNodes)
                                    {
                                        If ($XmlCounterInstanceNode.NAME.ToLower() -eq $sCounterInstance.ToLower())
                                        {
                                            $IsCounterInstanceFound = $True
                                        }
                                    }
                                    #// Create the counter Instance if it does not exist.
                                    If (($IsCounterInstanceFound -eq $False) -or ($IsCounterObjectSqlInstance -eq $True))
                                    {
                                        $XmlNewCounterInstanceNode = $global:XmlCounterLogCounterInstanceList.CreateElement("COUNTERINSTANCE")
                                        $XmlNewCounterInstanceNode.SetAttribute("NAME", $sCounterInstance)
                                        $XmlNewCounterInstanceNode.SetAttribute("COUNTERPATH", $sCounterPath)
                                        $XmlNewCounterInstanceNode.SetAttribute("COUNTERLISTINDEX", $($i+1)) #// The +1 is to compensate for the removal of the time zone in the original CSV file.
                                        [void] $XmlCounterNameNode.AppendChild($XmlNewCounterInstanceNode)
                                    }
                                }
                            }
                            #// Create the counter Name if it does not exist.
                            If ($IsCounterNameFound -eq $False)
                            {                            
                                $XmlNewCounterNameNode = $XmlCounterLogCounterInstanceList.CreateElement("COUNTERNAME")
                                $XmlNewCounterNameNode.SetAttribute("NAME", $sCounterName)
                                
                                $XmlNewCounterInstanceNode = $global:XmlCounterLogCounterInstanceList.CreateElement("COUNTERINSTANCE")
                                $XmlNewCounterInstanceNode.SetAttribute("NAME", $sCounterInstance)
                                $XmlNewCounterInstanceNode.SetAttribute("COUNTERPATH", $sCounterPath)
                                $XmlNewCounterInstanceNode.SetAttribute("COUNTERLISTINDEX", $($i+1)) #// The +1 is to compensate for the removal of the time zone in the original CSV file.
                                
                                [void] $XmlNewCounterNameNode.AppendChild($XmlNewCounterInstanceNode)
                                [void] $XmlCounterObjectNode.AppendChild($XmlNewCounterNameNode)
                            }
                        }
                    }
                    #// Create the counter object if it does not exist.
                    If ($IsCounterObjectFound -eq $False)
                    {
                        $XmlNewCounterObjectNode = $global:XmlCounterLogCounterInstanceList.CreateElement("COUNTEROBJECT")
                        $XmlNewCounterObjectNode.SetAttribute("NAME", $sCounterObject)
                        
                        $XmlNewCounterNameNode = $global:XmlCounterLogCounterInstanceList.CreateElement("COUNTERNAME")
                        $XmlNewCounterNameNode.SetAttribute("NAME", $sCounterName)
                        
                        $XmlNewCounterInstanceNode = $global:XmlCounterLogCounterInstanceList.CreateElement("COUNTERINSTANCE")
                        $XmlNewCounterInstanceNode.SetAttribute("NAME", $sCounterInstance)
                        $XmlNewCounterInstanceNode.SetAttribute("COUNTERPATH", $sCounterPath)
                        $XmlNewCounterInstanceNode.SetAttribute("COUNTERLISTINDEX", $($i+1)) #// The +1 is to compensate for the removal of the time zone in the original CSV file.
                        
                        [void] $XmlNewCounterNameNode.AppendChild($XmlNewCounterInstanceNode)
                        [void] $XmlNewCounterObjectNode.AppendChild($XmlNewCounterNameNode)
                        [void] $XmlCounterComputerNode.AppendChild($XmlNewCounterObjectNode)
                    }
                }            
            }
            #// Create the counter computer if it does not exist
            If ($IsCounterComputerFound -eq $False)
            {
                $XmlNewCounterComputerNode = $global:XmlCounterLogCounterInstanceList.CreateElement("COUNTERCOMPUTER")
                $XmlNewCounterComputerNode.SetAttribute("NAME", $sCounterComputer)
                
                $XmlNewCounterObjectNode = $global:XmlCounterLogCounterInstanceList.CreateElement("COUNTEROBJECT")
                $XmlNewCounterObjectNode.SetAttribute("NAME", $sCounterObject)
                
                $XmlNewCounterNameNode = $global:XmlCounterLogCounterInstanceList.CreateElement("COUNTERNAME")
                $XmlNewCounterNameNode.SetAttribute("NAME", $sCounterName)
                
                $XmlNewCounterInstanceNode = $global:XmlCounterLogCounterInstanceList.CreateElement("COUNTERINSTANCE")
                $XmlNewCounterInstanceNode.SetAttribute("NAME", $sCounterInstance)
                $XmlNewCounterInstanceNode.SetAttribute("COUNTERPATH", $sCounterPath)
                $XmlNewCounterInstanceNode.SetAttribute("COUNTERLISTINDEX", $($i+1)) #// The +1 is to compensate for the removal of the time zone in the original CSV file.
                
                [void] $XmlNewCounterNameNode.AppendChild($XmlNewCounterInstanceNode)
                [void] $XmlNewCounterObjectNode.AppendChild($XmlNewCounterNameNode)
                [void] $XmlNewCounterComputerNode.AppendChild($XmlNewCounterObjectNode)
                [void] $global:XmlCounterLogCounterInstanceList.DocumentElement.AppendChild($XmlNewCounterComputerNode)            
            }            
        }
    }
    $sComplete = "Progress: 100% (Counter $($c.GetUpperBound(0)) of $($c.GetUpperBound(0)))"
    write-progress -activity 'Generating counter index to improve performance...' -status $sComplete -Completed
    $global:NumberOfCounterInstancesInPerfmonLog = $c.GetUpperBound(0) + 1    
    #Write-Host 'Done'
    Write-Host "Number Of Counter Instances In Perfmon Log: $global:NumberOfCounterInstancesInPerfmonLog"
}

Function GetTimeZoneFromCsvFile
{
    param($CsvFilePath)
    
	$oCSVFile = Get-Content $CsvFilePath
	$aRawCounterList = $oCSVFile[0].Split(",")
	Return $aRawCounterList[0].Trim("`"")
}

Function GetTimeDataFromPerfmonLog()
{
	If ($global:sPerfLogTimeZone -eq "")
	{
		$global:sPerfLogTimeZone = GetTimeZoneFromCsvFile $global:sPerfLogFilePath
	}
    #$aTime = Import-Csv -Path $global:sPerfLogFilePath | ForEach-Object {$_.$global:sPerfLogTimeZone}
    $global:aTime = GetCounterDataFromPerfmonLog -sCounterPath $global:sPerfLogTimeZone -iCounterIndexInCsv 0
    $global:aTime
}

Function GetIndexWidthOfPerfmonCsvFile
{
    param($CsvFilePath)
	$oCSVFile = Get-Content $CsvFilePath
}

Function ConstructCounterDataArray
{
    $PercentComplete = 0
    $sComplete = "Progress: 0% (Counter ?? of ??)"
    write-progress -activity 'Importing counter data into memory...' -status $sComplete -percentcomplete $PercentComplete
    
	$oCSVFile = Get-Content -Path $global:sPerfLogFilePath
	#// Get the width and height of the CSV file as indexes.
	$aLine = $oCSVFile[0].Trim('"') -split '","'
    $iPerfmonCsvIndexWidth = $aLine.GetUpperBound(0)
	$iPerfmonCsvIndexHeight = $oCSVFile.GetUpperBound(0)
	$global:alCounterData = New-Object System.Collections.ArrayList
	If ($($oCSVFile[$iPerfmonCsvIndexHeight].Contains(',')) -eq $False)
	{
		do 
		{
			$iPerfmonCsvIndexHeight = $iPerfmonCsvIndexHeight - 1
		} until ($($oCSVFile[$iPerfmonCsvIndexHeight].Contains(',')) -eq $true)	
	}
	For ($i=0;$i -le $iPerfmonCsvIndexHeight;$i++)
	{
		$aLine = $oCSVFile[$i].Trim('"') -split '","'
		[void] $global:alCounterData.Add($aLine)
        $PercentComplete = CalculatePercentage -Number $i -Total $iPerfmonCsvIndexHeight
        $sComplete = "Progress: $(ConvertToDataType $PercentComplete 'integer')% (Counter $i of $iPerfmonCsvIndexHeight)"
        write-progress -activity 'Importing counter data into memory...' -status $sComplete -percentcomplete $PercentComplete
	}
	$global:alCounterData
    $sComplete = "Progress: 100% (Counter $iPerfmonCsvIndexHeight of $iPerfmonCsvIndexHeight)"
    write-progress -activity 'Importing counter data into memory...' -status $sComplete -Completed
}

Function GetCounterDataFromPerfmonLog($sCounterPath,$iCounterIndexInCsv)
{    
    $aValues = New-Object System.Collections.ArrayList
    If ($global:alCounterData -eq $null)
    {
        $global:alCounterData = ConstructCounterDataArray
    }
    
    For ($i=1;$i -lt $global:alCounterData.Count;$i++)
    {
        [void] $aValues.Add($($global:alCounterData[$i][$iCounterIndexInCsv]))
    }    
    #// Stopped - Get the counter data from alCounterData - look up $sCounterPath from XmlCounterLookup    
	$aValues
}

Function IsGreaterThanZero
{
    param($Value)
    If (IsNumeric $Value)
    {
        If ($Value -gt 0)
        {
            Return $True
        }
        Else
        {
            Return $False
        }
    }
    Else
    {
        Return $False
    }
}

Function ConvertToDataType
{
	param($ValueAsDouble, $DataTypeAsString="integer")
	$sDateType = $DataTypeAsString.ToLower()

    If ($(IsNumeric -Value $ValueAsDouble) -eq $True)
    {
    	switch ($sDateType) 
    	{
    		#"absolute" {[Math]::Abs($ValueAsDouble)}
    		#"double" {[double]$ValueAsDouble}
    		"integer" {[Math]::Round($ValueAsDouble,0)}
    		#"long" {[long]$ValueAsDouble}
    		#"single" {[single]$ValueAsDouble}
    		"round1" {[Math]::Round($ValueAsDouble,1)}
    		"round2" {[Math]::Round($ValueAsDouble,2)}
    		"round3" {[Math]::Round($ValueAsDouble,3)}
    		"round4" {[Math]::Round($ValueAsDouble,4)}
    		"round5" {[Math]::Round($ValueAsDouble,5)}
    		"round6" {[Math]::Round($ValueAsDouble,6)}
    		default {$ValueAsDouble}
    	}
    }
    Else
    {
        $ValueAsDouble
    }
}

Function GenerateAutoAnalysisInterval
{
	param($ArrayOfTimes,$NumberOfTimeSlices=30)
    $dtBeginDateTime = $ArrayOfTimes[0]
    $dtEndDateTime = $ArrayOfTimes[$ArrayOfTimes.GetUpperBound(0)]
    
    If ($dtBeginDateTime -isnot [datetime])
    {
        [datetime] $dtBeginDateTime = $dtBeginDateTime
    }
    
    If ($dtEndDateTime -isnot [datetime])
    {
        [datetime] $dtEndDateTime = $dtEndDateTime
    }
        
	#$iTimeSpanInSeconds = [int] $(New-TimeSpan -Start ([DateTime] $ArrayOfTimes[0]) -End ([DateTime] $ArrayOfTimes[$ArrayOfTimes.GetUpperBound(0)])).TotalSeconds
    $iTimeSpanInSeconds = [int] $(New-TimeSpan -Start ($dtBeginDateTime) -End ($dtEndDateTime)).TotalSeconds
	[int] $AutoAnalysisIntervalInSeconds = $iTimeSpanInSeconds / $NumberOfTimeSlices
	$AutoAnalysisIntervalInSeconds
}

Function ProcessAnalysisInterval
{
    param($aTime)
    If ($Interval -eq 'AUTO')
    {
        Write-Host `t"Auto analysis interval (one time only)..." -NoNewline
        $global:AnalysisInterval = GenerateAutoAnalysisInterval -ArrayOfTimes $aTime
        Write-Host 'Done'
    }
    Else
    {
        $global:AnalysisInterval = $Interval
    }
}

Function GenerateQuantizedIndexArray
{
	param($ArrayOfTimes,$AnalysisIntervalInSeconds=60)
	$alIndexArray = New-Object System.Collections.ArrayList
	$alSubIndexArray = New-Object System.Collections.ArrayList
	[datetime] $dTimeCursor = [datetime] $ArrayOfTimes[0]
	$dTimeCursor = $dTimeCursor.AddSeconds($AnalysisIntervalInSeconds)
    $u = $ArrayOfTimes.GetUpperBound(0)
    $dEndTime = [datetime] $ArrayOfTimes[$u]
    
    #// If the analysis interval is larger than the entire time range of the log, then just use the one time slice.
    If ($dTimeCursor -gt $dEndTime)
    {
        #//@([void] $alIndexArray.Add([System.Object[]] @(0..$u)))
        #//Return $alIndexArray
        $dDurationTime = New-TimeSpan -Start $ArrayOfTimes[0] -End $dEndTime
        Write-Warning $('The analysis interval is larger than the time range of the entire log. Please use an analysis interval that is smaller than ' + "$($dDurationTime.TotalSeconds)" + ' seconds.')
        Write-Warning $("Log Start Time: $($ArrayOfTimes[0])")
        Write-Warning $("Log Stop Time: $($ArrayOfTimes[$u])")
        Write-Warning $("Log Length: $($dDurationTime)")
        Break Main;
    }
    
    #// Set the Chart X Axis interval
    If ($global:NumberOfValuesPerTimeSlice -eq -1)
    {
    	:ValuesPerTimeSliceLoop For ($i=0;$i -le $ArrayOfTimes.GetUpperBound(0);$i++)
    	{
    		If ($ArrayOfTimes[$i] -le $dTimeCursor)
    		{
    			[Void] $alSubIndexArray.Add($i)
                $global:NumberOfValuesPerTimeSlice = $alSubIndexArray.Count
    		}
    		Else
    		{
                #If ($alSubIndexArray.Count -gt 1)
                #{
                    $global:NumberOfValuesPerTimeSlice = $alSubIndexArray.Count
                #}
                #Else
                #{
                #    $global:NumberOfValuesPerTimeSlice = $alSubIndexArray.Count + 1
                #}
    			$alSubIndexArray.Clear()
                Break ValuesPerTimeSliceLoop;
    		}
    	}
        $global:CHART_AXIS_X_INTERVAL = $global:NumberOfValuesPerTimeSlice        
        $iNumberOfValuesPerTimeSliceInChart = $global:NumberOfValuesPerTimeSlice
        $iNumberOfIntervals = $ArrayOfTimes.Count / $global:NumberOfValuesPerTimeSlice
        $iNumberOfIntervals = [Math]::Round($iNumberOfIntervals,0)
        If ($iNumberOfIntervals -gt $global:CHART_MAX_NUMBER_OF_AXIS_X_INTERVALS)
        {
            $iNumberOfValuesPerTimeSliceInChart = $ArrayOfTimes.Count / $global:CHART_MAX_NUMBER_OF_AXIS_X_INTERVALS
            $iNumberOfValuesPerTimeSliceInChart = [Math]::Round($iNumberOfValuesPerTimeSliceInChart,0)
            $global:CHART_AXIS_X_INTERVAL = $iNumberOfValuesPerTimeSliceInChart
        }
    }    
    
    #// Quantize the time array.
	For ($i=0;$i -le $ArrayOfTimes.GetUpperBound(0);$i++)
	{
		If ($ArrayOfTimes[$i] -le $dTimeCursor)
		{
			[Void] $alSubIndexArray.Add($i)
		}
		Else
		{
			[Void] $alIndexArray.Add([System.Object[]] $alSubIndexArray)
			$alSubIndexArray.Clear()
			[Void] $alSubIndexArray.Add($i)
			$dTimeCursor = $dTimeCursor.AddSeconds($AnalysisIntervalInSeconds)
		}
	}	
	$alIndexArray
}

Function GenerateQuantizedTimeArray
{
	param($ArrayOfTimes,$QuantizedIndexArray = $(GenerateQuantizedIndexArray -ArrayOfTimes $ArrayOfTimes -AnalysisIntervalInSeconds $global:AnalysisInterval))
	$alQuantizedTimeArray = New-Object System.Collections.ArrayList
	For ($i=0;$i -lt $QuantizedIndexArray.Count;$i++)
	{
		$iFirstIndex = $QuantizedIndexArray[$i][0]
		[void] $alQuantizedTimeArray.Add([datetime]$ArrayOfTimes[$iFirstIndex])	
	}
	$alQuantizedTimeArray
}

Function GenerateQuantizedAvgValueArray
{
	param($ArrayOfValues, $ArrayOfQuantizedIndexes, $DataTypeAsString="double")
	$aAvgQuantizedValues = New-Object System.Collections.ArrayList
    If ($ArrayOfValues -is [System.Collections.ArrayList])
    {
        [boolean] $IsValueNumeric = $false
    	For ($a=0;$a -lt $ArrayOfQuantizedIndexes.Count;$a++)
    	{
    		[double] $iSum = 0.0
            [int] $iCount = 0
    		[System.Object[]] $aSubArray = $ArrayOfQuantizedIndexes[$a]
    		For ($b=0;$b -le $aSubArray.GetUpperBound(0);$b++)
    		{
    			$i = $aSubArray[$b]
                $IsValueNumeric = IsNumeric -Value $ArrayOfValues[$i]
                If ($IsValueNumeric)
                {
                    $iSum += $ArrayOfValues[$i]
                    $iCount++
                }			
    		}
            If ($iCount -gt 0)
            {
                $iValue = ConvertToDataType -ValueAsDouble $($iSum / $iCount) -DataTypeAsString $DataTypeAsString
                [Void] $aAvgQuantizedValues.Add($iValue)
            }
            Else
            {
                [Void] $aAvgQuantizedValues.Add('-')
            }
    	}
    }
    Else
    {
        Return $ArrayOfValues
    }
	$aAvgQuantizedValues
}

Function GenerateQuantizedMinValueArray
{
	param($ArrayOfValues, $ArrayOfQuantizedIndexes, $DataTypeAsString="double")
	$aMinQuantizedValues = New-Object System.Collections.ArrayList
    If ($ArrayOfValues -is [System.Collections.ArrayList])
    {
    	For ($a=0;$a -lt $ArrayOfQuantizedIndexes.Count;$a++)
    	{
            [int] $iCount = 0
    		[System.Object[]] $aSubArray = $ArrayOfQuantizedIndexes[$a]
    		$iMin = $ArrayOfValues[$aSubArray[0]]
    		For ($b=0;$b -le $aSubArray.GetUpperBound(0);$b++)
    		{
    			$i = $aSubArray[$b]
    			If ($ArrayOfValues[$i] -lt $iMin)
    			{
    				$iMin = $ArrayOfValues[$i]
                    #$iCount++
    			}
    		}
            #If ($iCount -gt 0)
            #{
        		$iValue = ConvertToDataType -ValueAsDouble $iMin -DataTypeAsString $DataTypeAsString
        		[Void] $aMinQuantizedValues.Add($iValue)
            #}
            #Else
            #{
            #    [Void] $aMinQuantizedValues.Add('-')
            #}        
    	}
    }
    Else
    {
        Return $ArrayOfValues
    }
	$aMinQuantizedValues
}

Function GenerateQuantizedMaxValueArray
{
	param($ArrayOfValues, $ArrayOfQuantizedIndexes, $DataTypeAsString="double")
	$aMaxQuantizedValues = New-Object System.Collections.ArrayList
    If ($ArrayOfValues -is [System.Collections.ArrayList])
    {
    	For ($a=0;$a -lt $ArrayOfQuantizedIndexes.Count;$a++)
    	{
            [int] $iCount = 0
    		[System.Object[]] $aSubArray = $ArrayOfQuantizedIndexes[$a]
    		$iMax = $ArrayOfValues[$aSubArray[0]]
    		For ($b=0;$b -le $aSubArray.GetUpperBound(0);$b++)
    		{
    			$i = $aSubArray[$b]
    			If ($ArrayOfValues[$i] -gt $iMax)
    			{
    				$iMax = $ArrayOfValues[$i]
                    #$iCount++
    			}
    		}
            #If ($iCount -gt 0)
            #{        
                $iValue = ConvertToDataType -ValueAsDouble $iMax -DataTypeAsString $DataTypeAsString
                [Void] $aMaxQuantizedValues.Add($iValue)
            #}
            #Else
            #{
            #    [Void] $aMaxQuantizedValues.Add('-')
            #}
    	}
    }
    Else
    {
        Return $ArrayOfValues
    }
	$aMaxQuantizedValues
}

Function CalculateStdDev
{
	param($Values)
    $SumSquared = 0
	For ($i=0;$i -lt $Values.Count;$i++)
	{
		$SumSquared = $SumSquared + ($Values[$i] * $Values[$i])
	}	
	$oStats = $Values | Measure-Object -Sum
	
	If ($oStats.Sum -gt 0)
	{
		If ($oStats.Count -gt 1)
		{
			$StdDev = [Math]::Sqrt([Math]::Abs(($SumSquared - ($oStats.Sum * $oStats.Sum / $oStats.Count)) / ($oStats.Count -1)))
		}
		Else
		{
			$StdDev = [Math]::Sqrt([Math]::Abs(($SumSquared - ($oStats.Sum * $oStats.Sum / $oStats.Count)) / $oStats.Count))
		}
	}
	Else
	{
		$StdDev = 0
	}
	$StdDev
}

Function CalculatePercentile
{
	param($Values,$Percentile)
    If ($Values -eq $null)
    {Return $Values}
    If ($Values -is [System.Collections.ArrayList])
    {
    	$oStats = $Values | Measure-Object -Average -Minimum -Maximum -Sum
    	$iDeviation = $oStats.Average * ($Percentile / 100)
    	$iLBound = $Values.Count - [int]$(($Percentile / 100) * $Values.Count)
        $iUBound = [int]$(($Percentile / 100) * $Values.Count)
        [System.Object[]] $aSortedNumbers = $Values | Sort-Object
        If ($aSortedNumbers -isnot [System.Object[]])
        {
            Write-Error 'ERROR: $aSortedNumbers -isnot [System.Object[]]. This is most likely due to no counters in the threshold file matching to counters in the counter log.'
        }        
        $iIndex = 0
        If ($iUBound -gt $aSortedNumbers.GetUpperBound(0))
    	{
            $iUBound = $aSortedNumbers.GetUpperBound(0)
    	}
        If ($iLBound -eq $iUBound)
    	{
            Return $aSortedNumbers[$iLBound]
        }
    	$aNonDeviatedNumbers = New-Object System.Collections.ArrayList
        For ($i=0;$i -lt $iUBound;$i++)
    	{
            [void] $aNonDeviatedNumbers.Add($iIndex)
            $aNonDeviatedNumbers[$iIndex] = $aSortedNumbers[$i]
            $iIndex++
        }
        If ($iIndex -gt 0)
    	{
    		$oStats = $aNonDeviatedNumbers | Measure-Object -Average
            Return $oStats.Average
    	}
        Else
    	{
            Return "-"
        }
    }
    Else
    {
        Return $Values
    }
}


Function CalculateHourlyTrend
{
	param($Value,$AnalysisIntervalInSeconds,$DataTypeAsString)
    	
    If ($AnalysisIntervalInSeconds -lt 3600)
	{
        $IntervalAdjustment = 3600 / $AnalysisIntervalInSeconds 
        Return ConvertToDataType -ValueAsDouble $($Value * $IntervalAdjustment) -DataTypeAsString $DataTypeAsString
    }

    If ($AnalysisIntervalInSeconds -gt 3600)
	{
        $IntervalAdjustment = $AnalysisIntervalInSeconds / 3600
        Return ConvertToDataType -ValueAsDouble $($Value / $IntervalAdjustment) -DataTypeAsString $DataTypeAsString
    }

    If ($AnalysisIntervalInSeconds -eq 3600)
	{
        Return ConvertToDataType -ValueAsDouble $Value -DataTypeAsString $DataTypeAsString
	}
}

Function RemoveDashesFromArray
{
    param($Array)
    $Array | Where-Object {$_ -notlike '-'}
}

Function CalculateTrend
{
	param($ArrayOfQuantizedAvgs,$AnalysisIntervalInSeconds,$DataTypeAsString)
    $iSum = 0
    If (($ArrayOfQuantizedAvgs -is [System.Collections.ArrayList]) -or ($ArrayOfQuantizedAvgs -is [System.object[]]))
    {
    	If ($ArrayOfQuantizedAvgs -is [System.object[]])
    	{
    		$alDiff = New-Object System.Collections.ArrayList
    		$iUb = $ArrayOfQuantizedAvgs.GetUpperBound(0)
    		If ($iUb -gt 0)
    		{
    			For ($a = 1;$a -le $iUb;$a++)
    			{
                    $ArrayA = RemoveDashesFromArray -Array $ArrayOfQuantizedAvgs[$a]
                    $ArrayB = RemoveDashesFromArray -Array $ArrayOfQuantizedAvgs[$($a-1)]
                    If (($ArrayA -eq $null) -or ($ArrayB -eq $null))
                    {
                        $iDiff = 0
                    }
                    Else
                    {
    				    $iDiff = $ArrayA - $ArrayB
                    }
    				[void] $alDiff.Add($iDiff)
    			}
    		}
    		Else
    		{
    			Return $ArrayOfQuantizedAvgs[0]
    		}
    		
    		ForEach ($a in $alDiff)
    		{
    			$iSum = $iSum + $a
    		}
    		$iAvg = $iSum / $alDiff.Count
    		CalculateHourlyTrend -Value $iAvg -AnalysisIntervalInSeconds $AnalysisIntervalInSeconds -DataTypeAsString $DataTypeAsString
    	}
    	Else
    	{
    		$ArrayOfQuantizedAvgs
    	}
    }
    Else
    {
        Return $ArrayOfQuantizedAvgs
    }
}

Function GenerateQuantizedTrendValueArray
{
	param($ArrayOfQuantizedAvgs,$AnalysisIntervalInSeconds,$DataTypeAsString)
    If (($ArrayOfQuantizedAvgs -is [System.Collections.ArrayList]) -or ($ArrayOfQuantizedAvgs -is [System.object[]]))
    {
    	$alQuantizedValues = New-Object System.Collections.ArrayList
    	[void] $alQuantizedValues.Add(0)
    	For ($i = 1; $i -le $ArrayOfQuantizedAvgs.GetUpperBound(0);$i++)
    	{
    		$iTrendValue = CalculateTrend -ArrayOfQuantizedAvgs $ArrayOfQuantizedAvgs[0..$i] -AnalysisIntervalInSeconds $AnalysisInterval -DataTypeAsString "Integer"
    		[void] $alQuantizedValues.Add($iTrendValue)
    	}
    	$alQuantizedValues
    }
    Else
    {
        Return $ArrayOfQuantizedAvgs
    }
}

Function AddToCounterInstanceStatsArrayList
{
    param($sCounterPath,$aTime,$aValue,$alQuantizedTime,$alQuantizedMinValues,$alQuantizedAvgValues,$alQuantizedMaxValues,$alQuantizedTrendValues,$sCounterComputer,$sCounterObject,$sCounterName,$sCounterInstance, $Min='-', $Avg='-', $Max='-', $Trend='-', $StdDev='-', $PercentileSeventyth='-', $PercentileEightyth='-', $PercentileNinetyth='-')
        
    If ($htCounterInstanceStats.Contains($sCounterPath) -eq $False)
    {
    	$quantizedResultsObject = New-Object pscustomobject
    	Add-Member -InputObject $quantizedResultsObject -MemberType NoteProperty -Name CounterPath -Value $sCounterPath
        Add-Member -InputObject $quantizedResultsObject -MemberType NoteProperty -Name CounterComputer -Value $sCounterComputer
        #// Check if this is a SQL Named instance.
        If (($($sCounterPath.Contains('MSSQL$')) -eq $True) -or ($($sCounterPath.Contains('MSOLAP$')) -eq $True))
        {
            $sCounterObject = GetCounterObject $sCounterPath
        }
    	Add-Member -InputObject $quantizedResultsObject -MemberType NoteProperty -Name CounterObject -Value $sCounterObject
    	Add-Member -InputObject $quantizedResultsObject -MemberType NoteProperty -Name CounterName -Value $sCounterName
    	Add-Member -InputObject $quantizedResultsObject -MemberType NoteProperty -Name CounterInstance -Value $sCounterInstance
    	Add-Member -InputObject $quantizedResultsObject -MemberType NoteProperty -Name Time -Value $aTime
    	Add-Member -InputObject $quantizedResultsObject -MemberType NoteProperty -Name Value -Value $aValue
    	Add-Member -InputObject $quantizedResultsObject -MemberType NoteProperty -Name QuantizedTime -Value $alQuantizedTime
    	Add-Member -InputObject $quantizedResultsObject -MemberType NoteProperty -Name QuantizedMin -Value $alQuantizedMinValues
    	Add-Member -InputObject $quantizedResultsObject -MemberType NoteProperty -Name QuantizedAvg -Value $alQuantizedAvgValues
    	Add-Member -InputObject $quantizedResultsObject -MemberType NoteProperty -Name QuantizedMax -Value $alQuantizedMaxValues
        Add-Member -InputObject $quantizedResultsObject -MemberType NoteProperty -Name QuantizedTrend -Value $alQuantizedTrendValues
    	Add-Member -InputObject $quantizedResultsObject -MemberType NoteProperty -Name Min -Value $Min
        Add-Member -InputObject $quantizedResultsObject -MemberType NoteProperty -Name Avg -Value $Avg
        Add-Member -InputObject $quantizedResultsObject -MemberType NoteProperty -Name Max -Value $Max
        Add-Member -InputObject $quantizedResultsObject -MemberType NoteProperty -Name Trend -Value $Trend
        Add-Member -InputObject $quantizedResultsObject -MemberType NoteProperty -Name StdDev -Value $StdDev
        Add-Member -InputObject $quantizedResultsObject -MemberType NoteProperty -Name PercentileSeventyth -Value $PercentileSeventyth
        Add-Member -InputObject $quantizedResultsObject -MemberType NoteProperty -Name PercentileEightyth -Value $PercentileEightyth
        Add-Member -InputObject $quantizedResultsObject -MemberType NoteProperty -Name PercentileNinetyth -Value $PercentileNinetyth
    	[void] $htCounterInstanceStats.Add($sCounterPath,$quantizedResultsObject)
    }
}

Function FillNullsWithDashesAndIsAllNull
{
    param($Values)
    For ($i=0;$i -le $Values.GetUpperBound(0);$i++)
    {
        If (($Values[$i] -eq ' ') -or ($Values[$i] -eq $null))
        {
            $Values[$i] = '-'
        }
        Else
        {
            $global:IsValuesAllNull = $False
        }
    }
    $Values
}

Function AddCounterInstancesToXmlDataSource($XmlDoc,$XmlDataSource,$sCounterPath,$sCounterComputer,$sCounterObject,$sCounterName,$sCounterInstance,$iCounterInstanceInCsv)
{
	If (($global:aTime -eq '') -or ($global:aTime -eq $null))
	{
        Write-Host `t"Time data (one time only)..." -NoNewline
		$global:aTime = GetTimeDataFromPerfmonLog
        Write-Host 'Done'
	}
    $global:IsValuesAllNull = $True
    Write-Host `t"Counter data for `"$sCounterInstance`"..." -NoNewline
	$aValue = GetCounterDataFromPerfmonLog $sCounterPath $iCounterInstanceInCsv
    $aValue = FillNullsWithDashesAndIsAllNull -Values $aValue
    Write-Host 'Done'
    
    If ($global:IsAnalysisIntervalCalculated -eq $False)
    {
        ProcessAnalysisInterval $global:aTime
        $global:IsAnalysisIntervalCalculated = $True
    }
    
    If ($alQuantizedIndex -eq $null)
    {
        Write-Host `t"Quantized index (one time only)..." -NoNewline
        $global:alQuantizedIndex = @(GenerateQuantizedIndexArray -ArrayOfTimes $aTime -AnalysisIntervalInSeconds $global:AnalysisInterval)
        Write-Host 'Done'
    }
        
    If ($alQuantizedTime -eq $null)
    {
        Write-Host `t"Quantized time (one time only)..." -NoNewline
        $global:alQuantizedTime = @(GenerateQuantizedTimeArray -ArrayOfTimes $aTime -QuantizedIndexArray $alQuantizedIndex)
        Write-Host 'Done'
    }
    
    If ($global:IsValuesAllNull -eq $False)
    {        
        $MightBeArrayListOrDouble = $(MakeNumeric -Values $aValue)
        $alAllNumeric = New-Object System.Collections.ArrayList
        If (($MightBeArrayListOrDouble -is [System.Collections.ArrayList]) -or ($MightBeArrayListOrDouble -is [Array]))
        {
            [System.Collections.ArrayList] $alAllNumeric = $MightBeArrayListOrDouble
        }
        Else
        {        
            [void] $AlAllNumeric.Add($MightBeArrayListOrDouble)
        }
        #// Write-Host `t"Quantizing `"$sCounterInstance`" for Avg, Min, Max, and Trend values..." -NoNewline
    	$alQuantizedAvgValues = @(GenerateQuantizedAvgValueArray -ArrayOfValues $alAllNumeric -ArrayOfQuantizedIndexes $alQuantizedIndex -DataTypeAsString $($XmlDataSource.DATATYPE))
    	$alQuantizedMinValues = @(GenerateQuantizedMinValueArray -ArrayOfValues $alAllNumeric -ArrayOfQuantizedIndexes $alQuantizedIndex -DataTypeAsString $($XmlDataSource.DATATYPE))
    	$alQuantizedMaxValues = @(GenerateQuantizedMaxValueArray -ArrayOfValues $alAllNumeric -ArrayOfQuantizedIndexes $alQuantizedIndex -DataTypeAsString $($XmlDataSource.DATATYPE))
    	$alQuantizedTrendValues = @(GenerateQuantizedTrendValueArray -ArrayOfQuantizedAvgs $alQuantizedAvgValues -AnalysisIntervalInSeconds $AnalysisInterval -DataTypeAsString $($XmlDataSource.DATATYPE))
    	#// Write-Host 'Done'
            
        $oStats = $alAllNumeric | Measure-Object -Average -Minimum -Maximum
        $Min = $(ConvertToDataType -ValueAsDouble $oStats.Minimum -DataTypeAsString $XmlDataSource.DATATYPE)
        $Avg = $(ConvertToDataType -ValueAsDouble $oStats.Average -DataTypeAsString $XmlDataSource.DATATYPE)
        $Max = $(ConvertToDataType -ValueAsDouble $oStats.Maximum -DataTypeAsString $XmlDataSource.DATATYPE)
        $Trend = $(ConvertToDataType -ValueAsDouble $alQuantizedTrendValues[$($alQuantizedTrendValues.GetUpperBound(0))] -DataTypeAsString $XmlDataSource.DATATYPE)    
        $StdDev = $(CalculateStdDev -Values $alAllNumeric)
        $StdDev = $(ConvertToDataType -ValueAsDouble $StdDev -DataTypeAsString $XmlDataSource.DATATYPE)    
        $PercentileSeventyth = $(CalculatePercentile -Values $alAllNumeric -Percentile 70)
        $PercentileSeventyth = $(ConvertToDataType -ValueAsDouble $PercentileSeventyth -DataTypeAsString $XmlDataSource.DATATYPE)
        $PercentileEightyth = $(CalculatePercentile -Values $alAllNumeric -Percentile 80)
        $PercentileEightyth = $(ConvertToDataType -ValueAsDouble $PercentileEightyth -DataTypeAsString $XmlDataSource.DATATYPE)
        $PercentileNinetyth = $(CalculatePercentile -Values $alAllNumeric -Percentile 90)
        $PercentileNinetyth = $(ConvertToDataType -ValueAsDouble $PercentileNinetyth -DataTypeAsString $XmlDataSource.DATATYPE)    
    }
    Else
    {
        #// Write-Host `t"Quantizing `"$sCounterInstance`" for Avg, Min, Max, and Trend values..." -NoNewline
    	$alQuantizedAvgValues = '-'
    	$alQuantizedMinValues = '-'
    	$alQuantizedMaxValues = '-'
    	$alQuantizedTrendValues = '-'
    	#// Write-Host 'Done'
        
        $Min = '-'
        $Avg = '-'
        $Max = '-'
        $Trend = '-'
        $StdDev = '-'
        $StdDev = '-'
        $PercentileSeventyth = '-'
        $PercentileSeventyth = '-'
        $PercentileEightyth = '-'
        $PercentileEightyth = '-'
        $PercentileNinetyth = '-'
        $PercentileNinetyth = '-'
    }
    
    #Write-Host `t"Adding counter instance to stats array list..." -NoNewline
    AddToCounterInstanceStatsArrayList $sCounterPath $aTime $aValue $alQuantizedTime $alQuantizedMinValues $alQuantizedAvgValues $alQuantizedMaxValues $alQuantizedTrendValues $sCounterComputer $sCounterObject $sCounterName $sCounterInstance $Min $Avg $Max $Trend $StdDev $PercentileSeventyth $PercentileEightyth $PercentileNinetyth
    #Write-Host 'Done'

    $XmlNewCounterInstance = $XmlAnalysis.CreateElement("COUNTERINSTANCE")
    $XmlNewCounterInstance.SetAttribute("NAME", $sCounterPath)
    #$XmlNewCounterInstance.SetAttribute("TIME", $([string]::Join(',',$aTime)))
    #$XmlNewCounterInstance.SetAttribute("VALUE", $([string]::Join(',',$aValue)))
	#$XmlNewCounterInstance.SetAttribute("QUANTIZEDVALUE", $([string]::Join(',',$alQuantizedTime)))
    $XmlNewCounterInstance.SetAttribute("MIN", $([string]::Join(',',$Min)))
    $XmlNewCounterInstance.SetAttribute("AVG", $([string]::Join(',',$Avg)))
    $XmlNewCounterInstance.SetAttribute("MAX", $([string]::Join(',',$Max)))
    $XmlNewCounterInstance.SetAttribute("TREND", $([string]::Join(',',$Trend)))
    $XmlNewCounterInstance.SetAttribute("STDDEV", $([string]::Join(',',$StdDev)))
    $XmlNewCounterInstance.SetAttribute("PERCENTILESEVENTYTH", $([string]::Join(',',$PercentileSeventyth)))
    $XmlNewCounterInstance.SetAttribute("PERCENTILEEIGHTYTH", $([string]::Join(',',$PercentileEightyth)))
    $XmlNewCounterInstance.SetAttribute("PERCENTILENINETYTH", $([string]::Join(',',$PercentileNinetyth)))
    $XmlNewCounterInstance.SetAttribute("QUANTIZEDMIN", $([string]::Join(',',$alQuantizedMinValues)))
    $XmlNewCounterInstance.SetAttribute("QUANTIZEDAVG", $([string]::Join(',',$alQuantizedAvgValues)))
    $XmlNewCounterInstance.SetAttribute("QUANTIZEDMAX", $([string]::Join(',',$alQuantizedMaxValues)))
    $XmlNewCounterInstance.SetAttribute("QUANTIZEDTREND", $([string]::Join(',',$alQuantizedTrendValues)))
    $XmlNewCounterInstance.SetAttribute("COUNTERPATH", $sCounterPath)
    $XmlNewCounterInstance.SetAttribute("COUNTERCOMPUTER", $sCounterComputer)
    If (($($sCounterPath.Contains('MSSQL$')) -eq $True) -or ($($sCounterPath.Contains('MSOLAP$')) -eq $True))
    {
        $sCounterObject = GetCounterObject $sCounterPath
    }
    $XmlNewCounterInstance.SetAttribute("COUNTEROBJECT", $sCounterObject)
    $XmlNewCounterInstance.SetAttribute("COUNTERNAME", $sCounterName)
    $XmlNewCounterInstance.SetAttribute("COUNTERINSTANCE", $sCounterInstance)
    $XmlNewCounterInstance.SetAttribute("ISALLNULL", $global:IsValuesAllNull)
    [void] $XmlDataSource.AppendChild($XmlNewCounterInstance)    
}

Function GetCounterInstancesAndGenerateCounterStats($XmlDoc,$XmlDataSource)
{	
    #Write-Host 'Get-CounterInstances' $XmlDataSource.EXPRESSIONPATH
    $sDsCounterObject = GetCounterObject -sCounterPath $XmlDataSource.EXPRESSIONPATH
    $sDsCounterName = GetCounterName -sCounterPath $XmlDataSource.EXPRESSIONPATH
    $sDsCounterInstance = GetCounterInstance -sCounterPath $XmlDataSource.EXPRESSIONPATH
	$iCounterIndexInCsv = 0
    If ($global:aCounterLogCounterList -eq "")
    { 
		Write-Host `t"Getting the counter list from the perfmon log..." -NoNewline
       	$global:aCounterLogCounterList = GetCounterListFromCsvAsText $global:sPerfLogFilePath
		Write-Host "Done" 
    }
    #$global:XmlCounterLogCounterInstanceList.Save('.\XmlCounterlist.xml')
	#Write-Host `t"Matching the counters to counter instances" -NoNewline
    If ($(Test-XmlBoolAttribute -InputObject $XmlDataSource -Name 'ISCOUNTEROBJECTREGULAREXPRESSION') -eq $True)
    {
        $IsCounterObjectRegularExpression = $True
    }
    Else
    {
        $IsCounterObjectRegularExpression = $False
    }

    If ($(Test-XmlBoolAttribute -InputObject $XmlDataSource -Name 'ISCOUNTERNAMEREGULAREXPRESSION') -eq $True)
    {
        $IsCounterNameRegularExpression = $True
    }
    Else
    {
        $IsCounterNameRegularExpression = $False
    } 
    
    If ($(Test-XmlBoolAttribute -InputObject $XmlDataSource -Name 'ISCOUNTERINSTANCEREGULAREXPRESSION') -eq $True)
    {
        $IsCounterInstanceRegularExpression = $True
    }
    Else
    {
        $IsCounterInstanceRegularExpression = $False
    }         
    
    :CounterComputerLoop ForEach ($XmlCounterComputerNode in $global:XmlCounterLogCounterInstanceList.SelectNodes('//COUNTERCOMPUTER'))
    {
        :CounterObjectLoop ForEach ($XmlCounterObjectNode in $XmlCounterComputerNode.ChildNodes)
        {
            $IsCounterObjectMatch = $False
            If ($IsCounterObjectRegularExpression -eq $True)
            {
                $sDsCounterObject = GetCounterObject -sCounterPath $XmlDataSource.REGULAREXPRESSIONCOUNTERPATH
                If ($XmlCounterObjectNode.NAME -match $sDsCounterObject)
                {
                    $IsCounterObjectMatch = $True
                }
            }
            Else
            {
                If ($XmlCounterObjectNode.NAME -eq $sDsCounterObject)
                {
                    $IsCounterObjectMatch = $True
                }
            }
            If ($IsCounterObjectMatch -eq $True)
            {
                :CounterNameLoop ForEach ($XmlCounterNameNode in $XmlCounterObjectNode.ChildNodes)
                {
                    $IsCounterNameMatch = $False
                    If ($IsCounterNameRegularExpression -eq $True)
                    {
                        $sDsCounterName = GetCounterName -sCounterPath $XmlDataSource.REGULAREXPRESSIONCOUNTERPATH
                        If ($XmlCounterNameNode.NAME -match $sDsCounterName)
                        {
                            $IsCounterNameMatch = $True
                        }
                    }
                    Else
                    {
                        If ($XmlCounterNameNode.NAME -eq $sDsCounterName)
                        {
                            $IsCounterNameMatch = $True
                        }
                    }
                    If ($IsCounterNameMatch -eq $True)
                    {
                        :CounterInstanceLoop ForEach ($XmlCounterInstanceNode in $XmlCounterNameNode.ChildNodes)
                        {
                            $IsCounterInstanceMatch = $False
                            If (($sDsCounterInstance -eq '') -OR ($sDsCounterInstance -eq '*'))
                            {
                                $IsCounterInstanceMatch = $True                                
                            }
                            Else
                            {
                                If ($IsCounterInstanceRegularExpression -eq $True)
                                {
                                    If ($XmlCounterInstanceNode.NAME -match $sDsCounterInstance)
                                    {
                                        $IsCounterInstanceMatch = $True
                                    }
                                }
                                Else
                                {
                                    If ($sDsCounterInstance -eq $XmlCounterInstanceNode.NAME)
                                    {
                                        $IsCounterInstanceMatch = $True
                                    }
                                }
                            
                            }
                            If ($IsCounterInstanceMatch -eq $True)
                            {
                                ForEach ($XmlExcludeNode in $XmlDataSource.SelectNodes('./EXCLUDE'))
                                {
                                    If ($XmlExcludeNode.INSTANCE -eq $XmlCounterInstanceNode.NAME)
                                    {
                                        $IsCounterInstanceMatch = $False
                                    }
                                }
                            }                            
                            If ($IsCounterInstanceMatch -eq $True)
                            {
                                $iCounterIndexInCsv = [System.Int32]$XmlCounterInstanceNode.COUNTERLISTINDEX
                                 #// Add counter instances to XML node.
                                #Write-Host `t`t`t"Adding counter instance to Xml data source" -NoNewline
                                AddCounterInstancesToXmlDataSource $XmlDoc $XmlDataSource $XmlCounterInstanceNode.COUNTERPATH $XmlCounterComputerNode.NAME $XmlCounterObjectNode.NAME $XmlCounterNameNode.NAME $XmlCounterInstanceNode.NAME $iCounterIndexInCsv
                                #Write-Host "Done" -NoNewline
                            }
                        }
                        #break CounterObjectLoop
                    }
                }
            }
        }        
    }
}

Function GetDataSourceData($XmlDoc, $XmlAnalysisInstance, $XmlDataSource)
{
	GetCounterInstancesAndGenerateCounterStats $XmlDoc $XmlDataSource
}

Function GetQuantizedTimeSliceTimeRange
{
    param($TimeSliceIndex)
    $u = $alQuantizedTime.Count - 1
    If ($TimeSliceIndex -ge $u)
    {
    	#//[string] $DateDifference = '-'       
    	$LastTimeSlice = $alQuantizedTime[$u]
    	$EndTime = $alQuantizedTime[$u].AddSeconds($AnalysisInterval)
        $Date1 = Get-Date $([datetime]$alQuantizedTime[$u]) -format $global:sDateTimePattern
        $Date2 = Get-Date $([datetime]$EndTime) -format $global:sDateTimePattern
        [string] $ResultTimeRange = "$Date1" + ' - ' + "$Date2"
    }
    Else
    {
        #$Date1 = Get-Date $($alQuantizedTime[$TimeSliceIndex]) -format "MM/dd/yyyy HH:mm:ss"
        #$Date2 = Get-Date $($alQuantizedTime[$TimeSliceIndex+1]) -format "MM/dd/yyyy HH:mm:ss"
        $Date1 = Get-Date $([datetime]$alQuantizedTime[$TimeSliceIndex]) -format $global:sDateTimePattern
        $Date2 = Get-Date $([datetime]$alQuantizedTime[$TimeSliceIndex+1]) -format $global:sDateTimePattern
        [string] $ResultTimeRange = "$Date1" + ' - ' + "$Date2"
    }
    $ResultTimeRange
}

Function CreateAlert
{
    param($TimeSliceIndex,$CounterInstanceObject,$IsMinThresholdBroken=$False,$IsAvgThresholdBroken=$False,$IsMaxThresholdBroken=$False,$IsTrendThresholdBroken=$False,$IsMinEvaluated=$False,$IsAvgEvaluated=$False,$IsMaxEvaluated=$False,$IsTrendEvaluated=$False)
    #// The following are provided via global variables to make it simple for users to use.
    #$global:CurrentXmlAnalysisInstance = $XmlAnalysisInstance
    #$global:ThresholdName = $XmlThreshold.NAME
    #$global:ThresholdCondition = $XmlThreshold.CONDITION
    #$global:ThresholdColor = $XmlThreshold.COLOR
    #$global:ThresholdPriority = $XmlThreshold.PRIORITY
    #$global:ThresholdAnalysisID = $XmlAnalysisInstance.ID
    #$global:IsMinEvaulated = $False
    #$global:IsAvgEvaulated = $False
    #$global:IsMaxEvaulated = $False
    #$global:IsTrendEvaulated = $False    
    
    [string] $sCounterInstanceName = $CounterInstanceObject.CounterPath
    If ($($sCounterInstanceName.Contains('INTERNAL_OVERALL_COUNTER_STATS')) -eq $True)
    {
        $IsInternalOnly = $True
    }
    Else
    {
        $IsInternalOnly = $False
    }
    
    $IsSameCounterAlertFound = $False
    :XmlAlertLoop ForEach ($XmlAlert in $CurrentXmlAnalysisInstance.SelectNodes('./ALERT'))
    {
        If (($XmlAlert.TIMESLICEINDEX -eq $TimeSliceIndex) -and ($XmlAlert.COUNTER -eq $CounterInstanceObject.CounterPath))
        {
            #// Update alert
            If ($([int] $ThresholdPriority) -ge $([int] $XmlAlert.CONDITIONPRIORITY))
            {
                $XmlAlert.CONDITIONCOLOR = $ThresholdColor
                $XmlAlert.CONDITION = $ThresholdCondition
                $XmlAlert.CONDITIONNAME = $ThresholdName
                $XmlAlert.CONDITIONPRIORITY = $ThresholdPriority
            }

            If ($IsMinThresholdBroken -eq $True)
            {
                If ($([int] $ThresholdPriority) -ge $([int] $XmlAlert.MINPRIORITY))
                {
                    $XmlAlert.MINCOLOR = $ThresholdColor
                    $XmlAlert.MINPRIORITY = $ThresholdPriority
                    #// $XmlAlert.MINEVALUATED = 'True'
                }
            }
            
            If ($IsAvgThresholdBroken -eq $True)
            {
                If ($([int] $ThresholdPriority) -ge $([int] $XmlAlert.AVGPRIORITY))
                {
                    $XmlAlert.AVGCOLOR = $ThresholdColor
                    $XmlAlert.AVGPRIORITY = $ThresholdPriority
                    #// $XmlAlert.AVGEVALUATED = 'True'
                }
            }
            
            If ($IsMaxThresholdBroken -eq $True)
            {
                If ($([int] $ThresholdPriority) -ge $([int] $XmlAlert.MAXPRIORITY))
                {
                    $XmlAlert.MAXCOLOR = $ThresholdColor
                    $XmlAlert.MAXPRIORITY = $ThresholdPriority
                    #// $XmlAlert.MAXEVALUATED = 'True'
                }
            }
            
            If ($IsTrendThresholdBroken -eq $True)
            {
                If ($([int] $ThresholdPriority) -ge $([int] $XmlAlert.TRENDPRIORITY))
                {
                    $XmlAlert.TRENDCOLOR = $ThresholdColor
                    $XmlAlert.TRENDPRIORITY = $ThresholdPriority
                    #// $XmlAlert.TRENDEVALUATED = 'True'
                }
            }
            $IsSameCounterAlertFound = $True
            Break XmlAlertLoop
        }
    }
    
    If ($IsSameCounterAlertFound -eq $False)
    {        
        #// Add the alert
        $XmlNewAlert = $XmlAnalysis.CreateElement("ALERT")
        $XmlNewAlert.SetAttribute("TIMESLICEINDEX", $TimeSliceIndex)
        $XmlNewAlert.SetAttribute("TIMESLICERANGE", $(GetQuantizedTimeSliceTimeRange -TimeSliceIndex $TimeSliceIndex))
        $XmlNewAlert.SetAttribute("CONDITIONCOLOR", $ThresholdColor)
        $XmlNewAlert.SetAttribute("CONDITION", $ThresholdCondition)
        $XmlNewAlert.SetAttribute("CONDITIONNAME", $ThresholdName)
        $XmlNewAlert.SetAttribute("CONDITIONPRIORITY", $ThresholdPriority)
        $XmlNewAlert.SetAttribute("COUNTER", $CounterInstanceObject.CounterPath)
        $XmlNewAlert.SetAttribute("PARENTANALYSIS", $($CurrentXmlAnalysisInstance.NAME))
        $XmlNewAlert.SetAttribute("ISINTERNALONLY", $IsInternalOnly)
        
        If ($IsMinThresholdBroken -eq $True)
        {
            $XmlNewAlert.SetAttribute("MINCOLOR", $ThresholdColor)
            $XmlNewAlert.SetAttribute("MINPRIORITY", $ThresholdPriority)
            #// $XmlNewAlert.SetAttribute("MINEVALUATED", 'True')
        }
        Else
        {
            If ($IsMinEvaulated -eq $True)
            {
                #// 00FF00 is a light green
                #$XmlNewAlert.SetAttribute("MINCOLOR", '#00FF00')
                $XmlNewAlert.SetAttribute("MINCOLOR", 'White')
                $XmlNewAlert.SetAttribute("MINPRIORITY", '0')
                #// $XmlNewAlert.SetAttribute("MINEVALUATED", 'True')
            }
            Else
            {
                $XmlNewAlert.SetAttribute("MINCOLOR", 'White')
                $XmlNewAlert.SetAttribute("MINPRIORITY", '0')
            }
        }
        
        If ($IsAvgThresholdBroken -eq $True)
        {
            $XmlNewAlert.SetAttribute("AVGCOLOR", $ThresholdColor)
            $XmlNewAlert.SetAttribute("AVGPRIORITY", $ThresholdPriority)
            #// $XmlNewAlert.SetAttribute("AVGEVALUATED", 'True')
        }
        Else
        {
            If ($IsAvgEvaulated -eq $True)
            {
                #// 00FF00 is a light green
                #$XmlNewAlert.SetAttribute("AVGCOLOR", '#00FF00')
                $XmlNewAlert.SetAttribute("AVGCOLOR", 'White')
                $XmlNewAlert.SetAttribute("AVGPRIORITY", '0')
                #// $XmlNewAlert.SetAttribute("AVGEVALUATED", 'True')
            }
            Else
            {
                $XmlNewAlert.SetAttribute("AVGCOLOR", 'White')
                $XmlNewAlert.SetAttribute("AVGPRIORITY", '0')
            }
        }
        
        If ($IsMaxThresholdBroken -eq $True)
        {
            $XmlNewAlert.SetAttribute("MAXCOLOR", $ThresholdColor)
            $XmlNewAlert.SetAttribute("MAXPRIORITY", $ThresholdPriority)
            #// $XmlNewAlert.SetAttribute("MAXEVALUATED", 'True')
        }
        Else
        {
            If ($IsMaxEvaulated -eq $True)
            {
                #// 00FF00 is a light green
                #$XmlNewAlert.SetAttribute("MAXCOLOR", '#00FF00')
                $XmlNewAlert.SetAttribute("MAXCOLOR", 'White')
                $XmlNewAlert.SetAttribute("MAXPRIORITY", '0')
                #// $XmlNewAlert.SetAttribute("MAXEVALUATED", 'True')
            }
            Else
            {
                $XmlNewAlert.SetAttribute("MAXCOLOR", 'White')
                $XmlNewAlert.SetAttribute("MAXPRIORITY", '0')
            }
        }
        
        If ($IsTrendThresholdBroken -eq $True)
        {
            $XmlNewAlert.SetAttribute("TRENDCOLOR", $ThresholdColor)
            $XmlNewAlert.SetAttribute("TRENDPRIORITY", $ThresholdPriority)
            #// $XmlNewAlert.SetAttribute("TRENDEVALUATED", 'True')
        }
        Else
        {
            If ($IsTrendEvaulated -eq $True)
            {
                #// 00FF00 is a light green
                #$XmlNewAlert.SetAttribute("TRENDCOLOR", '#00FF00')
                $XmlNewAlert.SetAttribute("TRENDCOLOR", 'White')
                $XmlNewAlert.SetAttribute("TRENDPRIORITY", '0')
                #// $XmlNewAlert.SetAttribute("TRENDEVALUATED", 'True')
            }
            Else
            {
                $XmlNewAlert.SetAttribute("TRENDCOLOR", 'White')
                $XmlNewAlert.SetAttribute("TRENDPRIORITY", '0')
            }
        }
        $XmlNewAlert.SetAttribute("MIN", $($CounterInstanceObject.QuantizedMin[$TimeSliceIndex]))
        $XmlNewAlert.SetAttribute("AVG", $($CounterInstanceObject.QuantizedAvg[$TimeSliceIndex]))
        $XmlNewAlert.SetAttribute("MAX", $($CounterInstanceObject.QuantizedMax[$TimeSliceIndex]))
        $XmlNewAlert.SetAttribute("TREND", $($CounterInstanceObject.QuantizedTrend[$TimeSliceIndex]))
        [void] $CurrentXmlAnalysisInstance.AppendChild($XmlNewAlert)
    }
}

Function StaticChartThreshold
{
    param($CollectionOfCounterInstances,$MinThreshold,$MaxThreshold,$UseMaxValue=$True,$IsOperatorGreaterThan=$True)
    
    If ($IsOperatorGreaterThan -eq $True)
    {
        ForEach ($CounterInstanceOfCollection in $CollectionOfCounterInstances)
        {
            If (($CounterInstanceOfCollection.Max -gt $MaxThreshold) -and ($UseMaxValue -eq $True))
            {
                $MaxThreshold = $CounterInstanceOfCollection.Max
            }
        }
    }
    Else
    {
        ForEach ($CounterInstanceOfCollection in $CollectionOfCounterInstances)
        {
            If (($CounterInstanceOfCollection.Min -lt $MinThreshold) -and ($UseMaxValue -eq $True))
            {
                $MinThreshold = $CounterInstanceOfCollection.Min
            }
        }    
    }
    
    :ChartCodeLoop ForEach ($CounterInstanceOfCollection in $CollectionOfCounterInstances)
    {
        ForEach ($iValue in $CounterInstanceOfCollection.Value)
        {
            [void] $MinSeriesCollection.Add($MinThreshold)
            [void] $MaxSeriesCollection.Add($MaxThreshold)
        }
        Break ChartCodeLoop
    }
}

Function StaticThreshold
{
    param($CollectionOfCounterInstances,$Operator,$Threshold,$IsTrendOnly=$False)
    
    For ($i=0;$i -lt $CollectionOfCounterInstances.Count;$i++)
    {
        $oCounterInstance = $CollectionOfCounterInstances[$i]
        
        For ($t=0;$t -lt $alQuantizedTime.Count;$t++)
        {
            $IsMinThresholdBroken = $False
            $IsAvgThresholdBroken = $False
            $IsMaxThresholdBroken = $False
            $IsTrendThresholdBroken = $False
            $IsMinEvaulated = $False
            $IsAvgEvaulated = $False
            $IsMaxEvaulated = $False
            $IsTrendEvaulated = $False
            
            If ($IsTrendOnly -eq $False)
            {
                #/////////////////////////
                #// IsMinThresholdBroken
                #/////////////////////////
                If (($oCounterInstance.QuantizedMin[$t] -ne '-') -and ($oCounterInstance.QuantizedMin[$t] -ne $null))
                {
    				switch ($Operator)
                    {
                        'gt'
                        {
                            If ($oCounterInstance.QuantizedMin[$t] -gt $Threshold)
                            {
                                $IsMinThresholdBroken = $True
                            }
                    	}
                        'ge'
                        {
                            If ($oCounterInstance.QuantizedMin[$t] -ge $Threshold)
                            {
                                $IsMinThresholdBroken = $True
                            }
                    	}
                    	'lt'
                        {
                            If ($oCounterInstance.QuantizedMin[$t] -lt $Threshold)
                            {
                                $IsMinThresholdBroken = $True
                            }
                    	}
                        'le'
                        {
                            If ($oCounterInstance.QuantizedMin[$t] -le $Threshold)
                            {
                                $IsMinThresholdBroken = $True
                            }
                    	}
                    	'eq'
                        {
                            If ($oCounterInstance.QuantizedMin[$t] -eq $Threshold)
                            {
                                $IsMinThresholdBroken = $True
                            }
                    	}
                    	default
                        {
                            If ($oCounterInstance.QuantizedMin[$t] -gt $Threshold)
                            {
                                $IsMinThresholdBroken = $True
                            }                    
                    	}
                    }
                }
                #/////////////////////////
                #// IsAvgThresholdBroken
                #/////////////////////////
                If (($oCounterInstance.QuantizedAvg[$t] -ne '-') -and ($oCounterInstance.QuantizedAvg[$t] -ne $null))
                {
    				switch ($Operator)
                    {
                        'gt'
                        {
                            If ($oCounterInstance.QuantizedAvg[$t] -gt $Threshold)
                            {
                                $IsAvgThresholdBroken = $True
                            }
                    	}
                        'ge'
                        {
                            If ($oCounterInstance.QuantizedAvg[$t] -ge $Threshold)
                            {
                                $IsAvgThresholdBroken = $True
                            }
                    	}
                    	'lt'
                        {
                            If ($oCounterInstance.QuantizedAvg[$t] -lt $Threshold)
                            {
                                $IsAvgThresholdBroken = $True
                            }
                    	}
                        'le'
                        {
                            If ($oCounterInstance.QuantizedAvg[$t] -le $Threshold)
                            {
                                $IsAvgThresholdBroken = $True
                            }
                    	}
                    	'eq'
                        {
                            If ($oCounterInstance.QuantizedAvg[$t] -eq $Threshold)
                            {
                                $IsAvgThresholdBroken = $True
                            }
                    	}
                    	default
                        {
                            If ($oCounterInstance.QuantizedAvg[$t] -gt $Threshold)
                            {
                                $IsAvgThresholdBroken = $True
                            }                    
                    	}
                    }
                }            
                #/////////////////////////
                #// IsMaxThresholdBroken
                #/////////////////////////
                If (($oCounterInstance.QuantizedMax[$t] -ne '-') -and ($oCounterInstance.QuantizedMax[$t] -ne $null))
                {
    				switch ($Operator)
                    {
                        'gt'
                        {
                            If ($oCounterInstance.QuantizedMax[$t] -gt $Threshold)
                            {
                                $IsMaxThresholdBroken = $True
                            }
                    	}
                        'ge'
                        {
                            If ($oCounterInstance.QuantizedMax[$t] -ge $Threshold)
                            {
                                $IsMaxThresholdBroken = $True
                            }
                    	}
                    	'lt'
                        {
                            If ($oCounterInstance.QuantizedMax[$t] -lt $Threshold)
                            {
                                $IsMaxThresholdBroken = $True
                            }
                    	}
                        'le'
                        {
                            If ($oCounterInstance.QuantizedMax[$t] -le $Threshold)
                            {
                                $IsMaxThresholdBroken = $True
                            }
                    	}
                    	'eq'
                        {
                            If ($oCounterInstance.QuantizedMax[$t] -eq $Threshold)
                            {
                                $IsMaxThresholdBroken = $True
                            }
                    	}
                    	default
                        {
                            If ($oCounterInstance.QuantizedMax[$t] -gt $Threshold)
                            {
                                $IsMaxThresholdBroken = $True
                            }                    
                    	}
                    }
                }
            }
            Else
            {
                #/////////////////////////
                #// IsTrendThresholdBroken
                #/////////////////////////
                If (($oCounterInstance.QuantizedTrend[$t] -ne '-') -and ($oCounterInstance.QuantizedTrend[$t] -ne $null))
                {
    				switch ($Operator)
                    {
                        'gt'
                        {
                            If ($oCounterInstance.QuantizedTrend[$t] -gt $Threshold)
                            {
                                $IsTrendThresholdBroken = $True
                            }
                    	}
                        'ge'
                        {
                            If ($oCounterInstance.QuantizedTrend[$t] -ge $Threshold)
                            {
                                $IsTrendThresholdBroken = $True
                            }
                    	}
                    	'lt'
                        {
                            If ($oCounterInstance.QuantizedTrend[$t] -lt $Threshold)
                            {
                                $IsTrendThresholdBroken = $True
                            }
                    	}
                        'le'
                        {
                            If ($oCounterInstance.QuantizedTrend[$t] -le $Threshold)
                            {
                                $IsTrendThresholdBroken = $True
                            }
                    	}
                    	'eq'
                        {
                            If ($oCounterInstance.QuantizedTrend[$t] -eq $Threshold)
                            {
                                $IsTrendThresholdBroken = $True
                            }
                    	}
                    	default
                        {
                            If ($oCounterInstance.QuantizedTrend[$t] -gt $Threshold)
                            {
                                $IsTrendThresholdBroken = $True
                            }                    
                    	}
                    }
                }
            }
            If (($IsMinThresholdBroken -eq $True) -or ($IsAvgThresholdBroken -eq $True) -or ($IsMaxThresholdBroken -eq $True) -or ($IsTrendThresholdBroken -eq $True))
            {
                CreateAlert -TimeSliceIndex $t -CounterInstanceObject $oCounterInstance -IsMinThresholdBroken $IsMinThresholdBroken -IsAvgThresholdBroken $IsAvgThresholdBroken -IsMaxThresholdBroken $IsMaxThresholdBroken -IsTrendThresholdBroken $IsTrendThresholdBroken -IsMinEvaluated $IsMinEvaulated -IsAvgEvaluated $IsAvgEvaulated -IsMaxEvaluated $IsMaxEvaulated -IsTrendEvaluated $IsTrendEvaulated
            }
        }
    }
}

Function StaticTrendThreshold
{
    param($CollectionOfCounterInstances,$Operator,$Threshold,$IsTrendOnly=$False)
    StaticThreshold -CollectionOfCounterInstances $CollectionOfCounterInstances -Operator $Operator -Threshold $Threshold -IsTrendOnly $True
}

Function ExecuteCodeForThreshold
{
    param($Code,$Name,$htVariables,$htQuestionVariables)
    $global:IsMinThresholdBroken = $False
    $global:IsAvgThresholdBroken = $False
    $global:IsMaxThresholdBroken = $False
    $global:IsTrendThresholdBroken = $False
    $global:IsMinEvaluated = $False
    $global:IsAvgEvaluated = $False
    $global:IsMaxEvaluated = $False
    $global:IsTrendEvaluated = $False
    #'Code after changes:' >> CodeDebug.txt
    #'===================' >> CodeDebug.txt
    #$sCode >> CodeDebug.txt
    Invoke-Expression -Command $sCode
}

Function ExecuteCodeForGeneratedDataSource
{
    param($Code,$Name,$ExpressionPath,$htVariables,$htQuestionVariables)
    #'Code after changes:' >> CodeDebug.txt
    #'===================' >> CodeDebug.txt
    #$sCode >> CodeDebug.txt
    Invoke-Expression -Command $sCode
}

Function GenerateDataSourceData($XmlAnalysis, $XmlAnalysisInstance, $XmlGeneratedDataSource)
{
	#// Add a code replacement for the generated data source collection
	$alGeneratedDataSourceCollection = New-Object System.Collections.ArrayList
	[void] $htVariables.Add($XmlGeneratedDataSource.COLLECTIONVARNAME,$alGeneratedDataSourceCollection)
	$sCollectionName = $XmlGeneratedDataSource.COLLECTIONVARNAME
	$sCollectionNameWithBackslash = "\`$$sCollectionName"
	$sCollectionNameWithDoubleQuotes = "`"$sCollectionName`""
	$sCollectionVarName = "`$htVariables[$sCollectionNameWithDoubleQuotes]"
	[void] $htCodeReplacements.Add($sCollectionNameWithBackslash,$sCollectionVarName)
        
#    #// Expose the Generated Data Source EXPRESSIONPATH as a variable.
#    $sKey = "ExpressionPath"
#    $htVariables.Add($sKey,$XmlGeneratedDataSource.EXPRESSIONPATH)
#    $sModifiedKey = "\`$$sKey"
#    $sKeyWithDoubleQuotes = "`"$sKey`""
#    $sModifiedVarName = "`$htVariables[$sKeyWithDoubleQuotes]"
#    $htCodeReplacements.Add($sModifiedKey,$sModifiedVarName)
	$ExpressionPath = $XmlGeneratedDataSource.EXPRESSIONPATH
        
#    #// Expose the Generated Data Source NAME as a variable.
#    $sKey = "Name"
#    $htVariables.Add($sKey,$XmlGeneratedDataSource.NAME)
#    $sModifiedKey = "\`$$sKey"
#    $sKeyWithDoubleQuotes = "`"$sKey`""
#    $sModifiedVarName = "`$htVariables[$sKeyWithDoubleQuotes]"
#    $htCodeReplacements.Add($sModifiedKey,$sModifiedVarName)
	$Name = $XmlGeneratedDataSource.NAME
            
	ForEach ($XmlCode in $XmlGeneratedDataSource.SelectNodes("./CODE"))
	{
		$sCode = $XmlCode.get_innertext()
		#'Code before changes:' >> CodeDebug.txt
		#'====================' >> CodeDebug.txt
		#$sCode >> CodeDebug.txt            
		#// Replace all of the variables with their hash table version.
		ForEach ($sKey in $htCodeReplacements.Keys)
		{
			$sCode = $sCode -Replace $sKey,$htCodeReplacements[$sKey]
		}
		#// Execute the code
		ExecuteCodeForGeneratedDataSource -Code $sCode -Name $Name -ExpressionPath $ExpressionPath -htVariables $htVariables -htQuestionVariables $htQuestionVariables        
		Break #// Only execute one block of code, so breaking out.
	}
    $alNewGeneratedCounters = New-Object System.Collections.ArrayList    
   ForEach ($sKey in $htVariables[$XmlGeneratedDataSource.COLLECTIONVARNAME].Keys)
   {                    
		$aValue = $htVariables[$XmlGeneratedDataSource.COLLECTIONVARNAME][$sKey]       
		If ($alQuantizedIndex -eq $null)
		{
			$alQuantizedIndex = GenerateQuantizedIndexArray -ArrayOfTimes $aTime -AnalysisIntervalInSeconds $AnalysisInterval
		}
		If ($global:alQuantizedTime -eq $null)
		{
			$global:alQuantizedTime = GenerateQuantizedTimeArray -ArrayOfTimes $aTime -QuantizedIndexArray $alQuantizedIndex
		}       
		
        $MightBeArrayListOrDouble = $(MakeNumeric -Values $aValue)
        $alAllNumeric = New-Object System.Collections.ArrayList
        If (($MightBeArrayListOrDouble -is [System.Collections.ArrayList]) -or ($MightBeArrayListOrDouble -is [Array]))
        {
            [System.Collections.ArrayList] $alAllNumeric = $MightBeArrayListOrDouble
        }
        Else
        {            
            $AlAllNumeric.Add($MightBeArrayListOrDouble)
        }
        
		$alQuantizedAvgValues = GenerateQuantizedAvgValueArray -ArrayOfValues $alAllNumeric -ArrayOfQuantizedIndexes $alQuantizedIndex -DataTypeAsString $($XmlGeneratedDataSource.DATATYPE)
		$alQuantizedMinValues = GenerateQuantizedMinValueArray -ArrayOfValues $alAllNumeric -ArrayOfQuantizedIndexes $alQuantizedIndex -DataTypeAsString $($XmlGeneratedDataSource.DATATYPE)
		$alQuantizedMaxValues = GenerateQuantizedMaxValueArray -ArrayOfValues $alAllNumeric -ArrayOfQuantizedIndexes $alQuantizedIndex -DataTypeAsString $($XmlGeneratedDataSource.DATATYPE)
		$alQuantizedTrendValues = GenerateQuantizedTrendValueArray -ArrayOfQuantizedAvgs $alQuantizedAvgValues -AnalysisIntervalInSeconds $AnalysisInterval -DataTypeAsString "Integer"

		$oStats = $alAllNumeric | Measure-Object -Average -Minimum -Maximum
		$Min = $(ConvertToDataType -ValueAsDouble $oStats.Minimum -DataTypeAsString $XmlGeneratedDataSource.DATATYPE)
		$Avg = $(ConvertToDataType -ValueAsDouble $oStats.Average -DataTypeAsString $XmlGeneratedDataSource.DATATYPE)
		$Max = $(ConvertToDataType -ValueAsDouble $oStats.Maximum -DataTypeAsString $XmlGeneratedDataSource.DATATYPE)
		$Trend = $(ConvertToDataType -ValueAsDouble $alQuantizedTrendValues[$($alQuantizedTrendValues.GetUpperBound(0))] -DataTypeAsString $XmlGeneratedDataSource.DATATYPE)
		$StdDev = $(CalculateStdDev -Values $alAllNumeric)
		$StdDev = $(ConvertToDataType -ValueAsDouble $StdDev -DataTypeAsString $XmlGeneratedDataSource.DATATYPE)
		$PercentileSeventyth = $(CalculatePercentile -Values $alAllNumeric -Percentile 70)
		$PercentileSeventyth = $(ConvertToDataType -ValueAsDouble $PercentileSeventyth -DataTypeAsString $XmlGeneratedDataSource.DATATYPE)
		$PercentileEightyth = $(CalculatePercentile -Values $alAllNumeric -Percentile 80)
		$PercentileEightyth = $(ConvertToDataType -ValueAsDouble $PercentileEightyth -DataTypeAsString $XmlGeneratedDataSource.DATATYPE)
		$PercentileNinetyth = $(CalculatePercentile -Values $alAllNumeric -Percentile 90)
		$PercentileNinetyth = $(ConvertToDataType -ValueAsDouble $PercentileNinetyth -DataTypeAsString $XmlGeneratedDataSource.DATATYPE)            
	
		$sCounterPath = $sKey
		$sCounterComputer = GetCounterComputer -sCounterPath $sCounterPath
		$sCounterObject = GetCounterObject -sCounterPath $sCounterPath
		$sCounterName = GetCounterName -sCounterPath $sCounterPath
		$sCounterInstance = GetCounterInstance -sCounterPath $sCounterPath
       
		AddToCounterInstanceStatsArrayList $sKey $aTime $aValue $alQuantizedTime $alQuantizedMinValues $alQuantizedAvgValues $alQuantizedMaxValues $alQuantizedTrendValues $sCounterComputer $sCounterObject $sCounterName $sCounterInstance $Min $Avg $Max $Trend $StdDev $PercentileSeventyth $PercentileEightyth $PercentileNinetyth
           
		$XmlNewCounterInstance = $XmlAnalysis.CreateElement("COUNTERINSTANCE")
		$XmlNewCounterInstance.SetAttribute("NAME", $sCounterPath)
		# $XmlNewCounterInstance.SetAttribute("TIME", $([string]::Join(',',$aTime)))
		# $XmlNewCounterInstance.SetAttribute("VALUE", $([string]::Join(',',$aValue)))
		$XmlNewCounterInstance.SetAttribute("MIN", $([string]::Join(',',$Min)))
		$XmlNewCounterInstance.SetAttribute("AVG", $([string]::Join(',',$Avg)))
		$XmlNewCounterInstance.SetAttribute("MAX", $([string]::Join(',',$Max)))
		$XmlNewCounterInstance.SetAttribute("TREND", $([string]::Join(',',$Trend)))
		$XmlNewCounterInstance.SetAttribute("STDDEV", $([string]::Join(',',$StdDev)))
		$XmlNewCounterInstance.SetAttribute("PERCENTILESEVENTYTH", $([string]::Join(',',$PercentileSeventyth)))
		$XmlNewCounterInstance.SetAttribute("PERCENTILEEIGHTYTH", $([string]::Join(',',$PercentileEightyth)))
		$XmlNewCounterInstance.SetAttribute("PERCENTILENINETYTH", $([string]::Join(',',$PercentileNinetyth)))            
		$XmlNewCounterInstance.SetAttribute("QUANTIZEDMIN", $([string]::Join(',',$alQuantizedMinValues)))       
		$XmlNewCounterInstance.SetAttribute("QUANTIZEDAVG", $([string]::Join(',',$alQuantizedAvgValues)))
		$XmlNewCounterInstance.SetAttribute("QUANTIZEDMAX", $([string]::Join(',',$alQuantizedMaxValues)))
		$XmlNewCounterInstance.SetAttribute("QUANTIZEDTREND", $([string]::Join(',',$alQuantizedTrendValues)))
		$XmlNewCounterInstance.SetAttribute("COUNTERPATH", $sCounterPath)
		$XmlNewCounterInstance.SetAttribute("COUNTERCOMPUTER", $sCounterComputer)
		$XmlNewCounterInstance.SetAttribute("COUNTEROBJECT", $sCounterObject)
		$XmlNewCounterInstance.SetAttribute("COUNTERNAME", $sCounterName)
		$XmlNewCounterInstance.SetAttribute("COUNTERINSTANCE", $sCounterInstance)
		[void] $XmlGeneratedDataSource.AppendChild($XmlNewCounterInstance)
        [void] $alNewGeneratedCounters.Add($htCounterInstanceStats[$sKey])      
   }
   #// Replace the collection made from the generation code so that it is the same as other counters.
   $htVariables[$XmlGeneratedDataSource.COLLECTIONVARNAME] = $alNewGeneratedCounters
}

#Function PrepareChartCodeReplacements
#{
#    param($XmlAnalysisInstance)
#    #// Generated data source, charts, and thresholds assume that all of the counterlog counters are available to it.
#	ForEach ($XmlCounterDataSource in $XmlAnalysisInstance.SelectNodes('./DATASOURCE'))
#	{       
#		If ($XmlCounterDataSource.TYPE.ToLower() -eq "generated")
#		{
#			$global:alCounterDataSourceCollection = New-Object System.Collections.ArrayList
#            ForEach ($XmlGeneratedCounterDataSourceInstance in $XmlCounterDataSource.SelectNodes("./COUNTERINSTANCE"))
#            {
#                [void] $alCounterDataSourceCollection.Add($htCounterInstanceStats[$XmlGeneratedCounterDataSourceInstance.NAME])
#            }
#            [void] $htVariables.Add($XmlCounterDataSource.COLLECTIONVARNAME,$alCounterDataSourceCollection)
#            $sCollectionName = $XmlCounterDataSource.COLLECTIONVARNAME
#            $sCollectionNameWithBackslash = "\`$$sCollectionName"
#            $sCollectionNameWithDoubleQuotes = "`"$sCollectionName`""
#            $sCollectionVarName = "`$htVariables[$sCollectionNameWithDoubleQuotes]"
#            [void] $htCodeReplacements.Add($sCollectionNameWithBackslash,$sCollectionVarName)
#		}
#	}
#}

Function AddWarningCriticalThresholdRangesToXml
{
	param($XmlChartInstance,$WarningMinValues=$null,$WarningMaxValues=$null,$CriticalMinValues=$null,$CriticalMaxValues=$null)
	
    If (($WarningMinValues -ne $null) -or ($WarningMaxValues -ne $null))
    {
    	$oMinWarningStats = $WarningMinValues | Measure-Object -Minimum
    	$oMaxWarningStats = $WarningMaxValues | Measure-Object -Maximum
    	$XmlChartInstance.SetAttribute("MINWARNINGVALUE",$($oMinWarningStats.Minimum))
    	$XmlChartInstance.SetAttribute("MAXWARNINGVALUE",$($oMaxWarningStats.Maximum))        
    }
    
    If (($CriticalMinValues -ne $null) -or ($CriticalMaxValues -ne $null))
    {
    	$oMinCriticalStats = $CriticalMinValues | Measure-Object -Minimum
    	$oMaxCriticalStats = $CriticalMaxValues | Measure-Object -Maximum
    	$XmlChartInstance.SetAttribute("MINCRITICALVALUE",$($oMinCriticalStats.Minimum))
    	$XmlChartInstance.SetAttribute("MAXCRITICALVALUE",$($oMaxCriticalStats.Maximum))
    }
}

Function ExtractSqlNamedInstanceFromCounterObjectPath
{
    param($sCounterObjectPath)
    $sSqlNamedInstance = ''
    $iLocOfSqlInstance = $sCounterObjectPath.IndexOf('$')
    If ($iLocOfSqlInstance -eq -1)
    {
        Return $sSqlNamedInstance
    }
    $iLocOfSqlInstance++
    $iLocOfColon = $sCounterObjectPath.IndexOf(':',$iLocOfSqlInstance)
    $iLenOfSqlInstance = $iLocOfColon - $iLocOfSqlInstance
    $sSqlNamedInstance = $sCounterObjectPath.SubString($iLocOfSqlInstance,$iLenOfSqlInstance)
    Return $sSqlNamedInstance
}

Function GeneratePalChart
{
	param($XmlChart,$XmlAnalysisInstance)

    $alChartFilePaths = New-Object System.Collections.ArrayList
    $aDateTimes = $aTime
    $htCounterValues = @{}
    $alOfSeries = New-Object System.Collections.ArrayList    
    
    If ($(Test-property -InputObject $XmlChart -Name 'ISTHRESHOLDSADDED') -eq $False)
    {
        SetXmlChartIsThresholdAddedAttribute -XmlChart $XmlChart
    }

    If ($XmlChart.ISTHRESHOLDSADDED -eq "True")
    {
    	#$htVariables = @{} #// a global variable now.
    	#$htCodeReplacements = @{} #// a global variable now.
		#[System.Object[]] $MinWarningThresholdValues
		#[System.Object[]] $MaxWarningThresholdValues
		#[System.Object[]] $MinCriticalThresholdValues
		#[System.Object[]] $MaxCriticalThresholdValues
		
		#// Already added by the GenerateDataSource function.
		#PrepareChartCodeReplacements -XmlAnalysisInstance $XmlAnalysisInstance
		
        $alOfChartThresholdSeries = New-Object System.Collections.ArrayList

        ForEach ($XmlChartSeries in $XmlChart.SelectNodes("./SERIES"))
        {
            #// Add a code replacement for the MIN threshold series collection
            #$alEmpty = New-Object System.Collections.ArrayList
            #[void] $htVariables.Add($XmlChartSeries.COLLECTIONMINVARNAME,$alEmpty)
            #$sCollectionName = $XmlChartSeries.COLLECTIONMINVARNAME
            #$sCollectionNameWithBackslash = "\`$$sCollectionName"
            #$sCollectionNameWithDoubleQuotes = "`"$sCollectionName`""
            #$sCollectionVarName = "`$htVariables[$sCollectionNameWithDoubleQuotes]"
            #[void] $htCodeReplacements.Add($sCollectionNameWithBackslash,$sCollectionVarName)
            
            #// Add a code replacement for the MAX threshold series collection
            #$alEmpty = New-Object System.Collections.ArrayList
            #[void] $htVariables.Add($XmlChartSeries.COLLECTIONMAXVARNAME,$alEmpty)
            #$sCollectionName = $XmlChartSeries.COLLECTIONMAXVARNAME
            #$sCollectionNameWithBackslash = "\`$$sCollectionName"
            #$sCollectionNameWithDoubleQuotes = "`"$sCollectionName`""
            #$sCollectionVarName = "`$htVariables[$sCollectionNameWithDoubleQuotes]"
            #[void] $htCodeReplacements.Add($sCollectionNameWithBackslash,$sCollectionVarName)
            
            $global:MinSeriesCollection = New-Object System.Collections.ArrayList
            $global:MaxSeriesCollection = New-Object System.Collections.ArrayList
            
            $ExpressionPath = $XmlChartSeries.NAME
            $Name = $XmlChartSeries.NAME

        	ForEach ($XmlCode in $XmlChartSeries.SelectNodes("./CODE"))
        	{
                $sCode = $XmlCode.get_innertext()
                #// Replace all of the variables with their hash table version.
                ForEach ($sKey in $htCodeReplacements.Keys)
                {
                    $sCode = $sCode -Replace $sKey,$htCodeReplacements[$sKey]
                }
                #// Execute the code
                ExecuteCodeForGeneratedDataSource -Code $sCode -Name $Name -ExpressionPath $ExpressionPath -htVariables $htVariables -htQuestionVariables $htQuestionVariables        
                Break #// Only execute one block of code, so breaking out.
        	}
            
        	$oSeriesData = New-Object pscustomobject
        	Add-Member -InputObject $oSeriesData -MemberType NoteProperty -Name Name -Value $XmlChartSeries.NAME
            #Add-Member -InputObject $oSeriesData -MemberType NoteProperty -Name MinValues -Value $htVariables[$XmlChartSeries.COLLECTIONMINVARNAME]
            #Add-Member -InputObject $oSeriesData -MemberType NoteProperty -Name MaxValues -Value $htVariables[$XmlChartSeries.COLLECTIONMAXVARNAME]
            Add-Member -InputObject $oSeriesData -MemberType NoteProperty -Name MinValues -Value $MinSeriesCollection
            Add-Member -InputObject $oSeriesData -MemberType NoteProperty -Name MaxValues -Value $MaxSeriesCollection
            
            [void] $alOfChartThresholdSeries.Add($oSeriesData)        
        }
    
        $IsWarningThresholds = $False
        $IsCriticalThreshols = $False
        ForEach ($oChartThresholdSeriesInstance in $alOfChartThresholdSeries)
        {
            If ($oChartThresholdSeriesInstance.Name -eq "Warning")
            {
                $IsWarningThresholds = $True
                $MinWarningThresholdValues = $oChartThresholdSeriesInstance.MinValues
                $MaxWarningThresholdValues = $oChartThresholdSeriesInstance.MaxValues
            }
            If ($oChartThresholdSeriesInstance.Name -eq "Critical")
            {
                $IsCriticalThreshols = $True
                $MinCriticalThresholdValues = $oChartThresholdSeriesInstance.MinValues
                $MaxCriticalThresholdValues = $oChartThresholdSeriesInstance.MaxValues
            }
        }
		
        If (($IsCriticalThreshols -eq $True) -and ($IsWarningThresholds -eq $True))
        {
            AddWarningCriticalThresholdRangesToXml -XmlChartInstance $XmlChart -WarningMinValues $MinWarningThresholdValues -WarningMaxValues $MaxWarningThresholdValues -CriticalMinValues $MinCriticalThresholdValues -CriticalMaxValues $MaxCriticalThresholdValues
        }
        Else
        {
            If ($IsCriticalThreshols -eq $True)
            {
                AddWarningCriticalThresholdRangesToXml -XmlChartInstance $XmlChart -CriticalMinValues $MinCriticalThresholdValues -CriticalMaxValues $MaxCriticalThresholdValues
            }
            Else
            {
                AddWarningCriticalThresholdRangesToXml -XmlChartInstance $XmlChart -WarningMinValues $MinWarningThresholdValues -WarningMaxValues $MaxWarningThresholdValues
            }
        }		
		
        #// Populate $htCounterValues
        ForEach ($XmlCounterDataSource in $XmlAnalysisInstance.SelectNodes("./DATASOURCE"))
        {
            If ($XmlChart.DATASOURCE -eq $XmlCounterDataSource.EXPRESSIONPATH)
            {
                ForEach ($XmlDataSourceCounterInstance in $XmlCounterDataSource.SelectNodes("./COUNTERINSTANCE"))
                {
                    If ($(Test-XmlBoolAttribute -InputObject $XmlDataSourceCounterInstance -Name 'ISALLNULL') -eq $True)
                    {
                        $IsAllNull = $True
                    }
                    Else
                    {
                        $IsAllNull = $False
                    }
                    
                    If ($IsAllNull -eq $False)
                    {
                        $aValues = $htCounterInstanceStats[$XmlDataSourceCounterInstance.NAME].Value
                        #// Check if this is a named instance of SQL Server
                        If (($htCounterInstanceStats[$XmlDataSourceCounterInstance.NAME].CounterObject.Contains('MSSQL$') -eq $True) -or ($htCounterInstanceStats[$XmlDataSourceCounterInstance.NAME].CounterObject.Contains('MSOLAP$') -eq $True))
                        {
                            $sSqlNamedInstance = ExtractSqlNamedInstanceFromCounterObjectPath -sCounterObjectPath $htCounterInstanceStats[$XmlDataSourceCounterInstance.NAME].CounterObject
                            If ($XmlDataSourceCounterInstance.COUNTERINSTANCE -eq '')
                            {
        						$CounterLabel = $XmlDataSourceCounterInstance.COUNTERCOMPUTER + "/" + $sSqlNamedInstance
                            }
                            Else
                            {
                                $CounterLabel = $XmlDataSourceCounterInstance.COUNTERCOMPUTER + "/" + $sSqlNamedInstance + "/" + $XmlDataSourceCounterInstance.COUNTERINSTANCE
                            }                            
                        }
                        Else
                        {
                            If ($XmlDataSourceCounterInstance.COUNTERINSTANCE -eq '')
                            {
        						$CounterLabel = $XmlDataSourceCounterInstance.COUNTERCOMPUTER
                            }
                            Else
                            {
                                $CounterLabel = $XmlDataSourceCounterInstance.COUNTERCOMPUTER + "/" + $XmlDataSourceCounterInstance.COUNTERINSTANCE
                            }
                        }
                        [void] $htCounterValues.Add($CounterLabel,$aValues)
                    }
                }
            }
        }
        If ($htCounterValues.Count -gt 0)
        {
            If ($(Test-property -InputObject $XmlChart -Name 'BACKGRADIENTSTYLE') -eq $True)
            {
                If (($IsCriticalThreshols -eq $True) -and ($IsWarningThresholds -eq $True))
                {
                    ConvertCounterArraysToSeriesHashTable $alOfSeries $aDateTimes $htCounterValues $true $MinWarningThresholdValues $MaxWarningThresholdValues $MinCriticalThresholdValues $MaxCriticalThresholdValues $XmlChart.BACKGRADIENTSTYLE
                }
                Else
                {
                    If ($IsCriticalThreshols -eq $True)
                    {
                        ConvertCounterArraysToSeriesHashTable $alOfSeries $aDateTimes $htCounterValues $true $null $null $MinCriticalThresholdValues $MaxCriticalThresholdValues $XmlChart.BACKGRADIENTSTYLE
                    }
                    Else
                    {
                        ConvertCounterArraysToSeriesHashTable $alOfSeries $aDateTimes $htCounterValues $true $MinWarningThresholdValues $MaxWarningThresholdValues $null $null $XmlChart.BACKGRADIENTSTYLE
                    }
                }        
                
            }
            Else
            {
                If (($IsCriticalThreshols -eq $True) -and ($IsWarningThresholds -eq $True))
                {
                    ConvertCounterArraysToSeriesHashTable $alOfSeries $aDateTimes $htCounterValues $true $MinWarningThresholdValues $MaxWarningThresholdValues $MinCriticalThresholdValues $MaxCriticalThresholdValues
                }
                Else
                {
                    If ($IsCriticalThreshols -eq $True)
                    {
                        ConvertCounterArraysToSeriesHashTable $alOfSeries $aDateTimes $htCounterValues $true $null $null $MinCriticalThresholdValues $MaxCriticalThresholdValues
                    }
                    Else
                    {
                        ConvertCounterArraysToSeriesHashTable $alOfSeries $aDateTimes $htCounterValues $true $MinWarningThresholdValues $MaxWarningThresholdValues $null $null
                    }
                }
            }
        }
        Else
        {
            Write-Warning "`t[GeneratePalChart] No data to chart."
        }        
    }
    Else
    {
        #// Populate $htCounterValues
        ForEach ($XmlCounterDataSource in $XmlAnalysisInstance.SelectNodes("./DATASOURCE"))
        {
            If ($XmlChart.DATASOURCE -eq $XmlCounterDataSource.EXPRESSIONPATH)
            {
                ForEach ($XmlDataSourceCounterInstance in $XmlCounterDataSource.SelectNodes("./COUNTERINSTANCE"))
                {
                    $aValues = $htCounterInstanceStats[$XmlDataSourceCounterInstance.NAME].Value
                    #// Check if this is a named instance of SQL Server
                    If (($htCounterInstanceStats[$XmlDataSourceCounterInstance.NAME].CounterObject.Contains('MSSQL$') -eq $True) -or ($htCounterInstanceStats[$XmlDataSourceCounterInstance.NAME].CounterObject.Contains('MSOLAP$') -eq $True))
                    {
                        $sSqlNamedInstance = ExtractSqlNamedInstanceFromCounterObjectPath -sCounterObjectPath $htCounterInstanceStats[$XmlDataSourceCounterInstance.NAME].CounterPath
                        If ($XmlDataSourceCounterInstance.COUNTERINSTANCE -eq '')
                        {
                            $CounterLabel = $XmlDataSourceCounterInstance.COUNTERCOMPUTER + "/" + $sSqlNamedInstance
                        }
                        Else
                        {
                            $CounterLabel = $XmlDataSourceCounterInstance.COUNTERCOMPUTER + "/" + $sSqlNamedInstance + "/" + $XmlDataSourceCounterInstance.COUNTERINSTANCE
                        }
                    }
                    Else
                    {
                        If ($XmlDataSourceCounterInstance.COUNTERINSTANCE -eq '')
                        {
                            $CounterLabel = $XmlDataSourceCounterInstance.COUNTERCOMPUTER
                        }
                        Else
                        {
                            $CounterLabel = $XmlDataSourceCounterInstance.COUNTERCOMPUTER + "/" + $XmlDataSourceCounterInstance.COUNTERINSTANCE
                        }
                    }
                    [void] $htCounterValues.Add($CounterLabel,$aValues)
                }
            }   
        }
        If ($htCounterValues.Count -gt 0)
        {
            ConvertCounterArraysToSeriesHashTable $alOfSeries $aDateTimes $htCounterValues $False
        }
        Else
        {
            Write-Warning "`t[GeneratePalChart] No data to chart."
        }
    }    
    
    #// If there are too many counter instances in a data source for one chart, then need to do multiple charts.
    $ImageFileName = ConvertCounterToFileName -sCounterPath $XmlChart.DATASOURCE
    $OutputDirectoryPath = $htHTMLReport["ResourceDirectoryPath"]	
	$sChartTitle = $XmlChart.CHARTTITLE
	$MaxNumberOfItemsInChart = $CHART_MAX_INSTANCES
	$sFilePath = "$OutputDirectoryPath" + "$ImageFileName" + '.png'
    $alOriginalOfSeries = $alOfSeries
    
    #// Put _Total instances in their own chart series
    $alTotalInstancesSeries = New-Object System.Collections.ArrayList
    $alAllOthersOfSeries = New-Object System.Collections.ArrayList
    For ($t=0;$t -lt $alOfSeries.Count;$t++)
    {
        If ($($alOfSeries[$t].Name.Contains('_Total')) -eq $True)
        {
            $alTotalInstancesSeries += $alOfSeries[$t]
        }
        Else
        {
            $alAllOthersOfSeries += $alOfSeries[$t]
        }
    }

    #// Chart all of the _Total instances
    $alOfSeries = $alTotalInstancesSeries
	If ($alOfSeries.Count -gt $MaxNumberOfItemsInChart)
	{
		$c = 0
		$iChartNumber = 0
		$alSubOfSeries = New-Object System.Collections.ArrayList
		For ($b=0;$b -lt $alOfSeries.Count;$b++)
		{
            #// Re-add the thresholds if any
            If ($(Test-property -InputObject $XmlChart -Name 'ISTHRESHOLDSADDED') -eq $False)
            {
                SetXmlChartIsThresholdAddedAttribute -XmlChart $XmlChart
            }            
            If ($XmlChart.ISTHRESHOLDSADDED -eq "True")
            {
                $iNumberOfChartThresholds = 0
                ForEach ($XmlChartSeries in $XmlChart.SelectNodes("./SERIES"))
                {
                    If ($(Test-property -InputObject $XmlChartSeries -Name 'NAME') -eq $True)
                    {
                        If (($XmlChartSeries.NAME -eq 'Warning') -or ($XmlChartSeries.NAME -eq 'Critical'))
                        {
                            $alSubOfSeries += $alOriginalOfSeries[$iNumberOfChartThresholds]
                            $iNumberOfChartThresholds = $iNumberOfChartThresholds + 1
                        }
                    }
                }
            }
			$alSubOfSeries += $alOfSeries[$b]
			$c = $c + 1
			If ($c -gt ($MaxNumberOfItemsInChart-1))
			{
				$iChartNumber = 0
                $bFileExists = $True
                Do
                {
                    $iChartNumber++
                    $sFilePath = "$OutputDirectoryPath" + "$ImageFileName" + '_Total_' + "$iChartNumber" + '.png'
                    $bFileExists = Test-Path -Path $sFilePath
                } until ($bFileExists -eq $False)
				$sFilePath = GenerateMSChart $sChartTitle $sFilePath $alSubOfSeries
                [void] $alChartFilePaths.Add($sFilePath)
				$alSubOfSeries = New-Object System.Collections.ArrayList
				$iChartNumber = $iChartNumber + 1
				$c = 0
			}            
		}			
	}
	Else
	{
        If ($alOfSeries.Count -gt 0)
        {
    		$alSubOfSeries = New-Object System.Collections.ArrayList
    		For ($b=0;$b -lt $alOfSeries.Count;$b++)
    		{
                #// Re-add the thresholds if any
                
                If ($(Test-property -InputObject $XmlChart -Name 'ISTHRESHOLDSADDED') -eq $False)
                {
                    SetXmlChartIsThresholdAddedAttribute -XmlChart $XmlChart
                }

                If ($XmlChart.ISTHRESHOLDSADDED -eq "True")
                {
                    $iNumberOfChartThresholds = 0
                    ForEach ($XmlChartSeries in $XmlChart.SelectNodes("./SERIES"))
                    {
                        If ($(Test-property -InputObject $XmlChartSeries -Name 'NAME') -eq $True)
                        {
                            If (($XmlChartSeries.NAME -eq 'Warning') -or ($XmlChartSeries.NAME -eq 'Critical'))
                            {
                                $alSubOfSeries += $alOriginalOfSeries[$iNumberOfChartThresholds]
                                $iNumberOfChartThresholds = $iNumberOfChartThresholds + 1
                            }
                        }
                    }
                }
    			$alSubOfSeries += $alOfSeries[$b]
    		}                    
            $iChartNumber = 0
            $bFileExists = $True
            Do
            {
                $iChartNumber++
                $sFilePath = "$OutputDirectoryPath" + "$ImageFileName" + '_Total_' + "$iChartNumber" + '.png'
                $bFileExists = Test-Path -Path $sFilePath
            } until ($bFileExists -eq $False)            
    		$sFilePath = GenerateMSChart $sChartTitle $sFilePath $alSubOfSeries            
            [void] $alChartFilePaths.Add($sFilePath)
        }
	}

    #// Chart all non-_Total instances
    $alOfSeries = $alAllOthersOfSeries
	If ($alOfSeries.Count -gt $MaxNumberOfItemsInChart)
	{
		$c = 0
		$iChartNumber = 0
		$alSubOfSeries = New-Object System.Collections.ArrayList
		For ($b=0;$b -lt $alOfSeries.Count;$b++)
		{
            #// Re-add the thresholds if any
            If ($(Test-property -InputObject $XmlChart -Name 'ISTHRESHOLDSADDED') -eq $False)
            {
                SetXmlChartIsThresholdAddedAttribute -XmlChart $XmlChart
            }
            
            If ($XmlChart.ISTHRESHOLDSADDED -eq "True")
            {
                $iNumberOfChartThresholds = 0
                ForEach ($XmlChartSeries in $XmlChart.SelectNodes("./SERIES"))
                {
                    If ($(Test-property -InputObject $XmlChartSeries -Name 'NAME') -eq $True)
                    {
                        If (($XmlChartSeries.NAME -eq 'Warning') -or ($XmlChartSeries.NAME -eq 'Critical'))
                        {
                            $alSubOfSeries += $alOriginalOfSeries[$iNumberOfChartThresholds]
                            $iNumberOfChartThresholds = $iNumberOfChartThresholds + 1
                        }
                    }
                }
            }
			$alSubOfSeries += $alOfSeries[$b]
			$c = $c + 1
			If ($c -gt ($MaxNumberOfItemsInChart-1))
			{
				$sFilePath = "$OutputDirectoryPath" + "$ImageFileName" + '_' + "$iChartNumber" + '.png'
                
				$sFilePath = GenerateMSChart $sChartTitle $sFilePath $alSubOfSeries                
                [void] $alChartFilePaths.Add($sFilePath)
				$alSubOfSeries = New-Object System.Collections.ArrayList
				$iChartNumber = $iChartNumber + 1
				$c = 0
			}
		}			
	}
	Else
	{
        If ($alOfSeries.Count -gt 0)
        {
            If ($(Test-property -InputObject $XmlChart -Name 'ISTHRESHOLDSADDED') -eq $False)
            {
                SetXmlChartIsThresholdAddedAttribute -XmlChart $XmlChart
            }
            If ($XmlChart.ISTHRESHOLDSADDED -eq 'True')
            {
                If ($alOfSeries.Count -gt 1)
                {
                    $iChartNumber = 0
                    $bFileExists = $True
                    Do
                    {
                        $iChartNumber++
                        $sFilePath = "$OutputDirectoryPath" + "$ImageFileName" + "$iChartNumber" + '.png'
                        $bFileExists = Test-Path -Path $sFilePath
                    } until ($bFileExists -eq $False)                      
            		$sFilePath = GenerateMSChart $sChartTitle $sFilePath $alOfSeries
                    [void] $alChartFilePaths.Add($sFilePath)
                }
            }
            Else
            {
                $iChartNumber = 0
                $bFileExists = $True
                Do
                {
                    $iChartNumber++
                    $sFilePath = "$OutputDirectoryPath" + "$ImageFileName" + "$iChartNumber" + '.png'
                    $bFileExists = Test-Path -Path $sFilePath
                } until ($bFileExists -eq $False)                 
        		$sFilePath = GenerateMSChart $sChartTitle $sFilePath $alOfSeries
                [void] $alChartFilePaths.Add($sFilePath)
            }            
        }
    }
        
    $alChartFilePaths
}

Function DisableAnalysisIfNoCounterInstancesFound($XmlAnalysisInstance)
{
    $XmlAnalysisInstance.SetAttribute("AllCountersFound",'True')
    ForEach ($XmlDataSource in $XmlAnalysisInstance.SelectNodes('./DATASOURCE'))
    {
        If ($XmlDataSource.TYPE.ToLower() -ne 'generated')
        {
            $IsAtLeastOneCounterInstanceInDataSource = $False
            :CounterInstanceLoop ForEach ($XmlDataSource in $XmlDataSource.SelectNodes('./COUNTERINSTANCE'))
            {
                $IsAtLeastOneCounterInstanceInDataSource = $True
                Break CounterInstanceLoop
            }
            If ($IsAtLeastOneCounterInstanceInDataSource -eq $False)
            {
                $XmlAnalysisInstance.SetAttribute("AllCountersFound",'False')
            }
        }
    }
}

Function ConvertToRelativeFilePaths
{
    param($RootPath,$TargetPath)
    $Result = $TargetPath.Replace($RootPath,'')
    $Result
}

Function PrepareGeneratedCodeReplacements
{
    param($XmlAnalysisInstance)
    	
    #// Generated data source, charts, and thresholds assume that all of the counterlog counters are available to it.
	ForEach ($XmlCounterDataSource in $XmlAnalysisInstance.SelectNodes('./DATASOURCE'))
	{       
		If ($XmlCounterDataSource.TYPE -eq "CounterLog")
		{
			$global:alCounterDataSourceCollection = New-Object System.Collections.ArrayList
            ForEach ($XmlCounterDataSourceInstance in $XmlCounterDataSource.SelectNodes("./COUNTERINSTANCE"))
            {
                If ($(Test-XmlBoolAttribute -InputObject $XmlCounterDataSourceInstance -Name 'ISALLNULL') -eq $True)
                {
                    $IsAllNull = $True
                }
                Else
                {
                    $IsAllNull = $False
                }
                
                If ($IsAllNull -eq $False)
                {
                    [void] $alCounterDataSourceCollection.Add($htCounterInstanceStats[$XmlCounterDataSourceInstance.NAME])
                }
            }
            [void] $htVariables.Add($XmlCounterDataSource.COLLECTIONVARNAME,$alCounterDataSourceCollection)
            $sCollectionName = $XmlCounterDataSource.COLLECTIONVARNAME
            $sCollectionNameWithBackslash = "\`$$sCollectionName"
            $sCollectionNameWithDoubleQuotes = "`"$sCollectionName`""
            $sCollectionVarName = "`$htVariables[$sCollectionNameWithDoubleQuotes]"
            [void] $htCodeReplacements.Add($sCollectionNameWithBackslash,$sCollectionVarName)
		}
	}
                    
    #// Add the code replacements for the question variables
    ForEach ($sKey in $htQuestionVariables.Keys)
    {
        $sModifiedKey = "\`$$sKey"
        $sKeyWithDoubleQuotes = "`"$sKey`""
        $sModifiedVarName = "`$htQuestionVariables[$sKeyWithDoubleQuotes]"
        $IsInHashTable = $htCodeReplacements.Contains($sModifiedKey)
        If ($IsInHashTable -eq $false)
        {            
            [void] $htCodeReplacements.Add($sModifiedKey,$sModifiedVarName)
        }
    }
}

Function GenerateQuantizedArrayListForOverallStats
{
    param($Value)
    $alCounterStats = New-Object System.Collections.ArrayList
    If ($(IsNumeric -Value $Value) -eq $True)
    {
        [double] $Value = $Value
    }    
    For ($t=0;$t -lt $alQuantizedTime.Count;$t++)
    {
        If ($t -eq 0)
        {
            [void] $alCounterStats.Add($Value)
        }
        Else
        {
            [void] $alCounterStats.Add('-')
        }
    }
    $alCounterStats
}

Function PrepareEnvironmentForThresholdProcessing
{
    param($CurrentAnalysisInstance)
    
    If ($alQuantizedIndex -eq $null)
    {
        If (($aTime -eq $null) -or ($aTime -eq ''))
        {
            $aTime = GetTimeDataFromPerfmonLog
        }
        $alQuantizedIndex = GenerateQuantizedIndexArray -ArrayOfTimes $aTime -AnalysisIntervalInSeconds $AnalysisInterval
    }
    
    If ($global:alQuantizedTime -eq $null)
    {
        $global:alQuantizedTime = GenerateQuantizedTimeArray -ArrayOfTimes $aTime -QuantizedIndexArray $alQuantizedIndex
    }
    
    #// Create an internal overall counter stat for each counter instance for each counter stat.
    ForEach ($XmlDataSource in $CurrentAnalysisInstance.SelectNodes('./DATASOURCE'))
    {
        ForEach ($XmlCounterInstance in $XmlDataSource.SelectNodes('./COUNTERINSTANCE'))
        {
            If ($(Test-XmlBoolAttribute -InputObject $XmlCounterInstance -Name 'ISINTERNALONLY') -eq $True)
            {
                $IsInternalOnly = $True
            }
            Else
            {
                $IsInternalOnly = $False
            }
            If ($IsInternalOnly -eq $False)
            {
                #$global:alCounterDataSourceCollection = New-Object System.Collections.ArrayList
                $XmlNewCounterInstance = $XmlAnalysis.CreateElement("COUNTERINSTANCE")
                $InternalCounterInstanceName = 'INTERNAL_OVERALL_COUNTER_STATS_' + $($XmlCounterInstance.NAME)
                $XmlNewCounterInstance.SetAttribute("NAME", $InternalCounterInstanceName)
                $XmlNewCounterInstance.SetAttribute("MIN", $($XmlCounterInstance.MIN))
                $XmlNewCounterInstance.SetAttribute("AVG", $($XmlCounterInstance.AVG))
                $XmlNewCounterInstance.SetAttribute("MAX", $($XmlCounterInstance.MAX))
                $XmlNewCounterInstance.SetAttribute("TREND", $($XmlCounterInstance.TREND))
                $XmlNewCounterInstance.SetAttribute("STDDEV", $($XmlCounterInstance.STDDEV))
                $XmlNewCounterInstance.SetAttribute("PERCENTILESEVENTYTH", $($XmlCounterInstance.PERCENTILESEVENTYTH))
                $XmlNewCounterInstance.SetAttribute("PERCENTILEEIGHTYTH", $($XmlCounterInstance.PERCENTILEEIGHTYTH))
                $XmlNewCounterInstance.SetAttribute("PERCENTILENINETYTH", $($XmlCounterInstance.PERCENTILENINETYTH))
                $QuantizedMinForOverallStats = GenerateQuantizedArrayListForOverallStats -Value $XmlCounterInstance.MIN
                $QuantizedAvgForOverallStats = GenerateQuantizedArrayListForOverallStats -Value $XmlCounterInstance.AVG
                $QuantizedMaxForOverallStats = GenerateQuantizedArrayListForOverallStats -Value $XmlCounterInstance.MAX
                $QuantizedTrendForOverallStats = GenerateQuantizedArrayListForOverallStats -Value $XmlCounterInstance.TREND
                $XmlNewCounterInstance.SetAttribute("QUANTIZEDMIN", $([string]::Join(',',$QuantizedMinForOverallStats)))
                $XmlNewCounterInstance.SetAttribute("QUANTIZEDAVG", $([string]::Join(',',$QuantizedAvgForOverallStats)))
                $XmlNewCounterInstance.SetAttribute("QUANTIZEDMAX", $([string]::Join(',',$QuantizedMaxForOverallStats)))
                $XmlNewCounterInstance.SetAttribute("QUANTIZEDTREND", $([string]::Join(',',$QuantizedTrendForOverallStats)))
                $XmlNewCounterInstance.SetAttribute("COUNTERPATH", $($XmlCounterInstance.COUNTERPATH))
                $XmlNewCounterInstance.SetAttribute("COUNTERCOMPUTER", $($XmlCounterInstance.COUNTERCOMPUTER))
                $XmlNewCounterInstance.SetAttribute("COUNTEROBJECT", $($XmlCounterInstance.COUNTEROBJECT))
                $XmlNewCounterInstance.SetAttribute("COUNTERNAME", $($XmlCounterInstance.COUNTERNAME))
                If ($(Test-property -InputObject $XmlCounterInstance -Name 'ISALLNULL') -eq $True)
                {
                    $XmlNewCounterInstance.SetAttribute("ISALLNULL", $($XmlCounterInstance.ISALLNULL))
                }
                Else
                {
                    $XmlNewCounterInstance.SetAttribute("ISALLNULL", 'False')
                }                    
                $XmlNewCounterInstance.SetAttribute("ISINTERNALONLY", $True)
                $XmlNewCounterInstance.SetAttribute("ORIGINALNAME", $($XmlCounterInstance.NAME))
                [void] $XmlDataSource.AppendChild($XmlNewCounterInstance)
                $oCounter = $htCounterInstanceStats[$XmlCounterInstance.NAME]
                AddToCounterInstanceStatsArrayList $InternalCounterInstanceName $oCounter.Time $oCounter.Value $oCounter.QuantizedTime $QuantizedMinForOverallStats $QuantizedAvgForOverallStats $QuantizedMaxForOverallStats $QuantizedTrendForOverallStats $oCounter.CounterComputer $oCounter.CounterObject $oCounter.CounterName $oCounter.CounterInstance $oCounter.Min $oCounter.Avg $oCounter.Max $oCounter.Trend $oCounter.StdDev $oCounter.PercentileSeventyth $oCounter.PercentileEightyth $oCounter.PercentileNinetyth
                #[void] $alCounterDataSourceCollection.Add($htCounterInstanceStats[$InternalCounterInstanceName])
                #[void] $htVariables[$($XmlDataSource.COLLECTIONVARNAME)].Add($alCounterDataSourceCollection)
                [void] $htVariables[$($XmlDataSource.COLLECTIONVARNAME)].Add($htCounterInstanceStats[$InternalCounterInstanceName])
            }
        }
    }
}

Function ProcessThreshold
{
    param($XmlAnalysisInstance,$XmlThreshold)
    
    $global:CurrentXmlAnalysisInstance = $XmlAnalysisInstance
    $global:ThresholdName = $XmlThreshold.NAME
    $global:ThresholdCondition = $XmlThreshold.CONDITION
    $global:ThresholdColor = $XmlThreshold.COLOR
    $global:ThresholdPriority = $XmlThreshold.PRIORITY
    If ($(Test-property -InputObject $XmlAnalysisInstance -Name 'ID') -eq $True)
    {
        $global:ThresholdAnalysisID = $XmlAnalysisInstance.ID
    }
    Else
    {
        $global:ThresholdAnalysisID = Get-GUID
    }
    
    
    ForEach ($XmlCode in $XmlThreshold.SelectNodes("./CODE"))
    {
		$sCode = $XmlCode.get_innertext()
		#'Code before changes:' >> CodeDebug.txt
		#'====================' >> CodeDebug.txt
		#$sCode >> CodeDebug.txt            
		#// Replace all of the variables with their hash table version.
		ForEach ($sKey in $htCodeReplacements.Keys)
		{
			$sCode = $sCode -Replace $sKey,$htCodeReplacements[$sKey]
		}
        
		#// Execute the code
		ExecuteCodeForThreshold -Code $sCode -Name $ThresholdName -htVariables $htVariables -htQuestionVariables $htQuestionVariables        
		Break #// Only execute one block of code, so breaking out.
    }
}

Function SetDefaultQuestionVariables
{
    param($XmlAnalysis)
    #// Add all of the Question Variable defaults
    ForEach ($XmlQuestion in $XmlAnalysis.SelectNodes('//QUESTION'))
    {
        If ($(Test-property -InputObject $XmlQuestion -Name 'QUESTIONVARNAME') -eq $True)
        {
            If ($($htQuestionVariables.Contains($($XmlQuestion.QUESTIONVARNAME))) -eq $False)
            {
                If ($(Test-property -InputObject $XmlQuestion -Name 'DEFAULTVALUE') -eq $True)
                {                
                    If (($($XmlQuestion.DEFAULTVALUE) -eq 'True') -or ($($XmlQuestion.DEFAULTVALUE) -eq 'False'))
                    {
                        $IsTrueOrFalse = ConvertTextTrueFalse $XmlQuestion.DEFAULTVALUE
                        $htQuestionVariables.Add($($XmlQuestion.QUESTIONVARNAME),$IsTrueOrFalse)
                    }
                    Else
                    {
                        #// Cast the question variables to their appropriate type.
                        If ($(Test-property -InputObject $XmlQuestion -Name 'DATATYPE') -eq $True)
                        {
                            $sDataType = $XmlQuestion.DATATYPE
                            switch ($sDataType)
                            {
                                'boolean'
                                {
                                    #// Already taken care of from above.
                                }
                                'integer'
                                {
                                    [int] $DefaultValue = $($XmlQuestion.DEFAULTVALUE)
                                    $htQuestionVariables.Add($($XmlQuestion.QUESTIONVARNAME),$DefaultValue)
                                }
                                'int'
                                {
                                    [int] $DefaultValue = $($XmlQuestion.DEFAULTVALUE)
                                    $htQuestionVariables.Add($($XmlQuestion.QUESTIONVARNAME),$DefaultValue)
                                }                                
                                'string'
                                {
                                    [string] $DefaultValue = $($XmlQuestion.DEFAULTVALUE)
                                    $htQuestionVariables.Add($($XmlQuestion.QUESTIONVARNAME),$DefaultValue)
                                }
                            }
                        }
                        Else
                        {
                            #// Assume string
                            [string] $DefaultValue = $($XmlQuestion.DEFAULTVALUE)
                            $htQuestionVariables.Add($($XmlQuestion.QUESTIONVARNAME),$DefaultValue)
                        }
                    }
                }
            }
        }
    }
}

Function Analyze()
{
    $iAnalysisCount = 0
	ForEach ($XmlAnalysisInstance in $XmlAnalysis.SelectNodes("//ANALYSIS"))
	{
        $iAnalysisCount++    
    }
    $iAnalysisNum = 0
	ForEach ($XmlAnalysisInstance in $XmlAnalysis.SelectNodes("//ANALYSIS"))
	{
        $iAnalysisNum++
        $iPercentComplete = ConvertToDataType $(($iAnalysisNum / $iAnalysisCount) * 100) 'integer'
        $sComplete = "Progress: $iPercentComplete% (Analysis $iAnalysisNum of $iAnalysisCount)"
        Write-Progress -activity 'Analysis progress...' -status $sComplete -percentcomplete $iPercentComplete;    
        
        $global:htCounterInstanceStats = @{}
		#Write-Host "`tAcquiring data sources" -NoNewLine
		#// Gather data from counter data sources first since the generated data sources will depend on this.
        #// Do not process the analysis if it is not enabled.
        If ($(Test-XmlBoolAttribute -InputObject $XmlAnalysisInstance -Name 'ENABLED') -eq $True)
        {
            $IsEnabled = $True
        }
        Else
        {
            $IsEnabled = $False
        }
        
        If ($IsEnabled -eq $True)
        {
            Write-Host "Processing:" $XmlAnalysisInstance.NAME
    		ForEach ($XmlDataSource in $XmlAnalysisInstance.SelectNodes('./DATASOURCE'))
    		{
                If ($XmlDataSource.TYPE -ne "Generated")
                {
    				GetDataSourceData $XmlAnalysis $XmlAnalysisInstance $XmlDataSource
                }
    		}
            DisableAnalysisIfNoCounterInstancesFound $XmlAnalysisInstance
            If ($(Test-XmlBoolAttribute -InputObject $XmlAnalysisInstance -Name 'AllCountersFound') -eq $True)
            {
                $IsAllCountersFound = $True
            }
            Else
            {
                $IsAllCountersFound = $False
            }
			
			#// Add the counter instances to hash table for use by the generated data source.
			$global:htVariables = @{}
			$global:htCodeReplacements = @{}
			$global:alCounterDataSourceCollection = New-Object System.Collections.ArrayList
            If ($(Test-XmlBoolAttribute -InputObject $XmlAnalysisInstance -Name 'FROMALLCOUNTERSTATS') -eq $True)
            {
                $IsFromAllCounterStats = $True
            }
            Else
            {
                $IsFromAllCounterStats = $False
            }            

    		If ($IsAllCountersFound -eq $True)
            {
				#// If this analysis is generated from the AllCounterStats feature, then don't process it.
				If ($IsFromAllCounterStats -eq $True)
				{
                	ForEach ($XmlCounterDataSource in $XmlAnalysisInstance.SelectNodes('./DATASOURCE'))
                	{       
                		If ($XmlCounterDataSource.TYPE -eq "CounterLog")
                		{
                			$global:alCounterDataSourceCollection = New-Object System.Collections.ArrayList
                            ForEach ($XmlCounterDataSourceInstance in $XmlCounterDataSource.SelectNodes("./COUNTERINSTANCE"))
                            {
                                If ($(Test-XmlBoolAttribute -InputObject $XmlCounterDataSourceInstance -Name 'ISALLNULL') -eq $True)
                                {
                                    $IsAllNull = $True
                                }
                                Else
                                {
                                    $IsAllNull = $False
                                }
                                
                                If ($IsAllNull -eq $False)
                                {
                                    [void] $alCounterDataSourceCollection.Add($htCounterInstanceStats[$XmlCounterDataSourceInstance.NAME])
                                }
                            }
                            [void] $htVariables.Add($XmlCounterDataSource.COLLECTIONVARNAME,$alCounterDataSourceCollection)
                		}
                	}                
				}
				Else
				{
					#// Add the counter log data into memory for the processing of generated counters.
					PrepareGeneratedCodeReplacements -XmlAnalysisInstance $XmlAnalysisInstance
				}
            }
            			
    		If ($IsAllCountersFound -eq $True)
            {
				#// If this analysis is generated from the AllCounterStats feature, then don't process it.
				If ($IsFromAllCounterStats -eq $True)
				{
					#Do Nothing
				}
				Else
				{
                    #//////////////////////
					#// Generate data sources.
                    #//////////////////////
					ForEach ($XmlDataSource in $XmlAnalysisInstance.SelectNodes('./DATASOURCE'))
					{
						If ($XmlDataSource.TYPE.ToLower() -eq "generated")
						{
							If ($alCounterExpressionProcessedHistory.Contains($XmlDataSource.NAME) -eq $False)
							{
								GenerateDataSourceData $XmlAnalysis $XmlAnalysisInstance $XmlDataSource
								#Write-Host "." -NoNewline
								[Void] $alCounterExpressionProcessedHistory.Add($XmlDataSource.NAME)
							}
						}
					}
				}
            }

            If ($IsAllCountersFound -eq $True)
            {
                #//////////////////////
        		#// Generate charts.
                #//////////////////////
        		Write-Host "`tGenerating Charts." -NoNewline
                $alOfChartFilePaths = New-Object System.Collections.ArrayList
                $alTempFilePaths = New-Object System.Collections.ArrayList
        		ForEach ($XmlChart in $XmlAnalysisInstance.SelectNodes("./CHART"))
        		{			
        			$alTempFilePaths = GeneratePalChart -XmlChart $XmlChart -XmlAnalysisInstance $XmlAnalysisInstance
                    [System.Object[]] $alTempFilePaths = @($alTempFilePaths | Where-Object {$_ -ne $null})
                    For ($i=0;$i -lt $alTempFilePaths.Count;$i++)
                    {
                        $alTempFilePaths[$i] = ConvertToRelativeFilePaths -RootPath $global:htHtmlReport["OutputDirectoryPath"] -TargetPath $alTempFilePaths[$i]
                    }
                    
                    If ($alTempFilePaths -ne $null) #// Added by Andy from Codeplex.com
                    {
                        $result = [string]::Join(',',$alTempFilePaths)
                        $XmlChart.SetAttribute("FILEPATHS", $result)
            			Write-Host "." -NoNewline
                    }
        		}
                Write-Host 'Done'
                
                #//////////////////////
        		#// Processing Thresholds
                #//////////////////////                
                Write-Host "`tProcessing Thresholds." -NoNewline
                PrepareEnvironmentForThresholdProcessing -CurrentAnalysisInstance $XmlAnalysisInstance
                ForEach ($XmlThreshold in $XmlAnalysisInstance.SelectNodes("./THRESHOLD"))
                {
                    ProcessThreshold -XmlAnalysisInstance $XmlAnalysisInstance -XmlThreshold $XmlThreshold
                }
                Write-Host "." -NoNewLine
                Write-Host 'Done'
            }
    		Write-Host ""
        }
	}   
    $sComplete = "Progress: 100% (Analysis $iAnalysisCount of $iAnalysisCount)"
    Write-Progress -activity 'Analysis progress...' -status $sComplete -Completed
}

Function WriteLineToHttpReport($Line)
{
    Add-Content $htHtmlReport["ReportFilePath"] –value $Line    
}

Function GetFileNameFromFilePath
{
    param($FilePath)    
    $ArrayOfStrings = $FilePath.Split('\')
    $ArrayOfStrings[$ArrayOfStrings.GetUpperBound(0)]    
}

Function GetLogNameFromLogParameter
{
    $aSplitBySemiColon = $Log.Split(';')
    GetFileNameFromFilePath -FilePath $aSplitBySemiColon[0]
}

Function ConvertChartFilePathToImgTag
{
    param($FilePath)
    $result = "<CENTER><IMG SRC=" + "$FilePath" + "></CENTER><BR>"
    $result
}

Function ConvertStringForHref($str)
{
	$RetVal = $str
    $RetVal = $RetVal.Replace('/','')
	$RetVal = $RetVal.Replace('%','Percent')
	$RetVal = $RetVal.Replace(' ','')
	$RetVal = $RetVal.Replace('.','')
	$RetVal = $RetVal.Replace('(','')
	$RetVal = $RetVal.Replace(')','')
	$RetVal = $RetVal.Replace('*','All')
	$RetVal = $RetVal.Replace('\','')
    $RetVal = $RetVal.Replace(':','')
    $RetVal = $RetVal.Replace('-','')
	#// Remove first char if it is an underscore.
	$FirstChar = $RetVal.SubString(0,1)
	If ($FirstChar -eq '_')
	{		
		$RetVal = $RetVal.SubString(1)
	}
	#// Remove last char if it is an underscore.
	$iLenMinusOne = $RetVal.Length - 1
	$LastChar = $RetVal.SubString($iLenMinusOne)
	If ($LastChar -eq '_')
	{
		$RetVal = $RetVal.SubString(0,$iLenMinusOne)
	}
    $RetVal
}

Function GetCategoryList
{
    ForEach ($XmlAnalysisNode in $global:XmlAnalysis.SelectNodes('//ANALYSIS'))
    {
        If ($(Test-XmlBoolAttribute -InputObject $XmlAnalysisNode -Name 'ENABLED') -eq $True)
        {
            $IsEnabled = $True
        }
        Else
        {
            $IsEnabled = $False
        }    

        If ($IsEnabled -eq $True)
        {
            If ($(Test-property -InputObject $XmlAnalysisNode -Name 'CATEGORY') -eq $True) 
            {
                If ($alCategoryList.Contains($XmlAnalysisNode.CATEGORY) -eq $False)
                {
                    [void] $alCategoryList.Add($XmlAnalysisNode.CATEGORY)
                }            
            }
        }
    }
}

Function PrepareDataForReport
{
    $global:alCategoryList = New-Object System.Collections.ArrayList
    GetCategoryList
    $global:alCategoryList.Sort()
}

Function ConvertAnalysisIntervalIntoHumanReadableTime
{
    [string] $sInterval = ''
    If ($(IsNumeric -Value $AnalysisInterval) -eq $True)
    {
        $TimeInSeconds = $AnalysisInterval
    }
    Else
    {
        $TimeInSeconds = $global:AnalysisInterval
    }
	## Commented as we need to use global varables as we use them elsewere JonnyG 2010-06-11
	#$BeginTime = Get-Date
	#$EndTime = $BeginTime.AddSeconds($TimeInSeconds)
	#$DateDifference = New-TimeSpan -Start ([DateTime]$BeginTime) -End ([DateTime]$EndTime)
	$Global:BeginTime = Get-Date
	$Global:EndTime = $Global:BeginTime.AddSeconds($TimeInSeconds)
	$DateDifference = New-TimeSpan -Start ([DateTime]$Global:BeginTime) -End ([DateTime]$Global:EndTime)
	If ($DateDifference.Seconds -gt 0)
	{
		$sInterval = "$($DateDifference.Seconds) second(s)"
	}
	If ($DateDifference.Minutes -gt 0)
	{
		$sInterval = "$($DateDifference.Minutes) Minute(s) $sInterval"
	}
	If ($DateDifference.Hours -gt 0)
	{
		$sInterval = "$($DateDifference.Hours) Hours(s) $sInterval"
	}
	If ($DateDifference.Days -gt 0)
	{
		$sInterval = "$($DateDifference.Days) Days(s) $sInterval"
	}
    $sInterval
}

Function AddThousandsSeparator
{
    param($Value)
    If ($Value -eq '-')
    {Return $Value}
    [double] $Value = $Value
	If ($Value -eq 0)
	{ 0 }
	Else
	{ $Value.ToString("#,#.########") }
}

Function GetLogTimeRange
{	
	$u = $aTime.GetUpperBound(0)
    #$Date1 = Get-Date $($aTime[0]) -format "MM/dd/yyyy HH:mm:ss"
    #$Date2 = Get-Date $($aTime[$u]) -format "MM/dd/yyyy HH:mm:ss"
    $Date1 = Get-Date $([datetime]$aTime[0]) -format $global:sDateTimePattern
    $Date2 = Get-Date $([datetime]$aTime[$u]) -format $global:sDateTimePattern
    [string] $ResulTimeRange = "$Date1" + ' - ' + "$Date2"
    $ResulTimeRange
}

Function IsThresholdsInAnalysis
{
    param($XmlAnalysis)
    ForEach ($XmlNode in $XmlAnalysis.SelectNodes('./THRESHOLD'))
    {
        Return $True
    }
    $False    
}

Function Add-WhiteFont
{
    param([string] $Text,[string] $Color)
    $Color = $Color.ToLower()
    If (($Color -eq 'red') -or ($Color -eq '#FF0000'))
    {
        Return '<FONT COLOR="#FFFFFF">' + $Text + '</FONT>'
    }
    Else
    {
        Return $Text
    }
}

Function GenerateHtml
{
    param()
    If ($IsOutputHtml -eq $False)
    {
        Return
    }
    Write-Host 'Generating the HTML Report...' -NoNewline
    
    $iNumberOfAnalyses = 0
    $iTableCounter = 0
    ForEach ($XmlAnalysisNode in $global:XmlAnalysis.SelectNodes('//ANALYSIS'))
    {
        $iNumberOfAnalyses++
    }
    $h = $htHtmlReport["ReportFilePath"]
    
    #///////////////////////
    #// Header
    #///////////////////////    
    '<HTML>' > $h
    '<HEAD>' >> $h
    '<STYLE TYPE="text/css" TITLE="currentStyle" MEDIA="screen">' >> $h
    'body {' >> $h
    '   font: normal 8pt/16pt Verdana;' >> $h
    '   color: #000000;' >> $h
    '   margin: 10px;' >> $h
    '   }' >> $h
    'p {font: 8pt/16pt Verdana;margin-top: 0px;}' >> $h
    'h1 {font: 20pt Verdana;margin-bottom: 0px;color: #000000;}' >> $h
    'h2 {font: 15pt Verdana;margin-bottom: 0px;color: #000000;}' >> $h
    'h3 {font: 13pt Verdana;margin-bottom: 0px;color: #000000;}' >> $h
    'td {font: normal 8pt Verdana;}' >> $h
    'th {font: bold 8pt Verdana;}' >> $h
    'blockquote {font: normal 8pt Verdana;}' >> $h
    '</STYLE>' >> $h
    '</HEAD>' >> $h
    '<BODY LINK="Black" VLINK="Black">' >> $h
    #// $sTemp = ''
    #// For ($i=0;$i -lt $iNumberOfAnalyses;$i++)
    #// {
    #//     $sTemp += "initTable(`"table$i`");"
    #// }
    #// $sTemp = "onLoad='$sTemp'"
    #// '<BODY LINK="Black" VLINK="Black" ' + "$sTemp" + '>' >> $h
    #// $sTemp = $global:htHtmlReport["ResourceDirectoryPath"]
    #// '<SCRIPT SRC="' + "$sTemp" + '\TableSort.js">' >> $h
    #// '</SCRIPT>' >> $h
    '<TABLE CELLPADDING=10 WIDTH="100%"><TR><TD BGCOLOR="#000000">' >> $h
    '<FONT COLOR="#FFFFFF" FACE="Tahoma" SIZE="5"><STRONG>Analysis of "' + $(GetLogNameFromLogParameter) + '"</STRONG></FONT><BR><BR>' >> $h
    ## Updated to format with globalised date time JonnyG 2010-06-11
	#'<FONT COLOR="#FFFFFF" FACE="Tahoma" SIZE="2"><STRONG>Report Generated at: ' + "$(Get-Date)" + '</STRONG></FONT>' >> $h
    '<FONT COLOR="#FFFFFF" FACE="Tahoma" SIZE="2"><STRONG>Report Generated at: ' + "$((get-date).tostring($global:sDateTimePattern))" + '</STRONG></FONT>' >> $h
    #//'</TD><TD><A HREF="http://pal.codeplex.com"><FONT COLOR="#000000" FACE="Tahoma" SIZE="10">PAL</FONT><FONT COLOR="#000000" FACE="Tahoma" SIZE="5">v2</FONT></A><BR><FONT COLOR="#000000" FACE="Tahoma" SIZE="1">Provided by Microsoft Premier Field Engineering (<A HREF="http://www.microsoft.com/services/microsoftservices/srv_premier.mspx">PFE</A>)</FONT>' >> $h
    '</TD><TD><A HREF="http://pal.codeplex.com"><FONT COLOR="#000000" FACE="Tahoma" SIZE="10">PAL</FONT><FONT COLOR="#000000" FACE="Tahoma" SIZE="5">v2</FONT></A></FONT>' >> $h
    '</TD></TR></TABLE>' >> $h
    '<BR>' >> $h

    #///////////////////////
    #// Table of Contents
    #///////////////////////
    '<H4>On This Page</H4>' >> $h
    '<UL>' >> $h
        '<LI><A HREF="#ToolParameters">Tool Parameters</A></LI>' >> $h
        '<LI><A HREF="#AlertsbyChronologicalOrder">Alerts by Chronological Order</A></LI>' >> $h
        '<UL>' >> $h
        If ($alQuantizedTime -eq $null)
        {
            Write-Error 'None of the counters in the counter log match up to the threshold file. The counter log is either missing counters or is corrupted. Try opening this counter log in Performance Monitor to confirm the counters. Collect another counter log using the counters defined in the threshold file. Consider using the Export to Perfmon log template feature to collect the proper counters.'
            break;
        }
        For ($t=0;$t -lt $alQuantizedTime.Count;$t++)
        {
            $TimeRange = GetQuantizedTimeSliceTimeRange -TimeSliceIndex $t
            $HrefLink = "TimeRange_" + "$(ConvertStringForHref $TimeRange)"
            $NumOfAlerts = 0
            ForEach ($XmlAlert in $XmlAnalysis.SelectNodes('//ALERT'))
            {
                If (($XmlAlert.TIMESLICEINDEX -eq $t) -and ($(ConvertTextTrueFalse $XmlAlert.ISINTERNALONLY) -eq $False))
                {
                    $NumOfAlerts++
                }
            }
            
                '<LI><A HREF="#' + $HrefLink + '">' + $TimeRange + ' Alerts: (' + $NumOfAlerts + ')' + '</A></LI>' >> $h
        }
        '</UL>' >> $h
        ForEach ($Category in $global:alCategoryList)
        {
            $HrefLink = ConvertStringForHref $Category
            $HtmlCategory = '<LI><A HREF="#' + $HrefLink + '">' + "$Category" + '</A></LI>'
            $bHasHtmlCategoryBeenWritten = $False
            $IsCategoryEmpty = $True
            ForEach ($XmlAnalysisNode in $global:XmlAnalysis.SelectNodes('//ANALYSIS'))
            {
                If ($(ConvertTextTrueFalse $XmlAnalysisNode.ENABLED) -eq $True)
                {
                    $bThresholdsInAnalysis = $False
                    $bThresholdsInAnalysis = IsThresholdsInAnalysis -XmlAnalysis $XmlAnalysisNode
                    $IsAllCountersFound = ConvertTextTrueFalse $XmlAnalysisNode.AllCountersFound
                    $AnalysisCategory = $XmlAnalysisNode.CATEGORY
                    
                    If ($bThresholdsInAnalysis -eq $True)
                    {
                        If ($IsAllCountersFound -eq $True)
                        {
                            #// Count the number of alerts in each of the analyses for the TOC.
                            $NumOfAlerts = 0
                            ForEach ($XmlAlert in $XmlAnalysisNode.SelectNodes('./ALERT'))
                            {
                                If ($(ConvertTextTrueFalse $XmlAlert.ISINTERNALONLY) -eq $False)
                                {
                                    $NumOfAlerts++
                                }
                            }                        
                            If ($AnalysisCategory.ToLower() -eq $Category.ToLower())                    
                            {
                                If ($bHasHtmlCategoryBeenWritten -eq $False)
                                {
                                    $HtmlCategory >> $h
                                    '<UL>' >> $h
                                    $bHasHtmlCategoryBeenWritten = $True
                                    $IsCategoryEmpty = $False
                                }
                                $HrefLink = ConvertStringForHref $XmlAnalysisNode.NAME
                                '<LI><A HREF="#' + $HrefLink + '">' + $XmlAnalysisNode.NAME + ' (Alerts: ' + $NumOfAlerts + ')</A></LI>' >> $h
                            }
                        }
                    }
                    Else
                    {
                        If ($IsAllCountersFound -eq $True)
                        {
                            If ($AnalysisCategory.ToLower() -eq $Category.ToLower())
                            {
                                If ($bHasHtmlCategoryBeenWritten -eq $False)
                                {
                                    $HtmlCategory >> $h
                                    '<UL>' >> $h
                                    $bHasHtmlCategoryBeenWritten = $True
                                    $IsCategoryEmpty = $False
                                }
                                $HrefLink = ConvertStringForHref $XmlAnalysisNode.NAME
                                '<LI><A HREF="#' + $HrefLink + '">' + $XmlAnalysisNode.NAME + ' (Stats only)</A></LI>' >> $h
                            }
                        }
                    }
                }
            }
            If ($IsCategoryEmpty -eq $False)
            {
                '</UL>' >> $h
            }
        }
        '<LI><A HREF="#Disclaimer">Disclaimer</A></LI>' >> $h
    '</UL>' >> $h
    '<BR>' >> $h
    '<A HREF="#top">Back to the top</A><BR>' >> $h

    #///////////////////////
    #// Tool Parameters
    #///////////////////////
    '<TABLE BORDER=0 WIDTH=50%>' >> $h
    '<TR><TD>' >> $h
    '<H1><A NAME="ToolParameters">Tool Parameters:</A></H1>' >> $h
    '<HR>' >> $h
    '</TD></TR>' >> $h
    '</TABLE>' >> $h
    '<TABLE BORDER=0 CELLPADDING=5>' >> $h
    '<TR><TH WIDTH=300 BGCOLOR="#000000"><FONT COLOR="#FFFFFF">Name</FONT></TH><TH BGCOLOR="#000000"><FONT COLOR="#FFFFFF">Value</FONT></TH></TR>' >> $h
    '<TR><TD WIDTH=300><B>Log Time Range: </B></TD><TD>' + $(GetLogTimeRange) + '</TD></TR>' >> $h
    '<TR><TD WIDTH=300><B>Log(s): </B></TD><TD>' + $Log + '</TD></TR>' >> $h
    '<TR><TD WIDTH=300><B>AnalysisInterval: </B></TD><TD>' + $(ConvertAnalysisIntervalIntoHumanReadableTime) + '</TD></TR>' >> $h
    '<TR><TD WIDTH=300><B>Threshold File: </B></TD><TD>' + $($ThresholdFile) + '</TD></TR>' >> $h
    '<TR><TD WIDTH=300><B>AllCounterStats: </B></TD><TD>' + $($AllCounterStats) + '</TD></TR>' >> $h    
    ForEach ($sKey in $htQuestionVariables.Keys)
    {
        '<TR><TD WIDTH=300><B>' + $sKey + ':</B></TD><TD>' + $($htQuestionVariables[$sKey]) + '</TD></TR>' >> $h
    }
    '</TABLE>' >> $h
    '<BR>' >> $h
    '<A HREF="#top">Back to the top</A><BR>' >> $h
    
    #///////////////////////
    #// Alerts in Chronological Order
    #///////////////////////
    '<TABLE BORDER=0 WIDTH=50%>' >> $h
    '<TR><TD>' >> $h
    '<H1><A NAME="AlertsbyChronologicalOrder">Alerts by Chronological Order</A></H1>' >> $h
    '<HR>' >> $h
    '</TD></TR>' >> $h
    '</TABLE>' >> $h
    '<BLOCKQUOTE><B>Description: </B> This section displays all of the alerts in chronological order.</BLOCKQUOTE>' >> $h
    '<BR>' >> $h
    '<CENTER>' >> $h
    '<H3>Alerts</H3>' >> $h
    '<TABLE BORDER=0 WIDTH=60%><TR><TD>' >> $h
    'An alert is generated if any of the thresholds were broken during one of the time ranges analyzed. The background of each of the values represents the highest priority threshold that the value broke. See each of the counter' + "'" + 's respective analysis section for more details about what the threshold means.' >> $h
    '</TD></TR></TABLE>' >> $h
    '<BR>' >> $h
    $IsAlerts = $False
    :IsAlerts ForEach ($XmlAlert in $XmlAnalysis.SelectNodes('//ALERT'))
    {
        $IsAlerts = $True
        break IsAlerts
    }
    
    If ($IsAlerts -eq $False)
    {
        '<TABLE BORDER=1 CELLPADDING=5>' >> $h
        '<TR><TH>No Alerts Found</TH></TR>' >> $h
        '</TABLE>' >> $h
    }
    Else
    {
        '<TABLE BORDER=1 CELLPADDING=2>' >> $h
        '<TR><TH>Time Range</TH><TH></TH><TH></TH><TH></TH><TH></TH><TH></TH><TH></TH></TR>' >> $h
        For ($t=0;$t -lt $alQuantizedTime.Count;$t++)
        {
            $IsAnyAlertsInQuantizedTimeSlice = $False
            $TimeRange = GetQuantizedTimeSliceTimeRange -TimeSliceIndex $t
            $HrefLink = "TimeRange_" + "$(ConvertStringForHref $TimeRange)"
            :AlertInQuantizedTimeSliceLoopCheck ForEach ($XmlAlert in $XmlAnalysis.SelectNodes('//ALERT'))
            {
                If (($XmlAlert.TIMESLICEINDEX -eq $t) -and ($(ConvertTextTrueFalse $XmlAlert.ISINTERNALONLY) -eq $False))
                {
                    $IsAnyAlertsInQuantizedTimeSlice = $True
                    Break AlertInQuantizedTimeSliceLoopCheck
                }
            }            
            
            If ($IsAnyAlertsInQuantizedTimeSlice -eq $True)
            {
                '<TR><TH><A NAME="' + $HrefLink + '">' + $TimeRange + '</A></TH><TH>Condition</TH><TH>Counter</TH><TH>Min</TH><TH>Avg</TH><TH>Max</TH><TH>Hourly Trend</TH></TR>' >> $h
                ForEach ($XmlAlert in $XmlAnalysis.SelectNodes('//ALERT'))
                {
                    $HrefLink = ConvertStringForHref $XmlAlert.PARENTANALYSIS
                    If (($XmlAlert.TIMESLICEINDEX -eq $t) -and ($(ConvertTextTrueFalse $XmlAlert.ISINTERNALONLY) -eq $False))
                    {
                        [string] $sPart00 = '<TR><TD></TD><TD BGCOLOR="' + $($XmlAlert.CONDITIONCOLOR) + '"><A HREF="#' + $HrefLink + '">'
                        [string] $sPart01 = Add-WhiteFont -Text $($XmlAlert.CONDITIONNAME) -Color $($XmlAlert.CONDITIONCOLOR)
                        [string] $sPart02 = '</A></TD><TD>' + $($XmlAlert.COUNTER) + '</TD><TD BGCOLOR="' + $($XmlAlert.MINCOLOR) + '">'
                        [string] $sPart03 = Add-WhiteFont -Text $(AddThousandsSeparator -Value $XmlAlert.MIN) -Color $($XmlAlert.MINCOLOR)
                        [string] $sPart04 = '</TD><TD BGCOLOR="' + $($XmlAlert.AVGCOLOR) + '">'
                        [string] $sPart05 = Add-WhiteFont -Text $(AddThousandsSeparator -Value $XmlAlert.AVG) -Color $($XmlAlert.AVGCOLOR)
                        [string] $sPart06 = '</TD><TD BGCOLOR="' + $($XmlAlert.MAXCOLOR) + '">'
                        [string] $sPart07 = Add-WhiteFont -Text $(AddThousandsSeparator -Value $XmlAlert.MAX) -Color $($XmlAlert.MAXCOLOR)
                        [string] $sPart08 = '</TD><TD BGCOLOR="' + $($XmlAlert.TRENDCOLOR) + '">'
                        [string] $sPart09 = Add-WhiteFont -Text $(AddThousandsSeparator -Value $XmlAlert.TREND) -Color $($XmlAlert.TRENDCOLOR)
                        [string] $sPart10 = '</TD></TR>'
                        #'<TR><TD></TD><TD BGCOLOR="' + $($XmlAlert.CONDITIONCOLOR) + '"><A HREF="#' + $HrefLink + '">' + $($XmlAlert.CONDITIONNAME) + '</A></TD><TD>' + $($XmlAlert.COUNTER) + '</TD><TD BGCOLOR="' + $($XmlAlert.MINCOLOR) + '">' + $(AddThousandsSeparator -Value $XmlAlert.MIN) + '</TD><TD BGCOLOR="' + $($XmlAlert.AVGCOLOR) + '">' + $(AddThousandsSeparator -Value $XmlAlert.AVG) + '</TD><TD BGCOLOR="' + $($XmlAlert.MAXCOLOR) + '">' + $(AddThousandsSeparator -Value $XmlAlert.MAX) + '</TD><TD BGCOLOR="' + $($XmlAlert.TRENDCOLOR) + '">' + $(AddThousandsSeparator -Value $XmlAlert.TREND) + '</TD></TR>' >> $h
                        $sPart00 + $sPart01 + $sPart02 + $sPart03 + $sPart04 + $sPart05 + $sPart06 + $sPart07 + $sPart08 + $sPart09 + $sPart10 >> $h
                    }
                }
            }
        }
        '</TABLE>' >> $h
    }
    '</CENTER>' >> $h
    
    ForEach ($Category in $global:alCategoryList)
    {
        #///////////////////////
        #// Category
        #///////////////////////
        #'<A HREF="#top">Back to the top</A><BR>' >> $h
        $HrefLink = ConvertStringForHref $Category
        $bHasHtmlCategoryBeenWritten = $False
        $HtmlCategoryHeader = '<TABLE BORDER=0 WIDTH=50%><TR><TD>' + '<H1><A NAME="' + $HrefLink + '">' + "$Category" + '</A></H1><HR></TD></TR></TABLE>'
        #'<TABLE BORDER=0 WIDTH=50%>' >> $h
        #'<TR><TD>' >> $h        
        #'<H1><A NAME="' + $HrefLink + '">' + "$Category" + '</A></H1>' >> $h
        #'<HR>' >> $h
        #'</TD></TR>' >> $h
        #'</TABLE>' >> $h
        ForEach ($XmlAnalysisNode in $global:XmlAnalysis.SelectNodes('//ANALYSIS'))
        {
            #///////////////////////
            #// Analysis
            #///////////////////////            
            If ($(ConvertTextTrueFalse $XmlAnalysisNode.ENABLED) -eq $True)
            {
                $IsAllCountersFound = ConvertTextTrueFalse $XmlAnalysisNode.AllCountersFound
                $AnalysisCategory = $XmlAnalysisNode.CATEGORY
                If ($IsAllCountersFound -eq $True)
                {
                    If ($AnalysisCategory.ToLower() -eq $Category.ToLower())
                    {
                        If ($bHasHtmlCategoryBeenWritten -eq $False)
                        {
                            $HtmlCategoryHeader >> $h
                            $bHasHtmlCategoryBeenWritten = $True
                        }
                        $HrefLink = ConvertStringForHref $XmlAnalysisNode.NAME
                        '<H2><A NAME="' + $HrefLink + '">' + $XmlAnalysisNode.NAME + '</A></H2>' >> $h
                        #/////////////////
                        #// Description
                        #/////////////////
                        $IsAllCountersFound = ConvertTextTrueFalse $XmlAnalysisNode.AllCountersFound
                        If (($(Test-property -InputObject $XmlAnalysisNode -Name 'DESCRIPTION') -eq $True) -and ($IsAllCountersFound -eq $True))
                        {
                            $sDescription = $XmlAnalysisNode.DESCRIPTION.get_innertext()
                            '<BLOCKQUOTE><B>Description:</B> ' + $sDescription + '</BLOCKQUOTE>' >> $h
                            '<BR>' >> $h                        
                        }                        
                        
                        #///////////////////////
                        #// Chart
                        #///////////////////////
                        ForEach ($XmlChart in $XmlAnalysisNode.SelectNodes('./CHART'))
                        {
                            If ($(Test-property -InputObject $XmlChart -Name 'FILEPATHS') -eq $True)
                            {
                                If ($XmlChart.FILEPATHS -ne $null) #// Added by Andy from Codeplex.com
                                {
                                    $aFilePaths = $XmlChart.FILEPATHS.Split(',')

                                    If ($(Test-property -InputObject $XmlChart -Name 'ISTHRESHOLDSADDED') -eq $False)
                                    {
                                        SetXmlChartIsThresholdAddedAttribute -XmlChart $XmlChart
                                    }                                    
                                    
        							If ($(ConvertTextTrueFalse $XmlChart.ISTHRESHOLDSADDED) -eq $True)
        							{
                                        If (($(Test-property -InputObject $XmlChart -Name 'MINWARNINGVALUE') -eq $True) -and ($(Test-property -InputObject $XmlChart -Name 'MAXWARNINGVALUE') -eq $True))
                                        {
                                            $IsWarningValuesExist = $True
                                        }
                                        Else
                                        {
                                            $IsWarningValuesExist = $False
                                        }
                                        If (($(Test-property -InputObject $XmlChart -Name 'MINCRITICALVALUE') -eq $True) -and ($(Test-property -InputObject $XmlChart -Name 'MAXCRITICALVALUE') -eq $True))
                                        {
                                            $IsCriticalValuesExist = $True
                                        }
                                        Else
                                        {
                                            $IsCriticalValuesExist = $False
                                        }
                                        If (($IsWarningValuesExist -eq $True) -and ($IsCriticalValuesExist -eq $True))
                                        {
        								    $sAltText = "$($XmlChart.CHARTTITLE)`n" + $(If ($($XmlChart.MINWARNINGVALUE) -ne ''){'Warning Range: ' + "$(AddThousandsSeparator -Value $XmlChart.MINWARNINGVALUE)" + ' to ' + "$(AddThousandsSeparator -Value $XmlChart.MAXWARNINGVALUE)`n"}) + $(If ($($XmlChart.MINCRITICALVALUE) -ne ''){'Critical Range: ' + "$(AddThousandsSeparator -Value $XmlChart.MINCRITICALVALUE)" + ' to ' + "$(AddThousandsSeparator -Value $XmlChart.MAXCRITICALVALUE)"})
                                        }
                                        Else
                                        {
                                            If ($IsWarningValuesExist -eq $True)
                                            {
                                                $sAltText = "$($XmlChart.CHARTTITLE)`n" + $(If ($($XmlChart.MINWARNINGVALUE) -ne ''){'Warning Range: ' + "$(AddThousandsSeparator -Value $XmlChart.MINWARNINGVALUE)" + ' to ' + "$(AddThousandsSeparator -Value $XmlChart.MAXWARNINGVALUE)"})
                                            }
                                            Else
                                            {
                                                $sAltText = "$($XmlChart.CHARTTITLE)`n" + $(If ($($XmlChart.MINCRITICALVALUE) -ne ''){'Critical Range: ' + "$(AddThousandsSeparator -Value $XmlChart.MINCRITICALVALUE)" + ' to ' + "$(AddThousandsSeparator -Value $XmlChart.MAXCRITICALVALUE)"})
                                            }
                                        }
        							}
        							Else
        							{
        								$sAltText = "$($XmlChart.CHARTTITLE)"
        							}
                                    ForEach ($sFilePath in $aFilePaths)
                                    {
                                        '<CENTER><IMG SRC=' + '"' + "$sFilePath" + '"' + ' ALT="' + $sAltText + '"></CENTER><BR>' >> $h
                                    }
                                }
                                Else
                                {
                                    '<CENTER><table border=1 cellpadding=10><tr><td><FONT COLOR="#000000" FACE="Tahoma" SIZE="4">No data to chart</font></td></tr></table></CENTER><BR>' >> $h
                                }
                            }
                            Else
                            {
                                '<CENTER><table border=1 cellpadding=10><tr><td><FONT COLOR="#000000" FACE="Tahoma" SIZE="4">No data to chart</font></td></tr></table></CENTER><BR>' >> $h
                            }                            
                        }
                        #///////////////////////
                        #// Counter Stats
                        #///////////////////////
                        '<CENTER>' >> $h
                        '<H3>Overall Counter Instance Statistics</H3>' >> $h
                        '<TABLE BORDER=0 WIDTH=60%><TR><TD>' >> $h
                        'Overall statistics of each of the counter instances. Min, Avg, and Max are the minimum, average, and Maximum values in the entire log. Hourly Trend is the calculated hourly slope of the entire log. 10%, 20%, and 30% of Outliers Removed is the average of the values after the percentage of outliers furthest away from the average have been removed. This is to help determine if a small percentage of the values are extreme which can skew the average.' >> $h
                        '</TD></TR></TABLE><BR>' >> $h
                        #// Get the number of thresholds to determine if the counter stat condition is OK or never checked.
                        $iNumberOfThresholds = 0
                        ForEach ($XmlThreshold in $XmlAnalysisNode.SelectNodes('./THRESHOLD'))
                        {
                            $iNumberOfThresholds++
                        }                        
                        ForEach ($XmlChart in $XmlAnalysisNode.SelectNodes('./CHART'))
                        {
                            ForEach ($XmlDataSource in $XmlAnalysisNode.SelectNodes('./DATASOURCE'))
                            {
                                If ($XmlDataSource.EXPRESSIONPATH -eq $XmlChart.DATASOURCE)
                                {
                                    '<TABLE ID="table' + "$iTableCounter" + '" BORDER=1 CELLPADDING=2>' >> $h
                                    $iTableCounter++
                                    '<TR><TH><B>Condition</B></TH><TH><B>' + "$($XmlChart.DATASOURCE)" + '</B></TH><TH><B>Min</B></TH><TH><B>Avg</B></TH><TH><B>Max</B></TH><TH><B>Hourly Trend</B></TH><TH><B>Std Deviation</B></TH><TH><B>10% of Outliers Removed</B></TH><TH><B>20% of Outliers Removed</B></TH><TH><B>30% of Outliers Removed</B></TH></TR>' >> $h                                
                                    ForEach ($XmlCounterInstance in $XmlDataSource.SelectNodes('./COUNTERINSTANCE'))
                                    {
                                        If ($(Test-XmlBoolAttribute -InputObject $XmlCounterInstance -Name 'ISINTERNALONLY') -eq $True)
                                        {
                                            $IsInternalOnly = $True
                                        }
                                        Else
                                        {
                                            $IsInternalOnly = $False
                                        }
                                        If ($IsInternalOnly -eq $False)
                                        {
                                            $IsAlertOnOverallCounterStatInstance = $False
                                            #// Search for the INTERNAL ONLY COUNTER instance that matches this one.
                                            :InternalOnlyAlertLoop ForEach ($XmlAlert in $XmlAnalysisNode.SelectNodes('./ALERT'))
                                            {
                                                If ($(ConvertTextTrueFalse $XmlAlert.ISINTERNALONLY) -eq $True)
                                                {
                                                    [string] $InternalCounterPath = $XmlAlert.COUNTER
                                                    $InternalCounterPath = $InternalCounterPath.Replace('INTERNAL_OVERALL_COUNTER_STATS_','')
                                                    If ($InternalCounterPath -eq $XmlCounterInstance.COUNTERPATH)
                                                    {
                                                        $IsAlertOnOverallCounterStatInstance = $True
                                                        #// Check if this is a named instance of SQL Server
                                                        If (($XmlCounterInstance.COUNTEROBJECT.Contains('MSSQL$') -eq $True) -or ($XmlCounterInstance.COUNTEROBJECT.Contains('MSOLAP$') -eq $True))
                                                        {
                                                            $sSqlNamedInstance = ExtractSqlNamedInstanceFromCounterObjectPath -sCounterObjectPath $XmlCounterInstance.COUNTEROBJECT
                                                            If ($XmlCounterInstance.COUNTERINSTANCE -eq "")
                                                            {
                                                                $sCounterInstance = $XmlCounterInstance.COUNTERCOMPUTER + "/" + $sSqlNamedInstance
                                                            }
                                                            Else
                                                            {
                                                                $sCounterInstance = $XmlCounterInstance.COUNTERCOMPUTER + "/" + $sSqlNamedInstance + '/' + "$($XmlCounterInstance.COUNTERINSTANCE)"
                                                            }                                                            
                                                        }
                                                        Else
                                                        {
                                                            If ($XmlCounterInstance.COUNTERINSTANCE -eq "")
                                                            {
                                                                $sCounterInstance = $XmlCounterInstance.COUNTERCOMPUTER
                                                            }
                                                            Else
                                                            {
                                                                $sCounterInstance = "$($XmlCounterInstance.COUNTERCOMPUTER)" + '/' + "$($XmlCounterInstance.COUNTERINSTANCE)"
                                                            }
                                                        }
                                                        #'<TR><TD BGCOLOR="' + $XmlAlert.CONDITIONCOLOR + '">' + $(Add-WhiteFont -Text $XmlAlert.CONDITIONNAME -Color $XmlAlert.CONDITIONCOLOR) + '</TD><TD>' + $sCounterInstance + '</TD><TD BGCOLOR="' + $XmlAlert.MINCOLOR + '">' + $(Add-WhiteFont -Text $(AddThousandsSeparator -Value $XmlCounterInstance.MIN) -Color $XmlAlert.MINCOLOR) + '</TD><TD BGCOLOR="' + $XmlAlert.AVGCOLOR + '">' + $(AddThousandsSeparator -Value $XmlCounterInstance.AVG) + '</TD><TD BGCOLOR="' + $XmlAlert.MAXCOLOR + '">' + $(AddThousandsSeparator -Value $XmlCounterInstance.MAX) + '</TD><TD BGCOLOR="' + $XmlAlert.TRENDCOLOR + '">' + $(AddThousandsSeparator -Value $XmlCounterInstance.TREND) + '</TD><TD>' + $(AddThousandsSeparator -Value $XmlCounterInstance.STDDEV) + '</TD><TD>' + $(AddThousandsSeparator -Value $XmlCounterInstance.PERCENTILENINETYTH) + '</TD><TD>' + $(AddThousandsSeparator -Value $XmlCounterInstance.PERCENTILEEIGHTYTH) + '</TD><TD>' + $(AddThousandsSeparator -Value $XmlCounterInstance.PERCENTILESEVENTYTH) + '</TD></TR>' >> $h
                                                        '<TR><TD BGCOLOR="' + $XmlAlert.CONDITIONCOLOR + '">' + $(Add-WhiteFont -Text $XmlAlert.CONDITIONNAME -Color $XmlAlert.CONDITIONCOLOR) + '</TD><TD>' + $sCounterInstance + '</TD><TD BGCOLOR="' + $XmlAlert.MINCOLOR + '">' + $(Add-WhiteFont -Text $(AddThousandsSeparator -Value $XmlCounterInstance.MIN) -Color $XmlAlert.MINCOLOR) + '</TD><TD BGCOLOR="' + $XmlAlert.AVGCOLOR + '">' + $(Add-WhiteFont -Text $(AddThousandsSeparator -Value $XmlCounterInstance.AVG) -Color $XmlAlert.AVGCOLOR) + '</TD><TD BGCOLOR="' + $XmlAlert.MAXCOLOR + '">' + $(Add-WhiteFont -Text $(AddThousandsSeparator -Value $XmlCounterInstance.MAX) -Color $XmlAlert.MAXCOLOR) + '</TD><TD BGCOLOR="' + $XmlAlert.TRENDCOLOR + '">' + $(Add-WhiteFont -Text $(AddThousandsSeparator -Value $XmlCounterInstance.TREND) -Color $XmlAlert.TRENDCOLOR) + '</TD><TD>' + $(AddThousandsSeparator -Value $XmlCounterInstance.STDDEV) + '</TD><TD>' + $(AddThousandsSeparator -Value $XmlCounterInstance.PERCENTILENINETYTH) + '</TD><TD>' + $(AddThousandsSeparator -Value $XmlCounterInstance.PERCENTILEEIGHTYTH) + '</TD><TD>' + $(AddThousandsSeparator -Value $XmlCounterInstance.PERCENTILESEVENTYTH) + '</TD></TR>' >> $h
                                                        Break InternalOnlyAlertLoop                                                        
                                                    }
                                                }
                                            }
                                            If ($IsAlertOnOverallCounterStatInstance -eq $False)
                                            {
                                                #// Check if this is a named instance of SQL Server
                                                If (($XmlCounterInstance.COUNTEROBJECT.Contains('MSSQL$') -eq $True) -or ($XmlCounterInstance.COUNTEROBJECT.Contains('MSOLAP$') -eq $True))
                                                {
                                                    $sSqlNamedInstance = ExtractSqlNamedInstanceFromCounterObjectPath -sCounterObjectPath $XmlCounterInstance.COUNTEROBJECT
                                                    If ($XmlCounterInstance.COUNTERINSTANCE -eq "")
                                                    {
                                                        $sCounterInstance = $XmlCounterInstance.COUNTERCOMPUTER + "/" + $sSqlNamedInstance
                                                    }
                                                    Else
                                                    {
                                                        $sCounterInstance = $XmlCounterInstance.COUNTERCOMPUTER + "/" + $sSqlNamedInstance + '/' + "$($XmlCounterInstance.COUNTERINSTANCE)"
                                                    }                                                    
                                                }
                                                Else
                                                {
                                                    If ($XmlCounterInstance.COUNTERINSTANCE -eq "")
                                                    {
                                                        $sCounterInstance = $XmlCounterInstance.COUNTERCOMPUTER
                                                    }
                                                    Else
                                                    {
                                                        $sCounterInstance = "$($XmlCounterInstance.COUNTERCOMPUTER)" + '/' + "$($XmlCounterInstance.COUNTERINSTANCE)"
                                                    }
                                                }
                                                #// If the number of thresholds is zero, then do not put in OK.
                                                If ($iNumberOfThresholds -gt 0)
                                                {
                                                    '<TR><TD BGCOLOR="#00FF00">OK</TD><TD>' + $sCounterInstance + '</TD><TD>' + $(AddThousandsSeparator -Value $XmlCounterInstance.MIN) + '</TD><TD>' + $(AddThousandsSeparator -Value $XmlCounterInstance.AVG) + '</TD><TD>' + $(AddThousandsSeparator -Value $XmlCounterInstance.MAX) + '</TD><TD>' + $(AddThousandsSeparator -Value $XmlCounterInstance.TREND) + '</TD><TD>' + $(AddThousandsSeparator -Value $XmlCounterInstance.STDDEV) + '</TD><TD>' + $(AddThousandsSeparator -Value $XmlCounterInstance.PERCENTILENINETYTH) + '</TD><TD>' + $(AddThousandsSeparator -Value $XmlCounterInstance.PERCENTILEEIGHTYTH) + '</TD><TD>' + $(AddThousandsSeparator -Value $XmlCounterInstance.PERCENTILESEVENTYTH) + '</TD></TR>' >> $h
                                                }
                                                Else
                                                {
                                                    '<TR><TD>No Thresholds</TD><TD>' + $sCounterInstance + '</TD><TD>' + $(AddThousandsSeparator -Value $XmlCounterInstance.MIN) + '</TD><TD>' + $(AddThousandsSeparator -Value $XmlCounterInstance.AVG) + '</TD><TD>' + $(AddThousandsSeparator -Value $XmlCounterInstance.MAX) + '</TD><TD>' + $(AddThousandsSeparator -Value $XmlCounterInstance.TREND) + '</TD><TD>' + $(AddThousandsSeparator -Value $XmlCounterInstance.STDDEV) + '</TD><TD>' + $(AddThousandsSeparator -Value $XmlCounterInstance.PERCENTILENINETYTH) + '</TD><TD>' + $(AddThousandsSeparator -Value $XmlCounterInstance.PERCENTILEEIGHTYTH) + '</TD><TD>' + $(AddThousandsSeparator -Value $XmlCounterInstance.PERCENTILESEVENTYTH) + '</TD></TR>' >> $h
                                                }                                                
                                            }
                                        }
                                    }
                                    '</TABLE>' >> $h
                                    '<BR>' >> $h
                                }
                            }
                        }
                        '</CENTER>' >> $h
                        '<BR>' >> $h
                        
                        #///////////////////////
                        #// Alerts
                        #///////////////////////
                        '<CENTER>' >> $h
                        '<H3>Alerts</H3>' >> $h
                        '<TABLE BORDER=0 WIDTH=60%><TR><TD>' >> $h
                        'An alert is generated if any of the thresholds were broken during one of the time ranges analyzed. The background of each of the values represents the highest priority threshold that the value broke. See each of the counter' + "'" + 's respective analysis section for more details about what the threshold means.' >> $h
                        '</TD></TR></TABLE>' >> $h
                        
                        #// Check if no alerts are found.
                        $IsAlertFound = $False
                        :IsAlertsLoop ForEach ($XmlAlert in $XmlAnalysisNode.SelectNodes('./ALERT'))
                        {
                            $IsAlertFound = $True
                            Break IsAlertsLoop
                        }
                        
                        If ($IsAlertFound -eq $False)
                        {
                            '<TABLE BORDER=1 CELLPADDING=5>' >> $h
                            '<TR><TH>No Alerts Found</TH></TR>' >> $h
                            '</TABLE>' >> $h
                            '<BR>' >> $h
                        }
                        Else
                        {
                            '<TABLE BORDER=1 CELLPADDING=2>' >> $h
                            '<TR><TH>Time Range</TH><TH></TH><TH></TH><TH></TH><TH></TH><TH></TH><TH></TH></TR>' >> $h
                            For ($t=0;$t -lt $alQuantizedTime.Count;$t++)
                            {
                                $IsAnyAlertsInQuantizedTimeSlice = $False
                                $TimeRange = GetQuantizedTimeSliceTimeRange -TimeSliceIndex $t
                                $HrefLink = "TimeRange_" + "$(ConvertStringForHref $TimeRange)"
                                :AlertInQuantizedTimeSliceLoopCheck ForEach ($XmlAlert in $XmlAnalysisNode.SelectNodes('./ALERT'))
                                {                                
                                    If (($XmlAlert.TIMESLICEINDEX -eq $t) -and ($(ConvertTextTrueFalse $XmlAlert.ISINTERNALONLY) -eq $False))
                                    {
                                        $IsAnyAlertsInQuantizedTimeSlice = $True
                                        Break AlertInQuantizedTimeSliceLoopCheck
                                    }
                                }
                                If ($IsAnyAlertsInQuantizedTimeSlice -eq $True)
                                {
                                    '<TR><TH><A HREF="#' + $HrefLink + '">' + $TimeRange + '</A></TH><TH>Condition</TH><TH>Counter</TH><TH>Min</TH><TH>Avg</TH><TH>Max</TH><TH>Hourly Trend</TH></TR>' >> $h
                                    ForEach ($XmlAlert in $XmlAnalysisNode.SelectNodes('./ALERT'))
                                    {                                
                                        If (($XmlAlert.TIMESLICEINDEX -eq $t) -and ($(ConvertTextTrueFalse $XmlAlert.ISINTERNALONLY) -eq $False))
                                        {
                                            '<TR><TD></TD><TD BGCOLOR="' + $($XmlAlert.CONDITIONCOLOR) + '">' + $(Add-WhiteFont -Text $($XmlAlert.CONDITIONNAME) -Color $($XmlAlert.CONDITIONCOLOR)) + '</TD><TD>' + $($XmlAlert.COUNTER) + '</TD><TD BGCOLOR="' + $($XmlAlert.MINCOLOR) + '">' + $(Add-WhiteFont -Text $(AddThousandsSeparator -Value $XmlAlert.MIN) -Color $($XmlAlert.MINCOLOR)) + '</TD><TD BGCOLOR="' + $($XmlAlert.AVGCOLOR) + '">' + $(Add-WhiteFont -Text $(AddThousandsSeparator -Value $XmlAlert.AVG) -Color $($XmlAlert.AVGCOLOR)) + '</TD><TD BGCOLOR="' + $($XmlAlert.MAXCOLOR) + '">' + $(Add-WhiteFont -Text $(AddThousandsSeparator -Value $XmlAlert.MAX) -Color $($XmlAlert.MAXCOLOR)) + '</TD><TD BGCOLOR="' + $($XmlAlert.TRENDCOLOR) + '">' + $(Add-WhiteFont -Text $(AddThousandsSeparator -Value $XmlAlert.TREND) -Color $($XmlAlert.TRENDCOLOR)) + '</TD></TR>' >> $h
                                        }
                                    }
                                }
                            }                        
                            '</TABLE>' >> $h
                        }
                    '</CENTER>' >> $h                    
                    '<A HREF="#top">Back to the top</A><BR>' >> $h
                    }
                }                
            }
        }
        '<BR>' >> $h
    }
    '<A HREF="#top">Back to the top</A><BR>' >> $h
    '<BR><BR><TABLE BORDER="1" CELLPADDING="5"><TR><TD BGCOLOR="Silver"><A NAME="Disclaimer"><B>Disclaimer:</B></A> This report was generated using the Performance Analysis of Logs (PAL) tool. The information provided in this report is provided "as is" and is intended for information purposes only. The authors and contributors of this tool take no responsibility for damages or losses incurred by use of this tool.</TD></TR></TABLE>' >> $h
    '</BODY>' >> $h
    '</HTML>' >> $h
    Write-Host 'Done'
}

Function SaveXmlReport
{
    If ($IsOutputXml -eq $True)
    {
        $XmlAnalysis.Save($global:XmlReportFilePath)
    }    
}

Function OpenHtmlReport
{
    param()
    If ($IsOutputHtml -eq $False)
    {
        Return
    }    
    $htHtmlReport["ReportFilePath"]
    #// The ambersand is needed because there might be spaces in the file path to the HTML report.
    $HtmlReportFilePath = $htHtmlReport["ReportFilePath"]
    Invoke-Expression -Command "&'$HtmlReportFilePath'"    
}

Function GenerateThresholdFileCounterList
{
    Write-Host 'Generating the counter list to filter on...' -NoNewline
    $p = $global:htScript["SessionWorkingDirectory"] + '\CounterListFilter.txt'
    $c = New-Object System.Collections.ArrayList
    ForEach ($XmlAnalysisInstance in $XmlAnalysis.SelectNodes('//ANALYSIS'))
    {
        If ($(ConvertTextTrueFalse $XmlAnalysisInstance.ENABLED) -eq $True)
        {
            ForEach ($XmlAnalysisDataSourceInstance in $XmlAnalysisInstance.SelectNodes('./DATASOURCE'))
            {
                If ($XmlAnalysisDataSourceInstance.TYPE -eq 'CounterLog')
                {
                    If ($(Test-property -InputObject $XmlAnalysisDataSourceInstance -Name 'ISCOUNTEROBJECTREGULAREXPRESSION') -eq $True)
                    {
                        If ($(ConvertTextTrueFalse $XmlAnalysisDataSourceInstance.ISCOUNTEROBJECTREGULAREXPRESSION) -eq $True)
                        {
                            #//$sCounterObject = GetCounterObject -sCounterPath $XmlAnalysisDataSourceInstance.EXPRESSIONPATH
                            $sCounterName = GetCounterName -sCounterPath $XmlAnalysisDataSourceInstance.EXPRESSIONPATH
                            $sCounterInstance = GetCounterInstance -sCounterPath $XmlAnalysisDataSourceInstance.EXPRESSIONPATH
                            If ($sCounterInstance -eq '')
                            {
                                $sNewExpressionPath = '\' + '*' + '\' + "$sCounterName"
                            }
                            Else
                            {
                                $sNewExpressionPath = '\' + '*' + '(' + "$sCounterInstance" + ')\' + "$sCounterName"
                            }
                            #$sNewExpressionPath | Out-File -FilePath $c -Encoding 'ASCII' -Append
                            $c += $sNewExpressionPath
                        }
                        Else
                        {
                            #$XmlAnalysisDataSourceInstance.EXPRESSIONPATH | Out-File -FilePath $c -Encoding 'ASCII' -Append
                            $c += $XmlAnalysisDataSourceInstance.EXPRESSIONPATH
                        }
                    }
                    Else
                    {
                        #$XmlAnalysisDataSourceInstance.EXPRESSIONPATH | Out-File -FilePath $c -Encoding 'ASCII' -Append
                        $c += $XmlAnalysisDataSourceInstance.EXPRESSIONPATH
                    }
                }
            }
        }
    }
    Write-Host 'Done'
    Write-Host 'Removing duplicate counter expressions from counter list...' -NoNewline
    #// Remove duplicate counter expression paths
    $c = $c | select -uniq
    $c | Out-File -FilePath $p -Encoding 'ASCII'
    $global:sCounterListFilterFilePath = $p
    Write-Host 'Done'
    Write-Host ''
}

Function Set-EnglishLocales
{
    param()
    #// Provided by user mafalt. Thank you!
    $global:originalCulture = (Get-Culture)
    $usenglishLocales = new-object System.Globalization.CultureInfo "en-US"   
    $global:currentThread.CurrentCulture = $usenglishLocales
    $global:currentThread.CurrentUICulture = $usenglishLocales
}

Function Restore-Locales
{
    param()
    #// Provided by user mafalt. Thank you!
    $global:currentThread.CurrentCulture = $global:originalCulture
    $global:currentThread.CurrentUICulture = $global:originalCulture
}

Function GlobalizationCheck
{
    $sDisplayName = (Get-Culture).DisplayName
	Write-Host "Your locale is set to: $sDisplayName"
	If ($($sDisplayName.Contains('English')) -eq $false)
	{
        $global:bEnglishLocale = $false
        Set-EnglishLocales
		#// Write-Error 'PAL v2.0 currently only supports English (United States) localization. Please go to Control Panel and change your "Region and Language" settings to be English (United States). We apologize for this inconvenience. Please keep in mind that PAL is an open source project, we welcome help in this area. PAL is capable of non-English languages, but simply needs threshold files written in those languages.'
        #// Break Main;
	}
    Else
    {
        $global:bEnglishLocale = $true
    }
}

#/////////////////////
#// Main
#/////////////////////

Function Main
{
    param($MainArgs)
    InitializeGlobalVariables    
	#StartDebugLogFile $global:htScript["UserTempDirectory"] 0
	ShowMainHeader
    GlobalizationCheck
   	ProcessArgs -MyArgs $MainArgs
	CreateSessionWorkingDirectory
	Get-DateTimeStamp
	ResolvePALStringVariablesForPALArguments
	CreateFileSystemResources
	$global:XmlAnalysis = ReadThresholdFileIntoMemory -sThresholdFilePath $ThresholdFile
	InheritFromThresholdFiles -sThresholdFilePath $ThresholdFile
    ""
    "Threshold File Load History:"
	$global:alThresholdFilePathLoadHistory
    ""
    GenerateThresholdFileCounterList
    If ($global:IsCounterLogFile -eq $True)
    {
        If ($global:BeginTime -eq $null)
        {
            MergeConvertFilterPerfmonLogs -sPerfmonLogPaths $Log
        }
        Else
        {
            MergeConvertFilterPerfmonLogs -sPerfmonLogPaths $Log -BeginTime $global:BeginTime -EndTime $global:EndTime
        }    
    	If ($AllCounterStats -eq $True)
    	{
        	$global:XmlAnalysis = AddAllCountersFromPerfmonLog -XmlAnalysis $global:XmlAnalysis -sPerfLogFilePath $global:sFirstCounterLogFilePath
    	}
    }
    GenerateXmlCounterList
    Write-Host ''
    SetDefaultQuestionVariables -XmlAnalysis $global:XmlAnalysis
	Analyze
	PrepareDataForReport
	GenerateHtml
    SaveXmlReport
    OpenHtmlReport
    #StopDebugLogFile
    If ($global:bEnglishLocale -eq $false)
    {
        Restore-Locales
    }
}
Main -MainArgs $args
CleanUp
OnEnd
