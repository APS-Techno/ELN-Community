inherited edActionTypes: TedActionTypes
  Margins.Left = 2
  Margins.Top = 2
  Margins.Right = 2
  Margins.Bottom = 2
  Caption = 'Action Types'
  ClientHeight = 527
  ClientWidth = 445
  ParentFont = True
  ExplicitWidth = 461
  ExplicitHeight = 566
  TextHeight = 15
  inherited RzPanel1: TRzPanel
    Left = 2
    Top = 2
    Width = 441
    Height = 475
    Margins.Left = 2
    Margins.Top = 2
    Margins.Right = 2
    Margins.Bottom = 2
    ExplicitLeft = 2
    ExplicitTop = 2
    ExplicitWidth = 441
    ExplicitHeight = 386
    object lblTitle: TLabel [0]
      Left = 36
      Top = 9
      Width = 23
      Height = 15
      Margins.Left = 2
      Margins.Top = 2
      Margins.Right = 2
      Margins.Bottom = 2
      Caption = 'Title'
    end
    object lblKind: TLabel [1]
      Left = 36
      Top = 34
      Width = 24
      Height = 15
      Margins.Left = 2
      Margins.Top = 2
      Margins.Right = 2
      Margins.Bottom = 2
      Caption = 'Kind'
    end
    object lblItemType: TLabel [2]
      Left = 258
      Top = 36
      Width = 52
      Height = 15
      Margins.Left = 2
      Margins.Top = 2
      Margins.Right = 2
      Margins.Bottom = 2
      Caption = 'Item Type'
    end
    object lblEquipmentType: TLabel [3]
      Left = 225
      Top = 9
      Width = 86
      Height = 15
      Margins.Left = 2
      Margins.Top = 2
      Margins.Right = 2
      Margins.Bottom = 2
      Caption = 'Equipment Type'
    end
    object lblEquipment: TLabel [4]
      Left = 36
      Top = 59
      Width = 57
      Height = 15
      Margins.Left = 2
      Margins.Top = 2
      Margins.Right = 2
      Margins.Bottom = 2
      Caption = 'Equipment'
    end
    object lblDescription: TLabel [5]
      Left = 13
      Top = 84
      Width = 60
      Height = 15
      Margins.Left = 2
      Margins.Top = 2
      Margins.Right = 2
      Margins.Bottom = 2
      Caption = 'Description'
    end
    object lblFileTypes: TLabel [6]
      Left = 9
      Top = 109
      Width = 51
      Height = 15
      Margins.Left = 2
      Margins.Top = 2
      Margins.Right = 2
      Margins.Bottom = 2
      Caption = 'File Types'
    end
    inherited DBGrid1: TDBGrid
      Left = 4
      Top = 253
      Width = 433
      Height = 218
      Margins.Left = 2
      Margins.Top = 2
      Margins.Right = 2
      Margins.Bottom = 2
      Columns = <
        item
          Expanded = False
          FieldName = 'Title'
          Width = 66
          Visible = True
        end
        item
          Expanded = False
          FieldName = 'Kind'
          Width = 67
          Visible = True
        end
        item
          Expanded = False
          FieldName = 'ItemType'
          Title.Caption = 'Item Type'
          Width = 111
          Visible = True
        end
        item
          Expanded = False
          FieldName = 'Description'
          Width = 113
          Visible = True
        end
        item
          Expanded = False
          FieldName = 'CreatedDate'
          Title.Caption = 'Created Date'
          Width = 55
          Visible = True
        end>
    end
    inherited RzDBNavigator1: TRzDBNavigator
      Left = 180
      Top = 217
      Width = 250
      Height = 32
      Margins.Left = 2
      Margins.Top = 2
      Margins.Right = 2
      Margins.Bottom = 2
      Hints.Strings = ()
      ExplicitLeft = 180
      ExplicitTop = 217
      ExplicitWidth = 250
      ExplicitHeight = 32
    end
    object edTitle: TDBEdit
      Left = 80
      Top = 8
      Width = 135
      Height = 23
      Margins.Left = 2
      Margins.Top = 2
      Margins.Right = 2
      Margins.Bottom = 2
      DataField = 'Title'
      DataSource = DataSource
      TabOrder = 2
    end
    object cbKind: TComboBox
      Left = 80
      Top = 33
      Width = 135
      Height = 23
      Margins.Left = 2
      Margins.Top = 2
      Margins.Right = 2
      Margins.Bottom = 2
      Style = csDropDownList
      TabOrder = 3
      OnChange = cbKindChange
    end
    object cbItemType: TComboBox
      Left = 315
      Top = 33
      Width = 120
      Height = 23
      Margins.Left = 2
      Margins.Top = 2
      Margins.Right = 2
      Margins.Bottom = 2
      Style = csDropDownList
      TabOrder = 4
      OnChange = cbItemTypeChange
    end
    object cbEquipmentType: TComboBox
      Left = 315
      Top = 8
      Width = 120
      Height = 23
      Margins.Left = 2
      Margins.Top = 2
      Margins.Right = 2
      Margins.Bottom = 2
      Style = csDropDownList
      TabOrder = 5
      OnChange = cbEquipmentTypeChange
    end
    object cbEquipment: TComboBox
      Left = 120
      Top = 58
      Width = 315
      Height = 23
      Margins.Left = 2
      Margins.Top = 2
      Margins.Right = 2
      Margins.Bottom = 2
      Style = csDropDownList
      TabOrder = 6
      OnChange = cbEquipmentChange
    end
    object edDescription: TDBEdit
      Left = 80
      Top = 83
      Width = 355
      Height = 23
      Margins.Left = 2
      Margins.Top = 2
      Margins.Right = 2
      Margins.Bottom = 2
      DataField = 'Description'
      DataSource = DataSource
      TabOrder = 7
    end
    object clbFileTypes: TCheckListBox
      Left = 80
      Top = 109
      Width = 355
      Height = 100
      Margins.Left = 2
      Margins.Top = 2
      Margins.Right = 2
      Margins.Bottom = 2
      TabOrder = 8
      OnClickCheck = clbFileTypesClickCheck
    end
  end
  inherited RzPanel2: TRzPanel
    Left = 2
    Top = 481
    Width = 441
    Height = 44
    Margins.Left = 2
    Margins.Top = 2
    Margins.Right = 2
    Margins.Bottom = 2
    ExplicitLeft = 2
    ExplicitTop = 481
    ExplicitWidth = 441
    ExplicitHeight = 44
    DesignSize = (
      441
      44)
    inherited btnSave: TBitBtn
      Left = 347
      Top = 7
      Width = 77
      Height = 30
      Margins.Left = 2
      Margins.Top = 2
      Margins.Right = 2
      Margins.Bottom = 2
      Anchors = [akTop, akRight]
      ExplicitLeft = 347
      ExplicitTop = 7
      ExplicitWidth = 77
      ExplicitHeight = 30
    end
    inherited btnLoadCSV: TBitBtn
      Left = 9
      Top = 7
      Width = 85
      Height = 30
      Margins.Left = 1
      Margins.Top = 1
      Margins.Right = 1
      Margins.Bottom = 1
      ExplicitLeft = 9
      ExplicitTop = 7
      ExplicitWidth = 85
      ExplicitHeight = 30
    end
  end
  inherited DataSource: TDataSource
    Left = 496
    Top = 302
  end
end
