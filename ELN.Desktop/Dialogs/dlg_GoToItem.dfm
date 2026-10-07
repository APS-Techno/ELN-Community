object dlgGoToItem: TdlgGoToItem
  Left = 0
  Top = 0
  BorderIcons = [biSystemMenu]
  BorderStyle = bsDialog
  Caption = 'Go to item...'
  ClientHeight = 130
  ClientWidth = 380
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -12
  Font.Name = 'Segoe UI'
  Font.Style = []
  Position = poOwnerFormCenter
  OnShow = FormShow
  TextHeight = 15
  object lblPrompt: TLabel
    Left = 12
    Top = 12
    Width = 356
    Height = 15
    Caption = 'Enter an item ID or eln:// URL:'
  end
  object cbInput: TComboBox
    Left = 12
    Top = 33
    Width = 356
    Height = 23
    TabOrder = 0
  end
  object lblError: TLabel
    Left = 12
    Top = 60
    Width = 356
    Height = 15
    Caption = ' '
    Font.Charset = DEFAULT_CHARSET
    Font.Color = clRed
    Font.Height = -12
    Font.Name = 'Segoe UI'
    Font.Style = []
    ParentFont = False
  end
  object btnOK: TButton
    Left = 200
    Top = 92
    Width = 80
    Height = 25
    Caption = 'OK'
    Default = True
    ModalResult = 0
    TabOrder = 1
    OnClick = btnOKClick
  end
  object btnCancel: TButton
    Left = 288
    Top = 92
    Width = 80
    Height = 25
    Cancel = True
    Caption = 'Cancel'
    ModalResult = 2
    TabOrder = 2
  end
end
