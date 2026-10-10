unit unit_TELNModel;

interface
uses
  SysUtils,
  Aurelius.Bind.BaseDataset,
  Aurelius.Bind.Dataset,
  Aurelius.Drivers.Interfaces,
  Aurelius.Engine.DatabaseManager,
  Aurelius.Engine.ObjectManager,
  unit_Types,
  unit_ELNDB_Dictionary;

type
  TELNModel = class
    protected
      FDataSet: TAureliusDataset;
      FName: string;
      function GetDataSet: TAureliusDataset; virtual;
      function CreateDataSet: TAureliusDataset;
      procedure OpenDataSet; virtual; abstract;
    public
      constructor Create;

      destructor Destroy; override;
      property Name:string read FName write FName;
      property DataSet:TAureliusDataset read GetDataSet;
  end;

implementation


constructor TELNModel.Create;
begin
  inherited Create;
end;

destructor TELNModel.Destroy;
begin
  FreeAndNil(FDataSet);
  inherited;
end;

function TELNModel.CreateDataSet: TAureliusDataset;
begin
  Result := TAureliusDataset.Create(nil);
  Result.ForceWideTypes := True;
end;

function TELNModel.GetDataSet: TAureliusDataset;
begin
  Result := FDataSet;
end;

end.
