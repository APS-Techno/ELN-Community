unit unit_CommunityMCPHost;

interface

procedure RunCommunityServer;

implementation

uses
  System.SysUtils, System.IOUtils, System.StrUtils,
  Aurelius.Engine.ObjectManager,
  unit_LocalNotebook, unit_LocalNotebookStorage,
  unit_MCPTools, unit_MCPTransport, unit_ToolCatalog, unit_PluginHost,
  unit_User;

function RequiredPath(const Name: string): string;
var
  I: Integer;
  Arg, Value: string;
begin
  Result := '';
  I := 1;
  while I <= ParamCount do
  begin
    Arg := ParamStr(I);
    Value := '';
    if Arg = '--' + Name then
    begin
      Inc(I);
      if I <= ParamCount then
        Value := ParamStr(I);
    end
    else if StartsStr('--' + Name + '=', Arg) then
      Value := Copy(Arg, Length(Name) + 4, MaxInt)
    else
    begin
      Inc(I);
      Continue;
    end;
    if (Value = '') or StartsStr('--', Value) then
      raise EArgumentException.Create('Missing path for --' + Name);
    if Result <> '' then
      raise EArgumentException.Create('Duplicate --' + Name);
    Result := Value;
    Inc(I);
  end;
  if Result = '' then
    raise EArgumentException.Create('Required option: --' + Name);
  if not ((Length(Result) >= 3) and (Result[2] = ':') and
    CharInSet(Result[3], ['\', '/'])) and not StartsStr('\\', Result) then
    raise EArgumentException.Create('--' + Name + ' requires an absolute path');
  Result := TPath.GetFullPath(Result);
end;

procedure CheckOptions;
var
  I: Integer;
  Arg, Name: string;
  EqualAt: Integer;
begin
  I := 1;
  while I <= ParamCount do
  begin
    Arg := ParamStr(I);
    EqualAt := Pos('=', Arg);
    if EqualAt > 0 then
      Name := Copy(Arg, 1, EqualAt - 1)
    else
      Name := Arg;
    if (Name <> '--notebook') and (Name <> '--storage') and
      (Name <> '--upload-root') and (Name <> '--plugins') then
      raise EArgumentException.Create('Unknown option: ' + Arg);
    if EqualAt = 0 then
      Inc(I);
    Inc(I);
  end;
end;

procedure RunCommunityServer;
var
  NotebookPath, StoragePath, UploadPath, PluginsPath: string;
  Notebook: TLocalNotebook;
  Manager: TObjectManager;
  Plugins: TPluginHost;
  Registry: TToolRegistry;
  Context: TToolContext;
  PrincipalId: Integer;
  UploadValidator: TLocalNotebookStorage;
begin
  CheckOptions;
  NotebookPath := RequiredPath('notebook');
  StoragePath := RequiredPath('storage');
  UploadPath := RequiredPath('upload-root');
  PluginsPath := RequiredPath('plugins');
  if not TDirectory.Exists(UploadPath) then
    raise EArgumentException.Create('--upload-root directory does not exist');
  if not TDirectory.Exists(PluginsPath) then
    raise EArgumentException.Create('--plugins directory does not exist');
  // Reject ambiguous aliases and reparse points on the allowed import root.
  UploadValidator := TLocalNotebookStorage.Create(UploadPath);
  try
    UploadValidator.ResolvePath('__source_root_check__');
  finally
    UploadValidator.Free;
  end;
  // Open validates the local format; it never creates or migrates a notebook.
  Notebook := TLocalNotebook.Open(NotebookPath, StoragePath);
  try
    PrincipalId := Notebook.Principal.Id;
    // The notebook keeps its own principal alive. Clearing the tool manager
    // must never invalidate Notebook.Principal or the desktop composition.
    Manager := TObjectManager.Create(Notebook.Connection);
    try
      Plugins := TPluginHost.Create(PluginsPath);
      try
        Context := Default(TToolContext);
        Context.Manager := Manager;
        Context.StorageRoot := StoragePath;
        Context.Storage := Notebook.Storage;
        Context.AccessPolicy := Notebook.AccessPolicy;
        Context.PluginHost := Plugins;
        Context.UploadRoot := UploadPath;
        Context.User := Manager.Find<TUser>(PrincipalId);
        Registry := TToolRegistry.Create(Context);
        try
          RegisterAllTools(Registry);
          RunToolServer(Registry,
            procedure
            var
              FreshUser: TUser;
            begin
              Registry.SetUser(nil);
              Manager.Clear;
              FreshUser := Manager.Find<TUser>(PrincipalId);
              if (FreshUser = nil) or FreshUser.IsArchived then
                raise Exception.Create('Local notebook principal is no longer active');
              Registry.SetUser(FreshUser);
            end);
        finally
          Registry.Free;
        end;
      finally
        Plugins.Free;
      end;
    finally
      Manager.Free;
    end;
  finally
    Notebook.Free;
  end;
end;

end.
