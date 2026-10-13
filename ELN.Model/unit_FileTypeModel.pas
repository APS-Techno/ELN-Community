unit unit_FileTypeModel;

interface
uses
  SysUtils,
  Aurelius.Bind.BaseDataset,
  Aurelius.Bind.Dataset,
  Aurelius.Drivers.Interfaces,
  Aurelius.Engine.DatabaseManager,
  Aurelius.Engine.ObjectManager,
  Aurelius.Criteria.Base,
  unit_Types,

  unit_FileType,
  unit_TELNModel,
  unit_ELNDB_Dictionary;

type

  TFileTypeModel = class(TELNModel)
    private
      FDic: TFileTypeDictionary;
      FManager: TObjectManager;
    protected
      function GetDataSet: TAureliusDataset; override;
    public
      constructor Create(Manager: TObjectManager);
      destructor Destroy; override;
      procedure OpenDataSet; override;
      procedure CreateDefaultData;
      procedure AddFileType(const Ext, Description: string);
      function GetFileType(const ID: integer): TFileType;
      function GetFileTypeByExt(const Ext: string): TFileType;
      function GetFileTypes: TFileTypes;
      function FindDuplicateExt(const Ext: string; ExcludeID: Integer): TFileType;
      function CanDelete(ID: Integer): string;
      property Manager: TObjectManager read FManager;
  end;
implementation

uses
  unit_Item,
  unit_FileTypeLink,
  unit_TimeHelper;



procedure TFileTypeModel.AddFileType(const Ext, Description: string);
var
  FType: TFileType;
begin
  FType := TFileType.Create;

  FType.Ext := Ext;
  FType.Description := Description;
  FType.CreatedDate := UTCNow;
  FType.CreatedBy := 1;

  FManager.Save(FType);
end;

constructor TFileTypeModel.Create(Manager: TObjectManager);
begin
  inherited Create;
  FManager := Manager;
  FDataSet := CreateDataSet;
  FDataSet.Manager := FManager;
  FDic := TFileTypeDictionary.Create;
end;

procedure TFileTypeModel.CreateDefaultData;
begin
  AddFileType('.xrcx','X-Ray Calc Project');
  AddFileType('.opju','Origin Project');
  AddFileType('.pdf','PDF File');
  AddFileType('.xlsx','Excel Sheet');
  AddFileType('.dsc','Sputtering Recipie');
  AddFileType('.log','Sputtering log');
  AddFileType('.process.log','Process Event Log');
  AddFileType('.rcpx','Process Recipe');
  AddFileType('.rp4','3D Profile');
  AddFileType('.xrdml','XRD Data');
  AddFileType('.tiff','TIFF Image');
  AddFileType('.fibps','Optical Profilometer');
  AddFileType('.zrw','Tribotester Data');
  AddFileType('.dat','Columnar Data');
  AddFileType('.csv','CSV Data');
  AddFileType('.ascii','ASCII Data');
  AddFileType('.mit','Nanoindentation Data');
  AddFileType('.lmpin','LAMMPS Input Script');
  AddFileType('.dump','LAMMPS Data File');
  AddFileType('.xrfx','XRF Optimization Results');
  AddFileType('.raw','Tribometer Raw Data');
  AddFileType('.tsv','Deposition Log');
  AddFileType('.json','JSON Data');
  AddFileType('.data','LAMMPS Data');
  AddFileType('.lammps','LAMMPS Data');
end;

destructor TFileTypeModel.Destroy;
begin
  FreeAndNil(FDic);
  inherited;
end;

function TFileTypeModel.GetDataSet: TAureliusDataset;
begin
  OpenDataSet;
  Result := FDataSet;
end;

function TFileTypeModel.GetFileType(const ID: integer): TFileType;
begin
  Result := FManager.Find<TFileType>(ID);
end;

function TFileTypeModel.GetFileTypeByExt(const Ext: string): TFileType;
var
  List: TFileTypes;
  FT: TFileType;
begin
  Result := nil;
  List := FManager.Find<TFileType>.List;
  for FT in List do
    if SameText(FT.Ext, Ext) then
      Exit(FT);
end;

function TFileTypeModel.GetFileTypes: TFileTypes;
begin
  Result := FManager.Find<TFileType>.OrderBy(FDic.ID).List;
end;

// Returns the first OTHER file type registered against the same extension,
// or nil when Ext is unique. ExcludeID is the row being edited (0 when new).
// Duplicate extensions make every SameText(FT.Ext, ...) lookup in the app
// resolve to whichever row is reached first, so the label/icon a file gets
// becomes arbitrary.
function TFileTypeModel.FindDuplicateExt(const Ext: string;
  ExcludeID: Integer): TFileType;
var
  List: TFileTypes;
  FT: TFileType;
begin
  Result := nil;
  // TFileTypes is a plain TList<TFileType>; entities stay owned by the manager,
  // so freeing the list does not invalidate the result.
  List := FManager.Find<TFileType>.List;
  try
    for FT in List do
      if (FT.Id <> ExcludeID) and SameText(FT.Ext, Ext) then
        Exit(FT);
  finally
    List.Free;
  end;
end;

procedure TFileTypeModel.OpenDataSet;
begin
  FDataSet.Close;
  FDataSet.SetSourceCriteria(FManager.Find<TFileType>);
  FDataSet.Open;
end;

function TFileTypeModel.CanDelete(ID: Integer): string;
var
  FileDic: TFileDictionary;
  LinkDic: TFileTypeLinkDictionary;
  FileCount, LinkCount: Integer;
begin
  Result := '';
  FileDic := TFileDictionary.Create;
  LinkDic := TFileTypeLinkDictionary.Create;
  try
    FileCount := FManager.Find<TFile>.Where(FileDic.Typeid.Id = ID).List.Count;
    LinkCount := FManager.Find<TFileTypeLink>.Where(LinkDic.FileType_.Id = ID).List.Count;
    if (FileCount > 0) or (LinkCount > 0) then
      Result := Format('Cannot delete: used by %d file(s) and %d action type link(s).', [FileCount, LinkCount]);
  finally
    FileDic.Free;
    LinkDic.Free;
  end;
end;

end.
