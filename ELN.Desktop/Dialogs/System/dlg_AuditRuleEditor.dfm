object dlgAuditRuleEditor: TdlgAuditRuleEditor
  Left = 0
  Top = 0
  BorderStyle = bsSizeable
  Caption = 'Audit Rules'
  ClientHeight = 550
  ClientWidth = 900
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -11
  Font.Name = 'Tahoma'
  Font.Style = []
  Position = poMainFormCenter
  TextHeight = 13
  object pnlLeft: TRzPanel
    Left = 0
    Top = 0
    Width = 250
    Height = 550
    Align = alLeft
    BorderOuter = fsFlatRounded
    TabOrder = 0
    object lbRules: TListBox
      AlignWithMargins = True
      Left = 4
      Top = 4
      Width = 240
      Height = 504
      Margins.Left = 4
      Margins.Top = 4
      Margins.Right = 4
      Margins.Bottom = 4
      Align = alClient
      ItemHeight = 13
      TabOrder = 0
      OnClick = DoRuleSelect
    end
    object pnlLeftButtons: TRzPanel
      Left = 2
      Top = 510
      Width = 246
      Height = 38
      Align = alBottom
      BorderOuter = fsNone
      TabOrder = 1
      object btnAdd: TRzButton
        Left = 4
        Top = 6
        Width = 75
        Height = 25
        Caption = 'Add'
        TabOrder = 0
        OnClick = DoAddRule
      end
      object btnDelete: TRzButton
        Left = 84
        Top = 6
        Width = 75
        Height = 25
        Caption = 'Delete'
        TabOrder = 1
        OnClick = DoDeleteRule
      end
    end
  end
  object pnlRight: TRzPanel
    Left = 250
    Top = 0
    Width = 650
    Height = 550
    Align = alClient
    BorderOuter = fsNone
    TabOrder = 1
    object pnlRightButtons: TRzPanel
      Left = 0
      Top = 510
      Width = 650
      Height = 40
      Align = alBottom
      BorderOuter = fsNone
      TabOrder = 1
      object btnSave: TRzButton
        Left = 8
        Top = 6
        Width = 90
        Height = 28
        Caption = 'Save'
        TabOrder = 0
        OnClick = DoSaveRule
      end
    end
    object pnlContent: TRzPanel
      AlignWithMargins = True
      Left = 8
      Top = 4
      Width = 634
      Height = 502
      Margins.Left = 8
      Margins.Top = 4
      Margins.Right = 8
      Margins.Bottom = 4
      Align = alClient
      BorderOuter = fsNone
      TabOrder = 0
      object lblTitle: TRzLabel
        Left = 0
        Top = 4
        Width = 20
        Height = 13
        Caption = 'Title'
      end
      object lblActionType: TRzLabel
        Left = 0
        Top = 52
        Width = 57
        Height = 13
        Caption = 'Action Type'
      end
      object lblEquipment: TRzLabel
        Left = 260
        Top = 52
        Width = 51
        Height = 13
        Caption = 'Equipment'
      end
      object lblSeverity: TRzLabel
        Left = 0
        Top = 100
        Width = 38
        Height = 13
        Caption = 'Severity'
      end
      object lblDescription: TRzLabel
        Left = 0
        Top = 148
        Width = 53
        Height = 13
        Caption = 'Description'
      end
      object lblFileTypes: TRzLabel
        Left = 0
        Top = 234
        Width = 91
        Height = 13
        Caption = 'Required File Types'
      end
      object lblValueTypes: TRzLabel
        Left = 0
        Top = 376
        Width = 99
        Height = 13
        Caption = 'Required Value Types'
      end
      object edTitle: TRzEdit
        Left = 0
        Top = 22
        Width = 620
        Height = 21
        Anchors = [akLeft, akTop, akRight]
        TabOrder = 0
      end
      object cbActionType: TComboBox
        Left = 0
        Top = 70
        Width = 250
        Height = 21
        Style = csDropDownList
        TabOrder = 1
      end
      object cbEquipment: TComboBox
        Left = 260
        Top = 70
        Width = 250
        Height = 21
        Style = csDropDownList
        TabOrder = 2
      end
      object cbSeverity: TComboBox
        Left = 0
        Top = 118
        Width = 150
        Height = 21
        Style = csDropDownList
        TabOrder = 3
      end
      object chkActive: TCheckBox
        Left = 260
        Top = 120
        Width = 80
        Height = 17
        Caption = 'Active'
        TabOrder = 4
      end
      object memDescription: TMemo
        Left = 0
        Top = 166
        Width = 620
        Height = 60
        Anchors = [akLeft, akTop, akRight]
        ScrollBars = ssVertical
        TabOrder = 5
      end
      object clbFileTypes: TCheckListBox
        Left = 0
        Top = 252
        Width = 620
        Height = 115
        Anchors = [akLeft, akTop, akRight, akBottom]
        ItemHeight = 13
        TabOrder = 6
      end
      object clbValueTypes: TCheckListBox
        Left = 0
        Top = 394
        Width = 620
        Height = 105
        Anchors = [akLeft, akRight, akBottom]
        ItemHeight = 13
        TabOrder = 7
      end
    end
  end
end
