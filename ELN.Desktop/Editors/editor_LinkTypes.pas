unit editor_LinkTypes;

// Dictionary editor for the item-link relationship vocabulary.
//
// Every type carries both a forward and a reverse caption ("derived from" /
// "precursor of") so a link reads correctly from either end. For a relation
// that reads the same both ways, put the same text in both fields — the link
// dialog then offers it once instead of twice.

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants,
  System.Classes, Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.Dialogs,
  EditorBase, Data.DB, Vcl.StdCtrls, Vcl.Buttons, RzDBNav, Vcl.Grids,
  Vcl.DBGrids, Vcl.ExtCtrls, RzPanel, Vcl.Mask, Vcl.DBCtrls;

type
  TedLinkTypes = class(TfrmEditorBase)
    edForwardText: TDBEdit;
    edReverseText: TDBEdit;
    edDescription: TDBEdit;
    edSortOrder: TDBEdit;
    Label1: TLabel;
    Label2: TLabel;
    Label3: TLabel;
    Label4: TLabel;
  private
    procedure DataSetAfterInsert(DataSet: TDataSet);
    procedure DataSetBeforeDelete(DataSet: TDataSet);
  public
    procedure Show(DataSet: TDataSet); reintroduce;
  end;

var
  edLinkTypes: TedLinkTypes;

implementation

uses
  unit_DataModel,
  unit_TimeHelper;

{$R *.dfm}

procedure TedLinkTypes.Show(DataSet: TDataSet);
begin
  DataSet.AfterInsert := DataSetAfterInsert;
  DataSet.BeforeDelete := DataSetBeforeDelete;
  inherited;
  DataSet.AfterInsert := nil;
  DataSet.BeforeDelete := nil;
end;

procedure TedLinkTypes.DataSetAfterInsert(DataSet: TDataSet);
begin
  DataSet.FieldByName('CreatedDate').AsDateTime := UTCNow;
  // Sorts after the seeded vocabulary (10..60) by default.
  DataSet.FieldByName('SortOrder').AsInteger := 100;
end;

procedure TedLinkTypes.DataSetBeforeDelete(DataSet: TDataSet);
var
  Reason: string;
begin
  Reason := Model.LinkTypes.CanDelete(DataSet.FieldByName('Id').AsInteger);
  if Reason <> '' then
  begin
    ShowMessage(Reason);
    Abort;
  end;
end;

end.
