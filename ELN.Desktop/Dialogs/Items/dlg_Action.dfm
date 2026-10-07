object dlgAction: TdlgAction
  Left = 0
  Top = 0
  BorderStyle = bsDialog
  Caption = 'Action'
  ClientHeight = 578
  ClientWidth = 701
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
    Top = 534
    Width = 695
    Height = 41
    Align = alBottom
    BorderOuter = fsFlatRounded
    TabOrder = 0
    Color = clBtnFace
    object btnSave: TRzBitBtn
      Left = 614
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
    Width = 695
    Height = 525
    Align = alClient
    BorderOuter = fsFlatRounded
    TabOrder = 1
    Color = clBtnFace
    object RzLabel3: TRzLabel
      Left = 15
      Top = 61
      Width = 54
      Height = 17
      Caption = 'Item type'
      Font.Charset = DEFAULT_CHARSET
      Font.Color = clWindowText
      Font.Height = -13
      Font.Name = 'Segoe UI'
      Font.Style = []
      ParentFont = False
      Transparent = True
    end
    object RzLabel6: TRzLabel
      Left = 187
      Top = 11
      Width = 65
      Height = 17
      Caption = 'Action type'
      Font.Charset = DEFAULT_CHARSET
      Font.Color = clWindowText
      Font.Height = -13
      Font.Name = 'Segoe UI'
      Font.Style = []
      ParentFont = False
      Transparent = True
    end
    object RzLabel4: TRzLabel
      Left = 187
      Top = 183
      Width = 62
      Height = 17
      Caption = 'Equipment'
      Font.Charset = DEFAULT_CHARSET
      Font.Color = clWindowText
      Font.Height = -13
      Font.Name = 'Segoe UI'
      Font.Style = []
      ParentFont = False
      Transparent = True
    end
    object RzLabel1: TRzLabel
      Left = 8
      Top = 325
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
      Left = 344
      Top = 325
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
    object lblValues: TRzLabel
      Left = 399
      Top = 11
      Width = 37
      Height = 17
      Caption = 'Values'
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
      Top = 370
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
    object lbItemType: TRzListBox
      Left = 11
      Top = 85
      Width = 158
      Height = 234
      GroupFont.Charset = DEFAULT_CHARSET
      GroupFont.Color = clHighlight
      GroupFont.Height = -12
      GroupFont.Name = 'Segoe UI'
      GroupFont.Style = [fsBold]
      ItemHeight = 15
      TabOrder = 0
      OnClick = lbItemTypeClick
    end
    object lbActionType: TRzListBox
      Left = 175
      Top = 37
      Width = 218
      Height = 140
      GroupFont.Charset = DEFAULT_CHARSET
      GroupFont.Color = clHighlight
      GroupFont.Height = -12
      GroupFont.Name = 'Segoe UI'
      GroupFont.Style = [fsBold]
      ItemHeight = 15
      TabOrder = 1
      OnClick = lbActionTypeClick
    end
    object lbEquipment: TRzListBox
      Left = 175
      Top = 207
      Width = 218
      Height = 112
      GroupFont.Charset = DEFAULT_CHARSET
      GroupFont.Color = clHighlight
      GroupFont.Height = -12
      GroupFont.Name = 'Segoe UI'
      GroupFont.Style = [fsBold]
      ItemHeight = 15
      TabOrder = 2
      OnClick = lbEquipmentClick
    end
    object edTitle: TRzEdit
      Left = 8
      Top = 345
      Width = 313
      Height = 23
      Text = ''
      TabOrder = 3
    end
    object edComment: TRzEdit
      Left = 336
      Top = 345
      Width = 354
      Height = 23
      Text = ''
      TabOrder = 4
    end
    object rgLevel: TRzRadioGroup
      Left = 8
      Top = 8
      Width = 161
      Height = 49
      Caption = 'Level'
      Color = clBtnFace
      Columns = 3
      TabOrder = 5
    end
    object lbValues: TRzListBox
      Left = 400
      Top = 37
      Width = 289
      Height = 251
      GroupFont.Charset = DEFAULT_CHARSET
      GroupFont.Color = clHighlight
      GroupFont.Height = -12
      GroupFont.Name = 'Segoe UI'
      GroupFont.Style = [fsBold]
      ItemHeight = 15
      TabOrder = 6
    end
    object btnAddValue: TRzButton
      Left = 408
      Top = 294
      Width = 85
      Caption = 'Add Value'
      TabOrder = 7
      OnClick = btnAddValueClick
    end
    object btnEditValue: TRzButton
      Left = 512
      Top = 294
      Width = 85
      Caption = 'Edit Value'
      TabOrder = 8
      OnClick = btnEditValueClick
    end
    object btnDeleteValue: TRzButton
      Left = 605
      Top = 294
      Width = 85
      Caption = 'Delete Value'
      TabOrder = 9
      OnClick = btnDeleteValueClick
    end
    object btnAddActionType: TRzButton
      Left = 265
      Top = 10
      Width = 35
      Height = 20
      Caption = 'Add'
      Enabled = False
      TabOrder = 10
      OnClick = btnAddActionTypeClick
    end
    object btnAddEquipment: TRzButton
      Left = 260
      Top = 181
      Width = 35
      Height = 20
      Caption = 'Add'
      Enabled = False
      TabOrder = 11
      OnClick = btnAddEquipmentClick
    end
    object btnAddProp: TRzButton
      Left = 80
      Top = 370
      Width = 25
      Height = 20
      Caption = '+'
      TabOrder = 12
      OnClick = btnAddPropClick
    end
    object btnRemoveProp: TRzButton
      Left = 110
      Top = 370
      Width = 25
      Height = 20
      Caption = '-'
      TabOrder = 13
      OnClick = btnRemovePropClick
    end
    object vleProps: TValueListEditor
      Left = 8
      Top = 396
      Width = 681
      Height = 117
      KeyOptions = [keyEdit, keyAdd, keyDelete, keyUnique]
      TabOrder = 14
      ColWidths = (
        150
        525)
    end
  end
end
