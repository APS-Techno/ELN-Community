unit unit_DBSettingsModel;

interface

uses
  System.SysUtils,
  Aurelius.Engine.ObjectManager,
  unit_DBSetting;

type
  TDBSettingsModel = class
  private
    FManager: TObjectManager;
  public
    constructor Create(AManager: TObjectManager);
    function GetValue(const AKey: string; const ADefault: string = ''): string;
    procedure SetValue(const AKey, AValue: string);
    class procedure StoreValue(AManager: TObjectManager;
      const AKey, AValue: string); static;
    function GetDBGuid: string;
    procedure EnsureDBGuid;
  end;

implementation

uses
  System.Generics.Collections,
  Aurelius.Criteria.Base,
  Aurelius.Criteria.Linq;

const
  KEY_DB_GUID = 'DB_GUID';


constructor TDBSettingsModel.Create(AManager: TObjectManager);
begin
  inherited Create;
  FManager := AManager;
end;

function TDBSettingsModel.GetValue(const AKey: string; const ADefault: string): string;
var
  Setting: TDBSetting;
begin
  Setting := FManager.Find<TDBSetting>(AKey);
  if Assigned(Setting) then
    Result := Setting.SettingValue
  else
    Result := ADefault;
end;

procedure TDBSettingsModel.SetValue(const AKey, AValue: string);
begin
  StoreValue(FManager, AKey, AValue);
end;

class procedure TDBSettingsModel.StoreValue(AManager: TObjectManager;
  const AKey, AValue: string);
var
  Setting: TDBSetting;
begin
  Setting := AManager.Find<TDBSetting>(AKey);
  if Assigned(Setting) then
  begin
    Setting.SettingValue := AValue;
    AManager.Flush;
  end
  else
  begin
    Setting := TDBSetting.Create;
    Setting.SettingKey := AKey;
    Setting.SettingValue := AValue;
    AManager.Save(Setting);
    AManager.Flush;
  end;
end;

function TDBSettingsModel.GetDBGuid: string;
begin
  Result := GetValue(KEY_DB_GUID, '');
end;

procedure TDBSettingsModel.EnsureDBGuid;
var
  Guid: TGUID;
begin
  if GetDBGuid = '' then
  begin
    CreateGUID(Guid);
    SetValue(KEY_DB_GUID, GUIDToString(Guid));
  end;
end;

end.
