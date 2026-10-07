object dlgItem: TdlgItem
  Left = 0
  Top = 0
  BorderStyle = bsDialog
  Caption = 'Item'
  ClientHeight = 320
  ClientWidth = 402
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -12
  Font.Name = 'Segoe UI'
  Font.Style = []
  Position = poMainFormCenter
  TextHeight = 15
  object RzPanel2: TRzPanel
    AlignWithMargins = True
    Left = 3
    Top = 276
    Width = 396
    Height = 41
    Align = alBottom
    BorderOuter = fsFlatRounded
    TabOrder = 0
    Color = clBtnFace
    object btnSave: TRzBitBtn
      Left = 318
      Top = 8
      ModalResult = 1
      Caption = 'Save'
      TabOrder = 0
    end
    object btnCancel: TRzBitBtn
      Left = 8
      Top = 8
      ModalResult = 2
      Caption = 'Cancel'
      TabOrder = 1
    end
  end
  object RzPanel1: TRzPanel
    AlignWithMargins = True
    Left = 3
    Top = 3
    Width = 396
    Height = 267
    Align = alClient
    BorderOuter = fsFlatRounded
    TabOrder = 1
    Color = clBtnFace
    object RzLabel1: TRzLabel
      Left = 8
      Top = 55
      Width = 24
      Height = 17
      Caption = 'Title'
      Font.Charset = DEFAULT_CHARSET
      Font.Color = clWindowText
      Font.Height = -13
      Font.Name = 'Segoe UI'
      Font.Style = []
      ParentFont = False
      Transparent = True
    end
    object RzLabel2: TRzLabel
      Left = 8
      Top = 98
      Width = 66
      Height = 17
      Caption = 'Description'
      Font.Charset = DEFAULT_CHARSET
      Font.Color = clWindowText
      Font.Height = -13
      Font.Name = 'Segoe UI'
      Font.Style = []
      ParentFont = False
      Transparent = True
    end
    object lblProperties: TRzLabel
      Left = 8
      Top = 145
      Width = 60
      Height = 17
      Caption = 'Properties'
      Font.Charset = DEFAULT_CHARSET
      Font.Color = clWindowText
      Font.Height = -13
      Font.Name = 'Segoe UI'
      Font.Style = []
      ParentFont = False
      Transparent = True
    end
    object rgItemType: TRzRadioGroup
      Left = 8
      Top = 5
      Width = 385
      Height = 45
      Caption = 'Item type'
      Color = clBtnFace
      Columns = 4
      TabOrder = 0
    end
    object edTitle: TRzEdit
      Left = 8
      Top = 75
      Width = 385
      Height = 23
      Text = ''
      TabOrder = 1
    end
    object edComment: TRzEdit
      Left = 8
      Top = 120
      Width = 385
      Height = 23
      Text = ''
      TabOrder = 2
    end
    object btnAddProp: TRzButton
      Left = 80
      Top = 145
      Width = 25
      Height = 20
      Caption = '+'
      TabOrder = 3
      OnClick = btnAddPropClick
    end
    object btnRemoveProp: TRzButton
      Left = 110
      Top = 145
      Width = 25
      Height = 20
      Caption = '-'
      TabOrder = 4
      OnClick = btnRemovePropClick
    end
    object vleProps: TValueListEditor
      Left = 8
      Top = 171
      Width = 385
      Height = 81
      KeyOptions = [keyEdit, keyAdd, keyDelete, keyUnique]
      TabOrder = 5
      ColWidths = (
        150
        229)
    end
  end
end
