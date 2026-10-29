; Per-user Windows installer for the Liquidgram desktop app. `dev/buildDesktop.mjs` passes the defines:
; VERSION (display version), VERSION_WIN (four numbers), APP_EXE_PATH (built launcher) and OUT_FILE.

!macro REQUIRE_DEFINE NAME
  !ifndef ${NAME}
    !error "${NAME} is not defined: build the installer with dev/buildDesktop.mjs"
  !endif
!macroend
!insertmacro REQUIRE_DEFINE VERSION
!insertmacro REQUIRE_DEFINE VERSION_WIN
!insertmacro REQUIRE_DEFINE APP_EXE_PATH
!insertmacro REQUIRE_DEFINE OUT_FILE

Unicode true
ManifestDPIAware true
SetCompressor /SOLID lzma
RequestExecutionLevel user

!define APP_NAME "Liquidgram"
!define APP_EXE "Liquidgram.exe"
!define UNINSTALLER_EXE "Uninstall Liquidgram.exe"
!define UNINSTALL_KEY "Software\Microsoft\Windows\CurrentVersion\Uninstall\Liquidgram"
!define ICON_PATH "${__FILEDIR__}\..\assets\liquidgram.ico"

Name "${APP_NAME}"
OutFile "${OUT_FILE}"
InstallDir "$LOCALAPPDATA\Programs\Liquidgram"
InstallDirRegKey HKCU "${UNINSTALL_KEY}" "InstallLocation"
BrandingText "${APP_NAME} ${VERSION}"

!include "MUI2.nsh"
!include "FileFunc.nsh"
!include "x64.nsh"

!define MUI_ICON "${ICON_PATH}"
!define MUI_UNICON "${ICON_PATH}"
!define MUI_WELCOMEFINISHPAGE_BITMAP "${__FILEDIR__}\welcome.bmp"
!define MUI_UNWELCOMEFINISHPAGE_BITMAP "${__FILEDIR__}\welcome.bmp"
!define MUI_ABORTWARNING

!define MUI_WELCOMEPAGE_TEXT "$(WelcomeText)"
!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_INSTFILES
!define MUI_FINISHPAGE_RUN "$INSTDIR\${APP_EXE}"
!insertmacro MUI_PAGE_FINISH

!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES

; The first language is the fallback when Windows uses neither of them
!insertmacro MUI_LANGUAGE "Russian"
!insertmacro MUI_LANGUAGE "English"

LangString WelcomeText ${LANG_RUSSIAN} "Программа установит Liquidgram, неофициальный клиент Telegram с дизайном Liquid Glass.$\r$\n$\r$\nОкно приложения открывается через Microsoft Edge или Google Chrome. Ваш обычный браузер, его вкладки и настройки при этом не меняются.$\r$\n$\r$\nНажмите «Установить», чтобы продолжить."
LangString WelcomeText ${LANG_ENGLISH} "Setup will install Liquidgram, an unofficial Telegram client with the Liquid Glass design.$\r$\n$\r$\nThe app window opens through Microsoft Edge or Google Chrome. Your regular browser, its tabs and settings stay as they are.$\r$\n$\r$\nClick Install to continue."
LangString Need64Bit ${LANG_RUSSIAN} "Liquidgram работает только на 64-битной Windows 10 или 11."
LangString Need64Bit ${LANG_ENGLISH} "Liquidgram requires 64-bit Windows 10 or 11."
LangString CloseApp ${LANG_RUSSIAN} "Закройте все окна Liquidgram и нажмите «Повтор»."
LangString CloseApp ${LANG_ENGLISH} "Close all Liquidgram windows and click Retry."

VIProductVersion "${VERSION_WIN}"
VIFileVersion "${VERSION_WIN}"
VIAddVersionKey /LANG=${LANG_ENGLISH} "ProductName" "${APP_NAME}"
VIAddVersionKey /LANG=${LANG_ENGLISH} "FileDescription" "${APP_NAME} Setup"
VIAddVersionKey /LANG=${LANG_ENGLISH} "CompanyName" "${APP_NAME}"
VIAddVersionKey /LANG=${LANG_ENGLISH} "LegalCopyright" "GPL-3.0-or-later"
VIAddVersionKey /LANG=${LANG_ENGLISH} "FileVersion" "${VERSION}"
VIAddVersionKey /LANG=${LANG_ENGLISH} "ProductVersion" "${VERSION}"

Function .onInit
  ${IfNot} ${RunningX64}
    MessageBox MB_OK|MB_ICONSTOP "$(Need64Bit)" /SD IDOK
    Abort
  ${EndIf}
FunctionEnd

Section "Install"
  SetShellVarContext current
  SetOutPath "$INSTDIR"

  ; Windows keeps a running executable locked but lets it be renamed, so an update works while an
  ; older copy is open. The renamed copy is removed by a later update or the uninstaller once it
  ; exits. Only when copies from two earlier versions still run does the user have to close them.
  retryReplace:
    Delete "$INSTDIR\${APP_EXE}.old"
    Delete "$INSTDIR\${APP_EXE}"
    IfFileExists "$INSTDIR\${APP_EXE}" 0 replaced
    ClearErrors
    Rename "$INSTDIR\${APP_EXE}" "$INSTDIR\${APP_EXE}.old"
    IfErrors 0 replaced
      MessageBox MB_RETRYCANCEL|MB_ICONEXCLAMATION "$(CloseApp)" /SD IDCANCEL IDRETRY retryReplace
      Abort
  replaced:
  File "/oname=${APP_EXE}" "${APP_EXE_PATH}"

  WriteUninstaller "$INSTDIR\${UNINSTALLER_EXE}"

  CreateShortcut "$SMPROGRAMS\${APP_NAME}.lnk" "$INSTDIR\${APP_EXE}" "" "$INSTDIR\${APP_EXE}" 0
  CreateShortcut "$DESKTOP\${APP_NAME}.lnk" "$INSTDIR\${APP_EXE}" "" "$INSTDIR\${APP_EXE}" 0

  WriteRegStr HKCU "${UNINSTALL_KEY}" "DisplayName" "${APP_NAME}"
  WriteRegStr HKCU "${UNINSTALL_KEY}" "DisplayIcon" "$INSTDIR\${APP_EXE},0"
  WriteRegStr HKCU "${UNINSTALL_KEY}" "DisplayVersion" "${VERSION}"
  WriteRegStr HKCU "${UNINSTALL_KEY}" "Publisher" "${APP_NAME}"
  WriteRegStr HKCU "${UNINSTALL_KEY}" "UninstallString" '"$INSTDIR\${UNINSTALLER_EXE}"'
  WriteRegStr HKCU "${UNINSTALL_KEY}" "QuietUninstallString" '"$INSTDIR\${UNINSTALLER_EXE}" /S'
  WriteRegStr HKCU "${UNINSTALL_KEY}" "InstallLocation" "$INSTDIR"
  WriteRegDWORD HKCU "${UNINSTALL_KEY}" "NoModify" 1
  WriteRegDWORD HKCU "${UNINSTALL_KEY}" "NoRepair" 1
  ${GetSize} "$INSTDIR" "/S=0K" $0 $1 $2
  WriteRegDWORD HKCU "${UNINSTALL_KEY}" "EstimatedSize" $0
SectionEnd

; Removes the program and its shortcuts. Chats, keys and settings stay in %LOCALAPPDATA%\Liquidgram,
; so a reinstall picks them up again.
Section "Uninstall"
  SetShellVarContext current

  retryDelete:
    ClearErrors
    Delete "$INSTDIR\${APP_EXE}"
    IfErrors 0 +3
      MessageBox MB_RETRYCANCEL|MB_ICONEXCLAMATION "$(CloseApp)" /SD IDCANCEL IDRETRY retryDelete
      Abort

  Delete "$INSTDIR\${APP_EXE}.old"
  Delete "$INSTDIR\${UNINSTALLER_EXE}"
  RMDir "$INSTDIR"

  Delete "$SMPROGRAMS\${APP_NAME}.lnk"
  Delete "$DESKTOP\${APP_NAME}.lnk"
  DeleteRegKey HKCU "${UNINSTALL_KEY}"
SectionEnd
