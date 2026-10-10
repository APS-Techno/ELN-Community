unit dlg_Search;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Classes,
  Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.StdCtrls, Vcl.ExtCtrls,
  Vcl.ComCtrls,
  unit_SearchModel;

type
  TNavigateProc = procedure(Sender: TObject; ProjectId, FolderId, ItemId: Integer) of object;

  TdlgSearch = class(TForm)
    pnlTop: TPanel;
    edSearch: TEdit;
    btnSearch: TButton;
    lblCount: TLabel;
    ListView: TListView;
    pnlBottom: TPanel;
    btnGoTo: TButton;
    btnClose: TButton;
    procedure FormDestroy(Sender: TObject);
    procedure btnSearchClick(Sender: TObject);
    procedure btnGoToClick(Sender: TObject);
    procedure edSearchKeyPress(Sender: TObject; var Key: Char);
    procedure ListViewDblClick(Sender: TObject);
  private
    FResults: TSearchResults;
    FOnNavigate: TNavigateProc;
    procedure RefreshList;
    procedure NavigateToSelected;
    function KindToStr(Kind: TSearchResultKind): string;
  public
    class procedure Execute(NavigateProc: TNavigateProc);
  end;

implementation

uses
  unit_DataModel;

{$R *.dfm}


class procedure TdlgSearch.Execute(NavigateProc: TNavigateProc);
var
  Dialog: TdlgSearch;
begin
  Dialog := TdlgSearch.Create(Application);
  try
    Dialog.FOnNavigate := NavigateProc;
    Dialog.ShowModal;
  finally
    Dialog.Free;
  end;
end;

procedure TdlgSearch.FormDestroy(Sender: TObject);
begin
  FreeAndNil(FResults);
end;

function TdlgSearch.KindToStr(Kind: TSearchResultKind): string;
begin
  case Kind of
    srkItem:  Result := 'Item';
    srkEntry: Result := 'Protocol';
    srkFile:  Result := 'File';
    srkValue: Result := 'Value';
    srkTag:   Result := 'Tag';
  else
    Result := '';
  end;
end;

procedure TdlgSearch.edSearchKeyPress(Sender: TObject; var Key: Char);
begin
  if Key = #13 then
  begin
    Key := #0;
    btnSearchClick(Sender);
  end;
end;

procedure TdlgSearch.btnSearchClick(Sender: TObject);
begin
  if Length(edSearch.Text) < 2 then
  begin
    lblCount.Caption := 'Min 2 characters';
    Exit;
  end;

  Screen.Cursor := crHourGlass;
  try
    FreeAndNil(FResults);
    FResults := Model.Search.Search(edSearch.Text);
    RefreshList;
    lblCount.Caption := Format('%d result(s)', [FResults.Count]);
  finally
    Screen.Cursor := crDefault;
  end;
end;

procedure TdlgSearch.RefreshList;
var
  I: Integer;
  R: TSearchResult;
  ListItem: TListItem;
begin
  ListView.Items.BeginUpdate;
  try
    ListView.Items.Clear;
    if not Assigned(FResults) then
      Exit;

    for I := 0 to FResults.Count - 1 do
    begin
      R := FResults[I];
      ListItem := ListView.Items.Add;
      ListItem.Caption := IntToStr(R.ItemId);
      ListItem.SubItems.Add(KindToStr(R.Kind));
      ListItem.SubItems.Add(R.EntityName);
      ListItem.SubItems.Add(R.ProjectPath + ' > ' + R.ItemTitle);
      ListItem.SubItems.Add(R.MatchedField);
      ListItem.Data := Pointer(I);
    end;
  finally
    ListView.Items.EndUpdate;
  end;
end;

procedure TdlgSearch.NavigateToSelected;
var
  Idx: Integer;
  R: TSearchResult;
begin
  if ListView.Selected = nil then
    Exit;
  if not Assigned(FResults) then
    Exit;
  if not Assigned(FOnNavigate) then
    Exit;

  Idx := Integer(ListView.Selected.Data);
  if (Idx < 0) or (Idx >= FResults.Count) then
    Exit;

  R := FResults[Idx];
  ModalResult := mrOk;
  FOnNavigate(Self, R.ProjectId, R.FolderId, R.ItemId);
end;

procedure TdlgSearch.btnGoToClick(Sender: TObject);
begin
  NavigateToSelected;
end;

procedure TdlgSearch.ListViewDblClick(Sender: TObject);
begin
  NavigateToSelected;
end;

end.
