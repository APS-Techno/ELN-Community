unit dlg_GoToItem;


interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants,
  System.Classes, Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.Dialogs,
  Vcl.StdCtrls;

type
  TdlgGoToItem = class(TForm)
    lblPrompt: TLabel;
    cbInput: TComboBox;
    lblError: TLabel;
    btnOK: TButton;
    btnCancel: TButton;
    procedure FormShow(Sender: TObject);
    procedure btnOKClick(Sender: TObject);
  private
    procedure ShowError(const Msg: string);
    procedure ClearError;
    function BuildUrl(const RawInput: string): string;
    procedure LoadHistory;
    procedure SaveHistoryEntry(const Entry: string);
  public
    class procedure Execute;
  end;

implementation

{$R *.dfm}

uses
  System.StrUtils,
  unit_ElnLinkHandler,
  unit_ELNPluginCore,
  unit_NotebookSettings;

const
  HISTORY_MAX = 10;

class procedure TdlgGoToItem.Execute;
var
  Dialog: TdlgGoToItem;
begin
  Dialog := TdlgGoToItem.Create(Application);
  try
    Dialog.ShowModal;
  finally
    Dialog.Free;
  end;
end;

procedure TdlgGoToItem.FormShow(Sender: TObject);
begin
  ClearError;
  LoadHistory;
  cbInput.SetFocus;
  cbInput.SelectAll;
end;

procedure TdlgGoToItem.btnOKClick(Sender: TObject);
var
  RawInput, Url: string;
begin
  ClearError;

  RawInput := Trim(cbInput.Text);
  if RawInput = '' then
  begin
    ShowError('Enter an item ID or eln:// URL.');
    Exit;
  end;

  Url := BuildUrl(RawInput);

  if (ElnLinkHandler = nil) or (not ElnLinkHandler.HandleLink(Url)) then
  begin
    ShowError('Item not found.');
    cbInput.SetFocus;
    cbInput.SelectAll;
    Exit;
  end;

  SaveHistoryEntry(RawInput);
  ModalResult := mrOk;
end;

procedure TdlgGoToItem.ShowError(const Msg: string);
begin
  lblError.Caption := Msg;
end;

procedure TdlgGoToItem.ClearError;
begin
  lblError.Caption := ' ';
end;

function TdlgGoToItem.BuildUrl(const RawInput: string): string;
var
  Trimmed: string;
begin
  Trimmed := Trim(RawInput);
  if Trimmed = '' then
  begin
    Result := '';
    Exit;
  end;

  if StartsText('eln://', Trimmed) then
    Result := Trimmed
  else
    Result := 'eln://item/' + Trimmed;
end;

procedure TdlgGoToItem.LoadHistory;
var
  Settings: TNotebookSettings;
  HistText: string;
  List: TStringList;
begin
  cbInput.Items.Clear;
  cbInput.Text := '';

  Settings := TNotebookSettings.Create;
  try
    HistText := Settings.GoToItemHistory;
  finally
    Settings.Free;
  end;

  if HistText = '' then Exit;

  List := TStringList.Create;
  try
    List.Text := HistText;
    cbInput.Items.AddStrings(List);
  finally
    List.Free;
  end;
end;

procedure TdlgGoToItem.SaveHistoryEntry(const Entry: string);
var
  Settings: TNotebookSettings;
  List: TStringList;
  ExistingIdx: Integer;
begin
  if Entry = '' then Exit;

  Settings := TNotebookSettings.Create;
  try
    List := TStringList.Create;
    try
      List.Text := Settings.GoToItemHistory;

      ExistingIdx := -1;
      for var I := 0 to List.Count - 1 do
        if SameText(List[I], Entry) then
        begin
          ExistingIdx := I;
          Break;
        end;
      if ExistingIdx >= 0 then
        List.Delete(ExistingIdx);

      List.Insert(0, Entry);

      while List.Count > HISTORY_MAX do
        List.Delete(List.Count - 1);

      Settings.GoToItemHistory := List.Text;
    finally
      List.Free;
    end;
  finally
    Settings.Free;
  end;
end;

end.
