library msgbox_hook_x86;

{ Important note about DLL memory management: ShareMem must be the
  first unit in your library's USES clause AND your project's (select
  Project-View Source) USES clause if your DLL exports any procedures or
  functions that pass strings as parameters or function results. This
  applies to all strings passed to and from your DLL--even those that
  are nested in records and classes. ShareMem is the interface unit to
  the BORLNDMM.DLL shared memory manager, which must be deployed along
  with your DLL. To avoid using BORLNDMM.DLL, pass string information
  using PChar or ShortString parameters. }

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.SyncObjs,
  Winapi.Windows,
  HookIntfs in 'HookIntfs.pas',
  HookUtils in 'HookUtils.pas';

{$R *.res}

var
  LogFileName: string;
  LogLocker: TCriticalSection;

var
  pMessageBoxA: function(hWnd: hWnd; lpText, lpCaption: LPCSTR; uType: UINT)
    : Integer; stdcall;
  pMessageBoxW: function(hWnd: hWnd; lpText, lpCaption: LPCWSTR; uType: UINT)
    : Integer; stdcall;

procedure DebugLog(const Tag: string; const Fmt: string;
  const Args: array of const);
var
  DebugText: string;
  StreamWriter: TStreamWriter;
begin

  LogLocker.Enter;
  try
    DebugText := FormatDateTime('c', Now) + ' - [' + Tag + '] ' +
      Format(Fmt, Args);

    StreamWriter := TFile.AppendText(LogFileName);
    try
      StreamWriter.Write(DebugText + #13#10);
    finally
      StreamWriter.Close;
    end;

  finally
    LogLocker.Leave;
  end;

end;

function pHookMessageBoxA(hWnd: hWnd; lpText, lpCaption: LPCSTR; uType: UINT)
  : Integer; stdcall;
begin
  if (uType = MB_ICONHAND) then
  begin
    DebugLog('MessageBoxA', 'hWnd: %d, lpText: "%s", lpCaption: "%s", uType:%d',
      [hWnd, lpText, lpCaption, uType]);

    Result := ID_OK;
  end
  else
  begin
    Result := pMessageBoxA(hWnd, lpText, lpCaption, uType);
  end;
end;

function pHookMessageBoxW(hWnd: hWnd; lpText, lpCaption: LPCWSTR; uType: UINT)
  : Integer; stdcall;
begin

  if (uType = MB_ICONHAND) then
  begin
    DebugLog('MessageBoxW', 'hWnd: %d, lpText: "%s", lpCaption: "%s", uType:%d',
      [hWnd, lpText, lpCaption, uType]);

    Result := ID_OK;
  end
  else
  begin
    Result := pMessageBoxW(hWnd, lpText, lpCaption, uType);
  end;
end;

procedure HookMessageBox;
begin
  HookProc(user32, 'MessageBoxA', @pHookMessageBoxA, @pMessageBoxA);
  HookProc(user32, 'MessageBoxW', @pHookMessageBoxW, @pMessageBoxW);
end;

begin
  LogFileName := ParamStr(0) + FormatDateTime('_yy-mm-dd_hhnnss', Now) + '.log';
  TFile.CreateText(LogFileName).Close;
  LogLocker := TCriticalSection.Create;

  HookMessageBox;

end.
