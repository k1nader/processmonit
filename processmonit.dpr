program processmonit;

{$APPTYPE CONSOLE}
{$R *.res}
// {$DEFINE HOOKMSGBOX}

uses
  System.SysUtils,
  Winapi.Windows,
  Winapi.TlHelp32;

type
  PEnumInfo = ^TEnumInfo;

  TEnumInfo = record
    ProcessID: DWORD;
    TimeOut: Boolean;
  end;

function IsWindowAborted(Wnd: DWORD): Boolean;
var
  ErrorCode: DWORD;
{$IFDEF CPUX86}
  P: DWORD;
{$ELSE}
  P: PDWORD_PTR;
{$ENDIF}
begin
{$IFDEF CPUX64}
  P := nil;
{$ENDIF}
  ErrorCode := SendMessageTimeout(Wnd, 0, 0, 0, SMTO_ERRORONEXIT, 3000, P);
  Result := ErrorCode = 0;
end;

function EnumWindowsProc(Wnd: DWORD; var EI: TEnumInfo): Bool; stdcall;
var
  PID: DWORD;
begin

  Result := True;

  GetWindowThreadProcessID(Wnd, @PID);

  if PID = EI.ProcessID then
  begin
    EI.TimeOut := IsWindowAborted(Wnd);

    if EI.TimeOut then
    begin
      Result := False;
    end;

  end;

end;

function IsProcessWindowAborted(PID: DWORD): Boolean;
var
  EI: TEnumInfo;
begin

  EI.ProcessID := PID;
  EI.TimeOut := False;

  EnumWindows(@EnumWindowsProc, LPARAM(@EI));

  Result := EI.TimeOut;
end;

var
  FProcessInformation: TProcessInformation;
  FStartupInfo: TStartupInfo;
  FTimeOutCountOld: Integer;
  FTimeOutCount: Integer;
  FProcessFile: string;
  FCmdParams: string;

{$IFDEF HOOKMSGBOX}

function InjectDllToProcess(ProcessInfo: TProcessInformation;
  lpDllName: string): THandle;
var
  vAParam: Pointer;
  hThreadId: DWORD;
  pfnStartAddr: TFNThreadStartRoutine;
  nSize, lpNumberOfBytes: SIZE_T;
begin
  vAParam := VirtualAllocEx(ProcessInfo.hProcess, nil, MAX_PATH, MEM_COMMIT,
    PAGE_EXECUTE_READWRITE);

  nSize := Length(lpDllName) * SizeOf(WideChar);

  WriteProcessMemory(ProcessInfo.hProcess, vAParam, PWideChar(lpDllName), nSize,
    lpNumberOfBytes);

  pfnStartAddr := GetProcAddress(LoadLibrary('Kernel32.dll'), 'LoadLibraryW');

  Result := CreateRemoteThread(ProcessInfo.hProcess, nil, 0, pfnStartAddr,
    vAParam, CREATE_SUSPENDED, hThreadId);

end;

{$ENDIF}

procedure RunProcess(const AFile: string; const Params: string);

{$IFDEF HOOKMSGBOX}
var
  hThread: THandle;
{$ENDIF}
begin

  Writeln(FormatdateTime('c', Now), ' - start process ',
    ExtractFileName(AFile));

  FillChar(FProcessInformation, SizeOf(FProcessInformation), 0);
  FillChar(FStartupInfo, SizeOf(FStartupInfo), 0);
  FStartupInfo.cb := SizeOf(FStartupInfo);

  if not CreateProcess(PWideChar(AFile), PWideChar(Params), nil, nil, False,
    CREATE_SUSPENDED, nil, PWideChar(ExtractFilePath(AFile)), FStartupInfo,
    FProcessInformation) then
  begin
    Exit;
  end;

{$IFDEF HOOKMSGBOX}
  hThread := InjectDllToProcess(FProcessInformation, ExtractFilePath(ParamStr(0)
    ) + 'msgbox_hook_x86.dll');
{$ENDIF}
  ResumeThread(FProcessInformation.hThread);
{$IFDEF HOOKMSGBOX}
  ResumeThread(hThread);
{$ENDIF}
end;

function GetParamsValue(const Key: string): string;
begin
  if not FindCmdLineSwitch(Key, Result, True) then
  begin
    Result := '';
  end;
end;

function IsProcessIdRunning(const APID: DWORD): Boolean;
var
  h: THandle;
  P: TProcessEntry32;
begin

  P.dwSize := SizeOf(P);
  h := CreateToolHelp32Snapshot(TH32CS_SnapProcess, 0);
  try
    Process32First(h, P);
    repeat
      Result := APID = P.th32ProcessID;
    until Result or (not Process32Next(h, P));
  finally
    CloseHandle(h);
  end;
end;

procedure LoopCheck(const ASleepTime: Integer = 0);
var
  bNeedCreateProcess: Boolean;
begin

  bNeedCreateProcess := False;

  if not IsProcessIdRunning(FProcessInformation.dwProcessId) then
  begin
    bNeedCreateProcess := True;
  end;

  if not bNeedCreateProcess then
  begin
    if IsProcessWindowAborted(FProcessInformation.dwProcessId) then
    begin
      Dec(FTimeOutCount, 1);
      bNeedCreateProcess := FTimeOutCount <= 0;

      if bNeedCreateProcess then
      begin
        TerminateProcess(OpenProcess(PROCESS_TERMINATE, Bool(0),
          FProcessInformation.dwProcessId), 0)
      end;

    end;
  end;

  if ASleepTime > 0 then
  begin
    Sleep(ASleepTime);
  end;

  if bNeedCreateProcess then
  begin

    FTimeOutCount := FTimeOutCountOld;

    RunProcess(FProcessFile, FCmdParams);

    if FProcessInformation.dwProcessId = 0 then
    begin
      Writeln('createprocess ', FProcessFile, ' ', FCmdParams, ' error.');
      Exit;
    end;

  end;

  LoopCheck(1000);

end;

procedure RunProcessMonit;
begin

  RunProcess(FProcessFile, FCmdParams);

  if FProcessInformation.dwProcessId = 0 then
  begin
    Writeln('createprocess ', FProcessFile, ' ', FCmdParams, ' error.');
    Exit;
  end;

  LoopCheck;
end;

begin
  try

    FTimeOutCount := StrToIntDef(GetParamsValue('timeout'), 1);
    FProcessFile := GetParamsValue('file');
    FCmdParams := GetParamsValue('param');

    if FTimeOutCount <= 0 then
    begin
      FTimeOutCount := 1;
    end;

    FTimeOutCountOld := FTimeOutCount;

    if FProcessFile.IsEmpty then
    begin

      Writeln('params: ');
      Writeln(' -file: process file name.');
      Writeln(' -param: process param.');
      Writeln(' -timeout: restart process timeout.');

      Writeln;

      Writeln('param "-file" is empty.');
      Exit;
    end;

    if not FileExists(FProcessFile) then
    begin
      Writeln(FProcessFile, ' file is not exists.');
      Exit;
    end;

    if ExtractFilePath(FProcessFile).IsEmpty then
    begin
      FProcessFile := ExtractFilePath(ParamStr(0)) + FProcessFile;
    end;

    RunProcessMonit;

    { TODO -oUser -cConsole Main : Insert code here }
  except
    on E: Exception do
      Writeln(E.ClassName, ': ', E.Message);
  end;

end.
