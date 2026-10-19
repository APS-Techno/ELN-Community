object ReaderValueMappingsEditor: TReaderValueMappingsEditor
  Left = 0
  Top = 0
  Caption = 'Reader mappings'
  ClientHeight = 520
  ClientWidth = 920
  Constraints.MinHeight = 559
  Constraints.MinWidth = 936
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -13
  Font.Name = 'Segoe UI'
  Font.Style = []
  Position = poOwnerFormCenter
  PixelsPerInch = 96
  TextHeight = 17
  object lbMappings: TListBox
    Left = 16
    Top = 16
    Width = 888
    Height = 240
    Anchors = [akLeft, akTop, akRight, akBottom]
    ItemHeight = 17
    TabOrder = 0
    OnClick = MappingClick
  end
  object lblReader: TLabel
    Left = 16
    Top = 272
    Width = 56
    Height = 17
    Anchors = [akLeft, akBottom]
    Caption = 'Reader ID'
  end
  object edReader: TEdit
    Left = 16
    Top = 292
    Width = 264
    Height = 25
    Anchors = [akLeft, akBottom]
    MaxLength = 100
    TabOrder = 1
  end
  object lblKey: TLabel
    Left = 296
    Top = 272
    Width = 109
    Height = 17
    Anchors = [akLeft, akBottom]
    Caption = 'Key name or pattern'
  end
  object edKey: TEdit
    Left = 296
    Top = 292
    Width = 432
    Height = 25
    Anchors = [akLeft, akRight, akBottom]
    MaxLength = 255
    TabOrder = 2
  end
  object lblUnits: TLabel
    Left = 744
    Top = 272
    Width = 128
    Height = 17
    Anchors = [akRight, akBottom]
    Caption = 'Expected reader unit'
  end
  object edUnits: TEdit
    Left = 744
    Top = 292
    Width = 160
    Height = 25
    Anchors = [akRight, akBottom]
    MaxLength = 100
    TabOrder = 3
  end
  object lblType: TLabel
    Left = 16
    Top = 332
    Width = 96
    Height = 17
    Anchors = [akLeft, akBottom]
    Caption = 'Target value type'
  end
  object cbType: TComboBox
    Left = 16
    Top = 352
    Width = 368
    Height = 25
    Anchors = [akLeft, akBottom]
    Style = csDropDownList
    TabOrder = 4
  end
  object lblFactor: TLabel
    Left = 400
    Top = 332
    Width = 104
    Height = 17
    Anchors = [akLeft, akBottom]
    Caption = 'Conversion factor'
  end
  object edFactor: TEdit
    Left = 400
    Top = 352
    Width = 184
    Height = 25
    Anchors = [akLeft, akBottom]
    TabOrder = 5
    Text = '1'
  end
  object lblLabel: TLabel
    Left = 600
    Top = 332
    Width = 102
    Height = 17
    Anchors = [akLeft, akBottom]
    Caption = 'Description label'
  end
  object edLabel: TEdit
    Left = 600
    Top = 352
    Width = 304
    Height = 25
    Anchors = [akLeft, akRight, akBottom]
    MaxLength = 255
    TabOrder = 6
  end
  object lblPattern: TLabel
    Left = 16
    Top = 396
    Width = 888
    Height = 51
    Anchors = [akLeft, akRight, akBottom]
    AutoSize = False
    Caption = 
      'Patterns: <Material> captures a material and becomes the label; <' +
      'Any> matches any text. Examples: <Material> Thickness, Layer <Mat' +
      'erial>.<Any>. Exact keys win, then the pattern with the most fixe' +
      'd text. Units must match exactly. The converted number is the rea' +
      'der number multiplied by the factor.'
    WordWrap = True
  end
  object btnNew: TButton
    Left = 16
    Top = 464
    Width = 112
    Height = 32
    Anchors = [akLeft, akBottom]
    Caption = 'New mapping'
    TabOrder = 7
    OnClick = NewClick
  end
  object btnSave: TButton
    Left = 144
    Top = 464
    Width = 112
    Height = 32
    Anchors = [akLeft, akBottom]
    Caption = 'Save mapping'
    TabOrder = 8
    OnClick = SaveClick
  end
  object btnDelete: TButton
    Left = 272
    Top = 464
    Width = 112
    Height = 32
    Anchors = [akLeft, akBottom]
    Caption = 'Delete mapping'
    TabOrder = 9
    OnClick = DeleteClick
  end
  object btnClose: TButton
    Left = 792
    Top = 464
    Width = 112
    Height = 32
    Anchors = [akRight, akBottom]
    Caption = 'Close'
    Cancel = True
    ModalResult = 2
    TabOrder = 10
  end
end
