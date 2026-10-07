object dlgLinkRelation: TdlgLinkRelation
  Left = 0
  Top = 0
  BorderStyle = bsDialog
  Caption = 'Link'
  ClientHeight = 244
  ClientWidth = 458
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -12
  Font.Name = 'Segoe UI'
  Font.Style = []
  Position = poMainFormCenter
  PixelsPerInch = 96
  TextHeight = 15
  object lblRelation: TLabel
    Left = 12
    Top = 15
    Width = 74
    Height = 15
    Caption = 'Relationship:'
  end
  object lblSentence: TLabel
    Left = 12
    Top = 46
    Width = 434
    Height = 34
    AutoSize = False
    Caption = ' '
    Font.Charset = DEFAULT_CHARSET
    Font.Color = clGrayText
    Font.Height = -12
    Font.Name = 'Segoe UI'
    Font.Style = [fsItalic]
    ParentFont = False
    WordWrap = True
  end
  object lblNotes: TLabel
    Left = 12
    Top = 92
    Width = 38
    Height = 15
    Caption = 'Notes:'
  end
  object cbRelation: TComboBox
    Left = 100
    Top = 12
    Width = 346
    Height = 23
    Style = csDropDownList
    TabOrder = 0
    OnChange = cbRelationChange
  end
  object edNotes: TMemo
    Left = 100
    Top = 89
    Width = 346
    Height = 106
    ScrollBars = ssVertical
    TabOrder = 1
  end
  object btnOK: TButton
    Left = 286
    Top = 208
    Width = 75
    Height = 25
    Caption = 'Link'
    Default = True
    Enabled = False
    ModalResult = 1
    TabOrder = 2
  end
  object btnCancel: TButton
    Left = 371
    Top = 208
    Width = 75
    Height = 25
    Cancel = True
    Caption = 'Cancel'
    ModalResult = 2
    TabOrder = 3
  end
end
