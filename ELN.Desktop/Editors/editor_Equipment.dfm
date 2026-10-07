inherited edEquipment: TedEquipment
  Margins.Left = 2
  Margins.Top = 2
  Margins.Right = 2
  Margins.Bottom = 2
  Caption = 'Equipment'
  ClientHeight = 491
  ClientWidth = 417
  ParentFont = True
  ExplicitWidth = 433
  ExplicitHeight = 530
  TextHeight = 15
  inherited RzPanel1: TRzPanel
    Left = 2
    Top = 2
    Width = 413
    Height = 443
    Margins.Left = 2
    Margins.Top = 2
    Margins.Right = 2
    Margins.Bottom = 2
    ExplicitLeft = 2
    ExplicitTop = 2
    ExplicitWidth = 413
    ExplicitHeight = 338
    object lblModel: TLabel [0]
      Left = 27
      Top = 9
      Width = 34
      Height = 15
      Margins.Left = 2
      Margins.Top = 2
      Margins.Right = 2
      Margins.Bottom = 2
      Caption = 'Model'
    end
    object lblManufacturer: TLabel [1]
      Left = 22
      Top = 41
      Width = 72
      Height = 15
      Margins.Left = 2
      Margins.Top = 2
      Margins.Right = 2
      Margins.Bottom = 2
      Caption = 'Manufacturer'
    end
    object lblLocation: TLabel [2]
      Left = 49
      Top = 72
      Width = 46
      Height = 15
      Margins.Left = 2
      Margins.Top = 2
      Margins.Right = 2
      Margins.Bottom = 2
      Caption = 'Location'
    end
    object lblType: TLabel [3]
      Left = 275
      Top = 9
      Width = 25
      Height = 15
      Margins.Left = 2
      Margins.Top = 2
      Margins.Right = 2
      Margins.Bottom = 2
      Caption = 'Type'
    end
    object lblBookingUrl: TLabel [4]
      Left = 26
      Top = 135
      Width = 68
      Height = 15
      Margins.Left = 2
      Margins.Top = 2
      Margins.Right = 2
      Margins.Bottom = 2
      Caption = 'Booking URL'
    end
    object lblInfoUrl: TLabel [5]
      Left = 49
      Top = 167
      Width = 45
      Height = 15
      Margins.Left = 2
      Margins.Top = 2
      Margins.Right = 2
      Margins.Bottom = 2
      Caption = 'Info URL'
    end
    object lblDescription: TLabel [6]
      Left = 33
      Top = 104
      Width = 60
      Height = 15
      Margins.Left = 2
      Margins.Top = 2
      Margins.Right = 2
      Margins.Bottom = 2
      Caption = 'Description'
    end
    inherited DBGrid1: TDBGrid
      Left = 4
      Top = 221
      Width = 405
      Height = 218
      Margins.Left = 2
      Margins.Top = 2
      Margins.Right = 2
      Margins.Bottom = 2
      Columns = <
        item
          Expanded = False
          FieldName = 'Model'
          Width = 87
          Visible = True
        end
        item
          Expanded = False
          FieldName = 'Manufacturer'
          Width = 86
          Visible = True
        end
        item
          Expanded = False
          FieldName = 'Location'
          Width = 98
          Visible = True
        end
        item
          Expanded = False
          FieldName = 'Description'
          Width = 75
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
      Left = 192
      Top = 192
      Width = 210
      Margins.Left = 2
      Margins.Top = 2
      Margins.Right = 2
      Margins.Bottom = 2
      Hints.Strings = ()
      ExplicitLeft = 192
      ExplicitTop = 192
      ExplicitWidth = 210
    end
    object edModel: TDBEdit
      Left = 76
      Top = 8
      Width = 189
      Height = 23
      Margins.Left = 2
      Margins.Top = 2
      Margins.Right = 2
      Margins.Bottom = 2
      DataField = 'Model'
      DataSource = DataSource
      TabOrder = 2
    end
    object edManufacturer: TDBEdit
      Left = 108
      Top = 39
      Width = 296
      Height = 23
      Margins.Left = 2
      Margins.Top = 2
      Margins.Right = 2
      Margins.Bottom = 2
      DataField = 'Manufacturer'
      DataSource = DataSource
      TabOrder = 3
    end
    object edLocation: TDBEdit
      Left = 108
      Top = 71
      Width = 296
      Height = 23
      Margins.Left = 2
      Margins.Top = 2
      Margins.Right = 2
      Margins.Bottom = 2
      DataField = 'Location'
      DataSource = DataSource
      TabOrder = 4
    end
    object edBookingUrl: TDBEdit
      Left = 108
      Top = 134
      Width = 296
      Height = 23
      Margins.Left = 2
      Margins.Top = 2
      Margins.Right = 2
      Margins.Bottom = 2
      DataField = 'BookingUrl'
      DataSource = DataSource
      TabOrder = 5
    end
    object edInfoUrl: TDBEdit
      Left = 108
      Top = 165
      Width = 296
      Height = 23
      Margins.Left = 2
      Margins.Top = 2
      Margins.Right = 2
      Margins.Bottom = 2
      DataField = 'InfoUrl'
      DataSource = DataSource
      TabOrder = 6
    end
    object edDescription: TDBEdit
      Left = 108
      Top = 102
      Width = 296
      Height = 23
      Margins.Left = 2
      Margins.Top = 2
      Margins.Right = 2
      Margins.Bottom = 2
      DataField = 'Description'
      DataSource = DataSource
      TabOrder = 7
    end
    object cbEquipmentType: TComboBox
      Left = 319
      Top = 8
      Width = 85
      Height = 23
      Margins.Left = 2
      Margins.Top = 2
      Margins.Right = 2
      Margins.Bottom = 2
      Style = csDropDownList
      TabOrder = 8
      OnChange = cbEquipmentTypeChange
    end
  end
  inherited RzPanel2: TRzPanel
    Left = 2
    Top = 449
    Width = 413
    Height = 40
    Margins.Left = 2
    Margins.Top = 2
    Margins.Right = 2
    Margins.Bottom = 2
    ExplicitLeft = 2
    ExplicitTop = 344
    ExplicitWidth = 413
    ExplicitHeight = 40
    DesignSize = (
      413
      40)
    inherited btnSave: TBitBtn
      Left = 330
      Top = 9
      Width = 74
      Margins.Left = 2
      Margins.Top = 2
      Margins.Right = 2
      Margins.Bottom = 2
      Anchors = [akTop, akRight]
      ExplicitLeft = 330
      ExplicitTop = 9
      ExplicitWidth = 74
    end
    inherited btnLoadCSV: TBitBtn
      Left = 4
      Top = 9
      Width = 77
      Margins.Left = 1
      Margins.Top = 1
      Margins.Right = 1
      Margins.Bottom = 1
      ExplicitLeft = 4
      ExplicitTop = 9
      ExplicitWidth = 77
    end
  end
  inherited DataSource: TDataSource
    Left = 539
    Top = 376
  end
end
