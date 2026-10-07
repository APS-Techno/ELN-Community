object frCheckboxFieldCard: TfrCheckboxFieldCard
  Left = 0
  Top = 0
  Width = 320
  Height = 240
  Align = alClient
  TabOrder = 0
  object lblName: TRzLabel
    Left = 8
    Top = 8
    Width = 63
    Height = 15
    Caption = 'Field Name:'
  end
  object lblLabel: TRzLabel
    Left = 8
    Top = 48
    Width = 59
    Height = 15
    Caption = 'Field Label:'
  end
  object lblType: TRzLabel
    Left = 168
    Top = 8
    Width = 56
    Height = 15
    Caption = 'Field Type:'
  end
  object lblAutoFill: TRzLabel
    Left = 8
    Top = 88
    Width = 44
    Height = 15
    Caption = 'AutoFill:'
  end
  object lblFlex: TRzLabel
    Left = 220
    Top = 88
    Width = 23
    Height = 15
    Caption = 'Flex:'
  end
  object edtName: TRzEdit
    Left = 8
    Top = 24
    Width = 152
    Height = 23
    Text = ''
    TabOrder = 0
    OnChange = ControlChange
  end
  object edtLabel: TRzEdit
    Left = 8
    Top = 64
    Width = 300
    Height = 23
    Text = ''
    TabOrder = 2
    OnChange = ControlChange
  end
  object cmbType: TComboBox
    Left = 168
    Top = 24
    Width = 140
    Height = 23
    Style = csDropDownList
    TabOrder = 1
    OnChange = cmbTypeChange
  end
  object cmbAutoFill: TComboBox
    Left = 8
    Top = 104
    Width = 200
    Height = 23
    TabOrder = 3
    OnChange = ControlChange
  end
  object spnFlex: TSpinEdit
    Left = 220
    Top = 104
    Width = 60
    Height = 24
    MaxValue = 4
    MinValue = 1
    TabOrder = 4
    Value = 1
    OnChange = ControlChange
  end
end
