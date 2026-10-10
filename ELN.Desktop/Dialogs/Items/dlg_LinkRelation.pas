unit dlg_LinkRelation;


interface

uses
  Winapi.Windows,
  System.SysUtils, System.Classes, System.Generics.Collections,
  Vcl.Controls, Vcl.Forms, Vcl.StdCtrls, Vcl.ExtCtrls;

type
  TLinkRelationResult = record
    LinkTypeId: Integer;
    IsForward: Boolean;
    Notes: string;
  end;

  TdlgLinkRelation = class(TForm)
    lblRelation: TLabel;
    cbRelation: TComboBox;
    lblSentence: TLabel;
    lblNotes: TLabel;
    edNotes: TMemo;
    btnOK: TButton;
    btnCancel: TButton;
    procedure cbRelationChange(Sender: TObject);
  private
    FThisTitle: string;
    FOtherTitle: string;
    FEntries: TList<TLinkRelationResult>;
    procedure LoadRelations;
    procedure UpdateSentence;
    procedure Preselect(const AResult: TLinkRelationResult);
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;

    /// A non-zero LinkTypeId in AResult selects edit mode and its stored direction.
    class function Execute(const AThisTitle, AOtherTitle: string;
      var AResult: TLinkRelationResult): Boolean;
  end;

implementation

uses
  unit_DataModel,
  unit_LinkType;

{$R *.dfm}


constructor TdlgLinkRelation.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FEntries := TList<TLinkRelationResult>.Create;
end;

destructor TdlgLinkRelation.Destroy;
begin
  FreeAndNil(FEntries);
  inherited;
end;

procedure TdlgLinkRelation.LoadRelations;
var
  Types: TLinkTypes;
  LT: TLinkType;
  Entry: TLinkRelationResult;
begin
  cbRelation.Items.BeginUpdate;
  try
    cbRelation.Items.Clear;
    FEntries.Clear;

    Types := Model.LinkTypes.GetLinkTypes;
    try
      for LT in Types do
      begin
        Entry := Default(TLinkRelationResult);
        Entry.LinkTypeId := LT.Id;
        Entry.IsForward := True;
        FEntries.Add(Entry);
        cbRelation.Items.Add(LT.ForwardText);

        if LT.IsSymmetric then
          Continue;

        Entry.IsForward := False;
        FEntries.Add(Entry);
        cbRelation.Items.Add(LT.ReverseText);
      end;
    finally
      Types.Free;
    end;
  finally
    cbRelation.Items.EndUpdate;
  end;

  if cbRelation.Items.Count > 0 then
    cbRelation.ItemIndex := 0;
  UpdateSentence;
end;

procedure TdlgLinkRelation.UpdateSentence;
begin
  if (cbRelation.ItemIndex < 0) or (cbRelation.ItemIndex >= FEntries.Count) then
  begin
    lblSentence.Caption := '';
    btnOK.Enabled := False;
    Exit;
  end;

  lblSentence.Caption := Format('%s   %s   %s',
    [FThisTitle, cbRelation.Text, FOtherTitle]);
  btnOK.Enabled := True;
end;

procedure TdlgLinkRelation.Preselect(const AResult: TLinkRelationResult);
var
  I: Integer;
begin
  for I := 0 to FEntries.Count - 1 do
    if (FEntries[I].LinkTypeId = AResult.LinkTypeId) and
       (FEntries[I].IsForward = AResult.IsForward) then
    begin
      cbRelation.ItemIndex := I;
      UpdateSentence;
      Break;
    end;
end;

procedure TdlgLinkRelation.cbRelationChange(Sender: TObject);
begin
  UpdateSentence;
end;

class function TdlgLinkRelation.Execute(const AThisTitle, AOtherTitle: string;
  var AResult: TLinkRelationResult): Boolean;
var
  Dlg: TdlgLinkRelation;
  Entry: TLinkRelationResult;
begin
  Result := False;
  Dlg := TdlgLinkRelation.Create(Application);
  try
    Dlg.FThisTitle := AThisTitle;
    Dlg.FOtherTitle := AOtherTitle;
    Dlg.Caption := Format('Link to ''%s''', [AOtherTitle]);
    Dlg.LoadRelations;

    if AResult.LinkTypeId > 0 then
      Dlg.Preselect(AResult);
    Dlg.edNotes.Text := AResult.Notes;

    if Dlg.ShowModal <> mrOK then
      Exit;

    if (Dlg.cbRelation.ItemIndex < 0) or
       (Dlg.cbRelation.ItemIndex >= Dlg.FEntries.Count) then
      Exit;

    Entry := Dlg.FEntries[Dlg.cbRelation.ItemIndex];
    AResult.LinkTypeId := Entry.LinkTypeId;
    AResult.IsForward := Entry.IsForward;
    AResult.Notes := Trim(Dlg.edNotes.Text);
    Result := True;
  finally
    Dlg.Free;
  end;
end;

end.
