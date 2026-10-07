unit unit_FileModel;
interface
uses
  SysUtils,
  Aurelius.Linq,
  Aurelius.Bind.BaseDataset,
  Aurelius.Bind.Dataset,
  Aurelius.Drivers.Interfaces,
  Aurelius.Engine.DatabaseManager,
  Aurelius.Engine.ObjectManager,
  Aurelius.Criteria.Base,
  System.Generics.Collections,
  unit_TELNModel,
  unit_Item,
  unit_ActionType,
  unit_Equipment,
  unit_FileType,
  unit_ELNDB_Dictionary;

type

  TFileModel = class(TELNModel)
    private
      FDic: TFileDictionary;
      FManager: TObjectManager;
      FActionID: integer;

    public
      constructor Create(Manager: TObjectManager);
      destructor Destroy; override;
      procedure OpenDataSet; override;

      procedure AssignAction(const AActionID: integer);
      function GetFile(const ID: integer):TFile;
      function GetFileName(const ID: integer): string;
  end;

implementation

{ TFileModel }

procedure TFileModel.AssignAction(const AActionID: integer);
begin
  FActionID := AActionID;
end;

constructor TFileModel.Create(Manager: TObjectManager);
begin
  inherited Create;
  FManager := Manager;
  FDataSet := CreateDataSet;
  FDataSet.Manager := FManager;
  FDic := TFileDictionary.Create;
end;

destructor TFileModel.Destroy;
begin
  FreeAndNil(FDic);
  inherited;
end;

function TFileModel.GetFile(const ID: integer): TFile;
begin
  Result := FManager.Find<TFile>(ID);
end;

function TFileModel.GetFileName(const ID: integer): string;
var
  F: TFile;
begin
  F := GetFile(ID);
  if Assigned(F) then
    Result := F.FullName
  else
    Result := '';
end;

procedure TFileModel.OpenDataSet;
begin
  // Dataset not used - model uses direct ObjectManager queries
end;

end.
