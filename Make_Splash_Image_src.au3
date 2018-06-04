#NoTrayIcon
#Region ;**** Directives created by AutoIt3Wrapper_GUI ****
#AutoIt3Wrapper_Outfile_x64=Make_Splash_Image.exe
#AutoIt3Wrapper_Change2CUI=y
#EndRegion ;**** Directives created by AutoIt3Wrapper_GUI ****
#cs ----------------------------------------------------------------------------

 AutoIt Version: 3.3.14.5
 Author:         CosmicDan

 Script Function:
	Generate splash.img of all five images for tissot (Mi A1)

#ce ----------------------------------------------------------------------------

#include <File.au3>

#include "bin\Binary.au3"
#include "bin\IsPressed_UDF.au3"

; ------------------------------ Constants

Global Const $aInFiles[] = [ _
	@ScriptDir & "\input\01.png", _
	@ScriptDir & "\input\02.png", _
	@ScriptDir & "\input\03.png", _
	@ScriptDir & "\input\04.png", _
	@ScriptDir & "\input\05.png" _
]


Global $aInMaxSizesBytes[] = [ _
	"100864", _
	"613888", _
	"101888", _
	"153088", _
	"204800" _
]

Global $aInMaxSizesBytes_HackLarger03[] = [ _
	"100864", _
	"613888", _
	"183808", _
	"71168", _
	"204800" _
]

Global Const $sLogPath = @ScriptDir & "\last_log.txt"
Global Const $sTempDir = @ScriptDir & "\temp\"
Global Const $sBinDir = @ScriptDir & "\bin\"
Global Const $sSplashOut = $sTempDir & "splash.img"
Global Const $iSectorSize = 512
Global Const $iSplashImgHeaderSize = 1024

; ------------------------------ Functions

Func LogEcho($sMessage)
	ConsoleWrite($sMessage & @CRLF)
	; It's a bit crap to keep opening/closing a file handle but we don't want to contest with e.g. python script STDOUT
	Local $hFile = FileOpen($sLogPath, $FO_APPEND)
	FileWrite($hFile, $sMessage & @CRLF)
	FileClose($hFile)
EndFunc

Func ExitWait()
	If @Compiled Then
		ConsoleWrite("[i] Press any key to close." & @CRLF)
		While 1
			If _IsAnyKeyPressed() Then
				ExitLoop
			EndIf
		WEnd
	EndIf
	Exit
EndFunc

; ------------------------------ Main

If $CmdLine[0] >= 1 Then
	If $CmdLine[1] = "-hack03" Then
		LogEcho("[!] Using 'larger 03 splash' hack. Make sure splash 04 is reduced to a tiny size (it likely won't work anymore anyway).")
		$aInMaxSizesBytes = $aInMaxSizesBytes_HackLarger03
	EndIf
EndIf

If FileExists(@ScriptDir & "\splash.img") Then
	ConsoleWrite("[!] A splash.img already exists in the current folder. Please delete or move it first." & @CRLF)
	ExitWait()
EndIf

FileDelete($sLogPath)

DirCreate(@ScriptDir & "\input")
; check all PNG's are there
For $sInFile In $aInFiles
	If Not FileExists($sInFile) Then
		LogEcho("[!] One or more input PNG's are missing. Please put 01.png to 05.png in the 'input' folder.")
		ExitWait()
	EndIf
Next

DirRemove($sTempDir, 1)
DirCreate($sTempDir)

; write out header
Global $hSplashOut = FileOpen($sSplashOut, $FO_APPEND + $FO_BINARY)
For $l = 1 To $iSplashImgHeaderSize
	FileWrite($hSplashOut, Chr(0x00))
Next
FileFlush($hSplashOut)

Local $iCount = 1
For $iIndex = 0 To UBound($aInFiles) - 1
	Local $sInFile = $aInFiles[$iIndex]
	Local $sInSize = $aInMaxSizesBytes[$iIndex]
	; Build current PNG file/path info
	Local $sDrive = "", $sDir = "", $sFileName = "", $sExtension = ""
	_PathSplit($sInFile, $sDrive, $sDir, $sFileName, $sExtension)
	; Copy current png file to temp
	FileCopy($sInFile, $sTempDir)
	FileMove($sTempDir & $sFileName & $sExtension, $sTempDir & "input.png")
	; Convert to RLE
	LogEcho("[#] Converting file " & $iCount & " of " & UBound($aInFiles) &"...")
	RunWait(@ComSpec & " /c " & $sBinDir & "Python2.7\python2.7.exe " & $sBinDir & "code.py >> " & $sLogPath & " 2>&1", $sTempDir, @SW_HIDE)
	If Not FileExists($sTempDir & "output.rle") Then
		LogEcho("[!] Error creating RLE file!")
		ExitWait()
	EndIf
	FileMove($sTempDir & "output.rle", $sTempDir & $sFileName & ".rle")
	FileDelete($sTempDir & "input.png")
	Local $sSplashFile = $sTempDir & $sFileName & ".rle"
	; Do padding to next sector boundary
	Local $iSplashSizeBytes = FileGetSize($sSplashFile)
	LogEcho("    [i] File size is " & $iSplashSizeBytes & " bytes")
	If $iSplashSizeBytes > $sInSize Then
		LogEcho("    [!] RLE image file is too big. Must be smaller than " & $sInSize & " bytes. Try reducing the image complexity.")
		ExitWait()
	EndIf

	Local $iSplashSizeSectors = 0
	; pad the file to the required size
	Local $hSplashRleFile = FileOpen($sSplashFile, $FO_APPEND + $FO_BINARY)
	LogEcho("    [#] Padding RLE file...")
	For $l = 1 To $sInSize - $iSplashSizeBytes
		If Mod($iSplashSizeBytes + $l, $iSectorSize) = 0 And $iSplashSizeSectors = 0 Then
			; remember the sector size of image for header
			Local $iSplashSizeSectors = ($iSplashSizeBytes + $l) / 512
			LogEcho("        [i] RLE length detected at " & $iSplashSizeBytes + $l & " bytes (" & $iSplashSizeSectors & " sectors).")
		EndIf
		FileWrite($hSplashRleFile, Chr(0x00))
	Next

	If $iSplashSizeSectors = 0 Then
		LogEcho("[!] Could not calculate RLE size for header. It's probably too large. Try reducing the image complexity.")
		ExitWait()
	EndIf

	FileFlush($hSplashRleFile)
	FileClose($hSplashRleFile)
	; calculate new size
	$iChunkSizeBytes = FileGetSize($sSplashFile)
	Local $iChunkSizeSectors = $iSplashSizeBytes / $iSectorSize
	LogEcho("        [i] Full chunk size is " & $iChunkSizeBytes & " bytes")

	; Do header
	LogEcho("    [#] Calculating and adding header...")
	Local $sSplashHeader = $sTempDir & $sFileName & ".header"
	FileCopy($sBinDir & "splash_rle_header.img", $sSplashHeader)
	Local $bSplashLength = _BinaryFromInt32($iSplashSizeSectors)
	Local $hSplashHeaderFile = FileOpen($sSplashHeader, $FO_APPEND + $FO_BINARY)
	FileWrite($hSplashHeaderFile, $bSplashLength)
	LogEcho("        [i] Wrote '" & $bSplashLength & "' to header. Now padding to 512 bytes...")

	; recalculate the size
	FileFlush($hSplashHeaderFile)
	Local $iSplashHeaderSizeBytes = FileGetSize($sSplashHeader)
	For $l = 1 To $iSectorSize - $iSplashHeaderSizeBytes
		FileWrite($hSplashRleFile, Chr(0x00))
	Next
	FileFlush($hSplashHeaderFile)
	FileClose($hSplashHeaderFile)
	LogEcho("            ...done")


	LogEcho("    [#] Writing-out chunk...")
	Local $hFileInput = FileOpen($sSplashHeader, $FO_READ + $FO_BINARY)
	FileWrite($hSplashOut, FileRead($hFileInput))
	FileFlush($hSplashOut)
	FileClose($hFileInput)
	$hFileInput = FileOpen($sSplashFile, $FO_READ + $FO_BINARY)
	FileWrite($hSplashOut, FileRead($hFileInput))
	FileFlush($hSplashOut)
	FileClose($hFileInput)

	FileDelete($sSplashFile)
	FileDelete($sSplashHeader)

	LogEcho("        ... done")

	$iCount = $iCount + 1
Next

FileClose($hSplashOut)

LogEcho("")
If Not FileExists($sSplashOut) Then
	LogEcho("[!] splash.img build failed. Check log for details.")
Else
	FileMove($sSplashOut, @ScriptDir)
	LogEcho("[i] splash.img done!")
EndIf
LogEcho("")

; cleanup
DirRemove($sTempDir, 1)

ExitWait()

