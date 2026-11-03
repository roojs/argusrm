!include "MUI2.nsh"

!define PRODUCT_NAME "Argus Agent"
!define PRODUCT_PUBLISHER "roojs"
!define SERVICE_NAME "ArgusAgent"
!define UNINST_KEY "Software\Microsoft\Windows\CurrentVersion\Uninstall\ArgusAgent"

!ifndef OUTFILE
  !define OUTFILE "dist-windows\ArgusAgent-Setup.exe"
!endif
!ifndef INST_SRC
  !define INST_SRC "dist-windows\Argus"
!endif
!ifndef PRODUCT_VERSION
  !define PRODUCT_VERSION "0.0.0"
!endif

Name "${PRODUCT_NAME}"
OutFile "${OUTFILE}"
InstallDir "$PROGRAMFILES64\Argus"
RequestExecutionLevel admin
Unicode true

!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_LANGUAGE "English"

Section "Argus Agent" SecMain
  SectionIn RO

  nsExec::ExecToLog '"$SYSDIR\sc.exe" stop ${SERVICE_NAME}'
  nsExec::ExecToLog '"$SYSDIR\sc.exe" delete ${SERVICE_NAME}'
  ExecWait 'taskkill /F /IM argus-tray.exe'

  SetOutPath "$INSTDIR"
  File /r "${INST_SRC}\*.*"

  nsExec::ExecToLog '"$SYSDIR\sc.exe" create ${SERVICE_NAME} binPath= "$\"$INSTDIR\argus-agent.exe$\"" start= auto DisplayName= "$\"Argus Remote Management Agent$\""'
  nsExec::ExecToLog '"$SYSDIR\sc.exe" description ${SERVICE_NAME} "$\"Argus managed-machine agent$\""'
  nsExec::ExecToLog '"$SYSDIR\sc.exe" start ${SERVICE_NAME}'

  CreateDirectory "$SMPROGRAMS\Argus"
  CreateShortCut "$SMPROGRAMS\Argus\Register this machine.lnk" \
    "$INSTDIR\argus-tray.exe"

  WriteUninstaller "$INSTDIR\Uninstall.exe"
  WriteRegStr HKLM "${UNINST_KEY}" "DisplayName" "${PRODUCT_NAME}"
  WriteRegStr HKLM "${UNINST_KEY}" "DisplayVersion" "${PRODUCT_VERSION}"
  WriteRegStr HKLM "${UNINST_KEY}" "Publisher" "${PRODUCT_PUBLISHER}"
  WriteRegStr HKLM "${UNINST_KEY}" "InstallLocation" "$INSTDIR"
  WriteRegStr HKLM "${UNINST_KEY}" "UninstallString" "$\"$INSTDIR\Uninstall.exe$\""
  WriteRegDWORD HKLM "${UNINST_KEY}" "NoModify" 1
  WriteRegDWORD HKLM "${UNINST_KEY}" "NoRepair" 1
SectionEnd

Section "Uninstall"
  nsExec::ExecToLog '"$SYSDIR\sc.exe" stop ${SERVICE_NAME}'
  nsExec::ExecToLog '"$SYSDIR\sc.exe" delete ${SERVICE_NAME}'
  ExecWait 'taskkill /F /IM argus-tray.exe'

  Delete "$SMPROGRAMS\Argus\Register this machine.lnk"
  RMDir "$SMPROGRAMS\Argus"
  DeleteRegKey HKLM "${UNINST_KEY}"
  RMDir /r "$INSTDIR"
SectionEnd
