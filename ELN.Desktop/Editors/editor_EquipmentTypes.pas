unit editor_EquipmentTypes;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants, System.Classes, Vcl.Graphics,
  Vcl.Controls, Vcl.Forms, Vcl.Dialogs, EditorBase, Data.DB, Vcl.StdCtrls,
  Vcl.Buttons, RzDBNav, Vcl.Grids, Vcl.DBGrids, Vcl.ExtCtrls, RzPanel, Vcl.Mask,
  Vcl.DBCtrls;

type
  TedEquipmentTypes = class(TfrmEditorBase)
    edType: TDBEdit;
    edDescription: TDBEdit;
    Label1: TLabel;
    Label2: TLabel;
  private
    procedure DataSetAfterInsert(DataSet: TDataSet);
    procedure DataSetBeforeDelete(DataSet: TDataSet);
  public
    procedure Show(DataSet: TDataSet); reintroduce;
  end;

var
  edEquipmentTypes: TedEquipmentTypes;

implementation

uses
  unit_DataModel,
  unit_TimeHelper;

{$R *.dfm}

procedure TedEquipmentTypes.Show(DataSet: TDataSet);
begin
  DataSet.AfterInsert := DataSetAfterInsert;
  DataSet.BeforeDelete := DataSetBeforeDelete;
  inherited;
  DataSet.AfterInsert := nil;
  DataSet.BeforeDelete := nil;
end;

procedure TedEquipmentTypes.DataSetAfterInsert(DataSet: TDataSet);
begin
  DataSet.FieldByName('CreatedDate').AsDateTime := UTCNow;
end;

procedure TedEquipmentTypes.DataSetBeforeDelete(DataSet: TDataSet);
var
  Reason: string;
begin
  Reason := Model.EquipmentTypes.CanDelete(DataSet.FieldByName('Id').AsInteger);
  if Reason <> '' then
  begin
    ShowMessage(Reason);
    Abort;
  end;
end;

end.
