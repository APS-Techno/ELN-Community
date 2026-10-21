object dlgAction: TdlgAction
  Left = 0
  Top = 0
  BorderStyle = bsDialog
  Caption = 'Action'
  ClientHeight = 520
  ClientWidth = 560
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
    Top = 476
    Width = 554
    Height = 41
    Align = alBottom
    BorderOuter = fsFlatRounded
    TabOrder = 0
    Color = clBtnFace
    object btnSave: TRzBitBtn
      Left = 473
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
    Width = 554
    Height = 467
    Align = alClient
    BorderOuter = fsFlatRounded
    TabOrder = 1
    Color = clBtnFace
    object lblTitle: TRzLabel
      Left = 12
      Top = 15
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
    object edTitle: TRzEdit
      Left = 110
      Top = 12
      Width = 430
      Height = 23
      Text = ''
      TabOrder = 0
      OnChange = TextChanged
    end
    object lblItemType: TRzLabel
      Left = 12
      Top = 46
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
    object cbItemType: TRzComboBox
      Left = 110
      Top = 43
      Width = 260
      Height = 23
      Style = csDropDownList
      TabOrder = 1
      OnChange = cbItemTypeChange
    end
    object lblActionType: TRzLabel
      Left = 12
      Top = 77
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
    object cbActionType: TRzComboBox
      Left = 110
      Top = 74
      Width = 260
      Height = 23
      Style = csDropDownList
      TabOrder = 2
      OnChange = cbActionTypeChange
    end
    object btnAddActionType: TRzButton
      Left = 376
      Top = 74
      Width = 25
      Height = 23
      Hint = 'Add a new action type'
      Caption = '+'
      Enabled = False
      ParentShowHint = False
      ShowHint = True
      TabOrder = 3
      OnClick = btnAddActionTypeClick
    end
    object lblEquipment: TRzLabel
      Left = 12
      Top = 108
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
    object cbEquipment: TRzComboBox
      Left = 110
      Top = 105
      Width = 260
      Height = 23
      Style = csDropDownList
      TabOrder = 4
      OnChange = cbEquipmentChange
    end
    object btnAddEquipment: TRzButton
      Left = 376
      Top = 105
      Width = 25
      Height = 23
      Hint = 'Add new equipment'
      Caption = '+'
      Enabled = False
      ParentShowHint = False
      ShowHint = True
      TabOrder = 5
      OnClick = btnAddEquipmentClick
    end
    object lblDescription: TRzLabel
      Left = 12
      Top = 139
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
    object edComment: TRzEdit
      Left = 110
      Top = 136
      Width = 430
      Height = 23
      Text = ''
      TabOrder = 6
      OnChange = TextChanged
    end
    object pcDetails: TPageControl
      Left = 12
      Top = 172
      Width = 530
      Height = 288
      ActivePage = tsValues
      TabOrder = 7
      object tsValues: TTabSheet
        Caption = 'Values (0)'
        object pnlValueButtons: TRzPanel
          AlignWithMargins = True
          Left = 3
          Top = 3
          Width = 516
          Height = 34
          Align = alTop
          BorderOuter = fsNone
          TabOrder = 0
          object btnAddValue: TRzButton
            Left = 0
            Top = 4
            Width = 75
            Caption = 'Add'
            TabOrder = 0
            OnClick = btnAddValueClick
          end
          object btnEditValue: TRzButton
            Left = 81
            Top = 4
            Width = 75
            Caption = 'Edit'
            Enabled = False
            TabOrder = 1
            OnClick = btnEditValueClick
          end
          object btnDeleteValue: TRzButton
            Left = 162
            Top = 4
            Width = 75
            Caption = 'Delete'
            Enabled = False
            TabOrder = 2
            OnClick = btnDeleteValueClick
          end
        end
        object pnlValueSource: TRzPanel
          AlignWithMargins = True
          Left = 3
          Top = 219
          Width = 516
          Height = 34
          Align = alBottom
          BorderOuter = fsNone
          TabOrder = 1
          object lblValueSource: TLabel
            Left = 4
            Top = 9
            Width = 410
            Height = 15
            AutoSize = False
            EllipsisPosition = epEndEllipsis
            ShowHint = True
          end
          object btnGoToFile: TRzButton
            Left = 424
            Top = 4
            Width = 90
            Caption = 'Go to file'
            Enabled = False
            TabOrder = 0
            OnClick = btnGoToFileClick
          end
        end
        object lvValues: TListView
          AlignWithMargins = True
          Left = 3
          Top = 43
          Width = 516
          Height = 170
          Align = alClient
          Columns = <
            item
              Caption = 'Quantity'
              Width = 100
            end
            item
              Caption = 'Value'
              Width = 110
            end
            item
              Caption = 'Kind'
              Width = 80
            end
            item
              AutoSize = True
              Caption = 'Note'
              Width = 200
            end>
          HideSelection = False
          ReadOnly = True
          RowSelect = True
          TabOrder = 2
          ViewStyle = vsReport
          OnDblClick = lvValuesDblClick
          OnKeyDown = lvValuesKeyDown
          OnSelectItem = lvValuesSelectItem
        end
      end
      object tsProperties: TTabSheet
        Caption = 'Properties (0)'
        ImageIndex = 1
        object pnlPropButtons: TRzPanel
          AlignWithMargins = True
          Left = 3
          Top = 3
          Width = 516
          Height = 34
          Align = alTop
          BorderOuter = fsNone
          TabOrder = 0
          object btnAddProp: TRzButton
            Left = 0
            Top = 4
            Width = 75
            Caption = 'Add'
            TabOrder = 0
            OnClick = btnAddPropClick
          end
          object btnRemoveProp: TRzButton
            Left = 81
            Top = 4
            Width = 75
            Caption = 'Remove'
            TabOrder = 1
            OnClick = btnRemovePropClick
          end
        end
        object vleProps: TValueListEditor
          AlignWithMargins = True
          Left = 3
          Top = 43
          Width = 516
          Height = 210
          Align = alClient
          KeyOptions = [keyEdit, keyAdd, keyDelete, keyUnique]
          TabOrder = 1
          OnSetEditText = PropertiesChanged
          ColWidths = (
            150
            360)
        end
      end
    end
  end
end
