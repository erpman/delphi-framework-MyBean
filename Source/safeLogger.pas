(*
 *	 Unit owner: D10.Mofen
 *	       blog: http://www.cnblogs.com/dksoft
 *
 *	 v0.0.1(2014-08-31 12:40:18)
 *     + first release
 *)

unit safeLogger;

interface

uses
  Classes, BaseQueue, SysUtils, SyncObjs{$IFDEF MSWINDOWS}, Windows, Messages {$ENDIF};

type

  TLogLevel=(lgvError, lgvWarning, lgvHint, lgvMessage, lgvDebug);

const
  TLogLevelCaption: array [TLogLevel] of string = ('error', 'warning', 'hint', 'message', 'debug');

type
  TSafeLogger = class;
  TSyncMainThreadType = (rtSync{$IFDEF MSWINDOWS}, rtPostMessage {$ENDIF});

  PLogDataObject = ^TLogDataObject;

  TLogDataObject = record
    FThreadID:Cardinal;
    FTime:TDateTime;
    FLogLevel:TLogLevel;
    FMsg:string;
    FMsgType:string;
  end;

  TBaseAppender = class(TObject)
  protected
    FOwner:TSafeLogger;
  protected
    procedure AppendLog(pvData:PLogDataObject); virtual; abstract;
  end;

  TStringsAppender = class(TBaseAppender)
  private
    FStrings: TStrings;
  protected
    procedure AppendLog(pvData:PLogDataObject); override;
  public
    constructor Create(AStrings: TStrings);
  end;

  TLogFileAppender = class(TBaseAppender)
  private
    FAddThreadINfo: Boolean;
    FBasePath: string;
    FLogFile: TextFile;
    function openLogFile(pvPre: String = ''): Boolean;
  protected
    procedure AppendLog(pvData:PLogDataObject); override;
  public
    constructor Create(pvAddThreadINfo: Boolean);
    property AddThreadINfo: Boolean read FAddThreadINfo write FAddThreadINfo;
  end;


  TLogWorker = class(TThread)
  private
    {$IFDEF MSWINDOWS}
    FMessageEvent: TEvent;
    {$ENDIF}
    FSafeLogger: TSafeLogger;
    FNotify: TEvent;
    // temp for sync method
    FTempLogData: PLogDataObject;
    procedure ExecuteLogData(const pvData:PLogDataObject);
    procedure InnerSyncLogData;
  public
    constructor Create(ASafeLogger: TSafeLogger);
    destructor Destroy; override;
    procedure Execute; override;
  end;


  TSafeLogger = class(TObject)
  private
    FLogWorker:TLogWorker;
    FDataQueue: TBaseQueue;
    FOwnsAppender:Boolean;

    FAppender: TBaseAppender;
    FAppendInMainThread: Boolean;

    FSyncMainThreadType: TSyncMainThreadType;

    procedure ExecuteLogData(const pvData:PLogDataObject);
  private
    FEnable: Boolean;
    FWorkerCounter:Integer;
    FErrorCounter: Integer;
    FPostCounter: Integer;
    FResponseCounter: Integer;
    procedure incErrorCounter;


    procedure incResponseCounter;
    /// <summary>
    ///   check worker thread is alive
    /// </summary>
    function workersIsAlive: Boolean;

    procedure stopWorker;
  private
    {$IFDEF MSWINDOWS}
    FMessageHandle: HWND;
    procedure DoMainThreadWork(var AMsg: TMessage);
    procedure incWorkerCount;
    procedure decWorkerCounter;
    {$ENDIF}
  public
    constructor Create;
    destructor Destroy; override;
    /// <summary>
    ///   task current info
    /// </summary>
    function getStateINfo: String;

    procedure start;

    procedure setAppender(pvAppender: TBaseAppender; pvOwnsAppender: Boolean =
        true);

    procedure logMessage(pvMsg: string; pvMsgType: string = ''; pvLevel: TLogLevel
        = lgvMessage); overload;
    procedure logMessage(pvMsg: string; const args: array of const; pvMsgType:
        string = ''; pvLevel: TLogLevel = lgvMessage); overload;

    property SyncMainThreadType: TSyncMainThreadType read FSyncMainThreadType write
        FSyncMainThreadType;
    property AppendInMainThread: Boolean read FAppendInMainThread write
        FAppendInMainThread;



    property Enable: Boolean read FEnable write FEnable;


  end;

var
  sfLogger:TSafeLogger;

implementation


var
  __dataObjectPool:TBaseQueue;

{$IFDEF MSWINDOWS}
const
  WM_SYNC_METHOD = WM_USER + 1;

{$ENDIF}

constructor TSafeLogger.Create;
begin
  inherited Create;
  FEnable := true;
  FSyncMainThreadType := rtSync;
{$IFDEF MSWINDOWS}
  FSyncMainThreadType := rtPostMessage;
  FMessageHandle := AllocateHWnd(DoMainThreadWork);
{$ENDIF}
  FDataQueue := TBaseQueue.Create();
  FAppender := nil;
  FOwnsAppender := false;
  FWorkerCounter := 0;



end;

destructor TSafeLogger.Destroy;
begin
  FEnable := false;
  stopWorker;

  FDataQueue.DisposeAllData;
  FreeAndNil(FDataQueue);
  if FOwnsAppender then
  begin
    if FAppender <> nil then
    begin
      FAppender.Free;
      FAppender := nil;
    end;
  end;
{$IFDEF MSWINDOWS}
  DeallocateHWnd(FMessageHandle);
{$ENDIF}
  inherited Destroy;
end;

{$IFDEF MSWINDOWS}
procedure TSafeLogger.DoMainThreadWork(var AMsg: TMessage);
begin
  if AMsg.Msg = WM_SYNC_METHOD then
  begin
    try
      if not FEnable then Exit;
      ExecuteLogData(PLogDataObject(AMsg.WParam));
    finally
      if AMsg.LPARAM <> 0 then
        TEvent(AMsg.LPARAM).SetEvent;
    end;
  end else
    AMsg.Result := DefWindowProc(FMessageHandle, AMsg.Msg, AMsg.WPARAM, AMsg.LPARAM);
end;
{$ENDIF}

procedure TSafeLogger.ExecuteLogData(const pvData:PLogDataObject);
begin
  incResponseCounter;
  if FAppender = nil then
  begin
    incErrorCounter;
  end else
  begin
    FAppender.AppendLog(pvData);
  end;

end;

procedure TSafeLogger.incErrorCounter;
begin
  InterlockedIncrement(FErrorCounter);
end;

procedure TSafeLogger.incWorkerCount;
begin
  InterlockedIncrement(FWorkerCounter);
end;

procedure TSafeLogger.decWorkerCounter;
begin
  InterlockedDecrement(FErrorCounter);
end;

function TSafeLogger.getStateINfo: String;
var
  lvDebugINfo:TStrings;
begin
  lvDebugINfo := TStringList.Create;
  try
    lvDebugINfo.Add(Format('enable:%s', [boolToStr(FEnable, True)]));
    lvDebugINfo.Add(Format('post/response/error counter:%d / %d / %d',
       [self.FPostCounter,self.FResponseCounter,self.FErrorCounter]));
    Result := lvDebugINfo.Text;
  finally
    lvDebugINfo.Free;
  end;
end;

procedure TSafeLogger.incResponseCounter;
begin
  InterlockedIncrement(FResponseCounter);
end;

{ TSafeLogger }

procedure TSafeLogger.logMessage(pvMsg: string; pvMsgType: string = '';
    pvLevel: TLogLevel = lgvMessage);
var
  lvPData:PLogDataObject;
begin
  if not FEnable then exit;
  if FLogWorker = nil then exit;
  
  lvPData := __dataObjectPool.Pop;
  if lvPData = nil then New(lvPData);
{$IFDEF MSWINDOWS}
  lvPData.FThreadID := GetCurrentThreadId;
{$ELSE}
  lvPData.FThreadID := TThread.CurrentThread.ThreadID;
{$ENDIF};
  lvPData.FTime := Now();
  lvPData.FLogLevel := pvLevel;
  lvPData.FMsg := pvMsg;
  lvPData.FMsgType := pvMsgType;
  FDataQueue.Push(lvPData);
  InterlockedIncrement(FPostCounter);
  FLogWorker.FNotify.SetEvent;
end;

procedure TSafeLogger.logMessage(pvMsg: string; const args: array of const;
    pvMsgType: string = ''; pvLevel: TLogLevel = lgvMessage);
begin
  logMessage(Format(pvMsg, args), pvMsgType, pvLevel);
end;

procedure TSafeLogger.setAppender(pvAppender: TBaseAppender; pvOwnsAppender:
    Boolean = true);
begin
  if (FAppender <> nil) and FOwnsAppender then
  begin
    FAppender.Free;
    FAppender := nil;
  end;

  if pvAppender <> nil then
  begin
    FAppender := pvAppender;
    FOwnsAppender := pvOwnsAppender;
    FAppender.FOwner := Self;
  end;
end;

procedure TSafeLogger.start;
begin
  if FLogWorker = nil then
  begin
    FLogWorker := TLogWorker.Create(Self);

  end;
  FLogWorker.Resume;
end;

procedure TSafeLogger.stopWorker;
begin
  if FLogWorker <> nil then
  begin
    FLogWorker.Terminate;
    FLogWorker.FNotify.SetEvent;
  end;
  while (FWorkerCounter > 0) and workersIsAlive do
  begin
    {$IFDEF MSWINDOWS}
    SwitchToThread;
    {$ELSE}
    TThread.Yield;
    {$ENDIF}
  end;
  FLogWorker := nil;
end;

function TSafeLogger.workersIsAlive: Boolean;
var
  i: Integer;
  lvCode:Cardinal;
begin
  Result := false;
  if GetExitCodeThread(FLogWorker.Handle, lvCode) then
  begin
    if lvCode=STILL_ACTIVE then
    begin
      Result := true;
    end;
  end;
end;

constructor TLogWorker.Create(ASafeLogger: TSafeLogger);
begin
  inherited Create(True);
  FreeOnTerminate := true;
  FNotify := TEvent.Create(nil,false,false,'');
  FSafeLogger := ASafeLogger;
  FMessageEvent := TEvent.Create(nil, true, False, '');

end;

destructor TLogWorker.Destroy;
begin
  FNotify.Free;
  FMessageEvent.Free;
  inherited Destroy;
end;

procedure TLogWorker.Execute;
var
  lvPData:PLogDataObject;
begin
  FSafeLogger.incWorkerCount;
  try
    while not self.Terminated do
    begin
      if (FNotify.WaitFor(INFINITE)=wrSignaled) then
      begin
        while not self.Terminated do
        begin
          lvPData := FSafeLogger.FDataQueue.Pop;
          if lvPData = nil then Break;

          ExecuteLogData(lvPData);
        end;
      end;
    end;
  finally
    FSafeLogger.decWorkerCounter;
  end;
end;

procedure TLogWorker.ExecuteLogData(const pvData:PLogDataObject);
begin
  if FSafeLogger.FAppendInMainThread then
  begin
    if FSafeLogger.FSyncMainThreadType = rtSync then
    begin
      FTempLogData := pvData;
      Synchronize(InnerSyncLogData);
    end
{$IFDEF MSWINDOWS}
    else if FSafeLogger.FSyncMainThreadType = rtPostMessage then
    begin
      FMessageEvent.ResetEvent;
      if PostMessage(FSafeLogger.FMessageHandle, WM_SYNC_METHOD, WPARAM(pvData), LPARAM(FMessageEvent)) then
      begin
        FMessageEvent.WaitFor(INFINITE);
      end else
      begin
        FSafeLogger.incErrorCounter;
        // log exception
      end;
    end
{$ENDIF}
    ;
  end else
  begin
    FSafeLogger.ExecuteLogData(pvData);
  end;
end;

procedure TLogWorker.InnerSyncLogData;
begin
   FSafeLogger.ExecuteLogData(FTempLogData);
end;

constructor TStringsAppender.Create(AStrings: TStrings);
begin
  inherited Create;
  FStrings := AStrings;
end;

procedure TStringsAppender.AppendLog(pvData:PLogDataObject);
begin
  inherited;
  Assert(FStrings <> nil);
  FStrings.Add(
    Format('%s[%s]:%s',
      [FormatDateTime('yyyy-MM-dd hh:nn:ss.zzz', pvData.FTime)
        , TLogLevelCaption[pvData.FLogLevel]
        , pvData.FMsg
      ]
      ));
end;

procedure TLogFileAppender.AppendLog(pvData: PLogDataObject);
var
  lvMsg:String;
  lvFile:String;
begin
  if OpenLogFile(pvData.FMsgType) then
  begin
    try
      if FAddThreadINfo then
      begin
        lvMsg := Format('%s[%s][PID:%d,ThreadID:%d]:%s',
            [FormatDateTime('hh:nn:ss:zzz', pvData.FTime)
              , TLogLevelCaption[pvData.FLogLevel]
              , GetCurrentProcessID()
              , pvData.FThreadID
              , pvData.FMsg
            ]
            );
      end else
      begin
        lvMsg := Format('%s[%s]:%s',
            [FormatDateTime('hh:nn:ss:zzz', pvData.FTime)
              , TLogLevelCaption[pvData.FLogLevel]
              , pvData.FMsg
            ]
            );
      end;
      writeln(FLogFile, lvMsg);
      flush(FLogFile);
    finally
      CloseFile(FLogFile);
    end;
  end else
  begin
    FOwner.incErrorCounter;
  end;
end;

constructor TLogFileAppender.Create(pvAddThreadINfo: Boolean);
begin
  inherited Create;
  FBasePath :=ExtractFilePath(ParamStr(0)) + 'log';
  if not DirectoryExists(FBasePath) then CreateDir(FBasePath);
  FAddThreadINfo := pvAddThreadINfo;
end;

function TLogFileAppender.openLogFile(pvPre: String = ''): Boolean;
var
  lvFileName:String;
begin

  lvFileName :=FBasePath + '\' + pvPre + FormatDateTime('yyyymmddhh', Now()) + '.log';
  try
    AssignFile(FLogFile, lvFileName);
    if (FileExists(lvFileName)) then
      append(FLogFile)
    else
      rewrite(FLogFile);

    Result := true;
  except
    Result := false;
  end;
end;

initialization
  __dataObjectPool := TBaseQueue.Create;
  __dataObjectPool.Name := 'safeLoggerDataPool';
  sfLogger := TSafeLogger.Create();

finalization
  __dataObjectPool.Free;
  sfLogger.Free;

end.