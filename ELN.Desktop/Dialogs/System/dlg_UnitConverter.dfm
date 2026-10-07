object dlgUnitConverter: TdlgUnitConverter
  Left = 0
  Top = 0
  BorderStyle = bsDialog
  Caption = 'Unit Converter'
  ClientHeight = 130
  ClientWidth = 570
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -12
  Font.Name = 'Segoe UI'
  Font.Style = []
  Position = poMainFormCenter
  TextHeight = 15
  object lblCategory: TRzLabel
    Left = 16
    Top = 20
    Width = 55
    Height = 15
    Caption = 'Category:'
  end
  object lblEquals: TRzLabel
    Left = 275
    Top = 56
    Width = 20
    Height = 15
    Alignment = taCenter
    Caption = '='
  end
  object cmbCategory: TComboBox
    Left = 80
    Top = 16
    Width = 200
    Height = 23
    Style = csDropDownList
    TabOrder = 0
    OnChange = cmbCategoryChange
  end
  object edFrom: TRzEdit
    Left = 16
    Top = 52
    Width = 137
    Height = 23
    TabOrder = 1
    OnChange = edFromChange
  end
  object cmbFrom: TComboBox
    Left = 159
    Top = 52
    Width = 110
    Height = 23
    Style = csDropDownList
    TabOrder = 2
    OnChange = edFromChange
  end
  object edTo: TRzEdit
    Left = 301
    Top = 52
    Width = 137
    Height = 23
    TabOrder = 3
    OnChange = edToChange
  end
  object cmbTo: TComboBox
    Left = 444
    Top = 52
    Width = 110
    Height = 23
    Style = csDropDownList
    TabOrder = 4
    OnChange = edToChange
  end
  object pnlBottom: TRzPanel
    Left = 0
    Top = 86
    Width = 570
    Height = 44
    Align = alBottom
    BorderOuter = fsFlatRounded
    TabOrder = 5
    object btnApply: TRzButton
      Left = 376
      Top = 9
      Width = 85
      Height = 25
      Caption = 'Apply'
      Default = True
      Anchors = [akTop, akRight]
      TabOrder = 0
      Visible = False
      OnClick = btnApplyClick
    end
    object btnClose: TRzButton
      Left = 469
      Top = 9
      Width = 85
      Height = 25
      Cancel = True
      Caption = 'Close'
      ModalResult = 8
      Anchors = [akTop, akRight]
      TabOrder = 1
    end
  end
end
