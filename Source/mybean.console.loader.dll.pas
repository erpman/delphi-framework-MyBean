(*
 *	 Unit owner: D10.天地弦
 *	   blog: http://www.cnblogs.com/dksoft
 *
 *   v0.1.1(2014-11-06 21:27:40)
 *     修正checkIsValidLib- bug, 释放时判断是否BPL，bpl按照BPL释放的方式
 *
 *   v0.1.0(2014-08-29 13:00)
 *     修改加载方式(beanMananger.dll-改造)
 *
 *	 v0.0.1(2014-05-17)
 *     + first release
 *
 *
 *)

 
unit mybean.console.loader.dll;

interface

uses
  Windows, SysUtils, Classes, mybean.core.intf, superobject, mybean.core.SOTools,
  mybean.console.loader;

type
  /// <summary>
  ///   DLL文件管理
  /// </summary>
  TLibFactoryObject = class(TBaseFactoryObject)
  private
    FLibHandle:THandle;
    FLibFileName: String;
  private
    procedure DoInitalizeBeanFactory;

    procedure DoCreatePluginFactory;
    procedure DoFinalizeBeanFactory;

    procedure DoInitialize;
    procedure SetLibFileName(const Value: String);
    function GetBeanFactoryForCPlus(out beanFactory: IBeanFactory): Boolean;
  public
    function GetBeanIDList():String;
  public
    procedure CheckInitialize; override;

    procedure Cleanup; override;

    procedure StartService; override;

    /// <summary>
    ///   判断指定的Lib文件是否是MyBean的插件文件
    /// </summary>
    function CheckIsValidLib(pvUnLoadIfSucc: Boolean = false): Boolean; override;

    /// <summary>
    ///   根据beanID获取插件
    /// </summary>
    function GetBean(pvBeanID:string): IInterface; override;

    /// <summary>
    ///   释放Dll句柄
    /// </summary>
    procedure DoFreeLibrary;

    /// <summary>
    ///   加载dll文件
    /// </summary>
    function CheckLoadLibrary(pvRaiseIfNil: Boolean = true): Boolean;

    /// <summary>
    ///   DLL文件
    /// </summary>
    property LibFileName: String read FLibFileName write SetLibFileName;
  end;

implementation

function TLibFactoryObject.GetBeanFactoryForCPlus(out beanFactory:
    IBeanFactory): Boolean;
var
  lvProc:procedure(out beanFactory:IBeanFactory); stdcall;
begin
  @lvProc := GetProcAddress(FLibHandle, PChar('GetBeanFactoryForCPlus'));
  if (@lvProc <> nil) then
  begin       
    lvProc(beanFactory);
    FIsDelphiLib := False; 
  end;
  Result := beanFactory <> nil;
end;

function TLibFactoryObject.GetBeanIDList: String;
var
  lvBeanIDs:array[1..4096] of AnsiChar;
  lvRet:AnsiString;
begin
  FillChar(lvBeanIDs[1], 4096, 0);
  (FBeanFactory as  IBeanFactory).getBeanList(@lvBeanIDs[1], 4096);
  lvRet := StrPas(PAnsiChar(@lvBeanIDs[1]));
  Result := lvRet;
end;

procedure TLibFactoryObject.DoCreatePluginFactory;
var
  lvFunc : function:IBeanFactory; stdcall;
begin
  if not GetBeanFactoryForCPlus(FBeanFactory) then
  begin
    @lvFunc := GetProcAddress(FLibHandle, PChar('getBeanFactory'));
    if (@lvFunc = nil) then
    begin
      raise Exception.CreateFmt('非法的Plugin模块文件(%s),找不到入口函数(getBeanFactory)', [self.FLibFileName]);
    end;
    FBeanFactory := lvFunc;
    if FBeanFactory = nil then
    begin
      raise Exception.CreateFmt('非法的Plugin模块文件(%s),getBeanFactory 返回的对象为Nil', [self.FLibFileName]);
    end;
    FIsDelphiLib := True;
  end;
end;

procedure TLibFactoryObject.DoFreeLibrary;
begin
  FBeanFactory := nil;
  if FLibHandle <> 0 then
  begin
    if LowerCase(ExtractFileExt(FLibFileName)) = '.bpl' then
    begin
      UnloadPackage(FLibHandle);
    end else
    begin
      FreeLibrary(FLibHandle);
    end;

  end;
end;

procedure TLibFactoryObject.DoInitalizeBeanFactory;
var
  lvFunc:procedure(appContext: IApplicationContext; appKeyMap: IKeyMap); stdcall;
  lvProc:procedure(func: TGetInterfaceFunctionForStdcall) stdcall;
begin
  @lvFunc := GetProcAddress(FLibHandle, PChar('InitializeLibrary'));
  if (@lvFunc <> nil) then
  begin
    lvFunc(appPluginContext, applicationKeyMap);
  end else
  begin
    @lvFunc := GetProcAddress(FLibHandle, PChar('initializeBeanFactory'));
    if (@lvFunc = nil) then
    begin
      raise Exception.CreateFmt(
        '非法的Plugin模块文件(%s),找不到入口函数(initializeBeanFactory)',
        [self.FLibFileName]);
    end;
    lvFunc(appPluginContext, applicationKeyMap);
  end;

  lvProc := GetProcAddress(FLibHandle, PChar('SetApplicationContextGetterFunction'));
  if (@lvProc <> nil) then
  begin
    lvProc(__GetApplicationContextFunctionForStdcall);
  end;

  lvProc := GetProcAddress(FLibHandle, PChar('SetApplicationMapGetterFunction'));
  if (@lvProc <> nil) then
  begin
    lvProc(__GetApplicationMapFunctionForStdcall);
  end;
end;

procedure TLibFactoryObject.DoInitialize;
begin
  DoInitalizeBeanFactory;
  DoCreatePluginFactory;
  if FIsDelphiLib then
  begin
    (FBeanFactory as IBeanFactory).CheckInitalize;
  end;
end;

procedure TLibFactoryObject.CheckInitialize;
var
  lvConfigStr, lvBeanID:AnsiString;
  lvBeanConfig:ISuperObject;
  i: Integer;
begin
  if FbeanFactory = nil then
  begin
    CheckLoadLibrary;

    //将配置传入到beanFactory中
    for i := 0 to FConfig.A['list'].Length-1 do
    begin
      lvBeanConfig := FConfig.A['list'].O[i];
      lvBeanID := AnsiString(lvBeanConfig.S['id']);
      lvConfigStr := AnsiString(lvBeanConfig.AsJSon(false, false));

      (FBeanFactory as IBeanFactory).configBean(PAnsiChar(lvBeanID), PAnsiChar(lvConfigStr));

    end;
  end;

  //避免提前释放
  lvConfigStr := '';
  lvBeanID:= '';
end;

function TLibFactoryObject.CheckIsValidLib(pvUnLoadIfSucc: Boolean = false):
    Boolean;
var
  lvFunc:procedure(appContext: IApplicationContext; appKeyMap: IKeyMap); stdcall;
  lvLibHandle:THandle;
  lvIsBpl:Boolean;
begin
  Result := false;
  if FLibHandle = 0 then
  begin
    lvIsBpl :=LowerCase(ExtractFileExt(FLibFileName)) = '.bpl';
    if lvIsBpl then
    begin
      lvLibHandle := LoadPackage(FLibFileName);
    end else
    begin
      lvLibHandle := LoadLibrary(PChar(FLibFileName));
    end;


    if lvLibHandle <> 0 then
    begin
      try
        // 大写
        @lvFunc := GetProcAddress(lvLibHandle, PChar('InitializeLibrary'));
        result := (@lvFunc <> nil);
        
        if not Result then
        begin
          @lvFunc := GetProcAddress(lvLibHandle, PChar('initializeBeanFactory'));  
          result := (@lvFunc <> nil);
        end;
      finally
        if Result then
        begin
          if pvUnLoadIfSucc then
          begin
            if lvIsBpl then
            begin
              UnloadPackage(lvLibHandle);
            end else
            begin
              FreeLibrary(lvLibHandle);
            end;
          end else
          begin
            FLibHandle := lvLibHandle;
          end;
        end else
        begin    // 不是MyBean插件
          if lvIsBpl then
          begin
            UnloadPackage(lvLibHandle);
          end else
          begin
            FreeLibrary(lvLibHandle);
          end;
        end;
      end;
    end else
    begin
      Result := false;
    end;
  end else
  begin   // 已经成功加载
    Result := true;
  end;
end;

function TLibFactoryObject.CheckLoadLibrary(pvRaiseIfNil: Boolean = true):
    Boolean;
begin
  if FLibHandle = 0 then
  begin
    if not FileExists(FLibFileName) then
    begin
      if pvRaiseIfNil then
      begin
        raise Exception.Create('文件[' + FLibFileName + ']未找到!');
      end;
    end else
    begin
      if LowerCase(ExtractFileExt(FLibFileName)) = '.bpl' then
      begin
        FLibHandle := LoadPackage(FLibFileName);
      end else
      begin
        FLibHandle := LoadLibrary(PChar(FLibFileName));
      end;
    end;
  end;
  Result := FLibHandle <> 0;
  if not Result then RaiseLastOSError;  
  if Result then DoInitialize;  
end;

procedure TLibFactoryObject.Cleanup;
begin
  DoFinalizeBeanFactory;
  DoFreeLibrary;
end;

procedure TLibFactoryObject.DoFinalizeBeanFactory;
var
  lvFunc:procedure(); stdcall;
begin
  @lvFunc := GetProcAddress(FLibHandle, PChar('FinalizeLibrary'));
  if (@lvFunc <> nil) then
  begin
    lvFunc();
  end;
end;

function TLibFactoryObject.GetBean(pvBeanID:string): IInterface;
begin
  result := inherited GetBean(pvBeanID);
end;

procedure TLibFactoryObject.SetLibFileName(const Value: String);
begin
  FLibFileName := Value;
  Fnamespace := FLibFileName;
end;

procedure TLibFactoryObject.StartService;
var
  lvFunc:procedure(); stdcall;
begin
  @lvFunc := GetProcAddress(FLibHandle, PChar('StartLibraryService'));
  if (@lvFunc <> nil) then
  begin
    lvFunc();
  end;

end;

end.
