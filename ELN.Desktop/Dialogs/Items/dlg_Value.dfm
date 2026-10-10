object dlgValue: TdlgValue
  Left = 0
  Top = 0
  BorderStyle = bsDialog
  Caption = 'Value'
  ClientHeight = 300
  ClientWidth = 540
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -12
  Font.Name = 'Segoe UI'
  Font.Style = []
  Position = poMainFormCenter
  OnCloseQuery = FormCloseQuery
  TextHeight = 15
  object RzPanel2: TRzPanel
    AlignWithMargins = True
    Left = 3
    Top = 256
    Width = 534
    Height = 41
    Align = alBottom
    BorderOuter = fsFlatRounded
    TabOrder = 0
    Color = clBtnFace
    object btnSave: TRzBitBtn
      Left = 457
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
    Width = 534
    Height = 247
    Align = alClient
    BorderOuter = fsFlatRounded
    TabOrder = 1
    Color = clBtnFace
    object lblCategory: TRzLabel
      Left = 8
      Top = 8
      Width = 52
      Height = 17
      Caption = 'Category'
      Font.Charset = DEFAULT_CHARSET
      Font.Color = clWindowText
      Font.Height = -13
      Font.Name = 'Segoe UI'
      Font.Style = []
      ParentFont = False
      Transparent = True
    end
    object lblValueType: TRzLabel
      Left = 8
      Top = 117
      Width = 60
      Height = 17
      Caption = 'Value type'
      Font.Charset = DEFAULT_CHARSET
      Font.Color = clWindowText
      Font.Height = -13
      Font.Name = 'Segoe UI'
      Font.Style = []
      ParentFont = False
      Transparent = True
    end
    object lblRecType: TRzLabel
      Left = 228
      Top = 8
      Width = 71
      Height = 17
      Caption = 'Record type'
      Font.Charset = DEFAULT_CHARSET
      Font.Color = clWindowText
      Font.Height = -13
      Font.Name = 'Segoe UI'
      Font.Style = []
      ParentFont = False
      Transparent = True
    end
    object lblValue: TRzLabel
      Left = 228
      Top = 88
      Width = 31
      Height = 17
      Caption = 'Value'
      Font.Charset = DEFAULT_CHARSET
      Font.Color = clWindowText
      Font.Height = -13
      Font.Name = 'Segoe UI'
      Font.Style = []
      ParentFont = False
      Transparent = True
    end
    object lblTolerance: TRzLabel
      Left = 414
      Top = 88
      Width = 56
      Height = 17
      Caption = 'Tolerance'
      Font.Charset = DEFAULT_CHARSET
      Font.Color = clWindowText
      Font.Height = -13
      Font.Name = 'Segoe UI'
      Font.Style = []
      ParentFont = False
      Transparent = True
    end
    object lblBaseValue: TRzLabel
      Left = 228
      Top = 134
      Width = 298
      Height = 15
      AutoSize = False
      Caption = ''
      Font.Charset = DEFAULT_CHARSET
      Font.Color = clGray
      Font.Height = -12
      Font.Name = 'Segoe UI'
      Font.Style = [fsItalic]
      ParentFont = False
      Transparent = True
    end
    object lblDescription: TRzLabel
      Left = 228
      Top = 156
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
    object lbCategory: TListBox
      Left = 8
      Top = 28
      Width = 210
      Height = 85
      Font.Charset = DEFAULT_CHARSET
      Font.Color = clWindowText
      Font.Height = -13
      Font.Name = 'Segoe UI'
      Font.Style = []
      ParentFont = False
      StyleElements = [seClient, seBorder]
      TabOrder = 0
      OnClick = lbCategoryClick
    end
    object lbValueType: TListBox
      Left = 8
      Top = 137
      Width = 210
      Height = 102
      Font.Charset = DEFAULT_CHARSET
      Font.Color = clWindowText
      Font.Height = -13
      Font.Name = 'Segoe UI'
      Font.Style = []
      ParentFont = False
      StyleElements = [seClient, seBorder]
      TabOrder = 1
      OnClick = lbValueTypeClick
    end
    object rgRecType: TRzRadioGroup
      Left = 228
      Top = 28
      Width = 298
      Height = 51
      Caption = ''
      Color = clBtnFace
      Columns = 2
      ItemIndex = 0
      Items.Strings = (
        'Condition'
        'Result')
      TabOrder = 2
    end
    object edValue: TRzEdit
      Left = 228
      Top = 108
      Width = 92
      Height = 23
      Text = ''
      TabOrder = 3
      OnChange = edValueChange
    end
    object btnConvert: TRzButton
      Left = 324
      Top = 108
      Width = 80
      Height = 23
      Caption = 'Convert...'
      TabOrder = 6
      OnClick = btnConvertClick
    end
    object edTolerance: TRzEdit
      Left = 414
      Top = 108
      Width = 112
      Height = 23
      Text = ''
      TabOrder = 4
    end
    object edDescription: TRzEdit
      Left = 228
      Top = 176
      Width = 298
      Height = 23
      Text = ''
      TabOrder = 5
    end
  end
end
