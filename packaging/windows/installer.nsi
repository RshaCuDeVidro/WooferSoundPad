; WooferSoundPad installer for Windows (NSIS 3).
;
; Per user, no admin prompt: installs into %LOCALAPPDATA%\Programs\WooferSoundPad
; (so the app can still update itself), adds a Start menu shortcut, an optional
; desktop shortcut and an entry in Settings > Apps for uninstalling. Sounds and
; settings live in %APPDATA% and are kept when uninstalling.
;
; Built by the release workflow (makensis works from this folder, so pass absolute paths):
;   makensis -INPUTCHARSET UTF8 -DVERSION=1.2.0 -DVI_VERSION=1.2.0.0 -DEXE=$PWD/out/windows/bin/WooferSoundPad.exe -DOUTFILE=$PWD/dist/setup.exe packaging/windows/installer.nsi

Unicode true
SetCompressor /SOLID lzma
RequestExecutionLevel user
ManifestDPIAware true

!ifndef VERSION
  !define VERSION "0.0.0"
!endif
!ifndef VI_VERSION
  !define VI_VERSION "0.0.0.0"
!endif
!ifndef EXE
  !define EXE "..\..\zig-out\bin\WooferSoundPad.exe"
!endif
!ifndef OUTFILE
  !define OUTFILE "WooferSoundPad-${VERSION}-windows-x86_64-setup.exe"
!endif

!define APP "WooferSoundPad"
!define PUBLISHER "RshaCuDeVidro"
!define URL "https://github.com/RshaCuDeVidro/WooferSoundPad"
!define UNINST_KEY "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APP}"

Name "${APP}"
OutFile "${OUTFILE}"
InstallDir "$LOCALAPPDATA\Programs\${APP}"
InstallDirRegKey HKCU "Software\${APP}" "InstallDir"
BrandingText "${APP} ${VERSION}"

VIProductVersion "${VI_VERSION}"
VIAddVersionKey "ProductName" "${APP}"
VIAddVersionKey "ProductVersion" "${VERSION}"
VIAddVersionKey "FileVersion" "${VERSION}"
VIAddVersionKey "FileDescription" "${APP} installer"
VIAddVersionKey "CompanyName" "${PUBLISHER}"
VIAddVersionKey "LegalCopyright" "MIT License"

!include "MUI2.nsh"
!include "FileFunc.nsh"

!define MUI_ICON "..\..\assets\icon.ico"
!define MUI_UNICON "..\..\assets\icon.ico"
!define MUI_ABORTWARNING
!define MUI_COMPONENTSPAGE_NODESC
!define MUI_FINISHPAGE_RUN "$INSTDIR\${APP}.exe"

!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_COMPONENTS
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES

; English or Portuguese, whichever matches Windows
!insertmacro MUI_LANGUAGE "English"
!insertmacro MUI_LANGUAGE "PortugueseBR"

LangString SecAppName ${LANG_ENGLISH} "WooferSoundPad (Start menu)"
LangString SecAppName ${LANG_PORTUGUESEBR} "WooferSoundPad (menu Iniciar)"
LangString SecDesktopName ${LANG_ENGLISH} "Desktop shortcut"
LangString SecDesktopName ${LANG_PORTUGUESEBR} "Atalho na área de trabalho"
LangString StillRunning ${LANG_ENGLISH} "WooferSoundPad is running. Close it, then click Retry."
LangString StillRunning ${LANG_PORTUGUESEBR} "O WooferSoundPad está aberto. Feche-o e clique em Repetir."

; A running copy keeps its .exe locked
!macro WaitUntilClosed
  retry:
  ClearErrors
  IfFileExists "$INSTDIR\${APP}.exe" 0 done
  FileOpen $0 "$INSTDIR\${APP}.exe" a
  IfErrors 0 closed
  MessageBox MB_RETRYCANCEL|MB_ICONEXCLAMATION "$(StillRunning)" /SD IDCANCEL IDRETRY retry
  Abort
  closed:
  FileClose $0
  done:
!macroend

Section "!$(SecAppName)" SecApp
  SectionIn RO
  !insertmacro WaitUntilClosed
  SetOutPath "$INSTDIR"
  File "/oname=${APP}.exe" "${EXE}"
  File "..\..\LICENSE"
  File "..\..\THIRD_PARTY_NOTICES.md"
  ; Left behind by the app's own updater
  Delete "$INSTDIR\${APP}.exe.old"
  WriteUninstaller "$INSTDIR\Uninstall.exe"

  CreateShortCut "$SMPROGRAMS\${APP}.lnk" "$INSTDIR\${APP}.exe" "" "$INSTDIR\${APP}.exe" 0

  WriteRegStr HKCU "Software\${APP}" "InstallDir" "$INSTDIR"
  WriteRegStr HKCU "${UNINST_KEY}" "DisplayName" "${APP}"
  WriteRegStr HKCU "${UNINST_KEY}" "DisplayVersion" "${VERSION}"
  WriteRegStr HKCU "${UNINST_KEY}" "Publisher" "${PUBLISHER}"
  WriteRegStr HKCU "${UNINST_KEY}" "URLInfoAbout" "${URL}"
  WriteRegStr HKCU "${UNINST_KEY}" "DisplayIcon" "$INSTDIR\${APP}.exe"
  WriteRegStr HKCU "${UNINST_KEY}" "InstallLocation" "$INSTDIR"
  WriteRegStr HKCU "${UNINST_KEY}" "UninstallString" '"$INSTDIR\Uninstall.exe"'
  WriteRegStr HKCU "${UNINST_KEY}" "QuietUninstallString" '"$INSTDIR\Uninstall.exe" /S'
  WriteRegDWORD HKCU "${UNINST_KEY}" "NoModify" 1
  WriteRegDWORD HKCU "${UNINST_KEY}" "NoRepair" 1
  ${GetSize} "$INSTDIR" "/S=0K" $0 $1 $2
  IntFmt $0 "0x%08X" $0
  WriteRegDWORD HKCU "${UNINST_KEY}" "EstimatedSize" "$0"
SectionEnd

Section "$(SecDesktopName)" SecDesktop
  CreateShortCut "$DESKTOP\${APP}.lnk" "$INSTDIR\${APP}.exe" "" "$INSTDIR\${APP}.exe" 0
SectionEnd

Section "Uninstall"
  !insertmacro WaitUntilClosed
  Delete "$INSTDIR\${APP}.exe"
  Delete "$INSTDIR\${APP}.exe.old"
  Delete "$INSTDIR\LICENSE"
  Delete "$INSTDIR\THIRD_PARTY_NOTICES.md"
  Delete "$INSTDIR\Uninstall.exe"
  RMDir "$INSTDIR"
  Delete "$SMPROGRAMS\${APP}.lnk"
  Delete "$DESKTOP\${APP}.lnk"
  DeleteRegKey HKCU "${UNINST_KEY}"
  DeleteRegKey HKCU "Software\${APP}"
  ; Sounds, settings and downloaded tools in %APPDATA% stay
SectionEnd
