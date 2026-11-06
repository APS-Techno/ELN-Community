object dlgSeriesPlanEntry: TdlgSeriesPlanEntry
  Left = 0
  Top = 0
  BorderStyle = bsDialog
  Caption = 'Plan entry'
  ClientHeight = 300
  ClientWidth = 520
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -12
  Font.Name = 'Segoe UI'
  Font.Style = []
  Position = poOwnerFormCenter
  TextHeight = 15
  object lblCategory: TLabel
    Left = 8
    Top = 8
    Width = 48
    Height = 15
    Caption = 'Category'
  end
  object lbCategory: TListBox
    Left = 8
    Top = 28
    Width = 220
    Height = 85
    ItemHeight = 15
    TabOrder = 0
    OnClick = lbCategoryClick
  end
  object lblType: TLabel
    Left = 8
    Top = 121
    Width = 55
    Height = 15
    Caption = 'Value type'
  end
  object lbType: TListBox
    Left = 8
    Top = 141
    Width = 220
    Height = 110
    ItemHeight = 15
    TabOrder = 1
    OnClick = lbTypeClick
  end
  object lblEntryLabel: TLabel
    Left = 244
    Top = 8
    Width = 92
    Height = 15
    Caption = 'Label (optional)'
  end
  object edEntryLabel: TEdit
    Left = 244
    Top = 28
    Width = 268
    Height = 23
    MaxLength = 100
    TabOrder = 2
  end
  object lblFirst: TLabel
    Left = 244
    Top = 59
    Width = 24
    Height = 15
    Caption = 'First'
  end
  object edFirst: TEdit
    Left = 244
    Top = 79
    Width = 268
    Height = 23
    TabOrder = 3
    OnChange = NumberChange
  end
  object lblSecond: TLabel
    Left = 244
    Top = 110
    Width = 39
    Height = 15
    Caption = 'Second'
  end
  object edSecond: TEdit
    Left = 244
    Top = 130
    Width = 268
    Height = 23
    TabOrder = 4
    OnChange = NumberChange
  end
  object lblConversion: TLabel
    Left = 244
    Top = 157
    Width = 268
    Height = 30
    AutoSize = False
    Font.Charset = DEFAULT_CHARSET
    Font.Color = clGrayText
    Font.Height = -12
    Font.Name = 'Segoe UI'
    Font.Style = [fsItalic]
    ParentFont = False
    WordWrap = True
  end
  object lblHint: TLabel
    Left = 244
    Top = 191
    Width = 268
    Height = 62
    AutoSize = False
    Font.Charset = DEFAULT_CHARSET
    Font.Color = clGrayText
    Font.Height = -12
    Font.Name = 'Segoe UI'
    Font.Style = []
    ParentFont = False
    WordWrap = True
  end
  object pnlButtons: TRzPanel
    AlignWithMargins = True
    Left = 3
    Top = 257
    Width = 514
    Height = 40
    Align = alBottom
    BorderOuter = fsFlatRounded
    TabOrder = 5
    object btnOK: TButton
      Left = 322
      Top = 6
      Width = 90
      Height = 27
      Caption = 'OK'
      Default = True
      TabOrder = 0
      OnClick = btnOKClick
    end
    object btnCancel: TButton
      Left = 418
      Top = 6
      Width = 90
      Height = 27
      Cancel = True
      Caption = 'Cancel'
      ModalResult = 2
      TabOrder = 1
    end
  end
end
