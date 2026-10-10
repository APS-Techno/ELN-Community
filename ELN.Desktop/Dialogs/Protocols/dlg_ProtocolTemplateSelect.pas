unit dlg_ProtocolTemplateSelect;

interface

uses
  Winapi.Windows, System.SysUtils, System.Classes,
  System.Generics.Collections, System.Generics.Defaults,
  Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.StdCtrls, Vcl.ExtCtrls,
  RzPanel, RzButton, RzLstBox, RzLabel,
  unit_Template;

type
  TdlgTemplateSelect = class(TForm)
    pnlBottom: TRzPanel;
    btnOK: TRzBitBtn;
    btnCancel: TRzBitBtn;
    pnlMain: TRzPanel;
    lblCategories: TRzLabel;
    lbCategories: TRzListBox;
    lblTemplates: TRzLabel;
    lbTemplates: TRzListBox;
    lblDescCaption: TRzLabel;
    lblDescription: TRzLabel;
    procedure lbCategoriesClick(Sender: TObject);
    procedure lbTemplatesClick(Sender: TObject);
    procedure lbTemplatesDblClick(Sender: TObject);
    procedure FormCreate(Sender: TObject);
  private
    FTemplateList: TTemplates;
    FCategoryTemplates: TObjectDictionary<string, TList<TTemplate>>;
    procedure PopulateCategories;
    procedure FilterTemplates;
    function GetSelectedTemplate: TTemplate;
  public
    destructor Destroy; override;
  end;

function ShowTemplateSelectDialog(out SelectedTemplate: TTemplate): Boolean;

implementation

uses
  unit_DataModel;

{$R *.dfm}

const
  NO_TEMPLATE = '(No template)';

function ShowTemplateSelectDialog(out SelectedTemplate: TTemplate): Boolean;
var
  Dlg: TdlgTemplateSelect;
begin
  Result := False;
  SelectedTemplate := nil;

  Dlg := TdlgTemplateSelect.Create(Application.MainForm);
  try
    if Dlg.ShowModal = mrOk then
    begin
      SelectedTemplate := Dlg.GetSelectedTemplate;
      Result := True;
    end;
  finally
    Dlg.Free;
  end;
end;


destructor TdlgTemplateSelect.Destroy;
begin
  FTemplateList.Free;
  FCategoryTemplates.Free;
  inherited;
end;

procedure TdlgTemplateSelect.FormCreate(Sender: TObject);
begin
  FCategoryTemplates := TObjectDictionary<string, TList<TTemplate>>.Create([doOwnsValues]);
  PopulateCategories;

  if lbCategories.Items.Count > 0 then
  begin
    lbCategories.ItemIndex := 0;
    FilterTemplates;
  end;
end;

procedure TdlgTemplateSelect.PopulateCategories;
var
  T: TTemplate;
  Cat: string;
  CatList: TList<TTemplate>;
begin
  lbCategories.Items.Clear;
  lbCategories.Items.Add(NO_TEMPLATE);

  FTemplateList := Model.Templates.GetLatestVersions;
  if not Assigned(FTemplateList) or (FTemplateList.Count = 0) then
    Exit;

  FTemplateList.Sort(TComparer<TTemplate>.Construct(
    function(const L, R: TTemplate): Integer
    begin
      Result := CompareText(L.Category, R.Category);
      if Result = 0 then
        Result := CompareText(L.Name, R.Name);
    end));

  for T in FTemplateList do
  begin
    Cat := T.Category;
    if Cat = '' then
      Cat := 'Uncategorized';

    if not FCategoryTemplates.TryGetValue(Cat, CatList) then
    begin
      CatList := TList<TTemplate>.Create;
      FCategoryTemplates.Add(Cat, CatList);
      lbCategories.Items.Add(Cat);
    end;
    CatList.Add(T);
  end;
end;

procedure TdlgTemplateSelect.FilterTemplates;
var
  SelIdx: Integer;
  CatName: string;
  CatList: TList<TTemplate>;
  T: TTemplate;
  DisplayName: string;
begin
  lbTemplates.Items.Clear;
  lblDescription.Caption := '';

  SelIdx := lbCategories.ItemIndex;
  if SelIdx < 0 then Exit;

  if SelIdx = 0 then
  begin
    btnOK.Enabled := True;
    Exit;
  end;

  CatName := lbCategories.Items[SelIdx];
  if FCategoryTemplates.TryGetValue(CatName, CatList) then
  begin
    for T in CatList do
    begin
      if T.Version > 1 then
        DisplayName := Format('%s (v%d)', [T.Name, T.Version])
      else
        DisplayName := T.Name;
      lbTemplates.Items.AddObject(DisplayName, T);
    end;
  end;

  btnOK.Enabled := False;
end;

procedure TdlgTemplateSelect.lbCategoriesClick(Sender: TObject);
begin
  FilterTemplates;
end;

procedure TdlgTemplateSelect.lbTemplatesClick(Sender: TObject);
var
  T: TTemplate;
begin
  if (lbTemplates.ItemIndex >= 0) and
     Assigned(lbTemplates.Items.Objects[lbTemplates.ItemIndex]) then
  begin
    T := TTemplate(lbTemplates.Items.Objects[lbTemplates.ItemIndex]);
    lblDescription.Caption := T.Description;
    btnOK.Enabled := True;
  end
  else
  begin
    lblDescription.Caption := '';
    btnOK.Enabled := False;
  end;
end;

procedure TdlgTemplateSelect.lbTemplatesDblClick(Sender: TObject);
begin
  if (lbTemplates.ItemIndex >= 0) and
     Assigned(lbTemplates.Items.Objects[lbTemplates.ItemIndex]) then
    ModalResult := mrOk;
end;

function TdlgTemplateSelect.GetSelectedTemplate: TTemplate;
begin
  if lbCategories.ItemIndex = 0 then
    Result := nil
  else if (lbTemplates.ItemIndex >= 0) and
          Assigned(lbTemplates.Items.Objects[lbTemplates.ItemIndex]) then
    Result := TTemplate(lbTemplates.Items.Objects[lbTemplates.ItemIndex])
  else
    Result := nil;
end;

end.
